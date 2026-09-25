# Supabase

Schema Postgres, policy RLS e bucket Storage dei profili autenticati (ADR-0004, ADR-0007). Progetto remoto: `ojfwicezfctlwpouudsa`.

- `migrations/`: migrazioni versionate, applicate in ordine di timestamp. Non modificare una migrazione già applicata al remoto: aggiungine una nuova (`supabase migration new <nome>`).
- `tests/database/`: test pgTAP delle policy. `helpers.psql` contiene gli helper condivisi (`\ir helpers.psql` in ogni file).

## Locale

Richiede la [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started) e Docker.

```sh
supabase start      # stack locale, applica le migrazioni
supabase test db    # esegue i test pgTAP
supabase db reset   # ricrea il DB locale da zero dalle migrazioni
supabase db lint    # controlli statici su funzioni e schema
```

Per uno stack più leggero bastano DB, Auth e Storage:
`supabase start -x realtime,studio,imgproxy,edge-runtime,logflare,vector,supavisor,mailpit,postgres-meta`.

## Remoto

```sh
supabase login
supabase link --project-ref ojfwicezfctlwpouudsa   # chiede la password del DB
supabase db push --dry-run                          # mostra le migrazioni da applicare
supabase db push
```
