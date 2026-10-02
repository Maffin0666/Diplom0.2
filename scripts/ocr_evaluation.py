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
