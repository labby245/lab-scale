"""ESRGAN upscaling with model + upsampler caching and auto-tile sizing."""

from __future__ import annotations

import os
import sys
import threading
import types
from typing import Callable, Optional

import cv2
import numpy as np

from .gpu import auto_tile_size, get_gpu_id, get_gpu_vram_gb
from .inpaint_ops import apply_sharpness
from .logging_config import get

log = get(__name__)

LogFn = Optional[Callable[[str], None]]

_UPSAMPLER_CACHE: dict = {}
_CACHE_LOCK = threading.Lock()

_ESRGAN_MODELS = {
    "realesrgan-x4plus": {
        "url": (
            "https://github.com/xinntao/Real-ESRGAN/releases/download/"
            "v0.1.0/RealESRGAN_x4plus.pth"
        ),
        "arch": "rrdb",
        "num_block": 23,
    },
    "realesrgan-x4plus-anime": {
        "url": (
            "https://github.com/xinntao/Real-ESRGAN/releases/download/"
            "v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth"
        ),
        "arch": "rrdb",
        "num_block": 6,
    },
    "realesr-animevideov3": {
        "url": (
            "https://github.com/xinntao/Real-ESRGAN/releases/download/"
            "v0.2.5.0/realesr-animevideov3.pth"
        ),
        "arch": "srvgg",
    },
}


def _patch_torchvision() -> None:
    """Compatibility shim for torchvision >= 0.16 (functional_tensor removed)."""
    if "torchvision.transforms.functional_tensor" in sys.modules:
        return
    try:
        import torchvision.transforms.functional as F  # type: ignore

        ft = types.ModuleType("torchvision.transforms.functional_tensor")
        for name in dir(F):
            try:
                setattr(ft, name, getattr(F, name))
            except Exception as e:
                log.debug("torchvision shim skip %s: %s", name, e)
        sys.modules["torchvision.transforms.functional_tensor"] = ft
    except ImportError as e:
        log.debug("torchvision shim unavailable: %s", e)


def is_available() -> bool:
    try:
        _patch_torchvision()
        import realesrgan  # noqa: F401
        import basicsr     # noqa: F401
        return True
    except Exception as e:
        log.debug("ESRGAN unavailable: %s", e)
        return False


def _build_arch(model_key: str):
    _patch_torchvision()
    spec = _ESRGAN_MODELS[model_key]
    if spec["arch"] == "rrdb":
        from basicsr.archs.rrdbnet_arch import RRDBNet  # type: ignore

        return RRDBNet(
            num_in_ch=3, num_out_ch=3, num_feat=64,
            num_block=spec["num_block"], num_grow_ch=32, scale=4,
        )
    if spec["arch"] == "srvgg":
        from realesrgan.archs.srvgg_arch import SRVGGNetCompact  # type: ignore

        return SRVGGNetCompact(
            num_in_ch=3, num_out_ch=3, num_feat=64,
            num_conv=16, upscale=4, act_type="prelu",
        )
    raise RuntimeError(f"Unknown ESRGAN arch: {spec['arch']}")


def get_upsampler(model_key: str):
    """Return a cached RealESRGANer for the model. Built once per process."""
    if model_key not in _ESRGAN_MODELS:
        raise RuntimeError(f"Unknown ESRGAN model: {model_key}")
    with _CACHE_LOCK:
        if model_key in _UPSAMPLER_CACHE:
            return _UPSAMPLER_CACHE[model_key]

        _patch_torchvision()  # must come before realesrgan/basicsr import
        from realesrgan import RealESRGANer  # type: ignore

        gpu_id = get_gpu_id()
        tile = auto_tile_size()
        use_half = gpu_id >= 0 and get_gpu_vram_gb() >= 4.0
        log.info(
            "Building ESRGAN '%s' on %s (tile=%d, half=%s)",
            model_key,
            "GPU" if gpu_id >= 0 else "CPU",
            tile,
            use_half,
        )
        upsampler = RealESRGANer(
            scale=4,
            model_path=_ESRGAN_MODELS[model_key]["url"],
            model=_build_arch(model_key),
            tile=tile,
            tile_pad=10,
            pre_pad=0,
            half=use_half,
            gpu_id=gpu_id if gpu_id >= 0 else None,
        )
        _UPSAMPLER_CACHE[model_key] = upsampler
        return upsampler


def upscale_image(
    img_bgr: np.ndarray,
    model_key: str,
    target_scale: int,
    sharpness: float = 0.0,
) -> np.ndarray:
    if not is_available():
        raise RuntimeError(
            "realesrgan tidak terinstal. Jalankan: pip install realesrgan basicsr"
        )
    upsampler = get_upsampler(model_key)
    output, _ = upsampler.enhance(img_bgr, outscale=4)
    if target_scale != 4:
        h0, w0 = img_bgr.shape[:2]
        new_w = max(1, int(w0 * target_scale))
        new_h = max(1, int(h0 * target_scale))
        output = cv2.resize(output, (new_w, new_h), interpolation=cv2.INTER_LANCZOS4)
    return apply_sharpness(output, sharpness)


def process_frames_dir(
    frames_dir: str,
    model_key: str,
    target_scale: int,
    sharpness: float = 0.0,
    log_fn: LogFn = None,
) -> None:
    """Apply ESRGAN to every PNG frame in-place."""
    fnames = sorted(f for f in os.listdir(frames_dir) if f.endswith(".png"))
    total = len(fnames)
    if total == 0:
        return

    gpu_id = get_gpu_id()
    device_info = (
        f"GPU (CUDA:{gpu_id}, {get_gpu_vram_gb():.1f}GB)"
        if gpu_id >= 0 else "CPU"
    )
    if log_fn:
        sharp_info = f", sharpness={sharpness:.2f}" if sharpness > 0 else ""
        log_fn(f"ESRGAN: model {model_key} di {device_info}{sharp_info}…")

    upsampler = get_upsampler(model_key)
    for i, fname in enumerate(fnames):
        fpath = os.path.join(frames_dir, fname)
        img = cv2.imread(fpath, cv2.IMREAD_COLOR)
        if img is None:
            log.warning("could not read frame %s — skipping", fpath)
            continue
        out, _ = upsampler.enhance(img, outscale=4)
        if target_scale != 4:
            h0, w0 = img.shape[:2]
            out = cv2.resize(
                out,
                (max(1, int(w0 * target_scale)), max(1, int(h0 * target_scale))),
                interpolation=cv2.INTER_LANCZOS4,
            )
        out = apply_sharpness(out, sharpness)
        cv2.imwrite(fpath, out)
        if log_fn and (i % 10 == 0 or i == total - 1):
            log_fn(f"ESRGAN: frame {i + 1}/{total}")
