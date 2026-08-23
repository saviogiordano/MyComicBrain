# MyComicBrain

Catalogo personale di fumetti: cattura una collezione fisica con scansione/riconoscimento AI, la organizza per opera/edizione/copia e ne calcola statistiche e completezza delle serie.

## Language

**Opera**:
La storia/testata a prescindere da come è stata pubblicata (es. "Spider-Man"). Distinta dall'edizione (§36 dei requisiti).
_Avoid_: Titolo, fumetto (quando si intende l'opera e non l'edizione)

**Edizione**:
Una pubblicazione specifica di un'opera — prima stampa, ristampa, variant, edizione italiana/USA, collected edition. È l'unità catalogata: ha una serie (facoltativa) e un numero. Due edizioni diverse della stessa opera non sono duplicati fra loro.
_Avoid_: Fumetto (ambiguo fra edizione e copia), albo (ok in prosa, non come termine di modello)

**Copia**:
Un esemplare fisico posseduto di un'edizione. Un'edizione può avere più copie (es. comprata due volte). Ha uno `status` proprio.
_Avoid_: Esemplare (ok in prosa), item

**Copia posseduta**:
Una copia con `status = posseduta`. Solo le copie posseduta contano nei KPI di volume della Dashboard (totale fumetti, duplicati, speso finora). `status = prestata` conta ancora come posseduta; `status = venduta` o `persa` no.

**Edizione posseduta**:
Un'edizione che ha almeno una copia posseduta. Il possesso è sempre relativo allo stato attuale, in cascata: copia posseduta → edizione posseduta → conta per serie e numerazione. Vendere l'unica copia di un'edizione la rende non posseduta, e il suo numero torna "mancante" nella serie.

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
Il risultato dell'estrazione automatica via Claude dei campi leggibili (OCR, §6.1) e riconosciuti visivamente (computer vision, §6.2) sulla cover di una Scansione — titolo, numero (come letto, non parsato), editore, nome collana (come letto — non è ancora un legame con una Serie catalogata), autori, ISBN, barcode, prezzo, codici identificativi, personaggi raffigurati, tag di stile copertina, tag di elementi visivi caratteristici, logo editore riconosciuto, logo serie riconosciuto. Una lettura grezza, non verificata: non diventa un'Edizione finché il riconoscimento (§6.3, fuori scope qui) non la conferma. Relazione 1:1 con la Scansione che l'ha generata; stato pending/in corso/completata/fallita, nessun retry automatico. Si chiamava "Analisi OCR" prima di coprire anche la computer vision (rinominata su #48/#49).
_Avoid_: OCR/computer vision da soli come nome di entità (ok in prosa tecnica) — usare "Analisi Copertina" per il record persistito; "collana"/nome campo `serie` per il valore letto — collide con l'entità Serie già catalogata, che è un concetto diverso

**Personaggi raffigurati** / **Tag di stile copertina** / **Tag di elementi visivi caratteristici**:
Liste di tag liberi (stringhe), campi di computer vision (§6.2) dell'Analisi Copertina — mai `null`, lista vuota se Claude non riconosce nulla con sufficiente sicurezza. "Tag di stile copertina" descrive lo stile/genere artistico o la tipologia editoriale della copertina nel suo complesso (es. "manga", "variant cover"); "tag di elementi visivi caratteristici" elenca elementi visivi concreti e specifici che non descrivono uno stile generale (es. "sfondo con esplosione") — i due insiemi non si sovrappongono per costruzione del prompt, ma restano tag liberi non verificati.

**Logo editore riconosciuto** / **Logo serie riconosciuto**:
Campi di computer vision (§6.2) dell'Analisi Copertina: il logo dell'editore/della serie riconosciuto visivamente sulla copertina, `null` se non riconoscibile. Paralleli ai campi OCR omologhi (`publisher`/nome collana) ma distinti — un logo può essere riconosciuto anche quando il nome testuale non è leggibile, e viceversa.

**Sessione di acquisizione**:
Un raggruppamento temporaneo, non persistito, di più Scansioni prodotte consecutivamente (fotocamera e/o galleria) prima che l'utente termini con "Fine". Esiste solo come stato della UI: non sopravvive a un riavvio e non ha una propria riga nel database — solo le Scansioni che produce vengono salvate.
_Avoid_: Batch (ok in prosa tecnica, non come termine di dominio)
