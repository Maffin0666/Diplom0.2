"""Exercise the same HTTP flow that the first mobile client will use.

Start the server, then run:
python -m scripts.smoke_client_api --image test_lecture.jpg
"""

import argparse
import json
import mimetypes
import time
import uuid
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin
from urllib.request import Request, urlopen


def request_json(url: str, data: bytes | None = None,
                 content_type: str | None = None,
                 extra_headers: dict[str, str] | None = None) -> dict:
    headers = {"Accept": "application/json"}
    headers.update(extra_headers or {})
    if content_type:
        headers["Content-Type"] = content_type
    request = Request(url, data=data, headers=headers)
    try:
        with urlopen(request, timeout=30) as response:
            return json.load(response)
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code} от {url}: {detail}") from exc


def multipart_image(path: Path) -> tuple[bytes, str]:
    mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    boundary = "codex-" + uuid.uuid4().hex
    filename = "photo" + path.suffix.lower()
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'
        f"Content-Type: {mime}\r\n\r\n"
    ).encode("ascii") + path.read_bytes() + f"\r\n--{boundary}--\r\n".encode("ascii")
    return body, f"multipart/form-data; boundary={boundary}"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument("--image", type=Path, default=Path("test_lecture.jpg"))
    parser.add_argument("--timeout", type=int, default=240)
    args = parser.parse_args()
    base = args.base_url.rstrip("/") + "/"

    health = request_json(urljoin(base, "health"))
    if not health["models_loaded"]:
        raise RuntimeError("Сервер не готов")
    body, content_type = multipart_image(args.image)
    upload_id = str(uuid.uuid4())
    accepted = request_json(urljoin(base, "api/v1/recognition/upload"), body, content_type,
                            {"X-Upload-Id": upload_id})
    task_id = accepted["task_id"]
    print(f"Accepted task_id={task_id}", flush=True)

    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        status = request_json(urljoin(base, f"api/v1/recognition/status/{task_id}"))
        if status["status"] in ("completed", "failed"):
            break
        time.sleep(1)
    else:
        raise TimeoutError(f"Задача {task_id} не завершилась за {args.timeout} с")

    result = request_json(urljoin(base, f"api/v1/recognition/result/{task_id}"))
    if result["status"] != "completed":
        raise RuntimeError(f"Задача {task_id} завершилась с ошибкой: {result['error']}")
    chunks = result["chunks"]
    if not chunks or not result["audio_url"]:
        raise AssertionError("В успешном манифесте нет фрагментов или аудио")
    previous_end = 0.0
    for index, chunk in enumerate(chunks):
        if chunk["index"] != index or chunk["start_time"] < previous_end or chunk["end_time"] <= chunk["start_time"]:
            raise AssertionError(f"Неверные временные метки фрагмента {index}")
        previous_end = chunk["end_time"]
        bbox = chunk["bbox"]
        if bbox and (not result["image_width"] or not result["image_height"]
                     or not (0 <= bbox[0] <= bbox[2] <= result["image_width"])
                     or not (0 <= bbox[1] <= bbox[3] <= result["image_height"])):
            raise AssertionError(f"Координаты фрагмента {index} вне исходной фотографии")
    if result["total_duration"] < previous_end:
        raise AssertionError("Общая длительность меньше конца последнего фрагмента")
    if "неизвестный символ" in result["spoken_text"].lower() or "символ номер" in result["spoken_text"].lower():
        raise AssertionError("Диагностический код попал в озвучиваемый текст")

    audio_url = urljoin(base, result["audio_url"].lstrip("/"))
    with urlopen(audio_url, timeout=30) as response:
        audio = response.read()
        audio_type = response.headers.get("Content-Type", "")
    if len(audio) < 100 or "audio" not in audio_type:
        raise AssertionError(f"Аудиофайл недоступен: {audio_type}, {len(audio)} байт")
    print(json.dumps({"task_id": task_id, "status": result["status"],
                      "chunks": len(chunks), "duration_seconds": result["total_duration"],
                      "audio_bytes": len(audio), "audio_content_type": audio_type},
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        main()
    except URLError as exc:
        raise SystemExit(f"Сервер недоступен: {exc}") from exc
