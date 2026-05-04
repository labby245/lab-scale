"""Persistent labeled-watermark store for self-improving YOLO detector.

Each user-confirmed ROI becomes a training sample. Storage layout:

    labels/
      raw/<sha256[:16]>.jpg     # deduped JPEG (q=85)
      annotations.jsonl         # one JSON line per sample

Annotation line format:
    {"hash": "abc...", "roi": {"x":10, "y":20, "w":100, "h":50},
     "img_w": 1920, "img_h": 1080,
     "ts": "2026-05-04T12:34:56", "source": "manual"}
"""

from __future__ import annotations

import datetime
import hashlib
import json
import os
import threading
from typing import Iterator, Optional

import cv2
import numpy as np

from .logging_config import get

log = get(__name__)

_WRITE_LOCK = threading.Lock()


def _project_labels_dir() -> str:
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(here, "labels")


class LabelsStore:
    """Append-only labeled-sample store with hash-based image dedup."""

    def __init__(self, root: Optional[str] = None):
        self.root = root or _project_labels_dir()
        self.raw_dir = os.path.join(self.root, "raw")
        self.annotations_path = os.path.join(self.root, "annotations.jsonl")
        os.makedirs(self.raw_dir, exist_ok=True)

    # ── Writers ─────────────────────────────────────────────────────────

    def add_sample(
        self,
        image_bgr: np.ndarray,
        roi: dict,
        source: str = "manual",
    ) -> Optional[str]:
        """Save (image, roi) sample. Returns the image hash on success."""
        if image_bgr is None or image_bgr.size == 0:
            return None
        h_img, w_img = image_bgr.shape[:2]
        x = max(0, int(roi.get("x", 0)))
        y = max(0, int(roi.get("y", 0)))
        w = max(0, int(roi.get("width", roi.get("w", 0))))
        h = max(0, int(roi.get("height", roi.get("h", 0))))
        if w <= 0 or h <= 0:
            return None
        if x >= w_img or y >= h_img:
            return None

        digest = self._hash_image(image_bgr)
        img_path = os.path.join(self.raw_dir, f"{digest}.jpg")

        with _WRITE_LOCK:
            if not os.path.isfile(img_path):
                ok = cv2.imwrite(img_path, image_bgr, [cv2.IMWRITE_JPEG_QUALITY, 85])
                if not ok:
                    log.warning("labels_store: failed to write %s", img_path)
                    return None

            record = {
                "hash": digest,
                "roi": {"x": x, "y": y, "w": w, "h": h},
                "img_w": w_img,
                "img_h": h_img,
                "ts": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S"),
                "source": source,
            }
            try:
                with open(self.annotations_path, "a", encoding="utf-8") as fh:
                    fh.write(json.dumps(record, ensure_ascii=False) + "\n")
            except OSError as e:
                log.warning("labels_store: cannot append annotation: %s", e)
                return None
        return digest

    # ── Readers ─────────────────────────────────────────────────────────

    def stats(self) -> dict:
        total = 0
        unique_images: set = set()
        sources: dict = {}
        if os.path.isfile(self.annotations_path):
            try:
                with open(self.annotations_path, "r", encoding="utf-8") as fh:
                    for line in fh:
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            r = json.loads(line)
                        except json.JSONDecodeError:
                            continue
                        total += 1
                        unique_images.add(r.get("hash", ""))
                        s = r.get("source", "unknown")
                        sources[s] = sources.get(s, 0) + 1
            except OSError as e:
                log.warning("labels_store: cannot read annotations: %s", e)
        return {
            "total": total,
            "unique_images": len(unique_images),
            "sources": sources,
            "annotations_path": self.annotations_path,
        }

    def iter_samples(self) -> Iterator[dict]:
        """Yield each annotation record (one per labeling event)."""
        if not os.path.isfile(self.annotations_path):
            return
        with open(self.annotations_path, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    yield json.loads(line)
                except json.JSONDecodeError:
                    continue

    def image_path(self, digest: str) -> str:
        return os.path.join(self.raw_dir, f"{digest}.jpg")

    # ── Helpers ─────────────────────────────────────────────────────────

    @staticmethod
    def _hash_image(img_bgr: np.ndarray) -> str:
        """16-char sha256 of raw pixel bytes — stable across runs."""
        return hashlib.sha256(img_bgr.tobytes()).hexdigest()[:16]
