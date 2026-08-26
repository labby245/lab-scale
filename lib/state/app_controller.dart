/// Central app state: file selection, options, capability probing, and the
/// currently running job.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/binaries.dart';
import '../core/esrgan_runner.dart';
import '../core/ffmpeg_runner.dart';
import '../core/job_log.dart';
import '../core/pipeline.dart';
import '../core/rife_runner.dart';
import '../core/thumbnailer.dart';
import '../models/media_file.dart';
import '../models/process_options.dart';

/// Which external tools are present on this machine.
class Capabilities {
  const Capabilities({
    this.ffmpeg = false,
    this.esrgan = false,
    this.rife = false,
    this.encoderSummary = 'memuat…',
  });

  final bool ffmpeg;
  final bool esrgan;
  final bool rife;
  final String encoderSummary;

  int get readyCount => [esrgan, rife].where((v) => v).length;
  int get totalCount => 2;
}

enum JobPhase { idle, running, done }

/// Where a single queued file stands, for the selection grid.
enum FileStatus { queued, running, done, failed }

class AppController extends ChangeNotifier {
  AppController();

  /// Builds a controller already parked in a given state, so widgets that read
  /// it can be exercised without running a real job.
  @visibleForTesting
  AppController.inState({
    List<MediaFile> files = const [],
    JobPhase phase = JobPhase.idle,
    int? activeIndex,
    double? fileProgress,
    List<JobResult> results = const [],
  }) {
    _files = files;
    _phase = phase;
    _activeIndex = activeIndex;
    _fileProgress = fileProgress;
    _results = results;
  }

  // ── Preference keys ───────────────────────────────────────────────────────
  static const _kUpscaleModel = 'pref_upscale_model';
  static const _kCodec = 'pref_codec';
  static const _kInterpEngine = 'pref_interp_engine';
  static const _kQuality = 'pref_quality';
  static const _kSharpness = 'pref_sharpness';
  static const _kScale = 'pref_upscale_scale';
  static const _kOutputDir = 'pref_output_dir';

  // ── State ─────────────────────────────────────────────────────────────────
  List<MediaFile> _files = const [];
  ProcessOptions _options = const ProcessOptions();
  Capabilities _capabilities = const Capabilities();
  JobPhase _phase = JobPhase.idle;
  double? _progress;
  String _statusText = '';
  List<String> _logLines = const [];
  List<JobResult> _results = const [];
  String? _errorMessage;
  String _outputDir = '';
  String _defaultOutputDir = '';
  String _tempDir = '';
  MediaInfo? _sourceInfo;
  int? _activeIndex;
  double? _fileProgress;
  MediaFile? _previewFile;
  Thumbnailer? _thumbnailer;

  SharedPreferences? _prefs;
  StreamSubscription<String>? _logSub;
  StreamSubscription<double?>? _progressSub;

  // ── Getters ───────────────────────────────────────────────────────────────
  List<MediaFile> get files => _files;
  MediaFile? get firstFile => _files.isEmpty ? null : _files.first;
  bool get hasFiles => _files.isNotEmpty;
  bool get isBulk => _files.length > 1;

  ProcessOptions get options => _options;
  Capabilities get capabilities => _capabilities;
  JobPhase get phase => _phase;
  bool get isRunning => _phase == JobPhase.running;
  double? get progress => _progress;
  String get statusText => _statusText;
  List<String> get logLines => _logLines;
  List<JobResult> get results => _results;
  String? get errorMessage => _errorMessage;
  String get outputDir => _outputDir;

  /// Index of the file being processed right now, or null when idle.
  int? get activeIndex => _activeIndex;

  /// Progress of the *current* file, 0–1. Distinct from [progress], which is
  /// that fraction spread across the whole queue for the overall bar.
  double? get fileProgress => _fileProgress;

  /// File the preview pane is showing, or null when the grid has the column
  /// to itself.
  MediaFile? get previewFile => _previewFile;

  /// Shared poster cache for the grid. Null until [initialize] has run.
  Thumbnailer? get thumbnailer => _thumbnailer;

  /// Where [index] stands in the queue.
  ///
  /// Results are appended in queue order, so a file has a result exactly when
  /// its index is below the number collected so far.
  FileStatus statusFor(int index) {
    if (index < _results.length) {
      return _results[index].isSuccess ? FileStatus.done : FileStatus.failed;
    }
    if (isRunning && index == _activeIndex) return FileStatus.running;
    return FileStatus.queued;
  }

  /// The finished result for [index], or null while it is still queued.
  JobResult? resultFor(int index) =>
      index < _results.length ? _results[index] : null;

  /// The finished result for [file], matched by path rather than identity so a
  /// rebuilt [MediaFile] still lines up.
  JobResult? resultForFile(MediaFile? file) {
    if (file == null) return null;
    final index = _files.indexWhere((f) => f.path == file.path);
    return index < 0 ? null : resultFor(index);
  }

  /// Images have no frame rate, so the FPS toggle is hidden for them.
  bool get showFpsOption => _files.any((f) => f.isVideo);

  /// Probed dimensions of the first selected file, once ffprobe has answered.
  MediaInfo? get sourceInfo => _sourceInfo;

  /// Human-readable output size estimate for the upscale panel.
  String get dimensionEstimate {
    final info = _sourceInfo;
    if (!_options.upscale) return 'Aktifkan Upscale untuk melihat estimasi.';
    if (info == null) {
      return hasFiles
          ? 'Membaca dimensi…'
          : 'Pilih file untuk melihat estimasi dimensi.';
    }
    final scale = _options.upscaleScale;
    final source = '${info.width}×${info.height}';
    if (scale == 1) return '$source → $source (enhance saja, resolusi tetap)';
    return '$source → ${info.width * scale}×${info.height * scale}';
  }

  bool get canProcess => hasFiles && _options.hasAnyOp && !isRunning;

  /// The selected AI model is unavailable, so processing would fail.
  bool get esrganMissing =>
      _options.useEsrgan &&
      (!_capabilities.esrgan || !isModelInstalled(_options.upscaleModel));

  /// Whether [model] can actually run here — the binary plus its weights.
  bool isModelInstalled(UpscaleModel model) {
    final name = model.ncnnName;
    if (name == null) return true; // Lanczos needs nothing.
    return _capabilities.esrgan && Binaries.hasEsrganModel(name);
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    final documents = await getApplicationDocumentsDirectory();
    _defaultOutputDir = p.join(documents.path, 'LabScale');
    _outputDir = _defaultOutputDir;
    await Directory(_outputDir).create(recursive: true);

    final temp = await getTemporaryDirectory();
    _tempDir = p.join(temp.path, 'labscale');
    await Directory(_tempDir).create(recursive: true);
    _thumbnailer = Thumbnailer(cacheDir: p.join(_tempDir, 'thumbs'));

    _prefs = await SharedPreferences.getInstance();
    await _probeCapabilities();
    _restorePreferences();
    await _restoreOutputDir();
    notifyListeners();
  }

  /// Reinstates a folder the user picked previously.
  ///
  /// A stored folder can be gone by the next launch — an unmounted volume, a
  /// renamed directory — so it is only adopted if it can actually be created.
  /// Otherwise the default quietly takes over rather than every job failing.
  Future<void> _restoreOutputDir() async {
    final stored = _prefs?.getString(_kOutputDir);
    if (stored == null || stored == _defaultOutputDir) return;
    try {
      await Directory(stored).create(recursive: true);
      _outputDir = stored;
    } on FileSystemException {
      await _prefs?.remove(_kOutputDir);
    }
  }

  Future<void> _probeCapabilities() async {
    final support = await FfmpegRunner.encoders();
    _capabilities = Capabilities(
      ffmpeg: Binaries.isAvailable(Tool.ffmpeg),
      esrgan: EsrganRunner.isAvailable,
      rife: RifeRunner.isAvailable,
      encoderSummary: Binaries.isAvailable(Tool.ffmpeg)
          ? support.summary
          : 'FFmpeg tidak ditemukan',
    );
  }

  /// Re-probes after the user drops binaries into `bin/` without restarting.
  Future<void> refreshCapabilities() async {
    Binaries.invalidate();
    // A newly-dropped ffmpeg is a different build with a different encoder set,
    // so the probed encoder list has to go too.
    FfmpegRunner.invalidateEncoderCache();
    await _probeCapabilities();
    notifyListeners();
  }

  void _restorePreferences() {
    final prefs = _prefs;
    if (prefs == null) return;

    // Fall back to the best model the machine can actually run.
    final storedModel = prefs.getString(_kUpscaleModel);
    var model = UpscaleModel.fromId(storedModel);
    // A stored model whose weights are not on this machine would leave the
    // dropdown showing a disabled entry the user cannot re-pick, so fall back
    // the same way a first run does.
    if (storedModel == null || !isModelInstalled(model)) {
      // Falling back on the binary's presence alone would just pick another
      // model whose weights are missing, landing back in the same state.
      // x4plus first because it is what the default fetch installs.
      model = [
        UpscaleModel.realesrganX4Plus,
        ...UpscaleModel.values.where((m) => m.isAi),
      ].firstWhere(isModelInstalled, orElse: () => UpscaleModel.lanczos);
    }

    // A stored 'rife' must not survive onto a machine without RIFE: the
    // dropdown disables that entry, which would leave it showing a selection
    // the user cannot re-pick. The pipeline falls back either way.
    final storedEngine = prefs.getString(_kInterpEngine);
    final engine = (storedEngine == null || !_capabilities.rife)
        ? (_capabilities.rife ? InterpEngine.rife : InterpEngine.ffmpeg)
        : InterpEngine.fromId(storedEngine);

    _options = ProcessOptions(
      upscaleModel: model,
      upscaleScale: prefs.getInt(_kScale) ?? 2,
      interpEngine: engine,
      sharpness: prefs.getDouble(_kSharpness) ?? 0.3,
      quality: Quality.fromId(prefs.getString(_kQuality)),
      codec: VideoCodec.fromId(prefs.getString(_kCodec)),
    );
  }

  Future<void> _persistPreferences() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setString(_kUpscaleModel, _options.upscaleModel.id);
    await prefs.setInt(_kScale, _options.upscaleScale);
    await prefs.setString(_kInterpEngine, _options.interpEngine.id);
    await prefs.setDouble(_kSharpness, _options.sharpness);
    await prefs.setString(_kQuality, _options.quality.id);
    await prefs.setString(_kCodec, _options.codec.id);
  }

  // ── Selection ─────────────────────────────────────────────────────────────

  void setFiles(List<MediaFile> files) {
    // run() iterates _files against a length captured up front, so swapping the
    // list mid-job would either skip files or blow up with a RangeError.
    if (isRunning) return;
    _files = List.unmodifiable(files);
    _results = const [];
    _logLines = const [];
    _errorMessage = null;
    _phase = JobPhase.idle;
    _statusText = '';
    _sourceInfo = null;
    _activeIndex = null;
    _fileProgress = null;
    _previewFile = null;

    // FPS boost is meaningless for a photo-only selection.
    if (!showFpsOption && _options.fpsBoost) {
      _options = _options.copyWith(fpsBoost: false);
    }
    notifyListeners();
    unawaited(_probeSource());
  }

  /// Reads the first file's dimensions so the upscale panel can show a real
  /// before/after estimate. Best-effort: a failure just leaves it blank.
  Future<void> _probeSource() async {
    final file = firstFile;
    if (file == null) return;
    final info = await FfmpegRunner.probe(file.path);
    // The user may have swapped selection while ffprobe was running.
    if (firstFile?.path != file.path) return;
    _sourceInfo = info;
    notifyListeners();
  }

  void addPaths(Iterable<String> paths) {
    if (isRunning) {
      _errorMessage = 'Sedang memproses — tunggu sampai selesai';
      notifyListeners();
      return;
    }
    final found = MediaFile.collectFromPaths(paths);
    if (found.isEmpty) {
      _errorMessage = 'Tidak ada file yang didukung di lokasi tersebut';
      notifyListeners();
      return;
    }
    // Appends. The buttons say "Tambah" and dropping onto a filled grid reads
    // as adding to it, so replacing the queue would quietly discard work the
    // user had already lined up. Duplicates are ignored rather than queued
    // twice.
    final merged = <MediaFile>[..._files];
    final seen = _files.map((f) => f.path).toSet();
    for (final file in found) {
      if (seen.add(file.path)) merged.add(file);
    }
    setFiles(merged);
  }

  void clearSelection() {
    if (isRunning) return;
    _files = const [];
    _results = const [];
    _logLines = const [];
    _errorMessage = null;
    _phase = JobPhase.idle;
    _statusText = '';
    _progress = null;
    _sourceInfo = null;
    _activeIndex = null;
    _fileProgress = null;
    _previewFile = null;
    notifyListeners();
  }

  /// Opens [file] in the preview pane, or closes the pane when null.
  void selectForPreview(MediaFile? file) {
    _previewFile = (file != null && file.path == _previewFile?.path) ? null : file;
    notifyListeners();
  }

  /// Drops one file from the queue. Ignored mid-run, like every other
  /// selection change.
  void removeAt(int index) {
    if (isRunning) return;
    if (index < 0 || index >= _files.length) return;
    setFiles([..._files]..removeAt(index));
  }

  /// The folder results are written to, and where it started.
  String get defaultOutputDir => _defaultOutputDir;
  bool get usesDefaultOutputDir => _outputDir == _defaultOutputDir;

  /// Points output at [dir]. Rejected while a job is running, since the
  /// pipeline already holds the old path.
  Future<void> setOutputDir(String dir) async {
    if (isRunning) return;
    try {
      await Directory(dir).create(recursive: true);
    } on FileSystemException {
      _errorMessage = 'Tidak bisa menulis ke folder itu';
      notifyListeners();
      return;
    }
    _outputDir = dir;
    await _prefs?.setString(_kOutputDir, dir);
    notifyListeners();
  }

  Future<void> resetOutputDir() async {
    if (isRunning) return;
    _outputDir = _defaultOutputDir;
    await _prefs?.remove(_kOutputDir);
    notifyListeners();
  }

  void dismissError() {
    _errorMessage = null;
    notifyListeners();
  }

  // ── Option mutation ───────────────────────────────────────────────────────

  void updateOptions(ProcessOptions Function(ProcessOptions) transform) {
    _options = transform(_options);
    unawaited(_persistPreferences());
    notifyListeners();
  }

  // ── Processing ────────────────────────────────────────────────────────────

  Future<void> run() async {
    if (!canProcess) return;
    if (!_capabilities.ffmpeg) {
      _errorMessage = ToolMissingException(Tool.ffmpeg).installHint;
      notifyListeners();
      return;
    }

    _phase = JobPhase.running;
    _progress = null;
    _fileProgress = null;
    _activeIndex = null;
    _logLines = const [];
    _results = const [];
    _errorMessage = null;
    notifyListeners();

    final pipeline = Pipeline(outputDir: _outputDir, tempDir: _tempDir);
    final collected = <JobResult>[];
    // Snapshot the queue: selection is locked while running, but reading from a
    // local list makes that guarantee independent of the UI.
    final queue = List<MediaFile>.of(_files);
    final total = queue.length;

    try {
      for (var i = 0; i < total; i++) {
        final file = queue[i];
        _activeIndex = i;
        _fileProgress = null;
        _statusText = total == 1
            ? 'Memproses ${file.displayName}…'
            : '[${i + 1}/$total] ${file.displayName}';
        notifyListeners();

        final reporter = JobReporter();
        _attachReporter(reporter, index: i, total: total);
        try {
          collected.add(await pipeline.process(
            file: file,
            rawOptions: _options,
            reporter: reporter,
          ));
        } catch (e) {
          // One unexpected failure must not abandon the rest of the batch, and
          // every file needs a result: statusFor reads position in [results],
          // so a gap would leave this file and every file after it drawn as
          // still queued long after the run stopped.
          collected.add(JobResult(
            sourceName: file.displayName,
            outputPath: '',
            error: '$e',
          ));
        } finally {
          await _detachReporter(reporter);
        }

        _results = List.unmodifiable(collected);
        notifyListeners();
      }

      final ok = collected.where((r) => r.isSuccess).length;
      _statusText = '$ok/$total berhasil diproses';
    } catch (e) {
      // Pipeline.process handles its own expected failures; anything reaching
      // here is unexpected (a ProcessException from an unlaunchable binary, a
      // filesystem error). Without this the phase would stay `running` forever
      // and the Process button would never re-enable.
      _errorMessage = 'Proses berhenti tak terduga: $e';
      _statusText = 'Berhenti karena error';
    } finally {
      _phase = JobPhase.done;
      _progress = 1.0;
      _activeIndex = null;
      _fileProgress = null;
      _results = List.unmodifiable(collected);
      // Deliberately does not open anything: the viewer now takes the whole
      // window, and having that appear unbidden the moment a batch ends would
      // yank the user out of the grid they are watching.
      notifyListeners();
    }
  }

  void _attachReporter(JobReporter reporter, {required int index, required int total}) {
    _logSub = reporter.logs.listen((line) {
      _logLines = [..._logLines, line];
      notifyListeners();
    });
    _progressSub = reporter.progress.listen((fraction) {
      // The grid wants this file's own fraction; the overall bar wants it
      // spread across this file's slice of the queue.
      _fileProgress = fraction;
      _progress = fraction == null ? null : (index + fraction) / total;
      notifyListeners();
    });
  }

  Future<void> _detachReporter(JobReporter reporter) async {
    await _logSub?.cancel();
    await _progressSub?.cancel();
    _logSub = null;
    _progressSub = null;
    await reporter.close();
  }

  /// Reveals [path] (or the output folder) in Explorer / Finder.
  Future<void> revealInFileManager([String? path]) async {
    final target = path ?? _outputDir;
    if (!Directory(target).existsSync() && !File(target).existsSync()) return;
    try {
      if (Platform.isWindows) {
        await Process.start('explorer', [target.replaceAll('/', r'\')]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [
          if (File(target).existsSync()) '-R',
          target,
        ]);
      } else {
        await Process.start('xdg-open', [target]);
      }
    } on ProcessException {
      _errorMessage = 'Gagal membuka folder';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _progressSub?.cancel();
    super.dispose();
  }
}
