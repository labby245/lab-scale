"""Smoke tests for optional modules — verify graceful fallback when deps absent."""

from utils import rife_ops


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
