/// Configurazione del login (#171).
abstract final class AuthConfig {
  /// URL e chiave pubblicabile del progetto `ojfwicezfctlwpouudsa`. La
  /// chiave è pubblica per costruzione (le tabelle sono protette da RLS);
  /// entrambi si possono sostituire con `--dart-define`.
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ojfwicezfctlwpouudsa.supabase.co',
  );
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_kV9o89Xp2hfT4ajGFT_RSg_TOeaJi1y',
  );

  /// Deep link di ritorno per conferma email e Apple su Android (#168 §3).
  static const redirectUrl = 'com.saviogiordano.mycomicbrain://login-callback';

  // Client OAuth Google (pubblici, risoluzione di #169).
  static const googleWebClientId =
      '864729242544-fhlh5tgon6eog7dp1pfemgg80ijktqs4.apps.googleusercontent.com';
  static const googleIosClientId =
      '864729242544-irrm80b5cd3fqceb8rkpsih4b8sibcee.apps.googleusercontent.com';
}
