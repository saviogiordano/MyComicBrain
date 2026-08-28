# Tool-calling dell'Assistente a bassa granularità, non uno-per-capacità

La ricognizione delle query esistenti su `ComicsRepository` (ticket [#119](https://github.com/saviogiordano/MyComicBrain/issues/119), branch `research/assistente-tool-call-schema`) ha isolato 7 capacità che l'Assistente (§10) deve coprire: ricerca per campo/testo libero, numeri mancanti di una serie, conteggio/aggregazione per editore/anno, serie quasi complete, trova duplicati (due capacità aggiuntive — filtro per data d'acquisto e "letto senza recensione" — sono state poi escluse dallo scope, vedi il ticket [Schema del tool-calling dell'Assistente sopra ComicsRepository](https://github.com/saviogiordano/MyComicBrain/issues/126)). La domanda decisa qui: quante function esporre all'LLM Testuale per coprirle.

Decisione: **5 tool a filtri componibili**, non un tool per ciascuna capacità. In particolare `cercaEdizioni` bundla da solo titolo/serie/autore/editore/personaggio/tag/numero/isbn/testo libero in un unico set di parametri opzionali combinabili in AND, invece di essere spezzato in funzioni separate per campo. Gli altri quattro tool (`numeriMancantiSerie`, `conteggioPer`, `serieQuasiComplete`, `trovaDuplicati`) restano dedicati perché rispondono a una domanda strutturalmente diversa (aggregazione/enumerazione, non filtro), non perché la granularità fine sia preferibile in generale.

## Considered Options

- **Un tool per capacità** (7+ function strette, ciascuna con pochi parametri specifici) — scartata: più tool fra cui scegliere aumenta il rischio che l'LLM selezioni quello sbagliato quando le funzioni si sovrappongono semanticamente (es. "cerca per editore" vs "cerca per autore" sono la stessa operazione con un parametro diverso), a fronte di nessun beneficio implementativo — i dati di quasi tutte queste capacità vengono comunque dallo stesso payload (`watchIndiceCollezione`).

## Consequences

- Aggiungere un nuovo asse di filtro a `cercaEdizioni` in futuro (es. un campo bibliografico non ancora coperto) è un nuovo parametro opzionale sul tool esistente, non un nuovo tool — più economico da estendere finché il payload sorgente resta lo stesso.
- Il ticket che implementerà le query mancanti ([Implementare le query mancanti di ComicsRepository per il tool-calling](https://github.com/saviogiordano/MyComicBrain/issues/130)) e l'orchestratore ([Implementare l'orchestratore LLM Testuale con tool-calling](https://github.com/saviogiordano/MyComicBrain/issues/132)) devono trattare `cercaEdizioni` come un solo punto di ingresso con validazione/combinazione dei filtri, non come 9 funzioni indipendenti.
- Se in futuro emergesse un asse di filtro che richiede una fonte dati radicalmente diversa da `watchIndiceCollezione` (es. una query che non può essere espressa come filtro sullo stesso indice), la scelta andrà rivista caso per caso — questa decisione assume che tutti i filtri di `cercaEdizioni` continuino a vivere sullo stesso payload.
