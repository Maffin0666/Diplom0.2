import unittest

from scripts.ocr_evaluation import score_text
from server.app.services.content_classifier import ContentClassifier


class EvaluationTests(unittest.TestCase):
    def test_noisy_short_line_cannot_disable_handwriting_fallback(self):
        self.assertFalse(ContentClassifier.is_math_block("&u сенок 8 мuecce <расuиж"))
        self.assertTrue(ContentClassifier.is_math_block("Пример: y = x^2 + 3x - 5"))

    def test_foreign_garbage_and_digits_are_counted(self):
        score = score_text("русский текст", "русский ABC 123 текст")
        self.assertEqual(score["word_edits"], 2)
        self.assertGreater(score["cer"], 0)

    def test_missing_text_cannot_score_as_correct(self):
        self.assertEqual(score_text("два слова", "")["wer"], 1)
        self.assertGreater(score_text("два слова", "два � слова")["wer"], 0)

    def test_case_and_punctuation_do_not_inflate_text_errors(self):
        self.assertEqual(score_text("Ещё текст!", "еще текст")["cer"], 0)


if __name__ == "__main__":
    unittest.main()
