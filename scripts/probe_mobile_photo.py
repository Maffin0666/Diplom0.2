"""Run the production OCR path on one local phone photo without generating audio.

Usage: python -m scripts.probe_mobile_photo img_for_test/20261002_162351.jpg
The JSON report contains OCR blocks and timings but no source image bytes.
"""

import argparse
import json
import time
from pathlib import Path

from PIL import Image

from server.app.services.image_preprocessing import ImagePreprocessor
from server.app.services.text_recognition import TextRecognizer


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--beams", type=int, choices=[1, 2, 3, 4])
    parser.add_argument("--kv-cache", choices=["on", "off"])
    args = parser.parse_args()

    data = args.image.read_bytes()
    with Image.open(args.image) as image:
        source_size = image.size

    started = time.perf_counter()
    recognizer = TextRecognizer(num_beams=args.beams,
                                use_kv_cache=None if args.kv_cache is None
                                else args.kv_cache == "on")
    load_seconds = time.perf_counter() - started
    started = time.perf_counter()
    processed = ImagePreprocessor.preprocess_for_ocr(data)
    preprocess_seconds = time.perf_counter() - started
    started = time.perf_counter()
    blocks = recognizer.recognize_with_source(processed, data)
    ocr_seconds = time.perf_counter() - started

    report = {
        "image": str(args.image),
        "source_size": source_size,
        "working_size": [processed.shape[1], processed.shape[0]],
        "load_seconds": round(load_seconds, 2),
        "preprocess_seconds": round(preprocess_seconds, 2),
        "ocr_seconds": round(ocr_seconds, 2),
        "beams": recognizer.num_beams,
        "kv_cache": recognizer.trocr.generation_config.use_cache,
        "blocks": blocks,
    }
    for index, block in enumerate(blocks, 1):
        print(f"{index:02d} {block.get('ocr_method')} "
              f"conf={block.get('confidence')}: {block['text']}", flush=True)
    print(f"source={source_size} working={report['working_size']} "
          f"load={load_seconds:.1f}s preprocess={preprocess_seconds:.1f}s "
          f"ocr={ocr_seconds:.1f}s", flush=True)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2),
                               encoding="utf-8")


if __name__ == "__main__":
    main()
