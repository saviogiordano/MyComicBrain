/// Stato di un'Analisi Copertina (OCR §6.1 + computer vision §6.2, deciso su
/// #31, esteso su #48): `pending` alla creazione della riga, `inCorso`
/// durante la chiamata a Claude, poi `completata` o `fallita` — nessun retry
/// automatico, `fallita` è terminale.
enum StatoAnalisiCopertina { pending, inCorso, completata, fallita }

/// Stato osservabile dell'Analisi Copertina di una Scansione, per la UI del
/// riepilogo: `pending` finché la pipeline sequenziale non ha ancora preso
/// in carico questa Scansione (nessuna riga `AnalisiCopertinaTable` ancora),
/// altrimenti lo stato reale della riga. `errorMessage` è valorizzato solo
/// quando `stato` è `fallita`.
typedef StatoAnalisiScansione = ({StatoAnalisiCopertina stato, String? errorMessage});
