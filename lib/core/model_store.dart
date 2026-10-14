/// Optional Real-ESRGAN weights, downloaded on demand into the user's own
/// models folder.
///
/// The design model (UltraMix Balanced) is licensed CC BY-NC-SA 4.0. That is
/// fine for a person upscaling their own pictures, but it cannot be folded
/// into an MIT installer that anyone may use commercially. So it stays out of
/// the download, and the app fetches it only when someone picks it — with the
/// author and the non-commercial terms shown right there.
///
/// Every file is pinned to one commit and one sha256. A moved or altered file
/// fails verification and is discarded; it is never handed to the upscaler.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../l10n/strings.dart';
import '../models/process_options.dart';

class ModelFile {
  const ModelFile({
    required this.name,
    required this.url,
    required this.sha256,
    required this.sizeBytes,
  });

  final String name;
  final String url;
  final String sha256;
  final int sizeBytes;
}

class DownloadableModel {
  const DownloadableModel({
    required this.model,
    required this.author,
    required this.license,
    required this.licenseUrl,
    required this.files,
  });

  final UpscaleModel model;
  final String author;
  final String license;
  final String licenseUrl;
  final List<ModelFile> files;

  int get sizeBytes => files.fold(0, (sum, f) => sum + f.sizeBytes);
}

/// The Upscayl commit the NCNN conversions are taken from. Pinned so the
/// hashes below stay valid; `main` would drift.
const _kUpscaylCommit = 'a00d55fee90e0f9435d5eaa86e76700df8199af8';

ModelFile _upscayl(String name, String sha256, int size) => ModelFile(
      name: name,
      url: 'https://raw.githubusercontent.com/upscayl/upscayl/'
          '$_kUpscaylCommit/resources/models/$name',
      sha256: sha256,
      sizeBytes: size,
    );

const _ccByNcSa = 'CC BY-NC-SA 4.0';
const _ccByNcSaUrl = 'https://creativecommons.org/licenses/by-nc-sa/4.0/';

final List<DownloadableModel> kDownloadableModels = [
  DownloadableModel(
    model: UpscaleModel.ultramix,
    author: 'Kim2091',
    license: _ccByNcSa,
    licenseUrl: _ccByNcSaUrl,
    files: [
      _upscayl(
        'ultramix-balanced-4x.param',
        '859ecba5b3592ecf3e76c93bed65e9f627b5236dd696aae5a84ecf8c93ab65ce',
        140295,
      ),
      _upscayl(
        'ultramix-balanced-4x.bin',
        '171cae5968485d366b4fb575d232f98d117d94b766b15f22849cfccde40d2050',
        33424520,
      ),
    ],
  ),
];

/// Downloadable weights dropped from the menu in 2.2.0, by file stem.
const kRetiredDownloads = ['ultrasharp-4x', 'remacri-4x'];

DownloadableModel? downloadableFor(UpscaleModel model) {
  for (final entry in kDownloadableModels) {
    if (entry.model == model) return entry;
  }
  return null;
}

class ModelDownloadException implements Exception {
  const ModelDownloadException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ModelStore {
  ModelStore(this.dir);

  /// Writable per-user folder the weights land in. Never inside the app
  /// bundle: writing there would break the macOS code signature.
  final String dir;

  /// Deletes the weights of downloadable models the menu dropped in 2.2.0,
  /// which nothing can select or remove any more (~33 MB each). Returns how
  /// many files went.
  int removeRetired() {
    var removed = 0;
    for (final stem in kRetiredDownloads) {
      for (final ext in ['param', 'bin']) {
        final file = File(p.join(dir, '$stem.$ext'));
        try {
          if (file.existsSync()) {
            file.deleteSync();
            removed++;
          }
        } on FileSystemException {
          // Locked or read-only: harmless, it is only disk space.
        }
      }
    }
    return removed;
  }

  /// Downloads every file of [model] into [dir], verifying each against its
  /// pinned hash.
  ///
  /// The files are staged and only moved into place once all of them have
  /// verified, so an interrupted download can never leave a `.param` without
  /// its `.bin` — a pair the installed-check would accept and the upscaler
  /// would then fail on.
  Future<void> download(
    DownloadableModel model, {
    void Function(double fraction)? onProgress,
    HttpClient Function()? clientFactory,
  }) async {
    await Directory(dir).create(recursive: true);
    final staging = await Directory(dir).createTemp('.download_');
    final client = (clientFactory ?? HttpClient.new)()
      ..connectionTimeout = const Duration(seconds: 20);
    final total = model.sizeBytes;
    var received = 0;

    try {
      for (final file in model.files) {
        final target = File(p.join(staging.path, file.name));
        final digest = await _fetch(client, file.url, target, (chunk) {
          received += chunk;
          if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
        });
        if (digest != file.sha256) {
          throw ModelDownloadException(S.current.downloadHashMismatch);
        }
      }
      for (final file in model.files) {
        await File(p.join(staging.path, file.name))
            .rename(p.join(dir, file.name));
      }
      onProgress?.call(1.0);
    } on ModelDownloadException {
      rethrow;
    } on Object catch (e) {
      throw ModelDownloadException('$e');
    } finally {
      client.close(force: true);
      try {
        await staging.delete(recursive: true);
      } on FileSystemException {
        // A stray staging folder costs nothing; it is hidden and empty.
      }
    }
  }

  /// Streams [url] into [target], returning the hex sha256 of what arrived.
  static Future<String> _fetch(
    HttpClient client,
    String url,
    File target,
    void Function(int bytes) onChunk,
  ) async {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw ModelDownloadException(
        S.current.downloadHttpError(response.statusCode),
      );
    }

    Digest? digest;
    final hasher = sha256.startChunkedConversion(
      ChunkedConversionSink<Digest>.withCallback((d) => digest = d.single),
    );
    final sink = target.openWrite();
    try {
      // An idle timeout rather than a total one: 33 MB on a slow line is
      // legitimately slow, a connection that has stopped sending is not.
      await for (final chunk
          in response.timeout(const Duration(seconds: 60))) {
        sink.add(chunk);
        hasher.add(chunk);
        onChunk(chunk.length);
      }
    } finally {
      await sink.close();
    }
    hasher.close();
    return digest.toString();
  }
}
