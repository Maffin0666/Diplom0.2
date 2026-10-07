import os
import re
import cv2
import torch
import numpy as np
from PIL import Image
from typing import List, Dict, Any
import easyocr
from transformers import TrOCRProcessor, VisionEncoderDecoderModel

from server.config import settings
from .content_classifier import ContentClassifier
from .math_speech import normalize_ocr_math
from .image_preprocessing import ImagePreprocessor

from ..utils.logger import get_logger

logger = get_logger(__name__)


class TextRecognizer:
    def __init__(self, model_name: str | None = None, model_revision: str | None = None,
                 quantize_decoder: bool | None = None, num_beams: int | None = None,
                 use_kv_cache: bool | None = None):
        num_cores = os.cpu_count() or 4
        torch.set_num_threads(min(8, num_cores))

        self.device = "cuda" if (settings.USE_GPU and torch.cuda.is_available()) else "cpu"
        num_beams = settings.TROCR_NUM_BEAMS if num_beams is None else num_beams
        if num_beams < 1:
            raise ValueError("Число вариантов декодирования должно быть положительным")
        self.num_beams = num_beams
        self.batch_size = settings.OCR_BATCH_SIZE
        logger.info(f"Инициализация OCR конвейера (устройство: {self.device}, потоков: {torch.get_num_threads()})...")

        # 1. Детектор строк EasyOCR CRAFT
        self.reader = easyocr.Reader(
            settings.OCR_LANGUAGES,
            gpu=self.device == "cuda",
            model_storage_directory=str(settings.MODELS_DIR),
            download_enabled=False,
        )

        # 2. Модель TrOCR с INT8 квантованием
        self.trocr_name = model_name or settings.TROCR_MODEL_NAME
        revision = (model_revision if model_revision is not None else
                    settings.TROCR_REVISION if self.trocr_name == settings.TROCR_MODEL_NAME else None)
        self.model_revision = revision
        quantize_decoder = settings.TROCR_QUANTIZE_DECODER if quantize_decoder is None else quantize_decoder
        self.decoder_quantized = self.device == "cpu" and quantize_decoder
        try:
            self.processor = TrOCRProcessor.from_pretrained(
                self.trocr_name, revision=revision, local_files_only=True
            )
            model = VisionEncoderDecoderModel.from_pretrained(
                self.trocr_name, revision=revision, local_files_only=True
            )

            if self.decoder_quantized:
                model.decoder = torch.ao.quantization.quantize_dynamic(
                    model.decoder, {torch.nn.Linear}, dtype=torch.qint8
                )

            self.trocr = model.to(self.device)
            self.trocr.eval()
            self.trocr.generation_config.use_cache = (
                settings.TROCR_USE_KV_CACHE if use_kv_cache is None else use_kv_cache
            )
            logger.info("TrOCR готова: модель=%s revision=%s decoder=%s cache=%s batch=%d beams=%d",
                        self.trocr_name, revision,
                        "int8" if self.decoder_quantized else "fp32",
                        self.trocr.generation_config.use_cache, self.batch_size, self.num_beams)
        except Exception as e:
            raise RuntimeError("Локальная модель TrOCR недоступна") from e

    @staticmethod
    def is_math_line(text: str) -> bool:
        return ContentClassifier.is_math_block(text)

    @classmethod
    def has_reliable_math_line(cls, lines: List[List[Dict[str, Any]]]) -> bool:
        """Do not let a stray low-confidence OCR symbol veto line recovery."""
        for line in lines:
            confidence = sum(item["confidence"] for item in line) / len(line)
            if confidence >= 0.45 and cls.is_math_line(" ".join(item["text"] for item in line)):
                return True
        return False

    @staticmethod
    def needs_trocr(text: str, confidence: float) -> bool:
        """Не заменяет уверенный печатный текст результатом рукописной модели."""
        letters = [letter for letter in text if letter.isalpha()]
        cyrillic = sum(letter.lower() in "абвгдеёжзийклмнопрстуфхцчшщъыьэюя" for letter in letters)
        cyrillic_share = cyrillic / len(letters) if letters else 0.0
        return confidence < 0.70 or (confidence < 0.85 and cyrillic_share < 0.60)

    @classmethod
    def clean_handwriting_text(cls, text: str) -> str:
        """Устраняет дефекты курсивных соединений TrOCR и нормализует пробелы."""
        t = text.strip()

        # 1. Пробелы после знаков препинания: "серьезное.Так" -> "серьезное. Так"
        t = re.sub(r"([.,:;!?])(?=[а-яА-Яa-zA-Z])", r"\1 ", t)

        # Дефис может быть частью русского слова или математическим минусом.
        # Без оценки изображения нельзя безопасно решать, что он ошибочен.

        # 3. Часто встречающиеся слитные предлоги из-за курсива
        t = re.sub(r"\bвпроцессе\b", "в процессе", t, flags=re.I)
        t = re.sub(r"\bтакчто\b", "так что", t, flags=re.I)

        # После двоеточия добавляем пробел, сохраняя знак и смысл.
        t = re.sub(r"([а-яА-ЯёЁ]):([а-яА-ЯёЁ])", r"\1: \2", t)

        return re.sub(r"\s+", " ", t).strip()

    @staticmethod
    def repair_numbered_list(blocks: List[Dict[str, Any]]) -> None:
        """Исправляет похожую на цифру букву лишь между двумя соседними номерами."""
        lookalikes = {"З": 3, "з": 3, "б": 6, "В": 8, "B": 8, "в": 8}
        number = re.compile(r"^\s*(\d{1,2})[.)]\s+")
        letter = re.compile(r"^\s*([ЗзбВBв])([.)])\s+")
        for index in range(1, len(blocks) - 1):
            previous = number.match(blocks[index - 1]["text"])
            current = letter.match(blocks[index]["text"])
            following = number.match(blocks[index + 1]["text"])
            if not (previous and current and following):
                continue
            expected = int(previous.group(1)) + 1
            if (expected == int(following.group(1)) - 1
                    and lookalikes[current.group(1)] == expected):
                blocks[index]["text"] = (f"{expected}{current.group(2)} "
                                         + blocks[index]["text"][current.end():])

    def recognize_with_source(self, image: np.ndarray, source_bytes: bytes) -> List[Dict[str, Any]]:
        """Передаёт исходные цветные штрихи резервному детектору строк."""
        source = cv2.imdecode(np.frombuffer(source_bytes, np.uint8), cv2.IMREAD_COLOR)
        if source is None:
            return self.recognize(image)
        if source.shape[:2] != image.shape[:2]:
            source = cv2.resize(source, (image.shape[1], image.shape[0]), interpolation=cv2.INTER_AREA)
        source = ImagePreprocessor.deskew_page(source)
        return self.recognize(image, source_image=source)

    def _decode_crops(self, crops: list[Image.Image], *,
                      num_beams: int | None = None,
                      use_cache: bool | None = None) -> list[str]:
        """Одинаковый предел памяти для обычного и резервного пути OCR."""
        decoded = []
        generation_options = {"max_length": 65,
                              "num_beams": self.num_beams if num_beams is None else num_beams}
        if use_cache is not None:
            generation_options["use_cache"] = use_cache
        for start in range(0, len(crops), self.batch_size):
            inputs = self.processor(images=crops[start:start + self.batch_size],
                                    return_tensors="pt", padding=True).to(self.device)
            with torch.inference_mode():
                # 1 начальный токен и до 64 новых. Явный max_length устраняет
                # конфликт с max_length=64 из конфигурации модели.
                generated = self.trocr.generate(inputs.pixel_values,
                                                **generation_options)
            decoded.extend(self.processor.batch_decode(generated, skip_special_tokens=True))
        return decoded

    def _recognize_projected_lines(
        self, image: np.ndarray, spans: list[tuple[int, int]], raw_items: list[dict],
        source_image: np.ndarray | None = None,
    ) -> List[Dict[str, Any]]:
        """Читает отдельные строки, когда CRAFT объединил несколько строк."""
        height, width = image.shape[:2]
        crops = []
        crop_groups: list[int] = []
        for index, (y0, y1) in enumerate(spans):
            row = image[y0:y1]
            row_source = source_image[y0:y1] if source_image is not None else row
            centered = ImagePreprocessor.detect_centered_text_span(row_source)
            if centered is not None:
                row = row[:, centered[0]:centered[1]]
                row_source = row_source[:, centered[0]:centered[1]]
                logger.info("OCR: удалены боковые росчерки, строка=%d, x=%d:%d",
                            index, *centered)
            # Центрированная строка уже ограничена по X. Повторный поиск
            # самого плотного слова мог бы отбросить короткое первое слово.
            bounds = (ImagePreprocessor.detect_ink_bounds(row_source)
                      if centered is None and row_source.shape[1] >= 1200 else None)
            if bounds is not None:
                left, top, right, bottom = bounds
                row = row[top:bottom, left:right]
            row_width = row.shape[1]
            cuts = [0, row_width]
            # Длинная строка сжимается энкодером TrOCR до 384 пикселей.
            # Делим её только по светлому промежутку между словами.
            if row_width >= 800 and row_width / max(1, y1 - y0) > 10:
                gray = cv2.cvtColor(row, cv2.COLOR_BGR2GRAY)
                _, ink = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
                density = np.convolve(np.count_nonzero(ink, axis=0), np.ones(9) / 9, mode="same")
                left, right = int(row_width * 0.35), int(row_width * 0.65)
                split = left + int(np.argmin(density[left:right]))
                if density[split] < np.median(density[left:right]) * 0.45:
                    cuts = [0, split, row_width]
            for x0, x1 in zip(cuts, cuts[1:]):
                crops.append(Image.fromarray(cv2.cvtColor(row[:, x0:x1], cv2.COLOR_BGR2RGB)))
                crop_groups.append(index)
        # Ограничиваем размер пакета: целая страница курсивного текста может
        # содержать десятки фрагментов, что перегружает память ноутбука.
        dense_page = width >= 1200 and height >= 900
        # На плотной странице кэш декодера и два варианта поиска ускорили
        # локальный прогон, не меняя режим коротких рукописных снимков.
        decoded = self._decode_crops(crops,
                                     num_beams=max(2, self.num_beams) if dense_page else None,
                                     use_cache=True if dense_page else None)
        line_parts: list[list[str]] = [[] for _ in spans]
        for index, text in zip(crop_groups, decoded):
            line_parts[index].append(text)
        blocks = []
        for (top, bottom), parts in zip(spans, line_parts):
            clean = self.clean_handwriting_text(" ".join(parts))
            if not clean:
                continue
            nearby = [item["confidence"] for item in raw_items
                      if top <= (item["top_y"] + item["bottom_y"]) / 2 < bottom]
            blocks.append({
                "text": clean,
                "confidence": round(sum(nearby) / len(nearby), 3) if nearby else 0.0,
                "bbox": [[0, top], [width, top], [width, min(bottom, height)], [0, min(bottom, height)]],
                "ocr_method": "projection",
            })
        self.repair_numbered_list(blocks)
        logger.info("OCR: резервное разделение строк, найдено=%d, прочитано=%d, фрагментов=%d",
                    len(spans), len(blocks), len(crops))
        return blocks

    def recognize(self, image: np.ndarray, source_image: np.ndarray | None = None) -> List[Dict[str, Any]]:
        results = self.reader.readtext(
            image,
            paragraph=False,
            adjust_contrast=0.6,
            text_threshold=0.25,
            low_text=0.15,
            link_threshold=0.35,
            mag_ratio=1.3
        )

        if not results:
            return []

        h_img, w_img = image.shape[:2]
        raw_items = []

        for bbox, text, conf in results:
            clean = text.strip()
            if not clean or clean in ("@", "|", "_", "~"):
                continue

            top_y = max(0, int(min(bbox[0][1], bbox[1][1])))
            bottom_y = min(h_img, int(max(bbox[2][1], bbox[3][1])))
            left_x = max(0, int(min(bbox[0][0], bbox[3][0])))
            right_x = min(w_img, int(max(bbox[1][0], bbox[2][0])))

            # Отсекаем изолированные краевые цифры/метки страниц
            if len(clean) <= 2 and top_y < 85 and (right_x > w_img * 0.75 or left_x < w_img * 0.25):
                continue

            raw_items.append({
                "bbox": [[left_x, top_y], [right_x, top_y], [right_x, bottom_y], [left_x, bottom_y]],
                "text": clean,
                "confidence": float(conf),
                "top_y": top_y,
                "bottom_y": bottom_y,
                "left_x": left_x,
                "right_x": right_x,
                "height": bottom_y - top_y
            })

        if not raw_items:
            return []

        # Группировка в горизонтальные строки
        raw_items.sort(key=lambda it: it["top_y"])
        avg_h = sum(it["height"] for it in raw_items) / len(raw_items)
        line_threshold = avg_h * 0.65

        lines: List[List[Dict[str, Any]]] = []
        cur_line: List[Dict[str, Any]] = []

        for item in raw_items:
            if not cur_line:
                cur_line.append(item)
                continue
            if abs(item["top_y"] - cur_line[-1]["top_y"]) <= line_threshold:
                cur_line.append(item)
            else:
                cur_line.sort(key=lambda x: x["left_x"])
                lines.append(cur_line)
                cur_line = [item]

        if cur_line:
            cur_line.sort(key=lambda x: x["left_x"])
            lines.append(cur_line)

        if source_image is not None and raw_items:
            spans = ImagePreprocessor.detect_line_spans(source_image)
            mean_confidence = sum(item["confidence"] for item in raw_items) / len(raw_items)
            has_clear_formula = self.has_reliable_math_line(lines)
            if (mean_confidence < 0.45 and len(spans) > len(lines)
                    and not has_clear_formula):
                logger.info("OCR: детектор объединил строки, EasyOCR=%d, проекция=%d, confidence=%.3f",
                            len(lines), len(spans), mean_confidence)
                try:
                    return self._recognize_projected_lines(image, spans, raw_items,
                                                           source_image=source_image)
                except Exception:
                    logger.exception("OCR: резервное разделение строк не удалось; используем детектор")

        structured_blocks = []
        crops_to_trocr = []
        trocr_indices = []

        for idx, l in enumerate(lines):
            line_text = " ".join(it["text"] for it in l)
            avg_conf = sum(it["confidence"] for it in l) / len(l)

            # Вычисляем границы строки с запасом для петель букв (padding)
            h_line = max(it["bottom_y"] for it in l) - min(it["top_y"] for it in l)
            pad_y = max(8, int(h_line * 0.22))
            pad_x = 20

            min_x = max(0, min(it["left_x"] for it in l) - pad_x)
            max_x = min(w_img, max(it["right_x"] for it in l) + pad_x)
            min_y = max(0, min(it["top_y"] for it in l) - pad_y)
            max_y = min(h_img, max(it["bottom_y"] for it in l) + pad_y)

            bbox = [[min_x, min_y], [max_x, min_y], [max_x, max_y], [min_x, max_y]]

            has_math = self.is_math_line(line_text)
            is_candidate = (self.trocr is not None) and (not has_math) and self.needs_trocr(line_text, avg_conf) and (max_x - min_x > 30)

            if is_candidate and (max_y - min_y > 10):
                line_crop = image[min_y:max_y, min_x:max_x]
                crops_to_trocr.append(Image.fromarray(cv2.cvtColor(line_crop, cv2.COLOR_BGR2RGB)))
                trocr_indices.append(idx)

            structured_blocks.append({
                "text": line_text,
                "confidence": round(avg_conf, 3),
                "bbox": bbox,
                "ocr_method": "easyocr",
            })

        # Пакетное распознавание рукописных строк
        if crops_to_trocr:
            try:
                decoded_texts = self._decode_crops(crops_to_trocr)

                for block_idx, text_pred in zip(trocr_indices, decoded_texts):
                    pred_clean = self.clean_handwriting_text(text_pred)
                    if len(pred_clean) >= 3 and len(re.findall(r"[а-яА-ЯёЁ]", pred_clean)) >= 2:
                        structured_blocks[block_idx]["text"] = pred_clean
                        structured_blocks[block_idx]["ocr_method"] = "trocr"
                        # TrOCR не предоставляет здесь калиброванной уверенности.
                        # Сохраняем исходную оценку EasyOCR вместо выдуманных 0.95.
            except Exception as e:
                logger.error(f"Ошибка инференса TrOCR: {e}")

        # Финальная очистка для всех строк
        for b in structured_blocks:
            b["text"] = self.clean_handwriting_text(b["text"])
            if ContentClassifier.is_math_block(b["text"]):
                b["text"] = normalize_ocr_math(b["text"])

        self.repair_numbered_list(structured_blocks)

        logger.info(f"Распознано строк: {len(structured_blocks)}")
        return structured_blocks
