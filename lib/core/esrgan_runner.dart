/// Drives `realesrgan-ncnn-vulkan` for AI upscaling.
///
/// The ncnn build runs on Vulkan (Windows) and MoltenVK/Metal (macOS), so the
/// same code path gets GPU acceleration on both desktop targets without any
/// Python or PyTorch runtime.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  /// network — runs at 4x and is resized down in the encode pass.
  static int ncnnScaleFor(UpscaleModel model, int requestedScale) =>
      model.nativeScales.contains(requestedScale) ? requestedScale : 4;

  /// True when FFmpeg must resize after the model runs.
  static bool needsPostResize(UpscaleModel model, int requestedScale) =>
      !model.nativeScales.contains(requestedScale);

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
      '(${ncnnScaleFor(model, scale)}×)…',
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
    reporter.log('Real-ESRGAN: model ${model.id} (${ncnnScaleFor(model, scale)}×)…');
    await _run(
      inputPath: input,
      outputPath: output,
      model: model,
      scale: scale,
      reporter: reporter,
    );
    reporter.log('Real-ESRGAN selesai.');
  }

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

    final args = <String>[
      '-i', inputPath,
      '-o', outputPath,
      '-n', model.ncnnName!,
      '-s', '${ncnnScaleFor(model, scale)}',
      '-f', 'png',
      if (modelsDir != null) ...['-m', modelsDir],
    ];

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
