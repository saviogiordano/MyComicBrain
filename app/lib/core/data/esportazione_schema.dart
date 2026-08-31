import 'dart:convert';

import 'package:csv/csv.dart' as csv_pkg;
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/creator.dart';
import 'package:mycomicbrain/core/domain/esportazione.dart';
import 'package:mycomicbrain/core/domain/formato.dart';
import 'package:mycomicbrain/core/domain/voce_stato.dart';

/// Versione dello schema di export/import (§16, deciso su
/// [Mappa — Importazione ed esportazione](https://github.com/saviogiordano/MyComicBrain/issues/139)):
/// da incrementare solo quando cambia la forma delle colonne — incorporata
/// nei metadata del JSON per un roundtrip d'import sicuro (ticket import,
/// fuori scope qui).
const schemaEsportazioneVersione = 1;

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
/// futuro import.
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

/// Genera il CSV dell'export (§16, deciso su #140): intestazione con le
/// etichette di [colonneEsportazione], una riga per [RigaEsportazioneCopia].
String generaCsvEsportazione(List<RigaEsportazioneCopia> righe) {
  final tabella = [
    [for (final colonna in colonneEsportazione) colonna.etichetta],
    for (final riga in righe)
      [for (final colonna in colonneEsportazione) colonna.valore(riga)],
  ];
  return csv_pkg.csv.encode(tabella);
}

/// Genera il JSON dell'export (§16, deciso su #139/#140): un oggetto con
/// `metadata` (versione schema, data export, conteggio righe) che avvolge
/// l'array `righe` — stesse etichette di [colonneEsportazione] come chiavi,
/// coerenti col CSV. Indentato per leggibilità: file destinato alla
/// condivisione/ispezione manuale, non a un canale ad alto volume.
String generaJsonEsportazione(List<RigaEsportazioneCopia> righe) {
  final documento = {
    'metadata': {
      'versioneSchema': schemaEsportazioneVersione,
      'dataEsportazione': DateTime.now().toIso8601String(),
      'numeroRighe': righe.length,
    },
    'righe': [
      for (final riga in righe)
        {
          for (final colonna in colonneEsportazione)
            colonna.etichetta: colonna.valore(riga),
        },
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(documento);
}
