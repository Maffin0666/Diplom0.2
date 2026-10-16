"""The voice fallback validates uploads before running the model."""

import io
import wave

from fastapi import FastAPI
from fastapi.testclient import TestClient

from server.app.routes import voice


def _wav(rate=16_000, channels=1, width=2, frames=3_200):
    data = io.BytesIO()
    with wave.open(data, "wb") as writer:
        writer.setnchannels(channels)
        writer.setsampwidth(width)
        writer.setframerate(rate)
        writer.writeframes(b"\0" * frames * channels * width)
    return data.getvalue()


def test_voice_command_accepts_short_pcm_and_returns_words(monkeypatch, tmp_path):
    monkeypatch.setattr(voice.settings, "VOICE_MODEL_DIR", tmp_path)
    monkeypatch.setattr(voice, "_recognize", lambda pcm: "следующий фрагмент")
    app = FastAPI()
    app.include_router(voice.router)
    with TestClient(app) as client:
        response = client.post("/api/v1/voice/command", files={"file": ("voice.wav", _wav(), "audio/wav")})
    assert response.status_code == 200
    assert response.json() == {"text": "следующий фрагмент"}


def test_voice_command_rejects_wrong_audio_format():
    app = FastAPI()
    app.include_router(voice.router)
    with TestClient(app) as client:
        response = client.post("/api/v1/voice/command", files={"file": ("voice.wav", _wav(rate=44_100), "audio/wav")})
    assert response.status_code == 422
