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

class AppController extends ChangeNotifier {
  AppController();

  // ── Preference keys ───────────────────────────────────────────────────────
  static const _kUpscaleModel = 'pref_upscale_model';
  static const _kCodec = 'pref_codec';
  static const _kInterpEngine = 'pref_interp_engine';
  static const _kQuality = 'pref_quality';
  static const _kSharpness = 'pref_sharpness';
  static const _kScale = 'pref_upscale_scale';

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
  String _tempDir = '';
  MediaInfo? _sourceInfo;

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
  bool get esrganMissing => _options.useEsrgan && !_capabilities.esrgan;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    final documents = await getApplicationDocumentsDirectory();
    _outputDir = p.join(documents.path, 'LabScale');
    await Directory(_outputDir).create(recursive: true);

    final temp = await getTemporaryDirectory();
    _tempDir = p.join(temp.path, 'labscale');
    await Directory(_tempDir).create(recursive: true);

    _prefs = await SharedPreferences.getInstance();
    await _probeCapabilities();
    _restorePreferences();
    notifyListeners();
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
    await _probeCapabilities();
    notifyListeners();
  }

  void _restorePreferences() {
    final prefs = _prefs;
    if (prefs == null) return;

    // Fall back to the best model the machine can actually run.
    final storedModel = prefs.getString(_kUpscaleModel);
    var model = UpscaleModel.fromId(storedModel);
    if (storedModel == null) {
      model = _capabilities.esrgan
          ? UpscaleModel.realesrganX4Plus
          : UpscaleModel.lanczos;
    }

    final storedEngine = prefs.getString(_kInterpEngine);
    var engine = InterpEngine.fromId(storedEngine);
    if (storedEngine == null) {
      engine = _capabilities.rife ? InterpEngine.rife : InterpEngine.ffmpeg;
    }

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
    _files = List.unmodifiable(files);
    _results = const [];
    _logLines = const [];
    _errorMessage = null;
    _phase = JobPhase.idle;
    _statusText = '';
    _sourceInfo = null;

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
    final found = MediaFile.collectFromPaths(paths);
    if (found.isEmpty) {
      _errorMessage = 'Tidak ada file yang didukung di lokasi tersebut';
      notifyListeners();
      return;
    }
    setFiles(found);
  }

  void clearSelection() {
    _files = const [];
    _results = const [];
    _logLines = const [];
    _errorMessage = null;
    _phase = JobPhase.idle;
    _statusText = '';
    _progress = null;
    _sourceInfo = null;
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
    _logLines = const [];
    _results = const [];
    _errorMessage = null;
    notifyListeners();

    final pipeline = Pipeline(outputDir: _outputDir, tempDir: _tempDir);
    final collected = <JobResult>[];
    final total = _files.length;

    for (var i = 0; i < total; i++) {
      final file = _files[i];
      _statusText = total == 1
          ? 'Memproses ${file.displayName}…'
          : '[${i + 1}/$total] ${file.displayName}';
      notifyListeners();

      final reporter = JobReporter();
      _attachReporter(reporter, index: i, total: total);

      final result = await pipeline.process(
        file: file,
        options: _options,
        reporter: reporter,
      );
      collected.add(result);
      await _detachReporter(reporter);

      _results = List.unmodifiable(collected);
      notifyListeners();
    }

    _phase = JobPhase.done;
    _progress = 1.0;
    final ok = collected.where((r) => r.isSuccess).length;
    _statusText = '$ok/$total berhasil diproses';
    notifyListeners();
  }

  void _attachReporter(JobReporter reporter, {required int index, required int total}) {
    _logSub = reporter.logs.listen((line) {
      _logLines = [..._logLines, line];
      notifyListeners();
    });
    _progressSub = reporter.progress.listen((fraction) {
      // Spread each file's progress across its slice of the overall bar.
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
