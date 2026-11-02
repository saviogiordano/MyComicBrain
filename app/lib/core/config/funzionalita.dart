import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Funzionalità accese o spente alla compilazione.
abstract final class Funzionalita {
  /// Account, Sincronizzazione e tutto ciò che passa da Supabase. Spento
  /// (`--dart-define=CLOUD_ENABLED=false`) l'app vive solo in Modalità
  /// locale: niente benvenuto con l'account, niente login, Supabase mai
  /// inizializzato. È la build per gli store finché il cloud non è pronto;
  /// chi la usa ritroverà i suoi dati nel flusso di importazione
  /// (ADR-0005) quando il cloud verrà acceso.
  static const cloud = bool.fromEnvironment(
    'CLOUD_ENABLED',
    defaultValue: true,
  );
}

/// [Funzionalita.cloud] per i widget, sostituibile nei test.
final cloudAbilitatoProvider = Provider<bool>((ref) => Funzionalita.cloud);
