"""RIFE frame interpolation wrapper. Optional — needs rife-ncnn-vulkan binary.

Install:
  Windows: download rife-ncnn-vulkan-*.zip from
    https://github.com/nihui/rife-ncnn-vulkan/releases
    Extract to <project>/bin/  so that <project>/bin/rife-ncnn-vulkan.exe exists,
    or place the binary anywhere on your PATH.

Falls back to FFmpeg minterpolate (utils.interpolation_ops) when not installed.
RIFE is 5-10x faster than minterpolate and produces dramatically smoother motion."""

from __future__ import annotations

import os
import shutil
import subprocess
from typing import Callable, Optional

from .logging_config import get

log = get(__name__)

LogFn = Optional[Callable[[str], None]]

_BINARY_PATH: Optional[str] = None
_PROBED = False


def _project_bin_dir() -> str:
    """Resolve <project_root>/bin/ for bundled binaries."""
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(here, "bin")


def find_binary() -> Optional[str]:
    """Locate rife-ncnn-vulkan executable. Caches result."""
    global _BINARY_PATH, _PROBED
    if _PROBED:
        return _BINARY_PATH

    candidates = [
        os.path.join(_project_bin_dir(), "rife-ncnn-vulkan.exe"),
        os.path.join(_project_bin_dir(), "rife-ncnn-vulkan"),
    ]
    for c in candidates:
        if os.path.isfile(c):
            _BINARY_PATH = c
            _PROBED = True
            return _BINARY_PATH

    on_path = shutil.which("rife-ncnn-vulkan") or shutil.which("rife-ncnn-vulkan.exe")
    _BINARY_PATH = on_path
    _PROBED = True
    return _BINARY_PATH


def is_available() -> bool:
    return find_binary() is not None


def _model_dir(binary_path: str) -> Optional[str]:
    """Find the model directory next to the binary (bundled with releases)."""
    base = os.path.dirname(os.path.abspath(binary_path))
    for name in ("rife-v4.6", "rife-v4", "rife-anime", "rife"):
        cand = os.path.join(base, name)
        if os.path.isdir(cand):
            return cand
    if os.path.isfile(os.path.join(base, "flownet.bin")):
        return base
    return None


def interpolate_frames_dir(
    frames_dir: str,
    output_dir: str,
    fps: float,
    target_fps: float = 60.0,
    log_fn: LogFn = None,
) -> float:
    """Interpolate frames using RIFE if available, else fall back to FFmpeg."""
    if not is_available():
        from . import interpolation_ops
        if log_fn:
            log_fn("RIFE tidak ditemukan — pakai FFmpeg minterpolate.")
        return interpolation_ops.interpolate_frames_dir(
            frames_dir, output_dir, fps, target_fps=target_fps, log_fn=log_fn,
        )

    os.makedirs(output_dir, exist_ok=True)
    binary = find_binary()
    assert binary is not None
    model_dir = _model_dir(binary)

    src_count = len(
        [f for f in os.listdir(frames_dir) if f.endswith(".png")]
    )
    if src_count == 0:
        return float(fps)
    duration = src_count / max(fps, 0.001)
    target_count = max(2, int(round(duration * target_fps)))

    if log_fn:
        log_fn(
            f"RIFE: {src_count} frame @ {fps:.2f}fps → "
            f"{target_count} frame @ {target_fps:.0f}fps"
        )

    cmd = [binary, "-i", frames_dir, "-o", output_dir, "-n", str(target_count)]
    if model_dir:
        cmd += ["-m", model_dir]

    log.debug("rife cmd: %s", " ".join(cmd))
    proc = subprocess.run(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, env=os.environ.copy(),
    )
    if proc.returncode != 0:
        tail = (proc.stderr or "")[-1500:]
        log.error("RIFE failed: %s", tail)
        if log_fn:
            log_fn("RIFE gagal — fallback ke FFmpeg minterpolate.")
        from . import interpolation_ops
        return interpolation_ops.interpolate_frames_dir(
            frames_dir, output_dir, fps, target_fps=target_fps, log_fn=log_fn,
        )

    # RIFE outputs as 0000001.png — rename to frame_%06d.png for pipeline consistency.
    fnames = sorted(f for f in os.listdir(output_dir) if f.endswith(".png"))
    for i, fname in enumerate(fnames):
        target = f"frame_{i:06d}.png"
        if fname != target:
            src = os.path.join(output_dir, fname)
            dst = os.path.join(output_dir, target)
            if src != dst:
                os.replace(src, dst)

    if log_fn:
        log_fn(f"RIFE selesai → {len(fnames)} frame @ {target_fps:.0f}fps.")
    return target_fps
