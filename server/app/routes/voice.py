"""Short offline voice commands for phones without Android SpeechRecognizer."""

import asyncio
import io
import json
import wave
from functools import lru_cache
from typing import Literal

from fastapi import APIRouter, File, HTTPException, UploadFile

from server.config import settings
from server.app.utils.logger import get_logger

router = APIRouter(prefix="/api/v1/voice", tags=["voice"])
logger = get_logger(__name__)

MAX_WAV_BYTES = 400_000  # About 12 seconds of 16-kHz mono PCM.
GRAMMAR = [
    "воспроизвести", "включи", "продолжи", "слушать",
    "пауза", "останови", "стоп",
    "следующий", "следующий фрагмент", "дальше",
    "предыдущий", "предыдущий фрагмент", "назад",
    "повтори формулу", "повторить формулу", "формулу ещё раз",
    "разбери формулу", "объясни формулу", "покажи формулу",
    "главная", "домой", "библиотека", "настройки", "камера", "открой камеру",
    "галерея", "сделай фото", "сфотографируй", "снимок", "отмена", "закрыть",
    "помощь", "список команд", "начать", "новая лекция", "добавить лекцию",
    "исправить текст", "редактировать", "сохранить", "сохранить настройки",
    "замени текст", "диктовать текст", "последний фрагмент", "первый фрагмент",
    "удали фрагмент", "верни фрагмент",
    "закладка", "закладки", "все заметки", "быстрее", "медленнее", "оформление", "доступность",
    "озвучивание", "голосовое управление", "подключение",
    "светлая тема", "тёмная тема", "высокая контрастность", "текст крупнее", "текст мельче",
    "вверх", "вниз", "прокрути вверх", "прокрути вниз", "хватит", "выключи голос", "заверши управление",
    "[unk]",
]
NUMBER_WORDS = ["один", "два", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять", "десять",
                "одиннадцать", "двенадцать", "тринадцать", "четырнадцать", "пятнадцать", "шестнадцать",
                "семнадцать", "восемнадцать", "девятнадцать", "двадцать"]
NUMBER_WORDS += [f"{ten}{' ' + unit if unit else ''}" for ten in ("двадцать", "тридцать", "сорок", "пятьдесят", "шестьдесят", "семьдесят", "восемьдесят", "девяносто") for unit in ["", *NUMBER_WORDS[:9]]][1:]
GRAMMAR.extend(f"{prefix} {number}" for prefix in ("открой лекцию", "лекция", "фрагмент") for number in NUMBER_WORDS)


@lru_cache(maxsize=1)
def _model():
    if not settings.VOICE_MODEL_DIR.is_dir():
        raise FileNotFoundError("Русская модель Vosk не установлена на сервере")
    from vosk import Model, SetLogLevel  # Optional dependency: only needed for this fallback.

    logger.info("voice stage=model_load path=%s", settings.VOICE_MODEL_DIR)
    SetLogLevel(-1)
    return Model(str(settings.VOICE_MODEL_DIR))


def _recognize(pcm: bytes, dictation: bool = False) -> str:
    from vosk import KaldiRecognizer

    # Free-form recognition is reserved for explicit transcript dictation.
    # Commands keep the restricted grammar to reduce accidental actions.
    if dictation:
        recognizer = KaldiRecognizer(_model(), 16_000)
    else:
        recognizer = KaldiRecognizer(_model(), 16_000, json.dumps(GRAMMAR, ensure_ascii=False))
    parts = []
    for offset in range(0, len(pcm), 8000):
        if recognizer.AcceptWaveform(pcm[offset:offset + 8000]):
            parts.append(json.loads(recognizer.Result()).get("text", ""))
    parts.append(json.loads(recognizer.FinalResult()).get("text", ""))
    return " ".join(part for part in parts if part).strip()


@router.get("/availability")
async def availability():
    """Readiness without loading the model into memory."""
    try:
        import vosk  # noqa: F401
        ready = settings.VOICE_MODEL_DIR.is_dir()
    except ImportError:
        ready = False
    return {"available": ready}


@router.post("/command")
async def command(
    file: UploadFile = File(...), mode: Literal["command", "dictation"] = "command"
):
    if file.content_type not in ("audio/wav", "audio/x-wav", "audio/wave", "application/octet-stream"):
        raise HTTPException(415, "Нужна короткая запись WAV")
    raw = await file.read(MAX_WAV_BYTES + 1)
    if len(raw) > MAX_WAV_BYTES:
        raise HTTPException(413, "Команда слишком длинная; говорите не более 10 секунд")
    try:
        with wave.open(io.BytesIO(raw), "rb") as wav:
            if (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) != (1, 2, 16_000):
                raise HTTPException(422, "Запись должна быть WAV: 16 кГц, моно, 16 бит")
            if wav.getnframes() < 1600:
                raise HTTPException(422, "Запись слишком короткая")
            pcm = wav.readframes(wav.getnframes())
    except (wave.Error, EOFError) as error:
        raise HTTPException(422, "Не удалось прочитать запись WAV") from error
    if not settings.VOICE_MODEL_DIR.is_dir():
        raise HTTPException(503, "На ноутбуке ещё не установлена русская модель голосовых команд Vosk")
    try:
        if mode == "dictation":
            text = await asyncio.to_thread(_recognize, pcm, True)
        else:
            text = await asyncio.to_thread(_recognize, pcm)
    except ImportError as error:
        raise HTTPException(503, "На ноутбуке не установлен пакет Vosk") from error
    except Exception as error:
        logger.exception("voice stage=recognition_failed")
        raise HTTPException(503, "Не удалось распознать команду на ноутбуке") from error
    if mode == "dictation":
        logger.info("voice stage=dictation chars=%d", len(text))
    else:
        logger.info("voice stage=recognized text=%r", text)
    return {"text": text}
