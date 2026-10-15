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
typedef StatoAnalisiScansione = ({
  StatoAnalisiCopertina stato,
  String? errorMessage,
});

/// Una Scansione mandata al riconoscimento ("Fine" nel riepilogo) la cui
/// Analisi Copertina non è ancora partita: la riga è `pending`. Succede
/// senza rete, o su un altro device del Profilo, che non ha il file
/// (ADR-0008, #210).
typedef ScansioneInAttesa = ({
  String analisiId,
  String scansioneId,
  String image,
});
