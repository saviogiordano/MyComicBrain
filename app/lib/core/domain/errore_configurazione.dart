/// Prefisso comune ai messaggi d'errore di configurazione mancante (provider
/// AI o ComicVine senza API key, §12, deciso su
/// [Gestire l'assenza di configurazione: messaggi chiari quando manca provider/chiave](https://github.com/saviogiordano/MyComicBrain/issues/108)):
/// permette alla UI di distinguerli da un fallimento tecnico generico (rete,
/// risposta inattesa) e mostrare un link diretto alle Impostazioni invece
/// del solo messaggio grezzo dell'eccezione.
const prefissoConfigurazioneMancante = 'Configurazione mancante: ';

/// `true` se [errorMessage] segnala una configurazione mancante — non uno
/// dei tanti altri fallimenti tecnici possibili di Analisi Copertina o
/// Identificazione. Usa `contains`, non `startsWith`: il messaggio persiste
/// come `toString()` dell'eccezione originale (es. `CoverAnalysisException:
/// Configurazione mancante: ...`), che antepone il proprio prefisso.
bool erroreConfigurazioneMancante(String? errorMessage) =>
    errorMessage != null &&
    errorMessage.contains(prefissoConfigurazioneMancante);
