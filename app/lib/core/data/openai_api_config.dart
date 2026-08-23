/// Chiave API OpenAI incorporata a build-time via `--dart-define-from-file`.
///
/// Non committata in git: vedi `dart_define.example.json` e il README per
/// come fornire il valore reale in locale. Usata solo se
/// `CoverAnalysisProviderConfig.kind` seleziona il provider OpenAI.
class OpenAiApiConfig {
  const OpenAiApiConfig._();

  static const String apiKey = String.fromEnvironment('OPENAI_API_KEY');

  static bool get isConfigured => apiKey.isNotEmpty;
}
