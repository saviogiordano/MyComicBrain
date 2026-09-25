-- Cancellazione account, trasferimento di proprietà, inviti (ADR-0004).
begin;
\ir helpers.psql
select plan(13);

select tests.create_user('owner@example.com') as owner \gset
select tests.create_user('editor@example.com') as editor \gset
select tests.create_user('ospite@example.com') as ospite \gset
select tests.create_user('solo@example.com') as solo \gset
select tests.collection_of(:'owner') as col \gset
select tests.collection_of(:'solo') as solo_col \gset

insert into public.collection_members (collection_id, user_id, role) values (:'col', :'editor', 'editor');

-- Trasferimento di proprietà.
select tests.authenticate_as(:'editor');
select throws_ok(
  format($$ select public.transfer_collection_ownership(%L, %L) $$, :'col', :'editor'),
  'P0001', 'Solo il Proprietario può trasferire la proprietà.',
  'un Editor non si prende la proprietà');
reset role;

select tests.authenticate_as(:'ospite');
select throws_ok(
  format($$ select public.transfer_collection_ownership(%L, %L) $$, :'col', :'ospite'),
  'P0001', 'Solo il Proprietario può trasferire la proprietà.',
  'un non-membro non si prende la proprietà (member_role = null)');
reset role;

select tests.authenticate_as(:'owner');
select throws_ok(
  format($$ select public.transfer_collection_ownership(%L, %L) $$, :'col', :'ospite'),
  'P0001', 'Il nuovo Proprietario deve essere un altro membro della collezione.',
  'la proprietà non passa a chi non è membro');
reset role;

-- Il Proprietario con collaboratori non può cancellare l'account.
select throws_ok(
  format($$ delete from auth.users where id = %L $$, :'owner'),
  'P0001', 'Trasferisci la proprietà della collezione o rimuovi i collaboratori prima di eliminare l''account.',
  'cancellazione del Proprietario con collaboratori bloccata');

select tests.authenticate_as(:'owner');
select lives_ok(
  format($$ select public.transfer_collection_ownership(%L, %L) $$, :'col', :'editor'),
  'il Proprietario trasferisce la proprietà a un membro');
reset role;

select results_eq(
  format($$ select user_id::text, role from public.collection_members where collection_id = %L order by role $$, :'col'),
  format($$ values (%L, 'owner'::public.collection_role), (%L, 'editor'::public.collection_role) $$, :'editor', :'owner'),
  'dopo il trasferimento: un solo Proprietario, l''ex Proprietario è Editor');

-- Inviti.
select tests.authenticate_as(:'editor');
insert into public.collection_invites (collection_id, role, token)
values (:'col', 'viewer', '00000000-0000-0000-0000-000000000001');
insert into public.collection_invites (collection_id, role, token, expires_at)
values (:'col', 'viewer', '00000000-0000-0000-0000-000000000002', now() - interval '1 day');
reset role;

select tests.authenticate_as(:'ospite');
select is_empty($$ select 1 from public.collection_invites $$,
  'l''invitato non legge la tabella degli inviti');
select throws_ok(
  $$ select public.accept_collection_invite('00000000-0000-0000-0000-000000000002') $$,
  'P0001', 'Invito non valido o scaduto',
  'un invito scaduto non si accetta');
select is(
  public.accept_collection_invite('00000000-0000-0000-0000-000000000001'),
  'viewer'::public.collection_role,
  'l''invitato accetta con il ruolo dell''invito');
select throws_ok(
  $$ select public.accept_collection_invite('00000000-0000-0000-0000-000000000001') $$,
  'P0001', 'Invito non valido o scaduto',
  'un invito già accettato non si riusa');
reset role;

-- Utente unico membro della propria Collezione: la cancellazione elimina
-- la Collezione con i suoi dati e anonimizza il Profilo.
insert into public.opere (collection_id, title) values (:'solo_col', 'Zagor');
delete from auth.users where id = :'solo';

select is_empty(format($$ select 1 from public.collections where id = %L $$, :'solo_col'),
  'la Collezione dell''utente eliminato non esiste più');
select is_empty(format($$ select 1 from public.opere where collection_id = %L $$, :'solo_col'),
  '... né i suoi dati');
select results_eq(
  format($$ select display_name, deleted_at is not null from public.profiles where id = %L $$, :'solo'),
  $$ values ('Utente eliminato', true) $$,
  'il Profilo sopravvive anonimizzato');

select * from finish();
rollback;
