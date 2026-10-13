/// Downloads land only when every file verifies, and never half-installed.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labscale/core/binaries.dart';
import 'package:labscale/core/model_store.dart';
import 'package:labscale/models/process_options.dart';
import 'package:path/path.dart' as p;

void main() {
  late HttpServer server;
  late Directory dir;
  final payloads = <String, List<int>>{
    '/ultrasharp-4x.param': utf8.encode('param-bytes'),
    '/ultrasharp-4x.bin': List<int>.generate(4096, (i) => i % 251),
  };

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('labscale_models_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      final body = payloads[request.uri.path];
      if (body == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.add(body);
      }
      request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    dir.deleteSync(recursive: true);
    Binaries.userModelsDir = null;
  });

  DownloadableModel model({String? binHash}) {
    String url(String name) => 'http://127.0.0.1:${server.port}/$name';
    String hash(String path) => sha256.convert(payloads[path]!).toString();
    return DownloadableModel(
      model: UpscaleModel.ultrasharp,
      author: 'test',
      license: 'test',
      licenseUrl: 'https://example.com',
      files: [
        ModelFile(
          name: 'ultrasharp-4x.param',
          url: url('ultrasharp-4x.param'),
          sha256: hash('/ultrasharp-4x.param'),
          sizeBytes: payloads['/ultrasharp-4x.param']!.length,
        ),
        ModelFile(
          name: 'ultrasharp-4x.bin',
          url: url('ultrasharp-4x.bin'),
          sha256: binHash ?? hash('/ultrasharp-4x.bin'),
          sizeBytes: payloads['/ultrasharp-4x.bin']!.length,
        ),
      ],
    );
  }

  test('a verified download installs both files and reports progress',
      () async {
    final progress = <double>[];
    await ModelStore(dir.path).download(model(), onProgress: progress.add);

    expect(File(p.join(dir.path, 'ultrasharp-4x.param')).existsSync(), isTrue);
    expect(File(p.join(dir.path, 'ultrasharp-4x.bin')).existsSync(), isTrue);
    expect(progress.last, 1.0);

    // And the upscaler is pointed at this folder for that model.
    Binaries.userModelsDir = dir.path;
    expect(Binaries.esrganModelsDirFor('ultrasharp-4x'), dir.path);
  });

  test('a checksum mismatch installs nothing — not even the file that matched',
      () async {
    await expectLater(
      ModelStore(dir.path).download(model(binHash: '0' * 64)),
      throwsA(isA<ModelDownloadException>()),
    );
    // The .param verified, but alone it would make the model look installed.
    expect(File(p.join(dir.path, 'ultrasharp-4x.param')).existsSync(), isFalse);
    expect(File(p.join(dir.path, 'ultrasharp-4x.bin')).existsSync(), isFalse);
    expect(dir.listSync(), isEmpty, reason: 'folder staging tertinggal');
  });

  test('a server error is reported, not swallowed', () async {
    final missing = model();
    final saved = payloads.remove('/ultrasharp-4x.bin')!;
    addTearDown(() => payloads['/ultrasharp-4x.bin'] = saved);
    await expectLater(
      ModelStore(dir.path).download(missing),
      throwsA(isA<ModelDownloadException>()
          .having((e) => e.message, 'message', contains('404'))),
    );
  });
}
