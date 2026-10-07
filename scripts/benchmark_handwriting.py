"""Сравнивает локальные варианты подготовки строк на размеченных снимках.

Запуск: python -m scripts.benchmark_handwriting test_lecture3.jpg
Модели читаются только из локального кэша, аудио не генерируется.
"""

import argparse
import json
import hashlib
import time
from datetime import datetime, timezone
from pathlib import Path

import cv2
import numpy as np
import torch
import transformers
from PIL import Image

from server.app.services.image_preprocessing import ImagePreprocessor
from server.app.services.text_recognition import TextRecognizer
from server.app.services.semantic_chunker import SemanticChunker
from scripts.ocr_evaluation import score_text, score_line_spans, score_line_boxes, peak_rss_mib


ROOT = Path(__file__).resolve().parents[1]
REFERENCES = ROOT / "tests" / "fixtures" / "handwriting_ground_truth.json"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("images", nargs="*", help="Имена файлов в img_for_test")
    parser.add_argument("--references", type=Path, default=REFERENCES,
                        help="Локальный JSON с эталонными расшифровками")
    parser.add_argument("--images-dir", type=Path, default=ROOT / "img_for_test",
                        help="Каталог локальных фотографий")
    parser.add_argument("--line-regions", type=Path,
                        help="JSON с ручными Y-интервалами или прямоугольниками строк")
    parser.add_argument("--model", help="Локально сохранённая TrOCR-модель для сравнения")
    parser.add_argument("--revision", help="Ревизия указанной модели, если нужна")
    parser.add_argument("--output", type=Path, help="Сохранить измерения и текст в JSON")
    parser.add_argument("--kv-cache", choices=["default", "on", "off"], default="default",
                        help="Кэш декодера: сравнение времени и качества")
    parser.add_argument("--precision", choices=["int8", "fp32"],
                        help="Точность декодера на CPU")
    parser.add_argument("--beams", type=int, choices=[1, 2, 3, 4],
                        help="Число вариантов поиска при декодировании")
    parser.add_argument("--variant", action="append", dest="variants",
                        choices=["pipeline", "processed", "source", "binary", "no_deskew", "easyocr", "unsplit"],
                        help="Вариант изображения; можно указать несколько раз")
    args = parser.parse_args()
    selected_variants = args.variants or ["pipeline"]
    if not args.references.is_file():
        parser.error(f"Нет файла эталонов: {args.references}. Передайте --references.")
    reference_bytes = args.references.read_bytes()
    references = json.loads(reference_bytes.decode("utf-8"))
    regions = {}
    if args.line_regions:
        if not args.line_regions.is_file():
            parser.error(f"Нет разметки строк: {args.line_regions}")
        regions = json.loads(args.line_regions.read_text(encoding="utf-8"))
    load_started = time.perf_counter()
    quantize = None if args.precision is None else args.precision == "int8"
    cache = None if args.kv_cache == "default" else args.kv_cache == "on"
    recognizer = TextRecognizer(model_name=args.model, model_revision=args.revision,
                                quantize_decoder=quantize, num_beams=args.beams,
                                use_kv_cache=cache)
    load_seconds = time.perf_counter() - load_started
    report = {"created_at": datetime.now(timezone.utc).isoformat(),
              "model": recognizer.trocr_name, "revision": recognizer.model_revision,
              "precision": "int8" if recognizer.decoder_quantized else "fp32",
              "beams": recognizer.num_beams,
              "batch_size": recognizer.batch_size,
              "torch_version": torch.__version__, "transformers_version": transformers.__version__,
              "metric": "unicode_alnum_with_spaces_v1",
              "kv_cache": recognizer.trocr.generation_config.use_cache,
              "device": recognizer.device, "threads": torch.get_num_threads(),
              "reference_sha256": hashlib.sha256(reference_bytes).hexdigest(),
              "load_seconds": round(load_seconds, 3), "records": [], "detection": []}
    provenance = Path(recognizer.trocr_name) / "download_provenance.json"
    if provenance.is_file():
        report["download_provenance"] = json.loads(provenance.read_text(encoding="utf-8"))

    def record(name: str, label: str, reference: str, lines: list, started: float) -> None:
        hypothesis = " ".join(line["text"] for line in lines)
        result = {"image": name, "variant": label, "text": hypothesis,
                  "lines": [line["text"] for line in lines],
                  "ocr_lines": len(lines), "seconds": round(time.perf_counter() - started, 3),
                  "peak_rss_mib": round(peak_rss_mib(), 1),
                  "formula_chunks": sum(unit["is_formula"] for unit in
                                        SemanticChunker.aggregate_to_sentences(lines)),
                  **score_text(reference, hypothesis)}
        report["records"].append(result)
        print(f"{name} {label}: rows={len(lines)} CER={result['cer']:.3f} "
              f"WER={result['wer']:.3f} seconds={result['seconds']} "
              f"peak_MiB={result['peak_rss_mib']}", flush=True)
        print(hypothesis, flush=True)
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    for name in args.images or references:
        if name not in references:
            raise ValueError(f"Нет эталонной расшифровки: {name}")
        reference = references[name]
        if isinstance(reference, list):
            reference = " ".join(reference)
        image_path = args.images_dir / name
        if not image_path.is_file():
            raise FileNotFoundError(f"Нет изображения {image_path}; передайте --images-dir")
        data = image_path.read_bytes()
        page_started = time.perf_counter()
        processed = ImagePreprocessor.preprocess_for_ocr(data)
        source = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
        if source is None:
            raise ValueError(f"Не удалось декодировать {image_path}")
        if source.shape[:2] != processed.shape[:2]:
            source = cv2.resize(source, (processed.shape[1], processed.shape[0]),
                                interpolation=cv2.INTER_AREA)
        original = source.copy()
        source = ImagePreprocessor.deskew_page(source)
        spans = ImagePreprocessor.detect_line_spans(source)
        detection = {"image": name, "predicted_spans": spans, "detected_lines": len(spans)}
        if name in regions:
            if regions[name] and len(regions[name][0]) == 4:
                predicted_boxes = [[0, top, processed.shape[1], bottom]
                                   for top, bottom in spans]
                detection.update(score_line_boxes(regions[name], predicted_boxes))
                detection["geometry"] = "xyxy"
            else:
                detection.update(score_line_spans(regions[name], spans))
                detection["geometry"] = "y_band"
        report["detection"].append(detection)
        if "pipeline" in selected_variants:
            lines = recognizer.recognize_with_source(processed, data)
            record(name, "pipeline", reference, lines, page_started)
        if selected_variants == ["pipeline"]:
            continue
        if "unsplit" in selected_variants and spans:
            started = time.perf_counter()
            crops = []
            for top, bottom in spans:
                row = processed[top:bottom]
                row_source = source[top:bottom]
                centered = ImagePreprocessor.detect_centered_text_span(row_source)
                if centered is not None:
                    row = row[:, centered[0]:centered[1]]
                    row_source = row_source[:, centered[0]:centered[1]]
                bounds = (ImagePreprocessor.detect_ink_bounds(row_source)
                          if centered is None and row_source.shape[1] >= 1200 else None)
                if bounds is not None:
                    x0, y0, x1, y1 = bounds
                    row = row[y0:y1, x0:x1]
                crops.append(Image.fromarray(cv2.cvtColor(row, cv2.COLOR_BGR2RGB)))
            dense_page = processed.shape[1] >= 1200 and processed.shape[0] >= 900
            texts = recognizer._decode_crops(
                crops, num_beams=max(2, recognizer.num_beams) if dense_page else None,
                use_cache=True if dense_page else None)
            lines = [{"text": recognizer.clean_handwriting_text(text),
                      "bbox": [[0, top], [processed.shape[1], top],
                               [processed.shape[1], bottom], [0, bottom]]}
                     for (top, bottom), text in zip(spans, texts)]
            record(name, "unsplit", reference, lines, started)
        gray = cv2.cvtColor(source, cv2.COLOR_BGR2GRAY)
        _, binary = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        variants = {"processed": processed, "source": source,
                    "binary": cv2.cvtColor(binary, cv2.COLOR_GRAY2BGR),
                    "no_deskew": ImagePreprocessor.preprocess_for_ocr(data, deskew=False)}
        for label, image in variants.items():
            if label not in selected_variants:
                continue
            started = time.perf_counter()
            reference_image = original if label == "no_deskew" else source
            row_spans = ImagePreprocessor.detect_line_spans(reference_image)
            lines = recognizer._recognize_projected_lines(image, row_spans, [],
                                                          source_image=reference_image)
            record(name, label, reference, lines, started)

        # EasyOCR может читать строку даже тогда, когда его детектор страницы
        # ошибся. Сравниваем это отдельно, не меняя основной конвейер.
        if "easyocr" in selected_variants:
            started = time.perf_counter()
            recognized = []
            for top, bottom in spans:
                row = cv2.cvtColor(processed[top:bottom], cv2.COLOR_BGR2GRAY)
                items = recognizer.reader.recognize(
                    row, horizontal_list=[[0, row.shape[1], 0, row.shape[0]]],
                    free_list=[], detail=1,
                )
                recognized.append({"text": " ".join(str(item[1]) for item in items),
                                   "bbox": [[0, top], [processed.shape[1], top],
                                            [processed.shape[1], bottom], [0, bottom]]})
            record(name, "easyocr", reference, recognized, started)

    report["summary"] = {}
    for label in dict.fromkeys(item["variant"] for item in report["records"]):
        records = [item for item in report["records"] if item["variant"] == label]
        report["summary"][label] = {
            "pages": len(records),
            "cer": sum(item["char_edits"] for item in records) / sum(item["reference_chars"] for item in records),
            "wer": sum(item["word_edits"] for item in records) / sum(item["reference_words"] for item in records),
            "seconds": round(sum(item["seconds"] for item in records), 3),
            "peak_rss_mib": max(item["peak_rss_mib"] for item in records),
        }
    labelled = [item for item in report["detection"] if "matched" in item]
    if labelled:
        report["detection_summary_by_geometry"] = {}
        for geometry in {item["geometry"] for item in labelled}:
            group = [item for item in labelled if item["geometry"] == geometry]
            matched = sum(item["matched"] for item in group)
            predicted = matched + sum(item["extra"] for item in group)
            expected = matched + sum(item["missed"] for item in group)
            precision = matched / predicted if predicted else 0.0
            recall = matched / expected if expected else 0.0
            report["detection_summary_by_geometry"][geometry] = {
                "pages": len(group), "precision": precision, "recall": recall,
                "f1": 2 * precision * recall / (precision + recall)
                if precision + recall else 0.0,
                "matched": matched, "missed": expected - matched,
                "extra": predicted - matched,
            }
        if len(report["detection_summary_by_geometry"]) == 1:
            report["detection_summary"] = next(iter(
                report["detection_summary_by_geometry"].values()))
    if args.output:
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
