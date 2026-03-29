const $ = id => document.getElementById(id);

// ── Header tabs ──
const tabSingle = $('tabSingle'), tabBulk = $('tabBulk');
const singleMode = $('singleMode'), bulkMode = $('bulkMode');

// ── Single: Upload ──
const dropzone = $('dropzone'), browseBtn = $('browseBtn'), fileInput = $('fileInput');
const uploadBtn = $('uploadBtn'), uploadProgress = $('uploadProgress');
const uploadBar = $('uploadBar'), uploadPct = $('uploadPct');
const fileChip = $('fileChip'), fileChipName = $('fileChipName');

// ── Single: Ops ──
const opWatermark = $('opWatermark'), opUpscale = $('opUpscale'), opFps = $('opFps');
const methodSel = $('method'), qualitySel = $('quality');

// ── Single: ROI ──
const video = $('video'), overlay = $('overlay');
const vpPlaceholder = $('vpPlaceholder');
const roiInfo = $('roiInfo'), roiText = $('roiText');
const drawModeBtn = $('drawModeBtn'), drawNotice = $('drawNotice');
const clearRoi = $('clearRoi'), clearRoiSmall = $('clearRoiSmall');

// ── Single: Process ──
const processBtn = $('processBtn'), procProgress = $('procProgress'), singleResult = $('singleResult');

// ── Bulk: Source ──
const srcTabFolder = $('srcTabFolder'), srcTabFiles = $('srcTabFiles');
const srcFolderPanel = $('srcFolderPanel'), srcFilesPanel = $('srcFilesPanel');
const folderPath = $('folderPath'), scanBtn = $('scanBtn'), scanResult = $('scanResult');
const bulkDropzone = $('bulkDropzone'), bulkBrowseBtn = $('bulkBrowseBtn'), bulkFileInput = $('bulkFileInput');
const bulkFileList = $('bulkFileList');

// ── Bulk: Watermark ROI ──
const bOpWatermark = $('bOpWatermark'), bOpUpscale = $('bOpUpscale'), bOpFps = $('bOpFps');
const bulkRoiCard = $('bulkRoiCard');
const bRefBrowseBtn = $('bRefBrowseBtn'), bRefFileInput = $('bRefFileInput'), bRefStatus = $('bRefStatus');
const bRefVideo = $('bRefVideo'), bOverlay = $('bOverlay'), bVideoWrap = $('bVideoWrap');
const bDrawModeBtn = $('bDrawModeBtn'), bDrawNotice = $('bDrawNotice');
const bClearRoi = $('bClearRoi'), bClearRoiSmall = $('bClearRoiSmall');
const bRoiInfo = $('bRoiInfo'), bRoiText = $('bRoiText');

// ── Bulk: Process ──
const bMethodSel = $('bMethod'), bQualitySel = $('bQuality');
const bulkBtn = $('bulkBtn'), bulkProgress = $('bulkProgress'), bulkResults = $('bulkResults');

const toasts = $('toasts');

// ── State ──
let uploadedFilename = null;
let roi = null;
let drawMode = false;
let isDrawing = false, startX = 0, startY = 0;

let bulkRoi = null;
let bDrawMode = false;
let bIsDrawing = false, bStartX = 0, bStartY = 0;
let bulkRefFilename = null;

let bulkSrcMode = 'folder'; // 'folder' | 'files'
let bulkFiles = []; // FileList items for files mode

// ────────────────────────────────────────────
// TOAST
// ────────────────────────────────────────────
function toast(msg, type = 'info', ms = 3000) {
  const t = document.createElement('div');
  t.className = `toast ${type}`;
  t.textContent = msg;
  toasts.appendChild(t);
  setTimeout(() => t.remove(), ms);
}

// ────────────────────────────────────────────
// HEADER TABS
// ────────────────────────────────────────────
tabSingle.addEventListener('click', () => {
  tabSingle.classList.add('active'); tabBulk.classList.remove('active');
  singleMode.hidden = false; bulkMode.hidden = true;
});
tabBulk.addEventListener('click', () => {
  tabBulk.classList.add('active'); tabSingle.classList.remove('active');
  bulkMode.hidden = false; singleMode.hidden = true;
});

// ────────────────────────────────────────────
// SINGLE — UPLOAD
// ────────────────────────────────────────────
['dragenter', 'dragover'].forEach(ev => dropzone.addEventListener(ev, e => {
  e.preventDefault(); e.stopPropagation(); dropzone.classList.add('dragover');
}));
['dragleave', 'drop'].forEach(ev => dropzone.addEventListener(ev, e => {
  e.preventDefault(); e.stopPropagation(); dropzone.classList.remove('dragover');
}));
dropzone.addEventListener('drop', e => { const f = e.dataTransfer.files[0]; if (f) setFile(f); });
browseBtn.addEventListener('click', () => fileInput.click());
fileInput.addEventListener('change', () => { if (fileInput.files[0]) setFile(fileInput.files[0]); });

function setFile(f) {
  fileChipName.textContent = f.name;
  fileChip.hidden = false;
  uploadBtn.disabled = false;
}

uploadBtn.addEventListener('click', async () => {
  const f = fileInput.files?.[0];
  if (!f) { toast('Pilih file video dulu', 'error'); return; }
  uploadProgress.hidden = false;
  uploadBar.style.width = '0%'; uploadPct.textContent = '0%';
  uploadBtn.disabled = true;

  const form = new FormData();
  form.append('video', f);
  try {
    const data = await uploadWithProgress('/upload', form, pct => {
      uploadBar.style.width = pct + '%'; uploadPct.textContent = pct + '%';
    });
    uploadedFilename = data.filename;
    video.src = data.videoUrl;
    vpPlaceholder.style.display = 'none';
    drawModeBtn.disabled = false;
    updateProcessBtn();
    toast('Upload berhasil!', 'success');
  } catch (e) {
    toast(e.message || 'Upload gagal', 'error');
  } finally {
    uploadBtn.disabled = false;
    setTimeout(() => { uploadProgress.hidden = true; }, 800);
  }
});

function uploadWithProgress(url, form, onProgress) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('POST', url);
    xhr.upload.onprogress = e => {
      if (e.lengthComputable) onProgress(Math.round((e.loaded / e.total) * 100));
    };
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

// ────────────────────────────────────────────
// SINGLE — DRAW MODE TOGGLE
// ────────────────────────────────────────────
drawModeBtn.addEventListener('click', () => {
  drawMode = !drawMode;
  overlay.classList.toggle('draw-active', drawMode);
  drawModeBtn.classList.toggle('active', drawMode);
  drawModeBtn.textContent = drawMode ? '⏹ Selesai Tandai' : '✏️ Tandai Area';
  drawNotice.hidden = !drawMode;
});

// ────────────────────────────────────────────
// SINGLE — CANVAS ROI
// ────────────────────────────────────────────
function fitCanvas(vid, cvs) {
  const w = vid.clientWidth, h = vid.clientHeight;
  if (!w || !h) return;
  cvs.width = w; cvs.height = h;
  cvs.style.width = w + 'px'; cvs.style.height = h + 'px';
  cvs.style.left = '0'; cvs.style.top = '0';
}

function drawRoi(cvs, r) {
  const ctx = cvs.getContext('2d');
  ctx.clearRect(0, 0, cvs.width, cvs.height);
  if (!r) return;
  const vid = cvs === overlay ? video : bRefVideo;
  const sx = cvs.width / vid.videoWidth;
  const sy = cvs.height / vid.videoHeight;
  ctx.strokeStyle = '#6366f1';
  ctx.lineWidth = 2;
  ctx.setLineDash([6, 4]);
  ctx.strokeRect(r.x * sx, r.y * sy, r.width * sx, r.height * sy);
  ctx.fillStyle = 'rgba(99,102,241,0.13)';
  ctx.fillRect(r.x * sx, r.y * sy, r.width * sx, r.height * sy);
}

window.addEventListener('resize', () => {
  fitCanvas(video, overlay); drawRoi(overlay, roi);
  if (!bRefVideo.paused || bRefVideo.src) { fitCanvas(bRefVideo, bOverlay); drawRoi(bOverlay, bulkRoi); }
});

video.addEventListener('loadedmetadata', () => { fitCanvas(video, overlay); });
bRefVideo.addEventListener('loadedmetadata', () => { fitCanvas(bRefVideo, bOverlay); });

// Single ROI drawing
overlay.addEventListener('mousedown', e => {
  if (!drawMode || !video.videoWidth) return;
  isDrawing = true;
  const p = pos(e, overlay);
  startX = p.x; startY = p.y;
  roi = null; drawRoi(overlay, null);
});
overlay.addEventListener('mousemove', e => {
  if (!isDrawing) return;
  const p = pos(e, overlay);
  const sx = video.videoWidth / overlay.width;
  const sy = video.videoHeight / overlay.height;
  const x = Math.min(p.x, startX), y = Math.min(p.y, startY);
  roi = {
    x: Math.round(x * sx), y: Math.round(y * sy),
    width: Math.round(Math.abs(p.x - startX) * sx),
    height: Math.round(Math.abs(p.y - startY) * sy),
  };
  drawRoi(overlay, roi);
});
overlay.addEventListener('mouseup', () => {
  isDrawing = false;
  if (roi && roi.width > 0 && roi.height > 0) {
    roiText.textContent = `x:${roi.x} y:${roi.y} w:${roi.width} h:${roi.height}`;
    roiInfo.hidden = false;
    // Auto exit draw mode
    drawMode = false;
    overlay.classList.remove('draw-active');
    drawModeBtn.classList.remove('active');
    drawModeBtn.textContent = '✏️ Tandai Area';
    drawNotice.hidden = true;
  }
  updateProcessBtn();
});

function clearRoiFn() {
  roi = null; drawRoi(overlay, null); roiInfo.hidden = true; updateProcessBtn();
}
clearRoi.addEventListener('click', clearRoiFn);
clearRoiSmall.addEventListener('click', clearRoiFn);

function pos(e, cvs) {
  const r = cvs.getBoundingClientRect();
  return { x: e.clientX - r.left, y: e.clientY - r.top };
}

// ────────────────────────────────────────────
// SINGLE — OPERATIONS & PROCESS
// ────────────────────────────────────────────
[opWatermark, opUpscale, opFps].forEach(el => el.addEventListener('change', updateProcessBtn));

function updateProcessBtn() {
  const hasOp = opWatermark.checked || opUpscale.checked || opFps.checked;
  const hasFile = !!uploadedFilename;
  const roiOk = !opWatermark.checked || (roi && roi.width > 0);
  processBtn.disabled = !hasFile || !hasOp || !roiOk;
}

processBtn.addEventListener('click', async () => {
  if (!uploadedFilename) { toast('Upload video dulu', 'error'); return; }
  if (opWatermark.checked && (!roi || roi.width <= 0)) { toast('Tandai area watermark dulu', 'error'); return; }

  processBtn.disabled = true;
  procProgress.hidden = false;
  singleResult.hidden = true;

  try {
    const res = await fetch('/process', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        filename: uploadedFilename,
        roi: opWatermark.checked ? roi : null,
        method: methodSel.value,
        quality: qualitySel.value,
        upscale: opUpscale.checked,
        fps_boost: opFps.checked,
      }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Gagal');
    showSingleResult(data);
    toast('Selesai! File tersimpan otomatis.', 'success');
  } catch (e) {
    toast(e.message || 'Terjadi kesalahan', 'error');
  } finally {
    procProgress.hidden = true;
    processBtn.disabled = false;
  }
});

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

// ────────────────────────────────────────────
// BULK — SOURCE SUB-TABS
// ────────────────────────────────────────────
srcTabFolder.addEventListener('click', () => {
  bulkSrcMode = 'folder';
  srcTabFolder.classList.add('active'); srcTabFiles.classList.remove('active');
  srcFolderPanel.hidden = false; srcFilesPanel.hidden = true;
  updateBulkBtn();
});
srcTabFiles.addEventListener('click', () => {
  bulkSrcMode = 'files';
  srcTabFiles.classList.add('active'); srcTabFolder.classList.remove('active');
  srcFilesPanel.hidden = false; srcFolderPanel.hidden = true;
  updateBulkBtn();
});

// ────────────────────────────────────────────
// BULK — FOLDER SCAN
// ────────────────────────────────────────────
scanBtn.addEventListener('click', async () => {
  const fp = folderPath.value.trim();
  if (!fp) { toast('Masukkan path folder', 'error'); return; }
  scanResult.textContent = 'Scanning…'; scanResult.className = 'scan-result';
  try {
    const res = await fetch('/scan-folder', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ folder_path: fp }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error);
    scanResult.textContent = `✓ ${data.count} video ditemukan`;
    scanResult.className = 'scan-result ok';
    updateBulkBtn();
    toast(`${data.count} video ditemukan`, 'success');
  } catch (e) {
    scanResult.textContent = '✗ ' + (e.message || 'Folder tidak valid');
    scanResult.className = 'scan-result err';
    updateBulkBtn();
  }
});
folderPath.addEventListener('keydown', e => { if (e.key === 'Enter') scanBtn.click(); });

// ────────────────────────────────────────────
// BULK — FILE PICKER (multiple)
// ────────────────────────────────────────────
['dragenter', 'dragover'].forEach(ev => bulkDropzone.addEventListener(ev, e => {
  e.preventDefault(); e.stopPropagation(); bulkDropzone.classList.add('dragover');
}));
['dragleave', 'drop'].forEach(ev => bulkDropzone.addEventListener(ev, e => {
  e.preventDefault(); e.stopPropagation(); bulkDropzone.classList.remove('dragover');
}));
bulkDropzone.addEventListener('drop', e => { addBulkFiles(e.dataTransfer.files); });
bulkBrowseBtn.addEventListener('click', () => bulkFileInput.click());
bulkFileInput.addEventListener('change', () => { if (bulkFileInput.files.length) addBulkFiles(bulkFileInput.files); });

function addBulkFiles(files) {
  const ALLOWED = ['video/mp4', 'video/quicktime', 'video/webm', 'video/x-matroska', 'video/x-msvideo', '.mkv', '.avi'];
  for (const f of files) {
    const ext = f.name.split('.').pop().toLowerCase();
    if (!['mp4','mov','webm','mkv','avi','m4v'].includes(ext)) continue;
    if (!bulkFiles.find(b => b.name === f.name && b.size === f.size)) {
      bulkFiles.push(f);
    }
  }
  renderBulkFileList();
  updateBulkBtn();
}

function renderBulkFileList() {
  if (!bulkFiles.length) { bulkFileList.innerHTML = ''; return; }
  bulkFileList.innerHTML = bulkFiles.map((f, i) => `
    <div class="bulk-file-item">
      <span>${f.name}</span>
      <button class="remove-btn" onclick="removeBulkFile(${i})">×</button>
    </div>
  `).join('');
}

window.removeBulkFile = function(i) {
  bulkFiles.splice(i, 1);
  renderBulkFileList();
  updateBulkBtn();
};

// ────────────────────────────────────────────
// BULK — WATERMARK ROI (reference video)
// ────────────────────────────────────────────
bOpWatermark.addEventListener('change', () => {
  bulkRoiCard.hidden = !bOpWatermark.checked;
  updateBulkBtn();
});
[bOpUpscale, bOpFps].forEach(el => el.addEventListener('change', updateBulkBtn));

// Load reference video
bRefBrowseBtn.addEventListener('click', () => bRefFileInput.click());
bRefFileInput.addEventListener('change', async () => {
  const f = bRefFileInput.files[0];
  if (!f) return;
  bRefStatus.textContent = 'Mengupload…';
  try {
    const form = new FormData();
    form.append('video', f);
    const data = await uploadWithProgress('/upload', form, () => {});
    bulkRefFilename = data.filename;
    bRefVideo.src = data.videoUrl;
    bVideoWrap.hidden = false;
    bDrawModeBtn.disabled = false;
    bRefStatus.textContent = `✓ ${f.name}`;
    toast('Video referensi dimuat', 'success');
  } catch (e) {
    bRefStatus.textContent = '✗ Upload gagal';
    toast('Gagal upload referensi: ' + e.message, 'error');
  }
});

// Bulk draw mode toggle
bDrawModeBtn.addEventListener('click', () => {
  bDrawMode = !bDrawMode;
  bOverlay.classList.toggle('draw-active', bDrawMode);
  bDrawModeBtn.classList.toggle('active', bDrawMode);
  bDrawModeBtn.textContent = bDrawMode ? '⏹ Selesai Tandai' : '✏️ Tandai Area';
  bDrawNotice.hidden = !bDrawMode;
});

// Bulk canvas drawing
bOverlay.addEventListener('mousedown', e => {
  if (!bDrawMode || !bRefVideo.videoWidth) return;
  bIsDrawing = true;
  const p = pos(e, bOverlay);
  bStartX = p.x; bStartY = p.y;
  bulkRoi = null; drawRoi(bOverlay, null);
});
bOverlay.addEventListener('mousemove', e => {
  if (!bIsDrawing) return;
  const p = pos(e, bOverlay);
  const sx = bRefVideo.videoWidth / bOverlay.width;
  const sy = bRefVideo.videoHeight / bOverlay.height;
  const x = Math.min(p.x, bStartX), y = Math.min(p.y, bStartY);
  bulkRoi = {
    x: Math.round(x * sx), y: Math.round(y * sy),
    width: Math.round(Math.abs(p.x - bStartX) * sx),
    height: Math.round(Math.abs(p.y - bStartY) * sy),
  };
  drawRoi(bOverlay, bulkRoi);
});
bOverlay.addEventListener('mouseup', () => {
  bIsDrawing = false;
  if (bulkRoi && bulkRoi.width > 0 && bulkRoi.height > 0) {
    bRoiText.textContent = `x:${bulkRoi.x} y:${bulkRoi.y} w:${bulkRoi.width} h:${bulkRoi.height}`;
    bRoiInfo.hidden = false;
    bDrawMode = false;
    bOverlay.classList.remove('draw-active');
    bDrawModeBtn.classList.remove('active');
    bDrawModeBtn.textContent = '✏️ Tandai Area';
    bDrawNotice.hidden = true;
  }
  updateBulkBtn();
});

function clearBulkRoiFn() {
  bulkRoi = null; drawRoi(bOverlay, null); bRoiInfo.hidden = true; updateBulkBtn();
}
bClearRoi.addEventListener('click', clearBulkRoiFn);
bClearRoiSmall.addEventListener('click', clearBulkRoiFn);

// ────────────────────────────────────────────
// BULK — VALIDATE & ENABLE BUTTON
// ────────────────────────────────────────────
function updateBulkBtn() {
  const hasOp = bOpWatermark.checked || bOpUpscale.checked || bOpFps.checked;
  const roiOk = !bOpWatermark.checked || (bulkRoi && bulkRoi.width > 0);

  let srcOk = false;
  if (bulkSrcMode === 'folder') {
    srcOk = scanResult.classList.contains('ok');
  } else {
    srcOk = bulkFiles.length > 0;
  }

  bulkBtn.disabled = !hasOp || !roiOk || !srcOk;
}

// ────────────────────────────────────────────
// BULK — PROCESS
// ────────────────────────────────────────────
bulkBtn.addEventListener('click', async () => {
  const hasOp = bOpWatermark.checked || bOpUpscale.checked || bOpFps.checked;
  if (!hasOp) { toast('Pilih minimal satu operasi', 'error'); return; }
  if (bOpWatermark.checked && (!bulkRoi || bulkRoi.width <= 0)) {
    toast('Tandai area watermark pada video referensi', 'error'); return;
  }

  bulkBtn.disabled = true;
  bulkProgress.hidden = false;
  bulkResults.innerHTML = '<p style="color:#64748b;font-size:13px;padding:12px 0">Memproses… harap tunggu</p>';

  const commonPayload = {
    roi: bOpWatermark.checked ? bulkRoi : null,
    method: bMethodSel.value,
    quality: bQualitySel.value,
    upscale: bOpUpscale.checked,
    fps_boost: bOpFps.checked,
  };

  try {
    let data;
    if (bulkSrcMode === 'folder') {
      const res = await fetch('/process-folder', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ folder_path: folderPath.value.trim(), ...commonPayload }),
      });
      data = await res.json();
      if (!res.ok) throw new Error(data.error);
    } else {
      // Upload files one by one, then process via /process-bulk
      const uploaded = [];
      for (const f of bulkFiles) {
        const form = new FormData();
        form.append('video', f);
        const upData = await uploadWithProgress('/upload', form, () => {});
        uploaded.push({ filename: upData.filename, originalBase: upData.originalBase });
      }
      const res = await fetch('/process-bulk', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ files: uploaded, ...commonPayload }),
      });
      data = await res.json();
      if (!res.ok) throw new Error(data.error);
    }
    renderBulkResults(data);
    toast(data.summary, 'success');
  } catch (e) {
    bulkResults.innerHTML = `<p style="color:#f87171;font-size:13px">${e.message}</p>`;
    toast(e.message || 'Bulk processing gagal', 'error');
  } finally {
    bulkProgress.hidden = true;
    bulkBtn.disabled = false;
  }
});

function renderBulkResults(data) {
  let html = `<div class="bulk-summary">${data.summary}</div>`;
  if (data.outputDir) html += `<div class="bulk-dir">📁 ${data.outputDir}</div>`;
  for (const r of (data.results || [])) {
    if (r.status === 'success') {
      html += `
        <div class="bulk-item">
          <div class="bulk-status ok">✓</div>
          <div>
            <div class="bulk-fname">${r.file}</div>
            <div class="bulk-out">→ ${r.output}</div>
          </div>
        </div>`;
    } else {
      html += `
        <div class="bulk-item">
          <div class="bulk-status err">✗</div>
          <div>
            <div class="bulk-fname">${r.file}</div>
            <div class="bulk-err">${r.error}</div>
          </div>
        </div>`;
    }
  }
  bulkResults.innerHTML = html;
}
