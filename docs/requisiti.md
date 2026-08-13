# Requisiti funzionali e tecnici — App Catalogo Personale Fumetti

## 1. Obiettivo del prodotto

Realizzare un'applicazione mobile/web per consentire a un collezionista di:

- catalogare la propria collezione di fumetti;
- acquisire rapidamente un fumetto tramite fotografia della copertina;
- utilizzare l'AI per riconoscere titolo, serie, numero e altri elementi identificativi;
- recuperare automaticamente i metadati da fonti esterne;
- verificare e correggere i dati prima del salvataggio;
- organizzare, filtrare e ricercare la propria collezione;
- tenere traccia delle copie fisicamente possedute;
- individuare duplicati e numeri mancanti;
- gestire informazioni personali come stato di conservazione, posizione e prezzo di acquisto.

L'obiettivo principale è rendere l'inserimento di un nuovo fumetto un'operazione di pochi secondi.

---

# 2. Utente target

## Utente principale

Collezionista privato di fumetti, manga, graphic novel e albi.

L'utente può possedere:

- singoli albi;
- serie complete;
- serie incomplete;
- ristampe;
- variant cover;
- edizioni italiane e straniere;
- copie multiple dello stesso albo;
- fumetti acquistati nuovi o usati.

---

# 3. User journey principale

Il flusso principale deve essere:

**Fotografa → Riconosci → Cerca → Verifica → Salva**

### Esempio

1. L'utente apre "Aggiungi fumetto".
2. Seleziona "Scansiona cover".
3. Inquadra la copertina.
4. L'app acquisisce la fotografia.
5. L'AI analizza l'immagine.
6. Vengono estratti:
   - titolo;
   - numero albo;
   - editore;
   - eventuale autore;
   - personaggi;
   - eventuale ISBN/barcode;
   - altri testi presenti sulla cover.
7. L'app esegue una ricerca sui database disponibili.
8. Presenta i possibili risultati ordinati per probabilità.
9. L'utente seleziona il risultato corretto.
10. L'app mostra una schermata di conferma.
11. L'utente aggiunge eventuali dati personali.
12. Il fumetto viene salvato nella collezione.

---

# 4. Funzionalità principali

## 4.1 Dashboard

La home deve mostrare:

- numero totale di fumetti;
- numero di serie;
- numero di fumetti aggiunti recentemente;
- eventuali duplicati;
- serie incomplete;
- ultimi fumetti scansionati;
- statistiche della collezione;
- valore stimato, se disponibile;
- stato delle scansioni in sospeso.

Esempio:

> La tua collezione  
> 1.248 fumetti  
> 87 serie  
> 14 serie complete  
> 23 duplicati  
> 37 numeri mancanti

---

# 5. Catalogazione tramite AI

## 5.1 Acquisizione della cover

L'app deve permettere di:

- scattare una fotografia;
- selezionare una foto dalla galleria;
- acquisire più cover consecutivamente;
- utilizzare la fotocamera in modalità scanner.

L'interfaccia deve fornire una guida per:

- allineamento della cover;
- distanza corretta;
- illuminazione;
- messa a fuoco;
- riduzione dei riflessi.

### Miglioramento automatico

Prima dell'analisi l'app dovrebbe poter:

- ritagliare automaticamente la cover;
- correggere prospettiva;
- correggere luminosità;
- aumentare contrasto;
- ridurre riflessi;
- ruotare l'immagine.

---

# 6. Analisi AI della copertina

Il motore AI deve analizzare l'immagine per individuare gli elementi utili alla catalogazione.

## 6.1 OCR

L'OCR deve cercare:

- titolo;
- numero dell'albo;
- editore;
- nome della collana;
- autori;
- ISBN;
- barcode;
- prezzo;
- eventuali codici identificativi.

La tecnologia OCR dovrebbe restituire anche la posizione del testo nell'immagine, così da poter distinguere gli elementi più importanti.

## 6.2 Computer vision

L'AI dovrebbe cercare di riconoscere:

- personaggi;
- logo dell'editore;
- logo della serie;
- stile/copertina;
- elementi visivi caratteristici;
- eventuale barcode.

## 6.3 Identificazione del fumetto

Il sistema deve combinare:

**immagine + OCR + barcode + database + contesto della collezione**

per generare uno o più candidati.

Esempio:

```text
Possibile corrispondenza

Batman
Numero 42
DC Comics
2019

Confidenza: 96%

[ Conferma ]
[ Scegli un altro risultato ]
[ Inserisci manualmente ]
```

---

# 7. Motore di riconoscimento

Il riconoscimento non deve dipendere esclusivamente dall'AI generativa.

Deve essere implementata una pipeline a più livelli:

### Livello 1 — Barcode/ISBN

Se viene riconosciuto un ISBN o altro identificativo, utilizzarlo come chiave primaria di ricerca.

### Livello 2 — OCR

Utilizzare titolo, numero, editore e altri testi rilevati.

### Livello 3 — Image matching

Confrontare la cover con immagini di copertina presenti nei database.

### Livello 4 — Ricerca semantica

Utilizzare un modello AI per interpretare informazioni incomplete o ambigue.

### Livello 5 — Contesto

Utilizzare i dati già presenti nella collezione.

Esempio:

Se l'utente possiede:

- Spider-Man #1
- Spider-Man #2
- Spider-Man #3

e fotografa una cover riconosciuta come Spider-Man #4, il sistema dovrebbe aumentare la probabilità che il candidato #4 sia corretto.

---

# 8. Acquisizione dei metadati

Una volta identificato il fumetto, il sistema deve interrogare una o più fonti esterne.

## Metadati da acquisire

### Identificazione

- titolo;
- titolo originale;
- serie;
- numero;
- volume;
- edizione;
- lingua;
- paese;
- editore;
- data pubblicazione;
- ISBN;
- UPC/EAN;
- codice prodotto.

### Creatori

- sceneggiatore;
- disegnatore;
- colorista;
- copertinista;
- traduttore;
- altri contributori.

### Contenuto

- descrizione;
- personaggi;
- universo narrativo;
- generi;
- tag;
- arco narrativo.

### Informazioni editoriali

- numero di pagine;
- formato;
- tipo di copertina;
- edizione;
- ristampa;
- variant;
- serie/volume.

### Immagini

- cover originale;
- eventuali immagini aggiuntive;
- thumbnail.

---

# 9. Sistema multi-fonte

Il backend deve prevedere un livello astratto:

**Metadata Provider**

in modo da poter aggiungere o sostituire fonti senza modificare l'app.

Esempio:

```text
Comic Catalog
      │
      ▼
Metadata Aggregator
      │
 ┌────┼─────┐
 ▼    ▼     ▼
API  API    API
```

Le fonti possono comprendere:

- database internazionali;
- database di editori;
- database italiani;
- Open Library;
- servizi specializzati in fumetti;
- fonti configurabili in futuro.

Il sistema deve conservare la **fonte del singolo dato**, quando disponibile.

Esempio:

```text
Titolo: Spider-Man
Fonte: Provider A

ISBN: 9781234567890
Fonte: Provider B

Editore: Marvel
Fonte: Provider A
```

---

# 10. Gestione dei risultati AI

L'AI non deve modificare automaticamente la collezione senza controllo dell'utente.

Ogni risultato deve avere:

- valore rilevato;
- fonte;
- livello di confidenza;
- eventuali alternative.

Esempio:

| Campo | Valore | Confidenza |
|---|---|---:|
| Titolo | Spider-Man | 99% |
| Numero | 42 | 96% |
| Editore | Marvel | 98% |
| Anno | 2019 | 82% |
| ISBN | 978... | 99% |

L'utente deve poter modificare qualsiasi campo prima del salvataggio.

---

# 11. Gestione manuale

Deve essere sempre possibile inserire un fumetto senza AI.

Campi principali:

- titolo;
- serie;
- numero;
- volume;
- editore;
- anno;
- lingua;
- ISBN/UPC;
- autori;
- descrizione;
- note;
- cover;
- categoria;
- tag.

---

# 12. Scheda del fumetto

Ogni fumetto deve avere una propria scheda.

## Informazioni bibliografiche

- cover;
- titolo;
- serie;
- numero;
- volume;
- editore;
- data;
- lingua;
- ISBN/UPC;
- autori;
- descrizione.

## Informazioni personali

- posseduto;
- numero di copie;
- prezzo di acquisto;
- data di acquisto;
- negozio/venditore;
- stato di conservazione;
- posizione fisica;
- note personali.

## Stato

Possibili valori:

- Da leggere
- In lettura
- Letto
- Da rileggere
- Prestato
- Venduto
- Mancante

---

# 13. Gestione delle copie

Il modello dati deve distinguere il **fumetto/edizione** dalla **copia fisica**.

Esempio:

```text
Spider-Man #42
        │
        ├── Copia 1
        │   ├── acquistata: 2024
        │   ├── prezzo: €5
        │   └── condizione: VG
        │
        └── Copia 2
            ├── acquistata: 2026
            ├── prezzo: €12
            └── condizione: NM
```

Questo permette di gestire correttamente i duplicati.

---

# 14. Condizione del fumetto

Deve essere possibile selezionare una condizione standardizzata.

Esempio:

- Mint;
- Near Mint;
- Very Fine;
- Fine;
- Very Good;
- Good;
- Fair;
- Poor.

L'utente può anche aggiungere una valutazione personale.

In una fase successiva l'AI potrebbe stimare automaticamente la condizione della copia a partire dalle fotografie, ma questa funzione deve essere considerata **sperimentale** e non sostitutiva della valutazione del collezionista.

---

# 15. Organizzazione della collezione

L'utente deve poter organizzare i fumetti attraverso:

- serie;
- editore;
- autore;
- personaggio;
- genere;
- lingua;
- anno;
- formato;
- stato di lettura;
- condizione;
- posizione;
- tag personalizzati.

---

# 16. Ricerca

La ricerca deve supportare:

- titolo;
- numero;
- autore;
- editore;
- personaggio;
- ISBN;
- serie;
- tag;
- testo libero.

Esempio:

> "Batman numeri 1-50 che mi mancano"

L'AI dovrebbe poter trasformare la richiesta in un filtro strutturato.

---

# 17. Serie e numeri mancanti

Una funzionalità importante è la gestione delle serie.

Esempio:

```text
The Amazing Spider-Man

Posseduti:
#1 ✓
#2 ✓
#3 ✓
#4 ✗
#5 ✓
#6 ✓
#7 ✗

Mancano:
#4
#7
```

L'app deve poter calcolare automaticamente:

- numeri posseduti;
- numeri mancanti;
- numeri duplicati;
- percentuale di completamento.

---

# 18. Rilevamento duplicati

Durante una nuova scansione il sistema deve verificare se l'edizione è già presente.

Esempio:

> ⚠️ Questo fumetto sembra già presente nella tua collezione.

```text
Spider-Man #42
Marvel — 2019

Possiedi già 2 copie.
```

L'utente può scegliere:

- aggiungi nuova copia;
- annulla;
- salva comunque come nuova edizione.

---

# 19. AI Assistant

L'app può includere un assistente conversazionale.

Esempi:

> "Quali numeri di Dylan Dog mi mancano?"

> "Quanti fumetti Marvel ho?"

> "Mostrami i fumetti comprati nel 2025."

> "Quali sono le serie quasi complete?"

> "Quali fumetti ho letto ma non hanno una recensione?"

> "Trova i duplicati."

L'assistente deve operare sui dati della collezione dell'utente e non inventare informazioni mancanti.

---

# 20. Statistiche

Dashboard statistiche:

- totale fumetti;
- totale copie;
- totale serie;
- serie complete;
- serie incomplete;
- distribuzione per editore;
- distribuzione per anno;
- distribuzione per genere;
- distribuzione per lingua;
- numero di duplicati;
- valore di acquisto totale;
- valore stimato, se disponibile.

---

# 21. Posizione fisica

L'utente deve poter indicare dove è conservato ogni fumetto.

Struttura consigliata:

```text
Casa
 └── Studio
      └── Libreria 2
           └── Scaffale 4
                └── Box 03
```

La posizione deve essere ricercabile.

---

# 22. Importazione ed esportazione

L'app deve supportare:

### Import

- CSV;
- Excel;
- JSON;
- eventualmente database di altre applicazioni.

### Export

- CSV;
- Excel;
- JSON;
- PDF/catalogo stampabile.

---

# 23. Sincronizzazione

La collezione deve essere sincronizzata tra:

- smartphone;
- tablet;
- web app.

Il sistema deve supportare:

- account utente;
- backup automatico;
- sincronizzazione cloud;
- recupero dati dopo reinstallazione.

---

# 24. Offline mode

Le funzioni fondamentali devono essere utilizzabili offline:

- visualizzazione collezione;
- ricerca;
- modifica;
- aggiunta manuale;
- visualizzazione delle cover.

Le funzioni AI e il recupero dei metadati possono richiedere connessione.

Le operazioni effettuate offline devono essere sincronizzate successivamente.

---

# 25. Privacy

L'utente deve avere il controllo sulle proprie fotografie e sui propri dati.

Requisiti:

- consenso esplicito all'utilizzo dell'immagine per l'analisi AI;
- possibilità di eliminare le fotografie;
- possibilità di eliminare completamente l'account;
- esportazione dei propri dati;
- cifratura dei dati sensibili;
- gestione GDPR;
- informativa sul trattamento dei dati;
- possibilità di scegliere se conservare o meno le immagini originali.

Per utenti europei sarebbe inoltre opportuno prevedere una configurazione dell'infrastruttura che consenta, quando supportato dal provider, di mantenere elaborazione e storage nell'UE.

---

# 26. Architettura tecnica

Una possibile architettura:

```text
                MOBILE / WEB APP
                       │
                       ▼
                  API BACKEND
                       │
          ┌────────────┼────────────┐
          ▼            ▼            ▼
     Catalog DB     AI Service   Auth Service
                       │
              ┌────────┼─────────┐
              ▼        ▼         ▼
             OCR    Vision AI   LLM
              │        │         │
              └────────┼─────────┘
                       ▼
                Recognition Engine
                       │
                       ▼
               Metadata Aggregator
                       │
            ┌──────────┼──────────┐
            ▼          ▼          ▼
         Provider    Provider    Provider
```

---

# 27. Modello dati principale

## Comic

```text
id
title
original_title
series_id
issue_number
volume
publisher
publication_date
language
country
isbn
ean
upc
description
page_count
format
cover_url
cover_image
created_at
updated_at
```

## Series

```text
id
name
publisher
language
start_year
end_year
description
```

## Creator

```text
id
name
role
```

## ComicCreator

```text
comic_id
creator_id
role
```

## PhysicalCopy

```text
id
comic_id
condition
purchase_price
purchase_date
seller
location_id
status
notes
```

## Collection

```text
id
user_id
name
```

## Location

```text
id
user_id
name
parent_id
```

## Scan

```text
id
user_id
image
ocr_text
recognition_status
confidence
created_at
```

## RecognitionCandidate

```text
id
scan_id
comic_id
provider
confidence
matched_fields
```

---

# 28. Requisiti AI

Il sistema AI deve:

1. ricevere la fotografia;
2. verificare che sia una cover di fumetto;
3. correggere/normalizzare l'immagine;
4. estrarre il testo;
5. identificare gli elementi significativi;
6. generare possibili identificazioni;
7. interrogare le fonti metadata;
8. confrontare i risultati;
9. calcolare un punteggio di affidabilità;
10. presentare i risultati all'utente;
11. non salvare automaticamente dati con bassa affidabilità.

### Soglie indicative

**> 95%**

Salvataggio rapido possibile, previa conferma.

**80–95%**

Richiedere conferma esplicita.

**< 80%**

Mostrare più candidati e richiedere intervento manuale.

Le soglie dovranno essere calibrate con dati reali durante il beta testing.

---

# 29. Learning loop

Il sistema deve poter imparare dalle correzioni dell'utente.

Esempio:

AI:

> Spider-Man #42 — 92%

Utente:

> No, è Spider-Man #42 Variant Edition.

Il sistema registra la correzione per migliorare:

- ranking dei risultati;
- riconoscimento delle variant;
- associazione cover → edizione;
- gestione degli editori locali.

Importante: il sistema deve distinguere tra apprendimento globale del modello e semplice personalizzazione della collezione dell'utente.

---

# 30. Gestione degli errori

L'app deve gestire:

- cover non riconosciuta;
- fotografia sfocata;
- cover parzialmente visibile;
- più fumetti nella stessa fotografia;
- dati discordanti tra fonti;
- nessun risultato;
- più risultati con stessa probabilità;
- API esterne non disponibili;
- connessione assente.

Esempio:

> Non riesco a identificare con sufficiente sicurezza questo fumetto.

Azioni:

**[ Riprova foto ]**

**[ Cerca manualmente ]**

**[ Inserisci dati ]**

---

# 31. Performance

Obiettivi MVP:

- apertura schermate principali < 2 secondi;
- ricerca locale praticamente istantanea;
- preview della fotografia immediata;
- feedback visivo durante l'elaborazione AI;
- processo di riconoscimento percepito come asincrono;
- possibilità di mettere in coda più scansioni.

Per l'inserimento massivo è consigliato un sistema di elaborazione batch:

```text
Scan 1 → processing
Scan 2 → processing
Scan 3 → waiting
Scan 4 → waiting
```

---

# 32. Sicurezza

Il backend deve prevedere:

- autenticazione sicura;
- gestione sessioni/token;
- autorizzazione per collezione;
- isolamento dei dati tra utenti;
- cifratura in transito;
- cifratura dei dati sensibili;
- rate limiting;
- logging;
- audit delle modifiche;
- backup automatici.

---

# 33. MVP

Per la prima versione eviterei di implementare tutto.

### MVP consigliato

**1. Account**

- registrazione;
- login;
- profilo.

**2. Collezione**

- lista fumetti;
- ricerca;
- filtri;
- scheda fumetto.

**3. Scanner AI**

- fotocamera;
- acquisizione cover;
- OCR;
- riconoscimento;
- ricerca metadata.

**4. Conferma**

- risultati AI;
- modifica dati;
- salvataggio.

**5. Organizzazione**

- serie;
- numeri;
- tag;
- stato;
- posizione.

**6. Duplicati**

- rilevamento copie già presenti.

**7. Backup**

- sincronizzazione cloud.

---

# 34. Funzioni per la versione 2

Dopo aver validato il flusso principale:

- scansione batch;
- riconoscimento automatico di più fumetti;
- serie mancanti;
- statistiche avanzate;
- assistente AI;
- import CSV/Excel;
- export;
- gestione prestiti;
- notifiche;
- wishlist;
- ricerca di fumetti mancanti;
- integrazione con marketplace;
- valutazione economica;
- stima della condizione tramite AI.

---

# 35. Funzioni avanzate future

## Riconoscimento della variant

L'AI deve distinguere:

```text
Spider-Man #1
Standard Cover

Spider-Man #1
Variant Cover A

Spider-Man #1
Variant Cover B
```

## Riconoscimento dell'edizione

La stessa storia può avere:

- prima edizione;
- ristampa;
- nuova numerazione;
- edizione italiana;
- edizione USA;
- variant;
- collected edition.

Il database deve quindi trattare **edizione** e **storia/opera** come concetti distinti.

---

# 36. Requisito fondamentale: separare opera, edizione e copia

Questa è una scelta architetturale molto importante.

Il modello dovrebbe essere:

```text
OPERA
  │
  ├── EDIZIONE ITALIANA
  │       │
  │       ├── COPIA 1
  │       └── COPIA 2
  │
  └── EDIZIONE USA
          │
          └── COPIA 1
```

In questo modo l'app non considera erroneamente due versioni diverse dello stesso fumetto come duplicati.

---

# 37. Criteri di successo del prodotto

Il progetto può essere considerato riuscito se un utente riesce a:

**1. prendere un fumetto dalla libreria**

↓

**2. fotografarlo**

↓

**3. ottenere automaticamente una proposta corretta**

↓

**4. confermare**

↓

**5. vedere immediatamente il fumetto nella propria collezione**

in meno di **30 secondi** nella maggioranza dei casi.

Il KPI principale dell'MVP dovrebbe quindi essere:

> **% di fumetti correttamente catalogati con una sola scansione e una sola conferma dell'utente.**

Altri KPI:

- tempo medio di catalogazione;
- accuratezza del riconoscimento;
- % di risultati corretti;
- % di inserimenti manuali;
- numero medio di fumetti catalogati per sessione;
- tasso di correzione dei metadati;
- utilizzo della scansione rispetto all'inserimento manuale.

---

# 38. Priorità delle funzionalità

| Funzionalità | Priorità |
|---|---|
| Catalogo personale | P0 |
| Scheda fumetto | P0 |
| Fotocamera/scansione cover | P0 |
| OCR | P0 |
| Riconoscimento AI | P0 |
| Recupero metadati | P0 |
| Conferma risultato AI | P0 |
| Ricerca | P0 |
| Serie | P0 |
| Gestione copie | P1 |
| Duplicati | P1 |
| Tag | P1 |
| Posizione fisica | P1 |
| Import/export | P1 |
| Statistiche | P1 |
| Assistente AI | P2 |
| Scansione batch | P2 |
| Stima valore | P2 |
| Valutazione condition tramite AI | P3 |
| Marketplace | P3 |

---

# 39. Principio UX principale

L'app non dovrebbe sembrare un database da compilare.

Dovrebbe sembrare uno **scanner intelligente per collezionisti**.

Il percorso ideale è:

> **"Fammi vedere il fumetto."**

> 📷

> **"Credo sia questo."**

> 🧠

> **"Confermi?"**

> ✓

> **"Aggiunto alla tua collezione."**

Questa semplicità deve essere il principale criterio di progettazione del prodotto.
