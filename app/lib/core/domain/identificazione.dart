/// Stato di un'Identificazione (§6.3, deciso su #53): stesso schema a stati
/// di `AnalisiCopertina` (`pending` alla creazione, `inCorso` durante la
/// generazione dei Candidati, poi `completata` o `fallita`) — ma un'entità
/// distinta nel dominio (vedi `CONTEXT.md`), non lo stesso stato riusato.
/// `completata` copre anche il caso "zero Candidati trovati": nessuno stato
/// speciale, la differenza è l'assenza di righe `Candidati`. `fallita` è
/// riservato a un errore tecnico (es. database esterno irraggiungibile) ed è
/// terminale — nessun retry automatico né manuale, come `AnalisiCopertina`.
enum StatoIdentificazione { pending, inCorso, completata, fallita }

/// Provenienza di un Candidato (§6.3, deciso su #53): `interno` se combacia
/// con un'Edizione già catalogata (`edizioneId` valorizzato, confermarlo
/// aggiunge solo una nuova Copia), `esterno` se proviene da ComicVine e non
/// ha ancora una riga Edizione propria (confermarlo crea Opera/Edizione/Copia
/// da zero, con i campi grezzi della riga come dati di partenza).
enum FonteCandidato { interno, esterno }
