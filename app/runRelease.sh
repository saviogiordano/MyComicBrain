#!/usr/bin/env bash
# Lancia l'app in release sull'iPhone con il login reale attivo (#171, vedi
# "Account" nel README). La chiave pubblicabile di Supabase arriva dalla
# variabile SUPABASE_PUBLISHABLE_KEY o da ~/.mycomicbrain-supabase.env, che
# contiene una riga:
#   SUPABASE_PUBLISHABLE_KEY=sb_publishable_…
# (dashboard Supabase → Project Settings → API Keys).
set -euo pipefail

file_chiave="$HOME/.mycomicbrain-supabase.env"
if [[ -z "${SUPABASE_PUBLISHABLE_KEY:-}" && -f "$file_chiave" ]]; then
  # shellcheck source=/dev/null
  source "$file_chiave"
fi
if [[ -z "${SUPABASE_PUBLISHABLE_KEY:-}" ]]; then
  echo "Manca SUPABASE_PUBLISHABLE_KEY: impostala o scrivila in $file_chiave" >&2
  exit 1
fi

cd "$(dirname "$0")"
flutter run --release -d 00008150-00064CD80220401C \
  --dart-define=ACCOUNT_LOGIN=true \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY" \
  "$@"
