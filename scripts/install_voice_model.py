"""Install the optional Russian Vosk command model from its official host."""

from pathlib import Path
from urllib.request import urlretrieve
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "server" / "models"
NAME = "vosk-model-small-ru-0.22"
URL = f"https://alphacephei.com/vosk/models/{NAME}.zip"


def main() -> None:
    model = TARGET / NAME
    if (model / "am" / "final.mdl").is_file():
        print(f"Модель уже установлена: {model}")
        return
    TARGET.mkdir(parents=True, exist_ok=True)
    archive = TARGET / f"{NAME}.zip"
    if not archive.is_file():
        print(f"Скачиваем {URL}")
        urlretrieve(URL, archive)
    with ZipFile(archive) as package:
        for entry in package.infolist():
            destination = (TARGET / entry.filename).resolve()
            if not destination.is_relative_to(TARGET.resolve()):
                raise ValueError("Архив модели содержит недопустимый путь")
        package.extractall(TARGET)
    if not (model / "am" / "final.mdl").is_file():
        raise RuntimeError("Файлы модели отсутствуют после распаковки")
    print(f"Модель установлена: {model}")


if __name__ == "__main__":
    main()
