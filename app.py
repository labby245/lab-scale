import atexit
import datetime
import os
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
    encode_from_frames,
    process_video_direct,
    process_image_file,
    generate_video_comparison,
    _esrgan_available,
    _esrgan_process_frames_dir,
)

APP_ROOT      = os.path.dirname(os.path.abspath(__file__))
UPLOAD_FOLDER = os.path.join(APP_ROOT, 'uploads')
TEMP_FOLDER   = os.path.join(APP_ROOT, 'temp')
OUTPUT_FOLDER = os.path.join(APP_ROOT, 'outputs')

ALLOWED_VIDEO_EXT = {'.mp4', '.mov', '.m4v', '.webm', '.avi', '.mkv'}
ALLOWED_IMAGE_EXT = {'.jpg', '.jpeg', '.png', '.webp', '.tiff', '.bmp'}
ALLOWED_EXTENSIONS = ALLOWED_VIDEO_EXT | ALLOWED_IMAGE_EXT

for _d in (UPLOAD_FOLDER, TEMP_FOLDER, OUTPUT_FOLDER):
    os.makedirs(_d, exist_ok=True)

app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 2 * 1024 * 1024 * 1024  # 2 GB

_name_map: dict[str, str] = {}

# session_id -> list of comparison file paths (deleted on tab close)
_preview_files: dict[str, list] = {}

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


# ── Helpers ──────────────────────────────────────────────────────────────────

def _allowed(fn: str) -> bool:
    return os.path.splitext(fn.lower())[1] in ALLOWED_EXTENSIONS


def _is_image(fn: str) -> bool:
    return os.path.splitext(fn.lower())[1] in ALLOWED_IMAGE_EXT


def _has_roi(roi) -> bool:
    return bool(roi) and int(roi.get('width', 0)) > 0 and int(roi.get('height', 0)) > 0


def _make_suffix(remove_wm: bool, upscale: bool, upscale_model: str,
                 upscale_scale: int, fps_boost: bool) -> str:
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
    if fps_boost:
        p.append('60fps')
    return ('_' + '_'.join(p)) if p else '_processed'


def _register_preview(session_id: str, path: str) -> None:
    if session_id:
        _preview_files.setdefault(session_id, []).append(path)


def _cleanup_session(session_id: str) -> int:
    paths = _preview_files.pop(session_id, [])
    cleaned = 0
    for p in paths:
        try:
            if os.path.isfile(p):
                os.remove(p)
                cleaned += 1
        except Exception:
            pass
    return cleaned


def _cleanup_all_previews() -> None:
    for sid in list(_preview_files.keys()):
        _cleanup_session(sid)


atexit.register(_cleanup_all_previews)


def _do_process(input_path, output_path, roi, method, quality,
                upscale, upscale_model, upscale_scale, fps_boost, log_fn=None):
    """Core video processing: watermark removal and/or upscale/fps boost."""
    remove_wm   = _has_roi(roi)
    use_esrgan  = upscale and upscale_model not in ('lanczos', '', None)
    lanczos_scale = (
        upscale_scale
        if (upscale and not use_esrgan and upscale_scale and upscale_scale > 1)
        else None
    )

    if remove_wm or use_esrgan:
        frames_dir = os.path.join(TEMP_FOLDER, f'frm_{uuid.uuid4().hex}')
        try:
            if remove_wm:
                fps = remove_watermark_roi_to_frames(
                    input_path, frames_dir,
                    (int(roi['x']), int(roi['y']), int(roi['width']), int(roi['height'])),
                    method, log_fn=log_fn,
                )
            else:
                fps = extract_frames_to_dir(input_path, frames_dir, log_fn=log_fn)

            if use_esrgan:
                _esrgan_process_frames_dir(frames_dir, upscale_model, upscale_scale, log_fn=log_fn)
                encode_from_frames(frames_dir, fps, input_path, output_path,
                                   quality, None, fps_boost, log_fn=log_fn)
            else:
                encode_from_frames(frames_dir, fps, input_path, output_path,
                                   quality, lanczos_scale, fps_boost, log_fn=log_fn)
        finally:
            shutil.rmtree(frames_dir, ignore_errors=True)
    else:
        process_video_direct(input_path, output_path, quality, lanczos_scale, fps_boost, log_fn=log_fn)


# ── Routes ───────────────────────────────────────────────────────────────────

@app.route('/')
def index():
    return render_template('index.html')


@app.route('/video/<path:filename>')
def serve_video(filename):
    return send_from_directory(UPLOAD_FOLDER, filename, as_attachment=False)


@app.route('/output/<path:filename>')
def serve_output(filename):
    return send_from_directory(OUTPUT_FOLDER, filename, as_attachment=False)


@app.route('/temp/<path:filename>')
def serve_temp(filename):
    return send_from_directory(TEMP_FOLDER, filename, as_attachment=False)


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
    comparison    = bool(data.get('comparison', False))
    session_id    = data.get('session_id', '')

    if not filename:
        return jsonify({'error': 'filename required'}), 400
    input_path = os.path.join(UPLOAD_FOLDER, filename)
    if not os.path.exists(input_path):
        return jsonify({'error': 'File tidak ditemukan'}), 404

    remove_wm = _has_roi(roi)
    if not remove_wm and not upscale and not fps_boost:
        return jsonify({'error': 'Pilih minimal satu operasi'}), 400

    # Validate ESRGAN availability
    use_esrgan = upscale and upscale_model not in ('lanczos', '', None)
    if use_esrgan and not _esrgan_available():
        return jsonify({'error': 'realesrgan tidak terinstal. Jalankan: pip install realesrgan basicsr'}), 400

    orig_base = _name_map.get(filename, os.path.splitext(filename)[0])
    suffix    = _make_suffix(remove_wm, upscale, upscale_model, upscale_scale, fps_boost)
    out_name  = f'{orig_base}{suffix}.mp4'
    out_path  = os.path.join(OUTPUT_FOLDER, out_name)

    job_id = data.get('job_id', '')
    _job_start(job_id)
    log_fn = (lambda msg: _job_log(job_id, msg)) if job_id else None

    try:
        if log_fn: log_fn('Mulai memproses video…')
        _do_process(input_path, out_path, roi, method, quality,
                    upscale, upscale_model, upscale_scale, fps_boost, log_fn=log_fn)
    except Exception as e:
        _job_done(job_id)
        return jsonify({'error': str(e)}), 500

    resp = {
        'outputFilename': out_name,
        'outputDir': OUTPUT_FOLDER,
        'outputPath': out_path,
    }

    # Generate side-by-side comparison video if requested
    if comparison:
        try:
            if log_fn: log_fn('Membuat video comparison…')
            cmp_name = f'{orig_base}{suffix}_comparison.mp4'
            cmp_path = os.path.join(OUTPUT_FOLDER, cmp_name)
            generate_video_comparison(input_path, out_path, cmp_path, log_fn=log_fn)
            _register_preview(session_id, cmp_path)
            resp['comparisonFilename'] = cmp_name
        except Exception as e:
            resp['comparisonError'] = str(e)

    if log_fn: log_fn('Selesai!')
    _job_done(job_id)
    return jsonify(resp)


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
    comparison    = bool(data.get('comparison', False))
    session_id    = data.get('session_id', '')

    if not filename:
        return jsonify({'error': 'filename required'}), 400
    input_path = os.path.join(UPLOAD_FOLDER, filename)
    if not os.path.exists(input_path):
        return jsonify({'error': 'File tidak ditemukan'}), 404

    remove_wm = _has_roi(roi)
    if not remove_wm and not upscale:
        return jsonify({'error': 'Pilih minimal satu operasi'}), 400

    # Validate ESRGAN availability
    use_esrgan = upscale and upscale_model not in ('lanczos', '', None)
    if use_esrgan and not _esrgan_available():
        return jsonify({'error': 'realesrgan tidak terinstal. Jalankan: pip install realesrgan basicsr'}), 400

    orig_base = _name_map.get(filename, os.path.splitext(filename)[0])
    suffix    = _make_suffix(remove_wm, upscale, upscale_model, upscale_scale, False)
    out_ext   = '.png' if quality == 'ultra' else '.jpg'
    out_name  = f'{orig_base}{suffix}{out_ext}'
    out_path  = os.path.join(OUTPUT_FOLDER, out_name)

    # Save original copy in temp for comparison
    orig_ext  = os.path.splitext(filename)[1]
    orig_copy = os.path.join(TEMP_FOLDER, f'orig_{uuid.uuid4().hex}{orig_ext}')

    job_id = data.get('job_id', '')
    _job_start(job_id)
    log_fn = (lambda msg: _job_log(job_id, msg)) if job_id else None

    try:
        if log_fn: log_fn('Mulai memproses foto…')
        process_image_file(
            input_path, orig_copy, out_path,
            roi, method, upscale, upscale_model, upscale_scale, quality,
            log_fn=log_fn,
        )
    except Exception as e:
        _job_done(job_id)
        return jsonify({'error': str(e)}), 500

    resp = {
        'outputFilename': out_name,
        'outputDir': OUTPUT_FOLDER,
        'outputPath': out_path,
    }

    if comparison and os.path.exists(orig_copy):
        orig_copy_name = os.path.basename(orig_copy)
        resp['originalUrl']  = f'/temp/{orig_copy_name}'
        resp['processedUrl'] = f'/output/{out_name}'
        _register_preview(session_id, orig_copy)

    if log_fn: log_fn('Selesai!')
    _job_done(job_id)
    return jsonify(resp)


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

    suffix  = _make_suffix(remove_wm, upscale, upscale_model, upscale_scale, fps_boost)
    results = []

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
        try:
            _do_process(inp, out_path, roi, method, quality,
                        upscale, upscale_model, upscale_scale, fps_boost, log_fn=log_fn)
            results.append({'file': orig_base, 'status': 'success', 'output': out_name, 'outputPath': out_path})
            if log_fn: log_fn(f'[{idx}/{len(files)}] {orig_base} — selesai ✓')
        except Exception as e:
            results.append({'file': orig_base, 'status': 'error', 'error': str(e)[:300]})
            if log_fn: log_fn(f'[{idx}/{len(files)}] {orig_base} — ERROR: {str(e)[:120]}')

    ok = sum(1 for r in results if r['status'] == 'success')
    if log_fn: log_fn(f'Bulk selesai: {ok}/{len(files)} berhasil.')
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

    # Security: path must resolve inside OUTPUT_FOLDER
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


@app.route('/esrgan-check')
def esrgan_check():
    return jsonify({'available': _esrgan_available()})


@app.route('/cleanup-preview', methods=['POST'])
def cleanup_preview():
    try:
        # sendBeacon sends text/plain; force=True handles that
        data = request.get_json(force=True, silent=True) or {}
    except Exception:
        data = {}
    session_id = data.get('session_id', '')
    cleaned = _cleanup_session(session_id) if session_id else 0
    return jsonify({'cleaned': cleaned})


if __name__ == '__main__':
    app.run(debug=True, host='127.0.0.1', port=5000)
