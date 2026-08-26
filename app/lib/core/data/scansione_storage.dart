import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _cartellaScansioni = 'scansioni';
const _cartellaGrezziScanner = 'scansioni_grezze';

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

  /// Copia subito i file appena restituiti da uno scanner di terze parti
  /// (`cunning_document_scanner`, #89) nella directory
  /// `<ApplicationSupportDirectory>/scansioni_grezze/` — vivono in una cache
  /// non garantita del plugin, soggetta a rimozione di sistema, quindi vanno
  /// spostati in storage permanente prima di ogni elaborazione successiva
  /// (stesso pattern di [salva] per l'output di `image_cropper`, #17).
  /// Ritorna i nuovi percorsi permanenti nello stesso ordine; il chiamante
  /// resta responsabile di ripulirli una volta consumati, come già oggi per
  /// un grezzo da fotocamera/Galleria (`RevisionePage`, #24).
  Future<List<String>> salvaGrezzi(List<String> percorsiOriginali) async {
    final base = await _baseDirectory();
    final dir = Directory(p.join(base.path, _cartellaGrezziScanner));
    await dir.create(recursive: true);

    final risultato = <String>[];
    for (var i = 0; i < percorsiOriginali.length; i++) {
      final destPath = p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}_$i.jpg');
      final salvato = await File(percorsiOriginali[i]).copy(destPath);
      risultato.add(salvato.path);
    }
    return risultato;
  }

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

  /// Elimina il file salvato di una Scansione rimossa prima di essere
  /// processata (swipe-to-delete nel riepilogo) — best-effort, sullo stesso
  /// modello della ripulizia dei grezzi in [salva]: un file già assente non
  /// deve far fallire la rimozione.
  Future<void> elimina(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // Best-effort: il file già assente non invalida la rimozione della Scansione.
    }
  }
}
