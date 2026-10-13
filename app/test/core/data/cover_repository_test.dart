import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/copertina_downloader.dart';
import 'package:path/path.dart' as p;

import 'contratto/adapter_sotto_contratto.dart';

void main() => contrattoCover(creaAdapterDriftInMemoria);

/// Area Cover della suite di contratto di `ComicsRepository` (ADR-0007):
/// il valore restituito da `salvaCoverLocale` è quello che va in DB, e
/// `risolviCoverImage` lo riporta a un file locale per `Image.file`.
void contrattoCover(CreaAdapter crea) {
  late AdapterSottoContratto adapter;
  late ComicsRepository repo;
  late Directory temp;

  setUp(() async {
    adapter = await crea();
    temp = await Directory.systemTemp.createTemp('contratto_cover_');
    repo = adapter.repoCon(
      copertinaDownloader: CopertinaDownloader(
        baseDirectory: () async => temp,
      ),
    );
  });

  tearDown(() async {
    await adapter.chiudi();
    await temp.delete(recursive: true);
  });

  Future<File> immagine(String nome, List<int> bytes) async {
    final file = File(p.join(temp.path, 'galleria', nome));
    await file.parent.create(recursive: true);
    return file.writeAsBytes(bytes);
  }

  test('risolviCoverImage di null è null', () async {
    expect(await repo.risolviCoverImage(null), isNull);
  });

  test('risolviCoverImage lascia invariato un URL remoto', () async {
    const url = 'https://comicvine.gamespot.com/a/uploads/cover.jpg';

    expect(await repo.risolviCoverImage(url), url);
  });

  test('una cover salvata si risolve in un file locale con gli stessi '
      'byte', () async {
    final bytes = [0xFF, 0xD8, 0xFF, 1, 2, 3];
    final salvata = await repo.salvaCoverLocale(
      await immagine('cover.jpg', bytes),
    );

    final risolta = await repo.risolviCoverImage(salvata);

    expect(risolta, isNotNull);
    expect(await File(risolta!).readAsBytes(), bytes);
  });

  test('il valore salvato non è un percorso assoluto del device', () async {
    final salvata = await repo.salvaCoverLocale(
      await immagine('cover.png', [1, 2, 3]),
    );

    expect(p.isAbsolute(salvata), isFalse);
  });
}
