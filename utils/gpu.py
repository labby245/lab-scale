"""GPU and FFmpeg encoder probing. All results cached at module level."""

from __future__ import annotations

import subprocess
from typing import Optional

from .logging_config import get

log = get(__name__)

_GPU_ID: Optional[int] = None
_GPU_VRAM_GB: Optional[float] = None
_AVAILABLE_ENCODERS: Optional[set] = None


def get_gpu_id() -> int:
    """Return 0 if any CUDA GPU is available, -1 otherwise."""
    global _GPU_ID
    if _GPU_ID is not None:
        return _GPU_ID
    try:
        import torch  # type: ignore

        _GPU_ID = 0 if torch.cuda.is_available() else -1
    except ImportError:
        _GPU_ID = -1
    return _GPU_ID


def get_gpu_vram_gb() -> float:
    """Return total VRAM of GPU 0 in GB. 0.0 if no GPU."""
    global _GPU_VRAM_GB
    if _GPU_VRAM_GB is not None:
        return _GPU_VRAM_GB
    if get_gpu_id() < 0:
        _GPU_VRAM_GB = 0.0
        return _GPU_VRAM_GB
    try:
        import torch  # type: ignore

        props = torch.cuda.get_device_properties(0)
        _GPU_VRAM_GB = props.total_memory / (1024**3)
    except Exception as e:
        log.warning("could not probe VRAM: %s", e)
        _GPU_VRAM_GB = 0.0
    return _GPU_VRAM_GB


def _probe_encoders() -> set:
    """Run `ffmpeg -encoders` once and parse encoder names available."""
    global _AVAILABLE_ENCODERS
    if _AVAILABLE_ENCODERS is not None:
        return _AVAILABLE_ENCODERS
    try:
        result = subprocess.run(
            ["ffmpeg", "-hide_banner", "-encoders"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
        )
        encs = set()
        for line in result.stdout.splitlines():
            parts = line.split()
            if len(parts) >= 2 and parts[0].startswith(("V", "A")):
                encs.add(parts[1])
        _AVAILABLE_ENCODERS = encs
    except Exception as e:
        log.warning("ffmpeg encoder probe failed: %s", e)
        _AVAILABLE_ENCODERS = set()
    return _AVAILABLE_ENCODERS


def has_encoder(name: str) -> bool:
    return name in _probe_encoders()


def auto_tile_size() -> int:
    """Pick ESRGAN tile size based on VRAM. Smaller VRAM → smaller tile."""
    vram = get_gpu_vram_gb()
    if vram <= 0:
        return 256
    if vram < 4:
        return 192
    if vram < 6:
        return 256
    if vram < 8:
        return 384
    if vram < 12:
        return 512
    return 768
