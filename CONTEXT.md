# MyComicBrain

Catalogo personale di fumetti: cattura una collezione fisica con scansione/riconoscimento AI, la organizza per opera/edizione/copia e ne calcola statistiche e completezza delle serie.

## Language

**Opera**:
La storia/testata a prescindere da come è stata pubblicata (es. "Spider-Man"). Distinta dall'edizione (§30 dei requisiti).
_Avoid_: Titolo, fumetto (quando si intende l'opera e non l'edizione)

**Edizione**:
Una pubblicazione specifica di un'opera — prima stampa, ristampa, variant, edizione italiana/USA, collected edition. È l'unità catalogata: ha una serie (facoltativa) e un numero. Due edizioni diverse della stessa opera non sono duplicati fra loro.
_Avoid_: Fumetto (ambiguo fra edizione e copia), albo (ok in prosa, non come termine di modello)

**Copia**:
Un esemplare fisico posseduto di un'edizione. Un'edizione può avere più copie (es. comprata due volte). Ha uno `status` proprio. Può portare un legame opzionale alla Scansione che l'ha originata (conferma di un Candidato o inserimento manuale, §6.3) — assente per le copie inserite senza passare da una Scansione. Se due Scansioni dello stesso batch confermano la stessa Edizione, il risultato sono normalmente due Copie di quell'Edizione, non un errore da prevenire — vedi Duplicato, [#53](https://github.com/saviogiordano/MyComicBrain/issues/53).
_Avoid_: Esemplare (ok in prosa), item

**Copia posseduta**:
Una copia con `status = posseduta`. Solo le copie posseduta contano nei KPI di volume della Dashboard (totale fumetti, duplicati, speso finora). `status = prestata` conta ancora come posseduta; `status = venduta` o `persa` no.

**In vendita**:
Campo booleano `inVendita` di Copia, default `false`: l'intenzione del proprietario di cedere quella copia (vendita o scambio, trattati come la stessa intenzione — non c'è oggi un meccanismo di scambio reale fra utenti, resta un'idea distinta di marketplace) — indipendente da `status` (§8.3) e da Stato di lettura: una copia resta posseduta e in vendita finché non viene effettivamente ceduta, momento in cui `status` passa a venduta. Nessuna scelta forzata alla creazione della copia; si imposta e si modifica in un secondo momento dalla scheda (§8.4). Segue la stessa regola di cascata di Edizione posseduta per il filtro della vista Collezione (§9): un'Edizione compare nel filtro "In vendita" se almeno una delle sue copie possedute lo è. Deciso su [Mappa — Copie "In vendita": marcatura, filtro e azione in blocco](https://github.com/saviogiordano/MyComicBrain/issues/163).
_Avoid_: Da vendere/Da conservare come due valori distinti (collassati in un unico booleano — vedi sopra), scambio/marketplace (idea distinta, fuori scope)

**Edizione posseduta**:
Un'edizione che ha almeno una copia posseduta. Il possesso è sempre relativo allo stato attuale, in cascata: copia posseduta → edizione posseduta → conta per serie e numerazione. Vendere l'unica copia di un'edizione la rende non posseduta, e il suo numero torna "mancante" nella serie. Stessa regola per l'Organizzazione della collezione (§9, deciso su [Mappa — Organizzazione della collezione](https://github.com/saviogiordano/MyComicBrain/issues/79)): la vista Collezione elenca Edizioni, e per gli assi che vivono sulla Copia (stato di lettura, condizione, posizione, in vendita) un'Edizione soddisfa il filtro se almeno una delle sue copie possedute lo soddisfa.

**Valore stimato**:
Il valore di mercato indicativo di una Copia, calcolato tramite un servizio esterno di pricing (API), a partire dai dati identificativi della sua Edizione (titolo, numero, editore) e modulato dalla Condizione della Copia (§8.6) quando l'utente l'ha impostata; se non impostata, si assume una condizione di default (Very Fine) come riferimento. Convertito e mostrato sempre in EUR. Distinto dal "prezzo di acquisto" (§8.2), che è un dato personale inserito dall'utente sul costo effettivamente sostenuto, non una stima di mercato. Vedi anche Valore stimato della collezione.
_Avoid_: Valutazione condition (quella di §8.6 è la stima della condizione fisica tramite AI, un concetto diverso), prezzo (ambiguo fra prezzo di acquisto e valore stimato — usare sempre il termine completo)

**Valore stimato della collezione**:
La somma dei Valori stimati di tutte le Copie possedute (stesso criterio di Copia posseduta: `prestata` conta, `venduta`/`persa` no) — non delle Edizioni, quindi due Copie della stessa Edizione contano entrambe. Alimenta i KPI di Dashboard (§4.1) e Statistiche (§14).

**Duplicato**:
Un'edizione con due o più copie posseduta contemporaneamente. Non riguarda edizioni diverse della stessa opera (quello è riconoscimento, non duplicazione) — vedi Opera/Edizione.
_Avoid_: Copia doppia (ambiguo su cosa si stia contando — l'edizione o le copie in eccesso)

**Serie**:
Un raggruppamento facoltativo di edizioni con numerazione progressiva (es. "The Amazing Spider-Man"). Un'edizione può non avere serie (volume unico, one-shot, cartonato) — in tal caso non entra nel conteggio serie né in quello di numeri mancanti.

**Serie completa**:
Una serie il cui campo facoltativo "numeri totali" è compilato e per cui ogni numero intero da 1 a quel totale corrisponde a un'edizione posseduta. Una serie senza "numeri totali" non è mai valutabile come completa o incompleta — resta esclusa da entrambi i KPI.

**Numero mancante**:
Per una serie con "numeri totali" noto: un intero fra 1 e il totale per cui nessuna edizione posseduta lo copre. La numerazione conta solo interi; variant, speciali e allegati non generano un proprio buco, ma una variant del numero N copre il buco del numero N se posseduta.

**Scansione**:
Una fotografia di una cover, acquisita e confermata dall'utente (dopo eventuale ritaglio/rotazione), non ancora processata dal riconoscimento AI. È l'unità persistita dall'acquisizione — distinta da Opera/Edizione/Copia, che nascono solo quando il riconoscimento (fuori scope qui) la collega a un'edizione. Stato iniziale: in sospeso.
_Avoid_: Scan (usare il termine italiano nel dominio; ok come nome di classe/tabella nel codice), foto, cover (ambiguo con l'immagine di un'edizione già catalogata)

**Analisi Copertina**:
Il risultato dell'estrazione automatica via Claude dei campi leggibili (OCR, §6.1) e riconosciuti visivamente (computer vision, §6.2) sulla cover di una Scansione — titolo, numero (come letto, non parsato), editore, nome collana (come letto — non è ancora un legame con una Serie catalogata), autori, ISBN, barcode, prezzo, codici identificativi, personaggi raffigurati, tag di stile copertina, tag di elementi visivi caratteristici, logo editore riconosciuto, logo serie riconosciuto, Tipo di stampa, Classificazione, Descrizione. Una lettura grezza, non verificata: non diventa un'Edizione finché il riconoscimento (§6.3, fuori scope qui) non la conferma. Relazione 1:1 con la Scansione che l'ha generata; stato pending/in corso/completata/fallita, nessun retry automatico. Si chiamava "Analisi OCR" prima di coprire anche la computer vision (rinominata su #48/#49).
_Avoid_: OCR/computer vision da soli come nome di entità (ok in prosa tecnica) — usare "Analisi Copertina" per il record persistito; "collana"/nome campo `serie` per il valore letto — collide con l'entità Serie già catalogata, che è un concetto diverso

**Personaggi raffigurati** / **Tag di stile copertina** / **Tag di elementi visivi caratteristici**:
Liste di tag liberi (stringhe), campi di computer vision (§6.2) dell'Analisi Copertina — mai `null`, lista vuota se Claude non riconosce nulla con sufficiente sicurezza. "Tag di stile copertina" descrive lo stile/genere artistico o la tipologia editoriale della copertina nel suo complesso (es. "manga", "variant cover"); "tag di elementi visivi caratteristici" elenca elementi visivi concreti e specifici che non descrivono uno stile generale (es. "sfondo con esplosione") — i due insiemi non si sovrappongono per costruzione del prompt, ma restano tag liberi non verificati.
_Avoid_: confondere "Personaggi raffigurati" con Personaggio (§9, voce distinta — entità catalogabile collegata all'Edizione, senza collegamento automatico a questo campo)

**Logo editore riconosciuto** / **Logo serie riconosciuto**:
Campi di computer vision (§6.2) dell'Analisi Copertina: il logo dell'editore/della serie riconosciuto visivamente sulla copertina, `null` se non riconoscibile. Paralleli ai campi OCR omologhi (`publisher`/nome collana) ma distinti — un logo può essere riconosciuto anche quando il nome testuale non è leggibile, e viceversa.

**Tipo di stampa**:
Campo `printingType` (§6.4/§8.1, deciso su [Mappa — Campi bibliografici AI](https://github.com/saviogiordano/MyComicBrain/issues/71)) di Analisi Copertina/Edizione: testo libero letto in copertina/indicia (es. "Direct Edition"), unifica le tre nozioni distinte di §6.4 (edizione/ristampa/variant) in un solo campo — sono la stessa domanda vista da angolazioni diverse.
_Avoid_: Edizione (già l'entità stessa nel glossario — questo campo descrive una proprietà testuale della stampa, non l'unità catalogata)

**Formato**:
Campo `format` (§9, deciso su [Formato: valori esatti dell'enum](https://github.com/saviogiordano/MyComicBrain/issues/83)) di Edizione: enum chiuso, valore singolo, nullable — Spillato, Bonellide, Brossurato, Cartonato, Tankōbon, Omnibus. Descrive la forma fisica di stampa dell'edizione, distinto da Tipo di stampa (che copre prima stampa/ristampa/variant, non il formato fisico). Il digitale non è un valore dell'enum — resta fuori scope (asse concettualmente diverso: rompe le assunzioni di possesso fisico su cui si basano Copia, Condizione e Posizione).
_Avoid_: confondere con Tipo di stampa (proprietà diversa dello stesso oggetto — vedi sopra)

**Anno**:
Campo `year` (§9, deciso su [Anno come campo strutturato su Edizione](https://github.com/saviogiordano/MyComicBrain/issues/81)) di Edizione: intero, nullable, popolato in scrittura (riconoscimento AI o inserimento manuale) — non derivato a runtime da `releaseDate` (testo grezzo tipo "mese/anno", troppo fragile da parsare per un asse di organizzazione centrale).
_Avoid_: confondere con `releaseDate` (testo grezzo per la visualizzazione bibliografica, §8.1 — voce distinta, non un asse di filtro)

**Personaggio**:
Campo di Edizione (§9, deciso su [Mappa — Organizzazione della collezione](https://github.com/saviogiordano/MyComicBrain/issues/79) via [#84](https://github.com/saviogiordano/MyComicBrain/issues/84)): relazione many-to-many con una nuova entità catalogabile `Character`, condivisa fra Edizioni diverse — stesso pattern di Creator (#64), nessun vincolo UNIQUE su `name` (dedup lasciato all'autocomplete in UI). Aggiunto manualmente dall'utente, senza collegamento automatico con "Personaggi raffigurati": stesso principio già valido per gli autori, che pure hanno un'entità dedicata (Creator) ma non si auto-collegano dai campi letti dall'AI alla conferma del Candidato.
_Avoid_: confondere con Personaggi raffigurati (voce distinta — quel campo vive sulla Scansione/Analisi Copertina, libero e non verificato, senza collegamento a questa entità catalogata)

**Genere**:
Campo di Edizione (§9, deciso su [Mappa — Organizzazione della collezione](https://github.com/saviogiordano/MyComicBrain/issues/79) via [#84](https://github.com/saviogiordano/MyComicBrain/issues/84)): enum chiuso, multi-valore (relazione many-to-many, a differenza di Formato che è singolo) — Supereroi, Azione/Avventura, Fantascienza, Fantasy, Horror, Giallo/Noir, Commedia, Drammatico, Romantico, Storico, Slice of life, Erotico/Adulti.

**Tag personalizzati**:
Campo di Edizione (§9, deciso su [Tag personalizzati: nuova entità Tag](https://github.com/saviogiordano/MyComicBrain/issues/82)): relazione many-to-many con una nuova entità `Tag`, libera da vincoli — definiti dall'utente, non dall'AI (a differenza di "Tag di stile copertina"/"Tag di elementi visivi caratteristici").
_Avoid_: confondere con "Tag di stile copertina"/"Tag di elementi visivi caratteristici" (voci distinte — quei campi vivono sull'Analisi Copertina, generati dall'AI, senza collegamento a questa entità catalogata)

**Sessione di acquisizione**:
Un raggruppamento temporaneo, non persistito, di più Scansioni prodotte consecutivamente (fotocamera e/o galleria) prima che l'utente termini con "Fine". Esiste solo come stato della UI: non sopravvive a un riavvio e non ha una propria riga nel database — solo le Scansioni che produce vengono salvate.
_Avoid_: Batch (ok in prosa tecnica, non come termine di dominio)

**Candidato**:
Un'ipotesi di corrispondenza fra una Scansione (tramite la sua Analisi Copertina) e un'Edizione — proposta dal riconoscimento (§6.3) durante l'Identificazione. Può provenire dal catalogo interno (un'Edizione già catalogata: confermarlo aggiunge una nuova Copia a quell'Edizione) o da un database esterno di fumetti (un'Edizione non ancora catalogata: confermarlo crea Opera/Edizione/Copia da zero). Porta un Punteggio di confidenza. Persiste come riga propria non appena proposto (non solo se confermato); confermarlo marca quella riga come scelta e collega/crea la Copia risultante — vedi [Mappa — Identificazione del fumetto](https://github.com/saviogiordano/MyComicBrain/issues/50), [#52](https://github.com/saviogiordano/MyComicBrain/issues/52), [#53](https://github.com/saviogiordano/MyComicBrain/issues/53).
_Avoid_: Risultato, match (ok in prosa tecnica, non come termine di modello)

**Identificazione**:
Il processo — e la riga che lo traccia, 1:1 con una Scansione — che genera i Candidati a partire dall'Analisi Copertina di quella Scansione (§6.3). Stato pending/in corso/completata/fallita, stesso pattern di Analisi Copertina: nessun retry automatico né manuale, `fallita` è terminale (un errore tecnico, es. database esterno irraggiungibile — non lo stesso caso di "nessun Candidato trovato", che è comunque `completata`, solo senza Candidati proposti). Una Scansione è "risolta" quando esiste una Copia collegata a lei (conferma di un Candidato o inserimento manuale) — non è un attributo proprio dell'Identificazione. Deciso su [#53](https://github.com/saviogiordano/MyComicBrain/issues/53).
_Avoid_: Riconoscimento (il processo AI generico di §6 in prosa tecnica, non il nome di questa entità/tabella)

**Punteggio di confidenza**:
Un valore 0–100% assegnato a un Candidato durante l'identificazione (§6.3), che ne esprime la probabilità di essere la corrispondenza corretta. Calcolato combinando più segnali (non una cascata a livelli con stop al primo che risponde — tutti i segnali applicabili concorrono allo stesso punteggio): un segnale testuale dominante (somiglianza fra i campi letti nell'Analisi Copertina e i campi del Candidato), un boost secondario da Personaggi raffigurati/Tag di stile copertina/Tag di elementi visivi caratteristici/loghi riconosciuti (corrobora un match testuale già presente, non ne genera uno da solo), e un bonus additivo di contesto (stessa Serie già in catalogo con un numero adiacente o mancante fra le copie possedute). Barcode/ISBN letti nell'Analisi Copertina non contribuiscono al punteggio: nessuna delle due fonti di matching li supporta oggi come chiave di ricerca. I pesi relativi fra i segnali non sono fissati come valori di dominio: sono un dettaglio implementativo tarabile, non un concetto della collezione. Dettagli in [#52](https://github.com/saviogiordano/MyComicBrain/issues/52).
_Avoid_: Score (ok in prosa tecnica, non come termine di modello), affidabilità (ambiguo con la condizione fisica della Copia)

**Assistente**:
L'unica funzione di ricerca dell'app (§10): un'interfaccia conversazionale (testo o voce) raggiungibile dalla voce "Cerca" della bottom nav, che interroga la collezione dell'utente in linguaggio naturale e non inventa informazioni mancanti. Fonde in un'unica funzione l'ex ricerca a campi strutturati e l'ex "AI Assistant" (§14, ora confluito in §10) — non esiste più una schermata di ricerca a campi separata. Deciso su [Mappa — Ricerca conversazionale e Assistente](https://github.com/saviogiordano/MyComicBrain/issues/118).
_Avoid_: Ricerca (ambiguo — nome del requisito/funzionalità in prosa, non di questa interfaccia specifica), Cerca (nome della voce di navigazione, non dell'interfaccia stessa)

**Provider AI Visivo** / **Provider AI Testuale**:
Le due selezioni indipendenti di provider AI in Impostazioni (§12) — ciascuna con proprio brand (OpenAI/Claude/OpenRouter/Locale), API key, modello e, per Locale, URL. Il Visivo serve l'Analisi Copertina (§6, invariato); il Testuale serve l'Assistente. Possono coincidere o differire (es. visione su un brand cloud, testo su Locale), scelta pensata per ottimizzare il costo delle chiamate testuali rispetto a quelle di visione. Non esiste più un `AiProvider` unico condiviso fra i due usi. Vedi [ADR-0001](docs/adr/0001-provider-ai-visivo-testuale-separati.md).
_Avoid_: Provider AI (ambiguo dopo lo sdoppiamento — specificare sempre Visivo o Testuale)

**Conversazione**:
Il thread persistito degli scambi fra l'utente e l'Assistente (§10): multi-turno (l'Assistente mantiene il contesto degli scambi precedenti), unico e continuo — nessun concetto di "nuova conversazione" o cronologia di più conversazioni distinte, a differenza dei thread separati tipici dei chatbot generici. Sopravvive alla chiusura dell'app, conservata indefinitamente finché l'utente non la cancella esplicitamente (azione dedicata, indipendente dall'eliminazione dell'account di §19 Privacy, che comunque la include). La cancellazione svuota sempre l'intera Conversazione, mai singoli Messaggi. Composta da una sequenza di Messaggi. Deciso su [Memoria conversazionale e persistenza della cronologia chat dell'Assistente](https://github.com/saviogiordano/MyComicBrain/issues/122).
_Avoid_: Cronologia, chat (ok in prosa per descrivere l'interfaccia o il comportamento, non come nome dell'entità persistita)

**Messaggio**:
Un singolo scambio all'interno della Conversazione: domanda dell'utente, risposta dell'Assistente, oppure un messaggio di sistema (errore del Provider AI Testuale, query non interpretabile, segnalazione del fallback dello speech-to-text in rete) — questi ultimi portano un tipo/flag distintivo solo per lo stile in UI, ma sono Messaggi a tutti gli effetti: persistiti nella Conversazione come gli altri, non un concetto separato. Non cancellabile singolarmente: la cancellazione è sempre dell'intera Conversazione, mai di un Messaggio isolato — vedi Conversazione. Deciso su [Gestione errori dell'Assistente (provider irraggiungibile, query non interpretabile)](https://github.com/saviogiordano/MyComicBrain/issues/124).

**Profilo**:
Un account Supabase Auth distinto (§17.1) — l'unità di autenticazione e di switch rapido fra più utenti sullo stesso dispositivo. Ha una riga persistente (nome visualizzato) che sopravvive alla cancellazione dell'account: viene anonimizzata (nome sostituito da un placeholder) invece che cancellata, perché l'autore di una modifica in una Collezione condivisa (§17.2/§27) deve restare sempre risolvibile anche dopo che un collaboratore ha eliminato il proprio account. Deciso su [#151](https://github.com/saviogiordano/MyComicBrain/issues/151) (mapping su Supabase Auth) e [Decisione — schema Postgres + RLS per ruoli su collezioni condivise](https://github.com/saviogiordano/MyComicBrain/issues/154) (persistenza per l'audit).
_Avoid_: Account (ok in prosa generica su Supabase Auth, ma nel dominio dell'app il termine è Profilo — coerente con §17.1), Utente (troppo generico)

**Collezione**:
L'unità di condivisione multiutente su Supabase (§17.2/§17.3): un insieme di Opere/Edizioni/Copie con un Proprietario e zero o più collaboratori, ciascuno con un Ruolo distinto. Ogni Profilo possiede esattamente una Collezione, creata automaticamente alla registrazione — nessun flusso oggi per possederne più di una. Deciso su [#154](https://github.com/saviogiordano/MyComicBrain/issues/154).

**Modalità locale**:
Lo stato d'uso dell'app *prima* di qualunque autenticazione su un device — scansione, catalogazione, tutto, appoggiato solo su drift/sqlite locale. Non è uno dei Profili di §17.1 (non richiede un account), è ciò che c'è prima che ne esista uno. Alla prima autenticazione su quel device (creazione di un account o login su uno già esistente), i suoi dati migrano/si uniscono alla Collezione di destinazione e la Modalità locale su quel device si esaurisce — l'uso successivo richiede sempre un Profilo autenticato. Deciso su [#155](https://github.com/saviogiordano/MyComicBrain/issues/155), dettagli in [ADR-0005](docs/adr/0005-migrazione-dati-drift-supabase.md).
_Avoid_: Offline mode (quello di §19 è un requisito futuro per profili *già* autenticati, fuori scope della decisione qui — voce distinta, non ancora progettata), modalità ospite/guest (nessun concetto di sessione temporanea: la Modalità locale non scade e non richiede mai un account per continuare a funzionare)

**Ruolo**:
La posizione di un Profilo rispetto a una Collezione (§17.2): **Proprietario** (gestione completa, incluso invitare/rimuovere collaboratori ed eliminare la Collezione — sempre esattamente uno per Collezione, mai co-proprietà), **Editor** (aggiunge/modifica/elimina Opere, Edizioni e Copie, non gestisce i collaboratori) o **Visualizzatore** (accesso in sola lettura). Deciso su [#154](https://github.com/saviogiordano/MyComicBrain/issues/154).
_Avoid_: Permesso (usare Ruolo per la posizione in una Collezione; "permesso" resta ok in prosa per descrivere cosa un Ruolo consente)

**Invito**:
Una proposta di collaborazione su una Collezione (§17.2), inviata via email o come codice/link condivisibile, in stato in sospeso/accettato/rifiutato/revocato/scaduto. Distinto dall'appartenenza vera e propria (che nasce solo all'accettazione): un Invito non ancora accettato non dà alcun accesso alla Collezione. Deciso su [#154](https://github.com/saviogiordano/MyComicBrain/issues/154).
