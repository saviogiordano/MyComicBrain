import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/catalogo_stampabile_pdf.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/esportazione_schema.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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
/// [#143](https://github.com/saviogiordano/MyComicBrain/issues/143)/
/// [#145](https://github.com/saviogiordano/MyComicBrain/issues/145)):
/// CSV/JSON/Excel condividono schema/granularità; il PDF/catalogo
/// stampabile ha un layout suo (variante C, deciso su #141) e una
/// consegna diversa — vedi [EsportazioneService.esporta].
enum FormatoEsportazione { csv, json, excel, pdf }

extension _EstensioneFormato on FormatoEsportazione {
  String get estensione => switch (this) {
    FormatoEsportazione.csv => 'csv',
    FormatoEsportazione.json => 'json',
    FormatoEsportazione.excel => 'xlsx',
    FormatoEsportazione.pdf => 'pdf',
  };
}

/// I font già inclusi come asset dell'app (vedi `pubspec.yaml`), stessi
/// usati dal prototipo del layout (#141) — caricati qui per il PDF invece
/// che per il rendering nativo Flutter.
const _fontTitoli = 'assets/fonts/SpaceGrotesk-VariableFont_wght.ttf';
const _fontMono = 'assets/fonts/IBMPlexMono-Regular.ttf';

/// Esporta l'intera collezione (§16, sezione "Importa/Esporta dati" di
/// Impostazioni). CSV/JSON/Excel (deciso su
/// [#139](https://github.com/saviogiordano/MyComicBrain/issues/139)/
/// [#140](https://github.com/saviogiordano/MyComicBrain/issues/140))
/// condividono lo stesso schema e vengono consegnati via lo share sheet di
/// sistema (`share_plus`); il PDF/catalogo stampabile (layout deciso su
/// [#141](https://github.com/saviogiordano/MyComicBrain/issues/141)) ha
/// riga/query proprie (con cover) e passa dallo share sheet via `printing`
/// invece che da un file temporaneo scritto a mano — stesso risultato per
/// l'utente (l'OS mostra lo stesso foglio di condivisione), percorso di
/// consegna diverso perché è il pacchetto pensato apposta per condividere
/// un PDF generato in memoria.
class EsportazioneService {
  EsportazioneService(this._repository);

  final ComicsRepository _repository;

  Future<void> esporta(FormatoEsportazione formato) {
    if (formato == FormatoEsportazione.pdf) return _esportaPdf();
    return _esportaFile(formato);
  }

  Future<void> _esportaFile(FormatoEsportazione formato) async {
    final righe = await _repository.tutteLeCopiePerEsportazione();

    final directory = await getTemporaryDirectory();
    final nomeFile = _nomeFile(formato);
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
      case FormatoEsportazione.pdf:
        throw UnsupportedError('Il PDF passa da _esportaPdf');
    }

    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], fileNameOverrides: [nomeFile]),
    );
  }

  Future<void> _esportaPdf() async {
    final righe = await _repository.tutteLeCopiePerCatalogoStampabile();
    final bytes = await generaPdfCatalogoStampabile(
      righe,
      fontRegular: await _caricaFont(_fontTitoli),
      fontBold: await _caricaFont(_fontTitoli),
      fontMono: await _caricaFont(_fontMono),
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: _nomeFile(FormatoEsportazione.pdf),
    );
  }

  Future<pw.Font> _caricaFont(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return pw.Font.ttf(data);
  }

  String _nomeFile(FormatoEsportazione formato) =>
      'mycomicbrain_collezione_'
      '${DateTime.now().millisecondsSinceEpoch}.${formato.estensione}';
}
