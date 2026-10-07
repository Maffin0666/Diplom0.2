"""Метрики OCR без загрузки моделей и дополнительных зависимостей."""

import os


def normalized_words(value: str) -> list[str]:
    # Иностранные буквы и цифры остаются: это тоже ошибки распознавания.
    normalized = value.casefold().replace("ё", "е")
    return "".join(char if char.isalnum() or char == "\ufffd" else " "
                   for char in normalized).split()


def edit_distance(expected: list, actual: list) -> int:
    previous = list(range(len(actual) + 1))
    for row, item in enumerate(expected, 1):
        current = [row]
        for column, other in enumerate(actual, 1):
            current.append(min(current[-1] + 1, previous[column] + 1,
                               previous[column - 1] + (item != other)))
        previous = current
    return previous[-1]


def score_text(reference: str, hypothesis: str) -> dict:
    expected, actual = normalized_words(reference), normalized_words(hypothesis)
    if not expected:
        raise ValueError("Эталонный текст пуст")
    expected_chars, actual_chars = list(" ".join(expected)), list(" ".join(actual))
    char_edits = edit_distance(expected_chars, actual_chars)
    word_edits = edit_distance(expected, actual)
    return {"cer": char_edits / len(expected_chars), "wer": word_edits / len(expected),
            "char_edits": char_edits, "reference_chars": len(expected_chars),
            "word_edits": word_edits, "reference_words": len(expected)}


def score_line_spans(expected: list[list[int]], actual: list[tuple[int, int]],
                     min_iou: float = 0.5) -> dict:
    """Отдельно оценивает геометрию строк по размеченным Y-интервалам.

    Каждую предсказанную строку можно сопоставить только с одной эталонной:
    это штрафует и пропуски, и склейку нескольких строк в одну полосу.
    """
    def valid(span: tuple[int, int] | list[int]) -> bool:
        return len(span) == 2 and span[0] < span[1]

    if not all(valid(span) for span in expected) or not all(valid(span) for span in actual):
        raise ValueError("Каждая строка должна иметь границы [top, bottom], top < bottom")
    if not 0 < min_iou <= 1:
        raise ValueError("min_iou должен быть в интервале (0, 1]")

    pairs = []
    for reference_index, (a, b) in enumerate(expected):
        for predicted_index, (c, d) in enumerate(actual):
            intersection = max(0, min(b, d) - max(a, c))
            union = max(b, d) - min(a, c)
            overlap = intersection / union if union else 0.0
            if overlap >= min_iou:
                pairs.append((overlap, reference_index, predicted_index))
    used_reference, used_prediction = set(), set()
    for _, reference_index, predicted_index in sorted(pairs, reverse=True):
        if reference_index not in used_reference and predicted_index not in used_prediction:
            used_reference.add(reference_index)
            used_prediction.add(predicted_index)
    true_positive = len(used_reference)
    precision = true_positive / len(actual) if actual else 0.0
    recall = true_positive / len(expected) if expected else 0.0
    return {"precision": precision, "recall": recall,
            "f1": 2 * precision * recall / (precision + recall)
            if precision + recall else 0.0,
            "matched": true_positive, "missed": len(expected) - true_positive,
            "extra": len(actual) - true_positive}


def score_line_boxes(expected: list[list[int]], actual: list[list[int]],
                     min_iou: float = 0.3) -> dict:
    """Score two-dimensional line regions on pages with overlapping columns.

    A wide predicted band can match at most one narrow reference row. The
    lower IoU threshold allows for a full-width prediction covering one of
    two columns, while still penalizing merged rows and false detections.
    """
    def valid(box: list[int]) -> bool:
        return len(box) == 4 and box[0] < box[2] and box[1] < box[3]

    if not all(valid(box) for box in expected) or not all(valid(box) for box in actual):
        raise ValueError("Каждая область должна иметь границы [left, top, right, bottom]")
    if not 0 < min_iou <= 1:
        raise ValueError("min_iou должен быть в интервале (0, 1]")
    pairs = []
    for reference_index, (ax0, ay0, ax1, ay1) in enumerate(expected):
        area_a = (ax1 - ax0) * (ay1 - ay0)
        for predicted_index, (bx0, by0, bx1, by1) in enumerate(actual):
            intersection = max(0, min(ax1, bx1) - max(ax0, bx0)) * max(
                0, min(ay1, by1) - max(ay0, by0))
            area_b = (bx1 - bx0) * (by1 - by0)
            overlap = intersection / (area_a + area_b - intersection)
            if overlap >= min_iou:
                pairs.append((overlap, reference_index, predicted_index))
    used_reference, used_prediction = set(), set()
    for _, reference_index, predicted_index in sorted(pairs, reverse=True):
        if reference_index not in used_reference and predicted_index not in used_prediction:
            used_reference.add(reference_index)
            used_prediction.add(predicted_index)
    matched = len(used_reference)
    precision = matched / len(actual) if actual else 0.0
    recall = matched / len(expected) if expected else 0.0
    return {"precision": precision, "recall": recall,
            "f1": 2 * precision * recall / (precision + recall)
            if precision + recall else 0.0,
            "matched": matched, "missed": len(expected) - matched,
            "extra": len(actual) - matched}


def peak_rss_mib() -> float:
    """Пиковый рабочий набор процесса, включая нативные библиотеки Torch."""
    if os.name == "nt":
        import ctypes
        from ctypes import wintypes

        class Counters(ctypes.Structure):
            _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD)] + [
                (name, ctypes.c_size_t) for name in (
                    "PeakWorkingSetSize", "WorkingSetSize", "QuotaPeakPagedPoolUsage",
                    "QuotaPagedPoolUsage", "QuotaPeakNonPagedPoolUsage", "QuotaNonPagedPoolUsage",
                    "PagefileUsage", "PeakPagefileUsage",
                )
            ]

        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.GetCurrentProcess.restype = wintypes.HANDLE
        psapi = ctypes.WinDLL("psapi", use_last_error=True)
        psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.POINTER(Counters), wintypes.DWORD]
        counters = Counters()
        counters.cb = ctypes.sizeof(counters)
        if not psapi.GetProcessMemoryInfo(kernel.GetCurrentProcess(), ctypes.byref(counters), counters.cb):
            raise ctypes.WinError(ctypes.get_last_error())
        return counters.PeakWorkingSetSize / 1024**2
    import resource
    import sys
    peak = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return peak / (1024**2 if sys.platform == "darwin" else 1024)
