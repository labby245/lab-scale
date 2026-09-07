/// Asking a 4x-only network for `-s 2` does not fail — the tool mis-stitches
/// its tiles and leaves a seam every 400 output pixels. Measured on a real
/// 736x1040 source: seam strength 39.6 at x=400 with `-s 2`, versus 9.1 when
/// the model runs at 4x and FFmpeg resizes down.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:labscale/core/esrgan_runner.dart';
import 'package:labscale/models/process_options.dart';

void main() {
  test('only AnimeVideoV3 ships weights below 4x', () {
    for (final m in UpscaleModel.values.where((m) => m.isAi)) {
      final expected = m == UpscaleModel.realesrAnimeVideoV3
          ? {2, 3, 4}
          : {4};
      expect(m.nativeScales, expected, reason: m.id);
    }
  });

  test('a 4x-only model is always run at 4x, whatever was asked', () {
    for (final scale in [1, 2, 3, 4]) {
      expect(EsrganRunner.ncnnScaleFor(UpscaleModel.ultramix, scale), 4,
          reason: 'skala $scale');
      expect(EsrganRunner.ncnnScaleFor(UpscaleModel.realesrganX4Plus, scale), 4,
          reason: 'skala $scale');
    }
  });

  test('AnimeVideoV3 is asked for the scale it has', () {
    const m = UpscaleModel.realesrAnimeVideoV3;
    expect(EsrganRunner.ncnnScaleFor(m, 2), 2);
    expect(EsrganRunner.ncnnScaleFor(m, 3), 3);
    expect(EsrganRunner.ncnnScaleFor(m, 4), 4);
    // No 1x weights exist, so that one still runs at 4x and resizes down.
    expect(EsrganRunner.ncnnScaleFor(m, 1), 4);
  });

  test('post-resize is required exactly when the model ran at a wider scale',
      () {
    expect(EsrganRunner.needsPostResize(UpscaleModel.ultramix, 2), isTrue);
    expect(EsrganRunner.needsPostResize(UpscaleModel.ultramix, 4), isFalse);
    expect(
        EsrganRunner.needsPostResize(UpscaleModel.realesrAnimeVideoV3, 2),
        isFalse);
    expect(EsrganRunner.needsPostResize(UpscaleModel.realesrganX4Plus, 1),
        isTrue);
  });
}
