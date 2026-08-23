import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/copertina_downloader.dart';
import 'package:path/path.dart' as p;

/// `http.Client` finto: risponde con [statusCode]/[bytes] fissi, oppure
/// lancia se [bytes] è `null` (simula un host irraggiungibile) — stesso
/// pattern di `_FakeHttpClient` in `comic_vine_client_test.dart`.
class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient({this.statusCode = 200, this.bytes});

  final int statusCode;
  final List<int>? bytes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final corpo = bytes;
    if (corpo == null) throw const SocketException('host irraggiungibile');
    return http.StreamedResponse(Stream.value(corpo), statusCode);
  }
}

void main() {
  late Directory tempBase;

  setUp(() async {
    tempBase = await Directory.systemTemp.createTemp(
      'copertina_downloader_test_',
    );
  });

  tearDown(() => tempBase.delete(recursive: true));

  test(
    'scarica salva i byte in copertine/ con nome epoch e ritorna il percorso',
    () async {
      final downloader = CopertinaDownloader(
        httpClient: _FakeHttpClient(bytes: [1, 2, 3]),
        baseDirectory: () async => tempBase,
      );

      final percorso = await downloader.scarica(
        'https://comicvine.example/1.jpg',
      );

      expect(percorso, isNotNull);
      final file = File(percorso!);
      expect(file.existsSync(), isTrue);
      expect(p.dirname(file.path), p.join(tempBase.path, 'copertine'));
      expect(p.basename(file.path), matches(RegExp(r'^\d+\.jpg$')));
      expect(file.readAsBytesSync(), [1, 2, 3]);
    },
  );

  test('crea la directory copertine/ se assente', () async {
    final copertineDir = Directory(p.join(tempBase.path, 'copertine'));
    expect(copertineDir.existsSync(), isFalse);

    final downloader = CopertinaDownloader(
      httpClient: _FakeHttpClient(bytes: [1]),
      baseDirectory: () async => tempBase,
    );
    await downloader.scarica('https://comicvine.example/1.jpg');

    expect(copertineDir.existsSync(), isTrue);
  });

  test('risposta non-200: ritorna null, nessun file salvato', () async {
    final downloader = CopertinaDownloader(
      httpClient: _FakeHttpClient(statusCode: 404, bytes: [1]),
      baseDirectory: () async => tempBase,
    );

    final percorso = await downloader.scarica(
      'https://comicvine.example/mancante.jpg',
    );

    expect(percorso, isNull);
    expect(Directory(p.join(tempBase.path, 'copertine')).existsSync(), isFalse);
  });

  test('chiamata HTTP fallita (rete): ritorna null invece di lanciare', () async {
    final downloader = CopertinaDownloader(
      httpClient: _FakeHttpClient(),
      baseDirectory: () async => tempBase,
    );

    final percorso = await downloader.scarica(
      'https://comicvine.example/1.jpg',
    );

    expect(percorso, isNull);
  });
}
