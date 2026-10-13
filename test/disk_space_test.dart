import 'package:flutter_test/flutter_test.dart';
import 'package:labscale/core/disk_space.dart';
import 'package:labscale/models/process_options.dart';

void main() {
  group('DiskSpace.estimatePeakBytes', () {
    int estimate(ProcessOptions options) => DiskSpace.estimatePeakBytes(
          width: 100,
          height: 100,
          frameCount: 30,
          fps: 30,
          options: options,
        );

    test('extraction alone is one frame set', () {
      // Lanczos never takes the frames path, but the estimate must still be
      // sane if asked: one set of source frames.
      expect(estimate(const ProcessOptions(upscale: true)),
          (30 * 100 * 100 * kPngBytesPerPixel).round());
    });

    test('a 4x-only network at 2x still costs 4x frames', () {
      // The trap from the README: 2x on x4plus runs the 4x network, so the
      // upscaled frames are 16x the source pixels, not 4x.
      final bytes = estimate(const ProcessOptions(
        upscale: true,
        upscaleModel: UpscaleModel.realesrganX4Plus,
        upscaleScale: 2,
      ));
      expect(bytes, ((30 + 30 * 16) * 100 * 100 * kPngBytesPerPixel).round());
    });

    test('AnimeVideoV3 at 2x really is cheaper', () {
      final anime = estimate(const ProcessOptions(
        upscale: true,
        upscaleModel: UpscaleModel.realesrAnimeVideoV3,
        upscaleScale: 2,
      ));
      final x4plus = estimate(const ProcessOptions(
        upscale: true,
        upscaleModel: UpscaleModel.realesrganX4Plus,
        upscaleScale: 2,
      ));
      expect(anime, lessThan(x4plus));
    });

    test('RIFE doubles a 30fps clip before the upscaler sees it', () {
      final bytes = estimate(const ProcessOptions(
        upscale: true,
        upscaleModel: UpscaleModel.realesrganX4Plus,
        upscaleScale: 4,
        fpsBoost: true,
        interpEngine: InterpEngine.rife,
      ));
      // 60 interpolated frames in, 60 frames at 16x the pixels out.
      expect(bytes, ((60 + 60 * 16) * 100 * 100 * kPngBytesPerPixel).round());
    });
  });

  group('DiskSpace.parseDfOutput', () {
    test('reads the available column of POSIX output', () {
      const out = 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
          '/dev/disk3s5 482797652 391175648 71246228 85% /System/Volumes/Data\n';
      expect(DiskSpace.parseDfOutput(out), 71246228 * 1024);
    });

    test('returns null for anything unexpected', () {
      expect(DiskSpace.parseDfOutput(''), isNull);
      expect(DiskSpace.parseDfOutput('just one line'), isNull);
    });
  });
}
