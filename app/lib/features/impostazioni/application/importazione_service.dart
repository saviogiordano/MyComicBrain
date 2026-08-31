import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/importazione_schema.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:path/path.dart' as p;

/// Il servizio di import della collezione (§16, deciso su
/// [#139](https://github.com/saviogiordano/MyComicBrain/issues/139)/
/// [#142](https://github.com/saviogiordano/MyComicBrain/issues/142)), stesso
/// pattern del provider gemello `esportazioneServiceProvider`
/// (`esportazione_service.dart`).
final importazioneServiceProvider = Provider<ImportazioneService>(
  (ref) => ImportazioneService(ref.watch(comicsRepositoryProvider)),
);

/// Importa CSV/JSON nello stesso schema dell'export (§16, deciso su
/// #139/#142, sezione "Importa/Esporta dati" di Impostazioni): selezione
/// del file tramite `file_picker`, formato riconosciuto dall'estensione (a
/// differenza dell'export non serve chiederlo — è già scritto nel file), poi
/// scrittura additiva via [ComicsRepository.importaRighe]. Le righe scartate
/// durante l'analisi non bloccano le altre: tornano nel
/// [RisultatoAnalisiImportazione] per il riepilogo mostrato all'utente.
class ImportazioneService {
  ImportazioneService(this._repository);

  final ComicsRepository _repository;

  /// Ritorna `null` se l'utente ha annullato la selezione del file.
  Future<RisultatoAnalisiImportazione?> importa() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['csv', 'json'],
    );
    final percorso = file?.path;
    if (percorso == null) return null;

    final contenuto = await File(percorso).readAsString();
    final analisi = p.extension(percorso).toLowerCase() == '.json'
        ? analizzaJsonImportazione(contenuto)
        : analizzaCsvImportazione(contenuto);

    if (analisi.valide.isNotEmpty) {
      await _repository.importaRighe(analisi.valide);
    }

    return analisi;
  }
}
