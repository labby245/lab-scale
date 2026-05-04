"""Background removal via rembg with multi-model support and session caching."""

from __future__ import annotations

import os
import threading
from typing import Callable, Optional

import cv2
import numpy as np

from .logging_config import get

log = get(__name__)

LogFn = Optional[Callable[[str], None]]

REMBG_MODELS = (
    "u2net",
    "u2netp",
    "u2net_human_seg",
    "isnet-general-use",
    "birefnet-general",
)
DEFAULT_MODEL = "u2net"

_SESSION_CACHE: dict = {}
_CACHE_LOCK = threading.Lock()


def is_available() -> bool:
    try:
        import rembg  # noqa: F401
        return True
    except ImportError as e:
        log.debug("rembg unavailable: %s", e)
        return False


def get_session(model: str = DEFAULT_MODEL):
    """Return a cached rembg session for the given model."""
    if model not in REMBG_MODELS:
        log.warning("unknown rembg model %r — falling back to %s", model, DEFAULT_MODEL)
        model = DEFAULT_MODEL
    with _CACHE_LOCK:
        if model in _SESSION_CACHE:
            return _SESSION_CACHE[model]
        try:
            from rembg import new_session  # type: ignore
        except ImportError as e:
            raise RuntimeError(
                "rembg tidak terinstal. Jalankan: pip install rembg"
            ) from e
        log.info("Creating rembg session for model '%s'", model)
        session = new_session(model)
        _SESSION_CACHE[model] = session
        return session


def _remove_frame_rgba(img_bgr: np.ndarray, session) -> np.ndarray:
    """Remove background from one BGR frame. Returns RGBA numpy array."""
    try:
        from rembg import remove  # type: ignore
        import PIL.Image            # type: ignore
    except ImportError as e:
        raise RuntimeError(
            "rembg/Pillow tidak terinstal. Jalankan: pip install rembg"
        ) from e
    img_rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
    pil_img = PIL.Image.fromarray(img_rgb)
    result_pil = remove(pil_img, session=session)
    return np.array(result_pil)


def remove_background_image(
    img_bgr: np.ndarray,
    model: str = DEFAULT_MODEL,
    log_fn: LogFn = None,
) -> np.ndarray:
    """Remove background from a single BGR image. Returns BGRA (PNG-ready)."""
    if log_fn:
        log_fn(f"rembg: model {model} (kalau pertama, model akan diunduh)…")
    session = get_session(model)
    rgba = _remove_frame_rgba(img_bgr, session)
    return cv2.cvtColor(rgba, cv2.COLOR_RGBA2BGRA)


def remove_background_frames_dir(
    frames_dir: str,
    model: str = DEFAULT_MODEL,
    log_fn: LogFn = None,
) -> None:
    """Remove background per-frame, composite on black (H.264 compatible)."""
    fnames = sorted(f for f in os.listdir(frames_dir) if f.endswith(".png"))
    total = len(fnames)
    if total == 0:
        return
    if log_fn:
        log_fn(f"rembg: model {model} untuk {total} frame…")
    session = get_session(model)
    for i, fname in enumerate(fnames):
        fpath = os.path.join(frames_dir, fname)
        img = cv2.imread(fpath, cv2.IMREAD_COLOR)
        if img is None:
            log.warning("could not read frame %s — skipping", fpath)
            continue
        rgba = _remove_frame_rgba(img, session)
        alpha = rgba[:, :, 3:4].astype(np.float32) / 255.0
        rgb = rgba[:, :, :3].astype(np.float32)
        comp = (rgb * alpha).astype(np.uint8)
        bgr = cv2.cvtColor(comp, cv2.COLOR_RGB2BGR)
        cv2.imwrite(fpath, bgr)
        if log_fn and (i % 10 == 0 or i == total - 1):
            log_fn(f"rembg: frame {i + 1}/{total}")
    if log_fn:
        log_fn(f"rembg: selesai — {total} frame.")
