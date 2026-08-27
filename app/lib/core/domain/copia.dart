/// Stato di possesso di una copia fisica — guida tutti i KPI di volume
/// della Dashboard (§27, §2 della mappa).
enum StatoCopia { posseduta, prestata, venduta, persa }

/// Stato di lettura di una copia — non ha effetto sui KPI di possesso.
enum StatoLettura { daLeggere, inLettura, letto, daRileggere }

/// Etichette leggibili per l'asse "Stato di lettura" della Collezione (§9)
/// — distinta da `VoceStatoLabel` (`voce_stato.dart`): quella copre le 7
/// voci del selettore §8.3 (incluse Prestato/Venduto/Mancante), questa i
/// soli 4 valori di [StatoLettura].
extension StatoLetturaLabel on StatoLettura {
  String get label => switch (this) {
    StatoLettura.daLeggere => 'Da leggere',
    StatoLettura.inLettura => 'In lettura',
    StatoLettura.letto => 'Letto',
    StatoLettura.daRileggere => 'Da rileggere',
  };
}

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
