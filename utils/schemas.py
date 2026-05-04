"""Pydantic v2 schemas for API request bodies."""

from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, Field, field_validator

InpaintMethod = Literal["telea", "ns", "lama"]
InterpolationEngine = Literal["ffmpeg", "rife"]
Quality = Literal["fast", "balanced", "better", "best", "ultra"]
UpscaleModel = Literal[
    "lanczos",
    "realesrgan-x4plus",
    "realesrgan-x4plus-anime",
    "realesr-animevideov3",
]
RembgModel = Literal[
    "u2net",
    "u2netp",
    "u2net_human_seg",
    "isnet-general-use",
    "birefnet-general",
]
VideoCodec = Literal["h264", "hevc", "av1"]


class ROI(BaseModel):
    x: int = Field(ge=0)
    y: int = Field(ge=0)
    width: int = Field(ge=0)
    height: int = Field(ge=0)


class ProcessOptions(BaseModel):
    """Common fields shared by /process, /process-image, /process-bulk."""

    roi: Optional[ROI] = None
    method: InpaintMethod = "telea"
    quality: Quality = "ultra"
    upscale: bool = False
    upscale_model: UpscaleModel = "lanczos"
    upscale_scale: int = Field(2, ge=1, le=4)
    fps_boost: bool = False
    interp_engine: InterpolationEngine = "ffmpeg"
    sharpness: float = Field(0.0, ge=0.0, le=1.0)
    remove_bg: bool = False
    rembg_model: RembgModel = "u2net"
    codec: VideoCodec = "h264"
    job_id: str = ""

    @property
    def has_roi(self) -> bool:
        return (
            self.roi is not None
            and self.roi.width > 0
            and self.roi.height > 0
        )

    @property
    def has_any_op(self) -> bool:
        return self.has_roi or self.upscale or self.fps_boost or self.remove_bg


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


class DetectRequest(BaseModel):
    filename: str

    @field_validator("filename")
    @classmethod
    def _validate_filename(cls, v: str) -> str:
        return _no_path(v)


class OpenFolderRequest(BaseModel):
    path: str


LabelSource = Literal["manual", "auto", "correction"]


class SaveLabelRequest(BaseModel):
    """Save a user-confirmed (image, roi) sample for YOLO training."""

    filename: str
    roi: ROI
    source: LabelSource = "manual"
    frame_index: Optional[int] = None  # for video: which frame to capture

    @field_validator("filename")
    @classmethod
    def _validate_filename(cls, v: str) -> str:
        return _no_path(v)
