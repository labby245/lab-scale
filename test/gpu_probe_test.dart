/// A tool that is installed but cannot run (no Vulkan) must look missing to
/// the whole app, so its fallbacks apply instead of every job failing.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:labscale/core/binaries.dart';
import 'package:labscale/core/gpu_probe.dart';
import 'package:labscale/core/rife_runner.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory work;

  setUp(() => work = Directory.systemTemp.createTempSync('labscale_gpu_'));
  tearDown(() {
    Binaries.clearUnusable();
    work.deleteSync(recursive: true);
  });

  test('the probe image is a PNG ffmpeg can read', () async {
    final ffprobe = Binaries.resolve(Tool.ffprobe);
    if (ffprobe == null) return markTestSkipped('ffprobe tidak terpasang');
    final file = File(p.join(work.path, 'tiny.png'))..writeAsBytesSync(tinyPng());
    final result = await Process.run(ffprobe, [
      '-v', 'error', '-show_entries', 'stream=width,height,codec_name',
      '-of', 'csv=p=0', file.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect((result.stdout as String).trim(), 'png,16,16');
  });

  test('the bundled tools pass the probe on a machine with a GPU', () async {
    final esrgan = Binaries.resolve(Tool.realesrgan);
    final rife = Binaries.resolve(Tool.rife);
    if (esrgan == null || rife == null) {
      return markTestSkipped('ncnn tools tidak terpasang di bin/');
    }
    await probeGpuTools(work.path);
    expect(Binaries.unusableReason(Tool.realesrgan), isNull);
    expect(Binaries.unusableReason(Tool.rife), isNull);
    expect(RifeRunner.isAvailable, isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a tool that exits non-zero is reported with its last words', () async {
    if (Platform.isWindows) return markTestSkipped('pakai skrip shell');
    final fake = File(p.join(work.path, 'fake-ncnn'))
      ..writeAsStringSync('#!/bin/sh\necho "vkCreateInstance failed -9" >&2\nexit 255\n');
    await Process.run('chmod', ['+x', fake.path]);
    final result = await GpuProbe.esrgan(
      binary: fake.path,
      modelsDir: work.path,
      ncnnModel: 'x',
      workDir: work.path,
    );
    expect(result, isNotNull);
    expect(result!.failure, GpuProbeFailure.failed);
    expect(result.detail, contains('vkCreateInstance failed'));
  });

  test('a tool marked unusable counts as missing everywhere', () {
    if (Binaries.resolve(Tool.rife) == null) {
      return markTestSkipped('rife-ncnn-vulkan tidak terpasang di bin/');
    }
    Binaries.markUnusable(
      Tool.rife,
      const GpuProbeResult(GpuProbeFailure.noVulkan, 'vulkan-1.dll'),
    );
    // The pipeline's RIFE -> minterpolate fallback keys on exactly this.
    expect(RifeRunner.isAvailable, isFalse);
    expect(
      () => Binaries.require(Tool.rife),
      throwsA(isA<ToolMissingException>().having(
        (e) => e.installHint,
        'hint',
        contains('Vulkan'),
      )),
    );
  });

  test('the fastest bundled model is the one probed', () {
    for (final ext in ['param', 'bin']) {
      File(p.join(work.path, 'realesrgan-x4plus.$ext')).writeAsStringSync('');
      File(p.join(work.path, 'realesr-animevideov3-x4.$ext'))
          .writeAsStringSync('');
    }
    // AnimeVideoV3 is named without its -x4 suffix: the tool adds it.
    expect(probeModelFor(work.path), 'realesr-animevideov3');
    expect(probeModelFor(p.join(work.path, 'nope')), isNull);
  });
}
