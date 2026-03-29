import cv2
import numpy as np
from typing import Tuple
import os
import subprocess
import json

QUALITY_PRESETS = {
    'fast':     ['-preset', 'veryfast', '-crf', '23'],
    'balanced': ['-preset', 'medium',   '-crf', '20'],
    'better':   ['-preset', 'slow',     '-crf', '18'],
    'best':     ['-preset', 'veryslow', '-crf', '16'],
    'ultra':    ['-preset', 'placebo',  '-crf', '0'],
}


def remove_watermark_roi_to_frames(
    input_video_path: str,
    output_frames_dir: str,
    roi: Tuple[int, int, int, int],
    inpaint_method: str = 'telea',
) -> float:
    """Remove watermark and save lossless PNG frames. Returns source FPS."""
    os.makedirs(output_frames_dir, exist_ok=True)

    cap = cv2.VideoCapture(input_video_path)
    if not cap.isOpened():
        raise RuntimeError('Failed to open input video')

    width  = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps    = cap.get(cv2.CAP_PROP_FPS) or 25.0

    x, y, w, h = roi
    x = max(0, min(x, width  - 1))
    y = max(0, min(y, height - 1))
    w = max(1, min(w, width  - x))
    h = max(1, min(h, height - y))

    flags = cv2.INPAINT_TELEA if inpaint_method.lower() == 'telea' else cv2.INPAINT_NS

    idx = 0
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        mask = np.zeros((height, width), dtype=np.uint8)
        mask[y:y+h, x:x+w] = 255
        inpainted = cv2.inpaint(frame, mask, 3, flags)
        fname = os.path.join(output_frames_dir, f'frame_{idx:06d}.png')
        if not cv2.imwrite(fname, inpainted):
            cap.release()
            raise RuntimeError(f'Failed to write frame {fname}')
        idx += 1

    cap.release()
    return float(fps)


def probe_video_info(path: str) -> dict:
    """Return dict with width, height, fps via ffprobe."""
    cmd = [
        'ffprobe', '-v', 'error', '-select_streams', 'v:0',
        '-show_entries', 'stream=width,height,r_frame_rate',
        '-of', 'json', path,
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    defaults = {'width': 1920, 'height': 1080, 'fps': 25.0}
    if proc.returncode != 0:
        return defaults
    try:
        s = json.loads(proc.stdout)['streams'][0]
        num, den = s.get('r_frame_rate', '25/1').split('/')
        fps = float(num) / max(float(den), 1)
        return {'width': int(s['width']), 'height': int(s['height']), 'fps': fps}
    except Exception:
        return defaults


def _build_vf(upscale: bool, fps_boost: bool) -> str | None:
    parts = []
    if upscale:
        parts.append('scale=iw*2:ih*2:flags=lanczos')
    if fps_boost:
        parts.append("minterpolate=fps=60:mi_mode=mci:mc_mode=aobmc:vsbmc=1")
    return ','.join(parts) if parts else None


def encode_from_frames(
    frames_dir: str,
    fps: float,
    source_audio: str,
    output_path: str,
    quality: str = 'ultra',
    upscale: bool = False,
    fps_boost: bool = False,
) -> None:
    """Encode PNG frames to final video with optional upscale / fps_boost."""
    q_args  = QUALITY_PRESETS.get(quality, QUALITY_PRESETS['ultra'])
    vf      = _build_vf(upscale, fps_boost)
    pattern = os.path.join(frames_dir, 'frame_%06d.png')

    cmd = [
        'ffmpeg', '-y',
        '-framerate', str(fps), '-i', pattern,
        '-i', source_audio,
        '-map', '0:v:0', '-map', '1:a:0?',
        '-c:v', 'libx264', *q_args,
        '-pix_fmt', 'yuv420p',
        '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709',
        '-movflags', '+faststart',
        '-c:a', 'aac', '-b:a', '192k',
    ]
    if vf:
        cmd += ['-filter:v', vf]
    cmd.append(output_path)
    _run(cmd)


def process_video_direct(
    input_path: str,
    output_path: str,
    quality: str = 'ultra',
    upscale: bool = False,
    fps_boost: bool = False,
) -> None:
    """Re-encode video via FFmpeg only (upscale and/or fps_boost, no watermark removal)."""
    q_args = QUALITY_PRESETS.get(quality, QUALITY_PRESETS['ultra'])
    vf     = _build_vf(upscale, fps_boost)

    cmd = [
        'ffmpeg', '-y',
        '-i', input_path,
        '-c:v', 'libx264', *q_args,
        '-pix_fmt', 'yuv420p',
        '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709',
        '-movflags', '+faststart',
        '-c:a', 'aac', '-b:a', '192k',
    ]
    if vf:
        cmd += ['-filter:v', vf]
    cmd.append(output_path)
    _run(cmd)


def _run(cmd: list) -> None:
    proc = subprocess.run(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        env=os.environ.copy(), text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(f'FFmpeg error: {proc.stderr[:1200]}')
