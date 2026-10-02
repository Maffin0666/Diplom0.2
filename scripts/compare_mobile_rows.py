"""Compare local TrOCR inputs for selected rows of a phone photograph.

This is an offline diagnostic tool; it does not change the server pipeline.
"""

import argparse
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

from server.app.services.image_preprocessing import ImagePreprocessor
from server.app.services.text_recognition import TextRecognizer


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image")
    parser.add_argument("--rows", type=int, nargs="+", default=[8, 9, 10, 11, 12])
    args = parser.parse_args()
    data = Path(args.image).read_bytes()
    processed = ImagePreprocessor.preprocess_for_ocr(data)
    source = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
    source = cv2.resize(source, (processed.shape[1], processed.shape[0]),
                        interpolation=cv2.INTER_AREA)
    source = ImagePreprocessor.deskew_page(source)
    spans = ImagePreprocessor.detect_line_spans(source)
    recognizer = TextRecognizer()
    for variant, page in (("processed", processed), ("source", source)):
        crops = []
        for number in args.rows:
            top, bottom = spans[number - 1]
            ref_row = source[top:bottom]
            bounds = ImagePreprocessor.detect_ink_bounds(ref_row)
            if bounds is None:
                crop = page[top:bottom]
            else:
                x0, y0, x1, y1 = bounds
                crop = page[top + y0:top + y1, x0:x1]
            crops.append(Image.fromarray(cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)))
        decoded = recognizer._decode_crops(crops)
        for number, text in zip(args.rows, decoded):
            print(f"{variant} row={number}: {text}", flush=True)


if __name__ == "__main__":
    main()
