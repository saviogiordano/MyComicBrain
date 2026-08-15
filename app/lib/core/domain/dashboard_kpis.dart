/// I numeri riassuntivi della Dashboard (§4.1), calcolati secondo le regole
/// fissate su #2: tutti i KPI di volume contano copie fisiche con
/// `status = posseduta`.
class DashboardKpis {
  const DashboardKpis({
    required this.totaleCopie,
    required this.numeroSerie,
    required this.serieComplete,
    required this.duplicati,
    required this.numeriMancanti,
    required this.spesoFinora,
    required this.aggiuntiMeseCorrente,
  });

  /// Copie con `status = posseduta`.
  final int totaleCopie;

  /// Serie distinte con almeno un'edizione posseduta.
  final int numeroSerie;

  /// Serie con "numeri totali" noto e nessun numero mancante.
  final int serieComplete;

  /// Edizioni con due o più copie possedute contemporaneamente.
  final int duplicati;

  /// Somma dei numeri mancanti su tutte le serie valutabili.
  final int numeriMancanti;

  /// Somma di `purchase_price` sulle copie possedute con prezzo presente.
  final double spesoFinora;

  /// Copie possedute con `created_at` nel mese solare corrente.
  final int aggiuntiMeseCorrente;
}

/// Una serie con "numeri totali" noto e almeno un numero mancante,
/// con la percentuale di completamento (§17, sezione "Serie incomplete").
class SerieIncompleta {
  const SerieIncompleta({
    required this.serieId,
    required this.nome,
    required this.numeriPosseduti,
    required this.numeriTotali,
    required this.numeriMancanti,
  });

  final int serieId;
  final String nome;

  /// Quanti numeri interi distinti da 1 a [numeriTotali] sono coperti da
  /// un'edizione posseduta.
  final int numeriPosseduti;

  final int numeriTotali;

  /// I numeri (1..[numeriTotali]) non coperti da alcuna edizione posseduta,
  /// in ordine crescente.
  final List<int> numeriMancanti;

  double get percentualeCompletamento => numeriPosseduti / numeriTotali;
}
