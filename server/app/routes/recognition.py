import time
import uuid
import re
from fastapi import APIRouter, UploadFile, File, BackgroundTasks, HTTPException, Request
from ..models import RecognitionResponse, RecognitionStatus, TextChunk, ContentType
from ..services.image_preprocessing import ImagePreprocessor
from ..services.semantic_chunker import SemanticChunker
from ..services.formula_to_speech import FormulaToSpeech
from ..utils.logger import get_logger

router = APIRouter(prefix="/api/v1/recognition", tags=["Recognition"])
logger = get_logger(__name__)

TASKS_DB = {}

CYR_DIGITS = {
    "0": "ноль", "1": "один", "2": "два", "3": "три", "4": "четыре",
    "5": "пять", "6": "шесть", "7": "семь", "8": "восемь", "9": "девять"
}


def sanitize_text_for_silero(text: str) -> str:
    t = re.sub(r"\b\d\b", lambda m: CYR_DIGITS.get(m.group(0), m.group(0)), text)
    lat_map = {
        'a': 'а', 'b': 'б', 'c': 'с', 'd': 'д', 'e': 'е', 'f': 'ф', 'g': 'г',
        'h': 'х', 'i': 'и', 'j': 'й', 'k': 'к', 'l': 'л', 'm': 'м', 'n': 'н',
        'o': 'о', 'p': 'р', 'r': 'р', 's': 'с', 't': 'т', 'u': 'у', 'v': 'в',
        'w': 'в', 'x': 'икс', 'y': 'игрек', 'z': 'зет'
    }
    for l_ch, r_ch in lat_map.items():
        t = re.sub(rf"\b{l_ch}\b", r_ch, t, flags=re.IGNORECASE)

    t = re.sub(r"[^а-яА-ЯёЁ0-9\s\.,!\?\-:]", " ", t)
    t = re.sub(r"\s+", " ", t).strip()
    return t if t else "пауза"


def execute_pipeline(task_id: str, file_bytes: bytes, recognizer, audio_builder):
    start_time = time.time()
    try:
        TASKS_DB[task_id]["status"] = RecognitionStatus.PROCESSING

        # 1. Мягкая нормализация CLAHE без бинаризации
        preprocessed_img = ImagePreprocessor.preprocess_for_ocr(file_bytes)

        # 2. Гибридный OCR (CRAFT + TrOCR INT8)
        raw_blocks = recognizer.recognize(preprocessed_img)

        if not raw_blocks:
            TASKS_DB[task_id]["status"] = RecognitionStatus.COMPLETED
            TASKS_DB[task_id]["response"] = RecognitionResponse(
                task_id=task_id,
                status=RecognitionStatus.COMPLETED,
                full_text="",
                spoken_text="",
                audio_url=None,
                total_duration=0.0,
                chunks=[],
                processing_time=round(time.time() - start_time, 2)
            )
            return

        # 3. Семантическое объединение строк в полные предложения и формулы
        semantic_units = SemanticChunker.aggregate_to_sentences(raw_blocks)

        prepared_chunks: list[TextChunk] = []

        # 4. Вербализация формул и подготовка к синтезу
        for idx, unit in enumerate(semantic_units):
            raw_text = unit["text"]
            is_math = unit["is_formula"]
            content_type = ContentType.FORMULA if is_math else ContentType.TEXT

            spoken = FormulaToSpeech.convert(raw_text)
            spoken_clean = sanitize_text_for_silero(spoken)

            prepared_chunks.append(TextChunk(
                id=uuid.uuid4().hex[:8],
                index=idx,
                content_type=content_type,
                text=raw_text,
                spoken_text=spoken_clean,
                is_formula=is_math,
                confidence=unit["confidence"],
                bbox=unit["bbox"],
                start_time=0.0,
                end_time=0.0,
                duration=0.0
            ))

        # 5. Чанковый синтез по предложениям
        audio_url, timed_chunks = audio_builder.generate_full_audio(prepared_chunks)

        full_raw = "\n".join(ch.text for ch in timed_chunks)
        full_spoken = " ".join(ch.spoken_text for ch in timed_chunks)
        total_duration = timed_chunks[-1].end_time if timed_chunks else 0.0

        result = RecognitionResponse(
            task_id=task_id,
            status=RecognitionStatus.COMPLETED,
            full_text=full_raw,
            spoken_text=full_spoken,
            audio_url=audio_url,
            total_duration=total_duration,
            chunks=timed_chunks,
            processing_time=round(time.time() - start_time, 2)
        )

        TASKS_DB[task_id]["status"] = RecognitionStatus.COMPLETED
        TASKS_DB[task_id]["response"] = result
        logger.info(f"Конвейер завершен за {result.processing_time} с. Предложений/блоков: {len(timed_chunks)}")

    except Exception as err:
        logger.error(f"Сбой конвейера для задачи {task_id}: {err}", exc_info=True)
        TASKS_DB[task_id]["status"] = RecognitionStatus.FAILED
        TASKS_DB[task_id]["error"] = str(err)


@router.post("/upload", response_model=dict)
async def upload_lecture_image(
    request: Request,
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...)
):
    if not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Разрешена загрузка только файлов изображений")

    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="Файл пуст")

    task_id = str(uuid.uuid4())
    TASKS_DB[task_id] = {
        "status": RecognitionStatus.PENDING,
        "response": None,
        "error": None
    }

    recognizer = request.app.state.recognizer
    audio_builder = request.app.state.audio_builder

    background_tasks.add_task(execute_pipeline, task_id, content, recognizer, audio_builder)
    return {"task_id": task_id, "status": RecognitionStatus.PENDING}


@router.get("/status/{task_id}")
async def get_task_status(task_id: str):
    if task_id not in TASKS_DB:
        raise HTTPException(status_code=404, detail="Задача не найдена")
    return {"task_id": task_id, "status": TASKS_DB[task_id]["status"]}


@router.get("/result/{task_id}", response_model=RecognitionResponse)
async def get_task_result(task_id: str):
    if task_id not in TASKS_DB:
        raise HTTPException(status_code=404, detail="Задача не найдена")

    task = TASKS_DB[task_id]
    if task["status"] == RecognitionStatus.FAILED:
        raise HTTPException(status_code=500, detail=f"Ошибка обработки: {task['error']}")
    if task["status"] != RecognitionStatus.COMPLETED:
        raise HTTPException(status_code=202, detail="Обработка в процессе")

    return task["response"]


