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
    required ProcessOptions options,
    required JobReporter reporter,
  }) async {
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

  String _outputPathFor(MediaFile file, ProcessOptions options) {
    final ext = file.isImage
        ? (options.quality == Quality.ultra ? '.png' : '.jpg')
        : '.mp4';
    final name = '${file.baseName}${options.outputSuffix()}$ext';
    return p.join(outputDir, name);
  }

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

      final needsResize = options.useEsrgan &&
          EsrganRunner.needsPostResize(options.upscaleScale);

      await FfmpegRunner.encodeFromFrames(
        framesDir: framesDir,
        fps: fps,
        audioSource: input,
        output: output,
        options: options,
        info: info,
        reporter: reporter,
        postWidth: needsResize ? info.width * options.upscaleScale : null,
        postHeight: needsResize ? info.height * options.upscaleScale : null,
        sharpness: options.sharpness,
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
        sharpness: options.sharpness,
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
          EsrganRunner.needsPostResize(options.upscaleScale);
      await FfmpegRunner.filterImage(
        input: staged,
        output: output,
        reporter: reporter,
        targetWidth: needsResize ? info.width * options.upscaleScale : null,
        targetHeight: needsResize ? info.height * options.upscaleScale : null,
        sharpness: options.sharpness,
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
