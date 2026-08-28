# Separare il Provider AI Visivo dal Provider AI Testuale

Fino a oggi `AiProvider` (§12) è una singola selezione (brand + API key + modello) condivisa da tutte le chiamate AI dell'app, usata finora solo dall'Analisi Copertina (§6). L'introduzione dell'Assistente conversazionale (§10, fuso con l'ex §14 — vedi [Mappa — Ricerca conversazionale e Assistente](https://github.com/saviogiordano/MyComicBrain/issues/118)) aggiunge un secondo tipo di chiamata AI, puramente testuale, con requisiti diversi da quelle di visione: la vision analysis richiede un modello capace di computer vision e structured output (costoso), mentre la comprensione della query utente e l'orchestrazione delle tool call sui dati locali non richiede capacità di visione e può girare su un modello più economico o persino un provider diverso.

Decisione: `AiProvider` si sdoppia in due selezioni completamente indipendenti — **Provider AI Visivo** (Analisi Copertina, invariato nel comportamento) e **Provider AI Testuale** (Assistente) — ciascuna con il proprio brand (OpenAI/Claude/OpenRouter/Locale), API key, modello e, per Locale, URL. Le due possono coincidere (stesso brand per entrambe) o no (es. visione su Claude, testo su un modello locale più economico). Alla migrazione, entrambe le selezioni vengono inizializzate a copia della configurazione singola preesistente, cosicché l'Analisi Copertina continui a funzionare senza reconfigurazione e l'Assistente sia utilizzabile da subito, modificabile in seguito indipendentemente.

## Considered Options

- Mantenere un'unica selezione di brand/chiave, aggiungendo solo un secondo campo "modello" (visione/testo) sotto la stessa API key — scartata perché non permette di cambiare *brand* fra i due ruoli (es. Locale per il testo, cloud per la visione), il che limita l'ottimizzazione dei costi al solo modello e non al provider nel suo complesso.

## Consequences

- `SettingsRepository` (#105) raddoppia lo storage per ruolo (chiave/modello/URL per Visivo e per Testuale) invece che per solo brand.
- Lo schermo Impostazioni (§12) mostra due sezioni di provider AI invece di una.
- Ogni nuova funzionalità AI futura dovrà dichiarare esplicitamente se è di ruolo Visivo o Testuale — non esiste più un provider AI generico unico.
