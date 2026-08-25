/// Poster frames for the selection grid.
///
/// Every thumbnail goes through FFmpeg rather than Flutter's own decoder. That
/// costs a subprocess per file but buys three things: TIFF works (Flutter
/// cannot decode it at all), a 6000px source never gets decoded at full size
/// just to fill a 170px tile, and videos and stills take the same path.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/media_file.dart';
import 'binaries.dart';

class Thumbnailer {
  Thumbnailer({required this.cacheDir});

  /// Where generated posters live — under the app's temp dir, so the OS
  /// reclaims them and a stale cache is never a correctness problem.
  final String cacheDir;

  /// Longest edge of a generated poster. Tiles are ~170pt, so 400px covers
  /// a 2x display with room to spare.
  static const _edge = 400;

  /// In-flight and completed jobs, keyed by cache path. Without this a grid
  /// rebuild mid-generation would spawn a second FFmpeg for the same file.
  final Map<String, Future<String?>> _jobs = {};

  /// Absolute path to a poster for [file], or null when one cannot be made.
  Future<String?> posterFor(MediaFile file) =>
      posterForPath(file.path, isVideo: file.isVideo);

  /// Same, for a path that is not part of the selection — a pipeline output,
  /// for instance, which the compare slider needs a still of.
  Future<String?> posterForPath(String path, {required bool isVideo}) {
    final int size;
    try {
      size = File(path).lengthSync();
    } on FileSystemException {
      return Future.value(null);
    }
    final target = _cachePathFor(path, size);
    return _jobs.putIfAbsent(target, () => _generate(path, isVideo, target));
  }

  /// Keyed on size as well as path so replacing a file with a different one of
  /// the same name does not serve the previous poster.
  String _cachePathFor(String path, int size) {
    final stamp = Object.hash(path, size).toRadixString(16);
    return p.join(cacheDir, '${p.basenameWithoutExtension(path)}_$stamp.jpg');
  }

  Future<String?> _generate(String source, bool isVideo, String target) async {
    if (File(target).existsSync()) return target;

    final ffmpeg = Binaries.resolve(Tool.ffmpeg);
    if (ffmpeg == null) return null;

    try {
      await Directory(cacheDir).create(recursive: true);
    } on FileSystemException {
      return null;
    }

    // Videos get a frame from one second in — frame zero is often a black or
    // fade-in frame that says nothing about the clip.
    if (isVideo && await _run(ffmpeg, source, target, seekSeconds: 1)) {
      return target;
    }
    // Stills, and clips shorter than the seek point.
    if (await _run(ffmpeg, source, target)) return target;
    return null;
  }

  Future<bool> _run(
    String ffmpeg,
    String source,
    String target, {
    int? seekSeconds,
  }) async {
    try {
      final result = await Process.run(ffmpeg, [
        '-hide_banner', '-loglevel', 'error', '-y',
        // -ss ahead of -i seeks by keyframe: far cheaper than decoding up to
        // the timestamp, and precision does not matter for a thumbnail.
        if (seekSeconds != null) ...['-ss', '$seekSeconds'],
        '-i', source,
        '-frames:v', '1',
        '-vf', 'scale=$_edge:$_edge:force_original_aspect_ratio=decrease',
        target,
      ]).timeout(const Duration(seconds: 20));

      // FFmpeg can exit 0 having written nothing when a seek lands past the
      // end of a short clip, so the file itself is the test.
      return result.exitCode == 0 &&
          File(target).existsSync() &&
          File(target).lengthSync() > 0;
    } on ProcessException {
      return false;
    } on TimeoutException {
      return false;
    }
  }
}
