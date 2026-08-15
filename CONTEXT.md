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
