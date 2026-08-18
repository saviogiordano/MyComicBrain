# Modello locale specializzato su copertine di fumetti — alternativa a Claude cloud?

Ricerca per issue [#29](https://github.com/saviogiordano/MyComicBrain/issues/29) (figlia di [#27](https://github.com/saviogiordano/MyComicBrain/issues/27) — Mappa, requisito §6.1 OCR).

Contesto: la mappa #27 ha scelto come destinazione un pipeline che invia ogni foto di copertina
("Scansione") a Claude (API multimodale cloud) per estrarre campi strutturati — titolo, numero,
editore, collana, autori, ISBN, barcode, prezzo, codici — più, se ottenibile, la posizione del testo.
L'app è Flutter 100% client-side, nessun backend. Questo ticket verifica se esiste un'alternativa
locale (on-device o self-hosted) di qualità sufficiente prima di impegnare lavoro ingegneristico
sulla direzione cloud.

Metodo: repository ufficiali (GitHub/Hugging Face) dei modelli candidati, pagine pub.dev dei
plugin Flutter, documentazione ufficiale Google ML Kit e Apple Vision framework. Ogni affermazione
è accompagnata dalla fonte.

---

## 1. Modelli/pacchetti specializzati su testo di copertine fumetti (non OCR generico)

Non esiste, nelle fonti consultate, alcun modello o pacchetto pubblico specializzato **specificamente
sulle copertine** di fumetti (titolo/numero/editore in stile grafico, spesso stilizzato). Esistono
invece diversi progetti specializzati su **testo di fumetti/manga in generale** (soprattutto testo
nelle vignette/nuvolette), che sono il candidato più vicino:

### manga-ocr (kha-white)

- OCR end-to-end (Vision Encoder Decoder, Transformers) per **testo giapponese**, ottimizzato per
  manga: gestisce testo verticale/orizzontale, furigana, testo sovrapposto a immagini. Fonte:
  [README GitHub](https://raw.githubusercontent.com/kha-white/manga-ocr/master/README.md),
  [model card Hugging Face](https://huggingface.co/kha-white/manga-ocr-base).
- **Solo giapponese** — non applicabile a copertine in italiano/inglese, che è il caso d'uso di
  questa app. Fonte: README citato sopra ("OCR for Japanese text").
- Peso modello ~400 MB al download. Licenza **Apache 2.0**. Fonte: README GitHub;
  [LICENSE](https://github.com/kha-white/manga-ocr/blob/master/LICENSE).
- Nessuna menzione di deployment mobile/Flutter/on-device nella documentazione ufficiale — è
  pensato per essere eseguito via Python/PyTorch (CPU o GPU). Fonte: README GitHub.
- Limitazioni dichiarate: peggiora su testo lungo, non pensato per scrittura a mano, "tenta sempre
  di riconoscere del testo anche quando non ce n'è" (falsi positivi). Fonte: README GitHub.

### comic-text-detector (dmMaze)

- **Solo detection**, non riconoscimento del contenuto testuale: produce bounding-box, text line e
  maschere di segmentazione, pensato come step di preprocessing per traduzione automatica di
  manga/fumetti (rimozione testo + re-lettering), non per estrarre il testo stesso. Fonte:
  [GitHub dmMaze/comic-text-detector](https://github.com/dmMaze/comic-text-detector).
- Addestrato su ~13.000 immagini: 1/3 Manga109-s, 1/3 Digital Comic Museum, 1/3 sintetiche. Il
  dataset Manga109-s ha licenza che ne limita l'uso a scopi accademici/non commerciali (87 opere
  disponibili anche per uso commerciale a condizioni specifiche) — un vincolo potenzialmente
  rilevante sulla provenienza dei pesi del modello. Fonte:
  [Manga109 project — Terms of Use](https://manga109.github.io/manga109-project-website/en/index.html).
- Architettura: combinazione di detector di manga-image-translator, segmentazione (UNet/DBNet),
  YOLOv5. **Licenza GPL-3.0** (copyleft). Fonte: GitHub repo citato sopra.
- Esiste una conversione **non ufficiale** in formato ONNX di terze parti
  ([mayocream/comic-text-detector-onnx](https://huggingface.co/mayocream/comic-text-detector-onnx),
  licenza Apache 2.0 dichiarata dal converter, non dall'autore originale) — nessuna guida ufficiale
  per l'uso su mobile, solo il formato del file è teoricamente compatibile con ONNX Runtime.

### comic-text-and-bubble-detector (ogkalu)

- **Solo detection** di nuvolette e regioni di testo (classi: `bubble`, `text_bubble`,
  `text_free`), non riconoscimento del contenuto. Fine-tuning di **RT-DETR-v2 r50vd** (42,9M
  parametri) su ~11.000 immagini che coprono manga, webtoon, manhua **e fumetto occidentale**.
  Licenza **Apache 2.0**. Fonte:
  [model card Hugging Face](https://huggingface.co/ogkalu/comic-text-and-bubble-detector).
- Nessuna nota di deployment mobile/on-device nella model card. Fonte: model card citata sopra.

### COMICS Text+ / comics_text_plus (gsoykan et al.)

- L'unico progetto trovato che è un **pipeline end-to-end completo (detection + recognition)**
  esplicitamente addestrato e valutato su **fumetto occidentale** (non manga): detection con
  FCENet fine-tuned, riconoscimento con MASTER fine-tuned, entrambi su dataset custom-annotati
  dagli autori. Fonte: [GitHub gsoykan/comics_text_plus](https://github.com/gsoykan/comics_text_plus),
  [paper arXiv:2212.14674](https://arxiv.org/abs/2212.14674).
- Il paper riporta miglioramenti di "word accuracy" e "normalized edit distance" rispetto al
  dataset di partenza (COMICS) e stato dell'arte su task cloze-style downstream, ma **senza numeri
  di accuratezza assoluti riportati nell'abstract** consultato — servirebbe leggere il paper
  completo per cifre puntuali. Fonte: [abstract arXiv:2212.14674](https://arxiv.org/abs/2212.14674).
- **Licenza non specificata**: il README contiene un placeholder non compilato
  ("This project is licensed under the [NAME HERE] License"), nessun file LICENSE. Questo lo rende
  di fatto **non riutilizzabile legalmente** senza contattare gli autori. Fonte: README GitHub
  citato sopra.
- Richiede **MMOCR 0.6.0** (toolkit PyTorch) per l'inferenza — nessuna nota su deployment
  mobile/edge; pensato per esecuzione desktop/server. Fonte: README GitHub citato sopra.
- I modelli pre-addestrati sono scaricabili solo da link Google Drive, non da un registry
  standard (Hugging Face/pub.dev). Fonte: README GitHub citato sopra.

### ComiQ

- Libreria "ibrida": combina motori OCR tradizionali locali (PaddleOCR, EasyOCR) con un modello
  AI **cloud** (default `gemini-2.5-flash`) per il raggruppamento/classificazione del testo
  rilevato in nuvolette/didascalie. Licenza MIT, progetto piccolo (~30 star, 38 commit). Fonte:
  [GitHub StoneSteel27/ComiQ](https://github.com/StoneSteel27/ComiQ).
- **Richiede comunque una API key di un modello multimodale cloud** per la parte di
  raggruppamento — non è quindi un'alternativa "solo locale" nel senso richiesto da questo ticket;
  reintroduce la stessa dipendenza di rete che si vorrebbe evitare, senza i benefici di qualità di
  un modello frontier come Claude sulla parte di ragionamento. Fonte: README GitHub citato sopra.

**Sintesi punto 1**: nessuno dei progetti trovati è (a) specializzato su copertine di fumetti
(sono tutti pensati per testo nelle vignette/nuvolette all'interno delle pagine, un problema
visivamente diverso dalla singola immagine di copertina), (b) production-ready per l'estrazione di
campi strutturati, (c) impacchettato per l'esecuzione mobile. L'unico che fa riconoscimento
completo del testo su fumetto occidentale (comics_text_plus) non ha una licenza utilizzabile e
richiede un toolkit desktop pesante (MMOCR/PyTorch).

---

## 2. Qualità attesa: OCR generico on-device vs. specializzati vs. Claude cloud

### Google ML Kit Text Recognition v2 (on-device)

- Riconosce testo in script **Cinese, Devanagari, Giapponese, Coreano e Latino** — il Latino copre
  italiano/inglese, rilevante per questa app. Fonte:
  [ML Kit Text Recognition v2](https://developers.google.com/ml-kit/vision/text-recognition/v2).
- Restituisce, per blocco/riga/elemento/simbolo: **bounding box, corner points, informazioni di
  rotazione, confidence score, lingua riconosciuta e testo** — quindi copre la parte "posizione del
  testo" richiesta dal requisito §6.1. Fonte: pagina citata sopra.
- **Non fa alcuna comprensione strutturata dei campi**: restituisce testo grezzo + posizione, non
  "questo è il titolo", "questo è il numero dell'albo", "questo è l'ISBN". La pagina ML Kit cita
  come esempio di uso "automatizzare data-entry per carte di credito, ricevute, biglietti da
  visita" — cioè richiede comunque una logica applicativa a valle (parsing/euristiche/regex) per
  mappare il testo grezzo sui campi del dominio fumetto (titolo, numero, editore, collana, autori).
  Fonte: pagina citata sopra.

### Apple Vision — `VNRecognizeTextRequest` / `VNRecognizedTextObservation` (on-device)

- API nativa iOS/macOS per riconoscimento testo, disponibile da **iOS 13.0+**. Fonte:
  [VNRecognizeTextRequest](https://developer.apple.com/documentation/vision/vnrecognizetextrequest).
- `recognitionLanguages` consente di impostare le lingue attese; `recognitionLevel` sceglie tra
  modalità veloce e accurata (`VNRequestTextRecognitionLevel`). Fonte: pagina citata sopra.
- `VNRecognizedTextObservation` eredita da `VNRectangleObservation` (bounding box) e offre
  `topCandidates(_:)` per le migliori ipotesi di testo con confidence — quindi anche qui posizione
  + testo grezzo, non campi strutturati. Fonte:
  [VNRecognizedTextObservation](https://developer.apple.com/documentation/vision/vnrecognizedtextobservation).
- Come per ML Kit: nessuna comprensione semantica del layout di una copertina fumetto (dove sia il
  titolo vs. il numero vs. il prezzo) — va costruita a mano con euristiche (dimensione carattere,
  posizione, pattern regex per ISBN/numero).

### Claude cloud (riferimento — decisione già presa in #27)

- Comprende il **contesto semantico** dell'immagine: può essere istruito a restituire
  direttamente titolo/numero/editore/collana/autori/ISBN/barcode/prezzo come campi strutturati
  (JSON), non solo testo grezzo, perché ragiona sul layout e sul significato del testo, non solo
  sui suoi pixel. Nessuno dei modelli locali sopra (specializzati o generici) fa questo passo:
  tutti si fermano a "individua/leggi il testo", lasciando il mapping a campi come lavoro
  applicativo separato da scrivere e mantenere.
- Gestisce anche varianti grafiche complesse (font stilizzati di loghi/collane, testo integrato
  nell'illustrazione) meglio di un motore OCR "riga per riga", perché non dipende da un layout
  documentale regolare — è lo stesso motivo per cui i progetti di detection specializzati (comic-
  text-detector, comic-text-and-bubble-detector) esistono: OCR generico da documento fatica sul
  testo di fumetti/manga non allineato in righe regolari. Questo è indirettamente confermato
  dall'esistenza stessa di questi progetti di ricerca dedicati (§1).

**Sintesi punto 2**: per i campi richiesti dal requisito (titolo, numero, editore, collana,
autori, ISBN, barcode, prezzo, codici) **nessuna opzione locale — né generica né specializzata —
offre estrazione di campi strutturati "out of the box"**. ML Kit/Vision offrono testo+posizione di
buona qualità per script latino ma richiedono di scrivere e mantenere una logica di parsing
euristica separata per interpretare quel testo; i modelli comic-specific o si fermano alla sola
detection (nessun testo estratto) o non hanno una via di deployment mobile/licenza utilizzabile.

---

## 3. Dimensioni modello, requisiti hardware, compatibilità Flutter

| Opzione | Plugin Flutter esistente? | Note integrazione |
|---|---|---|
| Google ML Kit Text Recognition v2 | Sì — [`google_mlkit_text_recognition`](https://pub.dev/packages/google_mlkit_text_recognition), v0.17.1, licenza MIT, iOS ≥15.5 / Android minSdk 21 | Bridge nativo pronto all'uso, nessuna integrazione custom richiesta |
| Google ML Kit Barcode Scanning (EAN-13/ISBN) | Sì — famiglia `google_mlkit_*`, stesso ecosistema | Formati inclusi: EAN-13, UPC-A/E, Code 128, ecc.; **parsing automatico di ISBN da barcode 2D/lineare**; interamente on-device, nessuna rete richiesta. Fonte: [ML Kit Barcode Scanning](https://developers.google.com/ml-kit/vision/barcode-scanning) |
| Apple Vision Text Recognition | Sì — es. [`apple_vision_recognize_text`](https://pub.dev/packages/apple_vision_recognize_text), [`vision_text_recognition`](https://pub.dev/packages/vision_text_recognition) (iOS via Vision + Android via ML Kit nello stesso plugin) | Plugin di terze parti (non first-party Apple/Flutter), da valutare per maturità/manutenzione se scelti |
| manga-ocr | No | Richiede runtime Python/PyTorch; nessun export ufficiale mobile (TFLite/ONNX/CoreML) nella documentazione consultata |
| comic-text-detector | No (solo conversione ONNX non ufficiale di terzi) | Servirebbe integrazione custom via [`onnxruntime_flutter`](https://github.com/gtbluesky/onnxruntime_flutter)/[`flutter_onnxruntime`](https://pub.dev/packages/flutter_onnxruntime) o `tflite_flutter`, con conversione/validazione a proprio carico; produce solo bounding box, non testo |
| comic-text-and-bubble-detector | No | Stesso discorso: nessun export mobile ufficiale, solo detection (nessun testo) |
| comics_text_plus | No | Richiede MMOCR/PyTorch; nessuna nota di conversione mobile nella documentazione |

**Sintesi punto 3**: per OCR generico (ML Kit, Vision) esistono plugin Flutter maturi, pronti
all'uso, che girano interamente on-device senza lavoro di integrazione nativa. Per **qualunque**
modello comic-specific trovato, non esiste un plugin Flutter: servirebbe conversione del modello
(spesso non ufficiale), integrazione nativa manuale via ONNX Runtime o TFLite, e in più — anche
riuscendoci — il risultato sarebbe solo la detection delle aree di testo (o, nel solo caso di
comics_text_plus, testo letto ma senza licenza chiara), non l'estrazione dei campi del dominio.

---

## 4. Licenze — riepilogo

| Progetto | Licenza | Fonte |
|---|---|---|
| manga-ocr | Apache 2.0 | [LICENSE](https://github.com/kha-white/manga-ocr/blob/master/LICENSE) |
| comic-text-detector (dmMaze) | GPL-3.0 (copyleft); pesi derivati in parte da Manga109-s, che ha restrizioni d'uso accademico/non commerciale | [GitHub repo](https://github.com/dmMaze/comic-text-detector), [Manga109 Terms of Use](https://manga109.github.io/manga109-project-website/en/index.html) |
| comic-text-and-bubble-detector (ogkalu) | Apache 2.0 | [model card HF](https://huggingface.co/ogkalu/comic-text-and-bubble-detector) |
| comics_text_plus | **Non specificata** (placeholder nel README non compilato, nessun file LICENSE) | [README GitHub](https://github.com/gsoykan/comics_text_plus) |
| ComiQ | MIT (ma richiede comunque API key di un modello cloud) | [GitHub repo](https://github.com/StoneSteel27/ComiQ) |
| google_mlkit_text_recognition (plugin Flutter) | MIT | pagina pub.dev del pacchetto |
| Google ML Kit (SDK nativo sottostante) | Governato dai termini Google, non un progetto open-source separato | [ML Kit Text Recognition v2](https://developers.google.com/ml-kit/vision/text-recognition/v2) (contenuti CC BY 4.0, codice di esempio Apache 2.0) |
| Apple Vision framework | Parte dell'SDK iOS/macOS, governato dal Apple Developer Program License Agreement, non un pacchetto open-source | [documentazione Apple](https://developer.apple.com/documentation/vision/vnrecognizetextrequest) |

---

## 5. Costo/beneficio vs. Claude cloud (default già scelto in #27)

**A favore del locale (ML Kit/Vision generici, unica opzione realmente disponibile)**:
- Nessuna chiamata di rete, nessun costo per immagine, nessuna dipendenza da una chiave API
  embeddata lato client (punto debole già annotato in #27: "Chiave API incorporata come build-time
  secret lato client").
- Plugin Flutter maturi e pronti, zero lavoro di integrazione nativa custom.
- Ottimo per il barcode/ISBN specificamente: ML Kit Barcode Scanning legge EAN-13 e fa parsing
  ISBN nativamente, on-device, con qualità presumibilmente allo stesso livello o superiore a
  quanto Claude potrebbe leggere da una foto di barcode (un barcode è un formato machine-readable
  progettato per essere decodificato algoritmicamente, non un caso dove un modello linguistico
  multimodale ha un vantaggio).

**Contro (ciò che manca rispetto a Claude cloud)**:
- **Nessuna opzione locale — generica o specializzata — estrae campi strutturati.** Titolo,
  numero, editore, collana, autori, ISBN (da testo, non da barcode), prezzo andrebbero ricostruiti
  da testo grezzo + bounding box via euristiche scritte e mantenute a mano (dimensione font,
  posizione nell'immagine, regex) — lavoro ingegneristico non banale, fragile su layout di
  copertina molto variabili (ogni editore/collana ha un proprio design), e da re-tarare per ogni
  caso limite incontrato in una collezione reale.
- **Nessun modello specializzato su testo di copertine di fumetti esiste** con packaging
  utilizzabile: i progetti trovati sono tutti orientati al testo nelle vignette (non alla
  copertina), quasi tutti solo detection (non lettura del testo), l'unico che legge anche il testo
  su fumetto occidentale (comics_text_plus) non ha una licenza utilizzabile ed è legato a un
  toolkit desktop pesante senza percorso mobile.
- Per manga-ocr, l'unico OCR specializzato "manga" maturo e ben mantenuto, il vincolo di lingua
  (solo giapponese) lo esclude comunque per un'app di catalogazione orientata a fumetti in
  italiano/inglese.

### Raccomandazione

**Confermare la decisione cloud/Claude presa in #27 per l'estrazione dei campi strutturati e la
posizione del testo.** Non emerge, dalle fonti primarie consultate, un'alternativa locale
chiaramente migliore o anche solo comparabile: l'OCR generico on-device (ML Kit/Vision) è l'unica
opzione locale realmente disponibile e pronta per Flutter, ma si ferma a testo grezzo + posizione,
lasciando l'intero lavoro di comprensione/struttura a carico dell'app; i modelli specializzati su
fumetti trovati non sono production-ready per questo caso d'uso (mobile, copertine, campi
strutturati) per ragioni di scope (vignette non copertine), copertura (detection senza
riconoscimento, o solo giapponese) o licenza (comics_text_plus).

**Unica integrazione locale che vale la pena considerare fin da subito, indipendentemente da
questa decisione**: usare **ML Kit Barcode Scanning on-device** (via `google_mlkit_barcode_scanning`
o pacchetto equivalente) per leggere il barcode/ISBN quando visibile, come passo local e gratuito
prima/in parallelo alla chiamata a Claude — riduce dipendenza dal cloud solo per quel campo
specifico, senza cambiare l'architettura decisa per gli altri campi.

---

## Riepilogo per chi legge questa ricerca

1. Nessun modello specializzato su **copertine** di fumetti esiste in forma pubblica e
   production-ready; i progetti trovati riguardano testo nelle **vignette/nuvolette** interne alle
   pagine, non le copertine.
2. Dei progetti "comic text", la maggior parte fa solo **detection** (aree di testo, non
   contenuto): `comic-text-detector` (GPL-3.0, pesi legati a dataset con restrizioni d'uso) e
   `comic-text-and-bubble-detector` (Apache 2.0). L'unico con riconoscimento completo su fumetto
   occidentale, `comics_text_plus`, **non ha una licenza dichiarata** ed è legato a un toolkit
   desktop (MMOCR/PyTorch) senza percorso mobile.
3. `manga-ocr` è maturo e ben mantenuto (Apache 2.0) ma **solo per giapponese**.
4. Per nessuna di queste opzioni esiste un plugin Flutter — servirebbe integrazione nativa custom
   via ONNX Runtime/TFLite, spesso partendo da conversioni non ufficiali di terzi.
5. L'OCR generico on-device (Google ML Kit Text Recognition v2, Apple Vision
   `VNRecognizeTextRequest`) **ha** plugin Flutter maturi, gira interamente on-device, e restituisce
   testo + posizione di buona qualità per script latino — ma **nessuna comprensione dei campi del
   dominio** (titolo vs. numero vs. editore, ecc.), che andrebbe costruita a mano.
6. Il barcode scanning ML Kit (EAN-13, parsing ISBN) è invece un'opzione locale solida e già
   pronta per il campo ISBN/barcode specificamente.
7. **Raccomandazione**: mantenere Claude cloud come da decisione in #27 per l'estrazione dei campi
   strutturati; valutare separatamente l'aggiunta di ML Kit Barcode Scanning on-device come
   arricchimento mirato solo per barcode/ISBN.
