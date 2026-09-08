# Percorso di migrazione dati da drift/sqlite locale a Supabase Postgres (§17)

ADR-0003 fissa l'architettura (accesso diretto a Supabase, niente backend custom) e ADR-0004 lo schema multiutente (`collections`/`collection_members`, una Collezione per account). Nessuno dei due copre il momento di passaggio: oggi l'app è interamente locale (drift/sqlite, nessun account), e resterà usabile così anche dopo l'introduzione degli account. Questo documento registra quando e come i dati locali di un device si trasferiscono a Supabase. Decisioni prese in sessione di grilling sul ticket [#155](https://github.com/saviogiordano/MyComicBrain/issues/155) (mappa [#149](https://github.com/saviogiordano/MyComicBrain/issues/149)).

Decisione, in sintesi:

- **Modalità locale permanente**: usare l'app senza autenticarsi resta un modo d'uso pieno (scansione, catalogazione, tutto), non solo un onboarding provvisorio. Non è uno dei Profili di §17.1 — è lo stato precedente a qualunque autenticazione su un device. Vedi anche la voce di glossario "Modalità locale" in `CONTEXT.md`.
- **Trigger**: qualunque evento di autenticazione (creazione di un account *o* login su uno già esistente) su un device che ha ancora dati in Modalità locale scatena la migrazione — non solo la prima registrazione in assoluto.
- **Passaggio esplicito, non silenzioso**: l'utente vede una conferma ("abbiamo trovato N fumetti sul device, vuoi importarli?") con default "sì". Rifiutare scarta i dati locali di quel device.
- **Account nuovo**: il primo account creato su un device eredita i dati locali di quel device; ogni Profilo successivo creato sullo stesso device parte con una Collezione vuota (i dati locali sono già stati "consumati" dal primo).
- **Account esistente su un altro device**: se l'account esiste già (creato altrove) e il login avviene su un device che ha una propria Modalità locale con dati, questi vengono uniti (merge, come nuove Copie/Edizioni) alla Collezione remota già esistente — stesso percorso tecnico della migrazione "primo account", solo con una destinazione non vuota. Nessuna deduplica automatica, stessa logica già decisa in ADR-0004/[#154](https://github.com/saviogiordano/MyComicBrain/issues/154) (due conferme sulla stessa Edizione producono normalmente due Copie distinte).
- **Cosa migra**: il catalogo confermato (Opere/Edizioni/Copie/Serie/Creator/Personaggi/Tag) e le Scansioni/Analisi Copertina/Identificazione/Candidati non ancora risolti in una Copia (lavoro in corso, non solo dati confermati — scartarlo sarebbe una perdita reale). Esclusa la Conversazione con l'Assistente: non migra, resta persa con la Modalità locale.
- **Immagini** delle cover caricate su Supabase Storage durante la stessa operazione.
- **Dopo una migrazione riuscita, drift viene svuotato**: Supabase diventa l'unica fonte autorevole per quell'account, l'app opera online-only per i profili autenticati (nessuna cache locale di lettura) finché una mappa futura non riprogetta sincronizzazione/offline (§18/§19, fuori scope qui).
- **Gestione errori**: operazione bloccante e riprovabile in primo piano ("importazione in corso/fallita, riprova"), non best-effort silenzioso in background — evita stati ambigui su una collezione intera di dati non duplicabili facilmente (foto, catalogazione manuale).

## Considered Options

- **Account obbligatorio da subito, nessuna Modalità locale permanente** — scartata: romperebbe l'onboarding "scatta e basta" esistente e non c'è nessun requisito che imponga l'autenticazione per il solo uso in singolo giocatore della collezione.
- **Migrazione silenziosa e automatica**, senza chiedere conferma — scartata: i dati locali sono lavoro dell'utente (scansioni, catalogazione manuale); cancellarli o spostarli senza un passaggio visibile sarebbe distruttivo a sorpresa.
- **Escludere Scansioni/Candidati non risolti dalla migrazione** (migrare solo il catalogo confermato) — scartata: la Modalità locale è un flusso di lavoro pieno, non solo un demo; un utente può avere scansioni già fotografate e analizzate ma non confermate al momento della registrazione, e perderle sarebbe una perdita di lavoro reale a fronte di un costo di migrazione basso.
- **Mantenere drift come cache locale post-migrazione** (per anticipare un futuro offline mode) — scartata per questa decisione: progettare la cache richiede scelte di consistenza (staleness, conflitti in scrittura) esplicitamente fuori scope di questa mappa (§18/§19 sono "Out of scope" in [#149](https://github.com/saviogiordano/MyComicBrain/issues/149)); costruire ora una cache "a metà" senza strategia di sync sarebbe peggio che non averla.
- **Sync best-effort in background** in caso di errore di migrazione — scartata a favore del blocco in primo piano: è un'operazione una tantum su dati preziosi e difficili da recuperare (intera collezione, foto); un fallimento silenzioso lascerebbe l'utente incerto su cosa sia stato davvero salvato.

## Consequences

- L'implementazione di questa migrazione (probabile prossimo passo esecutivo dopo questa mappa) deve, per ogni riga migrata, popolare `collection_id`/`created_by` come definiti in ADR-0004, e caricare le immagini locali su Supabase Storage prima di considerare la riga migrata.
- Il flusso di registrazione/login deve controllare la presenza di dati in Modalità locale sul device *prima* di completare l'autenticazione, per poter mostrare il prompt di conferma.
- Un futuro lavoro su §18/§19 (sincronizzazione/offline per profili già autenticati) non riguarda questa decisione: la Modalità locale qui descritta esiste solo *prima* dell'autenticazione, non come cache parallela dopo.
