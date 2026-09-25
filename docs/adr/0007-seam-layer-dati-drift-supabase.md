# Seam del layer dati: un'interfaccia `ComicsRepository`, due adapter (drift / Supabase)

ADR-0003 fissa l'accesso diretto a Supabase con autorizzazione via RLS, ADR-0004 lo schema, ADR-0005 che la Modalità locale resta su drift e che i profili autenticati lavorano online-only su Supabase. Nessuno dei tre dice come il codice dell'app passa da un backend all'altro. Oggi `ComicsRepository` (`app/lib/core/data/comics_repository.dart`) è una classe concreta su drift (~97 metodi pubblici, 14 stream `watch*`, 6 transazioni) usata in ~40 file tramite `comicsRepositoryProvider`; `AppDatabase` non è usato da nessun altro. Decisioni prese in sessione di grilling sul ticket [#166](https://github.com/saviogiordano/MyComicBrain/issues/166) (mappa [#165](https://github.com/saviogiordano/MyComicBrain/issues/165)).

Decisione, in sintesi:

- **Interfaccia unica**: `ComicsRepository` diventa un'interfaccia con la superficie attuale; l'implementazione di oggi diventa `DriftComicsRepository`, si aggiunge `SupabaseComicsRepository`. Nessun chiamante cambia. Dentro l'adapter Supabase le aree (catalogo, scansioni, statistiche, …) possono stare in file separati come dettaglio interno.
- **Selezione via Riverpod**: `comicsRepositoryProvider` osserva il provider della sessione Supabase — nessuna sessione → adapter drift; sessione → adapter Supabase legato a quello `user_id` e al `collection_id` della sua Collezione (risolto una volta alla costruzione, riga `owner` in `collection_members`), non passato a ogni metodo. Login/logout ricostruiscono tutto ciò che dipende dal provider.
- **Reattività dei `watch*` su Supabase**: invalidazione interna all'adapter — ogni scrittura emette un segnale per tabella toccata e gli stream interessati rileggono. Riproduce la semantica di drift ("vedo subito le mie scritture"); modifiche dello stesso account da un altro device si vedono alla riapertura. Niente Supabase Realtime in questa tranche.
- **Strategia di query**: CRUD semplice e dettaglio via PostgREST dal client (select annidate); aggregati/statistiche (Dashboard, Serie, serie incomplete, duplicati, `conteggioPer`, ricerca/indice Collezione dove serve) come funzioni Postgres `SECURITY INVOKER` chiamate via `rpc()`; scritture atomiche multi-tabella (`confermaCandidato`, rimozione Copia/eliminazione Edizione, `unisciSerieDuplicate`, `importaRighe`) anch'esse come RPC `SECURITY INVOKER`, unico posto dove esiste una transazione. Le RLS di ADR-0004 restano l'unica barriera di autorizzazione. Le funzioni sono migrazioni versionate come il resto dello schema.
- **Immagini**: bucket Storage privati — cover in `covers/<collection_id>/<uuid>.jpg` (policy su `storage.objects` via `private.visible_collection_ids()` in lettura e `private.editable_collection_ids()` in scrittura), immagini delle Scansioni in `scansioni/<user_id>/<uuid>.jpg` (private all'utente). Nel DB si salva la chiave Storage, non un URL. L'adapter Supabase implementa `risolviCoverImage` con download autenticato in una cache su disco e restituisce un percorso locale: la UI resta su `Image.file`, nessun URL firmato o pubblico.
- **Conversazione/Assistente**: incluse nell'adapter Supabase (tabelle `conversazioni`/`messaggi` private per `user_id` di ADR-0004); nessuna limitazione dell'Assistente per i profili autenticati.
- **Parità fra adapter**: una sola suite di contratto — gli attuali `*_repository_test` resi parametrici su una factory di adapter — eseguita sempre su drift in memoria e su Supabase contro lo stack locale `supabase start`. Una fetta di porting è completa quando la sua parte di suite passa anche su Supabase.
- **Rilascio incrementale**: il login resta dietro un flag di sviluppo finché l'intera suite di contratto non passa su Supabase; `main` resta rilasciabile.
- **Importazione dalla Modalità locale** (ADR-0005): non passa dall'interfaccia. Un modulo dedicato legge drift direttamente, carica prima le immagini su Storage con chiavi deterministiche, poi invoca una RPC transazionale `importa_modalita_locale(payload jsonb, import_id uuid)` che rimappa gli id drift sugli id Postgres ed è idempotente sullo stesso `import_id` — riprovabile senza duplicati parziali.

## Considered Options

- **Repository per area** (Catalogo, Scansioni, Statistiche, …) ciascuno con due adapter — scartata per ora: interfacce più piccole, ma ~40 file da toccare senza avvicinare la destinazione; il seam attuale è già nel posto giusto. Resta possibile spezzarlo in seguito.
- **Supabase Realtime** per gli stream — scartata in questa tranche: costo di canali e publication senza un bisogno reale finché non ci sono Collezioni condivise (altri scrittori). Da rivalutare con §17.2.
- **Stream a valore singolo** (nessuna reattività) — scartata: romperebbe il comportamento delle pagine che oggi si aggiornano dopo una scrittura.
- **View Postgres** per gli aggregati — scartate a favore di funzioni: accettano parametri (filtri, paginazione).
- **URL firmati o pubblici** per le cover — scartati: richiederebbero di cambiare la UI (`Image.file` → rete) e, per i pubblici, di rinunciare all'isolamento RLS. La cache su disco non contraddice ADR-0005 ("nessuna cache locale di lettura"): è una cache di file immutabili, non di dati di dominio.
- **Metodi non portati che lanciano `UnimplementedError`** in un'app pubblicata — scartata a favore del flag.
- **Importazione riga per riga tramite l'adapter Supabase** — scartata: senza transazione, un errore a metà lascerebbe duplicati parziali.

## Consequences

- Il porting procede in fette `task` (una per sessione) sulla mappa [#165](https://github.com/saviogiordano/MyComicBrain/issues/165): estrazione dell'interfaccia, scheletro dell'adapter, catalogo/Copie, Scansioni→Identificazione, Serie/Dashboard/Valore stimato, Conversazione/esportazione, rimozione del flag.
- Ogni nuovo metodo aggiunto a `ComicsRepository` da qui in avanti va implementato su entrambi gli adapter e coperto dalla suite di contratto.
- I bucket e le policy Storage descritti sopra vanno creati insieme allo schema di ADR-0004.
- Con le Collezioni condivise (§17.2) la reattività per invalidazione interna non basta più (scrittori su altri account): servirà Realtime o equivalente.
