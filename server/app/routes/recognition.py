"""
Основные эндпоинты для распознавания текста и формул.

POST /api/recognize — загрузка изображения, запуск обработки
GET  /api/status/{task_id} — проверка статуса задачи
GET  /api/result/{task_id} — получение результата
GET  /api/audio/{task_id} — скачивание аудиофайла
DELETE /api/task/{task_id} — удаление задачи и файлов
"""

import uuid
import asyncio
import shutil
from pathlib import Path

from fastapi import APIRouter, UploadFile, File, BackgroundTasks, HTTPException, Depends
from fastapi.responses import FileResponse

from server.app.models import RecognitionResult, TaskStatusResponse, TaskStatus
from server.app.services.image_preprocessing import ImagePreprocessor
from server.app.services.text_recognition import TextRecognizer
from server.app.services.formula_recognition import FormulaRecognizer
from server.app.services.formula_to_speech import FormulaToSpeech
from server.app.services.tts_engine import TTSEngine
from server.app.services.audio_builder import AudioBuilder
from server.config import Settings, get_settings
from server.app.utils.logger import logger

router = APIRouter(prefix="/api", tags=["recognition"])

# --- Хранилище задач (в памяти; для ВКР этого достаточно) ---
# В продакшене — Redis / PostgreSQL
tasks_store: dict[str, dict] = {}


def get_preprocessor(settings: Settings = Depends(get_settings)) -> ImagePreprocessor:
    return ImagePreprocessor(max_side=settings.IMAGE_MAX_SIDE)


def get_text_recognizer(settings: Settings = Depends(get_settings)) -> TextRecognizer:
    return TextRecognizer(languages=settings.OCR_LANGUAGES, use_gpu=settings.OCR_USE_GPU)


def get_formula_recognizer() -> FormulaRecognizer:
    return FormulaRecognizer()


def get_formula_to_speech() -> FormulaToSpeech:
    return FormulaToSpeech()


def get_tts_engine(settings: Settings = Depends(get_settings)) -> TTSEngine:
    return TTSEngine(
        engine_type=settings.TTS_ENGINE,
        language=settings.TTS_LANGUAGE,
        rate=settings.TTS_RATE,
        volume=settings.TTS_VOLUME,
        speaker=settings.TTS_SPEAKER
    )


def get_audio_builder() -> AudioBuilder:
    return AudioBuilder()


# ============================================================
# Эндпоинт: загрузка изображения и запуск распознавания
# ============================================================

@router.post("/recognize", response_model=TaskStatusResponse)
async def recognize_image(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(..., description="Изображение конспекта/доски"),
    settings: Settings = Depends(get_settings)
):
    """
    Загружает изображение и запускает асинхронное распознавание.

    Поддерживаемые форматы: JPEG, PNG, BMP, TIFF.

    Returns:
        TaskStatusResponse с task_id для отслеживания прогресса
    """
    # Валидация типа файла
    allowed_types = {"image/jpeg", "image/png", "image/bmp", "image/tiff", "image/webp"}
    if file.content_type not in allowed_types:
        raise HTTPException(
            status_code=400,
            detail=f"Неподдерживаемый формат. Допустимые: {', '.join(allowed_types)}"
        )

    # Проверка размера
    content = await file.read()
    if len(content) > settings.MAX_UPLOAD_SIZE:
        raise HTTPException(
            status_code=413,
            detail=f"Файл слишком большой. Максимум: {settings.MAX_UPLOAD_SIZE // (1024*1024)} МБ"
        )

    # Генерируем ID задачи
    task_id = str(uuid.uuid4())[:12]
    logger.info(f"Новая задача: {task_id}, файл: {file.filename}, размер: {len(content)} байт")

    # Сохраняем изображение во временную директорию
    temp_dir = settings.TEMP_DIR / task_id
    temp_dir.mkdir(parents=True, exist_ok=True)

    # Определяем расширение
    ext = Path(file.filename).suffix if file.filename else ".jpg"
    if not ext:
        ext = ".jpg"
    image_path = temp_dir / f"input{ext}"

    with open(image_path, "wb") as f:
        f.write(content)

    logger.debug(f"Изображение сохранено: {image_path}")

    # Инициализируем запись задачи
    tasks_store[task_id] = {
        "status": TaskStatus.PENDING,
        "progress": 0.0,
        "message": "Задача в очереди",
        "image_path": str(image_path),
        "result": None,
        "error": None
    }

    # Запускаем обработку в фоне
    background_tasks.add_task(
        process_recognition_task,
        task_id=task_id,
        image_path=str(image_path),
        settings=settings
    )

    return TaskStatusResponse(
        task_id=task_id,
        status=TaskStatus.PENDING,
        progress=0.0,
        message="Задача принята, обработка начинается..."
    )


# ============================================================
# Фоновая задача: полный пайплайн обработки
# ============================================================

async def process_recognition_task(task_id: str, image_path: str, settings: Settings):
    """
    Полный пайплайн обработки изображения:
    1. Предобработка изображения
    2. Распознавание текста (EasyOCR)
    3. Определение формул
    4. Конвертация формул в речь
    5. Синтез аудио (TTS)
    6. Сборка финального MP3 с метками
    """
    try:
        # --- Этап 1: Предобработка ---
        _update_task(task_id, TaskStatus.PREPROCESSING, 10.0, "Предобработка изображения...")
        logger.info(f"[{task_id}] Этап 1: Предобработка")

        preprocessor = ImagePreprocessor(max_side=settings.IMAGE_MAX_SIDE)

        # Запускаем CPU-bound операцию в пуле потоков
        loop = asyncio.get_event_loop()
        processed_image = await loop.run_in_executor(
            None, preprocessor.preprocess, image_path
        )

        _update_task(task_id, TaskStatus.PREPROCESSING, 20.0, "Изображение обработано")

        # --- Этап 2: Распознавание текста ---
        _update_task(task_id, TaskStatus.RECOGNIZING, 25.0, "Распознавание текста...")
        logger.info(f"[{task_id}] Этап 2: OCR")

        text_recognizer = TextRecognizer(
            languages=settings.OCR_LANGUAGES,
            use_gpu=settings.OCR_USE_GPU
        )

        ocr_results = await loop.run_in_executor(
            None, text_recognizer.recognize, processed_image
        )

        if not ocr_results:
            _update_task(task_id, TaskStatus.ERROR, 100.0,
                        "Текст не обнаружен на изображении")
            tasks_store[task_id]["error"] = "Текст не обнаружен"
            logger.warning(f"[{task_id}] Текст не обнаружен")
            return

        # Собираем полный текст
        full_text = text_recognizer.get_full_text(ocr_results)
        logger.info(f"[{task_id}] Распознано {len(ocr_results)} блоков, {len(full_text)} символов")

        _update_task(task_id, TaskStatus.RECOGNIZING, 50.0,
                    f"Распознано {len(ocr_results)} текстовых блоков")

        # --- Этап 3: Обнаружение и обработка формул ---
        logger.info(f"[{task_id}] Этап 3: Обработка формул")

        formula_recognizer = FormulaRecognizer()
        formula_converter = FormulaToSpeech()

        # Разбиваем текст на сегменты для TTS
        segments_data = []
        lines = full_text.split("\n")

        for line in lines:
            line = line.strip()
            if not line:
                continue

            if formula_recognizer.is_formula(line):
                # Это формула — конвертируем для озвучки
                latex = formula_recognizer._text_to_latex(line)
                speech_text = formula_converter.convert(latex if latex else line)

                if not speech_text or speech_text.strip() == "":
                    speech_text = line

                segments_data.append({
                    "text": speech_text,
                    "display_text": line,
                    "is_formula": True,
                    "original": line
                })
                logger.debug(f"[{task_id}] Формула: '{line}' → '{speech_text}'")
            else:
                # Обычный текст
                segments_data.append({
                    "text": line,
                    "display_text": line,
                    "is_formula": False,
                    "original": None
                })

        _update_task(task_id, TaskStatus.SYNTHESIZING, 60.0,
                    f"Синтез речи ({len(segments_data)} сегментов)...")

        # --- Этап 4: Синтез речи и сборка аудио ---
        logger.info(f"[{task_id}] Этап 4: TTS + сборка аудио")

        tts_engine = TTSEngine(
            engine_type=settings.TTS_ENGINE,
            language=settings.TTS_LANGUAGE,
            rate=settings.TTS_RATE,
            volume=settings.TTS_VOLUME,
            speaker=settings.TTS_SPEAKER
        )

        audio_builder = AudioBuilder()

        output_dir = str(settings.OUTPUT_DIR)
        audio_path, timestamped_segments, total_duration = await loop.run_in_executor(
            None,
            audio_builder.build,
            segments_data,
            tts_engine,
            output_dir,
            task_id
        )

        # --- Формируем результат ---
        audio_url = f"/api/audio/{task_id}"

        result = RecognitionResult(
            task_id=task_id,
            status=TaskStatus.COMPLETED,
            recognized_text=full_text,
            segments=timestamped_segments,
            audio_url=audio_url,
            audio_duration=total_duration,
            error_message=None
        )

        tasks_store[task_id]["result"] = result
        _update_task(task_id, TaskStatus.COMPLETED, 100.0, "Обработка завершена")

        logger.info(f"[{task_id}] ✅ Готово! Аудио: {total_duration:.1f}с, сегментов: {len(timestamped_segments)}")

    except Exception as e:
        logger.error(f"[{task_id}] ❌ Ошибка обработки: {e}", exc_info=True)
        _update_task(task_id, TaskStatus.ERROR, 100.0, f"Ошибка: {str(e)}")
        tasks_store[task_id]["error"] = str(e)


def _update_task(task_id: str, status: TaskStatus, progress: float, message: str):
    """Обновление статуса задачи в хранилище"""
    if task_id in tasks_store:
        tasks_store[task_id]["status"] = status
        tasks_store[task_id]["progress"] = progress
        tasks_store[task_id]["message"] = message
        logger.debug(f"[{task_id}] Статус: {status.value} ({progress:.0f}%) — {message}")


# ============================================================
# Эндпоинт: проверка статуса задачи
# ============================================================

@router.get("/status/{task_id}", response_model=TaskStatusResponse)
async def get_task_status(task_id: str):
    """
    Возвращает текущий статус обработки.
    Клиент должен опрашивать этот эндпоинт до получения COMPLETED или ERROR.
    """
    if task_id not in tasks_store:
        raise HTTPException(status_code=404, detail="Задача не найдена")

    task = tasks_store[task_id]
    return TaskStatusResponse(
        task_id=task_id,
        status=task["status"],
        progress=task["progress"],
        message=task["message"]
    )


# ============================================================
# Эндпоинт: получение результата
# ============================================================

@router.get("/result/{task_id}", response_model=RecognitionResult)
async def get_task_result(task_id: str):
    """
    Возвращает полный результат распознавания.
    Доступен только после завершения обработки (статус COMPLETED).
    """
    if task_id not in tasks_store:
        raise HTTPException(status_code=404, detail="Задача не найдена")

    task = tasks_store[task_id]

    if task["status"] == TaskStatus.ERROR:
        return RecognitionResult(
            task_id=task_id,
            status=TaskStatus.ERROR,
            error_message=task.get("error", "Неизвестная ошибка")
        )

    if task["status"] != TaskStatus.COMPLETED:
        raise HTTPException(
            status_code=202,
            detail=f"Обработка ещё не завершена. Статус: {task['status'].value}, прогресс: {task['progress']}%"
        )

    result = task.get("result")
    if result is None:
        raise HTTPException(status_code=500, detail="Результат потерян")

    return result


# ============================================================
# Эндпоинт: скачивание аудио
# ============================================================

@router.get("/audio/{task_id}")
async def get_audio(task_id: str, settings: Settings = Depends(get_settings)):
    """
    Возвращает MP3-файл с озвученной лекцией.
    """
    if task_id not in tasks_store:
        raise HTTPException(status_code=404, detail="Задача не найдена")

    audio_path = settings.OUTPUT_DIR / f"{task_id}.mp3"

    if not audio_path.exists():
        raise HTTPException(status_code=404, detail="Аудиофайл не найден")

    return FileResponse(
        path=str(audio_path),
        media_type="audio/mpeg",
        filename=f"lecture_{task_id}.mp3",
        headers={
            "Accept-Ranges": "bytes",
            "Cache-Control": "public, max-age=3600"
        }
    )


# ============================================================
# Эндпоинт: удаление задачи и связанных файлов
# ============================================================

@router.delete("/task/{task_id}")
async def delete_task(task_id: str, settings: Settings = Depends(get_settings)):
    """
    Удаляет задачу и все связанные файлы (изображение, аудио).
    """
    if task_id not in tasks_store:
        raise HTTPException(status_code=404, detail="Задача не найдена")

    # Удаляем временные файлы
    temp_dir = settings.TEMP_DIR / task_id
    if temp_dir.exists():
        shutil.rmtree(temp_dir, ignore_errors=True)

    # Удаляем аудио
    audio_path = settings.OUTPUT_DIR / f"{task_id}.mp3"
    if audio_path.exists():
        audio_path.unlink()

    # Удаляем из хранилища
    del tasks_store[task_id]

    logger.info(f"Задача {task_id} удалена")
    return {"message": f"Задача {task_id} удалена", "task_id": task_id}


# ============================================================
# Эндпоинт: список всех задач
# ============================================================

@router.get("/tasks")
async def list_tasks():
    """
    Возвращает список всех задач (для отладки и истории).
    """
    tasks = []
    for task_id, task_data in tasks_store.items():
        tasks.append({
            "task_id": task_id,
            "status": task_data["status"].value,
            "progress": task_data["progress"],
            "message": task_data["message"]
        })
    return {"tasks": tasks, "count": len(tasks)}