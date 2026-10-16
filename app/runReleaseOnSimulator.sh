#!/usr/bin/env bash
# Lancia l'app sul Simulator iOS.
set -euo pipefail

cd "$(dirname "$0")"
flutter run -d 054F9AB9-92C1-4943-A89B-C01650A331EB "$@"
