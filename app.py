"""Flask entrypoint for Photo & Video Forge.

Thin route layer: delegates all heavy lifting to utils.pipeline / utils.* modules."""

from __future__ import annotations

import atexit
import os
import platform
import shutil
import subprocess as sp
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from typing import Optional

import cv2
from flask import Flask, jsonify, render_template, request, send_from_directory
from pydantic import ValidationError
from werkzeug.utils import secure_filename

from utils import (
    bg_ops,
    detection_ops,
    jobs,
    labels_store,
    lama_ops,
    logging_config,
    pipeline,
    rife_ops,
    schemas,
    upscale_ops,
    yolo_detect,
)

APP_ROOT = os.path.dirname(os.path.abspath(__file__))
UPLOAD_FOLDER = os.path.join(APP_ROOT, "uploads")
OUTPUT_FOLDER = os.path.join(APP_ROOT, "outputs")
TEMP_FOLDER = os.path.join(APP_ROOT, "temp")

ALLOWED_VIDEO_EXT = {".mp4", ".mov", ".m4v", ".webm", ".avi", ".mkv"}
ALLOWED_IMAGE_EXT = {".jpg", ".jpeg", ".png", ".webp", ".tiff", ".bmp"}
ALLOWED_EXTENSIONS = ALLOWED_VIDEO_EXT | ALLOWED_IMAGE_EXT

NAMEMAP_PATH = os.path.join(UPLOAD_FOLDER, ".namemap.json")
HEARTBEAT_TIMEOUT = 60  # idle seconds before shutdown — only when no active job

for _d in (UPLOAD_FOLDER, OUTPUT_FOLDER, TEMP_FOLDER):
    os.makedirs(_d, exist_ok=True)

logging_config.configure(APP_ROOT)
log = logging_config.get(__name__)

job_store = jobs.JobStore(ttl_seconds=3600, max_jobs=200)
name_map = jobs.NameMap(NAMEMAP_PATH)
LABELS_STORE = labels_store.LabelsStore()
bulk_executor = ThreadPoolExecutor(max_workers=max(1, (os.cpu_count() or 4) // 2))


# ── Startup hygiene ─────────────────────────────────────────────────────────


def _cleanup_orphan_temp() -> None:
    """Remove any temp/frm_* and temp/interp_* directories left from prior crashes."""
    if not os.path.isdir(TEMP_FOLDER):
        return
    for name in os.listdir(TEMP_FOLDER):
        if name.startswith(("frm_", "interp_", "tmp_")):
            path = os.path.join(TEMP_FOLDER, name)
            try:
                if os.path.isdir(path):
                    shutil.rmtree(path, ignore_errors=True)
                else:
                    os.remove(path)
            except OSError as e:
                log.warning("could not remove orphan %s: %s", path, e)


def _prune_namemap() -> None:
    try:
        existing = set(os.listdir(UPLOAD_FOLDER))
    except OSError:
        existing = set()
    name_map.prune_missing(existing)


_cleanup_orphan_temp()
_prune_namemap()


def _cleanup_uploads() -> None:
    """Remove all upload files at exit (preserves namemap file)."""
    if not os.path.isdir(UPLOAD_FOLDER):
        return
    for fn in os.listdir(UPLOAD_FOLDER):
        if fn.startswith("."):
            continue
        fp = os.path.join(UPLOAD_FOLDER, fn)
        try:
            if os.path.isfile(fp):
                os.remove(fp)
        except OSError as e:
            log.debug("cleanup_uploads skip %s: %s", fp, e)


atexit.register(_cleanup_uploads)


# ── Heartbeat watchdog ──────────────────────────────────────────────────────


_last_heartbeat: Optional[float] = None
_shutdown_event = threading.Event()


def _watchdog() -> None:
    while _last_heartbeat is None and not _shutdown_event.is_set():
        time.sleep(1)
    while not _shutdown_event.is_set():
        time.sleep(5)
        if _last_heartbeat is None:
            continue
        if time.time() - _last_heartbeat > HEARTBEAT_TIMEOUT:
            if job_store.has_active():
                log.info("heartbeat timeout but job still running — keeping alive")
                continue
            log.info("heartbeat timeout, no active jobs — shutting down")
            _shutdown_event.set()
            _cleanup_uploads()
            os._exit(0)


threading.Thread(target=_watchdog, daemon=True).start()


# ── Flask app ───────────────────────────────────────────────────────────────


app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 2 * 1024 * 1024 * 1024  # 2 GB


# ── Helpers ─────────────────────────────────────────────────────────────────


def _allowed(fn: str) -> bool:
    return os.path.splitext(fn.lower())[1] in ALLOWED_EXTENSIONS


def _is_image(fn: str) -> bool:
    return os.path.splitext(fn.lower())[1] in ALLOWED_IMAGE_EXT


def _safe_input_path(filename: str) -> Optional[str]:
    """Resolve an upload filename to its absolute path inside UPLOAD_FOLDER."""
    if "/" in filename or "\\" in filename or ".." in filename:
        return None
    candidate = os.path.realpath(os.path.join(UPLOAD_FOLDER, filename))
    upload_real = os.path.realpath(UPLOAD_FOLDER)
    try:
        if os.path.commonpath([candidate, upload_real]) != upload_real:
            return None
    except ValueError:
        return None
    if not os.path.isfile(candidate):
        return None
    return candidate


def _make_suffix(opts: schemas.ProcessOptions) -> str:
    p: list[str] = []
    if opts.has_roi:
        p.append("nowm")
    if opts.remove_bg:
        p.append("nobg")
    if opts.upscale:
        model_short = {
            "lanczos": "lanczos",
            "realesrgan-x4plus": "esrgan-real",
            "realesrgan-x4plus-anime": "esrgan-anime",
            "realesr-animevideov3": "esrgan-video",
        }.get(opts.upscale_model, "upscale")
        p.append(f"{model_short}-{opts.upscale_scale}x")
        if opts.sharpness > 0:
            p.append(f"sharp{int(opts.sharpness * 100)}")
    if opts.fps_boost:
        p.append("60fps")
    return ("_" + "_".join(p)) if p else "_processed"


def _validate_dependencies(opts: schemas.ProcessOptions) -> Optional[str]:
    use_esrgan = opts.upscale and opts.upscale_model not in ("lanczos", "", None)
    if use_esrgan and not upscale_ops.is_available():
        return "realesrgan tidak terinstal. Jalankan: pip install realesrgan basicsr"
    if opts.remove_bg and not bg_ops.is_available():
        return "rembg tidak terinstal. Jalankan: pip install rembg"
    return None


def _parse(model_cls, payload: dict):
    try:
        return model_cls.model_validate(payload)
    except ValidationError as e:
        return e


def _err(msg: str, status: int = 400):
    return jsonify({"error": msg}), status


# ── Routes ──────────────────────────────────────────────────────────────────


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/video/<path:filename>")
def serve_video(filename):
    if "/" in filename or "\\" in filename or ".." in filename:
        return _err("invalid filename", 400)
    return send_from_directory(UPLOAD_FOLDER, filename, as_attachment=False)


@app.route("/upload", methods=["POST"])
def upload():
    if "video" not in request.files:
        return _err("No file part")
    f = request.files["video"]
    if not f.filename or not _allowed(f.filename):
        return _err("Format tidak didukung")
    orig = secure_filename(f.filename)
    base, ext = os.path.splitext(orig)
    if not base:
        return _err("Invalid filename")
    stored = f"{base}_{uuid.uuid4().hex}{ext}"
    path = os.path.join(UPLOAD_FOLDER, stored)
    f.save(path)

    try:
        if _is_image(stored):
            valid = cv2.imread(path, cv2.IMREAD_COLOR) is not None
        else:
            cap = cv2.VideoCapture(path)
            valid = cap.isOpened() and cap.read()[0]
            cap.release()
    except Exception as e:
        log.warning("upload validation error: %s", e)
        valid = False
    if not valid:
        try:
            os.remove(path)
        except OSError:
            pass
        return _err("File rusak atau format tidak didukung")

    name_map.set(stored, base)
    return jsonify({
        "filename": stored,
        "originalBase": base,
        "isImage": _is_image(stored),
    })


@app.route("/process", methods=["POST"])
def process_video_route():
    parsed = _parse(schemas.ProcessVideoRequest, request.get_json(force=True) or {})
    if isinstance(parsed, ValidationError):
        return _err(parsed.errors()[0]["msg"])
    req: schemas.ProcessVideoRequest = parsed

    if not req.has_any_op:
        return _err("Pilih minimal satu operasi")

    in_path = _safe_input_path(req.filename)
    if not in_path:
        return _err("File tidak ditemukan", 404)

    err = _validate_dependencies(req)
    if err:
        return _err(err)

    orig_base = name_map.get(req.filename, os.path.splitext(req.filename)[0]) or "output"
    out_name = f"{orig_base}{_make_suffix(req)}.mp4"
    out_path = os.path.join(OUTPUT_FOLDER, out_name)

    job_store.start(req.job_id)
    log_fn = (lambda msg: job_store.log(req.job_id, msg)) if req.job_id else None

    try:
        if log_fn:
            log_fn("Mulai memproses video…")
        t0 = time.time()
        pipeline.process_video(
            in_path, out_path,
            roi=req.roi, method=req.method, quality=req.quality,
            upscale=req.upscale, upscale_model=req.upscale_model,
            upscale_scale=req.upscale_scale, fps_boost=req.fps_boost,
            interp_engine=req.interp_engine,
            sharpness=req.sharpness, remove_bg=req.remove_bg,
            rembg_model=req.rembg_model, codec=req.codec,
            temp_root=TEMP_FOLDER, log_fn=log_fn,
        )
        elapsed = time.time() - t0
        if log_fn:
            log_fn(f"Selesai! Total waktu: {elapsed:.1f} detik.")
    except Exception as e:
        log.exception("video processing failed")
        job_store.done(req.job_id)
        return _err(str(e), 500)

    job_store.done(req.job_id)
    return jsonify({
        "outputFilename": out_name,
        "outputDir": OUTPUT_FOLDER,
        "outputPath": out_path,
    })


@app.route("/process-image", methods=["POST"])
def process_image_route():
    parsed = _parse(schemas.ProcessImageRequest, request.get_json(force=True) or {})
    if isinstance(parsed, ValidationError):
        return _err(parsed.errors()[0]["msg"])
    req: schemas.ProcessImageRequest = parsed

    if not (req.has_roi or req.upscale or req.remove_bg):
        return _err("Pilih minimal satu operasi")

    in_path = _safe_input_path(req.filename)
    if not in_path:
        return _err("File tidak ditemukan", 404)

    err = _validate_dependencies(req)
    if err:
        return _err(err)

    orig_base = name_map.get(req.filename, os.path.splitext(req.filename)[0]) or "output"
    out_ext = ".png" if (req.remove_bg or req.quality == "ultra") else ".jpg"
    out_name = f"{orig_base}{_make_suffix(req)}{out_ext}"
    out_path = os.path.join(OUTPUT_FOLDER, out_name)

    job_store.start(req.job_id)
    log_fn = (lambda msg: job_store.log(req.job_id, msg)) if req.job_id else None

    try:
        if log_fn:
            log_fn("Mulai memproses foto…")
        t0 = time.time()
        pipeline.process_image(
            in_path, out_path,
            roi=req.roi, method=req.method,
            upscale=req.upscale, upscale_model=req.upscale_model,
            upscale_scale=req.upscale_scale, quality=req.quality,
            sharpness=req.sharpness, remove_bg=req.remove_bg,
            rembg_model=req.rembg_model, log_fn=log_fn,
        )
        elapsed = time.time() - t0
        if log_fn:
            log_fn(f"Selesai! Total waktu: {elapsed:.1f} detik.")
    except Exception as e:
        log.exception("image processing failed")
        job_store.done(req.job_id)
        return _err(str(e), 500)

    job_store.done(req.job_id)
    return jsonify({
        "outputFilename": out_name,
        "outputDir": OUTPUT_FOLDER,
        "outputPath": out_path,
    })


@app.route("/process-bulk", methods=["POST"])
def process_bulk_route():
    parsed = _parse(schemas.BulkRequest, request.get_json(force=True) or {})
    if isinstance(parsed, ValidationError):
        return _err(parsed.errors()[0]["msg"])
    req: schemas.BulkRequest = parsed

    if not req.files:
        return _err("Tidak ada file")
    if not req.has_any_op:
        return _err("Pilih minimal satu operasi")

    err = _validate_dependencies(req)
    if err:
        return _err(err)

    job_store.start(req.job_id)
    log_fn = (lambda msg: job_store.log(req.job_id, msg)) if req.job_id else None

    suffix = _make_suffix(req)
    total = len(req.files)
    t0_bulk = time.time()
    results: list[dict] = []

    for idx, item in enumerate(req.files, 1):
        stored = item.filename
        orig_base = (
            item.originalBase
            or name_map.get(stored)
            or os.path.splitext(stored)[0]
            or "output"
        )
        is_img = item.isImage if item.isImage is not None else _is_image(stored)
        in_path = _safe_input_path(stored)
        if not in_path:
            results.append({
                "file": orig_base, "status": "error",
                "error": "File tidak ditemukan",
            })
            continue

        if is_img:
            out_ext = ".png" if (req.remove_bg or req.quality == "ultra") else ".jpg"
            out_name = f"{orig_base}{suffix}{out_ext}"
        else:
            out_name = f"{orig_base}{suffix}.mp4"
        out_path = os.path.join(OUTPUT_FOLDER, out_name)

        if log_fn:
            log_fn(f"[{idx}/{total}] Memproses {orig_base}…")
        t0 = time.time()
        try:
            if is_img:
                pipeline.process_image(
                    in_path, out_path,
                    roi=req.roi, method=req.method,
                    upscale=req.upscale, upscale_model=req.upscale_model,
                    upscale_scale=req.upscale_scale, quality=req.quality,
                    sharpness=req.sharpness, remove_bg=req.remove_bg,
                    rembg_model=req.rembg_model, log_fn=log_fn,
                )
            else:
                pipeline.process_video(
                    in_path, out_path,
                    roi=req.roi, method=req.method, quality=req.quality,
                    upscale=req.upscale, upscale_model=req.upscale_model,
                    upscale_scale=req.upscale_scale, fps_boost=req.fps_boost,
                    sharpness=req.sharpness, remove_bg=req.remove_bg,
                    rembg_model=req.rembg_model, codec=req.codec,
                    temp_root=TEMP_FOLDER, log_fn=log_fn,
                )
            elapsed = time.time() - t0
            results.append({
                "file": orig_base, "status": "success",
                "output": out_name, "outputPath": out_path,
            })
            if log_fn:
                log_fn(f"[{idx}/{total}] {orig_base} — selesai ({elapsed:.1f}s)")
        except Exception as e:
            log.exception("bulk item failed: %s", orig_base)
            results.append({
                "file": orig_base, "status": "error",
                "error": str(e)[:300],
            })
            if log_fn:
                log_fn(f"[{idx}/{total}] {orig_base} — ERROR: {str(e)[:120]}")

    ok = sum(1 for r in results if r["status"] == "success")
    if log_fn:
        log_fn(
            f"Bulk selesai: {ok}/{total} berhasil. "
            f"Total waktu: {time.time() - t0_bulk:.1f} detik."
        )
    job_store.done(req.job_id)
    return jsonify({
        "outputDir": OUTPUT_FOLDER,
        "results": results,
        "summary": f"{ok}/{total} berhasil diproses",
    })


@app.route("/open-folder", methods=["POST"])
def open_folder():
    parsed = _parse(schemas.OpenFolderRequest, request.get_json(force=True) or {})
    if isinstance(parsed, ValidationError):
        return _err(parsed.errors()[0]["msg"])
    req: schemas.OpenFolderRequest = parsed

    real_path = os.path.realpath(req.path)
    real_output = os.path.realpath(OUTPUT_FOLDER)
    try:
        if os.path.commonpath([real_path, real_output]) != real_output:
            return _err("Akses ditolak", 403)
    except ValueError:
        return _err("Akses ditolak", 403)
    if not os.path.isdir(real_path):
        return _err("Folder tidak ditemukan", 404)

    try:
        sys_name = platform.system()
        if sys_name == "Darwin":
            sp.Popen(["open", real_path])
        elif sys_name == "Windows":
            sp.Popen(["explorer", real_path])
        else:
            sp.Popen(["xdg-open", real_path])
        return jsonify({"ok": True})
    except Exception as e:
        log.exception("open-folder failed")
        return _err(str(e), 500)


@app.route("/process-log/<job_id>")
def process_log_route(job_id):
    info = job_store.get(job_id)
    if info is None:
        return jsonify({"logs": [], "done": True})
    return jsonify(info)


@app.route("/heartbeat", methods=["POST"])
def heartbeat():
    global _last_heartbeat
    _last_heartbeat = time.time()
    return "", 204


@app.route("/esrgan-check")
def esrgan_check():
    return jsonify({"available": upscale_ops.is_available()})


@app.route("/rembg-check")
def rembg_check():
    return jsonify({"available": bg_ops.is_available()})


@app.route("/capabilities")
def capabilities():
    """Report availability of all optional capabilities for the UI."""
    stats = LABELS_STORE.stats()
    return jsonify({
        "esrgan": upscale_ops.is_available(),
        "rembg": bg_ops.is_available(),
        "lama": lama_ops.is_available(),
        "rife": rife_ops.is_available(),
        "yolo": yolo_detect.is_available(),
        "label_count": stats["total"],
        "label_unique_images": stats["unique_images"],
    })


@app.route("/label-stats")
def label_stats():
    return jsonify(LABELS_STORE.stats())


@app.route("/save-label", methods=["POST"])
def save_label():
    """Persist a (image, roi) sample for YOLO retraining."""
    parsed = _parse(schemas.SaveLabelRequest, request.get_json(force=True) or {})
    if isinstance(parsed, ValidationError):
        return _err(parsed.errors()[0]["msg"])
    req: schemas.SaveLabelRequest = parsed

    in_path = _safe_input_path(req.filename)
    if not in_path:
        return _err("File tidak ditemukan", 404)

    # Capture frame: image file → read directly; video → seek to requested frame
    if _is_image(req.filename):
        img = cv2.imread(in_path, cv2.IMREAD_COLOR)
        if img is None:
            return _err("Tidak dapat membaca gambar", 400)
    else:
        cap = cv2.VideoCapture(in_path)
        if not cap.isOpened():
            return _err("Tidak dapat membuka video", 400)
        try:
            total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) or 1
            target_idx = (
                req.frame_index
                if req.frame_index is not None and 0 <= req.frame_index < total
                else total // 2
            )
            cap.set(cv2.CAP_PROP_POS_FRAMES, target_idx)
            ret, img = cap.read()
            if not ret or img is None:
                return _err("Tidak dapat membaca frame", 400)
        finally:
            cap.release()

    digest = LABELS_STORE.add_sample(
        img,
        {"x": req.roi.x, "y": req.roi.y, "width": req.roi.width, "height": req.roi.height},
        source=req.source,
    )
    if digest is None:
        return _err("Sample ditolak (ROI invalid atau gagal simpan)", 400)

    return jsonify({"hash": digest, **LABELS_STORE.stats()})


@app.route("/encoder-info")
def encoder_info():
    """Report which video encoders are available + GPU state."""
    from utils.gpu import get_gpu_id, get_gpu_vram_gb, has_encoder
    return jsonify({
        "h264_nvenc": has_encoder("h264_nvenc"),
        "hevc_nvenc": has_encoder("hevc_nvenc"),
        "av1_nvenc": has_encoder("av1_nvenc"),
        "libx265": has_encoder("libx265"),
        "libsvtav1": has_encoder("libsvtav1"),
        "libaom_av1": has_encoder("libaom-av1"),
        "gpu": get_gpu_id() >= 0,
        "vram_gb": round(get_gpu_vram_gb(), 1),
    })


@app.route("/detect-watermark", methods=["POST"])
def detect_watermark_route():
    parsed = _parse(schemas.DetectRequest, request.get_json(force=True) or {})
    if isinstance(parsed, ValidationError):
        return _err(parsed.errors()[0]["msg"])
    req: schemas.DetectRequest = parsed

    in_path = _safe_input_path(req.filename)
    if not in_path:
        return _err("File tidak ditemukan", 404)

    try:
        if _is_image(req.filename):
            frame = cv2.imread(in_path, cv2.IMREAD_COLOR)
            if frame is None:
                return jsonify({"roi": None, "message": "Tidak dapat membaca gambar"})
            result = detection_ops.detect_watermark_roi(frame)
        else:
            frames = detection_ops.get_sample_frames(in_path, n=6)
            if not frames:
                return jsonify({"roi": None, "message": "Tidak dapat membaca frame video"})
            result = detection_ops.detect_watermark_roi(frames[0], extra_frames=frames[1:])
        if result is None:
            return jsonify({"roi": None, "message": "Watermark tidak terdeteksi — tandai manual"})
        x, y, w, h = result
        return jsonify({"roi": {"x": x, "y": y, "width": w, "height": h}})
    except Exception as e:
        log.exception("watermark detect failed")
        return _err(str(e), 500)


if __name__ == "__main__":
    import webbrowser

    log.info("Starting Photo & Video Forge on http://127.0.0.1:5000")
    threading.Timer(1.2, lambda: webbrowser.open("http://127.0.0.1:5000")).start()
    app.run(debug=False, use_reloader=False, host="127.0.0.1", port=5000)
