#!/usr/bin/env bash
# Wrapper attorno a `flutter` che aggiunge automaticamente
# --dart-define-from-file=dart_define.json ai comandi `run` e `build`,
# se il file esiste (vedi README.md, sezione "Configurare la chiave API Claude").
#
# Uso: identico a `flutter`, es. `scripts/flutter.sh run -d "iPhone 16"`.
set -euo pipefail
cd "$(dirname "$0")/.."

args=()
if [[ "${1:-}" == "run" || "${1:-}" == "build" ]] && [[ -f dart_define.json ]]; then
  args+=(--dart-define-from-file=dart_define.json)
fi

exec flutter "$@" ${args[@]+"${args[@]}"}
