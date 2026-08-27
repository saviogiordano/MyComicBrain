import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/formato.dart';
import 'package:mycomicbrain/core/domain/genere.dart';

/// Un'Edizione posseduta con tutti i valori dei 12 assi di filtro/
/// ordinamento della Collezione (§9) già risolti — proiezione di sola
/// lettura per lo schermo Collezione, distinta da `EdizioneDettaglio` (che
/// serve la Scheda) e da `EdizioneCatalogo` (che serve il matching).
class EdizioneCollezione {
  const EdizioneCollezione({
    required this.edizioneId,
    required this.titolo,
    required this.serieId,
    required this.serieName,
    required this.publisher,
    required this.issueNumber,
    required this.issueNumberLabel,
    required this.coverImage,
    required this.year,
    required this.format,
    required this.language,
    required this.autori,
    required this.personaggi,
    required this.generi,
    required this.tag,
    required this.copiePossedute,
  });

  final int edizioneId;
  final String titolo;
  final int? serieId;
  final String? serieName;
  final String? publisher;
  final int? issueNumber;
  final String? issueNumberLabel;
  final String? coverImage;
  final int? year;
  final FormatoEdizione? format;
  final String? language;
  final List<String> autori;
  final List<String> personaggi;
  final List<GenereEdizione> generi;
  final List<String> tag;

  /// Le sole copie possedute/prestate di questa Edizione (stesso filtro
  /// "posseduto" del resto del catalogo) — [numeroCopie] è la base del
  /// badge duplicato (§9, deciso su #93); i loro campi alimentano gli assi
  /// per-Copia (stato di lettura, condizione, posizione) secondo la regola
  /// "almeno una copia" (deciso su #80).
  final List<CopiaAsseCollezione> copiePossedute;

  int get numeroCopie => copiePossedute.length;

  /// Etichetta mostrata sulla card e nel sottotitolo, es. "#4" — stessa
  /// convenzione di `ComicRecente.numeroVisualizzato`.
  String get numeroVisualizzato {
    final label = issueNumberLabel ?? issueNumber?.toString();
    return label == null ? '' : '#$label';
  }
}

/// I soli campi di una Copia posseduta/prestata rilevanti per gli assi
/// per-Copia della Collezione (§9) — proiezione minima, non l'intera Copia.
class CopiaAsseCollezione {
  const CopiaAsseCollezione({
    required this.readingStatus,
    required this.condition,
    required this.location,
    required this.createdAt,
  });

  final StatoLettura? readingStatus;
  final CondizioneCopia? condition;
  final String? location;

  /// Non è uno dei 12 assi di filtro/ordinamento: pilota il solo
  /// pre-filtro d'ingresso dalla Dashboard (§9, deciso su #91) — "aggiunti
  /// nel mese corrente", stesso significato di `Copia.createdAt` per il KPI
  /// omonimo (`watchDashboardKpis`).
  final DateTime createdAt;
}
