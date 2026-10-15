#!/usr/bin/env bash
# Lancia l'app in release sull'iPhone.
set -euo pipefail

cd "$(dirname "$0")"
flutter run --release -d 00008150-00064CD80220401C "$@"
