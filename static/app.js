// ── Helpers ──────────────────────────────────────────────
const $ = id => document.getElementById(id);
const VIDEO_EXTS = ['mp4','mov','m4v','webm','avi','mkv'];
const IMAGE_EXTS = ['jpg','jpeg','png','webp','tiff','bmp'];
const isVideo = name => VIDEO_EXTS.includes(name.split('.').pop().toLowerCase());
const isImage = name => IMAGE_EXTS.includes(name.split('.').pop().toLowerCase());
const isMedia = name => isVideo(name) || isImage(name);

// ── Session ID (for cleanup-preview on tab close) ────────
let sessionId = sessionStorage.getItem('forge_session');
if (!sessionId) {
  sessionId = (crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).slice(2));
  sessionStorage.setItem('forge_session', sessionId);
}

// ── Elements ─────────────────────────────────────────────
const dropzone        = $('dropzone');
const fileInput       = $('fileInput');
const folderInput     = $('folderInput');
const browseFileBtn   = $('browseFileBtn');
const browseFolderBtn = $('browseFolderBtn');
const sourceInfo      = $('sourceInfo');
const srcIcon         = $('srcIcon');
const srcLabel        = $('srcLabel');
const srcSub          = $('srcSub');
const clearSourceBtn  = $('clearSourceBtn');
const modeBadge       = $('modeBadge');

const opWatermark     = $('opWatermark');
const opUpscale       = $('opUpscale');
const opFps           = $('opFps');
const opComparison    = $('opComparison');
const methodSel       = $('method');
const qualitySel      = $('quality');
const wmSubSettings   = $('wmSubSettings');
const esrganOptions   = $('esrganOptions');
const opFpsRow        = $('opFpsRow');
const esrganModel     = $('esrganModel');
const esrganWarn      = $('esrganWarn');
const esrganInstall   = $('esrganInstall');
const dimEstimate     = $('dimEstimate');

const processBtn      = $('processBtn');
const processBtnLabel = $('processBtnLabel');
const procProgress    = $('procProgress');
const procStatus      = $('procStatus');
const singleResult    = $('singleResult');
const bulkResultCard  = $('bulkResultCard');
const bulkResults     = $('bulkResults');

const video           = $('video');
const previewImg      = $('previewImg');
const overlay         = $('overlay');
const vpPlaceholder   = $('vpPlaceholder');
const customControls  = $('customControls');

const playBtn        = $('playBtn');
const iconPlay       = $('iconPlay');
const iconPause      = $('iconPause');
const muteBtn        = $('muteBtn');
const iconVol        = $('iconVol');
const iconMute       = $('iconMute');
const seekSlider     = $('seekSlider');
const timeCurrent    = $('timeCurrent');
const timeTotal      = $('timeTotal');

const drawModeBtn     = $('drawModeBtn');
const drawNotice      = $('drawNotice');
const clearRoi        = $('clearRoi');
const clearRoiSmall   = $('clearRoiSmall');
const roiInfo         = $('roiInfo');
const roiText         = $('roiText');

const comparisonCard  = $('comparisonCard');
const comparisonWrap  = $('comparisonWrap');
const cmpOrigImg      = $('cmpOrigImg');
const cmpProcImg      = $('cmpProcImg');
const cmpAfter        = $('cmpAfter');
const cmpDivider      = $('cmpDivider');
const cmpSlider       = $('cmpSlider');
const cmpVideo        = $('cmpVideo');

const logCard    = $('logCard');
const logBody    = $('logBody');
const logSpinner = $('logSpinner');

const toasts = $('toasts');

// ── State ────────────────────────────────────────────────
let mode          = 'none';   // 'none' | 'single' | 'bulk-files'
let mediaType     = 'none';   // 'none' | 'video' | 'image'
let selectedFiles = [];
let roi           = null;
let drawMode      = false;
let isDrawing     = false;
let startX = 0, startY = 0;
let selectedScale = 2;
let esrganAvailable = false;
let _logPollTimer = null;
let _seenLogCount = 0;

// ── Toast ───────────────────────────────────────────────
function toast(msg, type = 'info', ms = 3200) {
  const t = document.createElement('div');
  t.className = `toast ${type}`; t.textContent = msg;
  toasts.appendChild(t);
  setTimeout(() => t.remove(), ms);
}

// ── ESRGAN check on load ─────────────────────────────────
fetch('/esrgan-check')
  .then(r => r.json())
  .then(d => {
    esrganAvailable = d.available;
    esrganInstall.hidden = esrganAvailable;
  })
  .catch(() => {});

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
  const entry = items[0]?.webkitGetAsEntry?.();
  if (entry && entry.isDirectory) {
    const files = Array.from(e.dataTransfer.files).filter(f => isMedia(f.name));
    if (files.length === 0) { toast('Tidak ada file yang didukung di folder tersebut', 'error'); return; }
    setSource('bulk-files', files);
  } else {
    const files = Array.from(e.dataTransfer.files).filter(f => isMedia(f.name));
    if (files.length === 0) { toast('Format file tidak didukung', 'error'); return; }
    setSource(files.length === 1 ? 'single' : 'bulk-files', files);
  }
});

browseFileBtn.addEventListener('click', () => fileInput.click());
browseFolderBtn.addEventListener('click', () => folderInput.click());

fileInput.addEventListener('change', () => {
  const files = Array.from(fileInput.files).filter(f => isMedia(f.name));
  if (!files.length) return;
  setSource(files.length === 1 ? 'single' : 'bulk-files', files);
  fileInput.value = '';
});

folderInput.addEventListener('change', () => {
  const files = Array.from(folderInput.files).filter(f => isMedia(f.name));
  if (!files.length) { toast('Tidak ada file yang didukung di folder tersebut', 'error'); return; }
  setSource('bulk-files', files);
  folderInput.value = '';
});

// ── SET SOURCE ───────────────────────────────────────────
function setSource(newMode, files) {
  mode          = newMode;
  selectedFiles = files || [];
  roi           = null;
  drawRoi(null);
  roiInfo.hidden       = true;
  singleResult.hidden  = true;
  bulkResultCard.hidden = true;
  comparisonCard.hidden = true;

  // Detect media type from first file
  const firstFile = selectedFiles[0];
  mediaType = firstFile ? (isImage(firstFile.name) ? 'image' : 'video') : 'none';

  // Show/hide FPS boost (video only)
  opFpsRow.hidden = (mediaType === 'image');
  if (mediaType === 'image' && opFps.checked) {
    opFps.checked = false;
  }

  if (mode === 'single') {
    showSourceInfo(mediaType === 'image' ? '🖼️' : '🎬', firstFile.name, formatSize(firstFile.size));
    modeBadge.textContent = 'Single File';
    modeBadge.className   = 'header-badge';
    processBtnLabel.textContent = 'Proses File';
    if (mediaType === 'image') {
      loadImageBlob(firstFile);
    } else {
      loadVideoBlob(firstFile);
    }
  } else if (mode === 'bulk-files') {
    showSourceInfo('🗂️', `${selectedFiles.length} file dipilih`, `Referensi: ${firstFile.name}`);
    modeBadge.textContent = `Bulk · ${selectedFiles.length} file`;
    modeBadge.className   = 'header-badge bulk';
    processBtnLabel.textContent = `Proses ${selectedFiles.length} File`;
    if (mediaType === 'image') {
      loadImageBlob(firstFile);
    } else {
      loadVideoBlob(firstFile);
    }
  }

  procStatus.textContent = '';
  updateDimEstimate();
  updateProcessBtn();
}

function showSourceInfo(icon, label, sub) {
  srcIcon.textContent  = icon;
  srcLabel.textContent = label;
  srcSub.textContent   = sub;
  sourceInfo.hidden    = false;
}

clearSourceBtn.addEventListener('click', () => {
  mode          = 'none';
  mediaType     = 'none';
  selectedFiles = [];
  sourceInfo.hidden    = true;
  modeBadge.textContent = '';
  modeBadge.className  = 'header-badge';

  // Clear video
  video.src    = '';
  video.hidden = true;
  customControls.hidden = true;

  // Clear image
  previewImg.src    = '';
  previewImg.hidden = true;

  vpPlaceholder.style.display = '';

  roi = null; drawRoi(null); roiInfo.hidden = true;
  drawModeBtn.disabled = true;
  singleResult.hidden   = true;
  bulkResultCard.hidden = true;
  comparisonCard.hidden = true;
  logCard.hidden        = true;
  procStatus.textContent = '';
  updateDimEstimate();
  updateProcessBtn();
});

function loadVideoBlob(file) {
  const url    = URL.createObjectURL(file);
  video.src    = url;
  video.hidden = false;
  previewImg.hidden     = true;
  customControls.hidden = false;
  vpPlaceholder.style.display = 'none';
  drawModeBtn.disabled = false;

  iconPlay.hidden  = false;
  iconPause.hidden = true;
  seekSlider.value = 0;
  timeCurrent.textContent = '0:00';
  timeTotal.textContent   = '0:00';
}

function loadImageBlob(file) {
  const url = URL.createObjectURL(file);
  previewImg.src    = url;
  previewImg.hidden = false;
  video.src         = '';
  video.hidden      = true;
  customControls.hidden = true;
  vpPlaceholder.style.display = 'none';
  drawModeBtn.disabled = false;

  previewImg.onload = () => {
    fitCanvas();
    updateDimEstimate();
  };
}

function formatSize(bytes) {
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(0) + ' KB';
  return (bytes / 1024 / 1024).toFixed(1) + ' MB';
}

// ── Media dimensions helpers ─────────────────────────────
function mediaWidth()  { return mediaType === 'image' ? previewImg.naturalWidth  : video.videoWidth;  }
function mediaHeight() { return mediaType === 'image' ? previewImg.naturalHeight : video.videoHeight; }

// ── OPERATIONS ───────────────────────────────────────────
opWatermark.addEventListener('change', () => {
  wmSubSettings.hidden = !opWatermark.checked;
  updateProcessBtn();
});

opUpscale.addEventListener('change', () => {
  esrganOptions.hidden = !opUpscale.checked;
  updateDimEstimate();
  updateProcessBtn();
});

esrganModel.addEventListener('change', () => {
  const isAI = esrganModel.value !== 'lanczos';
  esrganWarn.hidden    = !(isAI && mediaType === 'video');
  esrganInstall.hidden = esrganAvailable || !isAI;
  updateDimEstimate();
});

// Scale buttons
document.querySelectorAll('.scale-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.scale-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    selectedScale = parseInt(btn.dataset.scale, 10);
    updateDimEstimate();
  });
});

[opFps].forEach(el => el.addEventListener('change', updateProcessBtn));

function updateProcessBtn() {
  const hasSource = mode !== 'none';
  const hasOp     = opWatermark.checked || opUpscale.checked || opFps.checked;
  const roiOk     = !opWatermark.checked || (roi && roi.width > 0);
  processBtn.disabled = !hasSource || !hasOp || !roiOk;
}

// ── Dim estimate ─────────────────────────────────────────
function updateDimEstimate() {
  if (!opUpscale.checked) { dimEstimate.textContent = 'Aktifkan Upscale untuk melihat estimasi'; return; }
  const w = mediaWidth();
  const h = mediaHeight();
  if (!w || !h) { dimEstimate.textContent = 'Pilih file untuk melihat estimasi dimensi'; return; }
  const scale = selectedScale;
  if (scale === 1) {
    dimEstimate.textContent = `${w}×${h} → ${w}×${h} (enhance only, resolusi tetap)`;
  } else {
    dimEstimate.textContent = `${w}×${h} → ${w * scale}×${h * scale}`;
  }
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
  const m   = Math.floor(s / 60);
  const sec = Math.floor(s % 60).toString().padStart(2, '0');
  return `${m}:${sec}`;
}

video.addEventListener('loadedmetadata', () => {
  fitCanvas();
  timeTotal.textContent  = formatTime(video.duration);
  seekSlider.max         = video.duration || 100;
  updateDimEstimate();
});
video.addEventListener('timeupdate', () => {
  if (!isSeeking) seekSlider.value = video.currentTime;
  timeCurrent.textContent = formatTime(video.currentTime);
});

let isSeeking = false;
seekSlider.addEventListener('mousedown', () => isSeeking = true);
seekSlider.addEventListener('mouseup',   () => isSeeking = false);
seekSlider.addEventListener('input', () => {
  video.currentTime = seekSlider.value;
  timeCurrent.textContent = formatTime(seekSlider.value);
});

playBtn.addEventListener('click', () => {
  if (!video.src) return;
  if (video.paused) { video.play(); } else { video.pause(); }
});
video.addEventListener('play',  () => { iconPlay.hidden = true;  iconPause.hidden = false; });
video.addEventListener('pause', () => { iconPlay.hidden = false; iconPause.hidden = true; });

muteBtn.addEventListener('click', () => {
  video.muted  = !video.muted;
  iconVol.hidden  =  video.muted;
  iconMute.hidden = !video.muted;
});

// ── CANVAS ROI ────────────────────────────────────────────
function fitCanvas() {
  const el = (mediaType === 'image') ? previewImg : video;
  const w  = el.clientWidth;
  const h  = el.clientHeight;
  if (!w || !h) return;
  overlay.width  = w; overlay.height = h;
  overlay.style.width  = w + 'px';
  overlay.style.height = h + 'px';
  overlay.style.left   = '0';
  overlay.style.top    = '0';
}

function drawRoi(r) {
  fitCanvas();
  const ctx = overlay.getContext('2d');
  ctx.clearRect(0, 0, overlay.width, overlay.height);
  if (!r || !mediaWidth()) return;
  const sx = overlay.width  / mediaWidth();
  const sy = overlay.height / mediaHeight();
  ctx.strokeStyle = '#6366f1'; ctx.lineWidth = 2; ctx.setLineDash([6, 4]);
  ctx.strokeRect(r.x * sx, r.y * sy, r.width * sx, r.height * sy);
  ctx.fillStyle = 'rgba(99,102,241,0.14)';
  ctx.fillRect(r.x * sx, r.y * sy, r.width * sx, r.height * sy);
  ctx.setLineDash([]);
  ctx.fillStyle = '#6366f1';
  ctx.font = '11px Inter, sans-serif';
  ctx.fillText(`${r.width}×${r.height}`, r.x * sx + 4, r.y * sy - 4);
}

window.addEventListener('resize', () => { fitCanvas(); drawRoi(roi); });

overlay.addEventListener('mousedown', e => {
  if (!drawMode || !mediaWidth()) return;
  isDrawing = true;
  const p = mousePos(e);
  startX = p.x; startY = p.y;
  roi = null; drawRoi(null);
});
overlay.addEventListener('mousemove', e => {
  if (!isDrawing) return;
  const p  = mousePos(e);
  const sx = mediaWidth()  / overlay.width;
  const sy = mediaHeight() / overlay.height;
  roi = {
    x:      Math.round(Math.min(p.x, startX) * sx),
    y:      Math.round(Math.min(p.y, startY) * sy),
    width:  Math.round(Math.abs(p.x - startX) * sx),
    height: Math.round(Math.abs(p.y - startY) * sy),
  };
  drawRoi(roi);
});
overlay.addEventListener('mouseup', () => {
  isDrawing = false;
  if (roi && roi.width > 2 && roi.height > 2) {
    roiText.textContent = `x:${roi.x} y:${roi.y} w:${roi.width} h:${roi.height}`;
    roiInfo.hidden = false;
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

// ── PROCESS LOG ──────────────────────────────────────────
function startLogPolling(jobId) {
  _seenLogCount = 0;
  logBody.textContent = '';
  logCard.hidden   = false;
  logSpinner.hidden = false;

  _logPollTimer = setInterval(async () => {
    try {
      const res  = await fetch(`/process-log/${jobId}`);
      const data = await res.json();
      const newLines = data.logs.slice(_seenLogCount);
      newLines.forEach(line => {
        const el = document.createElement('div');
        el.className = 'log-line';
        el.textContent = line;
        logBody.appendChild(el);
      });
      _seenLogCount = data.logs.length;
      if (newLines.length) logBody.scrollTop = logBody.scrollHeight;
      if (data.done) stopLogPolling();
    } catch { /* ignore fetch errors during processing */ }
  }, 400);
}

function stopLogPolling() {
  if (_logPollTimer) { clearInterval(_logPollTimer); _logPollTimer = null; }
  logSpinner.hidden = true;
}

// ── PROCESS ───────────────────────────────────────────────
processBtn.addEventListener('click', doProcess);

async function doProcess() {
  if (mode === 'none') { toast('Pilih file dulu', 'error'); return; }
  const hasOp = opWatermark.checked || opUpscale.checked || opFps.checked;
  if (!hasOp) { toast('Pilih minimal satu operasi', 'error'); return; }
  if (opWatermark.checked && (!roi || roi.width <= 0)) {
    toast('Klik ✏️ Tandai Area lalu gambar kotak pada watermark', 'error'); return;
  }

  const jobId = (crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).slice(2));

  const commonPayload = {
    roi:           opWatermark.checked ? roi : null,
    method:        methodSel.value,
    quality:       qualitySel.value,
    upscale:       opUpscale.checked,
    upscale_model: esrganModel.value,
    upscale_scale: selectedScale,
    fps_boost:     opFps.checked && mediaType === 'video',
    comparison:    opComparison.checked,
    session_id:    sessionId,
    job_id:        jobId,
  };

  processBtn.disabled  = true;
  procProgress.hidden  = false;
  singleResult.hidden  = true;
  bulkResultCard.hidden = true;
  comparisonCard.hidden = true;
  startLogPolling(jobId);

  try {
    if (mode === 'single') {
      procStatus.textContent = 'Mengupload…';
      const upData = await uploadFile(selectedFiles[0]);
      procStatus.textContent = 'Memproses…';

      let res, data;
      if (upData.isImage) {
        res  = await post('/process-image', { filename: upData.filename, ...commonPayload });
      } else {
        res  = await post('/process', { filename: upData.filename, ...commonPayload });
      }
      data = await res.json();
      if (!res.ok) throw new Error(data.error);

      showSingleResult(data);

      if (opComparison.checked) {
        if (upData.isImage && data.originalUrl && data.processedUrl) {
          showImageComparison(data.originalUrl, data.processedUrl);
        } else if (!upData.isImage && data.comparisonFilename) {
          showVideoComparison(data.comparisonFilename);
        } else if (data.comparisonError) {
          toast('Comparison gagal: ' + data.comparisonError, 'error');
        }
      }

      toast('Selesai! File tersimpan.', 'success');

    } else if (mode === 'bulk-files') {
      const uploaded = [];
      for (let i = 0; i < selectedFiles.length; i++) {
        procStatus.textContent = `Mengupload ${i + 1}/${selectedFiles.length}…`;
        const up = await uploadFile(selectedFiles[i]);
        uploaded.push(up);
      }
      procStatus.textContent = `Memproses ${selectedFiles.length} file…`;
      const res  = await post('/process-bulk', { files: uploaded, ...commonPayload });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      showBulkResults(data);
      toast(data.summary, 'success');
    }
  } catch (e) {
    toast(e.message || 'Terjadi kesalahan', 'error');
  } finally {
    stopLogPolling();
    procProgress.hidden = true;
    procStatus.textContent = '';
    processBtn.disabled = false;
    updateProcessBtn();
  }
}

async function uploadFile(file) {
  return new Promise((resolve, reject) => {
    const xhr  = new XMLHttpRequest();
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

// ── Results ───────────────────────────────────────────────
function showSingleResult(data) {
  singleResult.innerHTML = `
    <div class="r-title">
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>
      Berhasil disimpan
    </div>
    <div class="r-fn">${data.outputFilename}</div>
    <div class="r-path">${data.outputPath}</div>
    <button class="btn-open-folder" data-dir="${data.outputDir}">📂 Buka Folder</button>
  `;
  singleResult.querySelector('.btn-open-folder').addEventListener('click', async function () {
    try {
      const res = await post('/open-folder', { path: this.dataset.dir });
      const d   = await res.json();
      if (!res.ok) toast(d.error, 'error');
    } catch { toast('Gagal membuka folder', 'error'); }
  });
  singleResult.hidden = false;
}

function showBulkResults(data) {
  let html = `<div class="bulk-summary">${data.summary}</div>`;
  if (data.outputDir) {
    html += `
      <div class="bulk-dir">📁 ${data.outputDir}</div>
      <button class="btn-open-folder" data-dir="${data.outputDir}" style="margin-bottom:10px">📂 Buka Folder</button>
    `;
  }
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

  const folderBtn = bulkResults.querySelector('.btn-open-folder');
  if (folderBtn) {
    folderBtn.addEventListener('click', async function () {
      try {
        const res = await post('/open-folder', { path: this.dataset.dir });
        const d   = await res.json();
        if (!res.ok) toast(d.error, 'error');
      } catch { toast('Gagal membuka folder', 'error'); }
    });
  }
  bulkResultCard.hidden = false;
}

// ── Comparison ────────────────────────────────────────────
cmpSlider.addEventListener('input', () => {
  const val = cmpSlider.value;
  cmpAfter.style.clipPath = `inset(0 ${100 - val}% 0 0)`;
  cmpDivider.style.left   = val + '%';
});

function showImageComparison(origUrl, processedUrl) {
  cmpOrigImg.src  = origUrl;
  cmpProcImg.src  = processedUrl;
  cmpVideo.hidden = true;

  cmpOrigImg.onload = () => {
    const ratio = cmpOrigImg.naturalHeight / cmpOrigImg.naturalWidth;
    comparisonWrap.style.paddingBottom = (ratio * 100) + '%';
  };

  // Reset slider to 50%
  cmpSlider.value = 50;
  cmpAfter.style.clipPath = 'inset(0 50% 0 0)';
  cmpDivider.style.left   = '50%';

  comparisonWrap.hidden = false;
  comparisonCard.hidden = false;
}

function showVideoComparison(cmpFilename) {
  cmpVideo.src     = '/output/' + cmpFilename;
  cmpVideo.hidden  = false;
  comparisonWrap.hidden = true;
  comparisonCard.hidden = false;
}

// ── Cleanup on tab close ──────────────────────────────────
window.addEventListener('beforeunload', () => {
  navigator.sendBeacon('/cleanup-preview', JSON.stringify({ session_id: sessionId }));
});
