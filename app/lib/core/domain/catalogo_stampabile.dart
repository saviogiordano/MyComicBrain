import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/creator.dart';
import 'package:mycomicbrain/core/domain/formato.dart';

/// Una copia nel PDF/catalogo stampabile (§16, layout deciso su
/// [#141](https://github.com/saviogiordano/MyComicBrain/issues/141) —
/// variante C, schede ibride raggruppate Serie → Opera). Sottoinsieme dei
/// campi di `RigaEsportazioneCopia` scelto per un catalogo leggibile (non un
/// dump dati per data-interchange) più la cover risolta — assente
/// nell'export dati per decisione della mappa
/// [#139](https://github.com/saviogiordano/MyComicBrain/issues/139), qui
/// necessaria per le schede.
class RigaCatalogoStampabile {
  const RigaCatalogoStampabile({
    required this.copiaId,
    required this.operaTitolo,
    this.serieName,
    this.issueNumberLabel,
    this.issueNumber,
    this.publisher,
    this.year,
    this.format,
    this.autori = const [],
    this.condition,
    this.purchasePrice,
    this.location,
    this.notes,
    this.coverImage,
  });

  final int copiaId;
  final String operaTitolo;
  final String? serieName;
  final String? issueNumberLabel;
  final int? issueNumber;
  final String? publisher;
  final int? year;
  final FormatoEdizione? format;
  final List<CreatorConRuolo> autori;
  final CondizioneCopia? condition;
  final double? purchasePrice;
  final String? location;
  final String? notes;

  /// Percorso locale o URL remoto, già risolto (vedi
  /// `ComicsRepository.risolviCoverImage`) — `null` se assente, la scheda
  /// ricade sulla copertina procedurale (stesso fallback di
  /// `ComicCoverImage`/`ProceduralComicCover`).
  final String? coverImage;
}
