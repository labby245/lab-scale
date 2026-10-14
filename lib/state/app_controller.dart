/// Central app state: file selection, options, capability probing, and the
/// currently running job.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_log.dart';
import '../core/binaries.dart';
import '../core/esrgan_runner.dart';
import '../core/ffmpeg_runner.dart';
import '../core/gpu_probe.dart';
import '../core/job_log.dart';
import '../core/model_store.dart';
import '../core/pipeline.dart';
import '../core/rife_runner.dart';
import '../core/thumbnailer.dart';
import '../core/update_check.dart';
import '../l10n/strings.dart';
import '../models/media_file.dart';
import '../models/process_options.dart';

/// Which external tools are present on this machine.
class Capabilities {
  const Capabilities({
    this.ffmpeg = false,
    this.esrgan = false,
    this.rife = false,
    this.encoders,
    this.esrganIssue,
    this.rifeIssue,
  });

  final bool ffmpeg;
  final bool esrgan;
  final bool rife;

  /// Why a tool that is installed still cannot run here (no Vulkan GPU), or
  /// null. Lets the UI say "your GPU" instead of "reinstall the app".
  final GpuProbeResult? esrganIssue;
  final GpuProbeResult? rifeIssue;

  /// Verified encoders, or null until the probe has answered.
  final EncoderSupport? encoders;

  /// One line for the status bar and the codec hint, in [s].
  String encoderSummary(S s) {
    final support = encoders;
    if (support == null) return s.loading;
    if (!ffmpeg) return s.ffmpegNotFound;
    return support.summary(s);
  }

  int get readyCount => [esrgan, rife].where((v) => v).length;
  int get totalCount => 2;
}

enum JobPhase { idle, running, done }

/// Where a single queued file stands, for the selection grid.
enum FileStatus { queued, running, done, failed, cancelled }

/// Where results go until the user picks a folder: `<home>/LabScale`.
///
/// Not Documents. On many PCs Documents is redirected into OneDrive, and on
/// Macs with "Desktop & Documents" in iCloud it syncs too — so multi-gigabyte
/// results would quietly upload to the cloud, the opposite of what a "your
/// files stay on your computer" app should do. The home folder is synced by
/// neither by default. Documents remains the fallback when no home is known.
@visibleForTesting
String defaultOutputDirFor(
  Map<String, String> env, {
  required bool isWindows,
  required String documentsFallback,
}) {
  final home = isWindows ? env['USERPROFILE'] : env['HOME'];
  final base = (home == null || home.isEmpty) ? documentsFallback : home;
  return p.join(base, 'LabScale');
}

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
    Capabilities capabilities = const Capabilities(),
    ProcessOptions options = const ProcessOptions(),
    String outputDir = '',
    String tempDir = '',
  }) {
    _capabilities = capabilities;
    _options = options;
    _outputDir = outputDir;
    _tempDir = tempDir;
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
  static const _kLanguage = 'pref_language';

  // ── State ─────────────────────────────────────────────────────────────────
  List<MediaFile> _files = const [];
  ProcessOptions _options = const ProcessOptions();
  Capabilities _capabilities = const Capabilities();
  JobPhase _phase = JobPhase.idle;
  double? _progress;
  bool _cancelRequested = false;
  bool _stoppedByError = false;
  JobReporter? _activeReporter;
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
  String _version = '';
  AppLog? _appLog;
  ModelStore? _modelStore;
  final Map<UpscaleModel, double?> _downloads = {};
  AvailableUpdate? _update;
  bool _updateDismissed = false;

  SharedPreferences? _prefs;

  /// The interface language. Separate from [notifyListeners] so a language
  /// switch rebuilds the app root once, instead of the root rebuilding on
  /// every progress tick.
  final ValueNotifier<S> language = ValueNotifier<S>(S.current);
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

  /// True between a cancel request and the batch actually stopping.
  bool get isCancelling => isRunning && _cancelRequested;

  /// One line under the progress bar describing where the batch stands.
  String statusText(S s) {
    if (isRunning) {
      final index = _activeIndex;
      if (index == null || index >= _files.length) return '';
      final name = _files[index].displayName;
      return _files.length == 1
          ? s.processingFile(name)
          : '[${index + 1}/${_files.length}] $name';
    }
    if (_phase != JobPhase.done) return '';
    if (_stoppedByError) return s.stoppedOnError;
    final ok = _results.where((r) => r.isSuccess).length;
    return _results.any((r) => r.cancelled)
        ? s.succeededCancelled(ok, _results.length)
        : s.succeeded(ok, _results.length);
  }

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

  /// The running version, e.g. "2.1.0". Empty until [initialize] has run.
  String get version => _version;

  /// The persistent log file, for the "open log folder" action.
  String? get logPath => _appLog?.path;

  /// A newer release, while the user has not dismissed the banner.
  AvailableUpdate? get pendingUpdate => _updateDismissed ? null : _update;

  /// Where [index] stands in the queue.
  ///
  /// Results are appended in queue order, so a file has a result exactly when
  /// its index is below the number collected so far.
  FileStatus statusFor(int index) {
    if (index < _results.length) {
      final result = _results[index];
      if (result.cancelled) return FileStatus.cancelled;
      return result.isSuccess ? FileStatus.done : FileStatus.failed;
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
  String dimensionEstimate(S s) {
    final info = _sourceInfo;
    if (!_options.upscale) return s.estimateNeedsUpscale;
    if (info == null) {
      return hasFiles ? s.estimateReading : s.estimateNeedsFile;
    }
    final scale = _options.upscaleScale;
    final source = '${info.width}×${info.height}';
    if (scale == 1) return s.estimateEnhanceOnly(source);
    return '$source → ${info.width * scale}×${info.height * scale}';
  }

  /// A selected model whose weights are missing would fail every file, so
  /// the button waits for the download instead.
  bool get canProcess =>
      hasFiles && _options.hasAnyOp && !isRunning && !esrganMissing;

  /// The selected AI model is unavailable, so processing would fail.
  bool get esrganMissing =>
      _options.useEsrgan &&
      (!_capabilities.esrgan || !isModelInstalled(_options.upscaleModel));

  /// Download progress for [model]: absent when not downloading, null while
  /// the size is still unknown, otherwise 0–1.
  bool isDownloading(UpscaleModel model) => _downloads.containsKey(model);
  double? downloadProgress(UpscaleModel model) => _downloads[model];

  /// Fetches [model]'s weights into the per-user models folder. Errors arrive
  /// as a snackbar; the dropdown simply keeps offering the download.
  Future<void> downloadModel(UpscaleModel model) async {
    final entry = downloadableFor(model);
    final store = _modelStore;
    if (entry == null || store == null || isDownloading(model)) return;
    _downloads[model] = 0;
    notifyListeners();
    try {
      await store.download(entry, onProgress: (fraction) {
        _downloads[model] = fraction;
        notifyListeners();
      });
      _appLog?.write('model downloaded: ${model.id}');
    } on ModelDownloadException catch (e) {
      _errorMessage = S.current.downloadFailed(e);
      _appLog?.write('model download failed: ${model.id}: $e');
    } finally {
      _downloads.remove(model);
      notifyListeners();
    }
  }

  /// Asks GitHub whether a newer release exists. [manual] re-shows a banner
  /// the user dismissed earlier — they asked, so they want the answer.
  Future<UpdateStatus> checkForUpdates({bool manual = false}) async {
    if (_version.isEmpty) return UpdateStatus.failed;
    final result = await UpdateChecker().check(_version);
    if (result.status == UpdateStatus.available) {
      _update = result.update;
      if (manual) _updateDismissed = false;
      notifyListeners();
    }
    return result.status;
  }

  void dismissUpdate() {
    _updateDismissed = true;
    notifyListeners();
  }

  /// The upscale dropdown's entries. Lanczos only appears where no AI model
  /// can run — on a PC without Vulkan it is the one upscaler that works, and
  /// anywhere else it would only be a worse choice to stumble on.
  List<UpscaleModel> get offeredModels {
    final aiRuns =
        UpscaleModel.values.any((m) => m.isAi && isModelInstalled(m));
    return [
      for (final m in UpscaleModel.values)
        if (m.isAi || !aiRuns) m,
    ];
  }

  /// Whether [model] can actually run here — the binary plus its weights.
  bool isModelInstalled(UpscaleModel model) {
    final name = model.ncnnName;
    if (name == null) return true; // Lanczos needs nothing.
    return _capabilities.esrgan &&
        Binaries.hasEsrganModel(name, scales: model.nativeScales);
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    _defaultOutputDir = defaultOutputDirFor(
      Platform.environment,
      isWindows: Platform.isWindows,
      documentsFallback: (await getApplicationDocumentsDirectory()).path,
    );
    _outputDir = _defaultOutputDir;
    await Directory(_outputDir).create(recursive: true);

    final temp = await getTemporaryDirectory();
    _tempDir = p.join(temp.path, 'labscale');
    await Directory(_tempDir).create(recursive: true);
    final staleRemoved = Pipeline.cleanStaleWorkDirs(_tempDir);
    _thumbnailer = Thumbnailer(cacheDir: p.join(_tempDir, 'thumbs'));

    // Downloaded weights and the log live in the per-user support folder:
    // writable, and outside the app bundle whose signature must not change.
    final support = await getApplicationSupportDirectory();
    Binaries.userModelsDir = p.join(support.path, 'models');
    _modelStore = ModelStore(Binaries.userModelsDir!);
    _appLog = AppLog(p.join(support.path, 'logs'))..open();

    try {
      _version = (await PackageInfo.fromPlatform()).version;
    } on Object {
      _version = '';
    }

    _prefs = await SharedPreferences.getInstance();
    _restoreLanguage();
    await _probeCapabilities();
    _restorePreferences();
    await _restoreOutputDir();
    _logEnvironment();
    if (staleRemoved > 0) {
      _appLog?.write('removed $staleRemoved stale work folder(s) from temp');
    }
    notifyListeners();

    // In the background: a slow or absent network must not delay the window.
    unawaited(checkForUpdates());
  }

  /// One line per launch saying what this session runs on — the first thing
  /// anyone reading a bug report needs.
  void _logEnvironment() {
    final caps = _capabilities;
    _appLog?.write(
      'LabScale $_version · ${Platform.operatingSystem} '
      '${Platform.operatingSystemVersion} · ${Platform.localeName}',
    );
    _appLog?.write(
      'tools: ffmpeg=${caps.ffmpeg} esrgan=${caps.esrgan} rife=${caps.rife} '
      '· encoders: ${caps.encoderSummary(S.en)}',
    );
    for (final (name, issue) in [
      ('esrgan', caps.esrganIssue),
      ('rife', caps.rifeIssue),
    ]) {
      if (issue != null) {
        _appLog?.write('$name unusable: ${issue.failure.name} ${issue.detail}');
      }
    }
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
    // Both at once: the GPU probe is a second or so of real ncnn work, the
    // encoder probe a few trial encodes, and the window waits on both.
    final results = await Future.wait([
      FfmpegRunner.encoders(),
      probeGpuTools(_tempDir),
    ]);
    _capabilities = Capabilities(
      ffmpeg: Binaries.isAvailable(Tool.ffmpeg),
      esrgan: EsrganRunner.isAvailable,
      rife: RifeRunner.isAvailable,
      encoders: results.first as EncoderSupport,
      esrganIssue: Binaries.unusableReason(Tool.realesrgan),
      rifeIssue: Binaries.unusableReason(Tool.rife),
    );
  }

  /// Starts in the language last chosen, or the system's on first launch.
  void _restoreLanguage() {
    final stored = _prefs?.getString(_kLanguage);
    final strings = switch (stored) {
      'en' => S.en,
      'id' => S.id,
      _ => S.forLocale(Platform.localeName),
    };
    S.current = strings;
    language.value = strings;
  }

  Future<void> setLanguage(S strings) async {
    S.current = strings;
    language.value = strings;
    await _prefs?.setString(_kLanguage, strings.code);
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
    // Lanczos is hidden wherever AI runs, so a stored Lanczos there would be
    // a selection the dropdown no longer shows.
    if (storedModel == null ||
        !isModelInstalled(model) ||
        !offeredModels.contains(model)) {
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
      _errorMessage = S.current.busy;
      notifyListeners();
      return;
    }
    final found = MediaFile.collectFromPaths(paths);
    if (found.isEmpty) {
      _errorMessage = S.current.noSupportedFiles;
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
    _progress = null;
    _sourceInfo = null;
    _activeIndex = null;
    _fileProgress = null;
    _previewFile = null;
    notifyListeners();
  }

  /// Opens [file] in the preview pane, or closes the pane when null.
  void selectForPreview(MediaFile? file) {
    final same = file != null && file.path == _previewFile?.path;
    _previewFile = same ? null : file;
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
      _errorMessage = S.current.cannotWriteFolder;
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
    _cancelRequested = false;
    _stoppedByError = false;
    _progress = null;
    _fileProgress = null;
    _activeIndex = null;
    _logLines = const [];
    _results = const [];
    _errorMessage = null;
    notifyListeners();

    final pipeline = Pipeline(outputDir: _outputDir, tempDir: _tempDir);
    _appLog?.write(
      'run: ${_files.length} file(s) · upscale=${_options.upscale} '
      'model=${_options.upscaleModel.id} scale=${_options.upscaleScale} '
      'fps=${_options.fpsBoost} engine=${_options.interpEngine.id} '
      'quality=${_options.quality.id} codec=${_options.codec.id}',
    );
    final collected = <JobResult>[];
    // Snapshot the queue: selection is locked while running, but reading from a
    // local list makes that guarantee independent of the UI.
    final queue = List<MediaFile>.of(_files);
    final total = queue.length;

    try {
      for (var i = 0; i < total; i++) {
        final file = queue[i];
        // Everything not yet started when the user cancelled is recorded as
        // cancelled rather than dropped: statusFor reads position in
        // [results], and the grid should say what became of every file.
        if (_cancelRequested) {
          collected.add(JobResult.cancelled(file.displayName));
          continue;
        }
        _activeIndex = i;
        _fileProgress = null;
        notifyListeners();

        final reporter = JobReporter();
        final linesBefore = _logLines;
        _activeReporter = reporter;
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
          _activeReporter = null;
          await _detachReporter(reporter);
          // The streams feed the panel live; this makes the end state
          // exact. history is filled synchronously in log(), so it holds
          // every line the job wrote no matter how delivery and the
          // subscription teardown happened to interleave.
          _logLines = [...linesBefore, ...reporter.history];
        }

        final result = collected.last;
        _appLog?.write(
          result.cancelled
              ? 'cancelled: ${result.sourceName}'
              : result.isSuccess
                  ? 'ok: ${result.sourceName} -> ${result.outputName}'
                  : 'FAILED: ${result.sourceName}: ${result.error}',
        );
        _results = List.unmodifiable(collected);
        notifyListeners();
      }
    } catch (e) {
      // Pipeline.process handles its own expected failures; anything reaching
      // here is unexpected (a ProcessException from an unlaunchable binary, a
      // filesystem error). Without this the phase would stay `running` forever
      // and the Process button would never re-enable.
      _errorMessage = S.current.unexpectedStop(e);
      _stoppedByError = true;
      _appLog?.write('UNEXPECTED: $e');
    } finally {
      _phase = JobPhase.done;
      _cancelRequested = false;
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

  /// Stops the batch: the file in progress is abandoned (its tools are
  /// killed and its partial output deleted) and the rest are not started.
  void cancel() {
    if (!isRunning || _cancelRequested) return;
    _cancelRequested = true;
    _activeReporter?.cancel();
    notifyListeners();
  }

  void _attachReporter(
    JobReporter reporter, {
    required int index,
    required int total,
  }) {
    _logSub = reporter.logs.listen((line) {
      _appLog?.write('  $line');
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
    // Close first: the streams deliver asynchronously, so the job's last
    // lines ("Gambar tersimpan.", "Enkode selesai.") are still queued when
    // process() returns. Closing flushes them to the listeners; cancelling
    // first threw them away, and every log ended one or two lines short.
    await reporter.close();
    await _logSub?.cancel();
    await _progressSub?.cancel();
    _logSub = null;
    _progressSub = null;
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
      _errorMessage = S.current.cannotOpenFolder;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _progressSub?.cancel();
    language.dispose();
    unawaited(_appLog?.close());
    super.dispose();
  }
}
