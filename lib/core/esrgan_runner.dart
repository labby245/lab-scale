/// Drives `realesrgan-ncnn-vulkan` for AI upscaling.
///
/// The ncnn build runs on Vulkan (Windows) and MoltenVK/Metal (macOS), so the
/// same code path gets GPU acceleration on both desktop targets without any
/// Python or PyTorch runtime.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/process_options.dart';
import 'binaries.dart';
import 'job_log.dart';

class EsrganRunner {
  EsrganRunner._();

  static bool get isAvailable => Binaries.isAvailable(Tool.realesrgan);

  /// The scale to pass to `-s`.
  ///
  /// Only a scale the model has weights for is asked of the tool directly.
  /// Everything else — a 1x "enhance only" request, or 2x on a 4x-only
  /// network — runs at the model's widest scale and is resized down in the
  /// encode pass.
  ///
  /// The fallback is read off the model rather than hard-coded to 4, so a
  /// network that tops out lower can never be handed a `-s` it has no weights
  /// for, which is the very failure this mechanism exists to prevent.
  static int ncnnScaleFor(UpscaleModel model, int requestedScale) {
    final scales = model.nativeScales;
    if (scales.isEmpty) return requestedScale; // Not an ncnn model at all.
    if (scales.contains(requestedScale)) return requestedScale;
    return scales.reduce(math.max);
  }

  /// True when FFmpeg must resize after the model runs.
  ///
  /// Expressed through [ncnnScaleFor] so the two cannot drift apart: a resize
  /// is needed exactly when the tool was asked for a different scale than the
  /// user wanted.
  static bool needsPostResize(UpscaleModel model, int requestedScale) =>
      ncnnScaleFor(model, requestedScale) != requestedScale;

  /// Upscales every PNG in [inputDir], writing results to [outputDir].
  static Future<void> upscaleDirectory({
    required String inputDir,
    required String outputDir,
    required UpscaleModel model,
    required int scale,
    required JobReporter reporter,
    ProgressSink? progress,
  }) async {
    final totalFrames = Directory(inputDir)
        .listSync()
        .where((e) => e.path.endsWith('.png'))
        .length;
    if (totalFrames == 0) {
      throw PipelineException('Tidak ada frame untuk di-upscale');
    }

    await Directory(outputDir).create(recursive: true);
    reporter.log(
      'Real-ESRGAN: model ${model.id} pada $totalFrames frame '
      '($scale×)…',
    );

    await _run(
      inputPath: inputDir,
      outputPath: outputDir,
      model: model,
      scale: scale,
      reporter: reporter,
      progress: progress,
      totalOutputs: totalFrames,
      outputDirToWatch: outputDir,
    );

    reporter.log('Real-ESRGAN selesai.');
  }

  /// Upscales a single still image.
  static Future<void> upscaleImage({
    required String input,
    required String output,
    required UpscaleModel model,
    required int scale,
    required JobReporter reporter,
  }) async {
    final ncnnScale = ncnnScaleFor(model, scale);
    reporter.log(
      ncnnScale == scale
          ? 'Real-ESRGAN: model ${model.id} ($scale×)…'
          // Says why a 2x job is about to cost what a 4x one does: this model
          // has no weights at the requested scale, so it runs wide and FFmpeg
          // resizes down afterwards.
          : 'Real-ESRGAN: model ${model.id} ($scale× — jaringan '
              '$ncnnScale× lalu diperkecil)…',
    );
    await _run(
      inputPath: input,
      outputPath: output,
      model: model,
      scale: scale,
      reporter: reporter,
    );
    reporter.log('Real-ESRGAN selesai.');
  }

  /// The exact argv handed to `realesrgan-ncnn-vulkan`.
  ///
  /// Split out so the `-s` value can be asserted directly. A torn output comes
  /// back at exactly the requested size, so no test of the *result* can catch
  /// the wrong scale reaching the process — only the argv can.
  @visibleForTesting
  static List<String> buildArgs({
    required String inputPath,
    required String outputPath,
    required UpscaleModel model,
    required int requestedScale,
    String? modelsDir,
  }) =>
      <String>[
        '-i', inputPath,
        '-o', outputPath,
        '-n', model.ncnnName!,
        '-s', '${ncnnScaleFor(model, requestedScale)}',
        '-f', 'png',
        if (modelsDir != null) ...['-m', modelsDir],
      ];

  static Future<void> _run({
    required String inputPath,
    required String outputPath,
    required UpscaleModel model,
    required int scale,
    required JobReporter reporter,
    ProgressSink? progress,
    int totalOutputs = 0,
    String? outputDirToWatch,
  }) async {
    final binary = Binaries.require(Tool.realesrgan);
    final modelsDir = Binaries.modelsDir(Tool.realesrgan);

    final args = buildArgs(
      inputPath: inputPath,
      outputPath: outputPath,
      model: model,
      requestedScale: scale,
      modelsDir: modelsDir,
    );

    final process = await Process.start(binary, args);
    final stderrTail = <String>[];

    // The tool prints "N.NN%" to stderr; when that is unavailable we fall back
    // to counting files that have landed in the output directory.
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return;
      final percent = RegExp(r'([\d.]+)%').firstMatch(trimmed);
      if (percent != null) {
        final value = double.tryParse(percent.group(1)!);
        if (value != null) progress?.call(value / 100.0);
        return;
      }
      stderrTail.add(trimmed);
      if (stderrTail.length > 40) stderrTail.removeAt(0);
    }).asFuture<void>();

    final stdoutDone = process.stdout.drain<void>();

    Timer? poller;
    if (progress != null && outputDirToWatch != null && totalOutputs > 0) {
      poller = Timer.periodic(const Duration(milliseconds: 700), (_) {
        final done = Directory(outputDirToWatch)
            .listSync()
            .where((e) => e.path.endsWith('.png'))
            .length;
        progress(done / totalOutputs);
      });
    }

    final exitCode = await process.exitCode;
    poller?.cancel();
    await Future.wait([stdoutDone, stderrDone]);

    if (exitCode != 0) {
      throw PipelineException(
        'Real-ESRGAN gagal (exit $exitCode)',
        detail: stderrTail.join('\n'),
      );
    }
    progress?.call(1.0);
  }
}
