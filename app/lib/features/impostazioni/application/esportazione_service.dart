import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
enum FormatoEsportazione {
  csv('CSV'),
  json('JSON'),
  excel('Excel'),
  pdf('PDF');

  const FormatoEsportazione(this.label);

  /// Nome mostrato all'utente (es. nella dialog di attesa dell'export).
  final String label;
}

/// Un export già generato in memoria, pronto per [EsportazioneService.condividi]:
/// separato dalla consegna così la UI può chiudere la dialog di attesa
/// prima che si apra lo share sheet di sistema.
class EsportazionePronta {
  const EsportazionePronta({
    required this.formato,
    required this.bytes,
    required this.nomeFile,
  });

  final FormatoEsportazione formato;
  final Uint8List bytes;
  final String nomeFile;
}

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
/// condividono lo stesso schema e vengono consegnati come zip (file dati +
/// cover in `copertine/`) via lo share sheet di sistema (`share_plus`); il
/// PDF/catalogo stampabile (layout deciso su
/// [#141](https://github.com/saviogiordano/MyComicBrain/issues/141)) ha
/// riga/query proprie (con cover) e passa dallo share sheet via `printing`
/// invece che da un file temporaneo scritto a mano — stesso risultato per
/// l'utente (l'OS mostra lo stesso foglio di condivisione), percorso di
/// consegna diverso perché è il pacchetto pensato apposta per condividere
/// un PDF generato in memoria.
class EsportazioneService {
  EsportazioneService(this._repository);

  final ComicsRepository _repository;

  /// Genera e consegna in un colpo solo — equivalente a [prepara] seguito da
  /// [condividi].
  Future<void> esporta(FormatoEsportazione formato) async {
    await condividi(await prepara(formato));
  }

  /// Genera l'export in memoria: lo zip (file dati + cover) per
  /// CSV/JSON/Excel, il PDF/catalogo stampabile per [FormatoEsportazione.pdf].
  Future<EsportazionePronta> prepara(FormatoEsportazione formato) async {
    final nomeBase = _nomeBase();
    if (formato == FormatoEsportazione.pdf) {
      return EsportazionePronta(
        formato: formato,
        bytes: await _generaPdf(),
        nomeFile: '$nomeBase.${formato.estensione}',
      );
    }
    return EsportazionePronta(
      formato: formato,
      bytes: await _generaZip(formato, nomeBase),
      nomeFile: '$nomeBase.zip',
    );
  }

  /// Consegna un export già generato tramite lo share sheet di sistema: il
  /// PDF via `printing`, lo zip via un file temporaneo e `share_plus`.
  Future<void> condividi(EsportazionePronta esportazione) async {
    if (esportazione.formato == FormatoEsportazione.pdf) {
      await Printing.sharePdf(
        bytes: esportazione.bytes,
        filename: esportazione.nomeFile,
      );
      return;
    }

    final directory = await getTemporaryDirectory();
    final file = await File(
      p.join(directory.path, esportazione.nomeFile),
    ).writeAsBytes(esportazione.bytes);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        fileNameOverrides: [esportazione.nomeFile],
      ),
    );
  }

  /// CSV/JSON/Excel: uno zip con il file dati alla radice e le cover sotto
  /// `copertine/`, colonna "Copertina" col percorso del file nello zip.
  Future<Uint8List> _generaZip(
    FormatoEsportazione formato,
    String nomeBase,
  ) async {
    final righe = await _repository.tutteLeCopiePerEsportazione();
    final copertine = await raccogliCopertineEsportazione(righe);
    final fileCopertine = copertine.fileCopertine;

    final List<int> bytesDati = switch (formato) {
      FormatoEsportazione.csv => utf8.encode(
        generaCsvEsportazione(righe, fileCopertine: fileCopertine),
      ),
      FormatoEsportazione.json => utf8.encode(
        generaJsonEsportazione(righe, fileCopertine: fileCopertine),
      ),
      FormatoEsportazione.excel => generaExcelEsportazione(
        righe,
        fileCopertine: fileCopertine,
      ),
      FormatoEsportazione.pdf => throw UnsupportedError(
        'Il PDF passa da _generaPdf',
      ),
    };

    return generaZipEsportazione(
      nomeFileDati: '$nomeBase.${formato.estensione}',
      bytesDati: bytesDati,
      copertine: copertine.bytesPerFile,
    );
  }

  Future<Uint8List> _generaPdf() async {
    final righe = await _repository.tutteLeCopiePerCatalogoStampabile();
    return generaPdfCatalogoStampabile(
      righe,
      fontRegular: await _caricaFont(_fontTitoli),
      fontBold: await _caricaFont(_fontTitoli),
      fontMono: await _caricaFont(_fontMono),
    );
  }

  Future<pw.Font> _caricaFont(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return pw.Font.ttf(data);
  }

  String _nomeBase() =>
      'mycomicbrain_collezione_${DateTime.now().millisecondsSinceEpoch}';
}
