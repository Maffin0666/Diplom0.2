"""Регрессии резервной разметки строк и файлового журнала."""

import uuid
import unittest
from unittest.mock import patch

import cv2
import numpy as np

from server.config import settings
from server.app.services.image_preprocessing import ImagePreprocessor
from server.app.services.text_recognition import TextRecognizer
from server.app.services.semantic_chunker import SemanticChunker
from server.app.utils.logger import get_logger


def sample_page() -> np.ndarray:
    image = np.full((330, 600, 3), 255, dtype=np.uint8)
    for index in range(6):
        cv2.putText(image, "handwriting line", (25, 40 + index * 50),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.8, (20, 20, 20), 2)
    return image


class DetectionAndLoggingTests(unittest.TestCase):
    def test_numbered_list_repairs_only_a_supported_neighboring_digit(self):
        blocks = [{"text": "7. Прослеживаемость"},
                  {"text": "В. Модифицируемость"},
                  {"text": "9. Проранжированность"},
                  {"text": "В. Введение"}]
        TextRecognizer.repair_numbered_list(blocks)
        self.assertEqual(blocks[1]["text"], "8. Модифицируемость")
        self.assertEqual(blocks[3]["text"], "В. Введение")

    def test_decoder_batches_keep_order_and_limit_memory(self):
        class Inputs:
            def __init__(self, values):
                self.pixel_values = values

            def to(self, device):
                return self

        class Processor:
            def __call__(self, images, **kwargs):
                return Inputs(images)

            def batch_decode(self, generated, **kwargs):
                return [str(value) for value in generated]

        class Model:
            def __init__(self):
                self.batch_lengths = []
                self.options = []

            def generate(self, values, **kwargs):
                self.batch_lengths.append(len(values))
                self.options.append(kwargs)
                return values

        recognizer = TextRecognizer.__new__(TextRecognizer)
        recognizer.processor = Processor()
        recognizer.trocr = Model()
        recognizer.device = "cpu"
        recognizer.num_beams = 1
        recognizer.batch_size = 6
        self.assertEqual(recognizer._decode_crops(list(range(13))), [str(i) for i in range(13)])
        self.assertEqual(recognizer.trocr.batch_lengths, [6, 6, 1])
        self.assertTrue(all("use_cache" not in option for option in
                            recognizer.trocr.options))
        recognizer._decode_crops([1], num_beams=2, use_cache=True)
        self.assertEqual(recognizer.trocr.options[-1]["num_beams"], 2)
        self.assertTrue(recognizer.trocr.options[-1]["use_cache"])

    def test_centered_short_line_excludes_side_flourishes(self):
        row = np.full((160, 900, 3), 255, dtype=np.uint8)
        for x in range(330, 690, 45):
            cv2.rectangle(row, (x, 35), (x + 20, 59), (20, 20, 20), -1)
        for x in (60, 130, 210):
            cv2.rectangle(row, (x, 0), (x + 20, 70), (20, 20, 20), -1)
        span = ImagePreprocessor.detect_centered_text_span(row)
        self.assertIsNotNone(span)
        self.assertLess(span[0], 330)
        self.assertGreater(span[0], 150)
        self.assertGreater(span[1], 665)
        self.assertLess(span[1], 800)

    def test_sentences_inside_ocr_line_become_separate_audio_chunks(self):
        blocks = [{"text": "Тайга. Ночь. Слышны комары.", "confidence": 0.4,
                   "bbox": [[0, 0], [300, 0], [300, 40], [0, 40]]}]
        units = SemanticChunker.aggregate_to_sentences(blocks)
        self.assertEqual([unit["text"] for unit in units],
                         ["Тайга.", "Ночь.", "Слышны комары."])
        self.assertTrue(all(not unit["is_formula"] for unit in units))

    def test_projection_finds_lines_missing_from_detector(self):
        image = sample_page()
        spans = ImagePreprocessor.detect_line_spans(image)
        self.assertEqual(len(spans), 6)
        self.assertTrue(all(a < b for a, b in spans))

        class Reader:
            def readtext(self, image, **kwargs):
                return [
                    ([[20, 20], [260, 20], [260, 48], [20, 48]], "строка одна", 0.1),
                    ([[20, 265], [260, 265], [260, 295], [20, 295]], "строка шесть", 0.1),
                ]

        recognizer = TextRecognizer.__new__(TextRecognizer)
        recognizer.reader = Reader()
        recognizer.trocr = object()
        expected = [{"text": "найденная строка", "confidence": 0.1,
                     "bbox": [[0, 0], [600, 0], [600, 50], [0, 50]]}]
        with patch.object(recognizer, "_recognize_projected_lines", return_value=expected) as projected:
            self.assertEqual(recognizer.recognize(image, source_image=image), expected)
            self.assertEqual(len(projected.call_args.args[1]), 6)

        # Ошибка резервного OCR не должна превращать всю задачу в failed.
        recognizer.trocr = None
        with patch.object(recognizer, "_recognize_projected_lines", side_effect=RuntimeError("OCR failed")):
            fallback = recognizer.recognize(image, source_image=image)
            self.assertEqual(len(fallback), 2)
            self.assertEqual([item["text"] for item in fallback], ["строка одна", "строка шесть"])

    def test_dense_notebook_rows_do_not_merge_or_include_bleedthrough(self):
        """Частые строки и светлый текст с оборота не должны смешиваться."""
        image = np.full((1000, 1920, 3), 245, dtype=np.uint8)
        for y in range(0, 1000, 40):
            cv2.line(image, (0, y), (1919, y), (205, 185, 175), 1)
        for index in range(12):
            y = 125 + index * 65
            cv2.putText(image, f"{index + 1}. handwritten line", (350, y),
                        cv2.FONT_HERSHEY_SIMPLEX, 1.2, (30, 30, 30), 3)
            cv2.putText(image, "other side", (1520, y),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.8, (180, 180, 180), 2)
        for y in range(40, 950, 140):
            cv2.rectangle(image, (0, y), (70, y + 45), (20, 20, 20), -1)

        spans = ImagePreprocessor.detect_line_spans(image)
        self.assertEqual(len(spans), 12)
        bounds = ImagePreprocessor.detect_ink_bounds(image[spans[4][0]:spans[4][1]])
        self.assertIsNotNone(bounds)
        self.assertGreater(bounds[0], 300)
        self.assertLess(bounds[2], 1300)

        # От видимой только у нижней кромки строки нельзя получать аудиоблок.
        image[986:, 350:900] = (20, 20, 20)
        self.assertEqual(len(ImagePreprocessor.detect_line_spans(image)), 12)

    def test_file_logging_is_shared_and_not_duplicated(self):
        log = get_logger("server.app.test")
        self.assertIs(log, get_logger("server.app.test"))
        marker = "test-marker-" + uuid.uuid4().hex
        log.info("%s", marker)
        for handler in get_logger("server").handlers:
            handler.flush()
        content = (settings.LOG_DIR / "server.log").read_text(encoding="utf-8")
        self.assertEqual(content.count(marker), 1)


if __name__ == "__main__":
    unittest.main()
