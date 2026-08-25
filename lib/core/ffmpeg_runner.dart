/// FFmpeg/FFprobe orchestration: probing, filter chains, and encoding.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/process_options.dart';
import 'binaries.dart';
import 'job_log.dart';

/// Everything the encoder needs to know about the source file.
class MediaInfo {
  const MediaInfo({
    required this.width,
    required this.height,
    required this.fps,
    required this.frameCount,
    required this.durationSeconds,
    required this.hasAudio,
    required this.audioCodec,
    required this.colorPrimaries,
    required this.colorTransfer,
    required this.isHdr,
  });

  final int width;
  final int height;
  final double fps;
  final int frameCount;
  final double durationSeconds;
  final bool hasAudio;
  final String audioCodec;
  final String colorPrimaries;
  final String colorTransfer;
  final bool isHdr;

  static const MediaInfo unknown = MediaInfo(
    width: 1920,
    height: 1080,
    fps: 25,
    frameCount: 0,
    durationSeconds: 0,
    hasAudio: false,
    audioCodec: '',
    colorPrimaries: 'bt709',
    colorTransfer: 'bt709',
    isHdr: false,
  );
}

class EncoderSupport {
  const EncoderSupport(this._encoders);

  final Set<String> _encoders;

  bool has(String name) => _encoders.contains(name);

  bool get hasNvenc =>
      has('h264_nvenc') || has('hevc_nvenc') || has('av1_nvenc');

  /// Short human-readable summary shown under the codec selector.
  String get summary {
    final hw = <String>[
      if (has('h264_nvenc')) 'H.264 NVENC',
      if (has('hevc_nvenc')) 'HEVC NVENC',
      if (has('av1_nvenc')) 'AV1 NVENC',
      if (has('h264_videotoolbox')) 'H.264 VideoToolbox',
      if (has('hevc_videotoolbox')) 'HEVC VideoToolbox',
    ];
    return hw.isEmpty ? 'encoder CPU saja' : hw.join(' · ');
  }

  static const EncoderSupport none = EncoderSupport(<String>{});
}

class FfmpegRunner {
  FfmpegRunner._();

  // ── Quality presets ───────────────────────────────────────────────────────

  static const _x264 = {
    Quality.fast: ['-preset', 'veryfast', '-crf', '23'],
    Quality.balanced: ['-preset', 'medium', '-crf', '20'],
    Quality.better: ['-preset', 'slow', '-crf', '18'],
    Quality.best: ['-preset', 'veryslow', '-crf', '16'],
    Quality.ultra: ['-preset', 'placebo', '-crf', '0'],
  };

  static const _x265 = {
    Quality.fast: ['-preset', 'veryfast', '-crf', '26'],
    Quality.balanced: ['-preset', 'medium', '-crf', '23'],
    Quality.better: ['-preset', 'slow', '-crf', '21'],
    Quality.best: ['-preset', 'veryslow', '-crf', '19'],
    Quality.ultra: ['-preset', 'veryslow', '-crf', '12'],
  };

  static const _av1Cpu = {
    Quality.fast: ['-cpu-used', '8', '-crf', '32'],
    Quality.balanced: ['-cpu-used', '5', '-crf', '28'],
    Quality.better: ['-cpu-used', '4', '-crf', '24'],
    Quality.best: ['-cpu-used', '2', '-crf', '22'],
    Quality.ultra: ['-cpu-used', '1', '-crf', '18'],
  };

  static const _h264Nvenc = {
    Quality.fast: ['-preset', 'fast', '-rc:v', 'vbr', '-cq', '23', '-b:v', '0'],
    Quality.balanced: ['-preset', 'medium', '-rc:v', 'vbr', '-cq', '20', '-b:v', '0'],
    Quality.better: ['-preset', 'slow', '-rc:v', 'vbr', '-cq', '18', '-b:v', '0'],
    Quality.best: ['-preset', 'slow', '-rc:v', 'vbr', '-cq', '16', '-b:v', '0'],
    Quality.ultra: ['-preset', 'slow', '-rc:v', 'vbr', '-cq', '1', '-b:v', '0'],
  };

  static const _hevcNvenc = {
    Quality.fast: ['-preset', 'fast', '-rc:v', 'vbr', '-cq', '26', '-b:v', '0'],
    Quality.balanced: ['-preset', 'medium', '-rc:v', 'vbr', '-cq', '23', '-b:v', '0'],
    Quality.better: ['-preset', 'slow', '-rc:v', 'vbr', '-cq', '21', '-b:v', '0'],
    Quality.best: ['-preset', 'slow', '-rc:v', 'vbr', '-cq', '19', '-b:v', '0'],
    Quality.ultra: ['-preset', 'slow', '-rc:v', 'vbr', '-cq', '12', '-b:v', '0'],
  };

  static const _av1Nvenc = {
    Quality.fast: ['-preset', 'p3', '-rc:v', 'vbr', '-cq', '32', '-b:v', '0'],
    Quality.balanced: ['-preset', 'p4', '-rc:v', 'vbr', '-cq', '28', '-b:v', '0'],
    Quality.better: ['-preset', 'p5', '-rc:v', 'vbr', '-cq', '24', '-b:v', '0'],
    Quality.best: ['-preset', 'p6', '-rc:v', 'vbr', '-cq', '22', '-b:v', '0'],
    Quality.ultra: ['-preset', 'p7', '-rc:v', 'vbr', '-cq', '18', '-b:v', '0'],
  };

  static const _videoToolbox = {
    Quality.fast: ['-q:v', '45'],
    Quality.balanced: ['-q:v', '55'],
    Quality.better: ['-q:v', '65'],
    Quality.best: ['-q:v', '75'],
    Quality.ultra: ['-q:v', '90'],
  };

  static const jpegQuality = {
    Quality.fast: 8,
    Quality.balanced: 5,
    Quality.better: 3,
    Quality.best: 2,
    Quality.ultra: 2,
  };

  // ── Capability probing ────────────────────────────────────────────────────

  static EncoderSupport? _encoderCache;

  /// Hardware encoders whose presence in `-encoders` does not prove they work.
  ///
  /// FFmpeg lists these whenever the *build* has support compiled in, even when
  /// the machine has no such GPU or a driver too old for the SDK version. The
  /// only reliable check is to attempt a real encode.
  static const _hardwareEncoders = {
    'h264_nvenc', 'hevc_nvenc', 'av1_nvenc',
    'h264_videotoolbox', 'hevc_videotoolbox',
    'h264_qsv', 'hevc_qsv', 'av1_qsv',
    'h264_amf', 'hevc_amf', 'av1_amf',
  };

  static Future<EncoderSupport> encoders() async {
    final cached = _encoderCache;
    if (cached != null) return cached;

    final ffmpeg = Binaries.resolve(Tool.ffmpeg);
    if (ffmpeg == null) return EncoderSupport.none;

    try {
      final result = await Process.run(ffmpeg, ['-hide_banner', '-encoders']);
      final listed = <String>{};
      for (final line in const LineSplitter().convert(result.stdout as String)) {
        // Encoder rows look like: " V....D h264_nvenc  NVIDIA NVENC H.264"
        final match = RegExp(r'^\s*[VAS][\w.]{5}\s+(\S+)').firstMatch(line);
        if (match != null) listed.add(match.group(1)!);
      }

      // Software encoders are trustworthy; hardware ones get a trial run.
      final verified = listed.difference(_hardwareEncoders);
      for (final name in listed.intersection(_hardwareEncoders)) {
        if (await _canEncode(ffmpeg, name)) verified.add(name);
      }

      final support = EncoderSupport(verified);
      _encoderCache = support;
      return support;
    } on ProcessException {
      return EncoderSupport.none;
    }
  }

  /// Encodes one synthetic frame to /dev/null to prove the encoder opens.
  static Future<bool> _canEncode(String ffmpeg, String encoder) async {
    try {
      final result = await Process.run(ffmpeg, [
        '-hide_banner', '-loglevel', 'error', '-nostats',
        '-f', 'lavfi', '-i', 'nullsrc=s=256x256:d=1',
        '-c:v', encoder,
        '-frames:v', '1',
        '-f', 'null', '-',
      ]).timeout(const Duration(seconds: 20));
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  /// Forgets the probed encoder set. Used by tests and after a driver change.
  static void invalidateEncoderCache() => _encoderCache = null;

  /// Picks the best available encoder for [codec].
  /// Returns the encoder name plus its quality preset table.
  static Future<({String name, Map<Quality, List<String>> presets})>
      selectEncoder(VideoCodec codec) async {
    final support = await encoders();

    if (codec == VideoCodec.hevc) {
      if (support.has('hevc_nvenc')) return (name: 'hevc_nvenc', presets: _hevcNvenc);
      if (support.has('hevc_videotoolbox')) {
        return (name: 'hevc_videotoolbox', presets: _videoToolbox);
      }
      if (support.has('libx265')) return (name: 'libx265', presets: _x265);
    }
    if (codec == VideoCodec.av1) {
      if (support.has('av1_nvenc')) return (name: 'av1_nvenc', presets: _av1Nvenc);
      if (support.has('libsvtav1')) return (name: 'libsvtav1', presets: _av1Cpu);
      if (support.has('libaom-av1')) return (name: 'libaom-av1', presets: _av1Cpu);
    }
    if (support.has('h264_nvenc')) return (name: 'h264_nvenc', presets: _h264Nvenc);
    if (support.has('h264_videotoolbox')) {
      return (name: 'h264_videotoolbox', presets: _videoToolbox);
    }
    return (name: 'libx264', presets: _x264);
  }

  // ── Probing ───────────────────────────────────────────────────────────────

  static Future<MediaInfo> probe(String path) async {
    final ffprobe = Binaries.resolve(Tool.ffprobe);
    if (ffprobe == null) return MediaInfo.unknown;

    try {
      final result = await Process.run(ffprobe, [
        '-v', 'error',
        '-show_streams',
        '-show_format',
        '-of', 'json',
        path,
      ]);
      if (result.exitCode != 0) return MediaInfo.unknown;

      final root = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final streams = (root['streams'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final video = streams.firstWhere(
        (s) => s['codec_type'] == 'video',
        orElse: () => const {},
      );
      if (video.isEmpty) return MediaInfo.unknown;
      final audio = streams.firstWhere(
        (s) => s['codec_type'] == 'audio',
        orElse: () => const {},
      );

      final fps = _parseRational(video['r_frame_rate'] as String?) ?? 25.0;
      final duration = double.tryParse(
            (root['format']?['duration'] ?? '') as String,
          ) ??
          0.0;
      final declaredFrames = int.tryParse('${video['nb_frames'] ?? ''}') ?? 0;
      final frameCount =
          declaredFrames > 0 ? declaredFrames : (duration * fps).round();

      final primaries = (video['color_primaries'] as String?) ?? 'bt709';
      final transfer = (video['color_transfer'] as String?) ?? 'bt709';

      return MediaInfo(
        width: (video['width'] as num?)?.toInt() ?? 1920,
        height: (video['height'] as num?)?.toInt() ?? 1080,
        fps: fps,
        frameCount: frameCount,
        durationSeconds: duration,
        hasAudio: audio.isNotEmpty,
        audioCodec: (audio['codec_name'] as String?) ?? '',
        colorPrimaries: primaries,
        colorTransfer: transfer,
        isHdr: transfer == 'smpte2084' ||
            transfer == 'arib-std-b67' ||
            primaries == 'bt2020',
      );
    } on ProcessException {
      return MediaInfo.unknown;
    } on FormatException {
      return MediaInfo.unknown;
    }
  }

  static double? _parseRational(String? value) {
    if (value == null) return null;
    final parts = value.split('/');
    if (parts.length != 2) return double.tryParse(value);
    final num = double.tryParse(parts[0]);
    final den = double.tryParse(parts[1]);
    if (num == null || den == null || den == 0) return null;
    return num / den;
  }

  // ── Filter chains ─────────────────────────────────────────────────────────

  /// Builds the `-vf` chain. Returns null when no filtering is needed.
  static String? buildFilters({
    int? lanczosScale,
    bool minterpolate = false,
    double sharpness = 0.0,
  }) {
    final parts = <String>[
      if (lanczosScale != null && lanczosScale > 1)
        'scale=iw*$lanczosScale:ih*$lanczosScale:flags=lanczos',
      if (minterpolate)
        'minterpolate=fps=$kTargetFps:mi_mode=mci:mc_mode=aobmc:'
            'me_mode=bidir:vsbmc=1',
      if (sharpness > 0) _unsharp(sharpness),
    ];
    return parts.isEmpty ? null : parts.join(',');
  }

  static String _unsharp(double sharpness) {
    final amount = (sharpness * 1.5).toStringAsFixed(3);
    return 'unsharp=5:5:$amount:5:5:$amount';
  }

  static List<String> _colorArgs(MediaInfo info) {
    if (info.isHdr) {
      return [
        '-color_primaries', info.colorPrimaries,
        '-color_trc', info.colorTransfer,
        '-colorspace', 'bt2020nc',
      ];
    }
    return [
      '-color_primaries', 'bt709',
      '-color_trc', 'bt709',
      '-colorspace', 'bt709',
    ];
  }

  static List<String> _audioArgs(MediaInfo info) {
    if (!info.hasAudio) return ['-an'];
    // Copy AAC untouched; anything else gets a clean 192k AAC transcode.
    if (info.audioCodec == 'aac') return ['-c:a', 'copy'];
    return ['-c:a', 'aac', '-b:a', '192k'];
  }

  // ── Operations ────────────────────────────────────────────────────────────

  /// Single-pass transcode. Used when no per-frame AI stage is required.
  static Future<void> transcode({
    required String input,
    required String output,
    required ProcessOptions options,
    required MediaInfo info,
    required JobReporter reporter,
    ProgressSink? progress,
  }) async {
    final encoder = await selectEncoder(options.codec);
    final filters = buildFilters(
      lanczosScale: options.lanczosScale,
      minterpolate: options.fpsBoost && options.interpEngine == InterpEngine.ffmpeg,
      sharpness: options.sharpness,
    );

    reporter.log('Enkode langsung [${options.quality.label}] via ${encoder.name}…');

    final expectedFrames = options.fpsBoost
        ? (info.durationSeconds * kTargetFps).round()
        : info.frameCount;

    await _run(
      [
        '-y', '-i', input,
        '-c:v', encoder.name,
        ...encoder.presets[options.quality]!,
        '-pix_fmt', 'yuv420p',
        ..._colorArgs(info),
        '-movflags', '+faststart',
        ..._audioArgs(info),
        if (filters != null) ...['-filter:v', filters],
        output,
      ],
      reporter: reporter,
      progress: progress,
      totalFrames: expectedFrames,
    );
    reporter.log('Enkode selesai.');
  }

  /// Decodes every frame to lossless PNG in [framesDir].
  static Future<void> extractFrames({
    required String input,
    required String framesDir,
    required JobReporter reporter,
    required MediaInfo info,
    ProgressSink? progress,
  }) async {
    await Directory(framesDir).create(recursive: true);
    reporter.log('Ekstrak frame dari video (${info.frameCount} frame)…');
    await _run(
      ['-y', '-i', input, p.join(framesDir, 'frame_%06d.png')],
      reporter: reporter,
      progress: progress,
      totalFrames: info.frameCount,
    );
    reporter.log('Ekstrak frame selesai.');
  }

  /// Re-assembles PNG frames into the final video, muxing the source audio.
  ///
  /// [postWidth]/[postHeight] resize the AI-upscaled frames down to the exact
  /// requested output size; [sharpness] applies the unsharp mask in the same
  /// pass, which is far cheaper than touching every PNG on disk.
  static Future<void> encodeFromFrames({
    required String framesDir,
    required double fps,
    required String audioSource,
    required String output,
    required ProcessOptions options,
    required MediaInfo info,
    required JobReporter reporter,
    int? postWidth,
    int? postHeight,
    double sharpness = 0.0,
    bool minterpolate = false,
    ProgressSink? progress,
  }) async {
    final encoder = await selectEncoder(options.codec);
    reporter.log('Enkode [${options.quality.label}] via ${encoder.name}…');

    final filterParts = <String>[
      if (postWidth != null && postHeight != null)
        'scale=$postWidth:$postHeight:flags=lanczos',
      if (minterpolate)
        'minterpolate=fps=$kTargetFps:mi_mode=mci:mc_mode=aobmc:'
            'me_mode=bidir:vsbmc=1',
      if (sharpness > 0) _unsharp(sharpness),
    ];

    final totalFrames = Directory(framesDir)
        .listSync()
        .where((e) => e.path.endsWith('.png'))
        .length;

    await _run(
      [
        '-y',
        '-framerate', fps.toString(),
        '-i', p.join(framesDir, 'frame_%06d.png'),
        if (info.hasAudio) ...['-i', audioSource],
        '-map', '0:v:0',
        if (info.hasAudio) ...['-map', '1:a:0?'],
        '-c:v', encoder.name,
        ...encoder.presets[options.quality]!,
        '-pix_fmt', 'yuv420p',
        ..._colorArgs(info),
        '-movflags', '+faststart',
        ..._audioArgs(info),
        if (filterParts.isNotEmpty) ...['-filter:v', filterParts.join(',')],
        output,
      ],
      reporter: reporter,
      progress: progress,
      totalFrames: totalFrames,
    );
    reporter.log('Enkode selesai.');
  }

  /// Applies a resize and/or unsharp mask to a single still image.
  ///
  /// Pass either [lanczosScale] (a multiplier) or an explicit
  /// [targetWidth]/[targetHeight] pair, not both.
  static Future<void> filterImage({
    required String input,
    required String output,
    required JobReporter reporter,
    int? lanczosScale,
    int? targetWidth,
    int? targetHeight,
    double sharpness = 0.0,
    Quality quality = Quality.ultra,
  }) async {
    final explicitSize = targetWidth != null && targetHeight != null;
    final parts = <String>[
      if (explicitSize) 'scale=$targetWidth:$targetHeight:flags=lanczos',
      if (!explicitSize && lanczosScale != null && lanczosScale > 1)
        'scale=iw*$lanczosScale:ih*$lanczosScale:flags=lanczos',
      if (sharpness > 0) _unsharp(sharpness),
    ];
    final filters = parts.isEmpty ? null : parts.join(',');
    final isJpeg = output.toLowerCase().endsWith('.jpg') ||
        output.toLowerCase().endsWith('.jpeg');

    await _run(
      [
        '-y', '-i', input,
        if (filters != null) ...['-filter:v', filters],
        if (isJpeg) ...['-q:v', '${jpegQuality[quality]}'],
        '-frames:v', '1',
        output,
      ],
      reporter: reporter,
    );
  }

  // ── Process plumbing ──────────────────────────────────────────────────────

  /// Runs FFmpeg, streaming `-progress` updates and keeping the stderr tail for
  /// error reporting.
  static Future<void> _run(
    List<String> args, {
    required JobReporter reporter,
    ProgressSink? progress,
    int totalFrames = 0,
  }) async {
    final ffmpeg = Binaries.require(Tool.ffmpeg);
    final fullArgs = [
      '-hide_banner',
      '-loglevel', 'error',
      '-nostats',
      if (progress != null) ...['-progress', 'pipe:1'],
      ...args,
    ];

    final process = await Process.start(ffmpeg, fullArgs);
    final stderrTail = <String>[];

    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (progress == null || totalFrames <= 0) return;
      final match = RegExp(r'^frame=(\d+)').firstMatch(line);
      if (match != null) {
        final done = int.parse(match.group(1)!);
        progress(done / totalFrames);
      }
    }).asFuture<void>();

    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.trim().isEmpty) return;
      stderrTail.add(line);
      if (stderrTail.length > 40) stderrTail.removeAt(0);
    }).asFuture<void>();

    final exitCode = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);

    if (exitCode != 0) {
      throw PipelineException(
        'FFmpeg gagal (exit $exitCode)',
        detail: stderrTail.join('\n'),
      );
    }
    progress?.call(1.0);
  }
}
