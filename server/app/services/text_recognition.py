import os
import re
import cv2
import torch
import numpy as np
from PIL import Image
from typing import List, Dict, Any
import easyocr
from transformers import TrOCRProcessor, VisionEncoderDecoderModel

try:
    from config import settings
except (ImportError, ModuleNotFoundError):
    try:
        from server.config import settings
    except (ImportError, ModuleNotFoundError):
        from ...config import settings

from ..utils.logger import get_logger

logger = get_logger(__name__)


class TextRecognizer:
    def __init__(self):
        num_cores = os.cpu_count() or 4
        torch.set_num_threads(min(8, num_cores))

        self.device = "cuda" if (settings.USE_GPU and torch.cuda.is_available()) else "cpu"
        logger.info(f"Инициализация OCR конвейера (устройство: {self.device}, потоков: {torch.get_num_threads()})...")

        # 1. Детектор строк EasyOCR CRAFT
        self.reader = easyocr.Reader(
            settings.OCR_LANGUAGES,
            gpu=settings.USE_GPU,
            model_storage_directory=str(settings.MODELS_DIR)
        )

        # 2. Модель TrOCR с INT8 квантованием
        self.trocr_name = "raxtemur/trocr-base-ru"
        try:
            self.processor = TrOCRProcessor.from_pretrained(self.trocr_name)
            model = VisionEncoderDecoderModel.from_pretrained(self.trocr_name)

            if self.device == "cpu":
                model.decoder = torch.ao.quantization.quantize_dynamic(
                    model.decoder, {torch.nn.Linear}, dtype=torch.qint8
                )

            self.trocr = model.to(self.device)
            self.trocr.eval()
            logger.info("✅ Модель TrOCR готова к работе")
        except Exception as e:
            logger.warning(f"TrOCR недоступен ({e}), откат на EasyOCR")
            self.processor = None
            self.trocr = None

    @staticmethod
    def is_math_line(text: str) -> bool:
        t = text.lower().strip()
        has_eq = any(op in t for op in ["=", "≠", "≈", "≤", "≥", "<=", ">="])
        has_fn = bool(re.search(r"\b(lim|sqrt|sin|cos|tg|ctg|log|ln|int|sum)\b", t)) or ("\\" in t)
        has_pow = bool(re.search(r"[a-zа-я0-9]\^[0-9a-z]", t)) or bool(re.search(r"\b\d+/\d+\b", t))
        return has_eq or has_fn or has_pow

    @classmethod
    def clean_handwriting_text(cls, text: str) -> str:
        """Устраняет дефекты курсивных соединений TrOCR и нормализует пробелы."""
        t = text.strip()

        # 1. Пробелы после знаков препинания: "серьезное.Так" -> "серьезное. Так"
        t = re.sub(r"([.,:;!?])(?=[а-яА-Яa-zA-Z])", r"\1 ", t)

        # 2. Исправление ложных дефисов от рукописных соединений
        # Сохраняем только реальные русские частицы (-то, -либо, -нибудь, кое-)
        def _fix_hyphen(m):
            w1, w2 = m.group(1), m.group(2)
            w2_lower = w2.lower()
            if w2_lower in ("то", "либо", "нибудь", "ка", "де", "с"):
                return f"{w1}-{w2}"
            if w1.lower() in ("кое", "кой", "из", "по"):
                return f"{w1}-{w2}"
            return f"{w1} {w2}"

        t = re.sub(r"\b([а-яА-Яa-zA-Z]+)-([а-яА-Яa-zA-Z]+)\b", _fix_hyphen, t)

        # 3. Часто встречающиеся слитные предлоги из-за курсива
        t = re.sub(r"\bвпроцессе\b", "в процессе", t, flags=re.I)
        t = re.sub(r"\bтакчто\b", "так что", t, flags=re.I)

        # 4. Двоеточия внутри слов ("его:можно" -> "его можно")
        t = re.sub(r"([а-яА-ЯёЁ]):([а-яА-ЯёЁ])", r"\1 \2", t)

        return re.sub(r"\s+", " ", t).strip()

    def recognize(self, image: np.ndarray) -> List[Dict[str, Any]]:
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
            is_candidate = (self.trocr is not None) and (not has_math) and (avg_conf < 0.85) and (max_x - min_x > 30)

            if is_candidate and (max_y - min_y > 10):
                line_crop = image[min_y:max_y, min_x:max_x]
                crops_to_trocr.append(Image.fromarray(cv2.cvtColor(line_crop, cv2.COLOR_BGR2RGB)))
                trocr_indices.append(idx)

            structured_blocks.append({
                "text": line_text,
                "confidence": round(avg_conf, 3),
                "bbox": bbox
            })

        # Пакетное распознавание рукописных строк
        if crops_to_trocr:
            try:
                inputs = self.processor(images=crops_to_trocr, return_tensors="pt", padding=True).to(self.device)
                with torch.inference_mode():
                    generated_ids = self.trocr.generate(
                        inputs.pixel_values,
                        max_new_tokens=64,
                        num_beams=1
                    )
                decoded_texts = self.processor.batch_decode(generated_ids, skip_special_tokens=True)

                for block_idx, text_pred in zip(trocr_indices, decoded_texts):
                    pred_clean = self.clean_handwriting_text(text_pred)
                    if len(pred_clean) >= 3 and len(re.findall(r"[а-яА-ЯёЁ]", pred_clean)) >= 2:
                        structured_blocks[block_idx]["text"] = pred_clean
                        structured_blocks[block_idx]["confidence"] = 0.95
            except Exception as e:
                logger.error(f"Ошибка инференса TrOCR: {e}")

        # Финальная очистка для всех строк
        for b in structured_blocks:
            b["text"] = self.clean_handwriting_text(b["text"])

        logger.info(f"Распознано строк: {len(structured_blocks)}")
        return structured_blocks