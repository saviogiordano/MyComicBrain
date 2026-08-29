import 'package:flutter/foundation.dart';
import 'package:mycomicbrain/core/data/assistente_client.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';
import 'package:mycomicbrain/core/domain/conversazione.dart';
import 'package:mycomicbrain/core/domain/dashboard_kpis.dart';
import 'package:mycomicbrain/core/domain/edizione_collezione.dart';
import 'package:mycomicbrain/core/domain/ricerca_assistente.dart';

/// Orchestratore dell'Assistente (§10, deciso su
/// [Implementare l'orchestratore LLM Testuale con tool-calling](https://github.com/saviogiordano/MyComicBrain/issues/132)):
/// riceve il testo dell'utente, lo persiste come Messaggio, conduce lo
/// scambio di tool-calling con [AssistenteClient] eseguendo le chiamate
/// richieste contro `ComicsRepository` (i 5 tool di ADR-0002), e persiste
/// la risposta finale — o, in caso di fallimento, il Messaggio di sistema
/// con il copy deciso su §24/#124. Nessuna traccia del tool-calling stesso
/// è persistita (deciso su #128): solo domanda e risposta finale.
///
/// Ogni turno reinvia l'intera Conversazione come contesto al modello
/// (nessun riassunto/troncamento): accettabile per una collezione
/// personale con una Conversazione unica e continua (#122), ma un limite
/// noto se la Conversazione crescesse a lungo termine oltre la finestra di
/// contesto del modello — non risolto da questo ticket.
class AssistenteOrchestrator {
  AssistenteOrchestrator({
    required ComicsRepository repository,
    required SettingsRepository settingsRepository,
    required AssistenteClient client,
  }) : _repository = repository,
       _settingsRepository = settingsRepository,
       _client = client;

  final ComicsRepository _repository;
  final SettingsRepository _settingsRepository;
  final AssistenteClient _client;

  /// `true` se il Provider AI Testuale ha i dati minimi per tentare una
  /// chiamata (§10, deciso su
  /// [UX quando il Provider AI Testuale non è configurato](https://github.com/saviogiordano/MyComicBrain/issues/123)) —
  /// pilota lo stato bloccante (banner + input disabilitato) di una futura
  /// schermata Cerca, non implementata da questo ticket.
  Future<bool> configurato() =>
      _settingsRepository.configurato(RuoloProviderAi.testuale);

  /// Invia [testo] come nuovo Messaggio dell'utente e conduce lo scambio
  /// con il Provider AI Testuale configurato fino a una risposta finale,
  /// persistita come Messaggio dell'assistente col blocco Edizioni (§125)
  /// risolto dalle chiamate a `cercaEdizioni`/`trovaDuplicati`. Un
  /// fallimento di rete/provider (#124) persiste un Messaggio di sistema al
  /// posto della risposta, mai un'eccezione che risale al chiamante.
  ///
  /// Richiede che il chiamante abbia già verificato [configurato] (§10,
  /// #123: lo stato "non configurato" è un banner bloccante che disabilita
  /// l'invio, non un Messaggio persistito) — solleva [StateError] altrimenti,
  /// come difesa contro un chiamante che non ha rispettato il contratto.
  Future<void> inviaMessaggio(String testo) async {
    if (!await configurato()) {
      throw StateError(
        'AssistenteOrchestrator.inviaMessaggio chiamato senza Provider AI '
        'Testuale configurato: il chiamante deve verificare configurato() '
        "prima dell'invio (§10, #123) — questo stato non produce un "
        'Messaggio di sistema, a differenza dei fallimenti runtime di #124.',
      );
    }

    final conversazioneId = await _repository.getOrCreaConversazione();
    await _repository.aggiungiMessaggio(
      conversazioneId: conversazioneId,
      ruolo: RuoloMessaggio.utente,
      testo: testo,
    );

    final messaggi = await _repository.watchMessaggi(conversazioneId).first;
    final storico = <TurnoConversazione>[
      for (final messaggio in messaggi)
        if (messaggio.ruolo != RuoloMessaggio.sistema)
          (ruolo: messaggio.ruolo, testo: messaggio.testo),
    ];

    final edizioniCitate = <int>{};
    final String risposta;
    try {
      risposta = await _client.chiedi(
        storico: storico,
        eseguiTool: (nome, argomenti) =>
            _eseguiTool(nome, argomenti, edizioniCitate),
      );
    } on AssistenteException catch (e) {
      debugPrint('[Assistente] ${e.sottotipo.name}: ${e.dettaglio}');
      await _repository.aggiungiMessaggio(
        conversazioneId: conversazioneId,
        ruolo: RuoloMessaggio.sistema,
        testo: copyErroreAssistente(e.sottotipo),
        sottotipoSistema: e.sottotipo,
      );
      return;
    }

    await _repository.aggiungiMessaggio(
      conversazioneId: conversazioneId,
      ruolo: RuoloMessaggio.assistente,
      testo: risposta,
      edizioneIds: edizioniCitate.toList(),
    );
  }

  /// Esegue un tool richiesto dal modello contro `ComicsRepository` (§10,
  /// ADR-0002) e accumula in [edizioniCitate] gli id delle Edizioni citate
  /// nel risultato — diventa il blocco Edizioni (variante A, #125) del
  /// Messaggio finale dell'assistente. Un nome di tool sconosciuto (non
  /// dovrebbe accadere: i client offrono solo [assistenteTools] al modello)
  /// ritorna un oggetto di errore invece di sollevare, lasciando al modello
  /// la possibilità di recuperare con una risposta in linguaggio naturale
  /// (§24, comportamento imposto da [assistentePromptSistema]).
  Future<Map<String, Object?>> _eseguiTool(
    String nome,
    Map<String, Object?> argomenti,
    Set<int> edizioniCitate,
  ) async {
    switch (nome) {
      case 'cercaEdizioni':
        final risultato = await _repository.cercaEdizioni(
          titolo: argomenti['titolo'] as String?,
          serie: argomenti['serie'] as String?,
          autore: argomenti['autore'] as String?,
          editore: argomenti['editore'] as String?,
          personaggio: argomenti['personaggio'] as String?,
          tag: argomenti['tag'] as String?,
          numero: (argomenti['numero'] as num?)?.toInt(),
          isbn: argomenti['isbn'] as String?,
          testoLibero: argomenti['testoLibero'] as String?,
        );
        edizioniCitate.addAll(risultato.edizioni.map((e) => e.edizioneId));
        return {
          'edizioni': [for (final e in risultato.edizioni) _edizioneJson(e)],
          'totale': risultato.totale,
          'troncato': risultato.troncato,
        };

      case 'numeriMancantiSerie':
        final nomeSerie = argomenti['nomeSerie']! as String;
        final candidati = await _repository.cercaSerie(nomeSerie);
        if (candidati.isEmpty) {
          return {'trovata': false};
        }
        if (candidati.length > 1) {
          return {
            'ambiguo': true,
            'candidati': [for (final s in candidati) s.name],
          };
        }
        final serieId = candidati.single.id;
        final incomplete = await _repository.watchSerieIncomplete().first;
        SerieIncompleta? serie;
        for (final s in incomplete) {
          if (s.serieId == serieId) {
            serie = s;
            break;
          }
        }
        if (serie == null) {
          return {
            'trovata': true,
            'completa': true,
            'numeriMancanti': <int>[],
          };
        }
        return {
          'trovata': true,
          'completa': false,
          'numeriTotali': serie.numeriTotali,
          'numeriMancanti': serie.numeriMancanti,
        };

      case 'conteggioPer':
        final campo = switch (argomenti['campo'] as String?) {
          'anno' => CampoConteggio.anno,
          _ => CampoConteggio.editore,
        };
        return _repository.conteggioPer(campo);

      case 'serieQuasiComplete':
        final serie = await _repository.serieQuasiComplete();
        return {
          'serie': [
            for (final s in serie)
              {
                'nome': s.nome,
                'numeriPosseduti': s.numeriPosseduti,
                'numeriTotali': s.numeriTotali,
                'numeriMancanti': s.numeriMancanti,
              },
          ],
        };

      case 'trovaDuplicati':
        final duplicati = await _repository.trovaDuplicati();
        edizioniCitate.addAll(duplicati.map((d) => d.edizioneId));
        return {
          'duplicati': [
            for (final d in duplicati)
              {
                'titolo': d.titolo,
                'serie': d.serieName,
                'numero': d.issueNumberLabel,
                'editore': d.publisher,
                'copiePossedute': d.copiePossedute,
              },
          ],
        };

      default:
        return {'errore': 'Tool sconosciuto: $nome'};
    }
  }

  Map<String, Object?> _edizioneJson(EdizioneCollezioneIndice e) => {
    'titolo': e.titolo,
    'serie': e.serieName,
    'numero': e.issueNumberLabel ?? e.issueNumber?.toString(),
    'editore': e.publisher,
    'anno': e.year,
  };
}
