/// Free-space checks for the frame-by-frame video path.
///
/// That path writes every frame of the clip as PNG, sometimes twice over, and
/// Real-ESRGAN's frames are 16× the pixels of the source on the 4×-only
/// networks. A long 1080p clip can need tens of gigabytes. Running out halfway
/// fails the job after it has already cost many minutes and leaves the system
/// disk full, so the estimate is checked before the first frame is written.
library;

import 'dart:io';

import '../models/process_options.dart';
import 'esrgan_runner.dart';

/// Bytes per pixel of a PNG frame from real footage.
///
/// 24-bit RGB is 3 bytes raw; deflate typically lands camera footage at
/// 1.2–1.8. The top of that range, so the check errs towards warning early
/// rather than letting the disk fill.
const double kPngBytesPerPixel = 1.8;

/// Head room left untouched on the volume — the OS and every other program
/// still need somewhere to write while the job runs.
const int kDiskReserveBytes = 1 << 30;

class DiskSpace {
  DiskSpace._();

  /// Peak bytes the frames path holds on disk at once for this job.
  ///
  /// Each stage reads one folder and writes another, and the input folder is
  /// only deleted once the stage finishes, so the peak is the largest
  /// input + output pair along the way.
  static int estimatePeakBytes({
    required int width,
    required int height,
    required int frameCount,
    required double fps,
    required ProcessOptions options,
  }) {
    final pixels = width * height;
    final frames = frameCount;
    var peakPixels = frames * pixels; // extraction alone

    var current = frames;
    if (options.useRife) {
      final duration = frames / (fps <= 0 ? 1.0 : fps);
      final interpolated = (duration * kTargetFps).round();
      peakPixels = _max(peakPixels, (frames + interpolated) * pixels);
      current = interpolated;
    }

    if (options.useEsrgan) {
      final scale = EsrganRunner.ncnnScaleFor(
        options.upscaleModel,
        options.upscaleScale,
      );
      final upscaled = current * pixels * scale * scale;
      peakPixels = _max(peakPixels, current * pixels + upscaled);
    }

    return (peakPixels * kPngBytesPerPixel).round();
  }

  static int _max(int a, int b) => a > b ? a : b;

  /// Bytes available to this user on the volume holding [path], or null when
  /// it cannot be determined — in which case the caller proceeds unchecked
  /// rather than refusing work on a guess.
  static Future<int?> freeBytes(String path) async {
    try {
      if (Platform.isWindows) return await _freeBytesWindows(path);
      return await _freeBytesPosix(path);
    } on Object {
      return null;
    }
  }

  /// `df -Pk` prints one header line, then the volume: the fourth column is
  /// the space available to unprivileged users, in 1024-byte blocks. `-P`
  /// keeps it on one line even when the device name is long.
  static Future<int?> _freeBytesPosix(String path) async {
    final result = await Process.run('df', ['-Pk', path]);
    if (result.exitCode != 0) return null;
    return parseDfOutput(result.stdout as String);
  }

  static int? parseDfOutput(String output) {
    final lines = output
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.length < 2) return null;
    final columns = lines.last.split(RegExp(r'\s+'));
    if (columns.length < 4) return null;
    final blocks = int.tryParse(columns[3]);
    return blocks == null ? null : blocks * 1024;
  }

  /// .NET's DriveInfo through PowerShell, which ships with every supported
  /// Windows — cheaper to depend on than an FFI binding for one number.
  static Future<int?> _freeBytesWindows(String path) async {
    final quoted = path.replaceAll("'", "''");
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "[System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot('$quoted'))"
          '.AvailableFreeSpace',
    ]);
    if (result.exitCode != 0) return null;
    return int.tryParse((result.stdout as String).trim());
  }
}
