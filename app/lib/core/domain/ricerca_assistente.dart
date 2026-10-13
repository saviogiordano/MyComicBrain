import 'package:mycomicbrain/core/domain/edizione_collezione.dart';

/// Campo di aggregazione del tool `conteggioPer` dell'Assistente (§10,
/// schema tool-calling deciso su ADR-0002).
enum CampoConteggio { editore, anno }

/// Esito del tool `cercaEdizioni` dell'Assistente (§10, ADR-0002): tetto di
/// 30 righe restituite in `edizioni`, `totale` riporta il conteggio reale
/// (prima del troncamento) solo quando `troncato` è vero.
typedef RisultatoCercaEdizioni = ({
  List<EdizioneCollezioneIndice> edizioni,
  int totale,
  bool troncato,
});

/// Il tool `cercaEdizioni` applicato all'indice della Collezione già
/// caricato, condiviso dagli adapter di `ComicsRepository` (ADR-0007): i
/// filtri si combinano in AND; quelli testuali sono un match parziale
/// senza distinzione di maiuscole (stesso criterio di `cercaCreator`/
/// `cercaCharacter`/`cercaTag`). [serieIds] sono le Serie che corrispondono
/// al filtro per serie, già risolte dal chiamante con `cercaSerie`.
RisultatoCercaEdizioni filtraIndiceCollezione(
  List<EdizioneCollezioneIndice> indice, {
  String? titolo,
  Set<int>? serieIds,
  String? autore,
  String? editore,
  String? personaggio,
  String? tag,
  int? numero,
  String? isbn,
  String? testoLibero,
}) {
  var risultati = indice;
  if (titolo != null) {
    risultati = _filtraPerTesto(risultati, titolo, (e) => [e.titolo]);
  }
  if (serieIds != null) {
    risultati = risultati.where((e) => serieIds.contains(e.serieId)).toList();
  }
  if (autore != null) {
    risultati = _filtraPerTesto(risultati, autore, (e) => e.autori);
  }
  if (editore != null) {
    risultati = _filtraPerTesto(risultati, editore, (e) => [e.publisher]);
  }
  if (personaggio != null) {
    risultati = _filtraPerTesto(risultati, personaggio, (e) => e.personaggi);
  }
  if (tag != null) {
    risultati = _filtraPerTesto(risultati, tag, (e) => e.tag);
  }
  if (numero != null) {
    risultati = risultati.where((e) => e.issueNumber == numero).toList();
  }
  if (isbn != null) {
    risultati = risultati.where((e) => e.ean == isbn).toList();
  }
  if (testoLibero != null) {
    risultati = _filtraPerTesto(
      risultati,
      testoLibero,
      (e) => [
        e.titolo,
        e.serieName,
        e.publisher,
        ...e.autori,
        ...e.personaggi,
        ...e.tag,
      ],
    );
  }

  final totale = risultati.length;
  return (
    edizioni: risultati.take(30).toList(),
    totale: totale,
    troncato: totale > 30,
  );
}

List<EdizioneCollezioneIndice> _filtraPerTesto(
  List<EdizioneCollezioneIndice> righe,
  String query,
  Iterable<String?> Function(EdizioneCollezioneIndice) campi,
) {
  final q = query.toLowerCase();
  return righe
      .where((e) => campi(e).any((v) => v?.toLowerCase().contains(q) ?? false))
      .toList();
}

/// Una riga del tool `trovaDuplicati` dell'Assistente (§10, ADR-0002): la
/// stessa Edizione posseduta in più di una Copia, coi soli campi utili a
/// identificarla in una risposta conversazionale.
typedef EdizioneDuplicata = ({
  int edizioneId,
  String titolo,
  String? serieName,
  String? issueNumberLabel,
  String? publisher,
  int copiePossedute,
});
