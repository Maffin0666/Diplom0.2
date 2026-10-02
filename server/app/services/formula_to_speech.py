"""Совместимый интерфейс преобразования формул в русскую речь."""

from .math_speech import convert_math


class FormulaToSpeech:
    @staticmethod
    def convert(text: str) -> str:
        return convert_math(text)
