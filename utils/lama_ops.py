"""LaMa AI inpainting wrapper. Optional — graceful fallback if package missing.

Install:  pip install simple-lama-inpainting

LaMa produces dramatically better results than Telea/NS for watermarks over
faces, text, or complex backgrounds. ~700MB model downloaded on first use."""

from __future__ import annotations

import os
import threading
from typing import Callable, Optional

import cv2
import numpy as np

from .logging_config import get

log = get(__name__)

LogFn = Optional[Callable[[str], None]]

_LAMA_INSTANCE = None
_INSTANCE_LOCK = threading.Lock()


def is_available() -> bool:
    """Return True if simple-lama-inpainting is importable."""
    try:
        import simple_lama_inpainting  # noqa: F401
        return True
    except ImportError as e:
        log.debug("LaMa not available: %s", e)
        return False


def _get_lama():
    """Cached LaMa singleton — model loaded once per process."""
    global _LAMA_INSTANCE
    with _INSTANCE_LOCK:
        if _LAMA_INSTANCE is not None:
            return _LAMA_INSTANCE
        try:
            from simple_lama_inpainting import SimpleLama  # type: ignore
        except ImportError as e:
            raise RuntimeError(
                "simple-lama-inpainting tidak terinstal. "
                "Jalankan: pip install simple-lama-inpainting"
            ) from e
        log.info("Loading LaMa model (downloads ~700MB on first use)…")
        _LAMA_INSTANCE = SimpleLama()
        return _LAMA_INSTANCE


def inpaint_bgr(img_bgr: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """Run LaMa on a BGR image with a binary mask (uint8, white = remove)."""
    if not is_available():
        raise RuntimeError(
            "simple-lama-inpainting tidak terinstal. "
            "Jalankan: pip install simple-lama-inpainting"
        )
    import PIL.Image  # type: ignore

    lama = _get_lama()
    img_rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
    pil_img = PIL.Image.fromarray(img_rgb)
    pil_mask = PIL.Image.fromarray(mask).convert("L")
    result_pil = lama(pil_img, pil_mask)
    result_rgb = np.array(result_pil)
    return cv2.cvtColor(result_rgb, cv2.COLOR_RGB2BGR)


def inpaint_image_array(img_bgr: np.ndarray, roi: dict) -> np.ndarray:
    """Inpaint single image with LaMa given an ROI dict {x,y,width,height}."""
    h, w = img_bgr.shape[:2]
    x = max(0, min(int(roi["x"]), w - 1))
    y = max(0, min(int(roi["y"]), h - 1))
    rw = max(1, min(int(roi["width"]), w - x))
    rh = max(1, min(int(roi["height"]), h - y))
    mask = np.zeros((h, w), dtype=np.uint8)
    mask[y:y + rh, x:x + rw] = 255
    return inpaint_bgr(img_bgr, mask)


def remove_watermark_roi_to_frames(
    input_video_path: str,
    output_frames_dir: str,
    roi: tuple,
    log_fn: LogFn = None,
) -> float:
    """Inpaint each frame with LaMa, save lossless PNGs. Returns source FPS."""
    os.makedirs(output_frames_dir, exist_ok=True)
    cap = cv2.VideoCapture(input_video_path)
    if not cap.isOpened():
        raise RuntimeError("Failed to open input video")
    try:
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        fps = cap.get(cv2.CAP_PROP_FPS) or 25.0
        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) or 0

        x, y, rw, rh = roi
        x = max(0, min(int(x), width - 1))
        y = max(0, min(int(y), height - 1))
        rw = max(1, min(int(rw), width - x))
        rh = max(1, min(int(rh), height - y))

        if log_fn:
            log_fn(f"LaMa inpaint pada ROI {rw}×{rh} ({total} frame)…")

        # Preload model so download happens before the per-frame loop
        _get_lama()

        mask = np.zeros((height, width), dtype=np.uint8)
        mask[y:y + rh, x:x + rw] = 255

        idx = 0
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            out = inpaint_bgr(frame, mask)
            fname = os.path.join(output_frames_dir, f"frame_{idx:06d}.png")
            cv2.imwrite(fname, out)
            idx += 1
            if log_fn and total > 0 and (idx % 10 == 0 or idx == total):
                pct = int(idx / total * 100)
                log_fn(f"LaMa: frame {idx}/{total} ({pct}%)")

        if log_fn:
            log_fn(f"LaMa selesai — {idx} frame.")
        return float(fps)
    finally:
        cap.release()
