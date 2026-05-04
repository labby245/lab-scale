"""High-level video & image processing pipeline orchestrators."""

from __future__ import annotations

import os
import tempfile
from typing import Callable, Optional

import cv2

from . import (
    bg_ops,
    ffmpeg_ops,
    inpaint_ops,
    interpolation_ops,
    lama_ops,
    rife_ops,
    upscale_ops,
)
from .logging_config import get

log = get(__name__)

LogFn = Optional[Callable[[str], None]]


def _has_roi(roi) -> bool:
    if roi is None:
        return False
    if isinstance(roi, dict):
        return int(roi.get("width", 0)) > 0 and int(roi.get("height", 0)) > 0
    return getattr(roi, "width", 0) > 0 and getattr(roi, "height", 0) > 0


def _roi_tuple(roi) -> tuple:
    if isinstance(roi, dict):
        return (int(roi["x"]), int(roi["y"]), int(roi["width"]), int(roi["height"]))
    return (int(roi.x), int(roi.y), int(roi.width), int(roi.height))


def _roi_dict(roi) -> dict:
    if isinstance(roi, dict):
        return roi
    return {"x": roi.x, "y": roi.y, "width": roi.width, "height": roi.height}


def process_video(
    input_path: str,
    output_path: str,
    *,
    roi=None,
    method: str = "telea",
    quality: str = "ultra",
    upscale: bool = False,
    upscale_model: str = "lanczos",
    upscale_scale: int = 2,
    fps_boost: bool = False,
    interp_engine: str = "ffmpeg",
    sharpness: float = 0.0,
    remove_bg: bool = False,
    rembg_model: str = "u2net",
    codec: str = "h264",
    temp_root: Optional[str] = None,
    log_fn: LogFn = None,
) -> None:
    """Run the full video processing pipeline.

    Frame-level order: extract → interpolate → bg-removal → upscale → encode.
    When no frame-level op is needed, runs the FFmpeg-direct fast path."""
    remove_wm = _has_roi(roi)
    use_esrgan = upscale and upscale_model not in ("lanczos", "", None)
    lanczos_scale = (
        upscale_scale
        if (upscale and not use_esrgan and upscale_scale and upscale_scale > 1)
        else None
    )
    need_frames = remove_wm or use_esrgan or remove_bg

    if not need_frames:
        ffmpeg_ops.process_video_direct(
            input_path, output_path, quality, lanczos_scale,
            fps_boost, sharpness, codec=codec, log_fn=log_fn,
        )
        return

    with tempfile.TemporaryDirectory(prefix="frm_", dir=temp_root) as frames_dir:
        if remove_wm:
            if method == "lama" and lama_ops.is_available():
                fps = lama_ops.remove_watermark_roi_to_frames(
                    input_path, frames_dir, _roi_tuple(roi), log_fn=log_fn,
                )
            else:
                if method == "lama" and log_fn:
                    log_fn("LaMa tidak tersedia — pakai Telea sebagai fallback.")
                fallback = "telea" if method == "lama" else method
                fps = inpaint_ops.remove_watermark_roi_to_frames(
                    input_path, frames_dir, _roi_tuple(roi), fallback, log_fn=log_fn,
                )
        else:
            fps = inpaint_ops.extract_frames_to_dir(
                input_path, frames_dir, log_fn=log_fn,
            )

        if fps_boost:
            with tempfile.TemporaryDirectory(prefix="interp_", dir=temp_root) as interp_dir:
                interp_module = (
                    rife_ops if interp_engine == "rife" else interpolation_ops
                )
                fps = interp_module.interpolate_frames_dir(
                    frames_dir, interp_dir, fps, log_fn=log_fn,
                )
                if remove_bg:
                    bg_ops.remove_background_frames_dir(
                        interp_dir, model=rembg_model, log_fn=log_fn,
                    )
                if use_esrgan:
                    upscale_ops.process_frames_dir(
                        interp_dir, upscale_model, upscale_scale,
                        sharpness=sharpness, log_fn=log_fn,
                    )
                ffmpeg_ops.encode_from_frames(
                    interp_dir, fps, input_path, output_path, quality,
                    lanczos_scale if not use_esrgan else None,
                    False,
                    sharpness if not use_esrgan else 0.0,
                    codec=codec, log_fn=log_fn,
                )
            return

        if remove_bg:
            bg_ops.remove_background_frames_dir(
                frames_dir, model=rembg_model, log_fn=log_fn,
            )
        if use_esrgan:
            upscale_ops.process_frames_dir(
                frames_dir, upscale_model, upscale_scale,
                sharpness=sharpness, log_fn=log_fn,
            )
        ffmpeg_ops.encode_from_frames(
            frames_dir, fps, input_path, output_path, quality,
            lanczos_scale if not use_esrgan else None,
            False,
            sharpness if not use_esrgan else 0.0,
            codec=codec, log_fn=log_fn,
        )


def process_image(
    input_path: str,
    output_path: str,
    *,
    roi=None,
    method: str = "telea",
    upscale: bool = False,
    upscale_model: str = "lanczos",
    upscale_scale: int = 2,
    quality: str = "ultra",
    sharpness: float = 0.0,
    remove_bg: bool = False,
    rembg_model: str = "u2net",
    log_fn: LogFn = None,
) -> None:
    """Inpaint and/or remove background and/or upscale a single image."""
    if log_fn:
        log_fn("Membaca gambar…")
    img = cv2.imread(input_path, cv2.IMREAD_COLOR)
    if img is None:
        raise RuntimeError(f"Cannot read image: {input_path}")
    h0, w0 = img.shape[:2]
    if log_fn:
        log_fn(f"Gambar {w0}×{h0} dimuat.")

    if _has_roi(roi):
        roi_dict = _roi_dict(roi)
        if method == "lama" and lama_ops.is_available():
            if log_fn:
                log_fn(f"LaMa inpaint area watermark {roi_dict['width']}×{roi_dict['height']}…")
            img = lama_ops.inpaint_image_array(img, roi_dict)
        else:
            if method == "lama" and log_fn:
                log_fn("LaMa tidak tersedia — pakai Telea sebagai fallback.")
            fallback = "telea" if method == "lama" else method
            if log_fn:
                log_fn(f"Inpaint area watermark {roi_dict['width']}×{roi_dict['height']}…")
            img = inpaint_ops.inpaint_image_array(img, roi_dict, fallback)
        if log_fn:
            log_fn("Inpaint selesai.")

    has_alpha = False
    if remove_bg:
        if not bg_ops.is_available():
            raise RuntimeError("rembg tidak terinstal. Jalankan: pip install rembg")
        if log_fn:
            log_fn(f"Menghapus background ({rembg_model})…")
        bgra = bg_ops.remove_background_image(img, model=rembg_model, log_fn=log_fn)
        img = bgra
        has_alpha = True
        if log_fn:
            log_fn("Background berhasil dihapus.")

    if upscale and upscale_scale > 0:
        target = img
        if has_alpha:
            alpha_ch = img[:, :, 3:4].astype("float32") / 255.0
            bgr_ch = img[:, :, :3].astype("float32")
            target = (bgr_ch * alpha_ch).astype("uint8")

        if upscale_model == "lanczos":
            if upscale_scale > 1:
                if log_fn:
                    log_fn(f"Upscale Lanczos {upscale_scale}×…")
                h1, w1 = target.shape[:2]
                target = cv2.resize(
                    target,
                    (w1 * upscale_scale, h1 * upscale_scale),
                    interpolation=cv2.INTER_LANCZOS4,
                )
            if sharpness > 0:
                target = inpaint_ops.apply_sharpness(target, sharpness)
        else:
            target = upscale_ops.upscale_image(
                target, upscale_model, upscale_scale, sharpness=sharpness,
            )

        if has_alpha:
            orig_alpha = img[:, :, 3]
            h1, w1 = target.shape[:2]
            up_alpha = cv2.resize(orig_alpha, (w1, h1), interpolation=cv2.INTER_LANCZOS4)
            img = cv2.merge([
                target[:, :, 0], target[:, :, 1], target[:, :, 2], up_alpha,
            ])
        else:
            img = target

    if log_fn:
        log_fn(f"Menyimpan hasil ({quality})…")
    if has_alpha or output_path.lower().endswith(".png"):
        cv2.imwrite(output_path, img, [cv2.IMWRITE_PNG_COMPRESSION, 1])
    else:
        q = ffmpeg_ops.IMAGE_JPEG_QUALITY.get(quality, 85)
        cv2.imwrite(output_path, img, [cv2.IMWRITE_JPEG_QUALITY, q])
    if log_fn:
        log_fn("Gambar tersimpan.")
