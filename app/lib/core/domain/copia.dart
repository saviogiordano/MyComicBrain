/// Stato di possesso di una copia fisica — guida tutti i KPI di volume
/// della Dashboard (§27, §2 della mappa).
enum StatoCopia { posseduta, prestata, venduta, persa }

/// Stato di lettura di una copia — non ha effetto sui KPI di possesso.
enum StatoLettura { daLeggere, inLettura, letto, daRileggere }

/// Condizione fisica della copia (scala §14: mint...poor).
enum CondizioneCopia {
  mint,
  nearMint,
  veryFine,
  fine,
  veryGood,
  good,
  fair,
  poor,
}

/// Etichette leggibili per la Scheda del fumetto (§8.2, deciso su #69) —
/// la scala §14 resta quella già esistente, solo etichettata per la UI.
extension CondizioneCopiaLabel on CondizioneCopia {
  String get label => switch (this) {
    CondizioneCopia.mint => 'Mint',
    CondizioneCopia.nearMint => 'Near Mint',
    CondizioneCopia.veryFine => 'Very Fine',
    CondizioneCopia.fine => 'Fine',
    CondizioneCopia.veryGood => 'Very Good',
    CondizioneCopia.good => 'Good',
    CondizioneCopia.fair => 'Fair',
    CondizioneCopia.poor => 'Poor',
  };
}
