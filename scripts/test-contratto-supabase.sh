#!/usr/bin/env bash
# Esegue la suite di contratto di ComicsRepository su SupabaseComicsRepository
# contro lo stack locale (ADR-0007). Richiede Docker e la Supabase CLI; avvia
# lo stack se non è già su. Esegue anche i test propri dell'adapter
# (test/core/data/supabase/). Argomenti extra passano a `flutter test`.
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
  flutter test test/core/data/contratto/supabase_contratto_test.dart \
    test/core/data/supabase/ "$@"
