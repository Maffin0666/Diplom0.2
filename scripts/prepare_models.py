"""Явная однократная загрузка OCR-моделей перед автономным запуском.

Команда обращается к интернету. Основной сервер никогда не скачивает веса.
"""

import argparse
import json
from pathlib import Path

import easyocr
from huggingface_hub import HfApi, snapshot_download

from server.config import settings


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", help="Дополнительная TrOCR-модель для сравнения")
    parser.add_argument("--revision", help="Ревизия дополнительной модели")
    parser.add_argument("--local-dir", type=Path, help="Сохранить TrOCR в отдельную папку")
    args = parser.parse_args()
    model_name = args.model or settings.TROCR_MODEL_NAME
    revision = args.revision if args.revision is not None else (
        settings.TROCR_REVISION if model_name == settings.TROCR_MODEL_NAME else None
    )
    if revision is None:
        revision = HfApi().model_info(model_name).sha
    settings.MODELS_DIR.mkdir(parents=True, exist_ok=True)
    easyocr.Reader(
        settings.OCR_LANGUAGES,
        gpu=False,
        model_storage_directory=str(settings.MODELS_DIR),
        download_enabled=True,
    )
    path = snapshot_download(
        repo_id=model_name,
        revision=revision,
        local_dir=args.local_dir,
        allow_patterns=["*.json", "*.safetensors", "*.txt"],
    )
    if args.local_dir:
        (args.local_dir / "download_provenance.json").write_text(
            json.dumps({"repo": model_name, "revision": revision}, indent=2), encoding="utf-8"
        )
    print(f"EasyOCR сохранён в {settings.MODELS_DIR}")
    print(f"TrOCR сохранён в {path}")
    print(f"Silero: {settings.SILERO_MODEL_PATH}")


if __name__ == "__main__":
    main()
