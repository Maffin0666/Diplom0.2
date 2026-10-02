"""Ограниченный синтаксический разбор формул для русской озвучки.

Поддерживаемые операции разобраны по приоритету. Неизвестные команды и символы
произносятся явно, чтобы OCR-ошибка не превращалась в незаметную потерю данных.
"""

import re

from .speech_normalizer import number_to_words, normalize_prose


TOKEN = re.compile(r"\\[A-Za-z]+|\d+(?:[.,]\d+)?|[A-Za-zА-Яа-яЁё]+|<=|>=|!=|->|\s+|.", re.DOTALL)
GREEK = {"alpha": "альфа", "beta": "бета", "gamma": "гамма", "delta": "дельта", "epsilon": "эпсилон", "theta": "тета", "lambda": "лямбда", "mu": "мю", "pi": "пи", "rho": "ро", "sigma": "сигма", "phi": "фи", "omega": "омега"}
UNICODE = {"α": "альфа", "β": "бета", "γ": "гамма", "δ": "дельта", "ε": "эпсилон", "θ": "тета", "λ": "лямбда", "μ": "мю", "π": "пи", "ρ": "ро", "σ": "сигма", "φ": "фи", "ω": "омега", "∞": "бесконечность"}
MATH_LATIN = {"a": "а", "b": "бэ", "c": "цэ", "d": "дэ", "e": "е", "f": "эф", "g": "гэ", "h": "аш", "i": "и", "j": "йот", "k": "ка", "l": "эль", "m": "эм", "n": "эн", "o": "о", "p": "пэ", "q": "ку", "r": "эр", "s": "эс", "t": "тэ", "u": "у", "v": "вэ", "w": "дубль вэ", "x": "икс", "y": "игрек", "z": "зет"}
FUNCTIONS = {"sin": "синус", "cos": "косинус", "tan": "тангенс", "tg": "тангенс", "cot": "котангенс", "ctg": "котангенс", "log": "логарифм", "ln": "натуральный логарифм"}
OPERATORS = {"=": (10, "равно"), "≠": (10, "не равно"), "!=": (10, "не равно"), "<": (10, "меньше"), ">": (10, "больше"), "≤": (10, "меньше либо равно"), "≥": (10, "больше либо равно"), "<=": (10, "меньше либо равно"), ">=": (10, "больше либо равно"), "≈": (10, "приблизительно равно"), "->": (10, "стремится к"), "+": (20, "плюс"), "-": (20, "минус"), "−": (20, "минус"), "*": (30, "умножить на"), "·": (30, "умножить на"), "×": (30, "умножить на"), "/": (30, "дробь"), "÷": (30, "делить на"), ":": (30, "делить на"), "^": (40, "степень")}
COMMAND_OPS = {"\\le": "≤", "\\leq": "≤", "\\ge": "≥", "\\geq": "≥", "\\neq": "≠", "\\ne": "≠", "\\approx": "≈", "\\cdot": "·", "\\times": "×", "\\div": "÷", "\\to": "->", "\\rightarrow": "->"}


def normalize_ocr_math(text: str) -> str:
    """Исправляет только короткие, характерные для OCR записи операций."""
    value = re.sub(r"(?<!\S)\$(?=\s*=)", "S", text)
    value = re.sub(r"\b([a-zA-Z])l([a-zA-Z])\b", r"\1/\2", value)
    return re.sub(r"(?<!\w)[Зз](?=[xх]\b)", "3", value)


def _symbol(word: str) -> str:
    if word in UNICODE:
        return UNICODE[word]
    if word.lower() in GREEK:
        return GREEK[word.lower()]
    if word.lower() in ("x", "х"):
        return "икс"
    if word.lower() in ("y", "у"):
        return "игрек"
    if word.isdigit():
        return number_to_words(int(word))
    if re.fullmatch(r"\d+[,.]\d+", word):
        return normalize_prose(word)
    if word.isascii() and word.isalpha():
        return " ".join(MATH_LATIN[letter.lower()] for letter in word)
    return word


def _fraction(top: str, bottom: str) -> str:
    if " " not in top and " " not in bottom and ";" not in top + bottom:
        return f"дробь {top} на {bottom}"
    return f"дробь: числитель {top}; знаменатель {bottom}; конец дроби"


class _Parser:
    def __init__(self, text: str):
        self.tokens = [match.group() for match in TOKEN.finditer(text) if not match.group().isspace()]
        self.position = 0

    def peek(self) -> str:
        return self.tokens[self.position] if self.position < len(self.tokens) else ""

    def take(self) -> str:
        token = self.peek()
        if token:
            self.position += 1
        return token

    def group(self, opener: str = "{", closer: str = "}") -> str:
        if self.peek() != opener:
            return self.atom()
        self.take()
        value = self.expression(0, {closer})
        if self.peek() != closer:
            raise ValueError("Незакрытая скобка")
        self.take()
        return value

    def atom(self) -> str:
        token = self.take()
        if not token:
            raise ValueError("Ожидался операнд")
        if token in ("{", "(", "["):
            closer = {"{": "}", "(": ")", "[": "]"}[token]
            inside = self.expression(0, {closer})
            if self.peek() != closer:
                raise ValueError("Незакрытая скобка")
            self.take()
            return inside
        if token in ("-", "−", "+"):
            return ("минус " if token != "+" else "плюс ") + self.expression(35, {"}", ")", "]"})
        if token in ("\\frac", "\\dfrac", "\\tfrac"):
            top = self.group()
            bottom = self.group()
            return _fraction(top, bottom)
        if token in ("\\sqrt", "sqrt", "√"):
            degree = self.group("[", "]") if self.peek() == "[" else None
            argument = self.group("(", ")") if self.peek() == "(" else self.group()
            return f"корень степени {degree} из {argument}; конец корня" if degree else f"корень из {argument}; конец корня"
        if token in ("\\int", "∫", "int", "\\sum", "∑", "sum"):
            name = "интеграл" if token in ("\\int", "∫", "int") else "сумма"
            bounds = self._bounds()
            return name + bounds
        if token in ("\\lim", "lim"):
            bounds = self._bounds()
            return "предел" + bounds
        command = token[1:] if token.startswith("\\") else token
        if command.lower() == "f" and self.peek() == "(":
            return "эф от " + self.group("(", ")")
        if command.lower() in FUNCTIONS:
            argument = self.group("(", ")") if self.peek() == "(" else self.group()
            return f"{FUNCTIONS[command.lower()]} от {argument}"
        if token.startswith("\\"):
            if command.lower() in GREEK:
                return GREEK[command.lower()]
            return _symbol(command)
        if token in UNICODE or token.isalnum() or re.fullmatch(r"\d+[,.]\d+", token):
            return _symbol(token)
        return {"~": "примерно", "$": "", "|": "модуль"}.get(token, "")

    def _bounds(self) -> str:
        lower = upper = None
        for _ in range(2):
            if self.peek() == "_":
                self.take()
                lower = self.group()
            elif self.peek() == "^":
                self.take()
                upper = self.group()
        if lower is not None and upper is not None:
            # Для распространённых целых пределов используем правильный падеж.
            forms = {"ноль": "нуля", "один": "одного", "два": "двух", "три": "трёх"}
            return f" от {forms.get(lower, lower)} до {forms.get(upper, upper)}"
        if lower is not None:
            return f" при {lower}"
        if upper is not None:
            return f" до {upper}"
        return ""

    def expression(self, min_precedence: int = 0, stop: set[str] | None = None) -> str:
        stop = stop or set()
        left = self.atom()
        while self.peek() and self.peek() not in stop:
            token = self.peek()
            if token in ("_", "^"):
                precedence = 40
                if precedence < min_precedence:
                    break
                self.take()
                right = self.group() if token == "_" or self.peek() == "{" else self.expression(40, stop)
                if token == "_":
                    left = f"{left} с индексом {right}"
                elif right == "два":
                    left = f"{left} в квадрате"
                elif right == "три":
                    left = f"{left} в кубе"
                else:
                    left = f"{left} в степени: {right}; конец степени"
                continue
            op = COMMAND_OPS.get(token, token)
            if op in OPERATORS:
                precedence, spoken = OPERATORS[op]
                if precedence < min_precedence:
                    break
                self.take()
                right = self.expression(precedence + 1, stop)
                if op == "/":
                    left = _fraction(left, right)
                else:
                    left = f"{left} {spoken} {right}"
                continue
            if token in ("}", ")", "]", ",", ";"):
                break
            # Соседство 2x и (a+b)(c+d) означает умножение.
            precedence = 30
            if precedence < min_precedence:
                break
            right = self.expression(precedence + 1, stop)
            if left.startswith(("интеграл", "сумма", "предел")):
                left = f"{left} {right}"
            else:
                left = f"{left} умножить на {right}"
        return left

    def parse(self) -> str:
        parts = []
        while self.peek():
            before = self.position
            part = self.expression()
            if part:
                parts.append(part)
            if self.position == before:
                raise ValueError("Разбор остановился")
            if self.peek() in (",", ";"):
                self.take()
        return "; ".join(parts)


def convert_math(text: str) -> str:
    """Озвучивает формулу; при синтаксической ошибке читает токены явно."""
    value = text.strip()
    if value.startswith("$") and value.endswith("$") and len(value) > 2:
        value = value[1:-1].strip()
    value = normalize_ocr_math(value)
    if not value:
        return "пауза"
    sum_bounds = re.fullmatch(r"(?i)сумма\s+от\s+([a-zа-я])\s*=\s*(\d+)\s+до\s+([a-zа-я])", value)
    if sum_bounds:
        index, lower, upper = sum_bounds.groups()
        return f"Сумма от {_symbol(index)} равно {number_to_words(int(lower))} до {_symbol(upper)}"
    # Подпись перед двоеточием остается обычной речью.
    match = re.match(r"^([А-Яа-яЁё][А-Яа-яЁё\s]{2,}):\s*(.+)$", value)
    prefix = normalize_prose(match.group(1)) + ": " if match else ""
    if match:
        value = match.group(2)
    value = value.replace("\\left", "").replace("\\right", "")
    # У TrOCR короткие индексы часто записаны слитно: x0, y1.
    value = re.sub(r"(?<![A-Za-z])([xyхуXYХУ])([0-9])\b", r"\1_\2", value)
    try:
        spoken = _Parser(value).parse()
    except (ValueError, RecursionError):
        # Ошибку разбора оставляем в исходном text, в речь отправляем только
        # понятные слова и операции без технических диагностических фраз.
        spoken = " ".join(
            _symbol(token[1:]) if token.startswith("\\") else
            _symbol(token) if token.isalnum() else
            OPERATORS[token][1] if token in OPERATORS else ""
            for token in _Parser(value).tokens
        )
    return re.sub(r"\s+", " ", prefix + spoken).strip()
