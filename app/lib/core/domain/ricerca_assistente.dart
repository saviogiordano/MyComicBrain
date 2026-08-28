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
