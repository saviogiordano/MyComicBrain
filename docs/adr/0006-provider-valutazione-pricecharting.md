# Provider di valutazione: PriceCharting (§35)

Il Valore stimato (§35) richiede un servizio esterno di pricing interrogabile per titolo+numero+editore, che restituisca un prezzo modulato per condizione/grado. Una ricerca su dieci servizi (`docs/research/valutazione-fumetti-api-pricing.md`, sul branch `research/valutazione-fumetti-api-pricing`) ha verificato la documentazione ufficiale di ciascuno per capire quali espongano un'API self-serve reale, non solo un'interfaccia web o una partnership B2B negoziata.

Decisione: **PriceCharting** è il provider scelto per la prima implementazione, ed è oggi l'unica voce del nuovo ruolo "Provider valutazione" (§35.1).

## Considered Options

- **GoCollect** — scartata: il percorso "API" è gated da approvazione manuale e di scopo ambiguo (sembra pensato per condividere dati *verso* GoCollect più che per interrogare prezzi); la sua storica integrazione di pricing con un tool di catalogazione terzo (CLZ) è terminata quando l'accordo commerciale è scaduto (2021), segno che l'accesso a scopo di consultazione prezzi non è garantito né duraturo.
- **CovrPrice** e **GPAnalysis** — scartate: hanno i dati più ricchi (CovrPrice distingue esplicitamente le variant cover) ma nessuna delle due espone un'API pubblica self-serve; l'unico canale noto è una partnership B2B negoziata (es. CovrPrice via CLZ), non una registrazione aperta.
- **eBay** — scartata: l'unica API con dati di vendite concluse (Marketplace Insights) è limited-release e non richiedibile da sviluppatori indipendenti; la Browse API (annunci attivi, non vendite concluse) non dà un valore di mercato affidabile.
- **Comics Price Guide, Overstreet Access, Comic Book Realm, Key Collector Comics** — scartate: nessuna espone un'API pubblica documentata.

## Consequences

- Costo fisso di $49/mese (piano "Legendary") per l'accesso API, indipendentemente dal volume di chiamate entro il rate-limit.
- **Nessuna copertura confermata per edizioni italiane o manga** — per quelle Edizioni il Valore stimato sarà quasi sempre "non disponibile" (§35.2/§35.4), non un errore dell'app.
- Rate-limit di 1 chiamata/secondo: coerente con un innesco solo event-driven (§35.3, nessun job periodico, import massivo escluso), ma un futuro trigger che chiami il provider in batch (es. su import) andrebbe rivalutato contro questo limite.
- Il mapping Condizione→grado numerico (§35.2) e la struttura di risposta usata dal client (`PriceChartingClient`, implementazione) sono costruiti dalla pagina "Description of Keys" della documentazione ufficiale, non da una risposta reale osservata — da riverificare con una chiamata live non appena la sottoscrizione è attiva.
- Se in futuro emergesse un secondo provider (es. per coprire manga/edizioni europee), il pattern a campo singolo di §35.1 è comunque esteso senza refactoring — stessa scelta già presa per "Provider fumetti"/ComicVine.
