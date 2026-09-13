"""Быстрая проверка конвертации формул без запуска сервера"""
import sys
sys.path.insert(0, 'server')

from server.app import FormulaToSpeech

converter = FormulaToSpeech()

test_cases = [
    "f(x) = x^2 + 3x - 5",
    "y = sin(x) + cos(x)",
    "S = a/b",
    r"\frac{a+b}{c-d}",
    r"\sqrt{x^2 + y^2}",
    r"\int_{0}^{1} x^2 dx",
    r"\sum_{i=1}^{n} a_i",
    "log(x) = 2",
    "a + b = c",
    "F(x, y) = x^2 - y^2",
]

for formula in test_cases:
    result = converter.convert(formula)
    print(f"📝 {formula}")
    print(f"🔊 {result}\n")