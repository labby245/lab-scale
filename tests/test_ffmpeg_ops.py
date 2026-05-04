"""ffmpeg_ops pure-function tests."""

from utils import ffmpeg_ops, gpu


def test_build_vf_empty():
    assert ffmpeg_ops.build_vf(None, False, 0.0) is None
    assert ffmpeg_ops.build_vf(0, False, 0.0) is None
    assert ffmpeg_ops.build_vf(1, False, 0.0) is None


def test_build_vf_lanczos_only():
    vf = ffmpeg_ops.build_vf(2, False, 0.0)
    assert vf is not None
    assert "scale=iw*2:ih*2" in vf
    assert "lanczos" in vf
    assert "minterpolate" not in vf


def test_build_vf_fps_boost_uses_mci_bidir():
    vf = ffmpeg_ops.build_vf(None, True, 0.0)
    assert "minterpolate=fps=60" in vf
    assert "mi_mode=mci" in vf
    assert "me_mode=bidir" in vf
    assert "mi_mode=blend" not in vf


def test_build_vf_sharpness_only():
    vf = ffmpeg_ops.build_vf(None, False, 0.5)
    assert "unsharp" in vf
    assert "0.75" in vf  # 0.5 * 1.5


def test_build_vf_combined():
    vf = ffmpeg_ops.build_vf(2, True, 0.3)
    assert "scale=iw*2" in vf
    assert "minterpolate" in vf
    assert "unsharp" in vf
    assert vf.count(",") == 2


def test_select_encoder_h264_fallback(monkeypatch):
    monkeypatch.setattr(gpu, "_AVAILABLE_ENCODERS", set())
    enc, qt, pf = ffmpeg_ops.select_encoder("h264")
    assert enc == "libx264"
    assert pf == "yuv420p"
    assert "ultra" in qt


def test_select_encoder_h264_nvenc_preferred(monkeypatch):
    monkeypatch.setattr(gpu, "_AVAILABLE_ENCODERS", {"h264_nvenc", "libx264"})
    enc, _, _ = ffmpeg_ops.select_encoder("h264")
    assert enc == "h264_nvenc"


def test_select_encoder_hevc_nvenc(monkeypatch):
    monkeypatch.setattr(gpu, "_AVAILABLE_ENCODERS", {"hevc_nvenc", "libx264"})
    enc, _, _ = ffmpeg_ops.select_encoder("hevc")
    assert enc == "hevc_nvenc"


def test_select_encoder_hevc_falls_back_to_x265(monkeypatch):
    monkeypatch.setattr(gpu, "_AVAILABLE_ENCODERS", {"libx265", "libx264"})
    enc, _, _ = ffmpeg_ops.select_encoder("hevc")
    assert enc == "libx265"


def test_select_encoder_hevc_falls_back_to_h264_when_no_x265(monkeypatch):
    monkeypatch.setattr(gpu, "_AVAILABLE_ENCODERS", {"libx264"})
    enc, _, _ = ffmpeg_ops.select_encoder("hevc")
    assert enc == "libx264"


def test_select_encoder_av1_nvenc(monkeypatch):
    monkeypatch.setattr(gpu, "_AVAILABLE_ENCODERS", {"av1_nvenc", "libx264"})
    enc, _, _ = ffmpeg_ops.select_encoder("av1")
    assert enc == "av1_nvenc"


def test_select_encoder_av1_svt(monkeypatch):
    monkeypatch.setattr(gpu, "_AVAILABLE_ENCODERS", {"libsvtav1", "libx264"})
    enc, _, _ = ffmpeg_ops.select_encoder("av1")
    assert enc == "libsvtav1"


def test_quality_tables_have_all_levels():
    levels = {"fast", "balanced", "better", "best", "ultra"}
    for table in (
        ffmpeg_ops.QUALITY_X264,
        ffmpeg_ops.QUALITY_X265,
        ffmpeg_ops.QUALITY_AV1_CPU,
        ffmpeg_ops.QUALITY_H264_NVENC,
        ffmpeg_ops.QUALITY_HEVC_NVENC,
        ffmpeg_ops.QUALITY_AV1_NVENC,
    ):
        assert set(table.keys()) == levels


def test_image_jpeg_quality_levels():
    levels = {"fast", "balanced", "better", "best", "ultra"}
    assert set(ffmpeg_ops.IMAGE_JPEG_QUALITY.keys()) == levels
    seq = [
        ffmpeg_ops.IMAGE_JPEG_QUALITY[k]
        for k in ("fast", "balanced", "better", "best")
    ]
    assert seq == sorted(seq)
