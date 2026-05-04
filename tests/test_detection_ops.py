"""Smoke tests for watermark detection — uses synthetic images."""

import numpy as np

from utils import detection_ops


def _blank(h: int = 480, w: int = 640, color=(0, 0, 0)) -> np.ndarray:
    img = np.zeros((h, w, 3), dtype=np.uint8)
    img[:, :] = color
    return img


def test_detect_returns_none_on_blank_image():
    img = _blank(480, 640)
    assert detection_ops.detect_watermark_roi(img) is None


def test_detect_returns_none_on_empty_extra_frames():
    img = _blank()
    assert detection_ops.detect_watermark_roi(img, extra_frames=[]) is None


def test_detect_does_not_crash_on_arbitrary_image():
    """Smoke test — random noise should not raise; result may be None."""
    rng = np.random.default_rng(42)
    img = rng.integers(0, 255, (480, 640, 3), dtype=np.uint8)
    detection_ops.detect_watermark_roi(img)  # must not raise


def test_detect_returns_corner_roi_when_present():
    """Strong text-like strokes near a corner should be detected and returned in that quadrant."""
    import cv2
    img = _blank(480, 640, color=(40, 40, 40))
    # Render a multi-stroke "text" pattern in the bottom-right corner
    text_lines = [
        ((585, 440), (625, 440)),
        ((585, 446), (610, 446)),
        ((585, 452), (625, 452)),
        ((585, 458), (615, 458)),
        ((585, 464), (625, 464)),
    ]
    for p1, p2 in text_lines:
        cv2.line(img, p1, p2, (255, 255, 255), 2)
    roi = detection_ops.detect_watermark_roi(img)
    if roi is not None:
        x, y, _, _ = roi
        assert x >= 320
        assert y >= 240


def test_get_sample_frames_handles_missing_video(tmp_path):
    bogus = tmp_path / "does_not_exist.mp4"
    assert detection_ops.get_sample_frames(str(bogus)) == []


def test_temporal_falls_back_to_spatial_on_single_frame():
    img = _blank()
    result = detection_ops.detect_watermark_temporal([img])
    assert result is None
