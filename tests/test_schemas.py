"""Schema validation tests."""

import pytest
from pydantic import ValidationError

from utils import schemas


def test_minimal_video_request():
    req = schemas.ProcessVideoRequest(filename="clip.mp4")
    assert req.quality == "ultra"
    assert req.codec == "h264"
    assert req.upscale is False
    assert not req.has_any_op


def test_filename_rejects_path_separator():
    with pytest.raises(ValidationError):
        schemas.ProcessVideoRequest(filename="../etc/passwd")
    with pytest.raises(ValidationError):
        schemas.ProcessVideoRequest(filename="sub/clip.mp4")
    with pytest.raises(ValidationError):
        schemas.ProcessVideoRequest(filename="a\\b.mp4")


def test_upscale_scale_bounds():
    schemas.ProcessVideoRequest(filename="x.mp4", upscale_scale=4)
    with pytest.raises(ValidationError):
        schemas.ProcessVideoRequest(filename="x.mp4", upscale_scale=0)
    with pytest.raises(ValidationError):
        schemas.ProcessVideoRequest(filename="x.mp4", upscale_scale=99)


def test_sharpness_bounds():
    schemas.ProcessVideoRequest(filename="x.mp4", sharpness=0.5)
    with pytest.raises(ValidationError):
        schemas.ProcessVideoRequest(filename="x.mp4", sharpness=-0.1)
    with pytest.raises(ValidationError):
        schemas.ProcessVideoRequest(filename="x.mp4", sharpness=1.5)


def test_invalid_codec_rejected():
    with pytest.raises(ValidationError):
        schemas.ProcessVideoRequest(filename="x.mp4", codec="vp9")


def test_invalid_upscale_model_rejected():
    with pytest.raises(ValidationError):
        schemas.ProcessVideoRequest(filename="x.mp4", upscale_model="not-a-model")


def test_bulk_request_empty_files():
    req = schemas.BulkRequest(files=[])
    assert req.files == []


def test_bulk_request_files():
    req = schemas.BulkRequest(
        files=[{"filename": "a.mp4"}, {"filename": "b.png", "isImage": True}],
    )
    assert len(req.files) == 2
    assert req.files[0].filename == "a.mp4"


def test_open_folder_request():
    req = schemas.OpenFolderRequest(path="/tmp/x")
    assert req.path == "/tmp/x"


def test_has_any_op_combinations():
    base = {"filename": "x.mp4"}
    assert not schemas.ProcessVideoRequest(**base).has_any_op
    assert schemas.ProcessVideoRequest(**base, upscale=True).has_any_op
    assert schemas.ProcessVideoRequest(**base, fps_boost=True).has_any_op


def test_interp_engine_default_and_values():
    req = schemas.ProcessVideoRequest(filename="x.mp4")
    assert req.interp_engine == "ffmpeg"
    schemas.ProcessVideoRequest(filename="x.mp4", interp_engine="rife")
    with pytest.raises(ValidationError):
        schemas.ProcessVideoRequest(filename="x.mp4", interp_engine="invalid")
