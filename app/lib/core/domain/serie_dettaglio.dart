/// Il dettaglio `/serie/:id` (§11): numeri posseduti/mancanti, statistiche
/// derivate dalle edizioni della serie, e i campi editabili — nome, numero
/// totale, issn (deciso su #99, unica scrittura UI su questi campi), cover.
class SerieDettaglio {
  const SerieDettaglio({
    required this.serieId,
    required this.nome,
    required this.issn,
    required this.numeriTotali,
    required this.numeriPosseduti,
    required this.duplicati,
    required this.publisher,
    required this.annoInizio,
    required this.coverImage,
    required this.coverImageOverride,
  });

  final int serieId;
  final String nome;
  final String? issn;

  /// La cover da mostrare: l'override esplicito se impostato, altrimenti
  /// la cover della prima Edizione posseduta per numero — già risolta
  /// (percorso locale assoluto o URL remoto, vedi
  /// `ComicsRepository.risolviCoverImage`). Null se nessuna delle due
  /// esiste — la UI ricade sulla copertina procedurale come per le Edizioni.
  final String? coverImage;

  /// Il solo valore di override (`SerieTable.coverImage`, non risolto) —
  /// serve a `ModificaSerieSheet` per sapere se esiste già una scelta
  /// esplicita da poter rimuovere ("torna al default"), distinto da
  /// [coverImage] che è sempre il valore effettivo mostrato.
  final String? coverImageOverride;

  /// Null: numero totale non impostato — nessuna griglia possibile, la
  /// serie non è mai valutabile come completa (CONTEXT.md).
  final int? numeriTotali;

  /// I numeri posseduti (1..[numeriTotali] se noto), in ordine crescente —
  /// stesso filtro "posseduto" del resto del catalogo (`status IN
  /// (posseduta, prestata)`).
  final List<int> numeriPosseduti;

  /// Edizioni della serie con ≥2 copie possedute contemporaneamente —
  /// stessa definizione di Duplicato in CONTEXT.md, raggruppata per serie.
  final int duplicati;

  /// Editore più frequente fra le edizioni della serie — derivato, nessun
  /// campo su `SerieTable` (deciso su #97).
  final String? publisher;

  /// Anno minimo fra le edizioni della serie con anno noto — derivato,
  /// nessun campo su `SerieTable` (deciso su #97).
  final int? annoInizio;

  /// I numeri (1..[numeriTotali]) non coperti da alcuna edizione posseduta,
  /// in ordine crescente. Vuota se [numeriTotali] è null.
  List<int> get numeriMancanti {
    if (numeriTotali == null) return const [];
    final posseduti = numeriPosseduti.toSet();
    return [
      for (var n = 1; n <= numeriTotali!; n++)
        if (!posseduti.contains(n)) n,
    ];
  }

  bool get completa => numeriTotali != null && numeriMancanti.isEmpty;
}
