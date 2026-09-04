# Ricerca — Pattern Postgres/RLS per ruoli su collezioni condivise (Proprietario/Editor/Visualizzatore)

> Risposta al ticket Wayfinder [#153](https://github.com/saviogiordano/MyComicBrain/issues/153) "Ricerca — pattern RLS Postgres/Supabase per ruoli su collezioni condivise (Proprietario/Editor/Visualizzatore)", figlio della mappa [#149](https://github.com/saviogiordano/MyComicBrain/issues/149).
>
> Questo documento è **solo ricerca**: raccoglie i pattern consigliati da Supabase e dalla community Postgres/RLS per modellare condivisione multi-utente con ruoli distinti. Non progetta lo schema/le policy definitive — quello è compito del ticket figlio [#154](https://github.com/saviogiordano/MyComicBrain/issues/154) ("Decisione — schema Postgres + RLS per ruoli su collezioni condivise"), che va affrontato in una sessione successiva. Non modifica codice applicativo né gli issue #149/#154.

Contesto: la scelta della piattaforma (Supabase, Postgres + RLS) è stata fatta e giustificata nel ticket [#148](https://github.com/saviogiordano/MyComicBrain/issues/148); la ricerca comparativa completa è in `docs/research/baas-auth-backend.md` sul branch `research/baas-auth-backend` (motivazione: modello relazionale + RLS gratuita si presta naturalmente al requisito §17.2/§17.3 di ruoli distinti su una collezione condivisa). Il requisito da supportare (`docs/requisiti.md` §17.2 "Collezioni condivise" e §17.3 "Isolamento e permessi") prevede: invito di collaboratori via email o codice/link condivisibile con accetta/rifiuta; tre ruoli (Proprietario, Editor, Visualizzatore) con permessi distinti; un collaboratore può abbandonare autonomamente una collezione condivisa; ogni operazione deve verificare il ruolo; il modello dati deve associare una collezione a più utenti con ruoli distinti (non una singola colonna owner); l'eliminazione dell'account di un collaboratore rimuove i suoi permessi ma non la collezione né i dati altrui; ogni modifica va tracciata con autore e timestamp (§27 Security, audit trail).

## 1. Guida ufficiale Supabase su RLS: pattern generali multi-utente

La [guida ufficiale RLS di Supabase](https://supabase.com/docs/guides/database/postgres/row-level-security) mostra il pattern base "riga di proprietà singola":

```sql
-- Users can view their own profile.
using ( (select auth.uid()) = user_id )
```

e distingue esplicitamente `using` (quali righe sono visibili/selezionabili/modificabili) da `with check` (che forma deve avere la riga risultante di un INSERT/UPDATE) — le due clausole vanno combinate per operazioni di scrittura.

Per l'accesso condiviso (team/liste), la stessa guida mostra un pattern di **tabella di appartenenza** (membership table) molto vicino a quanto richiesto da §17.2/§17.3:

```sql
create table team_members (
  team_id uuid references teams (id),
  user_id uuid references auth.users (id),
  primary key (team_id, user_id)
);

create index team_members_user_id_idx
on team_members using btree (user_id);
```

Nota della guida: "The primary key covers team_id. A policy filtering on user_id needs its own index." — cioè la sola primary key composita non basta, serve un indice esplicito sulla colonna effettivamente filtrata dalla policy.

Fonte: [Row Level Security — Supabase Docs](https://supabase.com/docs/guides/database/postgres/row-level-security)

## 2. Il pattern "tabella di giunzione + RLS sulle tabelle di dominio"

Il pattern descritto nel ticket (`collection_members` con `user_id`, `collection_id`, `role`, più RLS su `collections`/`comics`/`physical_copies` che verificano il ruolo tramite quella tabella) corrisponde esattamente al pattern generale che sia la documentazione ufficiale Supabase sia la community chiamano **membership/junction table pattern**:

- La decisione chiave preliminare, secondo le fonti secondarie che riprendono/spiegano la doc ufficiale, è se il "tenant boundary" è l'utente singolo o un gruppo (org/team/collezione): per applicazioni dove più persone collaborano sulla stessa risorsa (il caso di §17.2) serve un'entità di gruppo come tenant, non un filtro diretto per singolo utente.
- Il pattern raccomandato: una tabella di appartenenza (account/collection memberships) che registra la relazione utente↔risorsa **con un ruolo**, più una funzione helper che verifica se l'utente ha un determinato ruolo sulla risorsa, richiamata dalle policy delle tabelle di dominio.

Fonte (sintesi/cross-check secondario, coerente con la doc ufficiale sopra): ricerca aggregata su [supabase.com/features/row-level-security](https://supabase.com/features/row-level-security) e articoli di settore che descrivono esplicitamente questo pattern come standard per RLS multi-tenant/team-based.

### Esempio "ufficiale" di riferimento cercato: Slack clone di Supabase

Il repo ufficiale `supabase/supabase` contiene un [esempio "Slack clone"](https://github.com/supabase/supabase/blob/master/examples/slack-clone/nextjs-slack-clone/README.md) (Next.js + Postgres RLS), storicamente citato come showcase ufficiale di RLS multi-utente. **Verifica diretta dello schema** (`full-schema.sql` nello stesso esempio): questo esempio **non contiene** una tabella di membership per-canale né una funzione `is_member()` — l'accesso ai canali è globale per qualunque utente autenticato (`auth.role() = 'authenticated'`), e i permessi sono gestiti solo con un sistema di ruoli via custom claim JWT (funzione `authorize()`, `SECURITY DEFINER`) per capacità globali tipo "moderator"/"admin", non con appartenenza per-risorsa. **Non è quindi un esempio direttamente riusabile per il caso "un ruolo diverso per utente su ogni singola collezione condivisa"** — è utile solo come conferma del pattern "funzione SECURITY DEFINER per il controllo ruoli", non come modello di membership table. Questo è un fatto negativo utile da registrare: il pattern completo membership-table + ruolo-per-risorsa **non ha un tutorial ufficiale Supabase dedicato e verificato** tra quelli rintracciati in questa ricerca; il pattern corretto va quindi composto a partire dalla guida RLS generale (sezione 1 e 3) più le pratiche community (sezione 5).

## 3. Evitare la ricorsione delle policy RLS (gotcha noto)

Fonte primaria: [Row Level Security — Supabase Docs](https://supabase.com/docs/guides/database/postgres/row-level-security), sezione sulla ricorsione.

**Il problema**: se la policy della tabella A interroga la tabella B (es. una membership table) e la policy della tabella B a sua volta interroga la tabella A, le due policy si richiamano a vicenda e Postgres non riesce a risolverle — la doc lo dice esplicitamente: *"Two tables whose policies read each other never resolve. Postgres raises `42P17`."*

Esempio (dalla doc, caso `lists`/`list_members`, struttura identica al nostro `collections`/`collection_members`):

```sql
-- Rifiutata da Postgres: ogni policy legge la tabella protetta dall'altra.
create policy "members read lists" on lists for select
to authenticated
using (
  exists (
    select 1 from list_members m
    where m.list_id = lists.id and m.user_id = (select auth.uid())
  )
);

create policy "members read membership" on list_members for select
to authenticated
using (
  exists (
    select 1 from lists l
    where l.id = list_members.list_id and l.owner_id = (select auth.uid())
  )
);
```

**La mitigazione ufficiale**: rompere il ciclo con una **funzione `SECURITY DEFINER`** che legge la tabella di membership come proprietario (bypassando quindi le RLS di quella tabella per la lettura interna), e farla richiamare da entrambe le policy invece di far leggere le tabelle direttamente l'una dall'altra:

```sql
create schema if not exists private;

create function private.user_list_ids()
returns setof uuid
language sql
security definer
set search_path = ''
stable
as $$
  select list_id from public.list_members
  where user_id = (select auth.uid())
$$;

revoke execute on function private.user_list_ids() from public;
grant usage on schema private to authenticated;
grant execute on function private.user_list_ids() to authenticated;

create policy "members read lists" on lists for select
to authenticated
using ( id in (select private.user_list_ids()) );

create policy "members read membership" on list_members for select
to authenticated
using ( list_id in (select private.user_list_ids()) );
```

Principio chiave citato dalla doc: *"The function runs as its owner, and a `security definer` function only skips RLS when its owner can."* — cioè la funzione deve essere creata da un ruolo che ha effettivamente accesso alla tabella di membership (bypassa RLS su quella tabella *per l'esecuzione interna della funzione*, non per l'utente chiamante).

**Nota di sicurezza esplicita nella doc**: *"A `security definer` function in an exposed schema is callable over the Data API with the creator's privileges. Never create one in a schema listed under 'Exposed schemas'"* — per questo l'esempio crea la funzione in uno schema `private` non esposto via API REST/RPC pubblica, e imposta `set search_path = ''` per prevenire injection tramite risoluzione di schema.

### Conferma da fonti secondarie (cross-check)
Ricerca aggregata (blog/tutorial di settore che citano esplicitamente la doc Supabase) conferma lo stesso principio: *"Recursive RLS loops can occur if your membership function reads a table that itself has RLS, and those policies call the membership function. The security definer attribute breaks the loop"* — coerente con la fonte primaria sopra, nessuna discrepanza rilevata.

### Nota Postgres "vanilla" (non specifica di Supabase)

La [documentazione ufficiale PostgreSQL su Row Security Policies](https://www.postgresql.org/docs/current/ddl-rowsecurity.html) conferma il meccanismo generale sotto Supabase:
- Le policy possono referenziare altre tabelle tramite sub-`SELECT` o funzioni che contengono `SELECT`, ma: *"Be aware however that such accesses can create race conditions that could allow information leakage if care is not taken."*
- *"Policy expressions run with the privileges of the user running the query, although security-definer functions can be used to access data not available to the calling user."* — questa è la base tecnica generale su cui si fonda il pattern SECURITY DEFINER usato da Supabase per rompere la ricorsione.
- Solo il proprietario della tabella può abilitare/disabilitare RLS; superuser e ruoli `BYPASSRLS` bypassano sempre le RLS; i proprietari delle tabelle bypassano RLS di default a meno di `ALTER TABLE ... FORCE ROW LEVEL SECURITY`.

Fonte: [PostgreSQL Docs — Row Security Policies](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)

## 4. Performance/indicizzazione per policy che joinano una membership table

Fonte primaria: [Supabase Docs — Troubleshooting: RLS Performance and Best Practices](https://supabase.com/docs/guides/troubleshooting/rls-performance-and-best-practices-Z5Jjwv) (con conferma nella guida RLS generale).

Cinque raccomandazioni concrete, con numeri di benchmark riportati dalla stessa doc:

1. **Indicizzare le colonne usate nelle policy che non sono già PK/uniche.** Esempio citato: indicizzare `user_id` per una policy `auth.uid() = user_id` dà un miglioramento "over 100x on large tables"; su un test con 1M righe e una tabella team da 1K righe, indicizzare `team_id` ha portato il tempo da 170ms a 2ms.
2. **Avvolgere le funzioni (incl. `auth.uid()`/`auth.jwt()` e funzioni `SECURITY DEFINER`) in un `select`.** `is_admin() or auth.uid() = user_id` diventa `(select is_admin()) OR (select auth.uid()) = user_id`. Questo fa sì che Postgres tratti la chiamata come un `initPlan` cacheato una volta per statement invece che rivalutato per ogni riga — nel benchmark citato, da 11.000ms a 10ms. **Attenzione**: va applicato solo se il risultato della funzione non dipende dai dati della riga corrente.
3. **Usare funzioni `SECURITY DEFINER` al posto di subquery/`EXISTS` dirette sulla membership table dentro la policy.** Sostituire `exists (select 1 from roles_table where auth.uid() = user_id and role = 'good_role')` con una funzione dedicata (es. `has_role()`) evita che la membership table debba rivalutare le proprie RLS per ogni riga della tabella di dominio. Benchmark citato: da 178.000ms a 12ms.
4. **Strutturare il join con `IN`/`ANY` "al contrario"**: invece di `auth.uid() in (select user_id from team_user where team_user.team_id = table.team_id)`, preferire `team_id in (select team_id from team_user where user_id = auth.uid())` (filtra prima sulla membership dell'utente corrente, poi confronta contro la colonna della tabella di dominio). Benchmark citato: da 9.000ms a 20ms. Nota esplicita: per liste con più di ~10.000 elementi "extra analysis is likely needed".
5. **Specificare sempre `to authenticated`** nelle policy invece di affidarsi solo al check su `auth.uid()`, per escludere `anon` a livello di ruolo Postgres prima ancora della valutazione della condizione.

Raccomandazione aggiuntiva della stessa pagina: applicare comunque filtri espliciti anche lato query applicativa (es. `.eq('collection_id', id)`), perché le RLS restano un controllo di sicurezza ma non sostituiscono un piano di query efficiente — nel test citato questo abbassa ulteriormente da 171ms a 9ms.

Queste cinque raccomandazioni si applicano direttamente al caso `collection_members`: la policy su `comics`/`physical_copies` che deve verificare "l'utente ha un ruolo su questa collezione" è esattamente lo scenario per cui la doc consiglia (a) indice su `collection_members(user_id)` oltre alla PK composita, (b) una funzione `SECURITY DEFINER` che restituisce gli id delle collezioni/ruoli dell'utente corrente invece di una subquery diretta ripetuta per riga, e (d) la forma "filtra prima per l'utente, poi confronta l'id" piuttosto che il contrario.

## 5. Come vengono modellati i flussi di invito (email/codice, pending/accepted)

Non esiste un tutorial ufficiale Supabase specifico per "invito a collezione condivisa" verificato in questa ricerca (vedi nota nella sezione 2 sul limite dell'esempio Slack clone). Le fonti disponibili — un mix di articoli tecnici di terze parti che descrivono esplicitamente pattern costruiti sopra le primitive Supabase/Postgres di RLS — convergono su due varianti equivalenti, entrambe compatibili con le fondamenta ufficiali (RLS + SECURITY DEFINER) delle sezioni precedenti:

- **Variante A — tabella di invito separata dalla membership**: una tabella `team_invitations`/`team_invites` (id, team/collection_id, invited_by, email o codice, timestamp, eventuale scadenza) distinta dalla tabella di membership effettiva (`team_members`/`collection_members`). Solo dopo l'accettazione viene creata la riga di membership vera e propria con il ruolo assegnato. Esempio di schema riportato da una fonte di settore:
  ```sql
  CREATE TABLE public.team_invites (
    id uuid PRIMARY KEY,
    team_id uuid NOT NULL,
    inviter_id uuid,
    first_name varchar NOT NULL,
    last_name varchar,
    email varchar,
    created_at timestamptz DEFAULT now()
  )
  ```
  Fonte: [Boardshape — How to implement RLS for a team invite system with Supabase](https://boardshape.com/engineering/how-to-implement-rls-for-a-team-invite-system-with-supabase)
- **Variante B — colonna `status` sulla riga di membership stessa** (`pending`/`accepted`/`declined`) invece di una tabella separata: la riga in `collection_members` esiste già al momento dell'invito ma con `status = 'pending'` e ruolo proposto; l'utente invitato può poi fare update del proprio `status` (accettazione/rifiuto). Pattern descritto da più fonti aggregate come alternativa più semplice quando non serve un ciclo di vita ricco per l'invito (scadenza, re-invio, ecc.).

**Problema tecnico comune alle due varianti, ben documentato**: se l'invito avviene per email prima che l'invitato abbia un account/sessione autenticata (o comunque prima che possa essere titolare di una riga protetta da RLS visibile solo a sé stesso), **RLS da sola non permette a un utente anonimo o non ancora membro di leggere/accettare l'invito**, perché "non è possibile referenziare i parametri della query in ingresso dentro RLS" (cita testualmente la fonte). La mitigazione descritta è la stessa vista nella sezione 3: una **funzione `SECURITY DEFINER`** dedicata (es. `get_invite(invite_id uuid)` o un RPC `accept_invite(...)`) che gira con i privilegi del creatore e quindi bypassa le RLS restrittive sulla tabella di invito/membership per l'operazione specifica e controllata di lettura/accettazione tramite un identificatore opaco (UUID/token), invece di aprire una policy larga sulla tabella.
```sql
CREATE OR REPLACE FUNCTION public.get_invite(invite_id uuid)
RETURNS SETOF team_invites LANGUAGE sql
SECURITY DEFINER SET search_path TO 'public'
AS $function$
  select * from team_invites where id = invite_id;
$function$
```
Fonte: [Boardshape — How to implement RLS for a team invite system with Supabase](https://boardshape.com/engineering/how-to-implement-rls-for-a-team-invite-system-with-supabase)

Altre fonti aggregate confermano lo stesso schema concettuale ("separazione tra inviti pendenti e membership attiva", "solo i proprietari del team possono selezionare/aggiornare gli inviti tramite una policy che verifica il privilegio owner", "operazioni come l'accettazione di un invito e la creazione della riga di membership devono bypassare RLS", tipicamente tramite RPC/funzione SECURITY DEFINER oppure, in alcuni casi più radicali, tramite la `service_role` key lato server) — nessuna di queste è una pagina ufficiale Supabase dedicata al flusso di invito; sono tutte fonti secondarie di settore usate qui per confermare la convergenza del pattern, non come fonte primaria del meccanismo RLS/SECURITY DEFINER sottostante (quello è documentato ufficialmente, sezione 3).

**Nota su "codice/link condivisibile"** (l'altra modalità di invito richiesta da §17.2 oltre all'email): nessuna fonte ufficiale Supabase specifica trovata per questo caso preciso; il pattern è concettualmente lo stesso di un invito via email ma con un token/codice opaco al posto dell'indirizzo email come identificatore della riga di invito, retrievable dalla stessa funzione `SECURITY DEFINER` per identificatore invece che per indirizzo.

## 6. Rimozione di un collaboratore / eliminazione del suo account: non orfanare dati e collezione

Due sotto-problemi distinti emergono dalle fonti ufficiali:

### 6.1 Rimuovere la riga di membership (collaboratore lascia o viene rimosso)

Questo è il caso semplice e non richiede pattern speciali oltre a quanto già in sezione 2-3: un `DELETE` sulla riga `collection_members` (protetto da una policy che verifica che il chiamante sia il Proprietario, oppure che stia cancellando la **propria** riga per il caso "abbandono autonomo" di §17.3) rimuove solo il legame utente↔collezione↔ruolo. Non tocca `collections` né le righe di `comics`/`physical_copies` — a patto che queste ultime **non** abbiano una foreign key verso `collection_members` (devono referenziare `collections` per l'appartenenza e, separatamente, l'utente autore per l'audit).

### 6.2 Eliminazione dell'account utente (non solo rimozione dalla collezione)

Fonte primaria: [Supabase Docs — Managing User Data](https://supabase.com/docs/guides/auth/managing-user-data) e [Supabase Docs — Cascade Deletes](https://supabase.com/docs/guides/database/postgres/cascade-deletes).

- La doc ufficiale raccomanda di referenziare **solo la chiave primaria** di `auth.users` dalle tabelle applicative: *"Only use primary keys as foreign key references for schemas and tables like auth.users which are managed by Supabase"*, perché *"Primary keys are guaranteed not to change"*.
- L'esempio ufficiale per una tabella `profiles` usa `on delete cascade`: `id uuid not null references auth.users on delete cascade` — ma questo è mostrato per il caso "il profilo è dati personali dell'utente, va cancellato con lui", **non** per il caso richiesto da §17.3 ("la cancellazione dell'account rimuove i permessi ma non i dati che l'utente ha aggiunto alla collezione").
- La pagina ufficiale [Cascade Deletes](https://supabase.com/docs/guides/database/postgres/cascade-deletes) elenca le cinque regole standard di Postgres per `ON DELETE` sulle foreign key — `CASCADE`, `RESTRICT`, `SET NULL`, `SET DEFAULT`, `NO ACTION` — con le rispettive semantiche, ma **non fornisce** (verificato direttamente sulla pagina) una raccomandazione esplicita su quale usare per preservare dati storici/autore quando la riga utente referenziata viene eliminata: è documentazione dei meccanismi, non delle scelte di design per questo caso specifico.
- La pratica community convergente (discussione ufficiale nel repo GitHub `supabase/supabase`, non doc prescrittiva ma dagli stessi maintainer/community Supabase) per il caso "voglio conservare i dati ma non l'utente" è: **`on delete set null`** sulla foreign key verso `auth.users` (richiede che la colonna sia nullable), così che alla cancellazione dell'account la riga applicativa resti con l'FK a `null` invece di essere cancellata a cascata, con la possibilità applicativa di mostrare un placeholder tipo "Utente eliminato" al posto dell'autore mancante.
  Fonte: [GitHub — supabase/supabase Discussion #6524 "delete from table with foreign keys"](https://github.com/orgs/supabase/discussions/6524)

**Implicazione diretta per §17.3 e per l'audit trail di §27**: la fonte ufficiale e quella community convergono sul fatto che la scelta del comportamento `ON DELETE` sulla FK verso `auth.users` è **una decisione di design esplicita per ogni tabella**, non un default sicuro univoco — Postgres/Supabase non impongono un default "giusto" per questo caso. Questo conferma (senza prescriverlo qui, che è compito di #154) che una colonna tipo `created_by`/`author_id` che referenzia `auth.users` per finalità di audit va probabilmente trattata con `on delete set null` (o un riferimento a una tabella `profiles` propria mantenuta anche dopo la cancellazione auth) — mentre la riga di **membership** (`collection_members`) va invece rimossa (delete reale, non set null) alla cancellazione dell'account, dato che rappresenta un permesso attivo che non ha senso restare "pendente" verso un utente che non esiste più. Nessuna fonte ufficiale trovata descrive esplicitamente questa distinzione a due velocità (membership da cancellare vs. autorship da preservare con FK nullable) come pattern nominato — è una sintesi coerente con le fonti sopra, non una citazione diretta.

## Conclusione (fatti raccolti, non uno schema definitivo)

Sintesi dei pattern raccomandati/osservati per il ticket #154, da fonti primarie salvo dove indicato:

- **Forma della tabella di giunzione**: una tabella `collection_members`-like con chiave primaria composita `(collection_id, user_id)`, colonna `role`, e un **indice separato** sulla colonna effettivamente usata come filtro nelle policy (tipicamente `user_id`) oltre alla PK composita — pattern esplicito nella guida ufficiale RLS di Supabase.
- **RLS sulle tabelle di dominio** (`comics`, `physical_copies`, ecc.) va costruita verificando l'appartenenza/il ruolo dell'utente tramite quella tabella di giunzione, **non** duplicando una colonna owner sulle tabelle di dominio.
- **Evitare la ricorsione delle policy** (gotcha noto, errore Postgres `42P17` quando due tabelle con RLS si controllano a vicenda): la mitigazione ufficiale è una **funzione `SECURITY DEFINER`** in uno schema non esposto (es. `private`), con `set search_path = ''`, che legge la membership table come proprietario e viene richiamata da entrambe le policy — mai le tabelle protette che si leggono direttamente a vicenda in una policy.
- **Performance/indicizzazione**: indicizzare le colonne di membership filtrate dalle policy, avvolgere le funzioni (incl. quelle `SECURITY DEFINER` e `auth.uid()`) in `select` per farle cacheare come `initPlan`, preferire una funzione `SECURITY DEFINER` a una subquery/`EXISTS` diretta sulla membership table dentro la policy, e strutturare i confronti come "id della collezione IN (collezioni dell'utente corrente)" piuttosto che il contrario — con benchmark ufficiali che mostrano differenze di più ordini di grandezza tra la forma naive e quella ottimizzata.
- **Inviti**: nessun tutorial ufficiale Supabase dedicato verificato in questa ricerca; il pattern convergente (fonti di settore, coerente con le fondamenta ufficiali RLS+SECURITY DEFINER) prevede o (a) una tabella di invito separata dalla membership effettiva, popolata solo dopo l'accettazione, oppure (b) uno stato `pending`/`accepted` direttamente sulla riga di membership; in entrambi i casi, la lettura/accettazione dell'invito da parte di un utente non ancora membro richiede tipicamente una funzione `SECURITY DEFINER` (o un RPC dedicato) perché RLS da sola non può esporre una riga a un chiamante che ancora non ha un legame di membership verificabile.
- **Rimozione collaboratore vs. eliminazione account**: rimuovere un collaboratore (o l'abbandono autonomo di §17.3) è un semplice `DELETE` sulla riga di membership, che non tocca la collezione né i dati altrui per costruzione (nessuna FK da `comics`/`physical_copies` verso `collection_members`). L'eliminazione dell'intero account utente è un caso distinto: la doc ufficiale Supabase mostra `on delete cascade` solo per dati strettamente personali (es. `profiles`); per preservare l'autorship storica di righe che l'utente ha creato in una collezione condivisa dopo che il suo account è stato eliminato, la pratica convergente (fonte community, non doc ufficiale prescrittiva) è referenziare l'utente con `on delete set null` su una colonna di audit (`created_by`), tenendo questa colonna distinta e disaccoppiata dalla riga di membership (che invece va cancellata, non messa a null).
