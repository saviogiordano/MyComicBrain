import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _cartellaScansioni = 'scansioni';

/// Copia il file confermato (già ritagliato/ruotato) di una Scansione nella
/// directory `<ApplicationSupportDirectory>/scansioni/` (creata se assente),
/// con nome `<millisecondsSinceEpoch>.jpg`, e ripulisce best-effort il file
/// temporaneo grezzo — un fallimento della ripulizia non deve far fallire il
/// salvataggio.
///
/// La directory base è iniettabile per i test (vedi
/// `test/core/data/scansione_storage_test.dart`); di default è
/// [getApplicationSupportDirectory].
class ScansioneStorage {
  ScansioneStorage({Future<Directory> Function()? baseDirectory})
    : _baseDirectory = baseDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _baseDirectory;

  Future<File> salva(File fileConfermato) async {
    final base = await _baseDirectory();
    final dir = Directory(p.join(base.path, _cartellaScansioni));
    await dir.create(recursive: true);

    final destPath = p.join(
      dir.path,
      '${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    final salvato = await fileConfermato.copy(destPath);

    try {
      await fileConfermato.delete();
    } on FileSystemException {
      // Best-effort: il temporaneo grezzo non ripulito non invalida il salvataggio.
    }

    return salvato;
  }
}
