import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/scansione_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempBase;
  late ScansioneStorage storage;

  setUp(() async {
    tempBase = await Directory.systemTemp.createTemp('scansione_storage_test_');
    storage = ScansioneStorage(baseDirectory: () async => tempBase);
  });

  tearDown(() => tempBase.delete(recursive: true));

  test(
    'copia il file confermato in scansioni/ con nome epoch e ripulisce il grezzo',
    () async {
      final grezzo = File(p.join(tempBase.path, 'grezzo.jpg'))
        ..writeAsStringSync('finta immagine');

      final salvato = await storage.salva(grezzo);

      expect(salvato.existsSync(), isTrue);
      expect(p.dirname(salvato.path), p.join(tempBase.path, 'scansioni'));
      expect(p.basename(salvato.path), matches(RegExp(r'^\d+\.jpg$')));
      expect(salvato.readAsStringSync(), 'finta immagine');
      expect(grezzo.existsSync(), isFalse);
    },
  );

  test('crea la directory scansioni/ se assente', () async {
    final scansioniDir = Directory(p.join(tempBase.path, 'scansioni'));
    expect(scansioniDir.existsSync(), isFalse);

    final grezzo = File(p.join(tempBase.path, 'grezzo.jpg'))
      ..writeAsStringSync('x');
    await storage.salva(grezzo);

    expect(scansioniDir.existsSync(), isTrue);
  });

  group('salvaGrezzi', () {
    test('copia ogni file in scansioni_grezze/ con nomi univoci, senza toccare gli originali (#89)', () async {
      final scanA = File(p.join(tempBase.path, 'scan_a.jpg'))..writeAsStringSync('a');
      final scanB = File(p.join(tempBase.path, 'scan_b.jpg'))..writeAsStringSync('b');

      final permanenti = await storage.salvaGrezzi([scanA.path, scanB.path]);

      expect(permanenti, hasLength(2));
      expect(permanenti.toSet(), hasLength(2), reason: 'ogni copia deve avere un nome univoco');
      for (final path in permanenti) {
        expect(p.dirname(path), p.join(tempBase.path, 'scansioni_grezze'));
      }
      expect(File(permanenti[0]).readAsStringSync(), 'a');
      expect(File(permanenti[1]).readAsStringSync(), 'b');
      // Gli originali (nella cache del plugin) non sono responsabilità di
      // questo metodo: restano intatti, la ripulizia è affare del plugin
      // (`cleanCache()`).
      expect(scanA.existsSync(), isTrue);
      expect(scanB.existsSync(), isTrue);
    });

    test('crea la directory scansioni_grezze/ se assente', () async {
      final grezziDir = Directory(p.join(tempBase.path, 'scansioni_grezze'));
      expect(grezziDir.existsSync(), isFalse);

      final scan = File(p.join(tempBase.path, 'scan.jpg'))..writeAsStringSync('x');
      await storage.salvaGrezzi([scan.path]);

      expect(grezziDir.existsSync(), isTrue);
    });
  });

  group('elimina', () {
    test(
      'rimuove il file salvato (swipe-to-delete nel riepilogo, #59)',
      () async {
        final grezzo = File(p.join(tempBase.path, 'grezzo.jpg'))
          ..writeAsStringSync('finta immagine');
        final salvato = await storage.salva(grezzo);
        expect(salvato.existsSync(), isTrue);

        await storage.elimina(salvato.path);

        expect(salvato.existsSync(), isFalse);
      },
    );

    test(
      'un file già assente non fa fallire la rimozione (best-effort)',
      () async {
        final percorso = p.join(tempBase.path, 'scansioni', 'mai-esistito.jpg');

        await storage.elimina(percorso);
      },
    );
  });
}
