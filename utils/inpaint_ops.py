"""Watermark inpainting on videos and images using OpenCV (Telea / Navier-Stokes)."""

from __future__ import annotations

import os
from typing import Callable, Optional, Tuple

import cv2
import numpy as np

from .logging_config import get

log = get(__name__)

LogFn = Optional[Callable[[str], None]]


def _inpaint_flag(method: str) -> int:
    return cv2.INPAINT_TELEA if method.lower() == "telea" else cv2.INPAINT_NS


def _clip_roi(roi: Tuple[int, int, int, int], w: int, h: int) -> Tuple[int, int, int, int]:
    x, y, rw, rh = roi
    x = max(0, min(int(x), w - 1))
    y = max(0, min(int(y), h - 1))
    rw = max(1, min(int(rw), w - x))
    rh = max(1, min(int(rh), h - y))
    return x, y, rw, rh


def remove_watermark_roi_to_frames(
    input_video_path: str,
    output_frames_dir: str,
    roi: Tuple[int, int, int, int],
    inpaint_method: str = "telea",
    log_fn: LogFn = None,
) -> float:
    """Inpaint watermark frame-by-frame, save lossless PNGs. Returns source FPS."""
    os.makedirs(output_frames_dir, exist_ok=True)
    cap = cv2.VideoCapture(input_video_path)
    if not cap.isOpened():
        raise RuntimeError("Failed to open input video")
    try:
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        fps = cap.get(cv2.CAP_PROP_FPS) or 25.0
        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) or 0

        if log_fn:
            log_fn(f"Membuka video {width}×{height} @ {fps:.1f}fps ({total} frame)…")

        x, y, w, h = _clip_roi(roi, width, height)
        flags = _inpaint_flag(inpaint_method)
        method_name = "Telea" if inpaint_method.lower() == "telea" else "Navier-Stokes"
        if log_fn:
            log_fn(f"Inpaint watermark ({method_name}) pada ROI {w}×{h}…")

        mask = np.zeros((height, width), dtype=np.uint8)
        mask[y:y + h, x:x + w] = 255

        idx = 0
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            inpainted = cv2.inpaint(frame, mask, 3, flags)
            fname = os.path.join(output_frames_dir, f"frame_{idx:06d}.png")
            if not cv2.imwrite(fname, inpainted):
                raise RuntimeError(f"Failed to write frame {fname}")
            idx += 1
            if log_fn and total > 0 and (idx % 30 == 0 or idx == total):
                pct = int(idx / total * 100)
                log_fn(f"Inpaint: frame {idx}/{total} ({pct}%)")

        if log_fn:
            log_fn(f"Inpaint selesai — {idx} frame diproses.")
        return float(fps)
    finally:
        cap.release()


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


def inpaint_image_array(
    img_bgr: np.ndarray,
    roi: dict,
    inpaint_method: str = "telea",
) -> np.ndarray:
    """Inpaint watermark on a single BGR image (returns new array)."""
    h, w = img_bgr.shape[:2]
    rx, ry, rw, rh = _clip_roi(
        (int(roi["x"]), int(roi["y"]), int(roi["width"]), int(roi["height"])),
        w, h,
    )
    mask = np.zeros((h, w), dtype=np.uint8)
    mask[ry:ry + rh, rx:rx + rw] = 255
    return cv2.inpaint(img_bgr, mask, 3, _inpaint_flag(inpaint_method))


def apply_sharpness(img_bgr: np.ndarray, strength: float) -> np.ndarray:
    """Unsharp mask. strength: 0.0 = none, 1.0 = strong."""
    if strength <= 0:
        return img_bgr
    blurred = cv2.GaussianBlur(img_bgr, (0, 0), 3)
    return cv2.addWeighted(img_bgr, 1.0 + strength, blurred, -strength, 0)
