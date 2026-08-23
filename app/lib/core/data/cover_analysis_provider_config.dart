/// Il provider AI usato dalla pipeline di Analisi Copertina (§6.1, §6.2).
enum CoverAnalysisProviderKind { claude, openai }

/// Quale provider è selezionato per [CoverAnalysisProviderKind], scelto a
/// build-time via `--dart-define=COVER_ANALYSIS_PROVIDER=claude|openai`
/// (default: `claude`, il provider originale della mappa #27/#46). Nessuna
/// UI per la scelta — fuori scope, coerente con "nessuna nuova UI" deciso
/// per la mappa #46 su cui il provider alternativo è stato aggiunto.
class CoverAnalysisProviderConfig {
  const CoverAnalysisProviderConfig._();

  static const String _raw = String.fromEnvironment(
    'COVER_ANALYSIS_PROVIDER',
    defaultValue: 'claude',
  );

  static CoverAnalysisProviderKind get kind => switch (_raw) {
    'openai' => CoverAnalysisProviderKind.openai,
    _ => CoverAnalysisProviderKind.claude,
  };
}
