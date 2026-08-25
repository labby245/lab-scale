"""Pydantic v2 schemas for API request bodies."""

from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, Field, field_validator

InterpolationEngine = Literal["ffmpeg", "rife"]
Quality = Literal["fast", "balanced", "better", "best", "ultra"]
UpscaleModel = Literal[
    "lanczos",
    "realesrgan-x4plus",
    "realesrgan-x4plus-anime",
    "realesr-animevideov3",
]
VideoCodec = Literal["h264", "hevc", "av1"]


class ProcessOptions(BaseModel):
    """Common fields shared by /process, /process-image, /process-bulk."""

    quality: Quality = "ultra"
    upscale: bool = False
    upscale_model: UpscaleModel = "lanczos"
    upscale_scale: int = Field(2, ge=1, le=4)
    fps_boost: bool = False
    interp_engine: InterpolationEngine = "ffmpeg"
    sharpness: float = Field(0.0, ge=0.0, le=1.0)
    codec: VideoCodec = "h264"
    job_id: str = ""

    @property
    def has_any_op(self) -> bool:
        return self.upscale or self.fps_boost


def _no_path(v: str) -> str:
    if "/" in v or "\\" in v or ".." in v:
        raise ValueError("filename must not contain path separators")
    return v


class ProcessVideoRequest(ProcessOptions):
    filename: str

    @field_validator("filename")
    @classmethod
    def _validate_filename(cls, v: str) -> str:
        return _no_path(v)


class ProcessImageRequest(ProcessVideoRequest):
    pass


class BulkFileEntry(BaseModel):
    filename: str
    originalBase: Optional[str] = None
    isImage: Optional[bool] = None

    @field_validator("filename")
    @classmethod
    def _validate_filename(cls, v: str) -> str:
        return _no_path(v)


class BulkRequest(ProcessOptions):
    files: list[BulkFileEntry] = Field(default_factory=list)


class OpenFolderRequest(BaseModel):
    path: str
