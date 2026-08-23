/// Stato di un'Analisi Copertina (OCR §6.1 + computer vision §6.2, deciso su
/// #31, esteso su #48): `pending` alla creazione della riga, `inCorso`
/// durante la chiamata a Claude, poi `completata` o `fallita` — nessun retry
/// automatico, `fallita` è terminale.
enum StatoAnalisiCopertina { pending, inCorso, completata, fallita }
