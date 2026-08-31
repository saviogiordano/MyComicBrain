import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/esportazione_schema.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Il servizio di export della collezione (§16, deciso su #139/#140),
/// costruito sul `ComicsRepository` condiviso — stesso pattern degli altri
/// provider di feature (`indiceCollezioneProvider`,
/// `features/collezione/application/collezione_providers.dart`).
final esportazioneServiceProvider = Provider<EsportazioneService>(
  (ref) => EsportazioneService(ref.watch(comicsRepositoryProvider)),
);

/// Formato dell'export della collezione (§16, deciso su
/// [#139](https://github.com/saviogiordano/MyComicBrain/issues/139)/
/// [#143](https://github.com/saviogiordano/MyComicBrain/issues/143)):
/// CSV/JSON/Excel, stesso schema/granularità; PDF/catalogo in ticket
/// separato.
enum FormatoEsportazione { csv, json, excel }

extension _EstensioneFormato on FormatoEsportazione {
  String get estensione => switch (this) {
    FormatoEsportazione.csv => 'csv',
    FormatoEsportazione.json => 'json',
    FormatoEsportazione.excel => 'xlsx',
  };
}

/// Esporta l'intera collezione (§16, sezione "Importa/Esporta dati" di
/// Impostazioni, deciso su
/// [#139](https://github.com/saviogiordano/MyComicBrain/issues/139)/
/// [#140](https://github.com/saviogiordano/MyComicBrain/issues/140)): legge
/// tutte le Copie da [ComicsRepository.tutteLeCopiePerEsportazione], genera
/// il file nel formato scelto e lo consegna tramite lo share sheet di
/// sistema (`share_plus`) — nessun salvataggio permanente nella directory
/// dei documenti dell'app, il file temporaneo vive solo per la durata della
/// condivisione (rimane nella directory temporanea del sistema operativo,
/// soggetta a pulizia automatica).
class EsportazioneService {
  EsportazioneService(this._repository);

  final ComicsRepository _repository;

  Future<void> esporta(FormatoEsportazione formato) async {
    final righe = await _repository.tutteLeCopiePerEsportazione();

    final directory = await getTemporaryDirectory();
    final nomeFile =
        'mycomicbrain_collezione_'
        '${DateTime.now().millisecondsSinceEpoch}.${formato.estensione}';
    final percorso = p.join(directory.path, nomeFile);
    final File file;
    switch (formato) {
      case FormatoEsportazione.csv:
        file = await File(
          percorso,
        ).writeAsString(generaCsvEsportazione(righe));
      case FormatoEsportazione.json:
        file = await File(
          percorso,
        ).writeAsString(generaJsonEsportazione(righe));
      case FormatoEsportazione.excel:
        file = await File(
          percorso,
        ).writeAsBytes(generaExcelEsportazione(righe));
    }

    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], fileNameOverrides: [nomeFile]),
    );
  }
}
