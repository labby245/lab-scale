/// Immutable processing options shared by the image and video pipelines.
library;

/// The upscalers offered in the UI. Their labels — by what each is *for*,
/// not by model name — live in `S.modelLabel`.
///
/// Ordering is the dropdown's order. The three AI entries are the whole menu
/// wherever AI runs; Lanczos is only offered where it does not (see
/// `AppController.offeredModels`).
///
/// Measured on an M1, each source reduced 4x then upscaled back: a flat
/// design poster, and a 1920x1080 crop of real 4K aerial footage.
enum UpscaleModel {
  /// The cleanest of every model tried on flat colour and type (design SSIM
  /// 0.966, against 0.949 for x4plus). CC BY-NC-SA, so downloaded on demand
  /// rather than bundled.
  ultramix('ultramix-balanced-4x', 'ultramix-balanced-4x', 'ultramix'),

  /// The bundled, commercially safe (BSD) photo model.
  realesrganX4Plus('realesrgan-x4plus', 'realesrgan-x4plus', 'esrgan-real'),

  /// xinntao's realesr-general-x4v3 under Upscayl's file name. Softer than
  /// x4plus (photo detail 0.72x against 0.93x) but 0.8s a frame where x4plus
  /// takes 6.3s, which is what makes AI video upscaling practical; the anime
  /// video model it replaced was as fast but left real footage blurred. Also
  /// the model the startup GPU probe runs, for the same speed.
  upscaylLite('upscayl-lite-4x', 'upscayl-lite-4x', 'video'),

  /// No AI: FFmpeg's Lanczos filter. Offered only where Real-ESRGAN cannot
  /// run, as the one upscaler that still works there.
  lanczos('lanczos', null, 'lanczos', nativeScales: {});

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

  /// Models dropped from the menu in 2.2.0, mapped to the entry that does
  /// the same job, so a stored preference lands somewhere sensible.
  static const _retired = {
    'ultrasharp-4x': ultramix,
    'realesrgan-x4plus-anime': ultramix,
    'remacri-4x': realesrganX4Plus,
    'realesr-animevideov3': upscaylLite,
  };

  static UpscaleModel fromId(String? id) =>
      _retired[id] ??
      UpscaleModel.values.firstWhere(
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
