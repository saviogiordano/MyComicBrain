/// Una riga dell'elenco Serie (§11): nome e frazione posseduti/totale —
/// stesse informazioni di `SerieIncompleta` (Dashboard) ma copre anche le
/// serie complete e quelle senza numero totale, per le tre sezioni
/// dell'elenco `/serie` (deciso su #97/#98).
class SerieRiga {
  const SerieRiga({
    required this.serieId,
    required this.nome,
    required this.numeriPosseduti,
    required this.coverImage,
    this.numeriTotali,
  });

  final int serieId;
  final String nome;
  final int numeriPosseduti;

  /// Override esplicito o cover della prima Edizione posseduta per numero
  /// — stessa risoluzione di `SerieDettaglio.coverImage`.
  final String? coverImage;

  /// Null: la serie non ha un numero totale impostato — mai valutabile
  /// come completa o incompleta (CONTEXT.md, "Serie completa").
  final int? numeriTotali;

  double? get percentualeCompletamento =>
      numeriTotali == null ? null : numeriPosseduti / numeriTotali!;
}

/// L'elenco `/serie` (§11) raggruppato nelle tre sezioni fissate su #97:
/// **incomplete** (percentuale di completamento crescente), **complete**
/// (alfabetico), **senza numero totale** (alfabetico). Solo le serie con
/// almeno un'edizione posseduta compaiono — stesso filtro del KPI "serie"
/// della Dashboard (#2).
class SerieLista {
  const SerieLista({
    required this.incomplete,
    required this.complete,
    required this.senzaTotale,
  });

  final List<SerieRiga> incomplete;
  final List<SerieRiga> complete;
  final List<SerieRiga> senzaTotale;

  bool get isEmpty =>
      incomplete.isEmpty && complete.isEmpty && senzaTotale.isEmpty;
}
