"""Frame extraction and image enhancement helpers (OpenCV)."""

from __future__ import annotations

import os
from typing import Callable, Optional

import cv2
import numpy as np

from .logging_config import get

log = get(__name__)

LogFn = Optional[Callable[[str], None]]


def extract_frames_to_dir(
    input_video_path: str,
    output_frames_dir: str,
    log_fn: LogFn = None,
) -> float:
    """Extract all video frames as PNG without modification. Returns source FPS."""
    os.makedirs(output_frames_dir, exist_ok=True)
    cap = cv2.VideoCapture(input_video_path)
    if not cap.isOpened():
        raise RuntimeError("Failed to open input video")
    try:
        fps = cap.get(cv2.CAP_PROP_FPS) or 25.0
        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) or 0
        if log_fn:
            log_fn(f"Ekstrak frame dari video ({total} frame)…")
        idx = 0
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            fname = os.path.join(output_frames_dir, f"frame_{idx:06d}.png")
            cv2.imwrite(fname, frame)
            idx += 1
            if log_fn and total > 0 and (idx % 60 == 0 or idx == total):
                pct = int(idx / total * 100)
                log_fn(f"Ekstrak frame: {idx}/{total} ({pct}%)")
        if log_fn:
            log_fn(f"Ekstrak selesai — {idx} frame.")
        return float(fps)
    finally:
        cap.release()


def apply_sharpness(img_bgr: np.ndarray, strength: float) -> np.ndarray:
    """Unsharp mask. strength: 0.0 = none, 1.0 = strong."""
    if strength <= 0:
        return img_bgr
    blurred = cv2.GaussianBlur(img_bgr, (0, 0), 3)
    return cv2.addWeighted(img_bgr, 1.0 + strength, blurred, -strength, 0)
