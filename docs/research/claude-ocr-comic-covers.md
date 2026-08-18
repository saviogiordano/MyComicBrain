# Ricerca — Claude API multimodale per l'estrazione OCR da copertine di fumetti

**Ticket:** [#28](https://github.com/saviogiordano/MyComicBrain/issues/28) (child di [#27](https://github.com/saviogiordano/MyComicBrain/issues/27))
**Requisito di riferimento:** `docs/requisiti.md` §6.1 OCR
**Data:** 2026-08-18
**Metodo:** ricerca contro fonti primarie Anthropic (docs.anthropic.com / platform.claude.com) e pub.dev. Nessuna fonte terza (blog, tutorial) citata come base fattuale.

---

## Sintesi

Claude (via Messages API multimodale) può estrarre i campi richiesti da una foto di copertina fumetto restituendo **JSON strutturato garantito** tramite `output_config.format` (structured outputs) o tool use con `strict: true`. Può anche restituire **coordinate in pixel** per elementi di testo se richiesto esplicitamente nel prompt, ma queste sono dichiarate dalla documentazione ufficiale come *approssimate* ("Claude's spatial reasoning has limits") e da verificare visivamente prima di un uso a scala — non c'è nella documentazione un confronto quantitativo diretto con un motore OCR dedicato come Google Cloud Vision. Il costo per immagine è nell'ordine di **pochi millesimi/centesimi di dollaro** per scansione con Claude Sonnet 5, ben entro i rate limit anche del tier più basso per un batch di decine/centinaia di scansioni consecutive. **Non esiste un SDK Dart/Flutter ufficiale Anthropic** — solo un pacchetto community su pub.dev; per l'app 100% client-side servirebbe quindi un client HTTP generico (`http`/`dio`) verso l'endpoint REST `POST /v1/messages`.

---

## 1. Output strutturato (JSON) per i campi richiesti

**Approccio raccomandato: `output_config.format` con JSON Schema (structured outputs)**, non tool use "improvvisato" con prompt libero.

> "JSON outputs control Claude's response format, ensuring Claude returns valid JSON matching your schema."
> "Structured outputs guarantee schema-compliant responses through constrained decoding: Always valid — no more `JSON.parse()` errors; Type safe — guaranteed field types and required fields; Reliable — no retries needed for schema violations."

Fonte: [Structured Outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)

Per l'estrazione da immagini, la stessa pagina indica esplicitamente l'uso di JSON outputs quando si deve "Extract data from images or text". Il flusso pratico per la copertina di un fumetto è:

```python
response = client.messages.create(
    model="claude-sonnet-5",
    max_tokens=1024,
    messages=[{
        "role": "user",
        "content": [
            {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": IMG_B64}},
            {"type": "text", "text": "Estrai i dati da questa copertina di fumetto."}
        ]
    }],
    output_config={
        "format": {
            "type": "json_schema",
            "schema": {
                "type": "object",
                "properties": {
                    "titolo": {"type": ["string", "null"]},
                    "numero_albo": {"type": ["string", "null"]},
                    "editore": {"type": ["string", "null"]},
                    "collana": {"type": ["string", "null"]},
                    "autori": {"type": "array", "items": {"type": "string"}},
                    "isbn": {"type": ["string", "null"]},
                    "barcode": {"type": ["string", "null"]},
                    "prezzo": {"type": ["string", "null"]},
                    "codici_identificativi": {"type": "array", "items": {"type": "string"}}
                },
                "required": ["titolo", "numero_albo", "editore", "collana", "autori",
                             "isbn", "barcode", "prezzo", "codici_identificativi"],
                "additionalProperties": False
            }
        }
    }
)
```

Nota tecnica sulle limitazioni dello schema JSON supportato (rilevante nel disegnare lo schema Drift/di richiesta): sono supportati tipi base (incluso `null`), `enum`, `const`, `anyOf`/`allOf`, formati stringa (`date-time`, `email`, `uri`, ecc.) e `additionalProperties: false` (obbligatorio su ogni oggetto). **Non** sono supportati schemi ricorsivi, vincoli numerici (`minimum`/`maximum`), vincoli di lunghezza stringa (`minLength`/`maxLength`), `$ref` esterni. Fonte: [Structured Outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs).

**Alternativa: tool use con `strict: true`.** Utile se in futuro l'estrazione viene incorporata in un flusso agentico con altri tool; per il caso d'uso descritto in #27 (chiamata singola per Scansione, nessun tool aggiuntivo) `output_config.format` è la soluzione più diretta e quella esplicitamente raccomandata dalla documentazione per "controllare il formato di risposta".

**Nota su latenza:** la prima richiesta con uno schema nuovo comporta un costo di compilazione una tantum ("grammar compiles"); gli schemi compilati restano in cache 24h dall'ultimo uso, quindi le richieste successive con lo stesso schema sono più veloci. Fonte: [Structured Outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs).

---

## 2. Posizione del testo nell'immagine (bounding box / coordinate)

**Sì, Claude può restituire coordinate in pixel per elementi individuati in un'immagine**, inclusi elementi testuali, se richiesto esplicitamente. Esiste una pagina dedicata della documentazione ufficiale: [Coordinates and bounding boxes](https://platform.claude.com/docs/en/build-with-claude/vision-coordinates).

Punti chiave, citati testualmente:

- **Formato da richiedere:** "Claude works best with absolute pixel coordinates. Ask for them explicitly in your prompt. For example: *'Return the bounding box of each table as `[x1, y1, x2, y2]` (top-left and bottom-right corners) in pixel coordinates.'* Claude does not work well when you ask for normalized coordinates... Always ask for pixel coordinates and normalize in your own code if you need to."
- **Combinabile con structured outputs:** "To get coordinates as machine-readable JSON instead of prose, define a schema with structured outputs, for example an object with an `[x1, y1, x2, y2]` array per detected element." → Per il caso della copertina fumetto, si può quindi estendere lo schema JSON del punto 1 con un campo opzionale `posizione: [x1, y1, x2, y2]` per ciascun elemento testuale rilevante.
- **Origine e sistema di coordinate:** origine `(0,0)` in alto a sinistra, x verso destra, y verso il basso — convenzione immagine standard.
- **Le coordinate si riferiscono all'immagine ridimensionata da Claude**, non necessariamente all'immagine originale inviata. Claude ridimensiona le immagini per rientrare nei limiti nativi del modello (edge limit + token-visivi limit) e poi applica un padding tecnico (senza contenuto) fino al multiplo di 28px successivo. Per allineare le coordinate all'immagine originale bisogna o (a) ridimensionare l'immagine lato client *prima* dell'invio secondo la formula documentata, oppure (b) ricalcolare le dimensioni con cui Claude ha "visto" l'immagine e fare un rescale lineare delle coordinate restituite. Fonte: [Coordinates and bounding boxes — How Claude resizes and pads images](https://platform.claude.com/docs/en/build-with-claude/vision-coordinates#how-claude-resizes-and-pads-images).

### Affidabilità (rispetto a un OCR dedicato)

La documentazione **non fornisce un confronto quantitativo diretto** con un motore OCR dedicato (es. Google Cloud Vision) — questo è un dato che la ricerca contro fonti primarie Anthropic non può confermare o smentire con un numero. Quello che la documentazione dichiara esplicitamente è una **cautela strutturale**:

> "**Spatial reasoning:** Claude's coordinate and localization outputs are approximate. Follow the guidance in [Coordinates and bounding boxes] and verify outputs before relying on them."
> "Claude's spatial reasoning has limits... Coordinate accuracy is best when you state the expected coordinate format in your prompt and spot-check results visually before processing at scale. Small elements lose precision when an image is downscaled: for fine targets, crop the region of interest and send the crop..., or use a high-resolution-tier model."
> "**Accuracy:** Claude might hallucinate or make mistakes when interpreting low-quality, rotated, or very small images under 200 pixels."

Fonti: [Vision — Limitations](https://platform.claude.com/docs/en/build-with-claude/vision#limitations), [Coordinates and bounding boxes](https://platform.claude.com/docs/en/build-with-claude/vision-coordinates).

**Interpretazione per questo progetto (sintesi mia, non citazione diretta):** un motore OCR dedicato come Google Cloud Vision produce bounding box pixel-perfetti a livello di singolo carattere/parola, derivati da un algoritmo di rilevamento testo classico. Claude è un modello linguistico multimodale che *stima* le coordinate come parte della generazione testuale — la documentazione stessa raccomanda di trattarle come stime da verificare, non come output geometrico affidabile a livello pixel. Per una copertina di fumetto (testo di dimensioni medio-grandi come titolo/numero, ma anche testo piccolo come barcode/prezzo), la precisione a livello di bounding box preciso rischia di essere insufficiente per il barcode/ISBN in particolare (spesso <10-15px di altezza dopo il resize a 1568-2576px di lato lungo).

### Migliore approssimazione realistica

Data la cautela documentata, l'approccio più robusto per il requisito §6.1 ("distinguere gli elementi più importanti") è probabilmente una **via ibrida**, coerente con quanto raccomandato dalla documentazione stessa:

1. **Posizione qualitativa/relativa** (es. enum `"alto" | "alto-sinistra" | "alto-destra" | "centro" | "basso" | "basso-sinistra" | "basso-destra"`) come campo obbligatorio nello schema JSON per ogni elemento — più affidabile di coordinate pixel esatte, perché richiede al modello un giudizio più grossolano e verificabile.
2. **Bounding box in pixel come campo opzionale/best-effort**, da trattare come stima approssimativa da non usare per crop/ritaglio automatico senza verifica.
3. Se in futuro serve precisione a livello pixel (es. per un crop automatico del barcode da passare a un decoder dedicato), la documentazione suggerisce esplicitamente di ritagliare/isolare la regione di interesse e inviarla come immagine separata, oppure usare un modello di livello "high-resolution tier" (Claude 4.7 e successivi, incluso Sonnet 5/Opus 5 — vedi §3) per aumentare la risoluzione nativa vista dal modello.

---

## 3. Costo stimato per immagine e rate limit per batch

### Modello consigliato

Per un'estrazione di testo/campi strutturati da un'immagine — compito che beneficia di lettura accurata di testo piccolo (ISBN, barcode, prezzo) ma non richiede ragionamento agentico complesso — **Claude Sonnet 5** (`claude-sonnet-5`) è il candidato di default più bilanciato: è nel tier "high-resolution" (immagini fino a 2576px di lato lungo / 4784 token visivi, contro i 1568px/1568 token dello standard tier), a un prezzo intermedio. Claude Haiku 4.5 è un'alternativa più economica ma resta nello *standard tier* di risoluzione. Fonte: [Vision — Resolution and token cost](https://platform.claude.com/docs/en/build-with-claude/vision#evaluate-image-size). **Questa è un'osservazione di ricerca, non una decisione presa qui** — la scelta finale del modello resta al ticket collegato, come indicato in #27.

### Prezzi correnti (per milione di token, dalla pagina Models Overview)

| Modello | Input | Output | Tier risoluzione immagine |
|---|---|---|---|
| Claude Haiku 4.5 | $1 / MTok | $5 / MTok | Standard (max 1568px, 1568 token visivi) |
| Claude Sonnet 5 | $2 / MTok | $10 / MTok | High-resolution (max 2576px, 4784 token visivi) |
| Claude Opus 5 | $5 / MTok | $25 / MTok | High-resolution (max 2576px, 4784 token visivi) |

Fonte: [Models overview](https://platform.claude.com/docs/en/about-claude/models/overview) (tabella "Latest models comparison").

### Costo per immagine — formula e stime

Claude conta le immagini in "token visivi": un token per ogni blocco 28×28 px, cioè `⌈width/28⌉ × ⌈height/28⌉`. La pagina Vision fornisce esempi calcolati direttamente:

> "At Claude Haiku 4.5's $1 USD per million input tokens (standard tier), the 1000×1000 image costs about $1.30 USD per thousand images. At Claude Opus 5's $5 USD per million (high-resolution tier), the same image costs about $6.48 USD per thousand and the 4K image about $23.92 USD per thousand."

Fonte: [Vision — Resolution and token cost](https://platform.claude.com/docs/en/build-with-claude/vision#evaluate-image-size).

Tabella dei token visivi per alcune dimensioni tipiche (dalla stessa pagina):

| Dimensione immagine | Standard tier — token | High-res tier — token |
|---|---|---|
| 1000×1000 px | 1296 | 1296 |
| 1092×1092 px | 1521 | 1521 |
| 1920×1080 px | 1560 (ridimensionata) | 2691 |
| 2000×1500 px | 1564 (ridimensionata) | 3888 |
| 3840×2160 px | 1560 (ridimensionata) | 4784 (ridimensionata) |

Una foto di copertina fumetto scattata con smartphone e poi ridimensionata lato client (come raccomandato dalla documentazione per allineare le coordinate — vedi §2) rientrerebbe verosimilmente in un intervallo di **~1300–3900 token visivi** su Sonnet 5 (high-res tier), a seconda della risoluzione scelta per lo scatto/compressione.

**Stima indicativa per scansione completa (immagine + prompt/schema + output JSON), su Sonnet 5:**

- Input: ~1500–4000 token (immagine) + ~200–500 token (istruzioni + schema JSON) ≈ 2000–4500 token → $0.004–$0.009
- Output: JSON con 9 campi richiesti, tipicamente ~150–400 token → $0.0015–$0.004
- **Totale stimato: ~$0.006–$0.013 per copertina scansionata** (meno di 2 centesimi), scalabile linearmente col numero di scansioni in un batch.

Questa è una stima derivata dalla formula e dagli esempi ufficiali sopra citati, non una misura empirica — va validata con un test reale prima di dimensionare i costi in produzione.

### Rate limit per un batch di N scansioni consecutive

Anche al tier più basso ("Start", il tier di ingresso per organizzazioni nuove), i limiti per Sonnet 5 sono ampiamente sufficienti per un batch di scansioni personali (decine/centinaia di fumetti in una sessione):

| Tier | RPM (Sonnet 5) | ITPM (Sonnet 5) | OTPM (Sonnet 5) |
|---|---|---|---|
| Start | 1.000 | 2.000.000 | 400.000 |
| Build | 5.000 | 5.000.000 | 1.000.000 |

Fonte: [Rate limits](https://platform.claude.com/docs/en/api/rate-limits) (tabelle "Start tier" / "Build tier").

Con una stima di ~2.000–4.500 token di input per scansione, il limite ITPM del tier Start (2.000.000 token/minuto) permetterebbe teoricamente **centinaia di scansioni al minuto** solo per il vincolo sui token — il collo di bottiglia pratico per un batch a fine sessione di scansione sarebbe più probabilmente il limite RPM (1.000 richieste/minuto sul tier Start) o semplicemente la latenza sequenziale delle chiamate, non i rate limit stessi. **Nota importante:** il rate limit di Sonnet 5 è *separato* da quello di Sonnet 4.x — non condivide il "bucket" combinato di modelli precedenti. Fonte: [Rate limits](https://platform.claude.com/docs/en/api/rate-limits), nota a piè di tabella.

Nota: le organizzazioni nuove o con storico d'uso limitato possono partire su un "Evaluation tier" con limiti inferiori a quelli standard del tier Start, che si alzano automaticamente con l'uso. Fonte: [Rate limits — About rate limits](https://platform.claude.com/docs/en/api/rate-limits#about-rate-limits).

---

## 4. Formato di risposta quando un campo non viene trovato o l'immagine è di bassa qualità

**Non esiste un segnale API dedicato "campo non trovato"** — questo è un aspetto di *design dello schema e del prompt*, non una funzionalità documentata a parte. Punti rilevanti dalle fonti primarie:

- Lo schema JSON supportato da structured outputs include il tipo `null` tra i tipi base supportati (vedi §1) — questo permette di dichiarare esplicitamente nello schema campi come `"type": ["string", "null"]`, così che il modello possa restituire `null` invece di inventare un valore quando non trova un'informazione nell'immagine. Questa è una raccomandazione di design (mia, basata sulle capacità documentate dello schema), non un comportamento automatico garantito dalla piattaforma.
- Sul rischio di dati inventati in caso di immagine di bassa qualità, la documentazione è esplicita:

  > "**Accuracy:** Claude might hallucinate or make mistakes when interpreting low-quality, rotated, or very small images under 200 pixels."
  > "**Image clarity:** Ensure images are clear and not too blurry or pixelated. **Text:** If the image contains important text, make sure it's legible and not too small."
  > "Always carefully review and verify Claude's image interpretations, especially for high-stakes use cases. Do not use Claude for tasks requiring perfect precision or sensitive image analysis without human oversight."

  Fonti: [Vision — Limitations](https://platform.claude.com/docs/en/build-with-claude/vision#limitations), [Vision — Image quality guidance](https://platform.claude.com/docs/en/build-with-claude/vision#image-quality-guidance).

**Implicazione pratica per lo schema Drift/di richiesta (ticket collegato):** dato che l'app non prevede retry automatico né (in questa mappa) una UI di revisione, e dato che Claude può restituire `null`/valori vuoti per campi non trovati ma può anche — su immagini di bassa qualità — produrre dati errati senza segnalarlo esplicitamente come "incerto", è opportuno che lo schema JSON richiesto includa, oltre ai campi elencati nel requisito, un modo per il modello di segnalare esplicitamente l'incertezza (es. un campo aggiuntivo non richiesto dal requisito ma utile in futuro, tipo `note_qualita: string | null`), così da poter distinguere in fase di persistenza tra "campo assente sulla copertina" e "immagine illeggibile". Questa non è un requisito del ticket ma un'osservazione di ricerca da tenere presente per §6.3 (revisione), fuori scope qui.

---

## 5. SDK Dart/Flutter — verifica su pub.dev

**Non esiste un SDK Dart ufficiale pubblicato da Anthropic.** Anthropic pubblica SDK ufficiali per Python, TypeScript, Java, Go, Ruby, C#, PHP — Dart non è tra questi (fonte: elenco SDK ufficiali su [platform.claude.com](https://platform.claude.com), verificato indirettamente tramite l'assenza di un pacchetto Anthropic-pubblicato su pub.dev).

Verifica diretta su pub.dev (ricerca "anthropic"):

- **`anthropic_sdk_dart`** (v7.0.0) — il pacchetto più popolare correlato, pubblicato dal publisher verificato `davidmiguel.com`. La pagina del pacchetto dichiara esplicitamente: *"This is a community-maintained package and is not affiliated with or endorsed by Anthropic."* Aggiornato di recente (16 giorni fa al momento della ricerca), 17 like, 160 pub points, ~14.7k download.
- Altri pacchetti trovati (`anthropic_dart`, `langchain_anthropic`, `llm_dart`, `ai_broker`, ecc.) sono anch'essi wrapper di terze parti, alcuni multi-provider, nessuno ufficiale.

Fonte: [pub.dev — ricerca "anthropic"](https://pub.dev/packages?q=anthropic), [pub.dev/packages/anthropic_sdk_dart](https://pub.dev/packages/anthropic_sdk_dart).

**Conseguenza per l'implementazione (osservazione, non decisione):** poiché l'app MyComicBrain è "100% client-side: nessun backend, nessuna libreria HTTP ancora in dipendenza" (per come descritto in #27), la pipeline OCR dovrà scegliere tra (a) adottare il pacchetto community `anthropic_sdk_dart` come dipendenza, accettando che non è mantenuto né supportato da Anthropic, oppure (b) chiamare direttamente l'endpoint REST `POST https://api.anthropic.com/v1/messages` con un client HTTP generico già comune in Flutter (es. i pacchetti `http` o `dio`), costruendo a mano il corpo della richiesta (immagine base64 + `output_config.format` come descritto in §1) e i relativi header (`x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`). Questa seconda via evita di introdurre una dipendenza non ufficiale ma richiede di mantenere manualmente la conformità al formato dell'API. La scelta tra le due resta al ticket/decisione di design collegato.

---

## Fonti primarie citate

- [Vision](https://platform.claude.com/docs/en/build-with-claude/vision) — invio immagini, limiti, costo token, qualità immagine, limitazioni
- [Coordinates and bounding boxes](https://platform.claude.com/docs/en/build-with-claude/vision-coordinates) — formato coordinate, resize/padding, affidabilità
- [Structured Outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs) — `output_config.format`, JSON Schema, tool use `strict: true`
- [Models overview](https://platform.claude.com/docs/en/about-claude/models/overview) — modelli correnti, prezzi, tier di risoluzione
- [Rate limits](https://platform.claude.com/docs/en/api/rate-limits) — RPM/ITPM/OTPM per tier e per modello
- [pub.dev — ricerca "anthropic"](https://pub.dev/packages?q=anthropic) e [pub.dev/packages/anthropic_sdk_dart](https://pub.dev/packages/anthropic_sdk_dart) — verifica assenza SDK Dart ufficiale
