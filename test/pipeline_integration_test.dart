/// End-to-end pipeline tests against the real binaries in ./bin.
///
/// Each group skips itself when the tool it needs is not installed, so the
/// suite still passes on a machine that has only fetched some of them.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:labscale/core/binaries.dart';
import 'package:labscale/core/ffmpeg_runner.dart';
import 'package:labscale/core/job_log.dart';
import 'package:labscale/core/pipeline.dart';
import 'package:labscale/models/media_file.dart';
import 'package:labscale/models/process_options.dart';
import 'package:path/path.dart' as p;

/// Small enough that even the CPU fallback finishes quickly.
const _clipWidth = 160;
const _clipHeight = 120;
const _clipFps = 10;
const _clipSeconds = 1;

/// Everything here shells out to ffmpeg. Without it there is nothing to test,
/// so the whole file opts out rather than reporting failures on a checkout
/// where `tools/fetch_binaries` has not been run yet.
final String? _noFfmpeg = Binaries.isAvailable(Tool.ffmpeg)
    ? null
    : 'ffmpeg tidak terpasang — jalankan tools/fetch_binaries';

void main() {
  late Directory workspace;
  late String outputDir;
  late String tempDir;

  setUpAll(() {
    workspace = Directory.systemTemp.createTempSync('labscale_it_');
    outputDir = p.join(workspace.path, 'out');
    tempDir = p.join(workspace.path, 'tmp');
    Directory(outputDir).createSync(recursive: true);
    Directory(tempDir).createSync(recursive: true);
  });

  tearDownAll(() {
    try {
      workspace.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows sometimes still holds a handle; the temp dir is disposable.
    }
  });

  /// Synthesises a test clip with ffmpeg's `testsrc2` generator.
  Future<MediaFile> makeClip(String name) async {
    final path = p.join(workspace.path, name);
    final result = await Process.run(Binaries.require(Tool.ffmpeg), [
      '-y', '-hide_banner', '-loglevel', 'error',
      '-f', 'lavfi',
      '-i', 'testsrc2=size=${_clipWidth}x$_clipHeight:rate=$_clipFps'
          ':duration=$_clipSeconds',
      '-pix_fmt', 'yuv420p',
      path,
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    return MediaFile.tryFrom(path)!;
  }

  Future<MediaFile> makeStill(String name) async {
    final path = p.join(workspace.path, name);
    final result = await Process.run(Binaries.require(Tool.ffmpeg), [
      '-y', '-hide_banner', '-loglevel', 'error',
      '-f', 'lavfi',
      '-i', 'testsrc2=size=${_clipWidth}x$_clipHeight',
      '-frames:v', '1',
      path,
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    return MediaFile.tryFrom(path)!;
  }

  Future<JobResult> run(MediaFile file, ProcessOptions options) async {
    final pipeline = Pipeline(outputDir: outputDir, tempDir: tempDir);
    final reporter = JobReporter();
    final result = await pipeline.process(
      file: file,
      rawOptions: options,
      reporter: reporter,
    );
    await reporter.close();
    return result;
  }

  group('binary discovery', () {
    test('ffmpeg and ffprobe resolve to real files', () {
      final ffmpeg = Binaries.resolve(Tool.ffmpeg);
      final ffprobe = Binaries.resolve(Tool.ffprobe);
      expect(ffmpeg, isNotNull, reason: 'jalankan tools/fetch_binaries');
      expect(File(ffmpeg!).existsSync(), isTrue);
      expect(ffprobe, isNotNull);
      expect(File(ffprobe!).existsSync(), isTrue);
    });

    test('RIFE never borrows the Real-ESRGAN models folder', () {
      // Both tools unpack into the same bin/, so a shared lookup would hand
      // RIFE the `models/` directory that belongs to Real-ESRGAN.
      final rifeModels = Binaries.modelsDir(Tool.rife);
      if (rifeModels == null) return;
      expect(p.basename(rifeModels), isNot('models'));
      expect(p.basename(rifeModels), startsWith('rife'));
    });

    test('every reported encoder actually opens', () async {
      final support = await FfmpegRunner.encoders();
      // libx264 is always compiled into the builds we ship.
      expect(support.has('libx264'), isTrue);

      final selected = await FfmpegRunner.selectEncoder(VideoCodec.h264);
      final ffmpeg = Binaries.require(Tool.ffmpeg);
      final probe = await Process.run(ffmpeg, [
        '-hide_banner', '-loglevel', 'error', '-nostats',
        '-f', 'lavfi', '-i', 'nullsrc=s=256x256:d=1',
        '-c:v', selected.name, '-frames:v', '1', '-f', 'null', '-',
      ]);
      expect(
        probe.exitCode,
        0,
        reason: 'encoder terpilih "${selected.name}" gagal dibuka: '
            '${probe.stderr}',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  }, skip: _noFfmpeg);

  group('video — direct FFmpeg path', () {
    test('lanczos 2x doubles the output dimensions', () async {
      final clip = await makeClip('src_direct.mp4');
      final result = await run(
        clip,
        const ProcessOptions(
          upscale: true,
          upscaleModel: UpscaleModel.lanczos,
          upscaleScale: 2,
          sharpness: 0.3,
          quality: Quality.fast,
        ),
      );

      expect(result.error, isNull);
      expect(File(result.outputPath).existsSync(), isTrue);

      final info = await FfmpegRunner.probe(result.outputPath);
      expect(info.width, _clipWidth * 2);
      expect(info.height, _clipHeight * 2);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('fps boost via minterpolate reaches the target rate', () async {
      final clip = await makeClip('src_fps.mp4');
      final result = await run(
        clip,
        const ProcessOptions(
          fpsBoost: true,
          interpEngine: InterpEngine.ffmpeg,
          quality: Quality.fast,
        ),
      );

      expect(result.error, isNull);
      final info = await FfmpegRunner.probe(result.outputPath);
      expect(info.fps, closeTo(kTargetFps.toDouble(), 0.5));
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('same-name sources do not overwrite each other', () async {
      // Regression: a recursive folder pick routinely holds several files with
      // the same basename, which used to collapse onto one output path while
      // every job still reported success.
      final first = await makeClip('dup.mp4');
      final a = await run(first, const ProcessOptions(
        upscale: true, upscaleScale: 2, quality: Quality.fast,
      ));
      final b = await run(first, const ProcessOptions(
        upscale: true, upscaleScale: 2, quality: Quality.fast,
      ));

      expect(a.error, isNull);
      expect(b.error, isNull);
      expect(a.outputPath, isNot(b.outputPath));
      expect(File(a.outputPath).existsSync(), isTrue);
      expect(File(b.outputPath).existsSync(), isTrue);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('fps-boost-only output is not silently sharpened', () async {
      // Name deliberately free of the substring being asserted on.
      final clip = await makeClip('plainboost.mp4');
      final result = await run(
        clip,
        // A high slider value that must be ignored because upscale is off.
        const ProcessOptions(
          fpsBoost: true,
          interpEngine: InterpEngine.ffmpeg,
          sharpness: 0.9,
          quality: Quality.fast,
        ),
      );
      expect(result.error, isNull);
      expect(p.basename(result.outputPath), isNot(contains('sharp')));
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('output filename carries the operation suffix', () async {
      final clip = await makeClip('src_suffix.mp4');
      final result = await run(
        clip,
        const ProcessOptions(
          upscale: true,
          upscaleScale: 2,
          sharpness: 0.3,
          quality: Quality.fast,
        ),
      );
      expect(result.error, isNull);
      expect(p.basename(result.outputPath), 'src_suffix_lanczos-2x_sharp30.mp4');
    }, timeout: const Timeout(Duration(minutes: 3)));
  }, skip: _noFfmpeg);

  group('image', () {
    test('lanczos 4x scales a still', () async {
      final still = await makeStill('photo.png');
      final result = await run(
        still,
        const ProcessOptions(
          upscale: true,
          upscaleModel: UpscaleModel.lanczos,
          upscaleScale: 4,
          sharpness: 0.2,
        ),
      );

      expect(result.error, isNull);
      final info = await FfmpegRunner.probe(result.outputPath);
      expect(info.width, _clipWidth * 4);
      expect(info.height, _clipHeight * 4);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a photo with only fps boost reports a clear error', () async {
      final still = await makeStill('photo_noop.png');
      final result = await run(still, const ProcessOptions(fpsBoost: true));
      expect(result.isSuccess, isFalse);
      expect(result.error, contains('foto'));
    });
  }, skip: _noFfmpeg);

  group('video — Real-ESRGAN frame path', () {
    test('AI upscale 2x produces a correctly sized clip', () async {
      final clip = await makeClip('src_esrgan.mp4');
      final result = await run(
        clip,
        const ProcessOptions(
          upscale: true,
          upscaleModel: UpscaleModel.realesrganX4Plus,
          upscaleScale: 2,
          sharpness: 0.3,
          quality: Quality.fast,
        ),
      );

      expect(result.error, isNull);
      final info = await FfmpegRunner.probe(result.outputPath);
      expect(info.width, _clipWidth * 2);
      expect(info.height, _clipHeight * 2);
    }, timeout: const Timeout(Duration(minutes: 10)));
  }, skip: _noFfmpeg ?? (Binaries.isAvailable(Tool.realesrgan)
      ? false
      : 'realesrgan-ncnn-vulkan tidak terpasang di bin/'));

  group('video — RIFE frame path', () {
    test('RIFE interpolation reaches the target rate', () async {
      final clip = await makeClip('src_rife.mp4');
      final result = await run(
        clip,
        const ProcessOptions(
          fpsBoost: true,
          interpEngine: InterpEngine.rife,
          quality: Quality.fast,
        ),
      );

      expect(result.error, isNull);
      final info = await FfmpegRunner.probe(result.outputPath);
      expect(info.fps, closeTo(kTargetFps.toDouble(), 0.5));
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('lanczos survives the RIFE frame path', () async {
      // Regression: entering the frames path via RIFE skipped the direct-path
      // filter chain, so the Lanczos scale was dropped while the filename still
      // claimed `_lanczos-2x`.
      final clip = await makeClip('src_rife_lanczos.mp4');
      final result = await run(
        clip,
        const ProcessOptions(
          upscale: true,
          upscaleModel: UpscaleModel.lanczos,
          upscaleScale: 2,
          fpsBoost: true,
          interpEngine: InterpEngine.rife,
          quality: Quality.fast,
        ),
      );

      expect(result.error, isNull);
      final info = await FfmpegRunner.probe(result.outputPath);
      expect(info.width, _clipWidth * 2, reason: 'lanczos ikut hilang lagi');
      expect(info.height, _clipHeight * 2);
      expect(info.fps, closeTo(kTargetFps.toDouble(), 0.5));
    }, timeout: const Timeout(Duration(minutes: 10)));
  }, skip: _noFfmpeg ?? (Binaries.isAvailable(Tool.rife)
      ? false
      : 'rife-ncnn-vulkan tidak terpasang di bin/'));
}
