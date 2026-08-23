/// Chiave API Comic Vine incorporata a build-time via `--dart-define-from-file`.
///
/// Non committata in git: vedi `dart_define.example.json` e il README per
/// come fornire il valore reale in locale. Usata da `ComicVineHttpClient`
/// come database esterno di fallback per l'Identificazione del fumetto
/// (§6.3, deciso su #51).
class ComicVineApiConfig {
  const ComicVineApiConfig._();

  static const String apiKey = String.fromEnvironment('COMIC_VINE_API_KEY');

  static bool get isConfigured => apiKey.isNotEmpty;
}
