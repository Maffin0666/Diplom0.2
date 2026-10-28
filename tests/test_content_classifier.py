"""False mathematical labels make normal handwriting unpleasant to hear."""

import unittest

from server.app.services.content_classifier import ContentClassifier


class ContentClassifierTests(unittest.TestCase):
    def test_ocr_noise_in_prose_is_not_formula(self):
        for text in (
            "Шрифт, которым япишу-сейчас, был сделан в процессе-красниских руки.",
            "Рнo Lnu поз9на 9 ~нолiсоезо",
            "&opayaл еиирфсх Mrtia € ? сИи 0тLdуVлили 'сэРсиз ^о/Фми",
            "По запуску кода на исполнение полной З.",
            "Виды тестирования: / программное обеспечение",
            "Система = управление процессами",
        ):
            with self.subTest(text=text):
                self.assertFalse(ContentClassifier.is_math_block(text))

    def test_actual_math_remains_formula(self):
        for text in (
            "lim f(x) = f(x0)",
            "y = x^2 + 3x - 5",
            "\\frac{a+b}{c}",
            "x/2",
            "∫ x dx",
            "f(x)",
        ):
            with self.subTest(text=text):
                self.assertTrue(ContentClassifier.is_math_block(text))


if __name__ == "__main__":
    unittest.main()
