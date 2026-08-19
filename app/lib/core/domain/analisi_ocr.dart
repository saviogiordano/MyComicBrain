/// Stato di un'Analisi OCR (§6.1, deciso su #31): `pending` alla creazione
/// della riga, `inCorso` durante la chiamata a Claude, poi `completata` o
/// `fallita` — nessun retry automatico, `fallita` è terminale.
enum StatoAnalisiOcr { pending, inCorso, completata, fallita }
