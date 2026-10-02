"""Inspect projection-line candidates on a phone photograph without OCR models."""

import argparse
import cv2
import numpy as np
from scipy.signal import find_peaks

from server.app.services.image_preprocessing import ImagePreprocessor


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image")
    args = parser.parse_args()
    source = cv2.imread(args.image)
    h, w = source.shape[:2]
    source = cv2.resize(source, (1920, round(h * 1920 / w)),
                        interpolation=cv2.INTER_AREA)
    source = ImagePreprocessor.deskew_page(source)
    gray = cv2.cvtColor(source, cv2.COLOR_BGR2GRAY)
    print(f"source={w}x{h} working={source.shape[1]}x{source.shape[0]}")
    print(f"production spans={ImagePreprocessor.detect_line_spans(source)}")
    for index, (top, bottom) in enumerate(ImagePreprocessor.detect_line_spans(source)):
        row = source[top:bottom]
        bounds = ImagePreprocessor.detect_ink_bounds(row)
        print(f"row={index + 1:02d} y={top}:{bottom} bounds={bounds}")
    for threshold in (80, 100, 120, 140, 160, "otsu"):
        if threshold == "otsu":
            _, ink = cv2.threshold(gray, 0, 255,
                                   cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
        else:
            ink = (gray < threshold).astype(np.uint8)
        profile = np.count_nonzero(ink, axis=1).astype(float)
        smooth = np.convolve(profile, np.ones(9) / 9, mode="same")
        peaks, props = find_peaks(smooth, distance=35,
                                  prominence=max(3, smooth.max() * 0.05))
        centers = [int(y) for y, prominence in zip(peaks, props["prominences"])
                   if smooth[y] >= smooth.max() * 0.20]
        print(f"threshold={threshold} max={smooth.max():.0f} "
              f"centers={centers}")


if __name__ == "__main__":
    main()
