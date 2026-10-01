/// Configurazione del login (#171). Il login resta dietro un flag di
/// sviluppo finché il porting Supabase non è completo (ADR-0007, #181):
/// senza `--dart-define=ACCOUNT_LOGIN=true` l'app si comporta come prima.
abstract final class AuthConfig {
  static const loginAbilitato = bool.fromEnvironment('ACCOUNT_LOGIN');

  /// URL e chiave pubblicabile del progetto `ojfwicezfctlwpouudsa`, passati
  /// con `--dart-define` insieme al flag (vedi `app/README.md`).
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ojfwicezfctlwpouudsa.supabase.co',
  );
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  /// Deep link di ritorno per conferma email e Apple su Android (#168 §3).
  static const redirectUrl = 'com.saviogiordano.mycomicbrain://login-callback';

  // Client OAuth Google (pubblici, risoluzione di #169).
  static const googleWebClientId =
      '864729242544-fhlh5tgon6eog7dp1pfemgg80ijktqs4.apps.googleusercontent.com';
  static const googleIosClientId =
      '864729242544-irrm80b5cd3fqceb8rkpsih4b8sibcee.apps.googleusercontent.com';
}
