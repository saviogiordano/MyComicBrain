import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/creator.dart';

/// Una Copia con tutti i campi §8.2, per il rendering della Scheda (§8,
/// deciso su #69) — proiezione di sola lettura di una riga `Copie`.
class CopiaDettaglio {
  const CopiaDettaglio({
    required this.id,
    required this.status,
    this.readingStatus,
    this.condition,
    this.purchasePrice,
    this.purchaseDate,
    this.seller,
    this.location,
    this.notes,
  });

  final int id;
  final StatoCopia status;
  final StatoLettura? readingStatus;
  final CondizioneCopia? condition;
  final double? purchasePrice;
  final DateTime? purchaseDate;
  final String? seller;
  final String? location;
  final String? notes;

  /// "Dati personali già inseriti" su questa Copia (§8.4, deciso su #68):
  /// qualsiasi campo §8.2 non-default — non include `status`/`readingStatus`
  /// (§8.3, sezione diversa). Guida la severità delle conferme di
  /// cancellazione.
  bool get haDatiPersonali =>
      condition != null ||
      purchasePrice != null ||
      purchaseDate != null ||
      seller != null ||
      location != null ||
      notes != null;
}

/// Un'Edizione con le sue Copie e i suoi Autori, per la Scheda del fumetto
/// (§8, deciso su #63/#65/#67/#68/#69) — proiezione di sola lettura che
/// risolve già `Opere.title` e `Serie.name` via join, distinta dai tipi di
/// scrittura di `ComicsRepository`.
class EdizioneDettaglio {
  const EdizioneDettaglio({
    required this.edizioneId,
    required this.operaId,
    required this.titolo,
    this.serieId,
    this.serieName,
    this.publisher,
    this.issueNumber,
    this.issueNumberLabel,
    this.coverImage,
    this.releaseDate,
    this.coverPrice,
    this.pageCount,
    this.language,
    this.color,
    this.ean,
    this.volume,
    this.description,
    this.autori = const [],
    this.copie = const [],
  });

  final int edizioneId;
  final int operaId;
  final String titolo;
  final int? serieId;
  final String? serieName;
  final String? publisher;
  final int? issueNumber;
  final String? issueNumberLabel;
  final String? coverImage;
  final String? releaseDate;
  final String? coverPrice;
  final int? pageCount;
  final String? language;
  final String? color;
  final String? ean;
  final String? volume;
  final String? description;
  final List<CreatorConRuolo> autori;
  final List<CopiaDettaglio> copie;
}
