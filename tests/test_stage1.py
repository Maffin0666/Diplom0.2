"""Регрессии этапа 1: готовность, загрузка, сохранность текста и TTS."""

from io import BytesIO
import json
from datetime import datetime
from pathlib import Path
import tempfile
import threading
import time
import uuid
import unittest
from unittest.mock import patch
import wave

from fastapi.testclient import TestClient
from PIL import Image
import numpy as np

from server.app.main import app
from server.app.routes import recognition
from server.app.models import RecognitionResponse, RecognitionStatus, TextChunk
from server.app.task_store import TaskStore
from server.config import settings
from server.app.services.audio_builder import AudioBuilder
from server.app.services.tts_engine import TTSEngine


def png(width=100, height=80):
    buffer = BytesIO()
    Image.new("RGB", (width, height), "white").save(buffer, format="PNG")
    return buffer.getvalue()


class FakeRecognizer:
    device = "cpu"

    def recognize(self, image):
        return [{
            "text": "Текст лекции.", "confidence": 0.8,
            "bbox": [[1, 1], [60, 1], [60, 25], [1, 25]],
        }]


class FakeAudioBuilder:
    tts = type("TTS", (), {"is_initialized": True, "engine_type": "silero"})()

    def generate_full_audio(self, chunks):
        return "/audio/test.mp3", [
            chunk.model_copy(update={"start_time": 0.0, "end_time": 1.0, "duration": 1.0})
            for chunk in chunks
        ]


class FailingAudioBuilder(FakeAudioBuilder):
    def generate_full_audio(self, chunks):
        raise RuntimeError("Имитированный отказ аудио")


class StageOneTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        task_db_patch = patch.object(settings, "TASK_DB_PATH", Path(directory.name) / "tasks.sqlite3")
        task_db_patch.start()
        self.addCleanup(task_db_patch.stop)

    def _result(self, client, task_id):
        for _ in range(100):
            status = client.get(f"/api/v1/recognition/status/{task_id}").json()["status"]
            if status in ("completed", "failed"):
                return client.get(f"/api/v1/recognition/result/{task_id}")
            time.sleep(0.02)
        self.fail(f"Задача {task_id} не завершилась")

    def _client(self, builder=None, recognizer=None):
        patches = [
            patch("server.app.main.shutil.which", return_value="ffmpeg"),
            patch("server.app.services.text_recognition.TextRecognizer",
                  return_value=recognizer or FakeRecognizer()),
            patch("server.app.services.audio_builder.AudioBuilder", return_value=builder or FakeAudioBuilder()),
        ]
        for item in patches:
            item.start()
            self.addCleanup(item.stop)
        client = TestClient(app)
        client.__enter__()
        self.addCleanup(client.__exit__, None, None, None)
        return client

    def test_model_failure_is_unready_and_rejects_upload_without_orphan_task(self):
        with patch("server.app.main.shutil.which", return_value="ffmpeg"), patch(
            "server.app.services.text_recognition.TextRecognizer",
            side_effect=RuntimeError("OCR unavailable"),
        ), TestClient(app) as client:
            health = client.get("/health")
            self.assertEqual(health.status_code, 503)
            self.assertFalse(health.json()["models_loaded"])
            upload = client.post(
                "/api/v1/recognition/upload",
                files={"file": ("note.png", png(), "image/png")},
            )
            self.assertEqual(upload.status_code, 503)
            with client.app.state.task_store._connect() as connection:
                self.assertEqual(connection.execute("SELECT COUNT(*) FROM tasks").fetchone()[0], 0)

    def test_missing_ffmpeg_is_unready(self):
        with patch("server.app.main.shutil.which", return_value=None), TestClient(app) as client:
            self.assertEqual(client.get("/health").status_code, 503)
            self.assertEqual(client.get("/info").json()["tts_engine"], "unavailable")

    def test_tts_failure_preserves_recognized_content(self):
        client = self._client(FailingAudioBuilder())
        self.assertEqual(client.get("/health").status_code, 200)
        upload = client.post(
            "/api/v1/recognition/upload",
            files={"file": ("note.png", png(), "image/png")},
        )
        self.assertEqual(upload.status_code, 202)
        task_id = upload.json()["task_id"]
        result = self._result(client, task_id)
        self.assertEqual(result.status_code, 200)
        data = result.json()
        self.assertEqual(data["status"], "failed")
        self.assertEqual(data["full_text"], "Текст лекции.")
        self.assertEqual(len(data["chunks"]), 1)
        self.assertIsNone(data["audio_url"])
        self.assertIsNotNone(data["error"])
        self.assertEqual(client.get(f"/api/v1/recognition/status/{task_id}").json()["status"], "failed")

    def test_blank_photo_reports_actionable_failure(self):
        class EmptyRecognizer(FakeRecognizer):
            def recognize(self, image):
                return []

        client = self._client(recognizer=EmptyRecognizer())
        upload = client.post("/api/v1/recognition/upload",
                             files={"file": ("blank.png", png(), "image/png")})
        result = self._result(client, upload.json()["task_id"]).json()
        self.assertEqual(result["status"], "failed")
        self.assertIsNone(result["audio_url"])
        self.assertIn("сфотографируйте", result["error"])

    def test_successful_upload_has_stable_result(self):
        client = self._client()
        upload = client.post(
            "/api/v1/recognition/upload",
            files={"file": ("note.png", png(), "image/png")},
        )
        self.assertEqual(upload.status_code, 202)
        task_id = upload.json()["task_id"]
        data = self._result(client, task_id).json()
        self.assertEqual(data["status"], "completed")
        self.assertEqual(data["full_text"], "Текст лекции.")
        self.assertEqual(data["total_duration"], 1.0)
        self.assertEqual(
            datetime.fromisoformat(data["created_at"].replace("Z", "+00:00")),
            client.app.state.task_store.get(task_id)["created_at"],
        )

    def test_upload_id_makes_network_retries_idempotent(self):
        client = self._client()
        identifier = str(uuid.uuid4())
        headers = {"X-Upload-Id": identifier}
        first = client.post("/api/v1/recognition/upload", headers=headers,
                            files={"file": ("note.png", png(), "image/png")})
        self.assertEqual(first.status_code, 202)
        self.assertEqual(first.json()["task_id"], identifier)
        self.assertEqual(self._result(client, identifier).json()["status"], "completed")
        retry = client.post("/api/v1/recognition/upload", headers=headers,
                            files={"file": ("note.png", png(), "image/png")})
        self.assertEqual(retry.status_code, 202)
        self.assertEqual(retry.json(), {"task_id": identifier, "status": "completed"})
        changed = client.post("/api/v1/recognition/upload", headers=headers,
                              files={"file": ("note.png", png(101, 80), "image/png")})
        self.assertEqual(changed.status_code, 409)
        with client.app.state.task_store._connect() as connection:
            self.assertEqual(connection.execute("SELECT COUNT(*) FROM tasks").fetchone()[0], 1)

    def test_queue_serializes_ocr_and_rejects_excess_work(self):
        started, release = threading.Event(), threading.Event()

        class BlockingRecognizer(FakeRecognizer):
            def recognize(self, image):
                started.set()
                if not release.wait(timeout=5):
                    raise RuntimeError("Тестовая задача не была разблокирована")
                return super().recognize(image)

        with patch.object(settings, "MAX_PENDING_TASKS", 2):
            client = self._client(recognizer=BlockingRecognizer())
            ids = []
            try:
                first = client.post("/api/v1/recognition/upload",
                                    files={"file": ("one.png", png(), "image/png")})
                self.assertEqual(first.status_code, 202)
                ids.append(first.json()["task_id"])
                self.assertTrue(started.wait(timeout=2))
                for name in ("two.png", "three.png"):
                    accepted = client.post("/api/v1/recognition/upload",
                                           files={"file": (name, png(), "image/png")})
                    self.assertEqual(accepted.status_code, 202)
                    ids.append(accepted.json()["task_id"])
                self.assertEqual(client.get("/info").json()["details"]["pending_tasks"], 2)
                self.assertNotIn("processing_task", client.get("/info").json()["details"])
                rejected = client.post("/api/v1/recognition/upload",
                                       files={"file": ("four.png", png(), "image/png")})
                self.assertEqual(rejected.status_code, 429)
                self.assertEqual(rejected.headers["retry-after"], "5")
            finally:
                release.set()
            for task_id in ids:
                self.assertEqual(self._result(client, task_id).json()["status"], "completed")

    def test_manifest_survives_restart_and_interrupted_task_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "tasks.sqlite3"
            first = TaskStore(path)
            created = first.create("done")
            manifest = RecognitionResponse(
                task_id="done", status=RecognitionStatus.COMPLETED,
                full_text="Текст лекции.", spoken_text="Текст лекции.",
                created_at=created,
            )
            first.update("done", RecognitionStatus.COMPLETED, manifest)
            first.create("interrupted")
            first.update("interrupted", RecognitionStatus.PROCESSING)

            restarted = TaskStore(path)
            self.assertEqual(restarted.fail_interrupted(), 1)
            self.assertEqual(restarted.get("done")["response"].full_text, "Текст лекции.")
            failed = restarted.get("interrupted")
            self.assertEqual(failed["status"], RecognitionStatus.FAILED)
            self.assertIn("перезапуском", failed["response"].error)
            self.assertEqual(restarted.fail_interrupted(), 0)

    def test_client_openapi_snapshot_matches_server(self):
        contract = Path(__file__).resolve().parents[1] / "client" / "api" / "openapi.v1.json"
        self.assertEqual(json.loads(contract.read_text(encoding="utf-8")), app.openapi())

    def test_bboxes_use_original_photo_coordinates(self):
        with tempfile.TemporaryDirectory() as directory:
            store = TaskStore(Path(directory) / "tasks.sqlite3")
            store.create("scaled")
            resized = np.zeros((50, 100, 3), dtype=np.uint8)
            with patch.object(recognition.ImagePreprocessor, "preprocess_for_ocr", return_value=resized):
                recognition.execute_pipeline("scaled", png(200, 100),
                                             FakeRecognizer(), FakeAudioBuilder(), store)
            manifest = store.get("scaled")["response"]
            self.assertEqual((manifest.image_width, manifest.image_height), (200, 100))
            self.assertEqual(manifest.chunks[0].bbox, [2, 2, 120, 50])

    def test_upload_rejects_wrong_type_corruption_and_size(self):
        client = self._client()
        cases = [
            ("bad.svg", b"<svg/>", "image/svg+xml", 415),
            ("bad.png", b"not-a-png", "image/png", 400),
            ("disguised.jpg", png(), "image/jpeg", 415),
        ]
        for name, body, mime, expected in cases:
            with self.subTest(name=name):
                response = client.post(
                    "/api/v1/recognition/upload",
                    files={"file": (name, body, mime)},
                )
                self.assertEqual(response.status_code, expected)
        with patch.object(settings, "MAX_IMAGE_BYTES", 10):
            response = client.post(
                "/api/v1/recognition/upload",
                files={"file": ("large.png", png(), "image/png")},
            )
            self.assertEqual(response.status_code, 413)
        with patch.object(settings, "MAX_IMAGE_PIXELS", 100):
            response = client.post(
                "/api/v1/recognition/upload",
                files={"file": ("large.png", png(), "image/png")},
            )
            self.assertEqual(response.status_code, 413)
        with client.app.state.task_store._connect() as connection:
            self.assertEqual(connection.execute("SELECT COUNT(*) FROM tasks").fetchone()[0], 0)

    def test_silero_missing_is_initialization_error(self):
        with patch("server.app.services.silero_tts.SileroTTS._find_model_file", return_value=None):
            with self.assertRaises(RuntimeError):
                TTSEngine(engine_type="silero", use_fallback=False)

    def test_online_tts_requires_explicit_setting(self):
        with self.assertRaises(RuntimeError):
            TTSEngine(engine_type="gtts", allow_online=False)

    def test_all_backends_return_a_path(self):
        class Voice:
            id = "ru"
            name = "Russian"
            languages = ["ru"]
            gender = "female"

        class FakePyttsx:
            def setProperty(self, key, value):
                pass

            def getProperty(self, key):
                return [Voice()]

            def save_to_file(self, text, path):
                Path(path).write_bytes(b"RIFF")

            def runAndWait(self):
                pass

        class FakeGtts:
            def __init__(self, **kwargs):
                pass

            def save(self, path):
                Path(path).write_bytes(b"ID3")

        with tempfile.TemporaryDirectory() as directory:
            with patch("pyttsx3.init", return_value=FakePyttsx()):
                local = TTSEngine(engine_type="pyttsx3")
                local_path = local.synthesize("Привет", str(Path(directory) / "local.wav"))
                self.assertTrue(Path(local_path).is_file())
                self.assertEqual(Path(local_path).suffix, ".wav")
            with patch("gtts.gTTS", FakeGtts):
                remote = TTSEngine(engine_type="gtts", allow_online=True)
                remote_path = remote.synthesize("Привет", str(Path(directory) / "remote.wav"))
                self.assertTrue(Path(remote_path).is_file())
                self.assertEqual(Path(remote_path).suffix, ".mp3")

    def test_audio_builder_does_not_publish_incomplete_lecture(self):
        class PartialTTS:
            calls = 0

            def synthesize(self, text, output_path):
                self.calls += 1
                if self.calls == 2:
                    raise RuntimeError("Второй фрагмент недоступен")
                with wave.open(output_path, "wb") as wav:
                    wav.setnchannels(1)
                    wav.setsampwidth(2)
                    wav.setframerate(48000)
                    wav.writeframes(b"\x00" * 9600)
                return output_path

        with tempfile.TemporaryDirectory() as directory:
            builder = AudioBuilder.__new__(AudioBuilder)
            builder.tts = PartialTTS()
            builder.output_dir = Path(directory) / "audio"
            builder.temp_dir = Path(directory) / "temp"
            builder.output_dir.mkdir()
            builder.temp_dir.mkdir()
            chunks = [
                TextChunk(index=0, text="Первый", spoken_text="Первый"),
                TextChunk(index=1, text="Второй", spoken_text="Второй"),
            ]
            with self.assertRaisesRegex(RuntimeError, "фрагмент 1"):
                builder.generate_full_audio(chunks)
            self.assertEqual(list(builder.output_dir.iterdir()), [])
            self.assertEqual(chunks[0].end_time, 0.0)


if __name__ == "__main__":
    unittest.main()
