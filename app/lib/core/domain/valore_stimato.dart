/// Stato del Valore stimato di una Copia (§35, deciso su
/// [UX di calcolo e gestione errori del Valore stimato](https://github.com/saviogiordano/MyComicBrain/issues/161)):
/// stesso pattern a stati di `StatoAnalisiCopertina`/`StatoIdentificazione`,
/// con due varianti in più al posto di un singolo `fallita` — `nonDisponibile`
/// (provider non configurato o Edizione non coperta dalla fonte, placeholder
/// permanente senza retry dedicato) è distinto da `fallita` (errore
/// transitorio — rete, timeout, rate-limit — ritentabile con l'azione
/// manuale "Aggiorna valore stimato"). Nessun valore `pending`: a differenza
/// di Analisi Copertina/Identificazione (one-shot per Scansione), qui una
/// riga assente significa semplicemente "non ancora calcolato", trattato
/// dalla UI come `inCorso`.
enum StatoValoreStimato { inCorso, completata, nonDisponibile, fallita }

/// Coppia stato+errore osservabile in streaming, stesso ruolo di
/// `StatoAnalisiScansione` per l'Analisi Copertina.
typedef ValoreStimatoOsservabile = ({
  StatoValoreStimato stato,
  String? errorMessage,
});
