"""Export manually transcribed line crops for reproducible OCR training.

The split is by page, never by line, so validation does not reuse the same
photograph's handwriting and background as training. Outputs are local and
ignored by Git because they contain the user's notes and transcriptions.
"""

import argparse
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np

from server.app.services.image_preprocessing import ImagePreprocessor


ROOT = Path(__file__).resolve().parents[1]
LABEL_DIR = ROOT / "reports" / "ocr_comparison"
DEFAULT_VALIDATION = ("real3.jpg", "real9.jpg", "real12.jpg")


def load_annotations() -> tuple[dict, dict, dict]:
    references = json.loads((ROOT / "tests/fixtures/handwriting_ground_truth.json")
                            .read_text(encoding="utf-8"))
    labels, metadata = {}, {}
    for stem in ("line_regions_2026-10-05", "line_regions_real2_real8_2026-10-06"):
        labels.update(json.loads((LABEL_DIR / f"{stem}.json").read_text(encoding="utf-8")))
        metadata.update(json.loads((LABEL_DIR / f"{stem}_meta.json").read_text(encoding="utf-8")))
    return references, labels, metadata


def export_lines(output: Path, validation_pages: set[str]) -> dict:
    references, labels, metadata = load_annotations()
    unknown = validation_pages - labels.keys()
    if unknown:
        raise ValueError(f"Нет разметки для проверочных страниц: {sorted(unknown)}")
    output.mkdir(parents=True, exist_ok=True)
    records = []
    for name in sorted(labels):
        data = (ROOT / "img_for_test" / name).read_bytes()
        checksum = hashlib.sha256(data).hexdigest()
        if checksum != metadata[name]["sha256"]:
            raise ValueError(f"Изображение {name} изменилось после разметки")
        spans, texts = labels[name], references[name]
        if not isinstance(texts, list) or len(spans) != len(texts):
            raise ValueError(f"Неверное число расшифровок для {name}")
        processed = ImagePreprocessor.preprocess_for_ocr(data)
        source = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
        if source is None:
            raise ValueError(f"Не удалось прочитать {name}")
        if source.shape[:2] != processed.shape[:2]:
            source = cv2.resize(source, (processed.shape[1], processed.shape[0]),
                                interpolation=cv2.INTER_AREA)
        source = ImagePreprocessor.deskew_page(source)
        split = "validation" if name in validation_pages else "train"
        for index, (region, text) in enumerate(zip(spans, texts)):
            if len(region) == 2:
                top, annotated_bottom = region
                left, right = 0, processed.shape[1]
            elif len(region) == 4:
                left, top, right, annotated_bottom = region
            else:
                raise ValueError(f"Неизвестный формат координат {name}:{index}")
            # Manual grid rounding may extend one or two pixels past the resized page.
            bottom = min(annotated_bottom, processed.shape[0])
            if (not (0 <= top < bottom and annotated_bottom <= processed.shape[0] + 2
                     and 0 <= left < right <= processed.shape[1]) or not str(text).strip()):
                raise ValueError(f"Пустая или неверная строка {name}:{index}")
            row = processed[top:bottom, left:right]
            row_source = source[top:bottom, left:right]
            if len(region) == 2:
                centered = ImagePreprocessor.detect_centered_text_span(row_source)
                if centered is not None:
                    row = row[:, centered[0]:centered[1]]
                elif row_source.shape[1] >= 1200:
                    bounds = ImagePreprocessor.detect_ink_bounds(row_source)
                    if bounds is not None:
                        crop_left, y0, crop_right, y1 = bounds
                        row = row[y0:y1, crop_left:crop_right]
            if row.size == 0:
                raise ValueError(f"Пустой кроп {name}:{index}")
            relative_path = Path(split) / f"{Path(name).stem}_{index:03d}.png"
            crop_path = output / relative_path
            crop_path.parent.mkdir(parents=True, exist_ok=True)
            if not cv2.imwrite(str(crop_path), row):
                raise OSError(f"Не удалось сохранить {crop_path}")
            records.append({"image": name, "line": index, "split": split,
                            "text": text, "crop": relative_path.as_posix(),
                            "source_sha256": checksum, "region": region})
    manifest = {"format": "handwriting_lines_v1", "validation_pages": sorted(validation_pages),
                "records": records}
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2),
                                          encoding="utf-8")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "reports/ocr_training/lines")
    parser.add_argument("--validation-page", action="append", dest="validation_pages")
    args = parser.parse_args()
    validation = set(args.validation_pages or DEFAULT_VALIDATION)
    manifest = export_lines(args.output, validation)
    counts = {split: sum(item["split"] == split for item in manifest["records"])
              for split in ("train", "validation")}
    print(f"Готово: {counts['train']} обучающих и {counts['validation']} проверочных строк; "
          f"{args.output / 'manifest.json'}")


if __name__ == "__main__":
    main()
