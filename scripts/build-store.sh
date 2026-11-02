#!/usr/bin/env bash
#
# Build per App Store e Play Store senza cloud (CLOUD_ENABLED=false): l'app
# vive solo in Modalità locale, senza account né Sincronizzazione. Vedi
# `app/lib/core/config/funzionalita.dart`.
#
# Uso: scripts/build-store.sh [ios|android|tutti]   (default: tutti)
# Gli argomenti dopo il primo passano a `flutter build`, ad es.
#   scripts/build-store.sh ios --build-number=7

set -euo pipefail

cd "$(dirname "$0")/../app"

piattaforma="${1:-tutti}"
shift || true
flag=(--release --dart-define=CLOUD_ENABLED=false)

case "$piattaforma" in
  ios) flutter build ipa "${flag[@]}" "$@" ;;
  android) flutter build appbundle "${flag[@]}" "$@" ;;
  tutti)
    flutter build ipa "${flag[@]}" "$@"
    flutter build appbundle "${flag[@]}" "$@"
    ;;
  *)
    echo "Piattaforma sconosciuta: $piattaforma (ios|android|tutti)" >&2
    exit 1
    ;;
esac
