#!/usr/bin/env bash
# Wrapper attorno a `dart run tool/analyze_cover.dart` che si posiziona nella
# cartella `app/` a prescindere dalla working directory di chi lo invoca —
# stesso pattern del rimosso `scripts/flutter.sh` (#106). Per questo motivo
# un percorso relativo per <percorso immagine>/--config va dato relativo ad
# `app/`, oppure passato come percorso assoluto.
#
# Uso: identico allo script Dart, es.
#   tool/analyze_cover.sh copertina.jpg
#   tool/analyze_cover.sh copertina.jpg --config tool/cover_analysis_config.json
set -euo pipefail
cd "$(dirname "$0")/.."

exec dart run tool/analyze_cover.dart "$@"
