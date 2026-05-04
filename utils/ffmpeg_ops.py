"""FFmpeg encode/probe helpers and codec preset tables."""

from __future__ import annotations

import json
import os
import subprocess
from typing import Optional

from .gpu import has_encoder
from .logging_config import get

log = get(__name__)

LogFn = Optional[callable]

VIDEO_CODECS = ("h264", "hevc", "av1")

QUALITY_X264 = {
    "fast":     ["-preset", "veryfast", "-crf", "23"],
    "balanced": ["-preset", "medium",   "-crf", "20"],
    "better":   ["-preset", "slow",     "-crf", "18"],
    "best":     ["-preset", "veryslow", "-crf", "16"],
    "ultra":    ["-preset", "placebo",  "-crf", "0"],
}

QUALITY_X265 = {
    "fast":     ["-preset", "veryfast", "-crf", "26"],
    "balanced": ["-preset", "medium",   "-crf", "23"],
    "better":   ["-preset", "slow",     "-crf", "21"],
    "best":     ["-preset", "veryslow", "-crf", "19"],
    "ultra":    ["-preset", "veryslow", "-crf", "12"],
}

QUALITY_AV1_CPU = {
    "fast":     ["-cpu-used", "8", "-crf", "32"],
    "balanced": ["-cpu-used", "5", "-crf", "28"],
    "better":   ["-cpu-used", "4", "-crf", "24"],
    "best":     ["-cpu-used", "2", "-crf", "22"],
    "ultra":    ["-cpu-used", "1", "-crf", "18"],
}

QUALITY_H264_NVENC = {
    "fast":     ["-preset", "fast",   "-rc:v", "vbr", "-cq", "23", "-b:v", "0"],
    "balanced": ["-preset", "medium", "-rc:v", "vbr", "-cq", "20", "-b:v", "0"],
    "better":   ["-preset", "slow",   "-rc:v", "vbr", "-cq", "18", "-b:v", "0"],
    "best":     ["-preset", "slow",   "-rc:v", "vbr", "-cq", "16", "-b:v", "0"],
    "ultra":    ["-preset", "slow",   "-rc:v", "vbr", "-cq", "1",  "-b:v", "0"],
}

QUALITY_HEVC_NVENC = {
    "fast":     ["-preset", "fast",   "-rc:v", "vbr", "-cq", "26", "-b:v", "0"],
    "balanced": ["-preset", "medium", "-rc:v", "vbr", "-cq", "23", "-b:v", "0"],
    "better":   ["-preset", "slow",   "-rc:v", "vbr", "-cq", "21", "-b:v", "0"],
    "best":     ["-preset", "slow",   "-rc:v", "vbr", "-cq", "19", "-b:v", "0"],
    "ultra":    ["-preset", "slow",   "-rc:v", "vbr", "-cq", "12", "-b:v", "0"],
}

QUALITY_AV1_NVENC = {
    "fast":     ["-preset", "p3", "-rc:v", "vbr", "-cq", "32", "-b:v", "0"],
    "balanced": ["-preset", "p4", "-rc:v", "vbr", "-cq", "28", "-b:v", "0"],
    "better":   ["-preset", "p5", "-rc:v", "vbr", "-cq", "24", "-b:v", "0"],
    "best":     ["-preset", "p6", "-rc:v", "vbr", "-cq", "22", "-b:v", "0"],
    "ultra":    ["-preset", "p7", "-rc:v", "vbr", "-cq", "18", "-b:v", "0"],
}

IMAGE_JPEG_QUALITY = {
    "fast": 75, "balanced": 85, "better": 92, "best": 97, "ultra": 97,
}


def select_encoder(codec: str = "h264") -> tuple[str, dict, str]:
    """Pick best encoder for a codec. Returns (encoder, quality_table, pix_fmt)."""
    codec = (codec or "h264").lower()
    if codec == "hevc":
        if has_encoder("hevc_nvenc"):
            return "hevc_nvenc", QUALITY_HEVC_NVENC, "yuv420p"
        if has_encoder("libx265"):
            return "libx265", QUALITY_X265, "yuv420p"
    if codec == "av1":
        if has_encoder("av1_nvenc"):
            return "av1_nvenc", QUALITY_AV1_NVENC, "yuv420p"
        if has_encoder("libsvtav1"):
            return "libsvtav1", QUALITY_AV1_CPU, "yuv420p"
        if has_encoder("libaom-av1"):
            return "libaom-av1", QUALITY_AV1_CPU, "yuv420p"
    if has_encoder("h264_nvenc"):
        return "h264_nvenc", QUALITY_H264_NVENC, "yuv420p"
    return "libx264", QUALITY_X264, "yuv420p"


def build_vf(
    lanczos_scale: Optional[int],
    fps_boost: bool,
    sharpness: float = 0.0,
) -> Optional[str]:
    """Compose ffmpeg -vf chain. MCI/bidir interpolation for smoothness."""
    parts: list[str] = []
    if lanczos_scale and lanczos_scale > 1:
        parts.append(
            f"scale=iw*{lanczos_scale}:ih*{lanczos_scale}:flags=lanczos"
        )
    if fps_boost:
        parts.append(
            "minterpolate=fps=60:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1"
        )
    if sharpness > 0:
        amt = round(sharpness * 1.5, 3)
        parts.append(f"unsharp=5:5:{amt}:5:5:{amt}")
    return ",".join(parts) if parts else None


def probe_video_info(path: str) -> dict:
    """Return {width, height, fps, has_audio, color_primaries, color_transfer, is_hdr}."""
    cmd = ["ffprobe", "-v", "error", "-show_streams", "-of", "json", path]
    defaults = {
        "width": 1920, "height": 1080, "fps": 25.0,
        "has_audio": False, "color_primaries": "bt709",
        "color_transfer": "bt709", "is_hdr": False,
    }
    try:
        proc = subprocess.run(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=15,
        )
        if proc.returncode != 0:
            return defaults
        streams = json.loads(proc.stdout).get("streams", [])
        v = next((s for s in streams if s.get("codec_type") == "video"), None)
        a = next((s for s in streams if s.get("codec_type") == "audio"), None)
        if not v:
            return defaults
        num, den = (v.get("r_frame_rate") or "25/1").split("/")
        fps = float(num) / max(float(den), 1.0)
        primaries = v.get("color_primaries") or "bt709"
        transfer = v.get("color_transfer") or "bt709"
        is_hdr = transfer in ("smpte2084", "arib-std-b67") or primaries == "bt2020"
        return {
            "width": int(v.get("width", 1920)),
            "height": int(v.get("height", 1080)),
            "fps": fps,
            "has_audio": a is not None,
            "color_primaries": primaries,
            "color_transfer": transfer,
            "is_hdr": is_hdr,
        }
    except Exception as e:
        log.warning("probe_video_info failed for %s: %s", path, e)
        return defaults


def _audio_args(source_audio_path: str) -> list[str]:
    """Copy audio if AAC, else re-encode to AAC 192k."""
    try:
        proc = subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", "a:0",
             "-show_entries", "stream=codec_name", "-of", "default=nw=1:nk=1",
             source_audio_path],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=10,
        )
        codec = (proc.stdout or "").strip().lower()
    except Exception:
        codec = ""
    if codec == "aac":
        return ["-c:a", "copy"]
    return ["-c:a", "aac", "-b:a", "192k"]


def _color_args(probe: dict) -> list[str]:
    if probe.get("is_hdr"):
        return [
            "-color_primaries", probe.get("color_primaries", "bt2020"),
            "-color_trc", probe.get("color_transfer", "smpte2084"),
            "-colorspace", "bt2020nc",
        ]
    return [
        "-color_primaries", "bt709",
        "-color_trc", "bt709",
        "-colorspace", "bt709",
    ]


def encode_from_frames(
    frames_dir: str,
    fps: float,
    source_audio: str,
    output_path: str,
    quality: str = "ultra",
    lanczos_scale: Optional[int] = None,
    fps_boost: bool = False,
    sharpness: float = 0.0,
    codec: str = "h264",
    log_fn: LogFn = None,
) -> None:
    """Encode PNG frames + source audio to final video."""
    encoder, qtable, pix_fmt = select_encoder(codec)
    q_args = qtable.get(quality, qtable["ultra"])
    vf = build_vf(lanczos_scale, fps_boost, sharpness)
    pattern = os.path.join(frames_dir, "frame_%06d.png")
    probe = probe_video_info(source_audio)

    if log_fn:
        extras = []
        if lanczos_scale and lanczos_scale > 1:
            extras.append(f"Lanczos {lanczos_scale}x")
        if fps_boost:
            extras.append("60fps MCI")
        if sharpness > 0:
            extras.append(f"sharp {sharpness:.2f}")
        log_fn(
            f"Enkode [{quality}] via {encoder}"
            + (" + " + ", ".join(extras) if extras else "")
            + "…"
        )

    audio_inputs = ["-i", source_audio] if probe.get("has_audio") else []
    audio_maps = ["-map", "1:a:0?"] if probe.get("has_audio") else []
    audio_codec = _audio_args(source_audio) if probe.get("has_audio") else ["-an"]

    cmd = [
        "ffmpeg", "-y",
        "-framerate", str(fps), "-i", pattern,
        *audio_inputs,
        "-map", "0:v:0", *audio_maps,
        "-c:v", encoder, *q_args,
        "-pix_fmt", pix_fmt,
        *_color_args(probe),
        "-movflags", "+faststart",
        *audio_codec,
    ]
    if vf:
        cmd += ["-filter:v", vf]
    cmd.append(output_path)
    run(cmd)
    if log_fn:
        log_fn("Enkode selesai.")


def process_video_direct(
    input_path: str,
    output_path: str,
    quality: str = "ultra",
    lanczos_scale: Optional[int] = None,
    fps_boost: bool = False,
    sharpness: float = 0.0,
    codec: str = "h264",
    log_fn: LogFn = None,
) -> None:
    """Re-encode video directly via FFmpeg (no per-frame extraction)."""
    encoder, qtable, pix_fmt = select_encoder(codec)
    q_args = qtable.get(quality, qtable["ultra"])
    vf = build_vf(lanczos_scale, fps_boost, sharpness)
    probe = probe_video_info(input_path)

    if log_fn:
        log_fn(f"Enkode langsung [{quality}] via {encoder}…")

    audio_codec = _audio_args(input_path) if probe.get("has_audio") else ["-an"]

    cmd = [
        "ffmpeg", "-y",
        "-i", input_path,
        "-c:v", encoder, *q_args,
        "-pix_fmt", pix_fmt,
        *_color_args(probe),
        "-movflags", "+faststart",
        *audio_codec,
    ]
    if vf:
        cmd += ["-filter:v", vf]
    cmd.append(output_path)
    run(cmd)
    if log_fn:
        log_fn("Enkode selesai.")


def run(cmd: list) -> None:
    """Run an ffmpeg/ffprobe command, raise with stderr tail on failure."""
    log.debug("ffmpeg cmd: %s", " ".join(cmd))
    proc = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=os.environ.copy(),
        text=True,
    )
    if proc.returncode != 0:
        tail = (proc.stderr or "")[-2000:]
        log.error("ffmpeg failed: %s", tail)
        raise RuntimeError(f"FFmpeg error: {tail}")
