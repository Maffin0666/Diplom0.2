"""API загрузки фотографии и формирования синхронизированного результата."""

from io import BytesIO
import hashlib
import time
import uuid

from fastapi import APIRouter, File, Header, HTTPException, Request, UploadFile
from PIL import Image, UnidentifiedImageError

from server.config import settings
from server.app.models import (ContentType, RecognitionResponse, RecognitionStatus,
                               TaskStatusResponse, TextChunk, UploadResponse)
from server.app.task_store import TaskStore
from server.app.services.formula_to_speech import FormulaToSpeech
from server.app.services.image_preprocessing import ImagePreprocessor
from server.app.services.semantic_chunker import SemanticChunker
from server.app.services.speech_normalizer import normalize_prose
from server.app.utils.logger import get_logger

router = APIRouter(prefix="/api/v1/recognition", tags=["Recognition"])
logger = get_logger(__name__)
SUPPORTED_FORMATS = {"JPEG", "PNG", "WEBP"}
SUPPORTED_MIME = {"image/jpeg", "image/png", "image/webp", "application/octet-stream"}
MIME_FORMAT = {"image/jpeg": "JPEG", "image/png": "PNG", "image/webp": "WEBP"}


class EmptyRecognitionError(RuntimeError):
    """The image was valid but no readable text was found."""


def execute_pipeline(task_id: str, file_bytes: bytes, recognizer, audio_builder,
                     task_store: TaskStore) -> None:
    started = time.perf_counter()
    semantic_units: list[dict] = []
    prepared_chunks: list[TextChunk] = []
    original_width: int | None = None
    original_height: int | None = None
    canvas_width: int | None = None
    canvas_height: int | None = None
    try:
        task_store.update(task_id, RecognitionStatus.PROCESSING)
        logger.info("task=%s stage=start bytes=%d", task_id, len(file_bytes))
        stage_started = time.perf_counter()
        image = ImagePreprocessor.preprocess_for_ocr(file_bytes)
        if hasattr(image, "shape"):
            canvas_height, canvas_width = image.shape[:2]
        try:
            with Image.open(BytesIO(file_bytes)) as original:
                original_width, original_height = original.size
        except (UnidentifiedImageError, OSError):
            # Unit tests may replace preprocessing with an in-memory image.
            pass
        size = f"{image.shape[1]}x{image.shape[0]}" if hasattr(image, "shape") else "unknown"
        source_size = (f"{original_width}x{original_height}"
                       if original_width is not None and original_height is not None else "unknown")
        logger.info("task=%s stage=preprocess ms=%d source_size=%s working_size=%s", task_id,
                    round((time.perf_counter() - stage_started) * 1000), source_size, size)
        stage_started = time.perf_counter()
        if hasattr(recognizer, "recognize_with_source"):
            raw_blocks = recognizer.recognize_with_source(image, file_bytes)
        else:
            raw_blocks = recognizer.recognize(image)
        mean_confidence = (sum(block.get("confidence", 0.0) for block in raw_blocks) / len(raw_blocks)
                           if raw_blocks else 0.0)
        projection_lines = sum(block.get("ocr_method") == "projection" for block in raw_blocks)
        trocr_lines = sum(block.get("ocr_method") == "trocr" for block in raw_blocks)
        logger.info("task=%s stage=ocr ms=%d lines=%d projection_lines=%d trocr_lines=%d detector_confidence=%.3f",
                    task_id, round((time.perf_counter() - stage_started) * 1000),
                    len(raw_blocks), projection_lines, trocr_lines, mean_confidence)
        if not raw_blocks:
            raise EmptyRecognitionError(
                "На снимке не найден читаемый текст. Проверьте освещение и сфотографируйте страницу повторно."
            )
        semantic_units = SemanticChunker.aggregate_to_sentences(raw_blocks)
        if not semantic_units:
            raise EmptyRecognitionError(
                "На снимке не найден читаемый текст. Проверьте освещение и сфотографируйте страницу повторно."
            )
        logger.info("task=%s stage=segment chunks=%d formulas=%d", task_id,
                    len(semantic_units), sum(unit["is_formula"] for unit in semantic_units))

        for index, unit in enumerate(semantic_units):
            raw_text = unit["text"]
            is_math = unit["is_formula"]
            spoken = FormulaToSpeech.convert(raw_text) if is_math else normalize_prose(raw_text)
            bbox = unit["bbox"]
            if (bbox is not None and original_width and original_height
                    and canvas_width and canvas_height):
                bbox = [
                    max(0, min(original_width, round(bbox[0] * original_width / canvas_width))),
                    max(0, min(original_height, round(bbox[1] * original_height / canvas_height))),
                    max(0, min(original_width, round(bbox[2] * original_width / canvas_width))),
                    max(0, min(original_height, round(bbox[3] * original_height / canvas_height))),
                ]
            prepared_chunks.append(TextChunk(
                index=index,
                content_type=ContentType.FORMULA if is_math else ContentType.TEXT,
                text=raw_text,
                spoken_text=spoken,
                is_formula=is_math,
                confidence=unit["confidence"],
                bbox=bbox,
            ))

        # OCR может вынести слово «предел» в конец строки перед записью lim.
        # В аудио достаточно произнести его один раз; исходный текст не меняем.
        for index in range(1, len(prepared_chunks)):
            previous, current = prepared_chunks[index - 1], prepared_chunks[index]
            if (current.is_formula and current.text.lstrip().lower().startswith(("lim", "\\lim"))
                    and not previous.is_formula and previous.spoken_text.lower().endswith("предел")):
                prepared_chunks[index - 1] = previous.model_copy(update={
                    "spoken_text": previous.spoken_text[:-len("предел")].rstrip()
                })

        if prepared_chunks:
            stage_started = time.perf_counter()
            audio_url, timed_chunks = audio_builder.generate_full_audio(prepared_chunks)
            if not audio_url or len(timed_chunks) != len(prepared_chunks):
                raise RuntimeError("Неполный результат синтеза речи")
            logger.info("task=%s stage=audio ms=%d seconds=%.3f", task_id,
                        round((time.perf_counter() - stage_started) * 1000), timed_chunks[-1].end_time)
        else:
            audio_url, timed_chunks = None, []

        result = RecognitionResponse(
            task_id=task_id,
            status=RecognitionStatus.COMPLETED,
            full_text="\n".join(chunk.text for chunk in prepared_chunks),
            spoken_text=" ".join(chunk.spoken_text for chunk in prepared_chunks),
            audio_url=audio_url,
            total_duration=timed_chunks[-1].end_time if timed_chunks else 0.0,
            image_width=original_width,
            image_height=original_height,
            chunks=timed_chunks,
            processing_time=round(time.perf_counter() - started, 2),
            created_at=task_store.get(task_id)["created_at"],
        )
        task_store.update(task_id, RecognitionStatus.COMPLETED, result)
        logger.info("task=%s stage=complete seconds=%.2f chunks=%d", task_id,
                    result.processing_time, len(timed_chunks))
    except Exception as exc:
        if isinstance(exc, EmptyRecognitionError):
            logger.info("task=%s stage=failed reason=no_text seconds=%.2f", task_id,
                        time.perf_counter() - started)
        else:
            logger.exception("task=%s stage=failed seconds=%.2f", task_id,
                             time.perf_counter() - started)
        message = (str(exc) if isinstance(exc, EmptyRecognitionError) else
                   "Не удалось завершить обработку лекции. Распознанный текст сохранён, если он доступен.")
        # Даже при ошибке звука текст остаётся доступен клиенту.
        result = RecognitionResponse(
            task_id=task_id,
            status=RecognitionStatus.FAILED,
            full_text="\n".join(unit["text"] for unit in semantic_units),
            spoken_text=" ".join(chunk.spoken_text for chunk in prepared_chunks),
            chunks=prepared_chunks,
            image_width=original_width,
            image_height=original_height,
            processing_time=round(time.perf_counter() - started, 2),
            created_at=task_store.get(task_id)["created_at"],
            error=message,
        )
        task_store.update(task_id, RecognitionStatus.FAILED, result, message)


async def _read_validated_image(file: UploadFile) -> bytes:
    mime = (file.content_type or "").lower()
    if mime and mime not in SUPPORTED_MIME:
        raise HTTPException(status_code=415, detail="Поддерживаются только изображения JPEG, PNG и WEBP")
    if file.size is not None and file.size > settings.MAX_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail="Размер изображения превышает допустимый")

    data = bytearray()
    while part := await file.read(min(1024 * 1024, settings.MAX_IMAGE_BYTES + 1 - len(data))):
        data.extend(part)
        if len(data) > settings.MAX_IMAGE_BYTES:
            raise HTTPException(status_code=413, detail="Размер изображения превышает допустимый")
    if not data:
        raise HTTPException(status_code=400, detail="Файл пуст")

    try:
        with Image.open(BytesIO(data)) as image:
            if image.format not in SUPPORTED_FORMATS:
                raise HTTPException(status_code=415, detail="Поддерживаются только изображения JPEG, PNG и WEBP")
            if mime in MIME_FORMAT and image.format != MIME_FORMAT[mime]:
                raise HTTPException(status_code=415, detail="Тип файла не совпадает с содержимым изображения")
            width, height = image.size
            if width <= 0 or height <= 0 or width > settings.MAX_IMAGE_SIDE or height > settings.MAX_IMAGE_SIDE or width * height > settings.MAX_IMAGE_PIXELS:
                raise HTTPException(status_code=413, detail="Разрешение изображения превышает допустимое")
            image.verify()
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
        raise HTTPException(status_code=400, detail="Не удалось прочитать изображение") from exc
    return bytes(data)


@router.post(
    "/upload", response_model=UploadResponse, status_code=202,
    responses={413: {"description": "Файл или изображение слишком велико"},
               415: {"description": "Тип изображения не поддерживается"},
               429: {"description": "Очередь заполнена; заголовок Retry-After задаёт паузу"},
               409: {"description": "Идентификатор повторного запроса занят другим снимком"},
               503: {"description": "Модели или кодировщик ещё не готовы"}},
)
async def upload_lecture_image(
    request: Request,
    file: UploadFile = File(...),
    x_upload_id: str | None = Header(default=None),
):
    recognizer = getattr(request.app.state, "recognizer", None)
    audio_builder = getattr(request.app.state, "audio_builder", None)
    if not getattr(request.app.state, "models_ready", False) or recognizer is None or audio_builder is None:
        raise HTTPException(status_code=503, detail="Сервер распознавания ещё не готов")
    queue = request.app.state.task_queue
    if x_upload_id is not None:
        try:
            task_id = str(uuid.UUID(x_upload_id))
        except ValueError as exc:
            raise HTTPException(status_code=400, detail="X-Upload-Id должен быть UUID") from exc
    else:
        task_id = str(uuid.uuid4())
    if x_upload_id is None and queue.full():
        raise HTTPException(status_code=429, detail="Очередь заполнена. Повторите попытку позже.",
                            headers={"Retry-After": "5"})

    content = await _read_validated_image(file)
    digest = hashlib.sha256(content).hexdigest()
    if x_upload_id is not None:
        existing = request.app.state.task_store.get(task_id)
        if existing is not None:
            if existing["image_sha256"] != digest:
                raise HTTPException(status_code=409, detail="X-Upload-Id уже использован для другого снимка")
            return UploadResponse(task_id=task_id, status=existing["status"])
    if queue.full():
        raise HTTPException(status_code=429, detail="Очередь заполнена. Повторите попытку позже.",
                            headers={"Retry-After": "5"})
    request.app.state.task_store.create(task_id, digest)
    queue.put_nowait((task_id, content))
    logger.info("task=%s stage=accepted mime=%s bytes=%d", task_id, file.content_type, len(content))
    return UploadResponse(task_id=task_id, status=RecognitionStatus.PENDING)


@router.get("/status/{task_id}", response_model=TaskStatusResponse,
            responses={404: {"description": "Задача не найдена"}})
async def get_task_status(task_id: str, request: Request):
    store = getattr(request.app.state, "task_store", None)
    if store is None:
        raise HTTPException(status_code=503, detail="Хранилище задач недоступно")
    task = store.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Задача не найдена")
    return TaskStatusResponse(task_id=task_id, status=task["status"], error=task["error"])


@router.get(
    "/result/{task_id}", response_model=RecognitionResponse,
    responses={202: {"description": "Задача ещё в очереди или выполняется"},
               404: {"description": "Задача не найдена"}},
)
async def get_task_result(task_id: str, request: Request):
    store = getattr(request.app.state, "task_store", None)
    if store is None:
        raise HTTPException(status_code=503, detail="Хранилище задач недоступно")
    task = store.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Задача не найдена")
    if task["status"] in (RecognitionStatus.PENDING, RecognitionStatus.PROCESSING):
        raise HTTPException(status_code=202, detail="Обработка в процессе")
    # Ошибочное задание возвращает сохранённый текст и статус failed.
    return task["response"]
