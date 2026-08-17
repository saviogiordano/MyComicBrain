/// Stato di riconoscimento di una Scansione (§6, fuori scope in questa
/// mappa) — avanzerà quando l'AI la collega a un'edizione. Per ora esiste
/// solo lo stato iniziale.
enum StatoRiconoscimento { inSospeso }

/// Aspect ratio (larghezza/altezza) di una cover di fumetto: guida sia
/// l'overlay a mirino dello scanner (#19) sia il riquadro di ritaglio della
/// revisione (#24) — condiviso perché rappresentano la stessa forma attesa.
const coverAspectRatio = 0.68;
