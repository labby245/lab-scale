/// Orchestrates the image and video processing stages.
///
/// Video takes one of two routes:
///   * **direct** — a single FFmpeg transcode covering Lanczos, minterpolate
///     and unsharp. Used whenever no AI stage is requested.
///   * **frames** — decode to PNG, optionally interpolate with RIFE, optionally
///     upscale with Real-ESRGAN, then re-encode. Required by any ncnn stage.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../l10n/strings.dart';
import '../models/media_file.dart';
import '../models/process_options.dart';
import 'binaries.dart';
import 'disk_space.dart';
import 'esrgan_runner.dart';
import 'ffmpeg_runner.dart';
import 'job_log.dart';
import 'rife_runner.dart';

class JobResult {
  const JobResult({
    required this.sourceName,
    required this.outputPath,
    this.error,
    this.cancelled = false,
  });

  /// A file the user stopped, or never reached because the batch was
  /// cancelled before it.
  const JobResult.cancelled(this.sourceName)
      : outputPath = '',
        error = null,
        cancelled = true;

  final String sourceName;
  final String outputPath;
  final String? error;
  final bool cancelled;

  bool get isSuccess => error == null && !cancelled;
  String get outputName => p.basename(outputPath);
}

class Pipeline {
  Pipeline({
    required this.outputDir,
    required this.tempDir,
    Future<int?> Function(String path)? freeSpace,
  }) : _freeSpace = freeSpace ?? DiskSpace.freeBytes;

  final String outputDir;
  final String tempDir;

  /// Free bytes on the volume holding a path. Injected by tests.
  final Future<int?> Function(String path) _freeSpace;

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
    } on JobCancelled {
      // The tool was killed mid-write; what it left is a truncated file that
      // would look like a real result in the output folder.
      _deleteFile(output);
      reporter.log(S.current.logCancelled);
      return JobResult.cancelled(file.displayName);
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
      reporter.log(S.current.logRifeFallback);
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

  /// Dimensions of the first extracted frame, or null when they cannot be
  /// read.
  ///
  /// Read straight from the PNG header rather than by shelling out: the answer
  /// is 24 bytes in, and this sits on the hot path of every video job.
  static Future<({int width, int height})?> _firstFrameSize(
    String framesDir,
  ) async {
    try {
      final frames = await Directory(framesDir)
          .list()
          .where((e) => e is File && e.path.toLowerCase().endsWith('.png'))
          .toList();
      if (frames.isEmpty) return null;
      frames.sort((a, b) => a.path.compareTo(b.path));

      final header = await (frames.first as File).openRead(0, 24).first;
      if (header.length < 24) return null;
      final bytes = Uint8List.fromList(header);
      // 8-byte signature, 4-byte chunk length, "IHDR", then two big-endian
      // uint32s.
      if (String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR') return null;
      final data = ByteData.sublistView(bytes);
      return (width: data.getUint32(16), height: data.getUint32(20));
    } on FileSystemException {
      return null;
    }
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
      S.current.logVideo(info.width, info.height, info.fps, info.frameCount),
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

    await _checkTempSpace(info, options, reporter);

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

      // Geometry comes from the frames themselves, not from probe(). FFmpeg
      // autorotates on extraction while ffprobe reports the *stored*
      // dimensions, so a phone clip carrying rotation=90 has frames that are
      // the transpose of what info says. Scaling to info's numbers would
      // squash a portrait clip into landscape.
      final source =
          await _firstFrameSize(framesDir) ??
          (width: info.width, height: info.height);

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
      //   * ESRGAN ran, but at a wider scale than was asked for. That is every
      //     request a model has no weights for — a 1x "enhance only", and
      //     also 2x and 3x on the seven 4x-only models, which all run at 4x.
      //   * ESRGAN did NOT run, but Lanczos upscaling was requested and we are
      //     on the frames path because of RIFE. The direct-path filter chain
      //     never executed, so the scale has to happen here or the output comes
      //     out at source resolution while the filename claims otherwise.
      final int? targetWidth;
      final int? targetHeight;
      if (options.useEsrgan) {
        final needsResize = EsrganRunner.needsPostResize(
          options.upscaleModel,
          options.upscaleScale,
        );
        targetWidth = needsResize ? source.width * options.upscaleScale : null;
        targetHeight = needsResize
            ? source.height * options.upscaleScale
            : null;
      } else if (options.lanczosScale != null) {
        targetWidth = source.width * options.lanczosScale!;
        targetHeight = source.height * options.lanczosScale!;
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
      throw PipelineException(S.current.noOpForPhoto);
    }

    final info = await FfmpegRunner.probe(input);
    reporter.log(S.current.logImage(info.width, info.height));

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
      reporter.log(S.current.logImageSaved);
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

      final needsResize = EsrganRunner.needsPostResize(
        options.upscaleModel,
        options.upscaleScale,
      );
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
      reporter.log(S.current.logImageSaved);
    } finally {
      await _deleteDir(workDir.path);
    }
  }

  /// Refuses a frames-path job the temp volume cannot hold.
  ///
  /// The estimate comes from the probed size and frame count, so rotation does
  /// not matter here (width × height is the same either way). When free space
  /// cannot be read the job proceeds — refusing work on a guess would be
  /// worse than the failure this guards against.
  Future<void> _checkTempSpace(
    MediaInfo info,
    ProcessOptions options,
    JobReporter reporter,
  ) async {
    if (info.frameCount <= 0) return;
    final needed = DiskSpace.estimatePeakBytes(
      width: info.width,
      height: info.height,
      frameCount: info.frameCount,
      fps: info.fps,
      options: options,
    );
    final free = await _freeSpace(tempDir);
    if (free == null) return;
    reporter.log(S.current.logTempEstimate(needed, free));
    if (needed + kDiskReserveBytes > free) {
      throw PipelineException(S.current.notEnoughDisk(needed, free, tempDir));
    }
  }

  static void _deleteFile(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Best effort: a leftover partial file is untidy, not harmful.
    }
  }

  /// Removes work folders an earlier session left behind.
  ///
  /// A job that ends normally deletes its own frames, but one cut short by a
  /// crash, a force quit or a power cut leaves them — tens of gigabytes for an
  /// AI video — in the temp folder for good. Only folders this app names
  /// (`labscale_*`, `gpu_probe_*`) and only ones untouched for [olderThan]
  /// are removed, so a second LabScale window's live job is never touched.
  /// Returns how many were removed.
  static int cleanStaleWorkDirs(
    String tempDir, {
    Duration olderThan = const Duration(hours: 6),
    DateTime? now,
  }) {
    final dir = Directory(tempDir);
    if (!dir.existsSync()) return 0;
    final cutoff = (now ?? DateTime.now()).subtract(olderThan);
    var removed = 0;
    for (final entry in dir.listSync(followLinks: false)) {
      if (entry is! Directory) continue;
      final name = p.basename(entry.path);
      if (!name.startsWith('labscale_') && !name.startsWith('gpu_probe_')) {
        continue;
      }
      try {
        if (entry.statSync().modified.isAfter(cutoff)) continue;
        entry.deleteSync(recursive: true);
        removed++;
      } on FileSystemException {
        // In use or locked: try again next launch.
      }
    }
    return removed;
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
