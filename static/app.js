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

const opWatermark     = $('opWatermark');
const opUpscale       = $('opUpscale');
const opFps           = $('opFps');
const opRemoveBg      = $('opRemoveBg');
const methodSel       = $('method');
const qualitySel      = $('quality');
const codecSel        = $('codec');
const codecHint       = $('codecHint');
const rembgModelSel   = $('rembgModel');
const interpEngineSel = $('interpEngine');
const interpHint      = $('interpHint');
const methodHint      = $('methodHint');
const detectorBadge   = $('detectorBadge');
const methodLamaOpt   = $('methodLamaOpt');
const interpRifeOpt   = $('interpRifeOpt');
const fpsSubSettings  = $('fpsSubSettings');
const labelOptInToggle = $('labelOptInToggle');
const labelStats       = $('labelStats');
const wmSubSettings   = $('wmSubSettings');
const esrganOptions   = $('esrganOptions');
const removeBgSettings = $('removeBgSettings');
const opFpsRow        = $('opFpsRow');
const esrganModel     = $('esrganModel');
const esrganWarn      = $('esrganWarn');
const esrganInstall   = $('esrganInstall');
const rembgVideoWarn  = $('rembgVideoWarn');
const rembgInstall    = $('rembgInstall');
const dimEstimate     = $('dimEstimate');
const sharpnessInput   = $('sharpness');
const sharpnessVal     = $('sharpnessVal');
const sharpnessDefault = $('sharpnessDefault');
const autoDetectBtn   = $('autoDetectBtn');

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
let rembgAvailable  = false;
let _logPollTimer = null;
let _seenLogCount = 0;
let currentUploadFilename = null;     // last successfully uploaded filename, for save-label
// Cache uploaded file data to avoid re-uploading when auto-detect already did it
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
  method:        'pref_method',
  upscale_model: 'pref_upscale_model',
  codec:         'pref_codec',
  rembg_model:   'pref_rembg_model',
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
  _setSelectValue(methodSel,       PREF_KEYS.method,        caps.lama   ? 'lama'              : 'ns');
  _setSelectValue(esrganModel,     PREF_KEYS.upscale_model, caps.esrgan ? 'realesrgan-x4plus' : 'lanczos');
  _setSelectValue(rembgModelSel,   PREF_KEYS.rembg_model,   caps.rembg  ? 'birefnet-general'  : 'u2net');
  _setSelectValue(interpEngineSel, PREF_KEYS.interp_engine, caps.rife   ? 'rife'              : 'ffmpeg');
  _setSelectValue(qualitySel,      PREF_KEYS.quality,       'ultra');
  if (sharpnessInput) {
    const stored = localStorage.getItem(PREF_KEYS.sharpness);
    sharpnessInput.value = stored !== null ? stored : '30';
    if (typeof updateSharpnessLabel === 'function') updateSharpnessLabel();
  }
}

function applyCodecDefault(encInfo) {
  _setSelectValue(codecSel, PREF_KEYS.codec, encInfo.hevc_nvenc ? 'hevc' : 'h264');
}

function attachPrefPersistence() {
  const pairs = [
    [methodSel,       PREF_KEYS.method],
    [esrganModel,     PREF_KEYS.upscale_model],
    [codecSel,        PREF_KEYS.codec],
    [rembgModelSel,   PREF_KEYS.rembg_model],
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

// ── Self-improving detector: opt-in label collection ─────────────────────────
function isLabelOptIn() {
  const v = localStorage.getItem('labelOptIn');
  return v === null ? true : v === '1';   // default: opt-in
}

if (labelOptInToggle) {
  labelOptInToggle.checked = isLabelOptIn();
  labelOptInToggle.addEventListener('change', () => {
    localStorage.setItem('labelOptIn', labelOptInToggle.checked ? '1' : '0');
  });
}

async function saveLabel(source) {
  if (!isLabelOptIn()) return;
  if (!currentUploadFilename) return;
  if (!roi || roi.width <= 0 || roi.height <= 0) return;
  try {
    const frameIndex = mediaType === 'video' && video.duration && video.videoWidth
      ? Math.round((video.currentTime || 0) * 30)   // approx 30fps reference
      : null;
    const res = await fetch('/save-label', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        filename: currentUploadFilename,
        roi: { x: roi.x, y: roi.y, width: roi.width, height: roi.height },
        source,
        ...(frameIndex !== null ? { frame_index: frameIndex } : {}),
      }),
    });
    const data = await res.json().catch(() => ({}));
    if (res.ok && data.total !== undefined) {
      updateLabelStats(data.total, data.unique_images);
    }
  } catch { /* silent — labeling is best-effort background work */ }
}

function updateLabelStats(total, unique) {
  if (!labelStats) return;
  if (!total) {
    labelStats.textContent =
      'Setiap ROI yang Anda konfirmasi disimpan lokal sebagai data training. Tidak ada yang dikirim ke cloud.';
    return;
  }
  const NEEDED = 100;
  const remaining = Math.max(0, NEEDED - (unique || 0));
  if (remaining > 0) {
    labelStats.textContent =
      `Anda sudah berkontribusi ${unique} gambar (${total} ROI). ${remaining} lagi sampai dataset training siap.`;
  } else {
    labelStats.textContent =
      `Anda sudah berkontribusi ${unique} gambar (${total} ROI). Cukup untuk training. Jalankan: python scripts/train_watermark_yolo.py`;
  }
}

async function refreshLabelStats() {
  try {
    const res = await fetch('/label-stats');
    const d = await res.json();
    updateLabelStats(d.total || 0, d.unique_images || 0);
  } catch { /* ignore */ }
}
refreshLabelStats();

// ── Unified capabilities probe — populates Setup panel + UI states ──────
let _caps = {};
function populateSetupPanel(caps) {
  const summary = $('setupSummary');
  const setupStatus = $('setupStatus');
  if (!setupStatus) return;
  const all = ['esrgan', 'rembg', 'lama', 'rife', 'yolo'];
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
    _caps = d;
    esrganAvailable = !!d.esrgan;
    rembgAvailable  = !!d.rembg;
    if (esrganInstall) esrganInstall.hidden = esrganAvailable;
    if (rembgInstall)  rembgInstall.hidden  = rembgAvailable;
    if (methodLamaOpt && !d.lama) methodLamaOpt.disabled = true;
    if (methodHint) methodHint.textContent = d.lama ? '✓ LaMa AI tersedia' : '⚠ LaMa belum aktif — pakai Telea/NS';
    if (interpRifeOpt && !d.rife) interpRifeOpt.disabled = true;
    if (interpHint) interpHint.textContent = d.rife ? '✓ RIFE aktif' : '⚠ RIFE belum aktif — pakai FFmpeg';
    if (detectorBadge) {
      detectorBadge.textContent = d.yolo ? '🤖 YOLO' : '⚙ heuristic';
      detectorBadge.title = d.yolo ? 'Auto-detect pakai YOLO model' : 'Auto-detect pakai heuristic OpenCV';
    }
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
  roi           = null;
  currentUploadFilename = null;
  _uploadCache.clear();
  drawRoi(null);
  roiInfo.hidden       = true;
  singleResult.hidden  = true;
  bulkResultCard.hidden = true;

  const firstFile = selectedFiles[0];
  mediaType = firstFile ? (isImage(firstFile.name) ? 'image' : 'video') : 'none';

  opFpsRow.hidden = (mediaType === 'image');
  if (mediaType === 'image' && opFps.checked) opFps.checked = false;

  // Update rembg video warning
  rembgVideoWarn.hidden = !(opRemoveBg.checked && mediaType === 'video');

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

  autoDetectBtn.disabled = (mode === 'none');

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

  roi = null; drawRoi(null); roiInfo.hidden = true;
  drawModeBtn.disabled  = true;
  autoDetectBtn.disabled = true;
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
  video.src         = ''; video.hidden = true;
  customControls.hidden = true;
  vpPlaceholder.style.display = 'none';
  drawModeBtn.disabled = false;
  previewImg.onload = () => { fitCanvas(); updateDimEstimate(); };
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

opRemoveBg.addEventListener('change', () => {
  removeBgSettings.hidden = !opRemoveBg.checked;
  rembgVideoWarn.hidden   = !(opRemoveBg.checked && mediaType === 'video');
  rembgInstall.hidden     = rembgAvailable || !opRemoveBg.checked;
  updateProcessBtn();
});

opUpscale.addEventListener('change', () => {
  esrganOptions.hidden = !opUpscale.checked;
  if (opUpscale.checked) {
    // Force thumb re-render when panel first becomes visible
    sharpnessInput.value = sharpnessInput.value;
    updateSharpnessLabel();
  }
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
  const hasOp     = opWatermark.checked || opUpscale.checked || opFps.checked || opRemoveBg.checked;
  const roiOk     = !opWatermark.checked || (roi && roi.width > 0);
  processBtn.disabled = !hasSource || !hasOp || !roiOk;
}

// ── AUTO DETECT WATERMARK ────────────────────────────────
autoDetectBtn.addEventListener('click', async () => {
  if (mode === 'none' || !selectedFiles.length) return;

  autoDetectBtn.disabled  = true;
  autoDetectBtn.textContent = '🔍 Mendeteksi…';

  try {
    // Upload first file (cached so processing won't re-upload)
    const upData = await uploadFileOnce(selectedFiles[0]);
    currentUploadFilename = upData.filename;
    const res    = await post('/detect-watermark', { filename: upData.filename });
    const data   = await res.json();

    if (!res.ok) throw new Error(data.error || 'Deteksi gagal');

    if (data.roi) {
      roi = data.roi;
      drawRoi(roi);
      roiText.textContent = `x:${roi.x} y:${roi.y} w:${roi.width} h:${roi.height}`;
      roiInfo.hidden = false;
      updateProcessBtn();
      saveLabel('auto');                                // collect training sample
      toast('Watermark terdeteksi! Koreksi manual jika perlu.', 'success', 4000);
    } else {
      toast(data.message || 'Watermark tidak terdeteksi — tandai manual.', 'info', 4000);
    }
  } catch (e) {
    toast('Deteksi gagal: ' + (e.message || 'Error tidak diketahui'), 'error');
  } finally {
    autoDetectBtn.disabled  = false;
    autoDetectBtn.textContent = '🔍 Auto Deteksi';
  }
});

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
overlay.addEventListener('mouseup', async () => {
  isDrawing = false;
  if (roi && roi.width > 2 && roi.height > 2) {
    roiText.textContent = `x:${roi.x} y:${roi.y} w:${roi.width} h:${roi.height}`;
    roiInfo.hidden = false;
    drawMode = false;
    overlay.classList.remove('draw-active');
    drawModeBtn.classList.remove('active');
    drawModeBtn.textContent = '✏️ Tandai Area';
    drawNotice.hidden = true;
    // Ensure we have a filename to associate the manual ROI with
    if (!currentUploadFilename && selectedFiles.length) {
      try {
        const up = await uploadFileOnce(selectedFiles[0]);
        currentUploadFilename = up.filename;
      } catch { /* labeling is best-effort */ }
    }
    saveLabel('manual');                              // collect training sample
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
  const hasOp = opWatermark.checked || opUpscale.checked || opFps.checked || opRemoveBg.checked;
  if (!hasOp) { toast('Pilih minimal satu operasi', 'error'); return; }
  if (opWatermark.checked && (!roi || roi.width <= 0)) {
    toast('Klik ✏️ Tandai Area atau 🔍 Auto Deteksi untuk menentukan area watermark', 'error'); return;
  }

  const jobId    = (crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).slice(2));
  const sharpness = parseFloat(sharpnessInput.value) / 100;

  const commonPayload = {
    roi:           opWatermark.checked ? roi : null,
    method:        methodSel.value,
    quality:       qualitySel.value,
    codec:         codecSel ? codecSel.value : 'h264',
    upscale:       opUpscale.checked,
    upscale_model: esrganModel.value,
    upscale_scale: selectedScale,
    fps_boost:     opFps.checked && mediaType === 'video',
    interp_engine: interpEngineSel ? interpEngineSel.value : 'ffmpeg',
    remove_bg:     opRemoveBg.checked,
    rembg_model:   rembgModelSel ? rembgModelSel.value : 'u2net',
    sharpness,
    job_id:        jobId,
  };

  processBtn.disabled   = true;
  autoDetectBtn.disabled = true;
  procProgress.hidden   = false;
  singleResult.hidden   = true;
  bulkResultCard.hidden  = true;
  startLogPolling(jobId);

  try {
    if (mode === 'single') {
      procStatus.textContent = 'Mengupload…';
      // Reuse cached upload if auto-detect already uploaded this file
      const upData = await uploadFileOnce(selectedFiles[0]);
      currentUploadFilename = upData.filename;
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
    autoDetectBtn.disabled = (mode === 'none');
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
