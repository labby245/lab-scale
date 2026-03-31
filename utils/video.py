import cv2
import numpy as np
from typing import Tuple, Optional, Callable
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

# NVENC (NVIDIA GPU) quality presets — uses CQ mode (no -crf)
QUALITY_PRESETS_NVENC = {
    'fast':     ['-preset', 'fast',   '-rc:v', 'vbr', '-cq', '23', '-b:v', '0'],
    'balanced': ['-preset', 'medium', '-rc:v', 'vbr', '-cq', '20', '-b:v', '0'],
    'better':   ['-preset', 'slow',   '-rc:v', 'vbr', '-cq', '18', '-b:v', '0'],
    'best':     ['-preset', 'slow',   '-rc:v', 'vbr', '-cq', '16', '-b:v', '0'],
    'ultra':    ['-preset', 'slow',   '-rc:v', 'vbr', '-cq', '1',  '-b:v', '0'],
}

IMAGE_JPEG_QUALITY = {
    'fast': 75, 'balanced': 85, 'better': 92, 'best': 97, 'ultra': 97,
}

LogFn = Optional[Callable[[str], None]]

# ── GPU detection ────────────────────────────────────────────────────────────

_GPU_ID: Optional[int] = None
_FFMPEG_ENCODER: Optional[str] = None


def _get_gpu_id() -> int:
    """Return 0 if CUDA GPU is available, -1 for CPU-only."""
    global _GPU_ID
    if _GPU_ID is not None:
        return _GPU_ID
    try:
        import torch
        _GPU_ID = 0 if torch.cuda.is_available() else -1
    except ImportError:
        _GPU_ID = -1
    return _GPU_ID


def _get_ffmpeg_encoder(log_fn: LogFn = None) -> str:
    """Return h264_nvenc if NVIDIA GPU encoder is available, else libx264."""
    global _FFMPEG_ENCODER
    if _FFMPEG_ENCODER is not None:
        return _FFMPEG_ENCODER
    try:
        result = subprocess.run(
            ['ffmpeg', '-hide_banner', '-encoders'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=5,
        )
        if 'h264_nvenc' in result.stdout:
            _FFMPEG_ENCODER = 'h264_nvenc'
            if log_fn:
                log_fn('GPU encoder terdeteksi: h264_nvenc (NVIDIA NVENC)')
            return _FFMPEG_ENCODER
    except Exception:
        pass
    _FFMPEG_ENCODER = 'libx264'
    return _FFMPEG_ENCODER


# ── Sharpness ────────────────────────────────────────────────────────────────

def _apply_sharpness_cv(img_bgr: np.ndarray, strength: float) -> np.ndarray:
    """Apply unsharp mask to a BGR image. strength: 0.0 = none, 1.0 = strong."""
    if strength <= 0:
        return img_bgr
    blurred = cv2.GaussianBlur(img_bgr, (0, 0), 3)
    return cv2.addWeighted(img_bgr, 1.0 + strength, blurred, -strength, 0)


# ── ESRGAN ───────────────────────────────────────────────────────────────────

def _patch_torchvision() -> None:
    """Compatibility shim for torchvision >= 0.16 (removed functional_tensor)."""
    import sys, types
    if 'torchvision.transforms.functional_tensor' in sys.modules:
        return
    try:
        import torchvision.transforms.functional as F
        ft = types.ModuleType('torchvision.transforms.functional_tensor')
        for name in dir(F):
            try:
                setattr(ft, name, getattr(F, name))
            except Exception:
                pass
        sys.modules['torchvision.transforms.functional_tensor'] = ft
    except ImportError:
        pass


def _esrgan_available() -> bool:
    """Return True if realesrgan can be imported (with torchvision compat patch)."""
    try:
        _patch_torchvision()
        import realesrgan  # noqa: F401
        import basicsr     # noqa: F401
        return True
    except Exception:
        return False


def _create_esrgan_upsampler(model_name: str, gpu_id: int = -1):
    """Build and return a RealESRGANer instance (model loaded once)."""
    _patch_torchvision()
    from basicsr.archs.rrdbnet_arch import RRDBNet
    from realesrgan import RealESRGANer

    if model_name == 'realesrgan-x4plus':
        model = RRDBNet(num_in_ch=3, num_out_ch=3, num_feat=64,
                        num_block=23, num_grow_ch=32, scale=4)
        model_url = ('https://github.com/xinntao/Real-ESRGAN/releases/download/'
                     'v0.1.0/RealESRGAN_x4plus.pth')
    elif model_name == 'realesrgan-x4plus-anime':
        model = RRDBNet(num_in_ch=3, num_out_ch=3, num_feat=64,
                        num_block=6, num_grow_ch=32, scale=4)
        model_url = ('https://github.com/xinntao/Real-ESRGAN/releases/download/'
                     'v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth')
    elif model_name == 'realesr-animevideov3':
        from realesrgan.archs.srvgg_arch import SRVGGNetCompact
        model = SRVGGNetCompact(num_in_ch=3, num_out_ch=3, num_feat=64,
                                num_conv=16, upscale=4, act_type='prelu')
        model_url = ('https://github.com/xinntao/Real-ESRGAN/releases/download/'
                     'v0.2.5.0/realesr-animevideov3.pth')
    else:
        raise RuntimeError(f'Unknown ESRGAN model: {model_name}')

    use_half = gpu_id >= 0  # fp16 only on GPU (saves VRAM, faster)
    return RealESRGANer(
        scale=4,
        model_path=model_url,
        model=model,
        tile=512, tile_pad=10, pre_pad=0,
        half=use_half,
        gpu_id=gpu_id if gpu_id >= 0 else None,
    )


def _esrgan_upscale_image(img_bgr: np.ndarray, model_name: str, target_scale: int,
                           upsampler=None, sharpness: float = 0.0) -> np.ndarray:
    """Upscale a BGR image with Real-ESRGAN then optionally sharpen."""
    if not _esrgan_available():
        raise RuntimeError('realesrgan tidak terinstal. Jalankan: pip install realesrgan basicsr')

    if upsampler is None:
        upsampler = _create_esrgan_upsampler(model_name, _get_gpu_id())

    output, _ = upsampler.enhance(img_bgr, outscale=4)

    if target_scale != 4:
        h0, w0 = img_bgr.shape[:2]
        new_w = max(1, int(w0 * target_scale))
        new_h = max(1, int(h0 * target_scale))
        output = cv2.resize(output, (new_w, new_h), interpolation=cv2.INTER_LANCZOS4)

    return _apply_sharpness_cv(output, sharpness)


def _esrgan_process_frames_dir(frames_dir: str, model_name: str, target_scale: int,
                                sharpness: float = 0.0,
                                log_fn: LogFn = None) -> None:
    """Apply ESRGAN upscaling (+ optional sharpness) to every PNG frame.
    Model is loaded once and reused. Automatically uses GPU (CUDA) if available.
    """
    fnames = sorted(f for f in os.listdir(frames_dir) if f.endswith('.png'))
    total = len(fnames)
    if total == 0:
        return

    gpu_id = _get_gpu_id()
    device_info = f'GPU (CUDA:{gpu_id})' if gpu_id >= 0 else 'CPU'
    if log_fn:
        sharp_info = f', sharpness={sharpness:.2f}' if sharpness > 0 else ''
        log_fn(f'ESRGAN: memuat model {model_name} di {device_info}{sharp_info}…')

    upsampler = _create_esrgan_upsampler(model_name, gpu_id)

    for i, fname in enumerate(fnames):
        fpath = os.path.join(frames_dir, fname)
        img = cv2.imread(fpath, cv2.IMREAD_COLOR)
        if img is None:
            continue
        upscaled = _esrgan_upscale_image(img, model_name, target_scale, upsampler, sharpness)
        cv2.imwrite(fpath, upscaled)
        if log_fn and (i % 10 == 0 or i == total - 1):
            log_fn(f'ESRGAN: frame {i + 1}/{total}')


# ── Frame extraction ──────────────────────────────────────────────────────────

def remove_watermark_roi_to_frames(
    input_video_path: str,
    output_frames_dir: str,
    roi: Tuple[int, int, int, int],
    inpaint_method: str = 'telea',
    log_fn: LogFn = None,
) -> float:
    """Remove watermark and save lossless PNG frames. Returns source FPS."""
    os.makedirs(output_frames_dir, exist_ok=True)

    cap = cv2.VideoCapture(input_video_path)
    if not cap.isOpened():
        raise RuntimeError('Failed to open input video')

    width   = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height  = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps     = cap.get(cv2.CAP_PROP_FPS) or 25.0
    total   = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) or 0

    if log_fn:
        log_fn(f'Membuka video {width}×{height} @ {fps:.1f}fps ({total} frame)…')

    x, y, w, h = roi
    x = max(0, min(x, width  - 1))
    y = max(0, min(y, height - 1))
    w = max(1, min(w, width  - x))
    h = max(1, min(h, height - y))

    flags = cv2.INPAINT_TELEA if inpaint_method.lower() == 'telea' else cv2.INPAINT_NS
    method_name = 'Telea' if inpaint_method.lower() == 'telea' else 'Navier-Stokes'
    if log_fn:
        log_fn(f'Inpaint watermark ({method_name}) pada ROI {w}×{h}…')

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
        if log_fn and total > 0 and (idx % 30 == 0 or idx == total):
            pct = int(idx / total * 100)
            log_fn(f'Inpaint: frame {idx}/{total} ({pct}%)')

    cap.release()
    if log_fn:
        log_fn(f'Inpaint selesai — {idx} frame diproses.')
    return float(fps)


def extract_frames_to_dir(input_video_path: str, output_frames_dir: str,
                           log_fn: LogFn = None) -> float:
    """Extract all video frames as PNG without modification. Returns source FPS."""
    os.makedirs(output_frames_dir, exist_ok=True)
    cap = cv2.VideoCapture(input_video_path)
    if not cap.isOpened():
        raise RuntimeError('Failed to open input video')
    fps   = cap.get(cv2.CAP_PROP_FPS) or 25.0
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) or 0
    if log_fn:
        log_fn(f'Ekstrak frame dari video ({total} frame)…')
    idx = 0
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        fname = os.path.join(output_frames_dir, f'frame_{idx:06d}.png')
        cv2.imwrite(fname, frame)
        idx += 1
        if log_fn and total > 0 and (idx % 60 == 0 or idx == total):
            pct = int(idx / total * 100)
            log_fn(f'Ekstrak frame: {idx}/{total} ({pct}%)')
    cap.release()
    if log_fn:
        log_fn(f'Ekstrak selesai — {idx} frame.')
    return float(fps)


# ── FPS Interpolation ─────────────────────────────────────────────────────────

def interpolate_frames_dir(
    frames_dir: str,
    output_dir: str,
    fps: float,
    target_fps: float = 60.0,
    log_fn: LogFn = None,
) -> float:
    """Interpolate PNG frames to target_fps using FFmpeg minterpolate.
    Must be called BEFORE upscaling so interpolation runs on original-resolution frames.
    Returns the new fps (target_fps).
    """
    os.makedirs(output_dir, exist_ok=True)
    if log_fn:
        log_fn(f'Interpolasi frame {fps:.2f}fps → {target_fps:.0f}fps (bidir MCI)…')

    pattern_in  = os.path.join(frames_dir, 'frame_%06d.png')
    pattern_out = os.path.join(output_dir,  'frame_%06d.png')

    vf = (
        f'minterpolate=fps={target_fps}:mi_mode=mci:'
        f'mc_mode=aobmc:me_mode=bidir:vsbmc=1'
    )
    cmd = [
        'ffmpeg', '-y',
        '-framerate', str(fps),
        '-i', pattern_in,
        '-vf', vf,
        '-r', str(target_fps),
        pattern_out,
    ]
    _run(cmd)

    if log_fn:
        n = len([f for f in os.listdir(output_dir) if f.endswith('.png')])
        log_fn(f'Interpolasi selesai → {n} frame @ {target_fps:.0f}fps.')
    return target_fps


# ── Image processing ──────────────────────────────────────────────────────────

def process_image_file(
    input_path: str,
    output_path: str,
    roi,
    inpaint_method: str = 'telea',
    upscale: bool = False,
    upscale_model: str = 'lanczos',
    upscale_scale: int = 2,
    quality: str = 'ultra',
    sharpness: float = 0.0,
    log_fn: LogFn = None,
) -> None:
    """Inpaint and/or upscale a single image."""
    if log_fn:
        log_fn('Membaca gambar…')
    img = cv2.imread(input_path, cv2.IMREAD_COLOR)
    if img is None:
        raise RuntimeError(f'Cannot read image: {input_path}')
    h0, w0 = img.shape[:2]
    if log_fn:
        log_fn(f'Gambar {w0}×{h0} dimuat.')

    if roi and int(roi.get('width', 0)) > 0 and int(roi.get('height', 0)) > 0:
        h_img, w_img = img.shape[:2]
        x  = max(0, min(int(roi['x']), w_img - 1))
        y  = max(0, min(int(roi['y']), h_img - 1))
        rw = max(1, min(int(roi['width']),  w_img - x))
        rh = max(1, min(int(roi['height']), h_img - y))
        mask  = np.zeros((h_img, w_img), dtype=np.uint8)
        mask[y:y+rh, x:x+rw] = 255
        flags = cv2.INPAINT_TELEA if inpaint_method.lower() == 'telea' else cv2.INPAINT_NS
        if log_fn:
            log_fn(f'Inpaint area watermark {rw}×{rh}…')
        img = cv2.inpaint(img, mask, 3, flags)
        if log_fn:
            log_fn('Inpaint selesai.')

    if upscale and upscale_scale > 0:
        if upscale_model == 'lanczos':
            if upscale_scale > 1:
                if log_fn:
                    log_fn(f'Upscale Lanczos {upscale_scale}×…')
                h1, w1 = img.shape[:2]
                img = cv2.resize(img, (w1 * upscale_scale, h1 * upscale_scale),
                                 interpolation=cv2.INTER_LANCZOS4)
                if log_fn:
                    log_fn(f'Upscale selesai → {w1 * upscale_scale}×{h1 * upscale_scale}.')
            if sharpness > 0:
                img = _apply_sharpness_cv(img, sharpness)
                if log_fn:
                    log_fn(f'Sharpness diterapkan ({sharpness:.2f}).')
        else:
            if log_fn:
                gpu_id = _get_gpu_id()
                device = f'GPU (CUDA:{gpu_id})' if gpu_id >= 0 else 'CPU'
                log_fn(f'ESRGAN upscale ({upscale_model}) {upscale_scale}× di {device}…')
            img = _esrgan_upscale_image(img, upscale_model, upscale_scale,
                                        sharpness=sharpness)
            h1, w1 = img.shape[:2]
            if log_fn:
                log_fn(f'ESRGAN selesai → {w1}×{h1}.')

    if log_fn:
        log_fn(f'Menyimpan hasil ({quality})…')
    if quality == 'ultra':
        cv2.imwrite(output_path, img, [cv2.IMWRITE_PNG_COMPRESSION, 1])
    else:
        q = IMAGE_JPEG_QUALITY.get(quality, 85)
        cv2.imwrite(output_path, img, [cv2.IMWRITE_JPEG_QUALITY, q])
    if log_fn:
        log_fn('Gambar tersimpan.')


# ── FFmpeg helpers ────────────────────────────────────────────────────────────

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


def _build_vf(lanczos_scale: Optional[int], fps_boost: bool,
              sharpness: float = 0.0) -> Optional[str]:
    """Build FFmpeg video filter string.

    FPS interpolation uses minterpolate with bidirectional ME (me_mode=bidir).
    Sharpness uses unsharp mask filter (luma only).
    """
    parts = []
    if lanczos_scale and lanczos_scale > 1:
        parts.append(f'scale=iw*{lanczos_scale}:ih*{lanczos_scale}:flags=lanczos')
    if fps_boost:
        parts.append(
            'minterpolate=fps=60:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1'
        )
    if sharpness > 0:
        # unsharp: lx:ly:la:cx:cy:ca — la = luma amount (0.0–1.5 typical)
        amt = round(sharpness * 1.5, 3)
        parts.append(f'unsharp=5:5:{amt}:5:5:{amt}')
    return ','.join(parts) if parts else None


def encode_from_frames(
    frames_dir: str,
    fps: float,
    source_audio: str,
    output_path: str,
    quality: str = 'ultra',
    lanczos_scale: Optional[int] = None,
    fps_boost: bool = False,
    sharpness: float = 0.0,
    log_fn: LogFn = None,
) -> None:
    """Encode PNG frames to final video.

    fps_boost=False when interpolation was already done at frame level.
    sharpness is applied via FFmpeg unsharp filter (for Lanczos path);
    for ESRGAN path sharpness is applied per-frame by _esrgan_process_frames_dir.
    """
    encoder = _get_ffmpeg_encoder(log_fn)
    is_nvenc = encoder == 'h264_nvenc'

    if log_fn:
        extra = []
        if lanczos_scale and lanczos_scale > 1:
            extra.append(f'Lanczos {lanczos_scale}×')
        if fps_boost:
            extra.append('boost 60fps (bidir MCI)')
        if sharpness > 0:
            extra.append(f'sharpness {sharpness:.2f}')
        device = 'NVENC' if is_nvenc else 'CPU'
        log_fn(f'Mengenkode video [{quality}] via {device}{" + " + ", ".join(extra) if extra else ""}…')

    q_args  = (QUALITY_PRESETS_NVENC if is_nvenc else QUALITY_PRESETS).get(
        quality, QUALITY_PRESETS_NVENC['ultra'] if is_nvenc else QUALITY_PRESETS['ultra']
    )
    vf      = _build_vf(lanczos_scale, fps_boost, sharpness)
    pattern = os.path.join(frames_dir, 'frame_%06d.png')

    cmd = [
        'ffmpeg', '-y',
        '-framerate', str(fps), '-i', pattern,
        '-i', source_audio,
        '-map', '0:v:0', '-map', '1:a:0?',
        '-c:v', encoder, *q_args,
        '-pix_fmt', 'yuv420p',
        '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709',
        '-movflags', '+faststart',
        '-c:a', 'aac', '-b:a', '192k',
    ]
    if vf:
        cmd += ['-filter:v', vf]
    cmd.append(output_path)
    _run(cmd)
    if log_fn:
        log_fn('Enkode selesai.')


def process_video_direct(
    input_path: str,
    output_path: str,
    quality: str = 'ultra',
    lanczos_scale: Optional[int] = None,
    fps_boost: bool = False,
    sharpness: float = 0.0,
    log_fn: LogFn = None,
) -> None:
    """Re-encode video via FFmpeg only (no watermark removal, no ESRGAN)."""
    encoder = _get_ffmpeg_encoder(log_fn)
    is_nvenc = encoder == 'h264_nvenc'

    if log_fn:
        extra = []
        if lanczos_scale and lanczos_scale > 1:
            extra.append(f'Lanczos {lanczos_scale}×')
        if fps_boost:
            extra.append('boost 60fps (bidir MCI)')
        if sharpness > 0:
            extra.append(f'sharpness {sharpness:.2f}')
        device = 'NVENC' if is_nvenc else 'CPU'
        log_fn(f'Mengenkode video langsung [{quality}] via {device}{" + " + ", ".join(extra) if extra else ""}…')

    q_args = (QUALITY_PRESETS_NVENC if is_nvenc else QUALITY_PRESETS).get(
        quality, QUALITY_PRESETS_NVENC['ultra'] if is_nvenc else QUALITY_PRESETS['ultra']
    )
    vf     = _build_vf(lanczos_scale, fps_boost, sharpness)

    cmd = [
        'ffmpeg', '-y',
        '-i', input_path,
        '-c:v', encoder, *q_args,
        '-pix_fmt', 'yuv420p',
        '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709',
        '-movflags', '+faststart',
        '-c:a', 'aac', '-b:a', '192k',
    ]
    if vf:
        cmd += ['-filter:v', vf]
    cmd.append(output_path)
    _run(cmd)
    if log_fn:
        log_fn('Enkode selesai.')


def _run(cmd: list) -> None:
    proc = subprocess.run(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        env=os.environ.copy(), text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(f'FFmpeg error: {proc.stderr[:1200]}')
