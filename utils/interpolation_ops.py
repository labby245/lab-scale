"""Frame interpolation via FFmpeg minterpolate (MCI / bidir motion-compensation)."""

from __future__ import annotations

import os
from typing import Callable, Optional

from .ffmpeg_ops import run
from .logging_config import get

log = get(__name__)

LogFn = Optional[Callable[[str], None]]


def interpolate_frames_dir(
    frames_dir: str,
    output_dir: str,
    fps: float,
    target_fps: float = 60.0,
    log_fn: LogFn = None,
) -> float:
    """Interpolate PNG frames to target_fps using FFmpeg MCI/bidir.

    Use BEFORE upscaling so interpolation runs on original-resolution frames."""
    os.makedirs(output_dir, exist_ok=True)
    if log_fn:
        log_fn(f"Interpolasi {fps:.2f}fps → {target_fps:.0f}fps (MCI/bidir)…")

    pattern_in = os.path.join(frames_dir, "frame_%06d.png")
    pattern_out = os.path.join(output_dir, "frame_%06d.png")

    vf = (
        f"minterpolate=fps={target_fps}:mi_mode=mci:"
        f"mc_mode=aobmc:me_mode=bidir:vsbmc=1"
    )
    cmd = [
        "ffmpeg", "-y",
        "-framerate", str(fps),
        "-i", pattern_in,
        "-vf", vf,
        "-r", str(target_fps),
        pattern_out,
    ]
    run(cmd)

    if log_fn:
        n = len([f for f in os.listdir(output_dir) if f.endswith(".png")])
        log_fn(f"Interpolasi selesai → {n} frame @ {target_fps:.0f}fps.")
    return target_fps
