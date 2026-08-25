/// Drives `rife-ncnn-vulkan` for AI frame interpolation.
///
/// RIFE is 5–10x faster than FFmpeg's `minterpolate` and produces noticeably
/// smoother motion. When the binary is missing the pipeline falls back to
/// minterpolate instead of failing.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/process_options.dart';
import 'binaries.dart';
import 'job_log.dart';

class RifeRunner {
  RifeRunner._();

  static bool get isAvailable => Binaries.isAvailable(Tool.rife);

  /// Interpolates the PNGs in [inputDir] up to [targetFps].
  ///
  /// Returns the frame rate the output directory should be encoded at.
  static Future<double> interpolateDirectory({
    required String inputDir,
    required String outputDir,
    required double sourceFps,
    required JobReporter reporter,
    double targetFps = kTargetFpsDouble,
    ProgressSink? progress,
  }) async {
    final sourceCount = Directory(inputDir)
        .listSync()
        .where((e) => e.path.endsWith('.png'))
        .length;
    if (sourceCount == 0) {
      throw PipelineException('Tidak ada frame untuk diinterpolasi');
    }

    await Directory(outputDir).create(recursive: true);

    final duration = sourceCount / (sourceFps <= 0 ? 1.0 : sourceFps);
    final targetCount = (duration * targetFps).round().clamp(2, 1 << 30);

    reporter.log(
      'RIFE: $sourceCount frame @ ${sourceFps.toStringAsFixed(2)}fps → '
      '$targetCount frame @ ${targetFps.toStringAsFixed(0)}fps',
    );

    final binary = Binaries.require(Tool.rife);
    final modelsDir = Binaries.modelsDir(Tool.rife);

    final args = <String>[
      '-i', inputDir,
      '-o', outputDir,
      '-n', '$targetCount',
      // Emit the naming scheme the encoder expects, so no rename pass is needed.
      '-f', 'frame_%06d.png',
      if (modelsDir != null) ...['-m', modelsDir],
    ];

    final process = await Process.start(binary, args);
    final stderrTail = <String>[];

    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return;
      stderrTail.add(trimmed);
      if (stderrTail.length > 40) stderrTail.removeAt(0);
    }).asFuture<void>();

    final stdoutDone = process.stdout.drain<void>();

    Timer? poller;
    if (progress != null) {
      poller = Timer.periodic(const Duration(milliseconds: 700), (_) {
        final done = Directory(outputDir)
            .listSync()
            .where((e) => e.path.endsWith('.png'))
            .length;
        progress(done / targetCount);
      });
    }

    final exitCode = await process.exitCode;
    poller?.cancel();
    await Future.wait([stdoutDone, stderrDone]);

    if (exitCode != 0) {
      throw PipelineException(
        'RIFE gagal (exit $exitCode)',
        detail: stderrTail.join('\n'),
      );
    }

    await _normalizeFrameNames(outputDir);
    progress?.call(1.0);
    reporter.log('RIFE selesai → $targetCount frame @ '
        '${targetFps.toStringAsFixed(0)}fps.');
    return targetFps;
  }

  /// Older RIFE builds ignore `-f` and write `00000001.png`. Rename anything
  /// that does not already match `frame_%06d.png` so the encoder can glob it.
  static Future<void> _normalizeFrameNames(String outputDir) async {
    final files = Directory(outputDir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final alreadyNamed = files.every(
      (f) => RegExp(r'^frame_\d{6}\.png$').hasMatch(p.basename(f.path)),
    );
    if (alreadyNamed) return;

    for (var i = 0; i < files.length; i++) {
      final target = p.join(outputDir, 'frame_${i.toString().padLeft(6, '0')}.png');
      if (files[i].path != target) {
        await files[i].rename(target);
      }
    }
  }
}
