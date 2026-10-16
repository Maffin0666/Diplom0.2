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
    def test_columns_require_a_clear_upper_gutter(self):
        page = np.full((1400, 1920, 3), 245, dtype=np.uint8)
        for y in range(80, 560, 80):
            cv2.rectangle(page, (200, y), (800, y + 27), (20, 20, 20), -1)
            cv2.rectangle(page, (1120, y), (1700, y + 27), (20, 20, 20), -1)
        for y in range(800, 1200, 100):
            cv2.rectangle(page, (200, y), (1700, y + 27), (20, 20, 20), -1)

        regions = ImagePreprocessor.detect_column_regions(page)
        self.assertGreaterEqual(len(regions), 14)
        self.assertTrue(any(right < 1100 for _, _, right, _ in regions))
        self.assertTrue(any(left > 800 and right == 1920
                            for left, _, right, _ in regions))
        self.assertTrue(any(left == 0 and right == 1920
                            for left, _, right, _ in regions))

        for y in range(80, 560, 80):
            cv2.rectangle(page, (800, y), (1120, y + 27), (20, 20, 20), -1)
        self.assertEqual(ImagePreprocessor.detect_column_regions(page), [])

    def test_clear_columns_use_rectangular_line_reader(self):
        image = sample_page()

        class Reader:
            def readtext(self, image, **kwargs):
                return [([[20, 20], [260, 20], [260, 48], [20, 48]],
                         "строка текста", 0.1)]

        recognizer = TextRecognizer.__new__(TextRecognizer)
        recognizer.reader = Reader()
        recognizer.trocr = object()
        regions = [(0, 0, 300, 60), (300, 0, 600, 60)]
        expected = [{"text": "прочитано", "confidence": 0.1,
                     "bbox": [[0, 0], [300, 0], [300, 60], [0, 60]]}]
        with (patch.object(ImagePreprocessor, "detect_line_spans", return_value=[]),
              patch.object(ImagePreprocessor, "detect_column_regions", return_value=regions),
              patch.object(recognizer, "_recognize_projected_regions",
                           return_value=expected) as projected):
            self.assertEqual(recognizer.recognize(image, source_image=image), expected)
            self.assertEqual(projected.call_args.args[1], regions)
            self.assertEqual(projected.call_args.kwargs["crop_width_threshold"], 700)

    def test_rectangular_reader_preserves_column_order_and_coordinates(self):
        image = np.full((80, 800, 3), 245, dtype=np.uint8)
        regions = [(0, 0, 400, 70), (400, 0, 800, 70)]
        recognizer = TextRecognizer.__new__(TextRecognizer)
        with patch.object(recognizer, "_decode_crops", return_value=["слева", "справа"]):
            blocks = recognizer._recognize_projected_regions(image, regions, [])
        self.assertEqual([block["text"] for block in blocks], ["слева", "справа"])
        self.assertEqual(blocks[0]["bbox"], [[0, 0], [400, 0], [400, 70], [0, 70]])
        self.assertEqual(blocks[1]["bbox"], [[400, 0], [800, 0], [800, 70], [400, 70]])

    def test_clear_columns_recover_when_craft_finds_nothing(self):
        image = sample_page()

        class EmptyReader:
            def readtext(self, image, **kwargs):
                return []

        recognizer = TextRecognizer.__new__(TextRecognizer)
        recognizer.reader = EmptyReader()
        recognizer.trocr = object()
        regions = [(0, 0, 300, 60), (300, 0, 600, 60)]
        expected = [{"text": "строка", "confidence": 0.5}]
        with (patch.object(ImagePreprocessor, "detect_column_regions", return_value=regions),
              patch.object(recognizer, "_recognize_projected_regions",
                           return_value=expected) as projected):
            self.assertEqual(recognizer.recognize(image, source_image=image), expected)
            self.assertIs(projected.call_args.args[0], image)
            self.assertEqual(projected.call_args.args[1:3], (regions, []))

    def test_unreliable_math_symbol_does_not_block_line_recovery(self):
        image = sample_page()

        class Reader:
            def __init__(self, formula_confidence):
                self.formula_confidence = formula_confidence

            def readtext(self, image, **kwargs):
                return [
                    ([[20, 20], [260, 20], [260, 48], [20, 48]],
                     "=аi" if self.formula_confidence < 0.45 else "x = 2",
                     self.formula_confidence),
                    ([[20, 265], [260, 265], [260, 295], [20, 295]],
                     "последняя строка", 0.1),
                ]

        recognizer = TextRecognizer.__new__(TextRecognizer)
        recognizer.trocr = None
        recognizer.reader = Reader(0.1)
        with patch.object(recognizer, "_recognize_projected_lines", return_value=[]) as projected:
            recognizer.recognize(image, source_image=image)
            projected.assert_called_once()

        recognizer.reader = Reader(0.9)
        with patch.object(recognizer, "_recognize_projected_lines", return_value=[]) as projected:
            recognizer.recognize(image, source_image=image)
            projected.assert_not_called()

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

    def test_shadowed_lower_page_does_not_create_a_long_tail_of_rows(self):
        page = np.full((1200, 1920, 3), 195, dtype=np.uint8)
        for index in range(8):
            cv2.putText(page, "handwriting line", (320, 85 + index * 80),
                        cv2.FONT_HERSHEY_SIMPLEX, 1.1, (25, 25, 25), 3)
        for y in range(760, 1200):
            page[y, :, :] = int(170 - 100 * (y - 760) / 440)
        for y in range(780, 1200, 35):
            cv2.line(page, (0, y), (1919, y), (90, 90, 90), 2)

        spans = ImagePreprocessor.detect_line_spans(page)
        self.assertLessEqual(len(spans), 10)
        self.assertLess(spans[-1][1], 900)

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

    def test_horizontal_crop_keeps_short_leading_word(self):
        row = np.full((110, 1920, 3), 245, dtype=np.uint8)
        cv2.putText(row, "Kinds", (210, 75), cv2.FONT_HERSHEY_SIMPLEX,
                    1.2, (20, 20, 20), 3)
        cv2.putText(row, "TestingRequirements", (450, 75),
                    cv2.FONT_HERSHEY_SIMPLEX, 1.2, (20, 20, 20), 3)
        # Близкая заметная пометка справа не должна расширить основную строку.
        cv2.putText(row, "side", (930, 75), cv2.FONT_HERSHEY_SIMPLEX,
                    1.0, (20, 20, 20), 2)
        cv2.putText(row, "reverse", (1550, 75), cv2.FONT_HERSHEY_SIMPLEX,
                    1.0, (180, 180, 180), 2)

        bounds = ImagePreprocessor.detect_ink_bounds(row)
        self.assertIsNotNone(bounds)
        self.assertLess(bounds[0], 210)
        self.assertGreater(bounds[2], 750)
        self.assertLess(bounds[2], 900)

    def test_horizontal_crop_ignores_dark_right_page_edge(self):
        for binding in ("solid", "spiral"):
            with self.subTest(binding=binding):
                row = np.full((95, 1920, 3), 245, dtype=np.uint8)
                cv2.putText(row, "real handwriting row", (230, 70),
                            cv2.FONT_HERSHEY_SIMPLEX, 1.6, (25, 25, 25), 3)
                if binding == "solid":
                    cv2.rectangle(row, (1740, 0), (1919, 94), (35, 35, 35), -1)
                else:
                    for y in range(0, 95, 16):
                        cv2.rectangle(row, (1740, y), (1919, y + 8),
                                      (25, 25, 25), -1)
                bounds = ImagePreprocessor.detect_ink_bounds(row)
                self.assertIsNotNone(bounds)
                self.assertLess(bounds[0], 320)
                self.assertGreater(bounds[2], 600)
                self.assertLess(bounds[2], 1500)

    def test_local_projection_recovers_short_rows_below_global_peak(self):
        page = np.full((1200, 1920, 3), 245, dtype=np.uint8)
        for index in range(8):
            top = 80 + index * 130
            width = 900 if index in (0, 3, 7) else 70
            cv2.rectangle(page, (300, top), (300 + width, top + 34),
                          (0, 0, 0), -1)
        spans = ImagePreprocessor.detect_line_spans(page)
        self.assertEqual(len(spans), 8)
        self.assertTrue(all(any(top <= 97 + index * 130 < bottom
                                for top, bottom in spans)
                            for index in range(8)))

    def test_local_projection_selects_one_extra_row_only_on_tall_dense_page(self):
        old = [(index * 90, (index + 1) * 90) for index in range(18)]
        extra = old + [(1620, 1710)]
        self.assertTrue(ImagePreprocessor._prefer_local_lines(old, extra, 1858))
        self.assertFalse(ImagePreprocessor._prefer_local_lines(old, extra, 1251))
        self.assertFalse(ImagePreprocessor._prefer_local_lines(old[:3], old[:4], 1858))

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
