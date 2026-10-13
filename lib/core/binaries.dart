/// Locates the external CLI tools LabScale drives.
///
/// Lookup order for every tool:
///   1. the bundled `bin/` folder shipped next to the executable
///   2. the same folder as the executable
///   3. whatever the OS `PATH` resolves
///
/// On Windows the bundled folder is `<exeDir>/bin`; on macOS the app bundle
/// puts it at `<Foo.app>/Contents/Resources/bin`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../l10n/strings.dart';

enum Tool {
  ffmpeg('ffmpeg'),
  ffprobe('ffprobe'),
  realesrgan('realesrgan-ncnn-vulkan'),
  rife('rife-ncnn-vulkan');

  const Tool(this.baseName);
  final String baseName;

  String get fileName => Platform.isWindows ? '$baseName.exe' : baseName;
}

class Binaries {
  Binaries._();

  static final Map<Tool, String?> _cache = {};

  /// Directories that may hold bundled binaries, most specific first.
  static List<String> get searchDirs {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final dirs = <String>[p.join(exeDir, 'bin'), exeDir];
    if (Platform.isMacOS) {
      // <Foo.app>/Contents/MacOS/foo -> <Foo.app>/Contents/Resources/bin
      final resources = p.normalize(p.join(exeDir, '..', 'Resources', 'bin'));
      dirs.insert(0, resources);
    }
    // Running from `flutter run` puts the exe deep inside build/; fall back to
    // a `bin/` folder at the project root so development works unbundled.
    final devBin = _devBinDir();
    if (devBin != null) dirs.add(devBin);
    return dirs;
  }

  static String? _devBinDir() {
    var dir = Directory.current;
    for (var i = 0; i < 5; i++) {
      final candidate = Directory(p.join(dir.path, 'bin'));
      if (candidate.existsSync()) return candidate.path;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  /// Absolute path to [tool], or null when it cannot be found anywhere.
  static String? resolve(Tool tool) {
    if (_cache.containsKey(tool)) return _cache[tool];

    for (final dir in searchDirs) {
      final candidate = p.join(dir, tool.fileName);
      if (File(candidate).existsSync()) {
        _cache[tool] = candidate;
        return candidate;
      }
    }

    final onPath = _which(tool.fileName);
    _cache[tool] = onPath;
    return onPath;
  }

  /// Path to [tool], throwing a user-facing message when it is missing.
  static String require(Tool tool) {
    final path = resolve(tool);
    if (path == null) {
      throw ToolMissingException(tool);
    }
    return path;
  }

  static bool isAvailable(Tool tool) => resolve(tool) != null;

  /// Candidate model folder names per tool, best first.
  ///
  /// These must stay tool-specific: Real-ESRGAN and RIFE are normally unpacked
  /// side by side into the same `bin/`, so a shared lookup would hand RIFE the
  /// `models/` folder that belongs to Real-ESRGAN.
  static const Map<Tool, List<String>> _modelDirNames = {
    Tool.realesrgan: ['models'],
    // Newest first. Every RIFE model past v4.6 needs a newer ncnn build than
    // nihui's 2022 release — that binary fails them all with "layer MemoryData
    // not exists or registered" — so `tools/fetch_binaries` fetches the
    // matching pair. An install that only has the old model still works: the
    // list simply falls through to it.
    Tool.rife: [
      'rife-v4.25',
      'rife-v4.15',
      'rife-v4.6',
      'rife-v4',
      'rife-anime',
      'rife-v3.1',
      'rife-v2.4',
      'rife',
    ],
  };

  /// Directory holding the ncnn `.param`/`.bin` model files for [tool], or null
  /// when the tool ships no models or none can be found.
  static String? modelsDir(Tool tool) {
    final binary = resolve(tool);
    if (binary == null) return null;
    final base = p.dirname(binary);

    for (final name in _modelDirNames[tool] ?? const <String>[]) {
      final dir = Directory(p.join(base, name));
      if (dir.existsSync()) return dir.path;
    }
    // Some builds drop the weights loose next to the executable.
    if (File(p.join(base, 'flownet.bin')).existsSync()) return base;
    return null;
  }

  /// Writable per-user folder for weights downloaded inside the app (see
  /// `ModelStore`). Set once at startup; null in tests and before then.
  static String? userModelsDir;

  /// Whether the Real-ESRGAN weights for [ncnnName] are actually installed,
  /// either bundled or downloaded.
  ///
  /// The model list is fixed in the UI so people can see what exists, but only
  /// some of it ships in the installer — the rest is downloaded on demand.
  /// Without this the dropdown would happily offer a model whose weights are
  /// absent, and the job would only fail once it had been queued.
  static bool hasEsrganModel(String ncnnName, {Set<int> scales = const {}}) =>
      esrganModelsDirFor(ncnnName, scales: scales) != null;

  /// The folder holding [ncnnName]'s weights, to pass as `-m`.
  ///
  /// realesrgan-ncnn-vulkan takes exactly one models folder per run, and
  /// downloaded weights cannot live beside the bundled ones (inside the app
  /// bundle, writing would break the code signature) — so the folder is chosen
  /// per model. The user's folder is checked first so a re-download can
  /// replace a damaged bundled copy.
  static String? esrganModelsDirFor(
    String ncnnName, {
    Set<int> scales = const {},
  }) {
    for (final dir in [userModelsDir, modelsDir(Tool.realesrgan)]) {
      if (dir == null || !Directory(dir).existsSync()) continue;
      if (_hasModelIn(dir, ncnnName, scales)) return dir;
    }
    return null;
  }

  static bool _hasModelIn(String dir, String ncnnName, Set<int> scales) {
    bool pairExists(String stem) =>
        File(p.join(dir, '$stem.param')).existsSync() &&
        File(p.join(dir, '$stem.bin')).existsSync();

    // Most models are one file pair. AnimeVideoV3 instead ships one pair per
    // scale — realesr-animevideov3-x2/-x3/-x4 — and the binary appends the
    // suffix itself, so looking only for the bare name would report a model
    // that works perfectly well as missing.
    //
    // Every declared scale must be present, not merely one of them: this
    // check exists so the dropdown never offers a model that fails once the
    // job is already queued, and a half-fetched set would do exactly that the
    // moment the user picked the missing scale.
    if (pairExists(ncnnName)) return true;
    if (scales.isEmpty) return false;
    return scales.every((scale) => pairExists('$ncnnName-x$scale'));
  }

  static String? _which(String fileName) {
    final locator = Platform.isWindows ? 'where' : 'which';
    try {
      final result = Process.runSync(locator, [fileName]);
      if (result.exitCode != 0) return null;
      final first = (result.stdout as String)
          .split(RegExp(r'[\r\n]+'))
          .map((s) => s.trim())
          .firstWhere((s) => s.isNotEmpty, orElse: () => '');
      return first.isEmpty ? null : first;
    } on ProcessException {
      return null;
    }
  }

  /// Clears the resolution cache. Used by tests and after the user installs a
  /// tool without restarting the app.
  static void invalidate() => _cache.clear();
}

class ToolMissingException implements Exception {
  ToolMissingException(this.tool);

  final Tool tool;

  String get installHint => switch (tool) {
        Tool.ffmpeg || Tool.ffprobe => S.current.ffmpegMissingHint,
        Tool.realesrgan => S.current.esrganMissingHint,
        Tool.rife => S.current.rifeMissingHint,
      };

  @override
  String toString() => installHint;
}
