/// Immutable processing options shared by the image and video pipelines.
library;

/// The upscalers offered in the UI. Their labels — by what each is *for*,
/// not by model name — live in `S.modelLabel`.
///
/// Ordering is the dropdown's order: the everyday choices first.
///
/// The figures in each comment come from measuring on an M1 — a 1920x1280
/// original reduced 4x then upscaled back, scored against the original.
/// "detail" is how much fine detail came back relative to the original: 1.00x
/// is right, below is blurry, above is invented.
enum UpscaleModel {
  lanczos('lanczos', null, 'lanczos', nativeScales: {}),

  /// Design SSIM 0.9931 (best of every model tried), photo detail 0.99x.
  /// The strongest all-rounder, and markedly better than x4plus on flat
  /// colour and type, where x4plus fills in letter counters and rings edges.
  ultramix('ultramix-balanced-4x', 'ultramix-balanced-4x', 'ultramix'),

  /// Design SSIM 0.9875, photo detail 1.05x — a touch crisper than the
  /// original rather than faithful to it.
  ultrasharp('ultrasharp-4x', 'ultrasharp-4x', 'ultrasharp'),

  /// Design SSIM 0.9827, photo detail 0.93x. Kept as the familiar baseline.
  realesrganX4Plus('realesrgan-x4plus', 'realesrgan-x4plus', 'esrgan-real'),

  /// Photo detail 1.59x — invents a lot of texture. Some people want exactly
  /// that on soft sources; it is the wrong default for a faithful upscale.
  remacri('remacri-4x', 'remacri-4x', 'remacri'),

  realesrganX4PlusAnime(
    'realesrgan-x4plus-anime',
    'realesrgan-x4plus-anime',
    'esrgan-anime',
  ),

  realesrAnimeVideoV3(
    'realesr-animevideov3',
    'realesr-animevideov3',
    'esrgan-video',
    // The only model shipping separate weights per scale.
    nativeScales: {2, 3, 4},
  ),

  /// ~0.7s where the 32 MB networks take ~6.5s, at a real but modest quality
  /// cost. Meant for checking a batch before committing to it.
  upscaylLite('upscayl-lite-4x', 'upscayl-lite-4x', 'lite');

  const UpscaleModel(
    this.id,
    this.ncnnName,
    this.suffix, {
    this.nativeScales = const {4},
  });

  /// Stable identifier used for preferences and output filename suffixes.
  final String id;

  /// Model name passed to `realesrgan-ncnn-vulkan -n`; null means "no AI".
  final String? ncnnName;

  /// Appears in the output filename so a result says how it was made.
  final String suffix;

  bool get isAi => ncnnName != null;

  /// Scales this model actually ships weights for.
  ///
  /// Handing a 4x-only network `-s 2` does not fail — the tool stitches its
  /// tiles with the wrong arithmetic and returns a torn image, at exactly the
  /// requested size so no dimension check catches it. Any scale not listed
  /// here is reached by running the model at its widest and letting FFmpeg
  /// resize down afterwards.
  ///
  /// Declared per model rather than derived in a getter, so a network that
  /// ships x2 weights is a matter of saying so on its own line instead of
  /// remembering to amend a condition elsewhere.
  final Set<int> nativeScales;

  static UpscaleModel fromId(String? id) => UpscaleModel.values.firstWhere(
    (m) => m.id == id,
    orElse: () => UpscaleModel.lanczos,
  );
}

enum InterpEngine {
  ffmpeg('ffmpeg'),
  rife('rife');

  const InterpEngine(this.id);
  final String id;

  static InterpEngine fromId(String? id) => InterpEngine.values.firstWhere(
    (e) => e.id == id,
    orElse: () => InterpEngine.ffmpeg,
  );
}

enum Quality {
  fast('fast'),
  balanced('balanced'),
  better('better'),
  best('best'),
  ultra('ultra');

  const Quality(this.id);
  final String id;

  static Quality fromId(String? id) =>
      Quality.values.firstWhere((q) => q.id == id, orElse: () => Quality.ultra);
}

enum VideoCodec {
  h264('h264'),
  hevc('hevc'),
  av1('av1');

  const VideoCodec(this.id);
  final String id;

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
