/// Immutable processing options shared by the image and video pipelines.
library;

enum UpscaleModel {
  lanczos('lanczos', 'Lanczos — cepat, tanpa AI', null),
  realesrganX4Plus(
    'realesrgan-x4plus',
    'ESRGAN x4+ — foto / umum',
    'realesrgan-x4plus',
  ),
  realesrganX4PlusAnime(
    'realesrgan-x4plus-anime',
    'ESRGAN x4+ Anime — ilustrasi',
    'realesrgan-x4plus-anime',
  ),
  realesrAnimeVideoV3(
    'realesr-animevideov3',
    'ESRGAN AnimeVideoV3 — video anime',
    'realesr-animevideov3',
  );

  const UpscaleModel(this.id, this.label, this.ncnnName);

  /// Stable identifier used for preferences and output filename suffixes.
  final String id;
  final String label;

  /// Model name passed to `realesrgan-ncnn-vulkan -n`; null means "no AI".
  final String? ncnnName;

  bool get isAi => ncnnName != null;

  /// Native scale factor of the ncnn model. All bundled models are x4.
  int get nativeScale => 4;

  String get suffix => switch (this) {
        UpscaleModel.lanczos => 'lanczos',
        UpscaleModel.realesrganX4Plus => 'esrgan-real',
        UpscaleModel.realesrganX4PlusAnime => 'esrgan-anime',
        UpscaleModel.realesrAnimeVideoV3 => 'esrgan-video',
      };

  static UpscaleModel fromId(String? id) => UpscaleModel.values.firstWhere(
        (m) => m.id == id,
        orElse: () => UpscaleModel.lanczos,
      );
}

enum InterpEngine {
  ffmpeg('ffmpeg', 'FFmpeg (MCI bidir) — bawaan, lambat'),
  rife('rife', 'RIFE AI — 5–10× lebih cepat & halus');

  const InterpEngine(this.id, this.label);
  final String id;
  final String label;

  static InterpEngine fromId(String? id) => InterpEngine.values.firstWhere(
        (e) => e.id == id,
        orElse: () => InterpEngine.ffmpeg,
      );
}

enum Quality {
  fast('fast', 'Fast'),
  balanced('balanced', 'Balanced'),
  better('better', 'Better'),
  best('best', 'Best'),
  ultra('ultra', 'Ultra (lossless)');

  const Quality(this.id, this.label);
  final String id;
  final String label;

  static Quality fromId(String? id) => Quality.values.firstWhere(
        (q) => q.id == id,
        orElse: () => Quality.ultra,
      );
}

enum VideoCodec {
  h264('h264', 'H.264 (kompatibel)'),
  hevc('hevc', 'HEVC / H.265 (file lebih kecil)'),
  av1('av1', 'AV1 (terkecil — perlu HW/SW)');

  const VideoCodec(this.id, this.label);
  final String id;
  final String label;

  static VideoCodec fromId(String? id) => VideoCodec.values.firstWhere(
        (c) => c.id == id,
        orElse: () => VideoCodec.h264,
      );
}

const int kTargetFps = 60;
const double kTargetFpsDouble = 60.0;
const int kMinScale = 1;
const int kMaxScale = 4;

class ProcessOptions {
  const ProcessOptions({
    this.upscale = false,
    this.upscaleModel = UpscaleModel.lanczos,
    this.upscaleScale = 2,
    this.fpsBoost = false,
    this.interpEngine = InterpEngine.ffmpeg,
    this.sharpness = 0.3,
    this.quality = Quality.ultra,
    this.codec = VideoCodec.h264,
  });

  final bool upscale;
  final UpscaleModel upscaleModel;
  final int upscaleScale;
  final bool fpsBoost;
  final InterpEngine interpEngine;

  /// 0.0 = none, 1.0 = strong unsharp mask.
  final double sharpness;
  final Quality quality;
  final VideoCodec codec;

  bool get hasAnyOp => upscale || fpsBoost;

  /// Sharpening is presented in the UI as part of Upscale and is only recorded
  /// in [outputSuffix] when Upscale is on, so it must not silently apply to an
  /// FPS-boost-only job. Every stage reads this, never [sharpness] directly.
  double get effectiveSharpness => upscale ? sharpness : 0.0;

  /// True when the AI upscaler must run, which forces the frame-by-frame path.
  bool get useEsrgan => upscale && upscaleModel.isAi;

  /// Lanczos factor for the FFmpeg filter chain, or null when not applicable.
  int? get lanczosScale =>
      (upscale && !useEsrgan && upscaleScale > 1) ? upscaleScale : null;

  /// RIFE replaces FFmpeg's minterpolate, and it only works on frame folders.
  bool get useRife => fpsBoost && interpEngine == InterpEngine.rife;

  /// Whether the pipeline has to decode to PNG frames instead of a direct
  /// FFmpeg transcode.
  bool get needsFrames => useEsrgan || useRife;

  ProcessOptions copyWith({
    bool? upscale,
    UpscaleModel? upscaleModel,
    int? upscaleScale,
    bool? fpsBoost,
    InterpEngine? interpEngine,
    double? sharpness,
    Quality? quality,
    VideoCodec? codec,
  }) {
    return ProcessOptions(
      upscale: upscale ?? this.upscale,
      upscaleModel: upscaleModel ?? this.upscaleModel,
      upscaleScale: upscaleScale ?? this.upscaleScale,
      fpsBoost: fpsBoost ?? this.fpsBoost,
      interpEngine: interpEngine ?? this.interpEngine,
      sharpness: sharpness ?? this.sharpness,
      quality: quality ?? this.quality,
      codec: codec ?? this.codec,
    );
  }

  /// Filename suffix describing the applied operations, e.g.
  /// `_esrgan-real-2x_sharp30_60fps`.
  String outputSuffix() {
    final parts = <String>[];
    if (upscale) {
      parts.add('${upscaleModel.suffix}-${upscaleScale}x');
      if (effectiveSharpness > 0) {
        parts.add('sharp${(effectiveSharpness * 100).round()}');
      }
    }
    if (fpsBoost) parts.add('${kTargetFps}fps');
    return parts.isEmpty ? '_processed' : '_${parts.join('_')}';
  }
}
