// ── Helpers ──────────────────────────────────────────────
const $ = id => document.getElementById(id);
const VIDEO_EXTS = ['mp4','mov','m4v','webm','avi','mkv'];
const isVideo = name => VIDEO_EXTS.includes(name.split('.').pop().toLowerCase());

// ── Elements ─────────────────────────────────────────────
const dropzone       = $('dropzone');
const fileInput      = $('fileInput');
const folderInput    = $('folderInput');
const browseFileBtn  = $('browseFileBtn');
const browseFolderBtn = $('browseFolderBtn');
const sourceInfo     = $('sourceInfo');
const srcIcon        = $('srcIcon');
const srcLabel       = $('srcLabel');
const srcSub         = $('srcSub');
const clearSourceBtn = $('clearSourceBtn');
const modeBadge      = $('modeBadge');

const opWatermark    = $('opWatermark');
const opUpscale      = $('opUpscale');
const opFps          = $('opFps');
const methodSel      = $('method');
const qualitySel     = $('quality');

const processBtn     = $('processBtn');
const processBtnLabel = $('processBtnLabel');
const procProgress   = $('procProgress');
const procStatus     = $('procStatus');
const singleResult   = $('singleResult');
const bulkResultCard = $('bulkResultCard');
const bulkResults    = $('bulkResults');

const video          = $('video');
const overlay        = $('overlay');
const vpPlaceholder  = $('vpPlaceholder');

const playBtn       = $('playBtn');
const iconPlay      = $('iconPlay');
const iconPause     = $('iconPause');
const muteBtn       = $('muteBtn');
const iconVol       = $('iconVol');
const iconMute      = $('iconMute');
const seekSlider    = $('seekSlider');
const timeCurrent   = $('timeCurrent');
const timeTotal     = $('timeTotal');

const drawModeBtn    = $('drawModeBtn');
const drawNotice     = $('drawNotice');
const clearRoi       = $('clearRoi');
const clearRoiSmall  = $('clearRoiSmall');
const roiInfo        = $('roiInfo');
const roiText        = $('roiText');

const toasts = $('toasts');

// ── State ────────────────────────────────────────────────
// mode: 'none' | 'single' | 'bulk-files'
let mode = 'none';
let selectedFiles   = [];   // File[] for single/multi
let roi             = null;
let drawMode        = false;
let isDrawing       = false;
let startX = 0, startY = 0;

// ── Toast ───────────────────────────────────────────────
function toast(msg, type = 'info', ms = 3200) {
  const t = document.createElement('div');
  t.className = `toast ${type}`; t.textContent = msg;
  toasts.appendChild(t);
  setTimeout(() => t.remove(), ms);
}

// ── DROP ZONE ────────────────────────────────────────────
['dragenter','dragover'].forEach(ev => dropzone.addEventListener(ev, e => {
  e.preventDefault(); e.stopPropagation(); dropzone.classList.add('dragover');
}));
['dragleave','drop'].forEach(ev => dropzone.addEventListener(ev, e => {
  e.preventDefault(); e.stopPropagation(); dropzone.classList.remove('dragover');
}));
dropzone.addEventListener('drop', e => {
  const items = e.dataTransfer.items;
  if (!items) return;
  // Check if folder was dropped
  const entry = items[0]?.webkitGetAsEntry?.();
  if (entry && entry.isDirectory) {
    // Folder dropped — use path from folder (webkitdirectory fallback via files)
    const files = Array.from(e.dataTransfer.files).filter(f => isVideo(f.name));
    if (files.length === 0) { toast('Tidak ada video di folder tersebut', 'error'); return; }
    setSource('bulk-files', files);
  } else {
    const files = Array.from(e.dataTransfer.files).filter(f => isVideo(f.name));
    if (files.length === 0) { toast('File bukan video yang didukung', 'error'); return; }
    setSource(files.length === 1 ? 'single' : 'bulk-files', files);
  }
});

browseFileBtn.addEventListener('click', () => fileInput.click());
browseFolderBtn.addEventListener('click', () => folderInput.click());

fileInput.addEventListener('change', () => {
  const files = Array.from(fileInput.files).filter(f => isVideo(f.name));
  if (!files.length) return;
  setSource(files.length === 1 ? 'single' : 'bulk-files', files);
});

folderInput.addEventListener('change', () => {
  const files = Array.from(folderInput.files).filter(f => isVideo(f.name));
  if (!files.length) { toast('Tidak ada video di folder tersebut', 'error'); return; }
  setSource('bulk-files', files);
});

// Folder path scan removed

// ── SET SOURCE ───────────────────────────────────────────
function setSource(newMode, files) {
  mode = newMode;
  selectedFiles = files || [];
  roi = null; drawRoi(null);
  roiInfo.hidden = true;
  singleResult.hidden = true;
  bulkResultCard.hidden = true;

  if (mode === 'single') {
    const f = selectedFiles[0];
    showSourceInfo('🎬', f.name, formatSize(f.size));
    modeBadge.textContent = 'Single File';
    modeBadge.className = 'header-badge';
    processBtnLabel.textContent = 'Proses Video';
    loadVideoBlob(f);
  } else if (mode === 'bulk-files') {
    const f = selectedFiles[0];
    showSourceInfo('🗂️', `${selectedFiles.length} video dipilih`, `Referensi: ${f.name}`);
    modeBadge.textContent = `Bulk · ${selectedFiles.length} file`;
    modeBadge.className = 'header-badge bulk';
    processBtnLabel.textContent = `Proses ${selectedFiles.length} Video`;
    loadVideoBlob(f);
  }
  procStatus.textContent = '';
  updateProcessBtn();
}

function loadVideoBlob(file) {
  const url = URL.createObjectURL(file);
  video.src = url;
  vpPlaceholder.style.display = 'none';
  drawModeBtn.disabled = false;
  
  // reset controls
  iconPlay.hidden = false;
  iconPause.hidden = true;
  seekSlider.value = 0;
  timeCurrent.textContent = '0:00';
  timeTotal.textContent = '0:00';
}

function formatSize(bytes) {
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(0) + ' KB';
  return (bytes / 1024 / 1024).toFixed(1) + ' MB';
}

// ── OPERATIONS ───────────────────────────────────────────
[opWatermark, opUpscale, opFps].forEach(el => el.addEventListener('change', updateProcessBtn));

function updateProcessBtn() {
  const hasSource = mode !== 'none';
  const hasOp     = opWatermark.checked || opUpscale.checked || opFps.checked;
  const roiOk     = !opWatermark.checked || (roi && roi.width > 0);
  processBtn.disabled = !hasSource || !hasOp || !roiOk;
}

// ── DRAW MODE ─────────────────────────────────────────────
drawModeBtn.addEventListener('click', () => {
  drawMode = !drawMode;
  overlay.classList.toggle('draw-active', drawMode);
  drawModeBtn.classList.toggle('active', drawMode);
  drawModeBtn.textContent = drawMode ? '⏹ Selesai' : '✏️ Tandai Area';
  drawNotice.hidden = !drawMode;
});

// ── VIDEO CONTROLS ───────────────────────────────────────
function formatTime(s) {
  if (!s || isNaN(s)) return '0:00';
  const m = Math.floor(s / 60);
  const sec = Math.floor(s % 60).toString().padStart(2, '0');
  return `${m}:${sec}`;
}

video.addEventListener('loadedmetadata', () => { 
  fitCanvas(); 
  timeTotal.textContent = formatTime(video.duration);
  seekSlider.max = video.duration || 100;
});
video.addEventListener('timeupdate', () => {
  if (!isSeeking) seekSlider.value = video.currentTime;
  timeCurrent.textContent = formatTime(video.currentTime);
});

let isSeeking = false;
seekSlider.addEventListener('mousedown', () => isSeeking = true);
seekSlider.addEventListener('mouseup', () => isSeeking = false);
seekSlider.addEventListener('input', () => {
  video.currentTime = seekSlider.value;
  timeCurrent.textContent = formatTime(seekSlider.value);
});

playBtn.addEventListener('click', () => {
  if (!video.src) return;
  if (video.paused) {
    video.play();
    iconPlay.hidden = true;
    iconPause.hidden = false;
  } else {
    video.pause();
    iconPlay.hidden = false;
    iconPause.hidden = true;
  }
});

video.addEventListener('play', () => { iconPlay.hidden = true; iconPause.hidden = false; });
video.addEventListener('pause', () => { iconPlay.hidden = false; iconPause.hidden = true; });

muteBtn.addEventListener('click', () => {
  video.muted = !video.muted;
  iconVol.hidden = video.muted;
  iconMute.hidden = !video.muted;
});

// ── CANVAS ROI ────────────────────────────────────────────
function fitCanvas() {
  const w = video.clientWidth, h = video.clientHeight;
  if (!w || !h) return;
  overlay.width = w; overlay.height = h;
  overlay.style.width = w + 'px'; overlay.style.height = h + 'px';
  overlay.style.left = '0'; overlay.style.top = '0';
}

function drawRoi(r) {
  fitCanvas();
  const ctx = overlay.getContext('2d');
  ctx.clearRect(0, 0, overlay.width, overlay.height);
  if (!r || !video.videoWidth) return;
  const sx = overlay.width / video.videoWidth;
  const sy = overlay.height / video.videoHeight;
  ctx.strokeStyle = '#6366f1'; ctx.lineWidth = 2; ctx.setLineDash([6, 4]);
  ctx.strokeRect(r.x * sx, r.y * sy, r.width * sx, r.height * sy);
  ctx.fillStyle = 'rgba(99,102,241,0.14)';
  ctx.fillRect(r.x * sx, r.y * sy, r.width * sx, r.height * sy);
  // Label
  ctx.setLineDash([]);
  ctx.fillStyle = '#6366f1';
  ctx.font = '11px Inter, sans-serif';
  ctx.fillText(`${r.width}×${r.height}`, r.x * sx + 4, r.y * sy - 4);
}

window.addEventListener('resize', () => { fitCanvas(); drawRoi(roi); });
video.addEventListener('loadedmetadata', () => { fitCanvas(); });

overlay.addEventListener('mousedown', e => {
  if (!drawMode || !video.videoWidth) return;
  isDrawing = true;
  const p = mousePos(e);
  startX = p.x; startY = p.y;
  roi = null; drawRoi(null);
});
overlay.addEventListener('mousemove', e => {
  if (!isDrawing) return;
  const p = mousePos(e);
  const sx = video.videoWidth / overlay.width;
  const sy = video.videoHeight / overlay.height;
  roi = {
    x: Math.round(Math.min(p.x, startX) * sx),
    y: Math.round(Math.min(p.y, startY) * sy),
    width: Math.round(Math.abs(p.x - startX) * sx),
    height: Math.round(Math.abs(p.y - startY) * sy),
  };
  drawRoi(roi);
});
overlay.addEventListener('mouseup', () => {
  isDrawing = false;
  if (roi && roi.width > 2 && roi.height > 2) {
    roiText.textContent = `x:${roi.x} y:${roi.y} w:${roi.width} h:${roi.height}`;
    roiInfo.hidden = false;
    // Auto-exit draw mode
    drawMode = false;
    overlay.classList.remove('draw-active');
    drawModeBtn.classList.remove('active');
    drawModeBtn.textContent = '✏️ Tandai Area';
    drawNotice.hidden = true;
  }
  updateProcessBtn();
});

function clearRoiFn() {
  roi = null; drawRoi(null); roiInfo.hidden = true; updateProcessBtn();
}
clearRoi.addEventListener('click', clearRoiFn);
clearRoiSmall.addEventListener('click', clearRoiFn);

function mousePos(e) {
  const r = overlay.getBoundingClientRect();
  return { x: e.clientX - r.left, y: e.clientY - r.top };
}

// ── PROCESS ───────────────────────────────────────────────
processBtn.addEventListener('click', doProcess);

async function doProcess() {
  if (mode === 'none') { toast('Pilih file video dulu', 'error'); return; }
  const hasOp = opWatermark.checked || opUpscale.checked || opFps.checked;
  if (!hasOp) { toast('Pilih minimal satu operasi', 'error'); return; }
  if (opWatermark.checked && (!roi || roi.width <= 0)) {
    toast('Klik ✏️ Tandai Area lalu gambar kotak pada watermark', 'error'); return;
  }

  const commonPayload = {
    roi:       opWatermark.checked ? roi : null,
    method:    methodSel.value,
    quality:   qualitySel.value,
    upscale:   opUpscale.checked,
    fps_boost: opFps.checked,
  };

  processBtn.disabled = true;
  procProgress.hidden = false;
  singleResult.hidden = true;
  bulkResultCard.hidden = true;

  try {
    if (mode === 'single') {
      procStatus.textContent = 'Mengupload…';
      const upData = await uploadFile(selectedFiles[0]);
      procStatus.textContent = 'Memproses…';
      const res = await post('/process', { filename: upData.filename, ...commonPayload });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      showSingleResult(data);
      toast('Selesai! File tersimpan.', 'success');

    } else if (mode === 'bulk-files') {
      const uploaded = [];
      for (let i = 0; i < selectedFiles.length; i++) {
        procStatus.textContent = `Mengupload ${i + 1}/${selectedFiles.length}…`;
        const up = await uploadFile(selectedFiles[i]);
        uploaded.push(up);
      }
      procStatus.textContent = `Memproses ${selectedFiles.length} video…`;
      const res = await post('/process-bulk', { files: uploaded, ...commonPayload });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      showBulkResults(data);
      toast(data.summary, 'success');
    }
  } catch (e) {
    toast(e.message || 'Terjadi kesalahan', 'error');
  } finally {
    procProgress.hidden = true;
    procStatus.textContent = '';
    processBtn.disabled = false;
    updateProcessBtn();
  }
}

async function uploadFile(file) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    const form = new FormData();
    form.append('video', file);
    xhr.open('POST', '/upload');
    xhr.onload = () => {
      try {
        const d = JSON.parse(xhr.responseText);
        xhr.status < 300 ? resolve(d) : reject(new Error(d.error || 'Upload gagal'));
      } catch { reject(new Error('Server error')); }
    };
    xhr.onerror = () => reject(new Error('Network error'));
    xhr.send(form);
  });
}

function post(url, body) {
  return fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
}

function showSingleResult(data) {
  singleResult.innerHTML = `
    <div class="r-title">
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>
      Berhasil disimpan
    </div>
    <div class="r-fn">${data.outputFilename}</div>
    <div class="r-path">${data.outputPath}</div>
  `;
  singleResult.hidden = false;
}

function showBulkResults(data) {
  let html = `<div class="bulk-summary">${data.summary}</div>`;
  if (data.outputDir) html += `<div class="bulk-dir">📁 ${data.outputDir}</div>`;
  for (const r of (data.results || [])) {
    if (r.status === 'success') {
      html += `<div class="bulk-item">
        <div class="bulk-status ok">✓</div>
        <div><div class="bulk-fname">${r.file}</div><div class="bulk-out">→ ${r.output}</div></div>
      </div>`;
    } else {
      html += `<div class="bulk-item">
        <div class="bulk-status err">✗</div>
        <div><div class="bulk-fname">${r.file}</div><div class="bulk-err">${r.error}</div></div>
      </div>`;
    }
  }
  bulkResults.innerHTML = html;
  bulkResultCard.hidden = false;
}
