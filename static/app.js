// ── Helpers ──────────────────────────────────────────────
const $ = id => document.getElementById(id);
const VIDEO_EXTS = ['mp4','mov','m4v','webm','avi','mkv'];
const IMAGE_EXTS = ['jpg','jpeg','png','webp','tiff','bmp'];
const isVideo = name => VIDEO_EXTS.includes(name.split('.').pop().toLowerCase());
const isImage = name => IMAGE_EXTS.includes(name.split('.').pop().toLowerCase());
const isMedia = name => isVideo(name) || isImage(name);

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

const opUpscale       = $('opUpscale');
const opFps           = $('opFps');
const qualitySel      = $('quality');
const codecSel        = $('codec');
const codecHint       = $('codecHint');
const interpEngineSel = $('interpEngine');
const interpHint      = $('interpHint');
const interpRifeOpt   = $('interpRifeOpt');
const fpsSubSettings  = $('fpsSubSettings');
const esrganOptions   = $('esrganOptions');
const opFpsRow        = $('opFpsRow');
const esrganModel     = $('esrganModel');
const esrganWarn      = $('esrganWarn');
const esrganInstall   = $('esrganInstall');
const dimEstimate     = $('dimEstimate');
const sharpnessInput   = $('sharpness');
const sharpnessVal     = $('sharpnessVal');
const sharpnessDefault = $('sharpnessDefault');

const SHARPNESS_DEFAULT = 30;

const processBtn      = $('processBtn');
const processBtnLabel = $('processBtnLabel');
const procProgress    = $('procProgress');
const procStatus      = $('procStatus');
const singleResult    = $('singleResult');
const bulkResultCard  = $('bulkResultCard');
const bulkResults     = $('bulkResults');

const video           = $('video');
const previewImg      = $('previewImg');
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

const logCard    = $('logCard');
const logBody    = $('logBody');
const logSpinner = $('logSpinner');

const toasts = $('toasts');

// ── State ────────────────────────────────────────────────
let mode          = 'none';   // 'none' | 'single' | 'bulk-files'
let mediaType     = 'none';   // 'none' | 'video' | 'image'
let selectedFiles = [];
let selectedScale = 2;
let esrganAvailable = false;
let _logPollTimer = null;
let _seenLogCount = 0;
// Cache uploaded file data to avoid re-uploading the same file twice
const _uploadCache = new Map();

function _uploadCacheKey(file) {
  return `${file.name}|${file.size}|${file.lastModified}`;
}

async function uploadFileOnce(file) {
  const key = _uploadCacheKey(file);
  if (_uploadCache.has(key)) return _uploadCache.get(key);
  const data = await uploadFile(file);
  _uploadCache.set(key, data);
  return data;
}

// ── Toast ───────────────────────────────────────────────
function toast(msg, type = 'info', ms = 3200) {
  const t = document.createElement('div');
  t.className = `toast ${type}`; t.textContent = msg;
  toasts.appendChild(t);
  setTimeout(() => t.remove(), ms);
}

// ── Heartbeat — keep server alive; server shuts down when pings stop ─────────
setInterval(() => fetch('/heartbeat', { method: 'POST' }).catch(() => {}), 5000);

// ── Smart defaults: best-available with localStorage persistence ─────────────
const PREF_KEYS = {
  upscale_model: 'pref_upscale_model',
  codec:         'pref_codec',
  interp_engine: 'pref_interp_engine',
  quality:       'pref_quality',
  sharpness:     'pref_sharpness',
};

function _setSelectValue(el, prefKey, bestDefault) {
  if (!el) return;
  const stored = localStorage.getItem(prefKey);
  const candidates = [stored, bestDefault].filter(v => v !== null && v !== undefined);
  for (const val of candidates) {
    const opt = el.querySelector(`option[value="${val}"]`);
    if (opt && !opt.disabled) {
      el.value = val;
      return;
    }
  }
  const first = el.querySelector('option:not([disabled])');
  if (first) el.value = first.value;
}

function applyCapabilityDefaults(caps) {
  _setSelectValue(esrganModel,     PREF_KEYS.upscale_model, caps.esrgan ? 'realesrgan-x4plus' : 'lanczos');
  _setSelectValue(interpEngineSel, PREF_KEYS.interp_engine, caps.rife   ? 'rife'              : 'ffmpeg');
  _setSelectValue(qualitySel,      PREF_KEYS.quality,       'ultra');
  if (sharpnessInput) {
    const stored = localStorage.getItem(PREF_KEYS.sharpness);
    sharpnessInput.value = stored !== null ? stored : '30';
    updateSharpnessLabel();
  }
}

function applyCodecDefault(encInfo) {
  _setSelectValue(codecSel, PREF_KEYS.codec, encInfo.hevc_nvenc ? 'hevc' : 'h264');
}

function attachPrefPersistence() {
  const pairs = [
    [esrganModel,     PREF_KEYS.upscale_model],
    [codecSel,        PREF_KEYS.codec],
    [interpEngineSel, PREF_KEYS.interp_engine],
    [qualitySel,      PREF_KEYS.quality],
  ];
  for (const [el, key] of pairs) {
    if (!el) continue;
    el.addEventListener('change', () => localStorage.setItem(key, el.value));
  }
  if (sharpnessInput) {
    sharpnessInput.addEventListener('change',
      () => localStorage.setItem(PREF_KEYS.sharpness, sharpnessInput.value));
  }
}
attachPrefPersistence();

// ── Unified capabilities probe — populates Setup panel + UI states ──────
function populateSetupPanel(caps) {
  const summary = $('setupSummary');
  const setupStatus = $('setupStatus');
  if (!setupStatus) return;
  const all = ['esrgan', 'rife'];
  const ready = all.filter(k => caps[k]).length;
  if (summary) {
    summary.textContent = ready === all.length
      ? `✓ semua fitur AI aktif`
      : `${ready}/${all.length} fitur AI aktif — klik untuk lihat`;
  }
  setupStatus.querySelectorAll('.cap-row[data-cap]').forEach(row => {
    const cap = row.dataset.cap;
    if (cap === 'encoder') return;
    const dot = row.querySelector('[data-status]');
    const cmd = row.querySelector('.cap-cmd');
    const ok = !!caps[cap];
    if (dot) {
      dot.textContent = ok ? '✓' : '✗';
      dot.className = 'cap-status ' + (ok ? 'ok' : 'off');
    }
    if (cmd) {
      cmd.hidden = ok;
      if (!ok) cmd.textContent = '📋 ' + cmd.dataset.cmd;
    }
  });
}

document.querySelectorAll('.cap-cmd').forEach(btn => {
  btn.addEventListener('click', async () => {
    const cmd = btn.dataset.cmd || '';
    try {
      await navigator.clipboard.writeText(cmd);
      const orig = btn.textContent;
      btn.textContent = '✓ disalin ke clipboard';
      setTimeout(() => { btn.textContent = orig; }, 1500);
    } catch {
      toast('Tidak bisa akses clipboard — salin manual', 'error');
    }
  });
});

fetch('/capabilities')
  .then(r => r.json())
  .then(d => {
    esrganAvailable = !!d.esrgan;
    if (esrganInstall) esrganInstall.hidden = esrganAvailable;
    if (interpRifeOpt && !d.rife) interpRifeOpt.disabled = true;
    if (interpHint) interpHint.textContent = d.rife ? '✓ RIFE aktif' : '⚠ RIFE belum aktif — pakai FFmpeg';
    populateSetupPanel(d);
    applyCapabilityDefaults(d);
  })
  .catch(() => applyCapabilityDefaults({}));

// ── Encoder probe — show NVENC availability under codec selector + Setup panel
fetch('/encoder-info')
  .then(r => r.json())
  .then(d => {
    const parts = [];
    if (d.gpu) parts.push(`GPU ${d.vram_gb}GB`);
    const enc = [];
    if (d.h264_nvenc) enc.push('H.264 NVENC');
    if (d.hevc_nvenc) enc.push('HEVC NVENC');
    if (d.av1_nvenc)  enc.push('AV1 NVENC');
    if (enc.length) parts.push(enc.join(' · '));
    else parts.push('encoder CPU saja');
    const txt = parts.join(' · ');
    if (codecHint) codecHint.textContent = txt;
    const encoderDetail = $('encoderDetail');
    if (encoderDetail) encoderDetail.textContent = txt;
    applyCodecDefault(d);
  })
  .catch(() => {
    if (codecHint) codecHint.textContent = '';
    const encoderDetail = $('encoderDetail');
    if (encoderDetail) encoderDetail.textContent = '—';
    applyCodecDefault({});
  });

// ── DROP ZONE ────────────────────────────────────────────
['dragenter','dragover'].forEach(ev => dropzone.addEventListener(ev, e => {
  e.preventDefault(); e.stopPropagation(); dropzone.classList.add('dragover');
}));
['dragleave','drop'].forEach(ev => dropzone.addEventListener(ev, e => {
  e.preventDefault(); e.stopPropagation(); dropzone.classList.remove('dragover');
}));
// Enumerate all files inside a dropped directory entry (FileSystem API)
async function readDirAllFiles(dirEntry) {
  const files = [];
  const reader = dirEntry.createReader();
  const allEntries = await new Promise(resolve => {
    const results = [];
    const read = () => reader.readEntries(entries => {
      if (!entries.length) { resolve(results); return; }
      results.push(...entries);
      read(); // may return up to 100 per call; keep reading
    });
    read();
  });
  for (const entry of allEntries) {
    if (entry.isFile) {
      const file = await new Promise(res => entry.file(res));
      files.push(file);
    } else if (entry.isDirectory) {
      const sub = await readDirAllFiles(entry);
      files.push(...sub);
    }
  }
  return files;
}

dropzone.addEventListener('drop', async e => {
  const items = e.dataTransfer.items;
  if (!items) return;
  const entry = items[0]?.webkitGetAsEntry?.();
  if (entry && entry.isDirectory) {
    // Use FileSystem API — e.dataTransfer.files is empty for dropped folders
    const all = await readDirAllFiles(entry);
    const files = all.filter(f => isMedia(f.name));
    if (!files.length) { toast('Tidak ada file yang didukung di folder tersebut', 'error'); return; }
    setSource('bulk-files', files);
  } else {
    const files = Array.from(e.dataTransfer.files).filter(f => isMedia(f.name));
    if (!files.length) { toast('Format file tidak didukung', 'error'); return; }
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
  _uploadCache.clear();
  singleResult.hidden  = true;
  bulkResultCard.hidden = true;

  const firstFile = selectedFiles[0];
  mediaType = firstFile ? (isImage(firstFile.name) ? 'image' : 'video') : 'none';

  opFpsRow.hidden = (mediaType === 'image');
  if (mediaType === 'image' && opFps.checked) opFps.checked = false;

  if (mode === 'single') {
    showSourceInfo(mediaType === 'image' ? '🖼️' : '🎬', firstFile.name, formatSize(firstFile.size));
    modeBadge.textContent = 'Single File';
    modeBadge.className   = 'header-badge';
    processBtnLabel.textContent = 'Proses File';
    if (mediaType === 'image') loadImageBlob(firstFile);
    else loadVideoBlob(firstFile);
  } else if (mode === 'bulk-files') {
    showSourceInfo('🗂️', `${selectedFiles.length} file dipilih`, `Referensi: ${firstFile.name}`);
    modeBadge.textContent = `Bulk · ${selectedFiles.length} file`;
    modeBadge.className   = 'header-badge bulk';
    processBtnLabel.textContent = `Proses ${selectedFiles.length} File`;
    if (mediaType === 'image') loadImageBlob(firstFile);
    else loadVideoBlob(firstFile);
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

  video.src    = ''; video.hidden = true;
  customControls.hidden = true;
  previewImg.src    = ''; previewImg.hidden = true;
  vpPlaceholder.style.display = '';

  singleResult.hidden   = true;
  bulkResultCard.hidden = true;
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
  video.src         = ''; video.hidden = true;
  customControls.hidden = true;
  vpPlaceholder.style.display = 'none';
  previewImg.onload = () => updateDimEstimate();
}

function formatSize(bytes) {
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(0) + ' KB';
  return (bytes / 1024 / 1024).toFixed(1) + ' MB';
}

// ── Media dimensions helpers ─────────────────────────────
function mediaWidth()  { return mediaType === 'image' ? previewImg.naturalWidth  : video.videoWidth;  }
function mediaHeight() { return mediaType === 'image' ? previewImg.naturalHeight : video.videoHeight; }

// ── OPERATIONS ───────────────────────────────────────────
opUpscale.addEventListener('change', () => {
  esrganOptions.hidden = !opUpscale.checked;
  if (opUpscale.checked) updateSharpnessLabel();
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

// Sharpness slider
function updateSharpnessLabel() {
  const v = parseInt(sharpnessInput.value, 10);
  sharpnessVal.textContent = v;
  sharpnessDefault.hidden  = (v !== SHARPNESS_DEFAULT);
}
sharpnessInput.addEventListener('input', updateSharpnessLabel);

// Force correct thumb position — range inputs in hidden divs don't render until visible
sharpnessInput.value = SHARPNESS_DEFAULT;
updateSharpnessLabel();

opFps.addEventListener('change', () => {
  if (fpsSubSettings) fpsSubSettings.hidden = !opFps.checked;
  updateProcessBtn();
});

function updateProcessBtn() {
  const hasSource = mode !== 'none';
  const hasOp     = opUpscale.checked || opFps.checked;
  processBtn.disabled = !hasSource || !hasOp;
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

// ── VIDEO CONTROLS ───────────────────────────────────────
function formatTime(s) {
  if (!s || isNaN(s)) return '0:00';
  const m   = Math.floor(s / 60);
  const sec = Math.floor(s % 60).toString().padStart(2, '0');
  return `${m}:${sec}`;
}

video.addEventListener('loadedmetadata', () => {
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
  const hasOp = opUpscale.checked || opFps.checked;
  if (!hasOp) { toast('Pilih minimal satu operasi', 'error'); return; }

  const jobId    = (crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).slice(2));
  const sharpness = parseFloat(sharpnessInput.value) / 100;

  const commonPayload = {
    quality:       qualitySel.value,
    codec:         codecSel ? codecSel.value : 'h264',
    upscale:       opUpscale.checked,
    upscale_model: esrganModel.value,
    upscale_scale: selectedScale,
    fps_boost:     opFps.checked && mediaType === 'video',
    interp_engine: interpEngineSel ? interpEngineSel.value : 'ffmpeg',
    sharpness,
    job_id:        jobId,
  };

  processBtn.disabled   = true;
  procProgress.hidden   = false;
  singleResult.hidden   = true;
  bulkResultCard.hidden  = true;
  startLogPolling(jobId);

  try {
    if (mode === 'single') {
      procStatus.textContent = 'Mengupload…';
      const upData = await uploadFileOnce(selectedFiles[0]);
      procStatus.textContent = 'Memproses…';

      let res;
      if (upData.isImage) {
        res = await post('/process-image', { filename: upData.filename, ...commonPayload });
      } else {
        res = await post('/process', { filename: upData.filename, ...commonPayload });
      }
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      showSingleResult(data);
      toast('Selesai! File tersimpan.', 'success');

    } else if (mode === 'bulk-files') {
      const uploaded = [];
      for (let i = 0; i < selectedFiles.length; i++) {
        procStatus.textContent = `Mengupload ${i + 1}/${selectedFiles.length}…`;
        const up = await uploadFileOnce(selectedFiles[i]);
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
    procProgress.hidden    = true;
    procStatus.textContent = '';
    processBtn.disabled    = false;
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
