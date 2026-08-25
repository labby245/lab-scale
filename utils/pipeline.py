"""High-level video & image processing pipeline orchestrators."""

from __future__ import annotations

import tempfile
from typing import Callable, Optional

import cv2

from . import (
    ffmpeg_ops,
    frame_ops,
    interpolation_ops,
    rife_ops,
    upscale_ops,
)
from .logging_config import get

log = get(__name__)

LogFn = Optional[Callable[[str], None]]


def process_video(
    input_path: str,
    output_path: str,
    *,
    quality: str = "ultra",
    upscale: bool = False,
    upscale_model: str = "lanczos",
    upscale_scale: int = 2,
    fps_boost: bool = False,
    interp_engine: str = "ffmpeg",
    sharpness: float = 0.0,
    codec: str = "h264",
    temp_root: Optional[str] = None,
    log_fn: LogFn = None,
) -> None:
    """Run the full video processing pipeline.

    Frame-level order: extract → interpolate → upscale → encode.
    When no frame-level op is needed, runs the FFmpeg-direct fast path."""
    use_esrgan = upscale and upscale_model not in ("lanczos", "", None)
    lanczos_scale = (
        upscale_scale
        if (upscale and not use_esrgan and upscale_scale and upscale_scale > 1)
        else None
    )

    if not use_esrgan:
        ffmpeg_ops.process_video_direct(
            input_path, output_path, quality, lanczos_scale,
            fps_boost, sharpness, codec=codec, log_fn=log_fn,
        )
        return

    with tempfile.TemporaryDirectory(prefix="frm_", dir=temp_root) as frames_dir:
        fps = frame_ops.extract_frames_to_dir(input_path, frames_dir, log_fn=log_fn)

        if fps_boost:
            with tempfile.TemporaryDirectory(prefix="interp_", dir=temp_root) as interp_dir:
                interp_module = (
                    rife_ops if interp_engine == "rife" else interpolation_ops
                )
                fps = interp_module.interpolate_frames_dir(
                    frames_dir, interp_dir, fps, log_fn=log_fn,
                )
                upscale_ops.process_frames_dir(
                    interp_dir, upscale_model, upscale_scale,
                    sharpness=sharpness, log_fn=log_fn,
                )
                ffmpeg_ops.encode_from_frames(
                    interp_dir, fps, input_path, output_path, quality,
                    None, False, 0.0, codec=codec, log_fn=log_fn,
                )
            return

        upscale_ops.process_frames_dir(
            frames_dir, upscale_model, upscale_scale,
            sharpness=sharpness, log_fn=log_fn,
        )
        ffmpeg_ops.encode_from_frames(
            frames_dir, fps, input_path, output_path, quality,
            None, False, 0.0, codec=codec, log_fn=log_fn,
        )


def process_image(
    input_path: str,
    output_path: str,
    *,
    upscale: bool = False,
    upscale_model: str = "lanczos",
    upscale_scale: int = 2,
    quality: str = "ultra",
    sharpness: float = 0.0,
    log_fn: LogFn = None,
) -> None:
    """Upscale and/or sharpen a single image."""
    if log_fn:
        log_fn("Membaca gambar…")
    img = cv2.imread(input_path, cv2.IMREAD_COLOR)
    if img is None:
        raise RuntimeError(f"Cannot read image: {input_path}")
    h0, w0 = img.shape[:2]
    if log_fn:
        log_fn(f"Gambar {w0}×{h0} dimuat.")

    if upscale and upscale_scale > 0:
        if upscale_model == "lanczos":
            if upscale_scale > 1:
                if log_fn:
                    log_fn(f"Upscale Lanczos {upscale_scale}×…")
                img = cv2.resize(
                    img,
                    (w0 * upscale_scale, h0 * upscale_scale),
                    interpolation=cv2.INTER_LANCZOS4,
                )
            img = frame_ops.apply_sharpness(img, sharpness)
        else:
            img = upscale_ops.upscale_image(
                img, upscale_model, upscale_scale, sharpness=sharpness,
            )

    if log_fn:
        log_fn(f"Menyimpan hasil ({quality})…")
    if output_path.lower().endswith(".png"):
        cv2.imwrite(output_path, img, [cv2.IMWRITE_PNG_COMPRESSION, 1])
    else:
        q = ffmpeg_ops.IMAGE_JPEG_QUALITY.get(quality, 85)
        cv2.imwrite(output_path, img, [cv2.IMWRITE_JPEG_QUALITY, q])
    if log_fn:
        log_fn("Gambar tersimpan.")
