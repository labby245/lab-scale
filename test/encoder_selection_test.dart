/// Hardware encoders are preferred, Intel and AMD included, and a hardware
/// encoder that fails on a real job never costs the user their file.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:labscale/core/binaries.dart';
import 'package:labscale/core/ffmpeg_runner.dart';
import 'package:labscale/core/job_log.dart';
import 'package:labscale/core/pipeline.dart';
import 'package:labscale/l10n/strings.dart';
import 'package:labscale/models/media_file.dart';
import 'package:labscale/models/process_options.dart';
import 'package:path/path.dart' as p;

MediaInfo _info({bool hdr = false}) => MediaInfo(
      width: 64,
      height: 64,
      fps: 10,
      frameCount: 10,
      durationSeconds: 1,
      hasAudio: false,
      audioCodec: '',
      colorPrimaries: hdr ? 'bt2020' : 'bt709',
      colorTransfer: hdr ? 'smpte2084' : 'bt709',
      isHdr: hdr,
    );

void main() {
  tearDown(FfmpegRunner.invalidateEncoderCache);

  Future<String> pick(Set<String> encoders, VideoCodec codec,
      {bool cpuOnly = false}) async {
    FfmpegRunner.debugSetEncoderSupport(EncoderSupport(encoders));
    return (await FfmpegRunner.selectEncoder(codec, cpuOnly: cpuOnly)).name;
  }

  test('hardware order: NVIDIA, Apple, Intel, AMD, then CPU', () async {
    expect(await pick({'libx264', 'h264_amf', 'h264_qsv', 'h264_nvenc'},
        VideoCodec.h264), 'h264_nvenc');
    expect(await pick({'libx264', 'h264_amf', 'h264_qsv'}, VideoCodec.h264),
        'h264_qsv');
    expect(await pick({'libx264', 'h264_amf'}, VideoCodec.h264), 'h264_amf');
    expect(await pick({'libx265', 'hevc_amf'}, VideoCodec.hevc), 'hevc_amf');
    expect(await pick({'libaom-av1', 'av1_qsv'}, VideoCodec.av1), 'av1_qsv');
    expect(await pick({'libx264', 'h264_qsv'}, VideoCodec.h264, cpuOnly: true),
        'libx264');
  });

  test('Quick Sync gets its native pixel formats', () {
    expect(FfmpegRunner.pixelFormatFor(_info(), 'h264_qsv'), 'nv12');
    expect(FfmpegRunner.pixelFormatFor(_info(hdr: true), 'hevc_qsv'), 'p010le');
    expect(FfmpegRunner.pixelFormatFor(_info(), 'libx264'), 'yuv420p');
    expect(FfmpegRunner.pixelFormatFor(_info(hdr: true), 'libx265'),
        'yuv420p10le');
  });

  test('a failing hardware encoder falls back to the CPU and is not retried',
      () async {
    final ffmpeg = Binaries.resolve(Tool.ffmpeg);
    if (ffmpeg == null || Binaries.resolve(Tool.ffprobe) == null) {
      return markTestSkipped('ffmpeg/ffprobe tidak terpasang');
    }
    final work = Directory.systemTemp.createTempSync('labscale_hwfb_');
    addTearDown(() => work.deleteSync(recursive: true));
    final clip = p.join(work.path, 'clip.mp4');
    final made = await Process.run(ffmpeg, [
      '-y', '-hide_banner', '-loglevel', 'error', '-f', 'lavfi',
      '-i', 'testsrc2=size=160x120:rate=10:duration=1', '-pix_fmt', 'yuv420p',
      clip,
    ]);
    expect(made.exitCode, 0, reason: '${made.stderr}');

    // Pretend an encoder this ffmpeg cannot run passed the probe: the real
    // encode then fails exactly the way a broken driver would.
    FfmpegRunner.debugSetEncoderSupport(
      const EncoderSupport({'libx264', 'h264_amf'}),
    );
    final reporter = JobReporter();
    final result = await Pipeline(
      outputDir: p.join(work.path, 'out'),
      tempDir: p.join(work.path, 'tmp'),
    ).process(
      file: MediaFile.tryFrom(clip)!,
      rawOptions: const ProcessOptions(
        upscale: true,
        upscaleScale: 2,
        quality: Quality.fast,
      ),
      reporter: reporter,
    );
    await reporter.close();

    expect(result.isSuccess, isTrue, reason: result.error);
    expect(File(result.outputPath).lengthSync(), greaterThan(0));
    expect(reporter.history,
        contains(S.current.logHardwareFallback('h264_amf', 'libx264')));
    // The broken encoder is skipped for the rest of the session.
    expect((await FfmpegRunner.selectEncoder(VideoCodec.h264)).name, 'libx264');
  });
}
