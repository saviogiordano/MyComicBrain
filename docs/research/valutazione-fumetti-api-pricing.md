# Ricerca: servizi di pricing/valutazione fumetti raggiungibili via API

Ticket: [#158 — Servizi di pricing per fumetti raggiungibili via API](https://github.com/saviogiordano/MyComicBrain/issues/158) (mappa: [#157](https://github.com/saviogiordano/MyComicBrain/issues/157))

Obiettivo: individuare servizi esterni che offrano dati di valutazione/pricing per fumetti, raggiungibili in modo programmatico (API), ricercabili per titolo + numero (+ editore), utilizzabili per calcolare il "Valore stimato" di una Copia posseduta modulato dalla Condizione.

Metodo: verifica diretta di documentazione ufficiale (pagine "API docs", pricing, developer/partner program) di ciascun servizio. Dove il fetch automatico era bloccato (403 su richieste da bot), i contenuti sono stati recuperati con `curl` da user-agent browser standard — le citazioni riportano comunque l'URL della pagina ufficiale consultata, non un riassunto di terze parti.

---

## 1. PriceCharting

- **API reale**: sì, pubblica, self-serve, con documentazione completa. https://www.pricecharting.com/api-documentation
- **Copertura editoriale**: categoria "Comics" con sotto-categorie Marvel, DC, Dark Horse, Dell, Image, "Other Comics" (menù del sito, stessa pagina). Nessuna categoria manga o edizioni europee/italiane esplicita — il catalogo è centrato sul mercato USA mainstream. "Other Comics" potrebbe includere editori minori ma non è documentato cosa copra esattamente.
- **Autenticazione**: token statico condiviso (parametro `t` in query string), associato all'abbonamento. Nessun piano gratuito per l'API: **richiede l'abbonamento "Legendary" ($49/mese)** — Free e Collector ($6/mese o $59/anno) non includono l'accesso API (tabella comparativa in https://www.pricecharting.com/pricecharting-pro).
- **Rate limit**: 1 chiamata al secondo; superarlo ripetutamente porta al blocco e alla revoca dei permessi dell'account. Esiste anche un export CSV completo (limitato a 1 richiesta ogni 10 minuti, generato ogni 24h), disponibile solo ai sottoscrittori Legendary.
- **Ricerca**: full-text via parametro `q` (es. `q=earthbound`, esempio nella doc per le carte: `charizard #4`), oppure per `id` (ID prodotto PriceCharting) o `upc`. Non risulta un parametro dedicato "publisher" — la ricerca testuale combina titolo/serie.
- **Scala di grading e struttura prezzo**: tabella completa prezzo-per-grado, non un singolo valore. Dalla sezione "Prices API: Description of Keys" (stessa pagina):
  - `loose-price` → fumetto non gradato ("Ungraded")
  - `condition-9-price` → gradato 2.0 (Good)
  - `condition-13-price` → gradato 3.0
  - `cib-price` → gradato 4.0 o 4.5
  - `condition-14-price` → gradato 5.0
  - `new-price` → gradato 6.0 o 6.5
  - `condition-15-price` → gradato 7.0
  - `graded-price` → gradato 8.0 o 8.5
  - `condition-16-price` → gradato 9.0
  - `box-only-price` → gradato 9.2
  - `condition-17-price` → gradato 9.4
  - `condition-10-price` → gradato 9.6 (Near Mint+)
  - `manual-only-price` → gradato 9.8
  - `bgs-10-price` → gradato 10.0

  È quindi la scala numerica CGC/Overstreet standard (0.5–10.0), con un prezzo per (quasi) ogni grado intermedio.
- **Variant cover**: non documentato esplicitamente come campo distinto nell'API. Ogni edizione/variante ha presumibilmente un `product-id` proprio nel catalogo (come accade per le versioni regionali dei videogiochi), ma la doc non conferma come le variant cover siano trattate nel catalogo comics.
- **Blocchi**: nessuno — è un servizio attivo, con signup self-service (serve solo carta di credito per il piano Legendary). L'azienda esiste dal 2007 (footer del sito).

## 2. GoCollect

- **API reale**: esiste un percorso di richiesta API, ma **non self-serve immediato**: richiede registrazione gratuita + compilazione di un modulo di richiesta, revisione manuale del team GoCollect, e solo dopo l'approvazione il token generato diventa funzionante. https://gocollect.com/data-sharing
- **Natura dell'API**: attenzione — la pagina descrive l'"API Integration" principalmente come canale per **condividere dati di vendita con GoCollect** (es. da un negozio/marketplace), non come API di consultazione prezzi per app terze. Testuale dalla pagina: *"Integrate our API with your systems following the documentation guidelines"* nel contesto di "Share Your Collectibles Data". Non è chiaro dalla documentazione pubblica se esista un endpoint di sola lettura (query FMV per titolo/numero) aperto a nuovi richiedenti.
- **Precedente storico**: GoCollect ha fornito in passato un'integrazione di pricing a un partner (CLZ Comic Collector/Comic Connect), con valori "powered by GoCollect" per comics CGC/CBCS graduati, dal 2019. L'accordo è terminato nell'ottobre 2021 e CLZ ha rimosso l'integrazione GoCollect passando a CovrPrice. Fonti: https://clz.com/blog/comic-connect/2019/07/11/new-comic-values-powered-by-gocollect , https://www.collectorz.com/comic/clz-comics/whatsnew/ios/2021/10/29/v6-9-no-more-automatic-comic-values-from-gocollect . Questo indica che l'accesso "API" a scopo di consultazione prezzi per app terze è stato storicamente concesso solo a partner selezionati, non è garantito né duraturo.
- **Copertura editoriale**: la sezione "Price Guides" del sito elenca "Comic Books — Golden, Silver, Bronze, Copper, and Modern Age" più Pokémon, riviste, videogiochi, poster da concerto, MTG. Nessuna menzione di manga o edizioni europee/italiane. https://gocollect.com/data-sharing
- **Autenticazione**: token generato da "Manage Account → API Tokens", **ma funzionante solo dopo approvazione**. Nessun costo per la richiesta di per sé ("a paid subscription is not required for data sharing"), ma un account Pro sblocca funzionalità aggiuntive.
- **Costi (piano consumer, non API)**: Free / Pro $9/mese (o $7.42/mese fatturato annualmente, $89/anno) / Enterprise a prezzo custom. https://gocollect.com/pricing
- **Scala di grading**: FMV (Fair Market Value) per grado, basata su vendite reali di comics graduati/slabbed (CGC/CBCS); i valori grezzi ("raw") risultano meno enfatizzati rispetto ai graduati secondo l'integrazione storica con CLZ ("Slabbed vs Raw" era un campo separato).
- **Variant cover**: il blog di GoCollect tratta le variant come argomento editoriale ("Variant Covers You May Be Overlooking", https://gocollect.com/blog/variant-covers-you-may-be-overlooking/) ma non è documentato se l'API/i dati FMV le trattino come SKU distinti in modo strutturato e interrogabile.
- **Blocchi**: accesso API gated da approvazione manuale, non self-serve; scopo dichiarato dell'API ambiguo (condivisione dati vs. consultazione prezzi); precedente di un partner (CLZ) che ha perso l'accesso quando l'accordo commerciale è terminato.

## 3. CovrPrice (ex GPAnalysis-adjacent, prodotto distinto)

- **API reale**: **nessuna API pubblica self-serve documentata** sul sito ufficiale https://covrprice.com/. Il sito mostra solo un'interfaccia web (ricerca, "CP Content", Marketplace, "Partner Portal").
- **Integrazione nota**: CovrPrice fornisce dati di valore a CLZ (Comic Collector / Comic Connect / CLZ Comics) tramite una partnership dedicata — non un'API pubblica a cui chiunque può registrarsi. Per usarla dentro CLZ serve un abbonamento CovrPrice "Premium" ($6.95/mese, o $60/anno = $5/mese) **oltre** all'abbonamento CLZ attivo. Fonte: https://clz.com/comics/covrprice e https://clz.com/comics/mobile/manual/1/en/topic/covrprice-faq . La presenza di un "Partner Portal" nel menu di covrprice.com suggerisce un canale B2B per integrazioni, ma non è documentato pubblicamente un processo self-serve per sviluppatori terzi.
- **Copertura editoriale**: non specificata per paese; il sito si concentra su fumetti USA mainstream ("Top Hot Comics", "Top Key Comics", "Top Rare Finds", "Top Variants" in home page, https://covrprice.com/). Nessuna menzione di manga o edizioni italiane/europee.
- **Grading e struttura prezzo**: CovrPrice mostra **sia** valori "raw" (non graduati, con grado stimato dal testo dell'annuncio quando disponibile) **sia** valori per comics slabbed/graduati (scala numerica tipo CGC, es. "CGC 9.6"). Il sistema "FMV Value Ribbon" restituisce **un valore per condizione specifica se disponibile**, altrimenti ripiega sul valore per la condizione più comune (non necessariamente un singolo prezzo fisso, ma una logica di fallback per-grado). Fonte: sezione "How to Read the COVRPRICE Value Ribbon", https://covrprice.com/ .
- **Variant cover**: **sì, esplicitamente distinte**. Il sito istruisce i venditori a includere "Comic Title, Issue #, Issue Year, Variant Info (di solito il cognome del copertinista), and Grade info" per far sì che i loro robot associno correttamente le vendite; l'esempio dato è "Captain Marvel #1 (2015) - Hughes Variant - CGC 9.8" — quindi le variant sono trattate come voce distinta nel matching delle vendite. Stessa fonte.
- **Costi**: Premium $6.95/mese o $60/anno (via CLZ) — su covrprice.com direttamente altre fonti secondarie riportano $89.95/anno per il piano standalone, ma questo dato non è stato verificato su una pagina prezzi ufficiale raggiungibile (la pagina piani ha restituito solo l'app-shell senza contenuto prezzi statico nel fetch).
- **Blocchi**: nessuna via di accesso API pubblica documentata; l'unico canale confermato è la partnership con CLZ, quindi per MyComicBrain significherebbe negoziare un accordo diretto con CovrPrice, non una semplice registrazione self-serve.

## 4. GPAnalysis (GPA for CGC Comics)

- **API reale**: **nessuna.** Il sito (https://comics.gpanalysis.com/features e https://comics.gpanalysis.com/) descrive solo un prodotto web/app per consultazione manuale (ricerca, grafici, "My Comics" per tracciare la propria collezione). Nessuna menzione di API, token, o programma sviluppatori in nessuna delle pagine pubbliche consultate.
- **Copertura**: **solo comics CGC-graduati** ("GPA for CGC Comics delivers the information you need to analyse and price CGC graded comics, magazines & pulps" — https://comics.gpanalysis.com/features). Nessun dato per fumetti non graduati (raw), nessuna menzione di edizioni italiane/europee o manga. Copertura dichiarata: "tens of thousands of individual titles and almost 7M transactions" tracciate da oltre 40 piattaforme di vendita dal 2002.
- **Grading**: scala numerica CGC standard (0.5–10.0); i dati sono raggruppati esplicitamente "by grade, label type, variant and pedigree details" (stessa fonte) — quindi **le variant cover sono distinte esplicitamente** insieme a pedigree e label type, e viene fornita una tabella storica per grado, non un singolo prezzo.
- **Costi**: $10.95/mese o $119/anno (https://comics.gpanalysis.com/features, sezione "Pricing").
- **Blocchi**: nessuna via API — è un servizio web-only, quindi non utilizzabile programmaticamente senza scraping (sconsigliato: violerebbe probabilmente i Terms of Use, non verificati in dettaglio in questa ricerca).

## 5. Comics Price Guide (comicspriceguide.com)

- **API reale**: **nessuna**, né pubblica né a pagamento. Una discussione storica sul forum di Comic Vine conferma l'assenza di accesso via XML/web service: https://comicvine.gamespot.com/forums/api-developers-2334/whats-your-collection-worth-556586/
- **Grading scale**: bucket dichiarati sulla guida di grading ufficiale (https://comicspriceguide.com/comic-book-grading): 9.9–10.0, 9.6–9.8, 9.2–9.4, 7.5–9.0, 5.5–7.0, 3.5–5.0, 1.8–3.0, 1.0–1.5, 0.5 — quindi grado numerico raggruppato in fasce, non singolo prezzo per raw/9.8/ecc separatamente come CGC puro.
- **Copertura**: dichiara "oltre 1,2 milioni di fumetti" su "6.745 editori" e include almeno alcuni editori manga (es. pagina dedicata "CPM Manga Comic Book Values", https://comicspriceguide.com/publishers/cpm-manga), ma non è chiaro il livello di copertura per edizioni italiane.
- **Blocchi**: assenza totale di canale programmatico → esclusa come opzione tecnica per l'app, salvo eventuale futura API non ancora annunciata.

## 6. Overstreet Access (Overstreet Comic Book Price Guide)

- **API reale**: **nessuna menzionata.** La pagina "Get Access" (https://www.overstreetaccess.com/get-access/) descrive solo piani di abbonamento consumer (app/web), nessun riferimento a sviluppatori o API.
- **Piani**: Free ($0, solo navigazione) / Bronze ($3/mese, aggiunge informazioni sui prezzi) / Silver ($5/mese, gestione collezione fino a 5.000 numeri) / Gold ($9/mese, numeri illimitati, fino a 5 collezioni). Stessa fonte.
- **Grading**: Overstreet è lo standard storico del settore (dal 1970) basato su fasce di condizione con nomi (Mint, Near Mint, Very Fine, Fine, ecc.) mappate a intervalli numerici — è il riferimento concettuale della scala usata anche da CGC/GoCollect/CovrPrice, ma la pagina consultata non elenca la tabella completa (rimanda a una risorsa "Grading Definitions" separata, non recuperata in questa ricerca).
- **Blocchi**: nessun canale programmatico pubblico → esclusa come opzione tecnica diretta, ma resta il riferimento concettuale/standard di scala condizione più riconosciuto nel settore USA.

## 7. eBay (sold/completed listings via API ufficiale)

- **API reali disponibili**: eBay ha più API distinte, con supporto molto diverso per i dati "sold":
  - **Browse API** (per articoli attivi/in vendita): documentazione ufficiale su developer.ebay.com. Limite di chiamate: **5.000 chiamate/giorno** di default per la maggior parte dei metodi (incl. `getItems`), aumentabile tramite "Application Growth Check". Non fornisce dati storici di vendita/completati.
  - **Finding API** (`findCompletedItems`): **deprecata e non più accessibile** dalle applicazioni dal 15 ottobre 2020; l'intera Finding API (insieme alla Shopping API) è stata **dismessa a febbraio 2025**.
  - **Marketplace Insights API** (unico canale ufficiale per dati di vendite concluse/sold comps): **accesso Limited Release**, riservato a partner pre-approvati con un rapporto commerciale diretto con eBay; **non è possibile richiederlo come sviluppatore indipendente self-serve** — le richieste di accesso standard non vengono accettate.
  - Fonti: https://developer.ebay.com/develop/get-started/api-call-limits , community eBay su deprecazione Finding API (es. https://community.ebay.com/t5/Traditional-APIs-Search/Alert-Finding-API-and-Shopping-API-to-be-decommissioned-in-2025/td-p/34222062 , https://forums.developer.ebay.com/questions/40111/findcompleteditems-api-is-deprecatedfindcompletedi.html), e discussione community su Marketplace Insights (https://community.ebay.com/forum/talk-to-your-fellow-developers-57970/topic/marketplace-insights-api-access-168586/).
- **Copertura**: marketplace generalista, non specifico fumetti; teoricamente include venditori italiani/europei/manga se qualcuno li mette in vendita su eBay, ma senza garanzia di volume o qualità del match per titolo+numero (richiederebbe parsing euristico dei titoli degli annunci).
- **Grading**: nessuna scala di grading strutturata — il "grado" è solo testo libero nel titolo/descrizione dell'annuncio (es. "CGC 9.8"), da estrarre con parsing/regex, non un campo dati strutturato.
- **Variant cover**: nessun supporto strutturato — dipende interamente da come il venditore ha scritto il titolo dell'annuncio.
- **Blocchi**: il dato di reale interesse (prezzi di vendite concluse) è **di fatto irraggiungibile in self-serve** per un'app come MyComicBrain, perché l'unica API che lo fornisce (Marketplace Insights) non accetta richieste standard.

## 8. League of Comic Geeks

- **API reale**: **nessuna API ufficiale.** Esistono solo librerie client non ufficiali reverse-engineered dalla community (Python: https://github.com/pruizlezcano/comicgeeks , Node.js: https://github.com/alistairjcbrown/leagueofcomicgeeks), che confermano esplicitamente l'assenza di un feed/API ufficiale per l'accesso ai dati.
- **Funzionalità di pricing**: il sito offre "Estimated Market Values" dentro la Collezione dell'utente (solo per chi ha un abbonamento Premium), calcolati come media delle vendite recenti per un grado specifico, con un impegno esplicito a non promuovere artificialmente i valori per hype. Fonte: https://intercom.help/comicgeeks/en/articles/9441661-how-are-the-estimated-values-calculated
- **Blocchi**: nessun canale ufficiale programmatico; qualunque integrazione richiederebbe reverse engineering non ufficiale (rischio di rottura senza preavviso, probabile violazione dei Termini di Servizio) → sconsigliato come base per una feature di produzione.

## 9. Comic Book Realm

- **API reale**: **nessuna** menzionata sul sito (https://comicbookrealm.com/) — nessun riferimento ad "API" o "developer" in tutta la home page. Il sito è un price guide/community database consultabile solo via interfaccia web.
- **Blocchi**: assenza di canale programmatico → escluso.

## 10. Key Collector Comics

- **API reale**: **nessuna evidenza pubblica.** Il sito (keycollectorcomics.com) e gli store app (Google Play, App Store) descrivono solo un'app consumer con notifiche push su "chiavi" (key issues) e contenuti curati in abbonamento; nessuna pagina developer/API trovata. Sarebbe necessario contattare direttamente l'azienda (nick@keycollectorcomics.com, indirizzo reperito nei risultati di ricerca) per verificare se esista un canale B2B non pubblicizzato.
- **Blocchi**: nessun self-serve API documentato → escluso salvo contatto diretto.

---

## Tabella comparativa

| Servizio | API self-serve reale | Costo API | Auth | Scala grading | Prezzo singolo o tabella per grado | Variant cover distinte | Copertura non-USA (IT/EU/manga) | Blocco principale |
|---|---|---|---|---|---|---|---|---|
| **PriceCharting** | **Sì**, documentata pubblicamente | $49/mese (piano Legendary) | Token statico (`t=`) | Numerica CGC 0.5–10.0 (12+ bucket) | Tabella completa per grado | Non documentato esplicitamente | No (Marvel/DC/Dark Horse/Dell/Image/Other) | Nessuno tecnico; costo mensile fisso |
| GoCollect | Solo su richiesta/approvazione; scopo API ambiguo (data-sharing vs query) | Richiesta gratuita, ma serve approvazione; Pro $9/mese per funzioni avanzate | Token, attivo solo se approvato | FMV per grado (CGC/CBCS) | Presumibilmente tabella (FMV per grado) | Non chiaro se strutturato nell'API | No | Accesso gated e non garantito; partnership storica (CLZ) terminata dal fornitore |
| CovrPrice | No pubblica; solo partnership B2B (es. CLZ) | $6.95–$60/anno (solo tramite CLZ) | N/D per self-serve | Numerica tipo CGC + raw stimato | Tabella con fallback per grado più comune | **Sì, esplicito** (matching per variant) | No | Nessuna via self-serve documentata |
| GPAnalysis | No | $10.95/mese o $119/anno (solo web) | N/D | Numerica CGC 0.5–10.0 | Tabella storica per grado | **Sì, esplicito** (variant/pedigree/label) | No (solo CGC-graduati) | Nessuna API — solo consultazione web |
| Comics Price Guide | No | N/D | N/D | Bucket (9.9–10.0 … 0.5) | Bucket per fascia | Non verificato | Parziale (alcuni editori manga) | Nessun canale programmatico |
| Overstreet Access | No | $3–$9/mese (consumer) | N/D | Standard di settore (nomi condizione) | N/D (non recuperato) | Non verificato | No | Nessun canale programmatico |
| eBay (Browse API) | Sì, ma solo annunci attivi, non "sold" | Gratis fino a 5.000 chiamate/giorno | OAuth | Nessuna (testo libero) | N/D | No (testo libero) | Sì (marketplace globale) ma senza garanzie di match | Dati "sold" reali richiedono Marketplace Insights, non richiedibile self-serve |
| eBay (Marketplace Insights) | No (limited release, solo partner pre-approvati) | N/D | OAuth con scope ristretti | N/D | N/D | N/D | N/D | Accesso non richiedibile in self-serve |
| League of Comic Geeks | No (solo librerie community non ufficiali) | N/D | N/D | Grado singolo (media vendite recenti) | Singolo valore per grado | Non verificato | No | Nessuna API ufficiale |
| Comic Book Realm | No | — | — | — | — | — | — | Nessun canale programmatico |
| Key Collector Comics | Nessuna evidenza pubblica | — | — | — | — | — | — | Nessuna documentazione developer trovata |

---

## Raccomandazione (input per la decisione umana, non una scelta definitiva)

**PriceCharting è l'unico servizio verificato con un'API self-serve reale, pubblicamente documentata, con autenticazione semplice (token), rate limit chiari e una tabella prezzo-per-grado allineata alla scala numerica CGC/Overstreet** — la stessa famiglia di scala su cui si può mappare in modo relativamente diretto l'enum Condizione a 8 valori dell'app (Mint/Near Mint/Very Fine/Fine/Very Good/Good/Fair/Poor → punti sulla scala 0.5–10.0). Il costo ($49/mese per l'accesso API, piano "Legendary") è significativo per un'app personale/hobbistica e andrebbe confrontato con l'uso reale previsto (quante valutazioni al mese, quanti utenti). Il suo limite principale per un pubblico italiano è la copertura: il catalogo sembra centrato su editori USA mainstream (Marvel, DC, Dark Horse, Dell, Image), senza garanzie per edizioni italiane o manga — probabilmente una parte rilevante della collezione di un utente italiano non troverebbe corrispondenza diretta.

**GoCollect** è la seconda opzione più promettente sulla carta (prodotto specificamente "comics", buona reputazione nel settore, integrazione storica con un tool di catalogazione simile a MyComicBrain), ma la sua API risulta **gated e di scopo non chiaramente confermato per la consultazione prezzi** (sembra pensata soprattutto per la condivisione dati verso GoCollect, non per interrogare FMV da un'app terza) — andrebbe verificato con un contatto diretto/richiesta di accesso prima di contarci come base tecnica.

**CovrPrice e GPAnalysis** offrono i dati più ricchi sul fronte "variant cover distinte" e prezzo-per-grado, ma **nessuno dei due espone un'API pubblica self-serve**: l'unico canale noto (CovrPrice via CLZ) è una partnership B2B negoziata, non una registrazione aperta.

**eBay** non è utilizzabile per il caso d'uso: l'unica API che darebbe accesso a vendite concluse reali (Marketplace Insights) non accetta richieste standard da sviluppatori indipendenti, e la Browse API (self-serve, gratuita) copre solo annunci attivi senza struttura di grading.

Per un'app di un collezionista italiano, budget-conscious, che necessita di prezzo-per-condizione: **nessuna delle opzioni verificate copre bene sia "API self-serve accessibile" sia "copertura edizioni italiane/manga"** — è una tensione reale da portare alle ticket #159 (se e come rendere il provider configurabile) e #160 (mapping condizione + comportamento per fumetti non coperti, che sarà necessario quasi sempre per una collezione italiana indipendentemente dal provider scelto).

Non è stato individuato, tra i candidati verificati, alcun servizio con copertura dedicata a edizioni italiane/europee: questo rafforza l'ipotesi che il requisito "Valore stimato" andrà quasi certamente progettato assumendo che una parte della collezione resti semplicemente non valutabile dalla fonte esterna (comportamento da definire in #160), indipendentemente dal provider scelto.
