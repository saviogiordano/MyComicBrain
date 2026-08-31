import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/creator.dart';
import 'package:mycomicbrain/core/domain/formato.dart';

/// Una riga dell'export della collezione (§16, deciso su
/// [Mappa — Importazione ed esportazione](https://github.com/saviogiordano/MyComicBrain/issues/139)):
/// una Copia con tutti i campi bibliografici di Edizione/Opera/Serie
/// collegati (§8.1) e i campi personali della Copia (§8.2) — niente
/// immagini. Proiezione di sola lettura condivisa da CSV/JSON (deciso su
/// [#140](https://github.com/saviogiordano/MyComicBrain/issues/140)) e
/// riusabile dai ticket successivi (Excel, import).
class RigaEsportazioneCopia {
  const RigaEsportazioneCopia({
    required this.copiaId,
    required this.edizioneId,
    required this.operaTitolo,
    required this.status,
    required this.createdAt,
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
  });

  final int copiaId;
  final int edizioneId;
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
  final List<CreatorConRuolo> autori;
  final StatoCopia status;
  final StatoLettura? readingStatus;
  final CondizioneCopia? condition;
  final double? purchasePrice;
  final DateTime? purchaseDate;
  final String? seller;
  final String? location;
  final String? notes;
  final DateTime createdAt;
}
