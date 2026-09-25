-- Scansioni e Conversazione restano private all'account che le ha create,
-- anche fra membri della stessa Collezione (ADR-0004).
begin;
\ir helpers.psql
select plan(9);

select tests.create_user('owner@example.com') as owner \gset
select tests.create_user('editor@example.com') as editor \gset
select tests.collection_of(:'owner') as col \gset

insert into public.collection_members (collection_id, user_id, role) values (:'col', :'editor', 'editor');

select tests.authenticate_as(:'owner');
select lives_ok(
  format($$ insert into public.scansioni (id, collection_id, image) values (101, %L, 'x/1.jpg') $$, :'col'),
  'l''utente crea una Scansione (user_id di default = auth.uid())');
insert into public.analisi_copertina (id, scansione_id) values (101, 101);
insert into public.identificazione (id, scansione_id) values (101, 101);
insert into public.candidati (identificazione_id, source, punteggio) values (101, 'esterno', 80);
insert into public.conversazione (id) values (101);
insert into public.messaggio (conversazione_id, ruolo, testo) values (101, 'utente', 'ciao');
reset role;

select tests.authenticate_as(:'editor');
select is_empty($$ select 1 from public.scansioni $$,
  'un collaboratore non vede le Scansioni del Proprietario');
select is_empty($$ select 1 from public.analisi_copertina $$,
  '... né le Analisi Copertina');
select is_empty($$ select 1 from public.candidati $$,
  '... né i Candidati');
select is_empty($$ select 1 from public.messaggio $$,
  '... né i Messaggi della Conversazione');
select throws_ok(
  format($$ insert into public.scansioni (user_id, image) values (%L, 'x/2.jpg') $$, :'owner'),
  '42501', null,
  'nessuno crea Scansioni a nome di un altro utente');
select is(tests.affected($$ delete from public.scansioni $$), 0,
  'un collaboratore non cancella le Scansioni altrui');
-- FK composita (user_id, scansione_id): anche conoscendo l'id, un utente
-- non aggancia righe alla Scansione di un altro.
select throws_ok(
  $$ insert into public.identificazione (scansione_id) values (101) $$,
  '23503', null,
  'un''Identificazione non può riferire la Scansione di un altro utente');
reset role;

select tests.authenticate_as(:'owner');
select results_eq($$ select count(*)::int from public.candidati $$, $$ values (1) $$,
  'chi ha creato la Scansione vede i propri Candidati');
reset role;

select * from finish();
rollback;
