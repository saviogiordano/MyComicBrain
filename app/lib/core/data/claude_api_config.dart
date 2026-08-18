/// Chiave API Anthropic incorporata a build-time via `--dart-define-from-file`.
///
/// Non committata in git: vedi `dart_define.example.json` e il README per
/// come fornire il valore reale in locale.
class ClaudeApiConfig {
  const ClaudeApiConfig._();

  static const String apiKey = String.fromEnvironment('ANTHROPIC_API_KEY');

  static bool get isConfigured => apiKey.isNotEmpty;
}
