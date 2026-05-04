"""Smoke tests for optional modules — verify graceful fallback when deps absent."""

import numpy as np

from utils import lama_ops, rife_ops, yolo_detect


# ── LaMa ────────────────────────────────────────────────────────────────────


def test_lama_is_available_returns_bool():
    """is_available() must always return a bool, never raise."""
    assert isinstance(lama_ops.is_available(), bool)


def test_lama_inpaint_raises_clearly_when_missing(monkeypatch):
    monkeypatch.setattr(lama_ops, "is_available", lambda: False)
    img = np.zeros((10, 10, 3), dtype=np.uint8)
    mask = np.zeros((10, 10), dtype=np.uint8)
    raised = False
    try:
        lama_ops.inpaint_bgr(img, mask)
    except RuntimeError as e:
        raised = True
        assert "lama" in str(e).lower() or "install" in str(e).lower()
    assert raised


# ── RIFE ────────────────────────────────────────────────────────────────────


def test_rife_find_binary_handles_missing(monkeypatch):
    monkeypatch.setattr(rife_ops, "_BINARY_PATH", None)
    monkeypatch.setattr(rife_ops, "_PROBED", False)
    result = rife_ops.find_binary()
    assert result is None or isinstance(result, str)


def test_rife_is_available_returns_bool():
    assert isinstance(rife_ops.is_available(), bool)


def test_rife_falls_back_to_ffmpeg_when_no_binary(tmp_path, monkeypatch):
    monkeypatch.setattr(rife_ops, "_BINARY_PATH", None)
    monkeypatch.setattr(rife_ops, "_PROBED", True)

    called = {"flag": False}

    def fake_interp(frames_dir, output_dir, fps, target_fps=60.0, log_fn=None):
        called["flag"] = True
        return target_fps

    import utils.interpolation_ops as iops
    monkeypatch.setattr(iops, "interpolate_frames_dir", fake_interp)
    out = rife_ops.interpolate_frames_dir(
        str(tmp_path / "in"), str(tmp_path / "out"), 30.0, 60.0,
    )
    assert called["flag"] is True
    assert out == 60.0


# ── YOLO ────────────────────────────────────────────────────────────────────


def test_yolo_is_available_returns_bool():
    assert isinstance(yolo_detect.is_available(), bool)


def test_yolo_detect_returns_none_when_unavailable(monkeypatch):
    monkeypatch.setattr(yolo_detect, "is_available", lambda: False)
    img = np.zeros((100, 100, 3), dtype=np.uint8)
    assert yolo_detect.detect_with_yolo(img) is None


def test_yolo_resolve_model_returns_none_when_no_file(monkeypatch, tmp_path):
    monkeypatch.setattr(yolo_detect, "_MODEL_PROBED", False)
    monkeypatch.setattr(yolo_detect, "_MODEL_PATH", None)
    monkeypatch.setattr(yolo_detect, "_project_models_dir", lambda: str(tmp_path))
    assert yolo_detect._resolve_model_path() is None
