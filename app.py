import atexit
import datetime
import os
import time
import platform
import shutil
import subprocess as sp
import threading
import uuid

from flask import Flask, render_template, request, jsonify, send_from_directory
from werkzeug.utils import secure_filename

from utils.video import (
    remove_watermark_roi_to_frames,
    extract_frames_to_dir,
    interpolate_frames_dir,
    encode_from_frames,
    process_video_direct,
    process_image_file,
    _esrgan_available,
    _esrgan_process_frames_dir,
)

APP_ROOT       = os.path.dirname(os.path.abspath(__file__))
UPLOAD_FOLDER  = os.path.join(APP_ROOT, 'uploads')
OUTPUT_FOLDER  = os.path.join(APP_ROOT, 'outputs')
TEMP_FOLDER    = os.path.join(APP_ROOT, 'temp')

ALLOWED_VIDEO_EXT = {'.mp4', '.mov', '.m4v', '.webm', '.avi', '.mkv'}
ALLOWED_IMAGE_EXT = {'.jpg', '.jpeg', '.png', '.webp', '.tiff', '.bmp'}
ALLOWED_EXTENSIONS = ALLOWED_VIDEO_EXT | ALLOWED_IMAGE_EXT

for _d in (UPLOAD_FOLDER, OUTPUT_FOLDER, TEMP_FOLDER):
    os.makedirs(_d, exist_ok=True)


def _cleanup_uploads() -> None:
    """Hapus semua file di uploads saat aplikasi ditutup."""
    for fn in os.listdir(UPLOAD_FOLDER):
        fp = os.path.join(UPLOAD_FOLDER, fn)
        try:
            if os.path.isfile(fp):
                os.remove(fp)
        except Exception:
            pass


atexit.register(_cleanup_uploads)

# ── Heartbeat watchdog ────────────────────────────────────────────────────────
# Browser sends POST /heartbeat every 5 s. If no heartbeat for 15 s after the
# first one arrives, the browser is gone → shut down the server cleanly.

_last_heartbeat: float | None = None   # None = browser not yet connected
_HEARTBEAT_TIMEOUT = 15                # seconds before shutdown


def _watchdog() -> None:
    while _last_heartbeat is None:     # wait for first browser connection
        time.sleep(1)
    while True:
        time.sleep(5)
        if time.time() - _last_heartbeat > _HEARTBEAT_TIMEOUT:
            _cleanup_uploads()
            os._exit(0)


threading.Thread(target=_watchdog, daemon=True).start()

app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 2 * 1024 * 1024 * 1024  # 2 GB

_name_map: dict[str, str] = {}

# job_id -> {logs: [...], done: bool}  — thread-safe process log
_jobs: dict = {}
_jobs_lock = threading.Lock()


def _job_start(job_id: str) -> None:
    with _jobs_lock:
        _jobs[job_id] = {'logs': [], 'done': False}


def _job_log(job_id: str, msg: str) -> None:
    ts = datetime.datetime.now().strftime('%H:%M:%S')
    with _jobs_lock:
        if job_id in _jobs:
            _jobs[job_id]['logs'].append(f'[{ts}] {msg}')


def _job_done(job_id: str) -> None:
    with _jobs_lock:
        if job_id in _jobs:
            _jobs[job_id]['done'] = True


# ── Helpers ───────────────────────────────────────────────────────────────────

def _allowed(fn: str) -> bool:
    return os.path.splitext(fn.lower())[1] in ALLOWED_EXTENSIONS


def _is_image(fn: str) -> bool:
    return os.path.splitext(fn.lower())[1] in ALLOWED_IMAGE_EXT


def _has_roi(roi) -> bool:
    return bool(roi) and int(roi.get('width', 0)) > 0 and int(roi.get('height', 0)) > 0


def _make_suffix(remove_wm: bool, upscale: bool, upscale_model: str,
                 upscale_scale: int, fps_boost: bool, sharpness: float = 0.0) -> str:
    p = []
    if remove_wm:
        p.append('nowm')
    if upscale:
        model_short = {
            'lanczos':                  'lanczos',
            'realesrgan-x4plus':        'esrgan-real',
            'realesrgan-x4plus-anime':  'esrgan-anime',
            'realesr-animevideov3':     'esrgan-video',
        }.get(upscale_model, 'upscale')
        p.append(f'{model_short}-{upscale_scale}x')
        if sharpness > 0:
            p.append(f'sharp{int(sharpness * 100)}')
    if fps_boost:
        p.append('60fps')
    return ('_' + '_'.join(p)) if p else '_processed'


def _do_process(input_path, output_path, roi, method, quality,
                upscale, upscale_model, upscale_scale, fps_boost,
                sharpness=0.0, log_fn=None):
    """Core video processing: watermark removal and/or upscale/fps boost.

    Workflow (frame-level pipeline):
      1. Extract frames  (+ optional watermark inpaint)
      2. Interpolate to 60fps  (fps_boost — BEFORE upscale, cheaper on original res)
      3. ESRGAN upscale  (on interpolated frames)
      4. Encode final video

    When no frame-level ops are needed (direct FFmpeg path):
      fps_boost/sharpness applied via FFmpeg filters in process_video_direct.
    """
    remove_wm   = _has_roi(roi)
    use_esrgan  = upscale and upscale_model not in ('lanczos', '', None)
    lanczos_scale = (
        upscale_scale
        if (upscale and not use_esrgan and upscale_scale and upscale_scale > 1)
        else None
    )

    need_frames = remove_wm or use_esrgan

    if need_frames:
        frames_dir = os.path.join(TEMP_FOLDER, f'frm_{uuid.uuid4().hex}')
        try:
            # Step 1: Extract frames (with optional watermark inpaint)
            if remove_wm:
                fps = remove_watermark_roi_to_frames(
                    input_path, frames_dir,
                    (int(roi['x']), int(roi['y']), int(roi['width']), int(roi['height'])),
                    method, log_fn=log_fn,
                )
            else:
                fps = extract_frames_to_dir(input_path, frames_dir, log_fn=log_fn)

            # Step 2: Interpolation FIRST — runs on original-resolution frames
            if fps_boost:
                interp_dir = os.path.join(TEMP_FOLDER, f'interp_{uuid.uuid4().hex}')
                fps = interpolate_frames_dir(frames_dir, interp_dir, fps, log_fn=log_fn)
                shutil.rmtree(frames_dir, ignore_errors=True)
                frames_dir = interp_dir

            # Step 3: ESRGAN upscale AFTER interpolation (with sharpness)
            if use_esrgan:
                _esrgan_process_frames_dir(frames_dir, upscale_model, upscale_scale,
                                           sharpness=sharpness, log_fn=log_fn)

            # Step 4: Encode — fps_boost already handled at frame level
            # For ESRGAN: sharpness already applied per-frame, pass 0.0 to avoid double
            encode_from_frames(frames_dir, fps, input_path, output_path,
                               quality,
                               lanczos_scale if not use_esrgan else None,
                               False,
                               sharpness if not use_esrgan else 0.0,
                               log_fn=log_fn)
        finally:
            shutil.rmtree(frames_dir, ignore_errors=True)
    else:
        # No frame extraction needed — FFmpeg handles everything directly
        process_video_direct(input_path, output_path, quality, lanczos_scale,
                             fps_boost, sharpness, log_fn=log_fn)


# ── Routes ────────────────────────────────────────────────────────────────────

@app.route('/')
def index():
    return render_template('index.html')


@app.route('/video/<path:filename>')
def serve_video(filename):
    return send_from_directory(UPLOAD_FOLDER, filename, as_attachment=False)


@app.route('/upload', methods=['POST'])
def upload():
    if 'video' not in request.files:
        return jsonify({'error': 'No file part'}), 400
    f = request.files['video']
    if not f.filename or not _allowed(f.filename):
        return jsonify({'error': 'Format tidak didukung'}), 400
    orig = secure_filename(f.filename)
    base, ext = os.path.splitext(orig)
    stored = f'{base}_{uuid.uuid4().hex}{ext}'
    f.save(os.path.join(UPLOAD_FOLDER, stored))
    _name_map[stored] = base
    return jsonify({
        'filename': stored,
        'originalBase': base,
        'isImage': _is_image(stored),
    })


@app.route('/process', methods=['POST'])
def process():
    data          = request.get_json(force=True)
    filename      = data.get('filename')
    roi           = data.get('roi')
    method        = data.get('method', 'telea')
    quality       = data.get('quality', 'ultra')
    upscale       = bool(data.get('upscale', False))
    upscale_model = data.get('upscale_model', 'lanczos')
    upscale_scale = int(data.get('upscale_scale', 2))
    fps_boost     = bool(data.get('fps_boost', False))
    sharpness     = float(data.get('sharpness', 0.0))

    if not filename:
        return jsonify({'error': 'filename required'}), 400
    input_path = os.path.join(UPLOAD_FOLDER, filename)
    if not os.path.exists(input_path):
        return jsonify({'error': 'File tidak ditemukan'}), 404

    remove_wm = _has_roi(roi)
    if not remove_wm and not upscale and not fps_boost:
        return jsonify({'error': 'Pilih minimal satu operasi'}), 400

    use_esrgan = upscale and upscale_model not in ('lanczos', '', None)
    if use_esrgan and not _esrgan_available():
        return jsonify({'error': 'realesrgan tidak terinstal. Jalankan: pip install realesrgan basicsr'}), 400

    orig_base = _name_map.get(filename, os.path.splitext(filename)[0])
    suffix    = _make_suffix(remove_wm, upscale, upscale_model, upscale_scale, fps_boost, sharpness)
    out_name  = f'{orig_base}{suffix}.mp4'
    out_path  = os.path.join(OUTPUT_FOLDER, out_name)

    job_id = data.get('job_id', '')
    _job_start(job_id)
    log_fn = (lambda msg: _job_log(job_id, msg)) if job_id else None

    try:
        if log_fn: log_fn('Mulai memproses video…')
        t0 = time.time()
        _do_process(input_path, out_path, roi, method, quality,
                    upscale, upscale_model, upscale_scale, fps_boost,
                    sharpness, log_fn=log_fn)
        elapsed = time.time() - t0
        if log_fn: log_fn(f'Selesai! Total waktu: {elapsed:.1f} detik.')
    except Exception as e:
        _job_done(job_id)
        return jsonify({'error': str(e)}), 500

    _job_done(job_id)
    return jsonify({
        'outputFilename': out_name,
        'outputDir': OUTPUT_FOLDER,
        'outputPath': out_path,
    })


@app.route('/process-image', methods=['POST'])
def process_image():
    data          = request.get_json(force=True)
    filename      = data.get('filename')
    roi           = data.get('roi')
    method        = data.get('method', 'telea')
    quality       = data.get('quality', 'ultra')
    upscale       = bool(data.get('upscale', False))
    upscale_model = data.get('upscale_model', 'lanczos')
    upscale_scale = int(data.get('upscale_scale', 2))
    sharpness     = float(data.get('sharpness', 0.0))

    if not filename:
        return jsonify({'error': 'filename required'}), 400
    input_path = os.path.join(UPLOAD_FOLDER, filename)
    if not os.path.exists(input_path):
        return jsonify({'error': 'File tidak ditemukan'}), 404

    remove_wm = _has_roi(roi)
    if not remove_wm and not upscale:
        return jsonify({'error': 'Pilih minimal satu operasi'}), 400

    use_esrgan = upscale and upscale_model not in ('lanczos', '', None)
    if use_esrgan and not _esrgan_available():
        return jsonify({'error': 'realesrgan tidak terinstal. Jalankan: pip install realesrgan basicsr'}), 400

    orig_base = _name_map.get(filename, os.path.splitext(filename)[0])
    suffix    = _make_suffix(remove_wm, upscale, upscale_model, upscale_scale, False, sharpness)
    out_ext   = '.png' if quality == 'ultra' else '.jpg'
    out_name  = f'{orig_base}{suffix}{out_ext}'
    out_path  = os.path.join(OUTPUT_FOLDER, out_name)

    job_id = data.get('job_id', '')
    _job_start(job_id)
    log_fn = (lambda msg: _job_log(job_id, msg)) if job_id else None

    try:
        if log_fn: log_fn('Mulai memproses foto…')
        t0 = time.time()
        process_image_file(
            input_path, out_path,
            roi, method, upscale, upscale_model, upscale_scale, quality,
            sharpness, log_fn=log_fn,
        )
        elapsed = time.time() - t0
        if log_fn: log_fn(f'Selesai! Total waktu: {elapsed:.1f} detik.')
    except Exception as e:
        _job_done(job_id)
        return jsonify({'error': str(e)}), 500

    _job_done(job_id)
    return jsonify({
        'outputFilename': out_name,
        'outputDir': OUTPUT_FOLDER,
        'outputPath': out_path,
    })


@app.route('/process-bulk', methods=['POST'])
def process_bulk():
    data          = request.get_json(force=True)
    files         = data.get('files', [])
    roi           = data.get('roi')
    method        = data.get('method', 'telea')
    quality       = data.get('quality', 'ultra')
    upscale       = bool(data.get('upscale', False))
    upscale_model = data.get('upscale_model', 'lanczos')
    upscale_scale = int(data.get('upscale_scale', 2))
    fps_boost     = bool(data.get('fps_boost', False))
    sharpness     = float(data.get('sharpness', 0.0))

    if not files:
        return jsonify({'error': 'Tidak ada file'}), 400
    remove_wm = _has_roi(roi)
    if not remove_wm and not upscale and not fps_boost:
        return jsonify({'error': 'Pilih minimal satu operasi'}), 400

    use_esrgan = upscale and upscale_model not in ('lanczos', '', None)
    if use_esrgan and not _esrgan_available():
        return jsonify({'error': 'realesrgan tidak terinstal. Jalankan: pip install realesrgan basicsr'}), 400

    job_id = data.get('job_id', '')
    _job_start(job_id)
    log_fn = (lambda msg: _job_log(job_id, msg)) if job_id else None

    suffix  = _make_suffix(remove_wm, upscale, upscale_model, upscale_scale, fps_boost, sharpness)
    results = []

    t0_bulk = time.time()
    for idx, item in enumerate(files, 1):
        stored    = item.get('filename', '')
        orig_base = item.get('originalBase') or _name_map.get(stored) or os.path.splitext(stored)[0]
        inp       = os.path.join(UPLOAD_FOLDER, stored)
        if not os.path.exists(inp):
            results.append({'file': orig_base, 'status': 'error', 'error': 'File tidak ditemukan'})
            continue
        out_name = f'{orig_base}{suffix}.mp4'
        out_path = os.path.join(OUTPUT_FOLDER, out_name)
        if log_fn: log_fn(f'[{idx}/{len(files)}] Memproses {orig_base}…')
        t0 = time.time()
        try:
            _do_process(inp, out_path, roi, method, quality,
                        upscale, upscale_model, upscale_scale, fps_boost,
                        sharpness, log_fn=log_fn)
            elapsed = time.time() - t0
            results.append({'file': orig_base, 'status': 'success', 'output': out_name, 'outputPath': out_path})
            if log_fn: log_fn(f'[{idx}/{len(files)}] {orig_base} — selesai ✓ ({elapsed:.1f}s)')
        except Exception as e:
            results.append({'file': orig_base, 'status': 'error', 'error': str(e)[:300]})
            if log_fn: log_fn(f'[{idx}/{len(files)}] {orig_base} — ERROR: {str(e)[:120]}')

    ok = sum(1 for r in results if r['status'] == 'success')
    total_elapsed = time.time() - t0_bulk
    if log_fn: log_fn(f'Bulk selesai: {ok}/{len(files)} berhasil. Total waktu: {total_elapsed:.1f} detik.')
    _job_done(job_id)
    return jsonify({
        'outputDir': OUTPUT_FOLDER,
        'results': results,
        'summary': f'{ok}/{len(files)} berhasil diproses',
    })


@app.route('/open-folder', methods=['POST'])
def open_folder():
    data = request.get_json(force=True)
    path = data.get('path', '')
    if not path:
        return jsonify({'error': 'Path diperlukan'}), 400

    real_path   = os.path.realpath(path)
    real_output = os.path.realpath(OUTPUT_FOLDER)
    if not real_path.startswith(real_output):
        return jsonify({'error': 'Akses ditolak'}), 403
    if not os.path.isdir(real_path):
        return jsonify({'error': 'Folder tidak ditemukan'}), 404

    try:
        sys_name = platform.system()
        if sys_name == 'Darwin':
            sp.Popen(['open', real_path])
        elif sys_name == 'Windows':
            sp.Popen(['explorer', real_path])
        else:
            sp.Popen(['xdg-open', real_path])
        return jsonify({'ok': True})
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/process-log/<job_id>')
def process_log(job_id):
    with _jobs_lock:
        info = _jobs.get(job_id)
        if info is None:
            return jsonify({'logs': [], 'done': True})
        return jsonify({'logs': list(info['logs']), 'done': info['done']})


@app.route('/heartbeat', methods=['POST'])
def heartbeat():
    global _last_heartbeat
    _last_heartbeat = time.time()
    return '', 204


@app.route('/esrgan-check')
def esrgan_check():
    return jsonify({'available': _esrgan_available()})


if __name__ == '__main__':
    import threading, webbrowser
    threading.Timer(1.2, lambda: webbrowser.open('http://127.0.0.1:5000')).start()
    app.run(debug=False, use_reloader=False, host='127.0.0.1', port=5000)
