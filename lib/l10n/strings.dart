/// Interface text in two languages: Indonesian and English.
///
/// Deliberately a plain class rather than `flutter_localizations` + ARB, the
/// same shape Fotolane uses: there are only two languages, much of the text
/// carries interpolated numbers, and a mistyped getter fails at compile time
/// where an ARB key only fails after code generation.
///
/// Widgets read [S.of] so a language switch rebuilds them. The core layer
/// (pipeline, runners) has no BuildContext and reads [S.current], which the
/// app keeps in step with the chosen language.
library;

import 'package:flutter/widgets.dart';

import '../core/gpu_probe.dart';
import '../models/process_options.dart';

class S {
  const S._(this.isEnglish);

  final bool isEnglish;

  static const S id = S._(false);
  static const S en = S._(true);

  /// The language the core layer writes log lines and errors in.
  ///
  /// Indonesian until the app sets it, so widget tests that pump a page with
  /// no [LocaleScope] keep seeing the text they were written against.
  static S current = id;

  static S of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LocaleScope>()?.strings ??
      current;

  /// The language to start in when the user has never chosen one: Indonesian
  /// for an Indonesian language *or* region, English everywhere else.
  ///
  /// The region counts because many Indonesian Macs and PCs run an English
  /// UI with the region set to Indonesia (`en_ID`); those users are still the
  /// ones the Indonesian text was written for, and the switch is one click
  /// away either way.
  static S forLocale(String localeName) {
    final parts = localeName.split(RegExp(r'[_\-.@]'));
    final language = parts.first.toLowerCase();
    final region = parts.length > 1 ? parts[1].toUpperCase() : '';
    return language == 'id' || region == 'ID' ? id : en;
  }

  String get code => isEnglish ? 'en' : 'id';

  String _(String idText, String enText) => isEnglish ? enText : idText;

  // ── Numbers ───────────────────────────────────────────────────────────────

  /// One decimal, with the separator each language expects: 1,5 / 1.5.
  String dec1(double value) {
    final s = value.toStringAsFixed(1);
    return isEnglish ? s : s.replaceAll('.', ',');
  }

  String gb(int bytes) => '${dec1(bytes / (1 << 30))} GB';

  String mb(int bytes) => '${(bytes / (1 << 20)).round()} MB';

  // ── Header ────────────────────────────────────────────────────────────────

  String get tagline => _(
        'Foto · Video · Upscale · 60 FPS',
        'Photo · Video · Upscale · 60 FPS',
      );
  String get privacyNote => _(
        'Diproses lokal · file asli tidak diubah',
        'Processed locally · originals untouched',
      );
  String get bulkBadge => 'Bulk';
  String get singleBadge => _('Satu File', 'Single File');
  String get languageTooltip => _('Bahasa', 'Language');
  String get aboutTooltip => _('Tentang LabScale', 'About LabScale');

  // ── File stage ────────────────────────────────────────────────────────────

  String get filesTitle => 'File';
  String fileCount(int n) => _('$n file', '$n ${n == 1 ? 'file' : 'files'}');
  String doneOf(int done, int total) =>
      _('$done/$total selesai', '$done/$total done');
  String get addFiles => _('Tambah file', 'Add files');
  String get addFolder => _('Tambah folder', 'Add folder');
  String get clearAll => _('Kosongkan', 'Clear');
  String get dropHere => _('Lepas di sini', 'Drop here');
  String get dropInvitation => _(
        'Drag & drop file video / foto atau folder di sini',
        'Drag & drop videos, photos or a folder here',
      );
  String get pickFiles => _('Pilih File', 'Choose Files');
  String get pickFolder => _('Pilih Folder', 'Choose Folder');
  String get supportedFormats => _(
        'Video: MP4 · MOV · WEBM · MKV · AVI   |   Foto: JPG · PNG · WEBP · TIFF',
        'Video: MP4 · MOV · WEBM · MKV · AVI   |   Photo: JPG · PNG · WEBP · TIFF',
      );
  String get mediaTypeGroup => 'Media';

  String get tileDone => _('selesai', 'done');
  String get tileFailed => _('gagal', 'failed');
  String get tileRunning => _('memproses…', 'processing…');
  String get tileCancelled => _('dibatalkan', 'cancelled');

  // ── Operations card ───────────────────────────────────────────────────────

  String get opsTitle => _('Operasi', 'Operations');
  String get upscale => 'Upscale';
  String get upscaleDescription => _(
        'Perbesar resolusi dengan AI atau Lanczos',
        'Increase resolution with AI or Lanczos',
      );
  String get fpsBoost => _('Boost ke $kTargetFps FPS', 'Boost to $kTargetFps FPS');
  String get fpsViaRife => _(
        'Motion interpolation via RIFE AI',
        'Motion interpolation with RIFE AI',
      );
  String get fpsViaFfmpeg => _(
        'Motion interpolation via FFmpeg minterpolate',
        'Motion interpolation with FFmpeg minterpolate',
      );
  String get fpsOnlyVideoPhotos => _(
        'Hanya untuk video — pilihan saat ini foto semua',
        'Video only — the current selection is all photos',
      );
  String get fpsOnlyVideoEmpty => _(
        'Hanya untuk video — pilih klip dulu',
        'Video only — add a clip first',
      );
  String get outputQuality => _('Kualitas Output', 'Output Quality');
  String get videoCodec => _('Codec Video', 'Video Codec');
  String get outputFolder => _('Folder Output', 'Output Folder');
  String get pickOutputFolder => _('Pilih folder output', 'Choose output folder');
  String get changeOutputFolder => _('Ubah folder output', 'Change output folder');
  String get resetOutputFolder =>
      _('Kembalikan ke folder bawaan', 'Back to the default folder');
  String get openFolder => _('Buka folder', 'Open folder');
  String get upscaleModel => _('Model Upscale', 'Upscale Model');
  String get outputScale => _('Skala Output', 'Output Scale');
  String sharpness(int percent) => 'Sharpness  $percent%';
  String get defaultTag => '(default)';
  String get esrganVideoNotice => _(
        'Real-ESRGAN pada video diproses per-frame — gunakan untuk klip pendek.',
        'Real-ESRGAN processes video frame by frame — best for short clips.',
      );
  String get esrganMissingNotice => _(
        'realesrgan-ncnn-vulkan tidak ditemukan — lihat Setup & Status di bawah.',
        'realesrgan-ncnn-vulkan was not found — see Setup & Status below.',
      );
  String get interpEngine => _('Engine Interpolasi', 'Interpolation Engine');
  String get rifeActive => _('✓ RIFE aktif', '✓ RIFE active');
  String get rifeUnavailable => _(
        '⚠ RIFE belum tersedia — pakai FFmpeg',
        '⚠ RIFE unavailable — using FFmpeg',
      );

  String get estimateNeedsUpscale => _(
        'Aktifkan Upscale untuk melihat estimasi.',
        'Turn on Upscale to see the output size.',
      );
  String get estimateReading => _('Membaca dimensi…', 'Reading dimensions…');
  String get estimateNeedsFile => _(
        'Pilih file untuk melihat estimasi dimensi.',
        'Add a file to see the output size.',
      );
  String estimateEnhanceOnly(String size) => _(
        '$size → $size (enhance saja, resolusi tetap)',
        '$size → $size (enhance only, same resolution)',
      );

  // ── Model download ────────────────────────────────────────────────────────

  String modelDownloadSuffix(int bytes) =>
      _(' — unduh ${mb(bytes)}', ' — ${mb(bytes)} download');
  String modelNotInstalled(int bytes) => _(
        'Model ini belum terpasang. Unduh sekali (${mb(bytes)}), lalu bisa '
            'dipakai seterusnya tanpa internet.',
        'This model is not installed yet. Download it once (${mb(bytes)}) and '
            'it works offline from then on.',
      );
  String get downloadModel => _('Unduh model', 'Download model');
  String downloading(int percent) =>
      _('Mengunduh… $percent%', 'Downloading… $percent%');
  String downloadFailed(Object e) =>
      _('Unduhan gagal: $e', 'Download failed: $e');
  String get downloadHashMismatch => _(
        'berkas yang diterima tidak cocok dengan checksum — dibuang',
        'the file received did not match its checksum — discarded',
      );
  String downloadHttpError(int code) =>
      _('server membalas $code', 'the server replied $code');
  String modelCredit(String author, String license) =>
      _('oleh $author · lisensi $license', 'by $author · $license licence');
  String get nonCommercialNote => _(
        'Lisensi model ini hanya untuk pemakaian non-komersial.',
        'This model’s licence allows non-commercial use only.',
      );
  String get modelWeightsMissing => _(
        'Bobot model ini tidak ada di instalasi ini.',
        'This model’s weights are missing from this installation.',
      );

  // ── Process button ────────────────────────────────────────────────────────

  String get processFiles => _('Proses File', 'Process Files');
  String processNFiles(int n) => _('Proses $n File', 'Process $n Files');
  String get processing => _('Memproses…', 'Processing…');
  String get cancel => _('Batalkan', 'Cancel');
  String get cancelling => _('Membatalkan…', 'Cancelling…');
  String processingFile(String name) =>
      _('Memproses $name…', 'Processing $name…');
  String succeeded(int ok, int total) =>
      _('$ok/$total berhasil diproses', '$ok/$total processed successfully');
  String succeededCancelled(int ok, int total) => _(
        '$ok/$total berhasil · sisanya dibatalkan',
        '$ok/$total processed · the rest cancelled',
      );
  String get stoppedOnError => _('Berhenti karena error', 'Stopped by an error');
  String unexpectedStop(Object e) =>
      _('Proses berhenti tak terduga: $e', 'Processing stopped unexpectedly: $e');

  // ── Snackbar errors ───────────────────────────────────────────────────────

  String get busy => _(
        'Sedang memproses — tunggu sampai selesai',
        'Still processing — wait until it finishes',
      );
  String get noSupportedFiles => _(
        'Tidak ada file yang didukung di lokasi tersebut',
        'No supported files were found there',
      );
  String get cannotWriteFolder =>
      _('Tidak bisa menulis ke folder itu', 'That folder is not writable');
  String get cannotOpenFolder =>
      _('Gagal membuka folder', 'Could not open the folder');

  // ── Results & log ─────────────────────────────────────────────────────────

  String get resultsTitle => _('Hasil Pemrosesan', 'Results');
  String get openFolderButton => _('Buka Folder', 'Open Folder');
  String get failed => _('Gagal', 'Failed');
  String get cancelled => _('Dibatalkan', 'Cancelled');
  String get logTitle => _('Log Proses', 'Process Log');
  String get copyLog => _('Salin log', 'Copy log');
  String get logCopied => _('Log disalin', 'Log copied');

  // ── Viewer ────────────────────────────────────────────────────────────────

  String get back => _('Kembali (Esc)', 'Back (Esc)');
  String get dragToCompare => _(
        'Geser pembatas untuk membandingkan asli dan hasil',
        'Drag the divider to compare the original and the result',
      );
  String get notProcessedYet => _(
        'Belum diproses — yang tampil file aslinya',
        'Not processed yet — showing the original',
      );
  String get revealInExplorer =>
      _('Tampilkan di Explorer', 'Show in Explorer');
  String get revealInFinder => _('Tampilkan di Finder', 'Show in Finder');
  String get previous => _('Sebelumnya (←)', 'Previous (←)');
  String get next => _('Berikutnya (→)', 'Next (→)');
  String get cannotShowImage =>
      _('Tidak dapat menampilkan gambar ini', 'This image cannot be shown');
  String get previewUnavailable =>
      _('Preview tidak tersedia', 'Preview unavailable');
  String get cannotGrabFrames => _(
        'Tidak dapat mengambil frame pembanding',
        'Could not grab frames to compare',
      );
  String get emptyPreview => _(
        'Pilih file video atau foto untuk melihat preview',
        'Choose a video or photo to preview it',
      );
  String get before => _('Asli', 'Original');
  String get after => _('Hasil', 'Result');
  String get beforeFrame => _('Asli (frame)', 'Original (frame)');
  String get afterFrame => _('Hasil (frame)', 'Result (frame)');
  String get compare => _('Banding', 'Compare');
  String get play => _('Putar', 'Play');

  // ── Setup & status ────────────────────────────────────────────────────────

  String get loading => _('memuat…', 'loading…');
  String get ffmpegNotFound => _('FFmpeg tidak ditemukan', 'FFmpeg not found');
  String get cpuEncoderOnly => _('encoder CPU saja', 'CPU encoder only');
  String aiReady(int ready, int total) =>
      _('$ready/$total fitur AI aktif', '$ready/$total AI features active');
  String get setupStatus => 'Setup & Status';
  String get ffmpegDetail => _(
        'Dekode, enkode, dan filter — wajib ada',
        'Decoding, encoding and filters — required',
      );
  String get ffmpegHint => _(
        'Install FFmpeg, atau salin ffmpeg + ffprobe ke bin/',
        'Install FFmpeg, or copy ffmpeg + ffprobe into bin/',
      );
  String get esrganName => _('Upscale AI (Real-ESRGAN)', 'AI upscale (Real-ESRGAN)');
  String get esrganDetail => _(
        'realesrgan-ncnn-vulkan — GPU Vulkan / Metal',
        'realesrgan-ncnn-vulkan — Vulkan / Metal GPU',
      );
  String get esrganHint => _(
        'Salin realesrgan-ncnn-vulkan + folder models ke bin/',
        'Copy realesrgan-ncnn-vulkan and its models folder into bin/',
      );
  String get rifeName => _('Interpolasi AI (RIFE)', 'AI interpolation (RIFE)');
  String get rifeDetail => _(
        'rife-ncnn-vulkan — 5–10× lebih cepat dari FFmpeg',
        'rife-ncnn-vulkan — 5–10× faster than FFmpeg',
      );
  String get rifeHint => _(
        'Salin rife-ncnn-vulkan + folder model ke bin/',
        'Copy rife-ncnn-vulkan and its model folder into bin/',
      );
  String get videoEncoder => 'Video Encoder';
  String searchedIn(String dir) => _('Dicari di: $dir', 'Looked in: $dir');
  String get recheck => _('Cek ulang', 'Check again');
  String get close => _('Tutup', 'Close');
  String get copyHint => _('Salin petunjuk', 'Copy instructions');
  String get openLogFolder => _('Buka folder log', 'Open log folder');

  // ── About & updates ───────────────────────────────────────────────────────

  String get aboutBlurb => _(
        'Upscale AI dan boost 60 FPS untuk foto & video. Semuanya diproses di '
            'komputer ini — tidak ada yang diunggah ke mana pun.',
        'AI upscaling and 60 FPS boost for photos and video. Everything runs on '
            'this computer — nothing is uploaded anywhere.',
      );
  String version(String v) => _('Versi $v', 'Version $v');
  String get madeBy => _(
        'Gratis & open source · oleh Labstory Studio',
        'Free & open source · by Labstory Studio',
      );
  String get fotolanePitch => _(
        'Juga dari kami: Fotolane — siapkan ribuan foto event untuk diunggah, '
            'otomatis.',
        'Also from us: Fotolane — get thousands of event photos upload-ready, '
            'automatically.',
      );
  String get sourceCode => _('Kode sumber', 'Source code');
  String get reportIssue => _('Laporkan masalah', 'Report a problem');
  String get licenses => _('Lisensi', 'Licences');
  String get checkUpdates => _('Cek pembaruan', 'Check for updates');
  String get checkingUpdates => _('Memeriksa…', 'Checking…');
  String get upToDate => _('Sudah versi terbaru', 'You’re up to date');
  String get updateCheckFailed => _(
        'Tidak bisa memeriksa pembaruan',
        'Could not check for updates',
      );
  String updateAvailable(String v) =>
      _('LabScale $v tersedia', 'LabScale $v is available');
  String get download => _('Unduh', 'Download');
  String get later => _('Nanti', 'Later');

  // ── Option labels ─────────────────────────────────────────────────────────

  /// Labelled by what each model is *for* rather than by its name — nobody
  /// picking a model knows what "ultramix-balanced" does, but everybody knows
  /// whether they are upscaling a photo or a logo.
  String modelLabel(UpscaleModel m) => switch (m) {
        UpscaleModel.lanczos =>
          _('Cepat — tanpa AI (Lanczos)', 'Fast — no AI (Lanczos)'),
        UpscaleModel.ultramix => _(
            'Desain & ilustrasi — paling seimbang',
            'Design & illustration — best balance',
          ),
        UpscaleModel.ultrasharp => _(
            'Desain tepi tajam — lebih renyah',
            'Design, crisp edges — sharper',
          ),
        UpscaleModel.realesrganX4Plus =>
          _('Foto realistis — ESRGAN x4+', 'Photo, realistic — ESRGAN x4+'),
        UpscaleModel.remacri => _(
            'Foto lembut — tambah tekstur (agresif)',
            'Photo, soft source — adds texture (strong)',
          ),
        UpscaleModel.realesrganX4PlusAnime =>
          _('Anime & manga — garis bersih', 'Anime & manga — clean lines'),
        UpscaleModel.realesrAnimeVideoV3 =>
          _('Video anime — jauh lebih cepat', 'Anime video — much faster'),
        UpscaleModel.upscaylLite =>
          _('Draf cepat — 9× lebih cepat', 'Quick draft — 9× faster'),
      };

  String interpLabel(InterpEngine e) => switch (e) {
        InterpEngine.ffmpeg => _(
            'FFmpeg (MCI bidir) — bawaan, lambat',
            'FFmpeg (MCI bidir) — built in, slow',
          ),
        InterpEngine.rife => _(
            'RIFE AI — 5–10× lebih cepat & halus',
            'RIFE AI — 5–10× faster & smoother',
          ),
      };

  String qualityLabel(Quality q) => switch (q) {
        Quality.fast => 'Fast',
        Quality.balanced => 'Balanced',
        Quality.better => 'Better',
        Quality.best => 'Best',
        Quality.ultra => 'Ultra (lossless)',
      };

  String codecLabel(VideoCodec c) => switch (c) {
        VideoCodec.h264 => _('H.264 (kompatibel)', 'H.264 (most compatible)'),
        VideoCodec.hevc =>
          _('HEVC / H.265 (file lebih kecil)', 'HEVC / H.265 (smaller files)'),
        VideoCodec.av1 =>
          _('AV1 (terkecil — perlu HW/SW)', 'AV1 (smallest — needs HW/SW)'),
      };

  // ── Core layer: log lines ─────────────────────────────────────────────────

  String logVideo(int w, int h, double fps, int frames) => _(
        'Video $w×$h @ ${fps.toStringAsFixed(1)}fps ($frames frame).',
        'Video $w×$h @ ${fps.toStringAsFixed(1)}fps ($frames frames).',
      );
  String logImage(int w, int h) =>
      _('Gambar $w×$h dimuat.', 'Image $w×$h loaded.');
  String get logImageSaved => _('Gambar tersimpan.', 'Image saved.');
  String get logRifeFallback => _(
        'RIFE tidak ditemukan — pakai FFmpeg minterpolate.',
        'RIFE not found — using FFmpeg minterpolate.',
      );
  String logDirectEncode(String quality, String encoder) => _(
        'Enkode langsung [$quality] via $encoder…',
        'Direct encode [$quality] with $encoder…',
      );
  String logEncode(String quality, String encoder) =>
      _('Enkode [$quality] via $encoder…', 'Encoding [$quality] with $encoder…');
  String get logEncodeDone => _('Enkode selesai.', 'Encode finished.');
  String logExtract(int frames) => _(
        'Ekstrak frame dari video ($frames frame)…',
        'Extracting frames from the video ($frames frames)…',
      );
  String get logExtractDone => _('Ekstrak frame selesai.', 'Frames extracted.');
  String logEsrganFrames(String model, int frames, int scale) => _(
        'Real-ESRGAN: model $model pada $frames frame ($scale×)…',
        'Real-ESRGAN: model $model on $frames frames ($scale×)…',
      );
  String logEsrganImage(String model, int scale) =>
      'Real-ESRGAN: model $model ($scale×)…';
  String logEsrganImageWide(String model, int scale, int native) => _(
        'Real-ESRGAN: model $model ($scale× — jaringan $native× lalu diperkecil)…',
        'Real-ESRGAN: model $model ($scale× — runs at $native×, then scaled down)…',
      );
  String get logEsrganDone => _('Real-ESRGAN selesai.', 'Real-ESRGAN finished.');
  String logRifeStart(int from, String fromFps, int to, String toFps) =>
      _('RIFE: $from frame @ ${fromFps}fps → $to frame @ ${toFps}fps',
          'RIFE: $from frames @ ${fromFps}fps → $to frames @ ${toFps}fps');
  String logRifeDone(int to, String fps) => _(
        'RIFE selesai → $to frame @ ${fps}fps.',
        'RIFE finished → $to frames @ ${fps}fps.',
      );
  String logTempEstimate(int needed, int free) => _(
        'Perkiraan ruang sementara: ±${gb(needed)} (tersedia ${gb(free)}).',
        'Estimated temporary space: ~${gb(needed)} (${gb(free)} free).',
      );
  String get logCancelled =>
      _('Dibatalkan oleh pengguna.', 'Cancelled by the user.');

  // ── Core layer: errors ────────────────────────────────────────────────────

  String toolFailed(String tool, int code) =>
      _('$tool gagal (exit $code)', '$tool failed (exit $code)');
  String get noOpForPhoto => _(
        'Tidak ada operasi yang berlaku untuk foto',
        'None of the chosen operations apply to photos',
      );
  String get noFramesToUpscale =>
      _('Tidak ada frame untuk di-upscale', 'There are no frames to upscale');
  String get noFramesToInterpolate => _(
        'Tidak ada frame untuk diinterpolasi',
        'There are no frames to interpolate',
      );
  String notEnoughDisk(int needed, int free, String dir) => _(
        'Ruang disk tidak cukup: butuh ±${gb(needed)} untuk frame sementara, '
            'tersedia ${gb(free)} di $dir. Kosongkan ruang, pilih "Video '
            'anime" (punya bobot 2× sendiri), atau potong klipnya.',
        'Not enough disk space: about ${gb(needed)} is needed for temporary '
            'frames, ${gb(free)} is free on $dir. Free up space, pick "Anime '
            'video" (it has its own 2× weights), or trim the clip.',
      );
  String get ffmpegMissingHint => _(
        'FFmpeg tidak ditemukan. Install ulang LabScale, atau letakkan ffmpeg '
            'dan ffprobe di folder bin/ milik aplikasi.',
        'FFmpeg was not found. Reinstall LabScale, or place ffmpeg and ffprobe '
            'in the app’s bin/ folder.',
      );
  String get noVulkanHint => _(
        'GPU atau driver di komputer ini tidak mendukung Vulkan, jadi fitur AI '
            'tidak bisa jalan. Upscale Lanczos dan boost 60 FPS lewat FFmpeg '
            'tetap bisa dipakai. Memperbarui driver GPU kadang menolong.',
        'This computer’s GPU or driver does not support Vulkan, so the AI '
            'features cannot run. Lanczos upscaling and the FFmpeg 60 FPS boost '
            'still work. Updating the GPU driver sometimes helps.',
      );
  String get noVulkanShort => _(
        'Tidak bisa jalan: GPU/driver tidak mendukung Vulkan',
        'Cannot run: the GPU/driver does not support Vulkan',
      );
  /// Why an installed AI tool cannot run, worded by what actually failed:
  /// "no Vulkan" sends the user to their driver, anything else (a hang, a
  /// driver error) must not claim Vulkan is missing.
  String gpuIssue(GpuProbeResult issue) =>
      issue.failure == GpuProbeFailure.noVulkan
          ? noVulkanShort
          : gpuProbeFailed(issue.detail);
  String gpuProbeFailed(String detail) => _(
        'Tidak bisa jalan di GPU ini — $detail',
        'Cannot run on this GPU — $detail',
      );
  String get esrganMissingHint => _(
        'Real-ESRGAN tidak ditemukan. Install ulang LabScale, atau letakkan '
            'realesrgan-ncnn-vulkan di folder bin/ milik aplikasi.',
        'Real-ESRGAN was not found. Reinstall LabScale, or place '
            'realesrgan-ncnn-vulkan in the app’s bin/ folder.',
      );
  String get rifeMissingHint => _(
        'RIFE tidak ditemukan. Install ulang LabScale, atau letakkan '
            'rife-ncnn-vulkan di folder bin/ milik aplikasi.',
        'RIFE was not found. Reinstall LabScale, or place rife-ncnn-vulkan in '
            'the app’s bin/ folder.',
      );
}

/// Makes the chosen language available to every route under it, so dialogs
/// and the full-window viewer switch along with the main page.
class LocaleScope extends InheritedWidget {
  const LocaleScope({super.key, required this.strings, required super.child});

  final S strings;

  @override
  bool updateShouldNotify(LocaleScope oldWidget) =>
      oldWidget.strings.isEnglish != strings.isEnglish;
}
