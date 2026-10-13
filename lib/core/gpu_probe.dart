/// Proves the ncnn tools can actually run here, not merely that they exist.
///
/// Both run on Vulkan. On a PC whose GPU or driver has no Vulkan — common on
/// older laptops (a GeForce 700M or an Intel HD 4000 era machine) — Windows
/// has no `vulkan-1.dll` at all and the tools die before printing anything,
/// with STATUS_DLL_NOT_FOUND. Judged by file presence alone they looked
/// ready: the status bar showed them green, RIFE became the default 60 FPS
/// engine, and every job then failed with an exit code nobody can read.
///
/// So each tool gets one real job on a tiny image at startup. One that fails
/// is treated as missing everywhere — the UI greys it out with the reason,
/// and the pipeline's existing fallback (RIFE → FFmpeg minterpolate) applies.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'binaries.dart';

/// Windows NTSTATUS for "a DLL the program needs was not found", as the
/// signed 32-bit exit code Dart reports.
const int kStatusDllNotFound = -1073741515; // 0xC0000135

/// Why a probe failed, in terms the UI can explain.
enum GpuProbeFailure {
  /// No Vulkan loader on the system: the GPU/driver does not support Vulkan.
  noVulkan,

  /// The tool started but could not finish a tiny job (no usable GPU device,
  /// a driver error, or it hung).
  failed,
}

class GpuProbeResult {
  const GpuProbeResult(this.failure, [this.detail = '']);

  final GpuProbeFailure failure;

  /// The tool's last stderr line or exit code, for the log.
  final String detail;
}

class GpuProbe {
  GpuProbe._();

  static const Duration _timeout = Duration(seconds: 30);

  /// Runs Real-ESRGAN on a 16×16 image with [ncnnModel] from [modelsDir].
  /// Null means it works.
  static Future<GpuProbeResult?> esrgan({
    required String binary,
    required String modelsDir,
    required String ncnnModel,
    required String workDir,
  }) async {
    final dir = await Directory(workDir).createTemp('gpu_probe_');
    try {
      final input = p.join(dir.path, 'in.png');
      final output = p.join(dir.path, 'out.png');
      await File(input).writeAsBytes(tinyPng());
      return await _run(
        binary,
        ['-i', input, '-o', output, '-n', ncnnModel, '-s', '4', '-m', modelsDir],
        succeeded: () => File(output).existsSync(),
      );
    } finally {
      await _delete(dir);
    }
  }

  /// Interpolates two 16×16 frames into three with RIFE. Null means it works.
  static Future<GpuProbeResult?> rife({
    required String binary,
    required String modelsDir,
    required String workDir,
  }) async {
    final dir = await Directory(workDir).createTemp('gpu_probe_');
    try {
      final frames = Directory(p.join(dir.path, 'in'))..createSync();
      final out = Directory(p.join(dir.path, 'out'))..createSync();
      final png = tinyPng();
      await File(p.join(frames.path, 'frame_000001.png')).writeAsBytes(png);
      await File(p.join(frames.path, 'frame_000002.png')).writeAsBytes(png);
      return await _run(
        binary,
        ['-i', frames.path, '-o', out.path, '-n', '3', '-m', modelsDir],
        succeeded: () => out.listSync().whereType<File>().isNotEmpty,
      );
    } finally {
      await _delete(dir);
    }
  }

  static Future<GpuProbeResult?> _run(
    String binary,
    List<String> args, {
    required bool Function() succeeded,
  }) async {
    final Process process;
    try {
      process = await Process.start(binary, args);
    } on ProcessException catch (e) {
      return GpuProbeResult(GpuProbeFailure.failed, e.message);
    }
    final stderrLines = <String>[];
    final stderrDone = process.stderr
        .transform(const SystemEncoding().decoder)
        .listen((chunk) => stderrLines.addAll(
              chunk.split(RegExp(r'[\r\n]+')).where((l) => l.trim().isNotEmpty),
            ))
        .asFuture<void>();
    unawaited(process.stdout.drain<void>());

    final exitCode = await process.exitCode.timeout(_timeout, onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      return -1;
    });
    await stderrDone.timeout(const Duration(seconds: 2), onTimeout: () {});

    if (exitCode == 0 && succeeded()) return null;
    if (exitCode == kStatusDllNotFound) {
      return GpuProbeResult(GpuProbeFailure.noVulkan, 'vulkan-1.dll');
    }
    final last = stderrLines.isEmpty ? '' : stderrLines.last.trim();
    return GpuProbeResult(
      GpuProbeFailure.failed,
      last.isEmpty ? 'exit $exitCode' : '$last (exit $exitCode)',
    );
  }

  static Future<void> _delete(Directory dir) async {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // A leftover 16×16 PNG in the temp folder harms nobody.
    }
  }
}

/// Real-ESRGAN's fastest bundled model, for the probe: `upscayl-lite-4x` takes
/// well under a second, x4plus several.
String? probeModelFor(String modelsDir) {
  for (final name in const [
    'upscayl-lite-4x',
    'realesr-animevideov3-x4',
    'realesrgan-x4plus-anime',
    'realesrgan-x4plus',
  ]) {
    if (File(p.join(modelsDir, '$name.param')).existsSync() &&
        File(p.join(modelsDir, '$name.bin')).existsSync()) {
      return name.endsWith('-x4') ? name.substring(0, name.length - 3) : name;
    }
  }
  return null;
}

/// Probes both tools in parallel and marks any that cannot run as unusable
/// in [Binaries], so every later availability check agrees.
Future<void> probeGpuTools(String workDir) async {
  Binaries.clearUnusable();
  final checks = <Future<void>>[];

  final esrgan = Binaries.resolve(Tool.realesrgan);
  final esrganModels = Binaries.modelsDir(Tool.realesrgan);
  final model = esrganModels == null ? null : probeModelFor(esrganModels);
  if (esrgan != null && esrganModels != null && model != null) {
    checks.add(GpuProbe.esrgan(
      binary: esrgan,
      modelsDir: esrganModels,
      ncnnModel: model,
      workDir: workDir,
    ).then((r) {
      if (r != null) Binaries.markUnusable(Tool.realesrgan, r);
    }));
  }

  final rife = Binaries.resolve(Tool.rife);
  final rifeModels = Binaries.modelsDir(Tool.rife);
  if (rife != null && rifeModels != null) {
    checks.add(GpuProbe.rife(
      binary: rife,
      modelsDir: rifeModels,
      workDir: workDir,
    ).then((r) {
      if (r != null) Binaries.markUnusable(Tool.rife, r);
    }));
  }

  await Future.wait(checks);
}

/// A 16×16 mid-grey RGB PNG, built here so the probe needs no asset and no
/// image package.
Uint8List tinyPng() {
  const size = 16;
  final raw = BytesBuilder();
  for (var y = 0; y < size; y++) {
    raw.addByte(0); // filter: none
    for (var x = 0; x < size * 3; x++) {
      raw.addByte(128);
    }
  }

  final ihdr = ByteData(13)
    ..setUint32(0, size)
    ..setUint32(4, size)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 2) // colour type: RGB
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);

  final png = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(_chunk('IHDR', ihdr.buffer.asUint8List()))
    ..add(_chunk('IDAT', ZLibCodec().encode(raw.takeBytes())))
    ..add(_chunk('IEND', const []));
  return png.takeBytes();
}

List<int> _chunk(String type, List<int> data) {
  final typeBytes = type.codeUnits;
  final out = ByteData(8 + data.length + 4);
  out.setUint32(0, data.length);
  final bytes = out.buffer.asUint8List();
  bytes.setRange(4, 8, typeBytes);
  bytes.setRange(8, 8 + data.length, data);
  out.setUint32(8 + data.length, _crc32([...typeBytes, ...data]));
  return bytes;
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc = _crcTable[(crc ^ b) & 0xFF] ^ (crc >> 8);
  }
  return crc ^ 0xFFFFFFFF;
}
