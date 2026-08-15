/// Stato di possesso di una copia fisica — guida tutti i KPI di volume
/// della Dashboard (§27, §2 della mappa).
enum StatoCopia { posseduta, prestata, venduta, persa }

/// Stato di lettura di una copia — non ha effetto sui KPI di possesso.
enum StatoLettura { daLeggere, inLettura, letto, daRileggere }

/// Condizione fisica della copia (scala §14: mint...poor).
enum CondizioneCopia { mint, nearMint, veryFine, fine, veryGood, good, fair, poor }
