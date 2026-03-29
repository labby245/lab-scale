/* ── Selectors ── */
const $ = id => document.getElementById(id);

// Header tabs
const tabSingle = $('tabSingle'), tabBulk = $('tabBulk');
const singleMode = $('singleMode'), bulkMode = $('bulkMode');

// Single — Upload
const dropzone = $('dropzone'), browseBtn = $('browseBtn'), fileInput = $('fileInput');
const uploadBtn = $('uploadBtn'), uploadProgress = $('uploadProgress');
const uploadBar = $('uploadBar'), uploadPct = $('uploadPct');
const fileChip = $('fileChip'), fileChipName = $('fileChipName');

// Single — Operations
const opWatermark = $('opWatermark'), opUpscale = $('opUpscale'), opFps = $('opFps');
const methodSel = $('method'), qualitySel = $('quality');

// Single — Editor / ROI
const video = $('video'), overlay = $('overlay');
const vpPlaceholder = $('vpPlaceholder'), roiHint = $('roiHint');
const roiInfo = $('roiInfo'), roiText = $('roiText');
const clearRoi = $('clearRoi'), clearRoiSmall = $('clearRoiSmall');

// Single — Process
const processBtn = $('processBtn'), procProgress = $('procProgress'), singleResult = $('singleResult');

// Bulk — Folder
const folderPath = $('folderPath'), scanBtn = $('scanBtn'), scanResult = $('scanResult');

// Bulk — Operations
const bOpWatermark = $('bOpWatermark'), bOpUpscale = $('bOpUpscale'), bOpFps = $('bOpFps');
const bulkRoiSection = $('bulkRoiSection');
const bRoiX = $('bRoiX'), bRoiY = $('bRoiY'), bRoiW = $('bRoiW'), bRoiH = $('bRoiH');
const bMethodSel = $('bMethod'), bQualitySel = $('bQuality');

// Bulk — Process
const bulkBtn = $('bulkBtn'), bulkProgress = $('bulkProgress'), bulkResults = $('bulkResults');

const toasts = $('toasts');

// ── State ────────────────────────────────────────────────────────────────
let uploadedFilename = null;
let roi = null;
let isDrawing = false, startX = 0, startY = 0;

// ── Toast ────────────────────────────────────────────────────────────────
function toast(msg, type = 'info', ms = 3000) {
  const t = document.createElement('div');
  t.className = `toast ${type}`;
  t.textContent = msg;
  toasts.appendChild(t);
  setTimeout(() => t.remove(), ms);
}

// ── Tab Switching ─────────────────────────────────────────────────────────
tabSingle.addEventListener('click', () => {
  tabSingle.classList.add('active'); tabBulk.classList.remove('active');
  singleMode.hidden = false; bulkMode.hidden = true;
  singleMode.classList.add('active');
});
tabBulk.addEventListener('click', () => {
  tabBulk.classList.add('active'); tabSingle.classList.remove('active');
  bulkMode.hidden = false; singleMode.hidden = true;
  bulkMode.classList.add('active');
});

// ── Dropzone ──────────────────────────────────────────────────────────────
['dragenter', 'dragover'].forEach(ev => dropzone.addEventListener(ev, e => {
  e.preventDefault(); e.stopPropagation(); dropzone.classList.add('dragover');
}));
['dragleave', 'drop'].forEach(ev => dropzone.addEventListener(ev, e => {
  e.preventDefault(); e.stopPropagation(); dropzone.classList.remove('dragover');
}));
dropzone.addEventListener('drop', e => {
  const f = e.dataTransfer.files[0];
  if (f) { setFile(f); }
});
browseBtn.addEventListener('click', () => fileInput.click());
fileInput.addEventListener('change', () => {
  if (fileInput.files[0]) setFile(fileInput.files[0]);
});

function setFile(f) {
  fileChipName.textContent = f.name;
  fileChip.hidden = false;
  uploadBtn.disabled = false;
}

// ── Upload ────────────────────────────────────────────────────────────────
uploadBtn.addEventListener('click', async () => {
  const f = fileInput.files?.[0];
  if (!f) { toast('Pilih file video dulu', 'error'); return; }

  uploadProgress.hidden = false;
  uploadBar.style.width = '0%';
  uploadPct.textContent = '0%';
  uploadBtn.disabled = true;

  const form = new FormData();
  form.append('video', f);

  try {
    const data = await uploadWithProgress('/upload', form, pct => {
      uploadBar.style.width = pct + '%';
      uploadPct.textContent = pct + '%';
    });
    uploadedFilename = data.filename;
    video.src = data.videoUrl;
    vpPlaceholder.style.display = 'none';
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

// ── Operations toggle ────────────────────────────────────────────────────
[opWatermark, opUpscale, opFps].forEach(el => el.addEventListener('change', updateProcessBtn));

function updateProcessBtn() {
  const hasOp = opWatermark.checked || opUpscale.checked || opFps.checked;
  const hasFile = !!uploadedFilename;
  const needsRoi = opWatermark.checked && (!roi || roi.width <= 0);
  processBtn.disabled = !hasFile || !hasOp || needsRoi;
}

// ── Canvas ROI ───────────────────────────────────────────────────────────
function fitCanvas() {
  const w = video.clientWidth, h = video.clientHeight;
  if (!w || !h) return;
  overlay.width = w; overlay.height = h;
  overlay.style.width = w + 'px'; overlay.style.height = h + 'px';
  overlay.style.left = overlay.style.top = '0px';
}
function drawRoi() {
  const ctx = overlay.getContext('2d');
  ctx.clearRect(0, 0, overlay.width, overlay.height);
  if (!roi) return;
  const sx = overlay.width / video.videoWidth;
  const sy = overlay.height / video.videoHeight;
  ctx.strokeStyle = '#6366f1';
  ctx.lineWidth = 2;
  ctx.setLineDash([6, 4]);
  ctx.strokeRect(roi.x * sx, roi.y * sy, roi.width * sx, roi.height * sy);
  ctx.fillStyle = 'rgba(99,102,241,0.12)';
  ctx.fillRect(roi.x * sx, roi.y * sy, roi.width * sx, roi.height * sy);
}
window.addEventListener('resize', () => { fitCanvas(); drawRoi(); });
video.addEventListener('loadedmetadata', () => { fitCanvas(); roiHint.style.display = 'block'; });

overlay.addEventListener('mousedown', e => {
  if (!video.videoWidth) return;
  isDrawing = true;
  const p = pos(e);
  startX = p.x; startY = p.y;
  roi = null; drawRoi();
  roiHint.style.display = 'none';
});
overlay.addEventListener('mousemove', e => {
  if (!isDrawing) return;
  const p = pos(e);
  const sx = video.videoWidth / overlay.width;
  const sy = video.videoHeight / overlay.height;
  const x = Math.min(p.x, startX), y = Math.min(p.y, startY);
  roi = {
    x: Math.round(x * sx), y: Math.round(y * sy),
    width: Math.round(Math.abs(p.x - startX) * sx),
    height: Math.round(Math.abs(p.y - startY) * sy),
  };
  drawRoi();
});
overlay.addEventListener('mouseup', () => {
  isDrawing = false;
  if (roi && roi.width > 0 && roi.height > 0) {
    roiText.textContent = `x:${roi.x} y:${roi.y} w:${roi.width} h:${roi.height}`;
    roiInfo.hidden = false;
  }
  updateProcessBtn();
});

function clearRoiFn() {
  roi = null; drawRoi(); roiInfo.hidden = true;
  roiHint.style.display = 'block'; updateProcessBtn();
}
clearRoi.addEventListener('click', clearRoiFn);
clearRoiSmall.addEventListener('click', clearRoiFn);

function pos(e) {
  const r = overlay.getBoundingClientRect();
  return { x: e.clientX - r.left, y: e.clientY - r.top };
}

// ── Single Process ────────────────────────────────────────────────────────
processBtn.addEventListener('click', async () => {
  if (!uploadedFilename) { toast('Upload video dulu', 'error'); return; }
  const hasOp = opWatermark.checked || opUpscale.checked || opFps.checked;
  if (!hasOp) { toast('Pilih minimal satu operasi', 'error'); return; }
  if (opWatermark.checked && (!roi || roi.width <= 0)) {
    toast('Tandai area watermark di video', 'error'); return;
  }

  processBtn.disabled = true;
  procProgress.hidden = false;
  singleResult.hidden = true;

  const payload = {
    filename: uploadedFilename,
    roi: opWatermark.checked ? roi : null,
    method: methodSel.value,
    quality: qualitySel.value,
    upscale: opUpscale.checked,
    fps_boost: opFps.checked,
  };

  try {
    const res = await fetch('/process', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Processing gagal');

    showSingleResult(data);
    toast('Selesai! File otomatis tersimpan.', 'success');
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
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>
      Berhasil disimpan
    </div>
    <div class="r-fn">${data.outputFilename}</div>
    <div class="r-path">${data.outputPath}</div>
  `;
  singleResult.hidden = false;
}

// ── Bulk — Scan Folder ────────────────────────────────────────────────────
scanBtn.addEventListener('click', async () => {
  const fp = folderPath.value.trim();
  if (!fp) { toast('Masukkan path folder', 'error'); return; }
  scanResult.textContent = 'Scanning…';
  scanResult.className = 'scan-result';

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
    bulkBtn.disabled = data.count === 0;
    toast(`${data.count} video ditemukan`, 'success');
  } catch (e) {
    scanResult.textContent = '✗ ' + (e.message || 'Folder tidak valid');
    scanResult.className = 'scan-result err';
    bulkBtn.disabled = true;
  }
});

// Enter key to scan
folderPath.addEventListener('keydown', e => { if (e.key === 'Enter') scanBtn.click(); });

// ── Bulk — Operation toggles ──────────────────────────────────────────────
bOpWatermark.addEventListener('change', () => {
  bulkRoiSection.hidden = !bOpWatermark.checked;
});

// ── Bulk Process ──────────────────────────────────────────────────────────
bulkBtn.addEventListener('click', async () => {
  const fp = folderPath.value.trim();
  if (!fp) { toast('Masukkan path folder', 'error'); return; }
  const hasOp = bOpWatermark.checked || bOpUpscale.checked || bOpFps.checked;
  if (!hasOp) { toast('Pilih minimal satu operasi', 'error'); return; }

  let bulkRoi = null;
  if (bOpWatermark.checked) {
    bulkRoi = {
      x: parseInt(bRoiX.value) || 0,
      y: parseInt(bRoiY.value) || 0,
      width: parseInt(bRoiW.value) || 0,
      height: parseInt(bRoiH.value) || 0,
    };
    if (bulkRoi.width <= 0 || bulkRoi.height <= 0) {
      toast('Lebar/tinggi ROI harus lebih dari 0', 'error'); return;
    }
  }

  bulkBtn.disabled = true;
  bulkProgress.hidden = false;
  bulkResults.innerHTML = '<p style="color:#64748b;font-size:13px;padding:12px 0">Memproses… harap tunggu</p>';

  const payload = {
    folder_path: fp,
    roi: bulkRoi,
    method: bMethodSel.value,
    quality: bQualitySel.value,
    upscale: bOpUpscale.checked,
    fps_boost: bOpFps.checked,
  };

  try {
    const res = await fetch('/process-folder', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Gagal');

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
  let html = `
    <div class="bulk-summary">${data.summary}</div>
    <div class="bulk-dir">📁 ${data.outputDir}</div>
  `;
  for (const r of data.results) {
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
