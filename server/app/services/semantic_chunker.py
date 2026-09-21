import uuid
import re
from typing import List, Dict, Any
from ..models import TextChunk, ContentType
from .content_classifier import ContentClassifier


class SemanticChunker:
    """Объединяет строки конспекта в полноценные смысловые предложения и формулы."""

    @staticmethod
    def _union_bboxes(boxes: List[List[int]]) -> List[int]:
        if not boxes:
            return [0, 0, 0, 0]
        min_x = min(b[0] for b in boxes)
        min_y = min(b[1] for b in boxes)
        max_x = max(b[2] for b in boxes)
        max_y = max(b[3] for b in boxes)
        return [min_x, min_y, max_x, max_y]

    @classmethod
    def aggregate_to_sentences(cls, raw_blocks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        Группирует построчные блоки:
        - Формулы остаются независимыми блоками.
        - Текст накапливается до знака окончания предложения (. ! ?).
        """
        if not raw_blocks:
            return []

        semantic_units = []
        pending_texts = []
        pending_boxes = []
        pending_confs = []

        def flush_sentence():
            if not pending_texts:
                return
            full_sentence = " ".join(pending_texts).strip()
            # Исправляем склеенные знаки препинания
            full_sentence = re.sub(r"\s+([.,:;!?])", r"\1", full_sentence)
            avg_conf = sum(pending_confs) / len(pending_confs) if pending_confs else 0.9
            semantic_units.append({
                "text": full_sentence,
                "is_formula": False,
                "confidence": round(avg_conf, 3),
                "bbox": cls._union_bboxes(pending_boxes)
            })
            pending_texts.clear()
            pending_boxes.clear()
            pending_confs.clear()

        for b in raw_blocks:
            text = b["text"].strip()
            if not text:
                continue

            box = [b["bbox"][0][0], b["bbox"][0][1], b["bbox"][2][0], b["bbox"][2][1]]
            is_formula = ContentClassifier.is_math_block(text)

            if is_formula:
                # Если встретили формулу — сначала сбрасываем накопленный текст
                flush_sentence()
                semantic_units.append({
                    "text": text,
                    "is_formula": True,
                    "confidence": b.get("confidence", 0.9),
                    "bbox": box
                })
            else:
                pending_texts.append(text)
                pending_boxes.append(box)
                pending_confs.append(b.get("confidence", 0.9))

                # Если строка заканчивается точкой, восклицательным или вопросительным знаком
                if re.search(r"[.!?]\s*$", text):
                    flush_sentence()

        # Сбрасываем оставшийся хвост текста
        flush_sentence()
        return semantic_units