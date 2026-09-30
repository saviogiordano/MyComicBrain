import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive_pkg;
import 'package:csv/csv.dart' as csv_pkg;
import 'package:excel/excel.dart' as excel_pkg;
import 'package:mycomicbrain/core/data/copertina_bytes.dart' as copertina_bytes;
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/creator.dart';
import 'package:mycomicbrain/core/domain/esportazione.dart';
import 'package:mycomicbrain/core/domain/formato.dart';
import 'package:mycomicbrain/core/domain/voce_stato.dart';

/// Versione dello schema di export/import (§16, deciso su
/// [Mappa — Importazione ed esportazione](https://github.com/saviogiordano/MyComicBrain/issues/139)):
/// da incrementare solo quando cambia la forma delle colonne — incorporata
/// nei metadata del JSON per un roundtrip d'import sicuro (ticket import,
/// fuori scope qui). v2: aggiunta la colonna "Copertina" (nome del file
/// della cover dentro lo zip).
const schemaEsportazioneVersione = 2;

/// Una colonna dello schema di export condiviso fra CSV e JSON (§16, deciso
/// su [#139](https://github.com/saviogiordano/MyComicBrain/issues/139)/
/// [#140](https://github.com/saviogiordano/MyComicBrain/issues/140)):
/// etichetta italiana leggibile (coerente col glossario di `CONTEXT.md`) più
/// il valore testuale per una [RigaEsportazioneCopia] — stesso schema
/// riusabile da Excel/import nei ticket successivi.
class ColonnaEsportazione {
  const ColonnaEsportazione(this.etichetta, this.valore);

  final String etichetta;
  final String Function(RigaEsportazioneCopia riga) valore;
}

String _testo(String? valore) => valore ?? '';

String _intero(int? valore) => valore?.toString() ?? '';

String _data(DateTime? valore) =>
    valore == null ? '' : valore.toIso8601String().split('T').first;

/// "Nome (ruolo)" per autore, più autori separati da `; ` — stesso
/// separatore per liste in tutte le colonne multi-valore di questo schema.
String _autori(List<CreatorConRuolo> autori) =>
    autori.map((a) => '${a.name} (${a.ruolo.name})').join('; ');

/// Le 24 colonne dell'export, nell'ordine in cui compaiono in CSV/JSON —
/// **Stato** collassa `status`+`readingStatus` sulla stessa voce a 7 valori
/// mostrata in UI (§8.3, `voceStatoDi`), non i due campi DB separati: più
/// leggibile per l'utente e roundtrip diretto con `statoPerVoce` per un
/// futuro import. La colonna "Copertina" non è qui ma in coda, da
/// [_colonneConCopertina]: il suo valore dipende dalle cover effettivamente
/// incluse nello zip, non solo dalla riga.
final colonneEsportazione = <ColonnaEsportazione>[
  ColonnaEsportazione('Opera', (r) => r.operaTitolo),
  ColonnaEsportazione('Serie', (r) => _testo(r.serieName)),
  ColonnaEsportazione('Editore', (r) => _testo(r.publisher)),
  ColonnaEsportazione(
    'Numero',
    (r) => _testo(r.issueNumberLabel ?? r.issueNumber?.toString()),
  ),
  ColonnaEsportazione('Volume', (r) => _testo(r.volume)),
  ColonnaEsportazione('Data di pubblicazione', (r) => _testo(r.releaseDate)),
  ColonnaEsportazione('Anno', (r) => _intero(r.year)),
  ColonnaEsportazione('Prezzo di copertina', (r) => _testo(r.coverPrice)),
  ColonnaEsportazione('Pagine', (r) => _intero(r.pageCount)),
  ColonnaEsportazione('Lingua', (r) => _testo(r.language)),
  ColonnaEsportazione('Colore', (r) => _testo(r.color)),
  ColonnaEsportazione('EAN/ISBN', (r) => _testo(r.ean)),
  ColonnaEsportazione(
    'Formato',
    (r) => r.format == null ? '' : r.format!.label,
  ),
  ColonnaEsportazione('Tipo di stampa', (r) => _testo(r.printingType)),
  ColonnaEsportazione('Classificazione', (r) => _testo(r.classificazione)),
  ColonnaEsportazione('Descrizione', (r) => _testo(r.description)),
  ColonnaEsportazione('Autori', (r) => _autori(r.autori)),
  ColonnaEsportazione(
    'Stato',
    (r) => voceStatoDi(r.status, r.readingStatus).label,
  ),
  ColonnaEsportazione(
    'Condizione',
    (r) => r.condition == null ? '' : r.condition!.label,
  ),
  ColonnaEsportazione(
    'Prezzo di acquisto',
    (r) => r.purchasePrice == null ? '' : r.purchasePrice.toString(),
  ),
  ColonnaEsportazione('Data di acquisto', (r) => _data(r.purchaseDate)),
  ColonnaEsportazione('Venditore', (r) => _testo(r.seller)),
  ColonnaEsportazione('Posizione', (r) => _testo(r.location)),
  ColonnaEsportazione('Note', (r) => _testo(r.notes)),
  ColonnaEsportazione('Aggiunta il', (r) => _data(r.createdAt)),
];

/// Etichetta della colonna con il nome del file della cover nello zip.
const etichettaColonnaCopertina = 'Copertina';

/// [colonneEsportazione] più "Copertina" in coda: il percorso della cover
/// dentro lo zip (es. `copertine/edizione_10.jpg`), vuoto se l'Edizione non
/// ha cover o se non è stato possibile leggerla. [fileCopertine] è quello
/// di [CopertineEsportazione.fileCopertine].
List<ColonnaEsportazione> _colonneConCopertina(
  Map<int, String> fileCopertine,
) => [
  ...colonneEsportazione,
  ColonnaEsportazione(
    etichettaColonnaCopertina,
    (r) => fileCopertine[r.edizioneId] ?? '',
  ),
];

/// Genera il CSV dell'export (§16, deciso su #140): intestazione con le
/// etichette di [colonneEsportazione], una riga per [RigaEsportazioneCopia].
String generaCsvEsportazione(
  List<RigaEsportazioneCopia> righe, {
  Map<int, String> fileCopertine = const {},
}) {
  final colonne = _colonneConCopertina(fileCopertine);
  final tabella = [
    [for (final colonna in colonne) colonna.etichetta],
    for (final riga in righe)
      [for (final colonna in colonne) colonna.valore(riga)],
  ];
  return csv_pkg.csv.encode(tabella);
}

/// Genera il JSON dell'export (§16, deciso su #139/#140): un oggetto con
/// `metadata` (versione schema, data export, conteggio righe) che avvolge
/// l'array `righe` — stesse etichette di [colonneEsportazione] come chiavi,
/// coerenti col CSV. Indentato per leggibilità: file destinato alla
/// condivisione/ispezione manuale, non a un canale ad alto volume.
String generaJsonEsportazione(
  List<RigaEsportazioneCopia> righe, {
  Map<int, String> fileCopertine = const {},
}) {
  final colonne = _colonneConCopertina(fileCopertine);
  final documento = {
    'metadata': {
      'versioneSchema': schemaEsportazioneVersione,
      'dataEsportazione': DateTime.now().toIso8601String(),
      'numeroRighe': righe.length,
    },
    'righe': [
      for (final riga in righe)
        {
          for (final colonna in colonne)
            colonna.etichetta: colonna.valore(riga),
        },
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(documento);
}

/// Genera l'export Excel (§16, deciso su
/// [#143](https://github.com/saviogiordano/MyComicBrain/issues/143)): stesso
/// schema/etichette/granularità di [generaCsvEsportazione], un foglio unico
/// con intestazione più una riga per [RigaEsportazioneCopia]. Tutte le celle
/// sono testo (coerente col CSV, niente formattazione numerica/data
/// specifica) — evita ambiguità di parsing fra locali diversi di Excel.
Uint8List generaExcelEsportazione(
  List<RigaEsportazioneCopia> righe, {
  Map<int, String> fileCopertine = const {},
}) {
  final colonne = _colonneConCopertina(fileCopertine);
  final libro = excel_pkg.Excel.createExcel();
  final nomeFoglioPredefinito = libro.getDefaultSheet()!;
  final foglio = libro['Collezione'];
  libro
    ..setDefaultSheet('Collezione')
    ..delete(nomeFoglioPredefinito);

  foglio.appendRow([
    for (final colonna in colonne) excel_pkg.TextCellValue(colonna.etichetta),
  ]);
  for (final riga in righe) {
    foglio.appendRow([
      for (final colonna in colonne)
        excel_pkg.TextCellValue(colonna.valore(riga)),
    ]);
  }

  return Uint8List.fromList(libro.encode()!);
}

/// Cartella dello zip che contiene le cover.
const cartellaCopertineZip = 'copertine';

/// Le cover raccolte per lo zip dell'export: [fileCopertine] mappa
/// `edizioneId` → percorso nello zip (per la colonna "Copertina"),
/// [bytesPerFile] percorso nello zip → byte dell'immagine. Una sola voce per
/// Edizione: più Copie della stessa Edizione condividono lo stesso file.
class CopertineEsportazione {
  const CopertineEsportazione({
    required this.fileCopertine,
    required this.bytesPerFile,
  });

  final Map<int, String> fileCopertine;
  final Map<String, Uint8List> bytesPerFile;
}

/// Legge i byte della cover di ogni Edizione presente in [righe] e assegna
/// a ciascuna un nome file stabile nello zip
/// (`copertine/edizione_<id>.<ext>`, estensione dedotta dai byte). Una
/// cover illeggibile è saltata in silenzio (colonna "Copertina" vuota), mai
/// un errore: stesso principio del PDF/catalogo stampabile.
/// [caricaBytesCopertina] è iniettabile per i test.
Future<CopertineEsportazione> raccogliCopertineEsportazione(
  List<RigaEsportazioneCopia> righe, {
  Future<Uint8List?> Function(String coverImage)? caricaBytesCopertina,
}) async {
  final carica = caricaBytesCopertina ?? copertina_bytes.caricaBytesCopertina;
  final fileCopertine = <int, String>{};
  final bytesPerFile = <String, Uint8List>{};
  final edizioniViste = <int>{};

  for (final riga in righe) {
    final coverImage = riga.coverImage;
    if (coverImage == null || !edizioniViste.add(riga.edizioneId)) continue;
    final bytes = await carica(coverImage);
    if (bytes == null || bytes.isEmpty) continue;
    final nomeFile =
        '$cartellaCopertineZip/edizione_${riga.edizioneId}'
        '.${_estensioneImmagine(bytes)}';
    fileCopertine[riga.edizioneId] = nomeFile;
    bytesPerFile[nomeFile] = bytes;
  }

  return CopertineEsportazione(
    fileCopertine: fileCopertine,
    bytesPerFile: bytesPerFile,
  );
}

/// Estensione dai magic number: il percorso/URL originale non è affidabile
/// (le cover locali compresse da `cover_compressor.dart` sono JPEG, quelle
/// remote dipendono dal provider). Default `jpg`.
String _estensioneImmagine(Uint8List bytes) {
  bool inizia(List<int> firma, [int offset = 0]) {
    if (bytes.length < offset + firma.length) return false;
    for (var i = 0; i < firma.length; i++) {
      if (bytes[offset + i] != firma[i]) return false;
    }
    return true;
  }

  if (inizia([0x89, 0x50, 0x4E, 0x47])) return 'png';
  if (inizia([0x47, 0x49, 0x46, 0x38])) return 'gif';
  if (inizia([0x52, 0x49, 0x46, 0x46]) && inizia([0x57, 0x45, 0x42, 0x50], 8)) {
    return 'webp';
  }
  return 'jpg';
}

/// Impacchetta l'export in uno zip: il file dati ([nomeFileDati], CSV/JSON/
/// Excel già generato) alla radice più le cover sotto [cartellaCopertineZip]
/// (da [CopertineEsportazione.bytesPerFile]).
Uint8List generaZipEsportazione({
  required String nomeFileDati,
  required List<int> bytesDati,
  required Map<String, Uint8List> copertine,
}) {
  final archivio = archive_pkg.Archive()
    ..addFile(
      archive_pkg.ArchiveFile(nomeFileDati, bytesDati.length, bytesDati),
    );
  for (final MapEntry(key: nomeFile, value: bytes) in copertine.entries) {
    archivio.addFile(archive_pkg.ArchiveFile(nomeFile, bytes.length, bytes));
  }
  return Uint8List.fromList(archive_pkg.ZipEncoder().encode(archivio)!);
}
