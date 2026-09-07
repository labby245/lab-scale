/// Orchestrates the image and video processing stages.
///
/// Video takes one of two routes:
///   * **direct** — a single FFmpeg transcode covering Lanczos, minterpolate
///     and unsharp. Used whenever no AI stage is requested.
///   * **frames** — decode to PNG, optionally interpolate with RIFE, optionally
///     upscale with Real-ESRGAN, then re-encode. Required by any ncnn stage.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/media_file.dart';
import '../models/process_options.dart';
import 'binaries.dart';
import 'esrgan_runner.dart';
import 'ffmpeg_runner.dart';
import 'job_log.dart';
import 'rife_runner.dart';

class JobResult {
  const JobResult({
    required this.sourceName,
    required this.outputPath,
    this.error,
  });

  final String sourceName;
  final String outputPath;
  final String? error;

  bool get isSuccess => error == null;
  String get outputName => p.basename(outputPath);
}

class Pipeline {
  Pipeline({required this.outputDir, required this.tempDir});

  final String outputDir;
  final String tempDir;

  /// Processes [file] and returns where the result landed.
  Future<JobResult> process({
    required MediaFile file,
    required ProcessOptions rawOptions,
    required JobReporter reporter,
  }) async {
    final options = _resolveAvailability(rawOptions, reporter);
    final output = _outputPathFor(file, options);
    try {
      if (file.isImage) {
        await _processImage(file.path, output, options, reporter);
      } else {
        await _processVideo(file.path, output, options, reporter);
      }
      return JobResult(sourceName: file.displayName, outputPath: output);
    } on PipelineException catch (e) {
      return JobResult(
        sourceName: file.displayName,
        outputPath: output,
        // Keep the tool's own words: without them a failure is undiagnosable.
        error: e.detail == null || e.detail!.isEmpty
            ? e.message
            : '${e.message} — ${_lastLine(e.detail!)}',
      );
    } on ToolMissingException catch (e) {
      return JobResult(
        sourceName: file.displayName,
        outputPath: output,
        error: e.installHint,
      );
    }
  }

  /// Downgrades options that ask for a tool this machine does not have.
  ///
  /// A missing RIFE falls back to FFmpeg's `minterpolate` rather than failing
  /// the job — that is what the README and the UI both promise. A missing
  /// Real-ESRGAN is *not* downgraded: silently swapping in Lanczos would
  /// deliver visibly different output than the user asked for, so that one is
  /// left to fail with a clear "tool tidak ditemukan" message.
  ProcessOptions _resolveAvailability(
    ProcessOptions options,
    JobReporter reporter,
  ) {
    if (options.useRife && !RifeRunner.isAvailable) {
      reporter.log('RIFE tidak ditemukan — pakai FFmpeg minterpolate.');
      return options.copyWith(interpEngine: InterpEngine.ffmpeg);
    }
    return options;
  }

  /// The most informative line of a stderr tail is usually the last real one.
  static String _lastLine(String detail) {
    final lines = detail
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return detail.trim();
    return lines.last.length > 300 ? lines.last.substring(0, 300) : lines.last;
  }

  /// Builds the output path, appending `_2`, `_3`… when the name is taken.
  ///
  /// A recursive folder pick routinely contains several files with the same
  /// basename in different subfolders; without this they would overwrite each
  /// other while every one still reported success.
  String _outputPathFor(MediaFile file, ProcessOptions options) {
    final ext = file.isImage
        ? (options.quality == Quality.ultra ? '.png' : '.jpg')
        : '.mp4';
    final stem = '${file.baseName}${options.outputSuffix()}';

    // A dropped folder keeps its results together in a folder of its own.
    final destination = file.destinationDir(outputDir);
    Directory(destination).createSync(recursive: true);

    var candidate = p.join(destination, '$stem$ext');
    var counter = 2;
    while (File(candidate).existsSync() || _claimed.contains(candidate)) {
      candidate = p.join(destination, '${stem}_$counter$ext');
      counter++;
    }
    _claimed.add(candidate);
    return candidate;
  }

  /// Paths handed out during this pipeline's lifetime. Needed because a file is
  /// only created at the very end of a job, so `existsSync` alone would hand
  /// the same name to two files in one batch.
  final Set<String> _claimed = {};

  // ── Video ─────────────────────────────────────────────────────────────────

  Future<void> _processVideo(
    String input,
    String output,
    ProcessOptions options,
    JobReporter reporter,
  ) async {
    final info = await FfmpegRunner.probe(input);
    reporter.log(
      'Video ${info.width}×${info.height} @ ${info.fps.toStringAsFixed(1)}fps '
      '(${info.frameCount} frame).',
    );

    if (!options.needsFrames) {
      await FfmpegRunner.transcode(
        input: input,
        output: output,
        options: options,
        info: info,
        reporter: reporter,
        progress: reporter.stage(0.0, 1.0),
      );
      return;
    }

    final workDir = await Directory(tempDir).createTemp('labscale_');
    try {
      var framesDir = p.join(workDir.path, 'frames');
      await FfmpegRunner.extractFrames(
        input: input,
        framesDir: framesDir,
        reporter: reporter,
        info: info,
        progress: reporter.stage(0.0, 0.25),
      );

      var fps = info.fps;

      if (options.useRife) {
        final interpDir = p.join(workDir.path, 'interp');
        fps = await RifeRunner.interpolateDirectory(
          inputDir: framesDir,
          outputDir: interpDir,
          sourceFps: fps,
          reporter: reporter,
          progress: reporter.stage(0.25, 0.55),
        );
        await _deleteDir(framesDir);
        framesDir = interpDir;
      }

      if (options.useEsrgan) {
        final upDir = p.join(workDir.path, 'upscaled');
        await EsrganRunner.upscaleDirectory(
          inputDir: framesDir,
          outputDir: upDir,
          model: options.upscaleModel,
          scale: options.upscaleScale,
          reporter: reporter,
          progress: reporter.stage(options.useRife ? 0.55 : 0.25, 0.85),
        );
        await _deleteDir(framesDir);
        framesDir = upDir;
      }

      // Work out the final size. Two separate cases land here:
      //   * ESRGAN ran at its native 2/3/4x — only 1x ("enhance only") needs a
      //     resize back down.
      //   * ESRGAN did NOT run, but Lanczos upscaling was requested and we are
      //     on the frames path because of RIFE. The direct-path filter chain
      //     never executed, so the scale has to happen here or the output comes
      //     out at source resolution while the filename claims otherwise.
      final int? targetWidth;
      final int? targetHeight;
      if (options.useEsrgan) {
        final needsResize =
            EsrganRunner.needsPostResize(options.upscaleModel, options.upscaleScale);
        targetWidth = needsResize ? info.width * options.upscaleScale : null;
        targetHeight = needsResize ? info.height * options.upscaleScale : null;
      } else if (options.lanczosScale != null) {
        targetWidth = info.width * options.lanczosScale!;
        targetHeight = info.height * options.lanczosScale!;
      } else {
        targetWidth = null;
        targetHeight = null;
      }

      await FfmpegRunner.encodeFromFrames(
        framesDir: framesDir,
        fps: fps,
        audioSource: input,
        output: output,
        options: options,
        info: info,
        reporter: reporter,
        postWidth: targetWidth,
        postHeight: targetHeight,
        sharpness: options.effectiveSharpness,
        // RIFE already produced the target rate; only FFmpeg's own engine still
        // needs the minterpolate filter at encode time.
        minterpolate: options.fpsBoost && !options.useRife,
        progress: reporter.stage(0.85, 1.0),
      );
    } finally {
      await _deleteDir(workDir.path);
    }
  }

  // ── Image ─────────────────────────────────────────────────────────────────

  Future<void> _processImage(
    String input,
    String output,
    ProcessOptions options,
    JobReporter reporter,
  ) async {
    if (!options.upscale) {
      throw PipelineException('Tidak ada operasi yang berlaku untuk foto');
    }

    final info = await FfmpegRunner.probe(input);
    reporter.log('Gambar ${info.width}×${info.height} dimuat.');

    if (!options.useEsrgan) {
      reporter.report(null);
      await FfmpegRunner.filterImage(
        input: input,
        output: output,
        reporter: reporter,
        lanczosScale: options.upscaleScale > 1 ? options.upscaleScale : null,
        sharpness: options.effectiveSharpness,
        quality: options.quality,
      );
      reporter.report(1.0);
      reporter.log('Gambar tersimpan.');
      return;
    }

    final workDir = await Directory(tempDir).createTemp('labscale_img_');
    try {
      final staged = p.join(workDir.path, 'upscaled.png');
      reporter.report(null);
      await EsrganRunner.upscaleImage(
        input: input,
        output: staged,
        model: options.upscaleModel,
        scale: options.upscaleScale,
        reporter: reporter,
      );

      final needsResize =
          EsrganRunner.needsPostResize(options.upscaleModel, options.upscaleScale);
      await FfmpegRunner.filterImage(
        input: staged,
        output: output,
        reporter: reporter,
        targetWidth: needsResize ? info.width * options.upscaleScale : null,
        targetHeight: needsResize ? info.height * options.upscaleScale : null,
        sharpness: options.effectiveSharpness,
        quality: options.quality,
      );
      reporter.report(1.0);
      reporter.log('Gambar tersimpan.');
    } finally {
      await _deleteDir(workDir.path);
    }
  }

  static Future<void> _deleteDir(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return;
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // A locked temp file must never fail an otherwise-successful job.
    }
  }
}
