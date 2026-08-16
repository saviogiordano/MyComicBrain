# MyComicBrain

Applicazione mobile/web per catalogare la propria collezione di fumetti tramite riconoscimento AI della copertina.

## Obiettivo

Consentire a un collezionista di:

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

## Utente target

Collezionista privato di fumetti, manga, graphic novel e albi, che può possedere singoli albi, serie complete o incomplete, ristampe, variant cover, edizioni italiane e straniere, copie multiple e fumetti acquistati nuovi o usati.

## Flusso principale

**Fotografa → Riconosci → Cerca → Verifica → Salva**

L'utente scatta la foto di una copertina, l'AI la analizza (OCR + computer vision + barcode) e propone uno o più candidati con relativa confidenza. L'utente conferma o corregge, aggiunge eventuali dati personali (condizione, posizione, prezzo) e il fumetto viene salvato nella collezione.

## Principio UX

L'app non deve sembrare un database da compilare, ma uno **scanner intelligente per collezionisti**:

> "Fammi vedere il fumetto." → 📷 → "Credo sia questo." → 🧠 → "Confermi?" → ✓ → "Aggiunto alla tua collezione."

## Scope dell'MVP

1. **Account** — registrazione, login, profilo.
2. **Collezione** — lista fumetti, ricerca, filtri, scheda fumetto.
3. **Scanner AI** — fotocamera, acquisizione cover, OCR, riconoscimento, ricerca metadata.
4. **Conferma** — risultati AI, modifica dati, salvataggio.
5. **Organizzazione** — serie, numeri, tag, stato, posizione.
6. **Duplicati** — rilevamento copie già presenti.
7. **Backup** — sincronizzazione cloud.

Funzionalità più avanzate (assistente AI conversazionale, scansione batch, import/export, statistiche avanzate, stima del valore, integrazione marketplace) sono previste per le versioni successive.

## Documentazione

- [`docs/requisiti.md`](docs/requisiti.md) — requisiti funzionali e tecnici completi.
- [`CONTEXT.md`](CONTEXT.md) — contesto di dominio del progetto.
- [`docs/adr/`](docs/adr) — architecture decision records.
- [`app/README.md`](app/README.md) — istruzioni per eseguire l'applicazione.
