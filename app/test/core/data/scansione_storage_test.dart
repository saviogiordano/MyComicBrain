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
}
