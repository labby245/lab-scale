"""YOLOv8 watermark detection inference. Optional — needs ultralytics + model file.

Install:  pip install ultralytics
Place a trained YOLOv8 model at  <project>/models/watermark_yolo.pt

Falls back silently to the heuristic detector when ultralytics or the model
file is missing. Returns the highest-confidence bbox for the watermark class."""

from __future__ import annotations

import os
import threading
from typing import Optional, Tuple

import numpy as np

from .logging_config import get

log = get(__name__)

CONF_THRESHOLD = 0.25

_MODEL = None
_MODEL_LOCK = threading.Lock()
_MODEL_PROBED = False
_MODEL_PATH: Optional[str] = None


def _project_models_dir() -> str:
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(here, "models")


def _resolve_model_path() -> Optional[str]:
    """Find a YOLO weights file under <project>/models/."""
    global _MODEL_PATH, _MODEL_PROBED
    if _MODEL_PROBED:
        return _MODEL_PATH
    _MODEL_PROBED = True

    base = _project_models_dir()
    candidates = ["watermark_yolo.pt", "watermark.pt", "yolo_watermark.pt"]
    for name in candidates:
        path = os.path.join(base, name)
        if os.path.isfile(path):
            _MODEL_PATH = path
            return _MODEL_PATH
    return None


def is_available() -> bool:
    """Return True if ultralytics is installed AND a weights file is present."""
    if _resolve_model_path() is None:
        return False
    try:
        import ultralytics  # noqa: F401
        return True
    except ImportError as e:
        log.debug("ultralytics not installed: %s", e)
        return False


def _get_model():
    global _MODEL
    with _MODEL_LOCK:
        if _MODEL is not None:
            return _MODEL
        path = _resolve_model_path()
        if path is None:
            raise RuntimeError("YOLO model file not found in models/")
        try:
            from ultralytics import YOLO  # type: ignore
        except ImportError as e:
            raise RuntimeError(
                "ultralytics tidak terinstal. Jalankan: pip install ultralytics"
            ) from e
        log.info("Loading YOLO watermark model: %s", path)
        _MODEL = YOLO(path)
        return _MODEL


def detect_with_yolo(
    image: np.ndarray,
    conf: float = CONF_THRESHOLD,
) -> Optional[Tuple[int, int, int, int]]:
    """Run YOLO detection. Returns (x, y, w, h) of highest-confidence box, or None."""
    if not is_available():
        return None
    try:
        model = _get_model()
    except RuntimeError as e:
        log.warning("YOLO unavailable at runtime: %s", e)
        return None

    try:
        results = model.predict(image, conf=conf, verbose=False)
    except Exception as e:
        log.warning("YOLO inference failed: %s", e)
        return None
    if not results:
        return None
    r0 = results[0]
    boxes = getattr(r0, "boxes", None)
    if boxes is None or len(boxes) == 0:
        return None

    try:
        confs = boxes.conf.cpu().numpy() if hasattr(boxes.conf, "cpu") else np.array(boxes.conf)
        xyxy = boxes.xyxy.cpu().numpy() if hasattr(boxes.xyxy, "cpu") else np.array(boxes.xyxy)
    except Exception as e:
        log.warning("YOLO result parse failed: %s", e)
        return None

    best_i = int(np.argmax(confs))
    x1, y1, x2, y2 = xyxy[best_i].astype(int)
    h, w = image.shape[:2]
    x1 = max(0, min(int(x1), w - 1))
    y1 = max(0, min(int(y1), h - 1))
    x2 = max(x1 + 1, min(int(x2), w))
    y2 = max(y1 + 1, min(int(y2), h))
    return (int(x1), int(y1), int(x2 - x1), int(y2 - y1))
