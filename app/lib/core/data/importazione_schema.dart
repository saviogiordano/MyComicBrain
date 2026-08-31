import 'dart:convert';

import 'package:csv/csv.dart' as csv_pkg;
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/creator.dart';
import 'package:mycomicbrain/core/domain/formato.dart';
import 'package:mycomicbrain/core/domain/voce_stato.dart';

/// Un autore da collegare a un'Edizione importata — a differenza di
/// [CreatorConRuolo] non ha ancora id: il Creator viene creato in scrittura
/// (§16, deciso su
/// [#142](https://github.com/saviogiordano/MyComicBrain/issues/142), stesso
/// pattern non-dedup di [ComicsRepository.aggiungiCreator], #64).
typedef AutoreImportato = ({String name, RuoloCreator ruolo});

/// Una riga d'import pronta per la scrittura (§16, deciso su
/// [#142](https://github.com/saviogiordano/MyComicBrain/issues/142)):
/// stessi campi di [RigaEsportazioneCopia] meno gli id (non ancora
/// assegnati, la riga diventerà sempre una nuova Opera/Edizione/Copia) più
/// gli autori come coppie nome/ruolo invece di [CreatorConRuolo].
class RigaImportazioneParsata {
  const RigaImportazioneParsata({
    required this.operaTitolo,
    required this.status,
    this.serieName,
    this.publisher,
    this.issueNumber,
    this.issueNumberLabel,
    this.releaseDate,
    this.year,
    this.coverPrice,
    this.pageCount,
    this.language,
    this.color,
    this.ean,
    this.volume,
    this.description,
    this.printingType,
    this.classificazione,
    this.format,
    this.autori = const [],
    this.readingStatus,
    this.condition,
    this.purchasePrice,
    this.purchaseDate,
    this.seller,
    this.location,
    this.notes,
    this.createdAt,
  });

  final String operaTitolo;
  final String? serieName;
  final String? publisher;
  final int? issueNumber;
  final String? issueNumberLabel;
  final String? releaseDate;
  final int? year;
  final String? coverPrice;
  final int? pageCount;
  final String? language;
  final String? color;
  final String? ean;
  final String? volume;
  final String? description;
  final String? printingType;
  final String? classificazione;
  final FormatoEdizione? format;
  final List<AutoreImportato> autori;
  final StatoCopia status;
  final StatoLettura? readingStatus;
  final CondizioneCopia? condition;
  final double? purchasePrice;
  final DateTime? purchaseDate;
  final String? seller;
  final String? location;
  final String? notes;

  /// Riusato come `createdAt` di Opera/Edizione/Copia quando presente
  /// (colonna "Aggiunta il"), per un roundtrip più fedele — altrimenti le
  /// scritture (`ComicsRepository.aggiungiOpera`/...) usano `DateTime.now()`
  /// di default.
  final DateTime? createdAt;
}

/// Una riga scartata durante l'analisi (§16, deciso su #142): campo
/// obbligatorio mancante o non riconosciuto — non blocca il resto
/// dell'import, finisce nel riepilogo finale.
class RigaImportazioneScartata {
  const RigaImportazioneScartata({
    required this.numeroRiga,
    required this.motivo,
  });

  /// Numero di riga dati 1-based (intestazione esclusa, per CSV; indice+1
  /// nell'array `righe` per JSON) — mostrato nel riepilogo per farla
  /// individuare nel file originale.
  final int numeroRiga;
  final String motivo;
}

/// Esito dell'analisi di un file d'import (§16, deciso su #142): righe
/// pronte per la scrittura e righe scartate col motivo, per il riepilogo
/// finale ("N importate, M saltate").
class RisultatoAnalisiImportazione {
  const RisultatoAnalisiImportazione({
    required this.valide,
    required this.scartate,
  });

  final List<RigaImportazioneParsata> valide;
  final List<RigaImportazioneScartata> scartate;
}

/// Analizza un CSV generato da [generaCsvEsportazione] (o compatibile,
/// stesse etichette in intestazione) — §16, deciso su #142.
RisultatoAnalisiImportazione analizzaCsvImportazione(String contenuto) {
  final tabella = csv_pkg.csv.decode(contenuto);
  if (tabella.isEmpty) {
    return const RisultatoAnalisiImportazione(valide: [], scartate: []);
  }

  final intestazione = [for (final v in tabella.first) v.toString()];
  final valide = <RigaImportazioneParsata>[];
  final scartate = <RigaImportazioneScartata>[];

  var numeroRiga = 0;
  for (final riga in tabella.skip(1)) {
    numeroRiga++;
    if (riga.every((v) => v.toString().trim().isEmpty)) continue;

    final valori = <String, String>{
      for (final (i, etichetta) in intestazione.indexed)
        etichetta: i < riga.length ? riga[i].toString() : '',
    };
    _smistaRiga(
      valori,
      numeroRiga: numeroRiga,
      valide: valide,
      scartate: scartate,
    );
  }

  return RisultatoAnalisiImportazione(valide: valide, scartate: scartate);
}

/// Analizza un JSON generato da [generaJsonEsportazione] (o compatibile,
/// stesse chiavi/etichette nell'array `righe`) — §16, deciso su #142.
RisultatoAnalisiImportazione analizzaJsonImportazione(String contenuto) {
  final documento = jsonDecode(contenuto) as Map<String, dynamic>;
  final righe = documento['righe'] as List<dynamic>? ?? const [];

  final valide = <RigaImportazioneParsata>[];
  final scartate = <RigaImportazioneScartata>[];

  var numeroRiga = 0;
  for (final riga in righe) {
    numeroRiga++;
    final mappa = riga as Map<String, dynamic>;
    final valori = <String, String>{
      for (final entry in mappa.entries)
        entry.key: entry.value?.toString() ?? '',
    };
    if (valori.values.every((v) => v.trim().isEmpty)) continue;

    _smistaRiga(
      valori,
      numeroRiga: numeroRiga,
      valide: valide,
      scartate: scartate,
    );
  }

  return RisultatoAnalisiImportazione(valide: valide, scartate: scartate);
}

/// Analizza una riga già ridotta a mappa etichetta->valore (stesse
/// etichette di `colonneEsportazione`, condivise fra CSV e JSON) e la
/// smista fra [valide] e [scartate] — unica logica di validazione
/// riusata da entrambi i formati.
///
/// Unici campi obbligatori (§16, deciso su #142): "Opera" (titolo non
/// vuoto) e "Stato" (deve corrispondere a una delle 7 voci di
/// [VoceStato]) — tutti gli altri campi sono tolleranti: un valore non
/// riconosciuto (es. "Formato" con un'etichetta sconosciuta) diventa
/// `null` invece di scartare la riga.
void _smistaRiga(
  Map<String, String> valori, {
  required int numeroRiga,
  required List<RigaImportazioneParsata> valide,
  required List<RigaImportazioneScartata> scartate,
}) {
  final operaTitolo = (valori['Opera'] ?? '').trim();
  if (operaTitolo.isEmpty) {
    scartate.add(
      RigaImportazioneScartata(
        numeroRiga: numeroRiga,
        motivo: 'Campo obbligatorio mancante: Opera',
      ),
    );
    return;
  }

  final statoTesto = (valori['Stato'] ?? '').trim();
  final voce = _trovaVoceStato(statoTesto);
  if (voce == null) {
    scartate.add(
      RigaImportazioneScartata(
        numeroRiga: numeroRiga,
        motivo: 'Stato non riconosciuto: "$statoTesto"',
      ),
    );
    return;
  }
  final statoRisolto = statoPerVoce(voce);

  final issueNumberLabel = _nonVuoto(valori['Numero']);

  valide.add(
    RigaImportazioneParsata(
      operaTitolo: operaTitolo,
      serieName: _nonVuoto(valori['Serie']),
      publisher: _nonVuoto(valori['Editore']),
      issueNumberLabel: issueNumberLabel,
      issueNumber: issueNumberLabel == null
          ? null
          : int.tryParse(issueNumberLabel),
      releaseDate: _nonVuoto(valori['Data di pubblicazione']),
      year: _parseIntero(valori['Anno']),
      coverPrice: _nonVuoto(valori['Prezzo di copertina']),
      pageCount: _parseIntero(valori['Pagine']),
      language: _nonVuoto(valori['Lingua']),
      color: _nonVuoto(valori['Colore']),
      ean: _nonVuoto(valori['EAN/ISBN']),
      volume: _nonVuoto(valori['Volume']),
      description: _nonVuoto(valori['Descrizione']),
      printingType: _nonVuoto(valori['Tipo di stampa']),
      classificazione: _nonVuoto(valori['Classificazione']),
      format: _trovaEnumPerLabel(
        valori['Formato'],
        FormatoEdizione.values,
        (
          f,
        ) => f.label,
      ),
      autori: _parseAutori(valori['Autori']),
      status: statoRisolto.status,
      readingStatus: statoRisolto.readingStatus,
      condition: _trovaEnumPerLabel(
        valori['Condizione'],
        CondizioneCopia.values,
        (c) => c.label,
      ),
      purchasePrice: _parseDoppio(valori['Prezzo di acquisto']),
      purchaseDate: _parseData(valori['Data di acquisto']),
      seller: _nonVuoto(valori['Venditore']),
      location: _nonVuoto(valori['Posizione']),
      notes: _nonVuoto(valori['Note']),
      createdAt: _parseData(valori['Aggiunta il']),
    ),
  );
}

String? _nonVuoto(String? valore) {
  final t = valore?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

int? _parseIntero(String? valore) {
  final t = valore?.trim();
  if (t == null || t.isEmpty) return null;
  return int.tryParse(t);
}

double? _parseDoppio(String? valore) {
  final t = valore?.trim();
  if (t == null || t.isEmpty) return null;
  return double.tryParse(t.replaceAll(',', '.'));
}

DateTime? _parseData(String? valore) {
  final t = valore?.trim();
  if (t == null || t.isEmpty) return null;
  return DateTime.tryParse(t);
}

VoceStato? _trovaVoceStato(String valore) {
  if (valore.isEmpty) return null;
  final normalizzato = valore.toLowerCase();
  for (final voce in VoceStato.values) {
    if (voce.label.toLowerCase() == normalizzato) return voce;
  }
  return null;
}

/// Match tollerante etichetta->enum (case-insensitive) per campi opzionali
/// come Formato/Condizione — un valore non riconosciuto diventa `null`
/// invece di scartare la riga (solo Opera/Stato sono obbligatori).
T? _trovaEnumPerLabel<T>(
  String? valore,
  List<T> valori,
  String Function(T) label,
) {
  final t = valore?.trim();
  if (t == null || t.isEmpty) return null;
  final normalizzato = t.toLowerCase();
  for (final v in valori) {
    if (label(v).toLowerCase() == normalizzato) return v;
  }
  return null;
}

/// Autori dal formato "Nome (ruolo)" separati da `; ` (stesso formato di
/// [_autori] nell'export) — un ruolo non riconosciuto ricade su
/// [RuoloCreator.altro] invece di scartare la riga.
List<AutoreImportato> _parseAutori(String? valore) {
  final t = valore?.trim();
  if (t == null || t.isEmpty) return const [];

  final autori = <AutoreImportato>[];
  for (final segmento in t.split(';')) {
    final testo = segmento.trim();
    if (testo.isEmpty) continue;

    final match = RegExp(r'^(.*)\(([^)]+)\)$').firstMatch(testo);
    if (match == null) {
      autori.add((name: testo, ruolo: RuoloCreator.altro));
      continue;
    }

    final nome = match.group(1)!.trim();
    if (nome.isEmpty) continue;
    final ruoloTesto = match.group(2)!.trim().toLowerCase();
    final ruolo = RuoloCreator.values.firstWhere(
      (r) => r.name.toLowerCase() == ruoloTesto,
      orElse: () => RuoloCreator.altro,
    );
    autori.add((name: nome, ruolo: ruolo));
  }
  return autori;
}
