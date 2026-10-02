"""Проверяем чтение формул и сохранность текста перед синтезом речи."""

import unittest
import tempfile
from pathlib import Path
from unittest.mock import patch

from server.app.models import RecognitionStatus
from server.app.routes import recognition
from server.app.task_store import TaskStore
from server.app.services.content_classifier import ContentClassifier
from server.app.services.formula_to_speech import FormulaToSpeech
from server.app.services.math_speech import normalize_ocr_math
from server.app.services.speech_normalizer import normalize_prose
from server.app.services.text_recognition import TextRecognizer


class SpeechTests(unittest.TestCase):
    def test_math_classification(self):
        formulas = ["a/b", "x^{2}", "x0", "x ≤ y", r"\frac{a+b}{c-d}",
                    r"\int_0^1 x^2 dx", "√x", "α+β", "sin(x)"]
        for formula in formulas:
            with self.subTest(formula=formula):
                self.assertTrue(ContentClassifier.is_math_block(formula))
        for prose in ("Лекция по алгебре.", "Из-за ошибки нужен повторный снимок."):
            self.assertFalse(ContentClassifier.is_math_block(prose))
        self.assertFalse(ContentClassifier.is_math_block('[ucobor, JW% ч/ю 2 лотско / л"иt'))
        self.assertFalse(ContentClassifier.is_math_block('Рнo Lnu поз9на 9 ~нолiсоезо'))
        self.assertFalse(ContentClassifier.is_math_block('[cubcmbe Lnu Ёчпашеочая'))
        self.assertFalse(ContentClassifier.is_math_block(
            "&opayaл еиирфсх Mrtia € ? сИи 0тLdуVлили 'сэРсиз ^о/Фми LLwuиWи */1сeт"))

    def test_math_speech_exact(self):
        examples = {
            "sin(x)+cos(x)": "синус от икс плюс косинус от икс",
            "x ≤ y": "икс меньше либо равно игрек",
            r"\frac{a+b}{c-d}": "дробь: числитель а плюс бэ; знаменатель цэ минус дэ; конец дроби",
            r"\frac{1}{\frac{x+1}{2}}": "дробь: числитель один; знаменатель дробь: числитель икс плюс один; знаменатель два; конец дроби; конец дроби",
            "x^{2}": "икс в квадрате",
            "a/b": "дробь а на бэ",
            r"\sqrt[3]{x+1}": "корень степени три из икс плюс один; конец корня",
            r"\int_0^1 x^2 dx": "интеграл от нуля до одного икс в квадрате дэ икс",
            r"\alpha+\beta": "альфа плюс бета",
            "α+β": "альфа плюс бета",
            "-x^2": "минус икс в квадрате",
            "x^y^z": "икс в степени: игрек в степени: зет; конец степени; конец степени",
            "Пример: y=x^2": "Пример: игрек равно икс в квадрате",
            "f(x)=x0": "эф от икс равно икс с индексом ноль",
        }
        for formula, expected in examples.items():
            with self.subTest(formula=formula):
                self.assertEqual(FormulaToSpeech.convert(formula), expected)

    def test_uncertain_input_has_no_spoken_diagnostic_codes(self):
        for value in (r"\unknown{x}", "x+", "[cubcmbe Lnu Ёчпашеочая"):
            speech = FormulaToSpeech.convert(value)
            self.assertNotIn("неизвестный символ", speech)
            self.assertNotIn("формула распознана не полностью", speech)
        self.assertNotIn("символ номер", normalize_prose("[cubcmbe Lnu Ёчпашеочая"))

    def test_tr_ocr_only_replaces_uncertain_text(self):
        self.assertFalse(TextRecognizer.needs_trocr("непрерывной в точке х0, если предел", 0.82))
        self.assertTrue(TextRecognizer.needs_trocr("Рнo Lnu поз9на 9 ~нолiсоезо", 0.37))

    def test_printed_manifest_examples(self):
        self.assertEqual(normalize_ocr_math("Интеграл: $ = alb * sqrt(x)"),
                         "Интеграл: S = a/b * sqrt(x)")
        self.assertEqual(normalize_ocr_math("Пример: у = x^2 + Зх - 5"),
                         "Пример: у = x^2 + 3х - 5")
        self.assertEqual(FormulaToSpeech.convert("Пример: у = x^2 + Зх - 5"),
                         "Пример: игрек равно икс в квадрате плюс три умножить на икс минус пять")
        self.assertEqual(FormulaToSpeech.convert("Интеграл: $ = alb * sqrt(x)"),
                         "Интеграл: эс равно дробь а на бэ умножить на корень из икс; конец корня")
        self.assertEqual(FormulaToSpeech.convert("Сумма от i=1 до n"),
                         "Сумма от и равно один до эн")

    def test_limit_is_spoken_once_across_ocr_lines(self):
        class Recognizer:
            def recognize(self, image):
                return [
                    {"text": "Если предел", "confidence": 0.8,
                     "bbox": [[0, 0], [100, 0], [100, 20], [0, 20]]},
                    {"text": "lim f(x) = f(x0)", "confidence": 0.8,
                     "bbox": [[0, 30], [100, 30], [100, 50], [0, 50]]},
                ]

        class AudioBuilder:
            def generate_full_audio(self, chunks):
                return "/audio/test.mp3", [
                    chunk.model_copy(update={"end_time": index + 1})
                    for index, chunk in enumerate(chunks)
                ]

        with tempfile.TemporaryDirectory() as directory:
            store = TaskStore(Path(directory) / "tasks.sqlite3")
            store.create("limit")
            with patch.object(recognition.ImagePreprocessor, "preprocess_for_ocr", return_value=None):
                recognition.execute_pipeline("limit", b"image", Recognizer(), AudioBuilder(), store)
            result = store.get("limit")["response"]
        self.assertEqual(result.full_text, "Если предел\nlim f(x) = f(x0)")
        self.assertEqual(result.spoken_text, "Если предел эф от икс равно эф от икс с индексом ноль")

    def test_prose_keeps_numbers_technical_words_and_hyphens(self):
        text = normalize_prose("Python API 12,5 и физико-математический факультет.")
        self.assertEqual(text, "пайтон эй пи ай двенадцать запятая пять и физико-математический факультет.")
        self.assertEqual(normalize_prose("101 студент"), "сто один студент")
        self.assertEqual(normalize_prose("H2O №5"), "эйч два оу номер пять")
        self.assertEqual(normalize_prose("функция f(x) непрерывна"), "функция эф от икс непрерывна")
        self.assertEqual(normalize_prose("в точке х0"), "в точке икс с индексом ноль")

    def test_pipeline_uses_separate_prose_and_math_paths(self):
        class Recognizer:
            def recognize(self, image):
                return [
                    {"text": "Python API 12,5.", "confidence": 0.8,
                     "bbox": [[0, 0], [100, 0], [100, 20], [0, 20]]},
                    {"text": r"\frac{a+b}{c-d}", "confidence": 0.7,
                     "bbox": [[0, 30], [100, 30], [100, 50], [0, 50]]},
                ]

        class AudioBuilder:
            def generate_full_audio(self, chunks):
                return "/audio/test.mp3", [
                    chunk.model_copy(update={"start_time": i, "end_time": i + 1, "duration": 1})
                    for i, chunk in enumerate(chunks)
                ]

        with tempfile.TemporaryDirectory() as directory:
            store = TaskStore(Path(directory) / "tasks.sqlite3")
            store.create("stage2")
            with patch.object(recognition.ImagePreprocessor, "preprocess_for_ocr", return_value=None):
                recognition.execute_pipeline("stage2", b"image", Recognizer(), AudioBuilder(), store)
            result = store.get("stage2")["response"]
        self.assertEqual(result.status, RecognitionStatus.COMPLETED)
        self.assertEqual([chunk.content_type.value for chunk in result.chunks], ["text", "formula"])
        self.assertIn("пайтон эй пи ай двенадцать запятая пять", result.chunks[0].spoken_text)
        self.assertIn("числитель а плюс бэ", result.chunks[1].spoken_text)


if __name__ == "__main__":
    unittest.main()
