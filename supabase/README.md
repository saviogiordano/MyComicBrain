# Supabase

Schema Postgres, policy RLS e bucket Storage dei profili autenticati (ADR-0004, ADR-0007). Progetto remoto: `ojfwicezfctlwpouudsa`.

- `migrations/`: migrazioni versionate, applicate in ordine di timestamp. Non modificare una migrazione già applicata al remoto: aggiungine una nuova (`supabase migration new <nome>`).
- `tests/database/`: test pgTAP delle policy. `helpers.psql` contiene gli helper condivisi (`\ir helpers.psql` in ogni file).
- `functions/`: Edge Function (Deno). `elimina-account` cancella l'account dall'app (#172): file Storage, revoca del token Apple, poi `auth.admin.deleteUser`, che fa scattare il trigger di ADR-0004.

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

## Edge Function

```sh
# test della logica (senza Deno installato: via Docker)
docker run --rm -v "$PWD/supabase/functions:/f" -w /f/elimina-account denoland/deno:2.5.6 test
supabase functions serve                     # in locale, sullo stack avviato
supabase functions deploy elimina-account    # sul remoto (dopo `supabase link`)
```

`elimina-account` richiede i secret Apple per revocare il token Sign in with Apple. Il client è il bundle id, perché l'app manda il code del foglio Apple nativo; la chiave è la stessa `.p8` del provider Apple:

```sh
supabase secrets set \
  APPLE_TEAM_ID=5Y43GX53B5 \
  APPLE_KEY_ID=DN59A5Z8HZ \
  APPLE_CLIENT_ID=com.saviogiordano.mycomicbrain.mycomicbrain \
  APPLE_PRIVATE_KEY="$(cat ~/.mycomicbrain-secrets/apple-signin/AuthKey_DN59A5Z8HZ.p8)"
```

## Provider di login

Si configurano dal dashboard, non con `supabase config push`, che sovrascriverebbe tutta la configurazione Auth remota con quella di `config.toml`. Le wizard guidano i passi manuali e salvano gli identificatori in un env file in home, fuori dal repo:

- `scripts/setup-apple-signin.sh`: Sign in with Apple (`~/.mycomicbrain-apple-signin.env`).
- `scripts/setup-google-signin.sh`: Google Sign-In (`~/.mycomicbrain-google-signin.env`). Rilanciala quando esisterà la chiave di release Android, per aggiungere il relativo client.
