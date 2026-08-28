import 'package:mycomicbrain/core/domain/edizione_collezione.dart';

/// Ruolo di un Messaggio nella Conversazione dell'Assistente (§10/§24,
/// deciso su #124/#128): domanda dell'utente, risposta dell'Assistente, o
/// messaggio di sistema (errore/fallback STT). Tutti Messaggi a tutti gli
/// effetti — vedi `CONTEXT.md` — non un concetto separato.
enum RuoloMessaggio { utente, assistente, sistema }

/// Sottotipo del Messaggio di sistema (§24, deciso su #124/#128) — le 3
/// varianti di copy: errore di rete, errore del Provider AI Testuale
/// (con CTA "Vai a Impostazioni"), fallback STT Android in rete.
/// Valorizzato solo quando [Messaggio.ruolo] è [RuoloMessaggio.sistema].
enum SottotipoSistema { erroreRete, erroreProvider, infoSttFallback }

/// Un Messaggio della Conversazione, letto per la schermata Cerca (§10,
/// deciso su #128). [edizioni] è il blocco strutturato di un Messaggio
/// assistente (variante A, #125) — riferimento vivo risolto a runtime da
/// `ComicsRepository.watchMessaggi`, mai denormalizzato: un'Edizione
/// cancellata dopo il fatto è semplicemente assente, nessun placeholder.
class Messaggio {
  const Messaggio({
    required this.id,
    required this.ruolo,
    required this.testo,
    required this.createdAt,
    this.sottotipoSistema,
    this.edizioni = const [],
  });

  final int id;
  final RuoloMessaggio ruolo;
  final SottotipoSistema? sottotipoSistema;
  final String testo;
  final DateTime createdAt;
  final List<EdizioneCollezioneIndice> edizioni;
}
