import 'package:flutter_test/flutter_test.dart';
import 'package:labscale/core/ffmpeg_runner.dart';
import 'package:labscale/models/process_options.dart';

void main() {
  group('FfmpegRunner.buildFilters', () {
    test('returns null when nothing needs filtering', () {
      expect(FfmpegRunner.buildFilters(), isNull);
    });

    test('skips a 1x lanczos scale', () {
      expect(FfmpegRunner.buildFilters(lanczosScale: 1), isNull);
    });

    test('emits a lanczos scale filter', () {
      expect(
        FfmpegRunner.buildFilters(lanczosScale: 2),
        'scale=iw*2:ih*2:flags=lanczos',
      );
    });

    test('emits minterpolate at the target frame rate', () {
      final chain = FfmpegRunner.buildFilters(minterpolate: true);
      expect(chain, contains('minterpolate=fps=$kTargetFps'));
      expect(chain, contains('mi_mode=mci'));
    });

    test('emits an unsharp mask scaled by strength', () {
      expect(
        FfmpegRunner.buildFilters(sharpness: 0.4),
        'unsharp=5:5:0.600:5:5:0.600',
      );
    });

    test('omits unsharp at zero strength', () {
      expect(FfmpegRunner.buildFilters(sharpness: 0), isNull);
    });

    test('orders scale before interpolation before sharpening', () {
      final chain = FfmpegRunner.buildFilters(
        lanczosScale: 2,
        minterpolate: true,
        sharpness: 0.5,
      )!;
      final parts = chain.split(',');
      expect(parts.first, startsWith('scale='));
      expect(parts[1], startsWith('minterpolate='));
      expect(parts.last, startsWith('unsharp='));
    });
  });

  group('EncoderSupport', () {
    test('reports hardware encoders in the summary', () {
      const support = EncoderSupport({'libx264', 'h264_nvenc', 'hevc_nvenc'});
      expect(support.hasNvenc, isTrue);
      expect(support.summary, contains('H.264 NVENC'));
      expect(support.summary, contains('HEVC NVENC'));
    });

    test('falls back to a CPU-only message', () {
      const support = EncoderSupport({'libx264'});
      expect(support.hasNvenc, isFalse);
      expect(support.summary, 'encoder CPU saja');
    });
  });
}
