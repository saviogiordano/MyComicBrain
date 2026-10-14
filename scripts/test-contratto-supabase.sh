#!/usr/bin/env bash
# Esegue contro lo stack locale ciò che l'app fa su Supabase: la parte della
# suite di contratto di ComicsRepository che cambia per un Profilo
# autenticato (la Conversazione, ADR-0008) e i test di
# test/core/data/supabase/ (Storage, importazione). Richiede Docker e la
# Supabase CLI; avvia lo stack se non è già su. Argomenti extra passano a
# `flutter test`.
set -euo pipefail

radice="$(cd "$(dirname "$0")/.." && pwd)"
cd "$radice"

if ! supabase status >/dev/null 2>&1; then
  supabase start -x realtime,studio,imgproxy,edge-runtime,logflare,vector,supavisor,mailpit,postgres-meta
fi
eval "$(supabase status -o env 2>/dev/null)"

cd app
SUPABASE_TEST_URL="$API_URL" \
SUPABASE_TEST_PUBLISHABLE_KEY="$PUBLISHABLE_KEY" \
  flutter test test/core/data/contratto/profilo_contratto_test.dart \
    test/core/data/supabase/ "$@"
