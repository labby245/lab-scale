import os
import uuid
import shutil

from flask import Flask, render_template, request, jsonify, send_from_directory
from werkzeug.utils import secure_filename

from utils.video import (
    remove_watermark_roi_to_frames,
    encode_from_frames,
    process_video_direct,
    probe_video_info,
)

APP_ROOT     = os.path.dirname(os.path.abspath(__file__))
UPLOAD_FOLDER = os.path.join(APP_ROOT, 'uploads')
TEMP_FOLDER   = os.path.join(APP_ROOT, 'temp')
OUTPUT_FOLDER = os.path.join(APP_ROOT, 'outputs')
ALLOWED_EXTENSIONS = {'.mp4', '.mov', '.m4v', '.webm', '.avi', '.mkv'}

for _d in (UPLOAD_FOLDER, TEMP_FOLDER, OUTPUT_FOLDER):
    os.makedirs(_d, exist_ok=True)

app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 2 * 1024 * 1024 * 1024  # 2 GB

# stored_name -> original base name (without ext)
_name_map: dict[str, str] = {}


def _allowed(filename: str) -> bool:
    return os.path.splitext(filename.lower())[1] in ALLOWED_EXTENSIONS


def _make_suffix(remove_wm: bool, upscale: bool, fps_boost: bool) -> str:
    parts = []
    if remove_wm:  parts.append('nowm')
    if upscale:    parts.append('upscale2x')
    if fps_boost:  parts.append('60fps')
    return ('_' + '_'.join(parts)) if parts else '_processed'


def _has_roi(roi) -> bool:
    if not roi:
        return False
    return int(roi.get('width', 0)) > 0 and int(roi.get('height', 0)) > 0


def _do_process(input_path, output_path, roi, method, quality, upscale, fps_boost):
    """Shared processing core."""
    remove_wm = _has_roi(roi)
    if remove_wm:
        frames_dir = os.path.join(TEMP_FOLDER, f'frm_{uuid.uuid4().hex}')
        try:
            fps = remove_watermark_roi_to_frames(
                input_video_path=input_path,
                output_frames_dir=frames_dir,
                roi=(int(roi['x']), int(roi['y']), int(roi['width']), int(roi['height'])),
                inpaint_method=method,
            )
            encode_from_frames(
                frames_dir=frames_dir,
                fps=fps,
                source_audio=input_path,
                output_path=output_path,
                quality=quality,
                upscale=upscale,
                fps_boost=fps_boost,
            )
        finally:
            shutil.rmtree(frames_dir, ignore_errors=True)
    else:
        process_video_direct(
            input_path=input_path,
            output_path=output_path,
            quality=quality,
            upscale=upscale,
            fps_boost=fps_boost,
        )


# ── Routes ──────────────────────────────────────────────────────────────────

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
    if not f.filename:
        return jsonify({'error': 'No selected file'}), 400
    if not _allowed(f.filename):
        return jsonify({'error': 'Format tidak didukung'}), 400

    orig  = secure_filename(f.filename)
    base, ext = os.path.splitext(orig)
    stored = f'{base}_{uuid.uuid4().hex}{ext}'
    f.save(os.path.join(UPLOAD_FOLDER, stored))
    _name_map[stored] = base

    return jsonify({'filename': stored, 'videoUrl': f'/video/{stored}', 'originalBase': base})


@app.route('/process', methods=['POST'])
def process():
    data      = request.get_json(force=True)
    filename  = data.get('filename')
    roi       = data.get('roi')
    method    = data.get('method', 'telea')
    quality   = data.get('quality', 'ultra')
    upscale   = bool(data.get('upscale', False))
    fps_boost = bool(data.get('fps_boost', False))

    if not filename:
        return jsonify({'error': 'filename diperlukan'}), 400

    input_path = os.path.join(UPLOAD_FOLDER, filename)
    if not os.path.exists(input_path):
        return jsonify({'error': 'File tidak ditemukan'}), 404

    remove_wm = _has_roi(roi)
    if not remove_wm and not upscale and not fps_boost:
        return jsonify({'error': 'Pilih minimal satu operasi'}), 400

    orig_base = _name_map.get(filename, os.path.splitext(filename)[0])
    suffix    = _make_suffix(remove_wm, upscale, fps_boost)
    out_name  = f'{orig_base}{suffix}.mp4'
    out_path  = os.path.join(OUTPUT_FOLDER, out_name)

    try:
        _do_process(input_path, out_path, roi, method, quality, upscale, fps_boost)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

    return jsonify({
        'outputFilename': out_name,
        'outputDir':      OUTPUT_FOLDER,
        'outputPath':     out_path,
    })


@app.route('/process-folder', methods=['POST'])
def process_folder():
    data        = request.get_json(force=True)
    folder_path = data.get('folder_path', '').strip()
    roi         = data.get('roi')
    method      = data.get('method', 'telea')
    quality     = data.get('quality', 'ultra')
    upscale     = bool(data.get('upscale', False))
    fps_boost   = bool(data.get('fps_boost', False))

    if not folder_path:
        return jsonify({'error': 'folder_path diperlukan'}), 400
    if not os.path.isdir(folder_path):
        return jsonify({'error': f'Folder tidak ditemukan: {folder_path}'}), 400

    remove_wm = _has_roi(roi)
    if not remove_wm and not upscale and not fps_boost:
        return jsonify({'error': 'Pilih minimal satu operasi'}), 400

    video_files = sorted(
        f for f in os.listdir(folder_path)
        if os.path.splitext(f.lower())[1] in ALLOWED_EXTENSIONS
    )
    if not video_files:
        return jsonify({'error': 'Tidak ada video di folder tersebut'}), 400

    suffix  = _make_suffix(remove_wm, upscale, fps_boost)
    out_dir = os.path.join(folder_path, 'processed')
    os.makedirs(out_dir, exist_ok=True)

    results = []
    for fname in video_files:
        inp      = os.path.join(folder_path, fname)
        base     = os.path.splitext(fname)[0]
        out_name = f'{base}{suffix}.mp4'
        out_path = os.path.join(out_dir, out_name)
        try:
            _do_process(inp, out_path, roi, method, quality, upscale, fps_boost)
            results.append({'file': fname, 'status': 'success', 'output': out_name})
        except Exception as e:
            results.append({'file': fname, 'status': 'error', 'error': str(e)[:300]})

    ok = sum(1 for r in results if r['status'] == 'success')
    return jsonify({
        'outputDir': out_dir,
        'results':   results,
        'summary':   f'{ok}/{len(video_files)} berhasil diproses',
    })


@app.route('/process-bulk', methods=['POST'])
def process_bulk():
    """Process a list of already-uploaded files (bulk 'files' mode)."""
    data      = request.get_json(force=True)
    files     = data.get('files', [])  # [{filename, originalBase}, ...]
    roi       = data.get('roi')
    method    = data.get('method', 'telea')
    quality   = data.get('quality', 'ultra')
    upscale   = bool(data.get('upscale', False))
    fps_boost = bool(data.get('fps_boost', False))

    if not files:
        return jsonify({'error': 'Tidak ada file untuk diproses'}), 400

    remove_wm = _has_roi(roi)
    if not remove_wm and not upscale and not fps_boost:
        return jsonify({'error': 'Pilih minimal satu operasi'}), 400

    suffix  = _make_suffix(remove_wm, upscale, fps_boost)
    results = []

    for item in files:
        stored_name = item.get('filename', '')
        orig_base   = item.get('originalBase') or _name_map.get(stored_name) or os.path.splitext(stored_name)[0]
        input_path  = os.path.join(UPLOAD_FOLDER, stored_name)

        if not os.path.exists(input_path):
            results.append({'file': orig_base, 'status': 'error', 'error': 'File tidak ditemukan'})
            continue

        out_name = f'{orig_base}{suffix}.mp4'
        out_path = os.path.join(OUTPUT_FOLDER, out_name)

        try:
            _do_process(input_path, out_path, roi, method, quality, upscale, fps_boost)
            results.append({'file': orig_base, 'status': 'success', 'output': out_name, 'outputPath': out_path})
        except Exception as e:
            results.append({'file': orig_base, 'status': 'error', 'error': str(e)[:300]})

    ok = sum(1 for r in results if r['status'] == 'success')
    return jsonify({
        'outputDir': OUTPUT_FOLDER,
        'results':   results,
        'summary':   f'{ok}/{len(files)} berhasil diproses',
    })


@app.route('/scan-folder', methods=['POST'])
def scan_folder():
    data = request.get_json(force=True)
    folder_path = data.get('folder_path', '').strip()
    if not folder_path or not os.path.isdir(folder_path):
        return jsonify({'error': 'Folder tidak valid'}), 400

    files = sorted(
        f for f in os.listdir(folder_path)
        if os.path.splitext(f.lower())[1] in ALLOWED_EXTENSIONS
    )
    return jsonify({'files': files, 'count': len(files)})


if __name__ == '__main__':
    app.run(debug=True, host='127.0.0.1', port=5000)
