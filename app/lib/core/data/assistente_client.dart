import 'package:mycomicbrain/core/domain/conversazione.dart';

/// Prompt di sistema condiviso fra i client del Provider AI Testuale (§10,
/// ADR-0002): impone il grounding via tool-calling (mai inventare dati non
/// prodotti da un tool) e il comportamento di fallback in linguaggio
/// naturale per query non interpretabili o senza copertura (§24, deciso su
/// #124) — quest'ultimo caso non è un errore tecnico, quindi non è
/// modellato come eccezione: è il modello stesso a rispondere così quando
/// istruito da questo prompt.
const assistentePromptSistema =
    "Sei l'Assistente di ricerca di MyComicBrain, un catalogo personale di "
    'fumetti. Rispondi sempre in italiano, in linguaggio naturale, in modo '
    'conciso. Usa esclusivamente i tool disponibili per rispondere su '
    "contenuti della collezione dell'utente: non inventare mai fumetti, "
    'numeri, editori, serie o conteggi che non provengono da un risultato '
    'di tool. Se nessuna chiamata disponibile copre la richiesta, o una '
    'chiamata non produce risultati utili, rispondi con una frase simile a '
    '"Non sono riuscito a trovare questa informazione nella tua collezione. '
    'Puoi provare a riformulare?" invece di un errore tecnico o di una '
    "risposta inventata. Se un nome di serie è ambiguo (più corrispondenze "
    "possibili), chiedi all'utente quale intende invece di sceglierne una a "
    'caso.';

const Map<String, Object?> _nessunParametro = {
  'type': 'object',
  'properties': <String, Object?>{},
  'additionalProperties': false,
};

const Map<String, Object?> _cercaEdizioniParametri = {
  'type': 'object',
  'properties': {
    'titolo': {'type': 'string', 'description': 'Titolo, anche parziale.'},
    'serie': {
      'type': 'string',
      'description': 'Nome della serie/collana, anche parziale.',
    },
    'autore': {'type': 'string', 'description': 'Nome di un autore.'},
    'editore': {'type': 'string', 'description': 'Nome dell\'editore.'},
    'personaggio': {
      'type': 'string',
      'description': 'Nome di un personaggio.',
    },
    'tag': {'type': 'string', 'description': 'Un tag associato.'},
    'numero': {
      'type': 'integer',
      'description': "Numero esatto dell'albo nella serie.",
    },
    'isbn': {'type': 'string', 'description': 'ISBN o codice EAN esatto.'},
    'testoLibero': {
      'type': 'string',
      'description':
          'Ricerca generica su più campi (titolo, serie, editore, autori, '
          'personaggi, tag) da usare quando nessun filtro specifico sopra è '
          'applicabile.',
    },
  },
  'additionalProperties': false,
};

const Map<String, Object?> _numeriMancantiSerieParametri = {
  'type': 'object',
  'properties': {
    'nomeSerie': {
      'type': 'string',
      'description': 'Nome della serie, anche parziale.',
    },
  },
  'required': ['nomeSerie'],
  'additionalProperties': false,
};

const Map<String, Object?> _conteggioPerParametri = {
  'type': 'object',
  'properties': {
    'campo': {
      'type': 'string',
      'enum': ['editore', 'anno'],
      'description': 'Il campo su cui aggregare il conteggio.',
    },
  },
  'required': ['campo'],
  'additionalProperties': false,
};

/// Una funzione esposta all'LLM Testuale (§10, schema deciso su ADR-0002 /
/// [Schema del tool-calling dell'Assistente sopra ComicsRepository](https://github.com/saviogiordano/MyComicBrain/issues/126)).
/// [parametri] è lo schema JSON standard dei parametri (non lo schema
/// "strict mode" di [coverAnalysisJsonSchema] — i parametri di un tool
/// restano opzionali secondo la semantica JSON Schema ordinaria, coerente
/// con come li accettano sia le function OpenAI/OpenRouter/Locale sia
/// `input_schema` di Claude).
class AssistenteTool {
  const AssistenteTool(this.nome, this.descrizione, this.parametri);

  final String nome;
  final String descrizione;
  final Map<String, Object?> parametri;
}

/// I 5 tool dell'Assistente (§10, ADR-0002), stessa lista per tutti i
/// provider: ciascun client la traduce nel proprio formato di function
/// calling. L'esecuzione reale (contro `ComicsRepository`) è responsabilità
/// dell'orchestratore (#132), mai dei client.
const List<AssistenteTool> assistenteTools = [
  AssistenteTool(
    'cercaEdizioni',
    'Cerca le Edizioni possedute nella collezione, filtrando per uno o più '
        'campi opzionali combinati in AND.',
    _cercaEdizioniParametri,
  ),
  AssistenteTool(
    'numeriMancantiSerie',
    'Elenca i numeri mancanti di una serie posseduta, dato il suo nome.',
    _numeriMancantiSerieParametri,
  ),
  AssistenteTool(
    'conteggioPer',
    'Conta le Edizioni possedute aggregate per editore o per anno di '
        'pubblicazione.',
    _conteggioPerParametri,
  ),
  AssistenteTool(
    'serieQuasiComplete',
    "Elenca le serie possedute quasi complete (almeno l'80% dei numeri "
        'posseduti, non completa).',
    _nessunParametro,
  ),

  AssistenteTool(
    'trovaDuplicati',
    'Elenca le Edizioni possedute in più di una copia.',
    _nessunParametro,
  ),
];

/// Numero massimo di round di tool-calling per una singola domanda
/// dell'utente, condiviso fra i client: limita un loop che non converge mai
/// verso una risposta testuale finale — trattato come un errore di
/// [SottotipoSistema.erroreProvider] ("risposta inattesa"), non un problema
/// di rete.
const assistenteMaxRoundTool = 6;

/// Timeout di ogni singola chiamata HTTP al Provider AI Testuale, condiviso
/// fra i client — stesso principio di [coverAnalysisTimeout]: senza un
/// timeout esplicito una richiesta senza risposta lascia la Conversazione
/// bloccata a tempo indeterminato invece di produrre il Messaggio di
/// sistema di rete (§24, deciso su #124).
const assistenteTimeout = Duration(seconds: 45);

/// Un turno già scambiato nella Conversazione (§10), nel formato minimo che
/// i client convertono nel proprio schema di messaggi. Solo
/// [RuoloMessaggio.utente]/[RuoloMessaggio.assistente]: i Messaggi di
/// sistema (§24) non fanno parte del contesto inviato al modello — sono
/// bolle informative per l'utente, non dialogo reale.
typedef TurnoConversazione = ({RuoloMessaggio ruolo, String testo});

/// Una chiamata al Provider AI Testuale fallita — rete assente o risposta
/// del provider inattesa/con errore (§24, deciso su #124). [sottotipo]
/// distingue le due categorie di copy decise su #124: solo
/// [SottotipoSistema.erroreRete] o [SottotipoSistema.erroreProvider], mai
/// [SottotipoSistema.infoSttFallback] (non generato da questo client).
class AssistenteException implements Exception {
  AssistenteException(this.sottotipo, this.dettaglio);

  final SottotipoSistema sottotipo;

  /// Dettaglio tecnico grezzo (per log/debug), mai mostrato all'utente: il
  /// copy utente-facing è deciso centralmente dall'orchestratore da
  /// [sottotipo] (§24), non da questo messaggio.
  final String dettaglio;

  @override
  String toString() => 'AssistenteException(${sottotipo.name}): $dettaglio';
}

/// Copy utente-facing di un [AssistenteException] per [sottotipo] (§24,
/// deciso su #124) — unica fonte di verità, condivisa fra il Messaggio di
/// sistema di `AssistenteOrchestrator` e il bottone "Verifica connessione"
/// della sezione Provider AI Testuale in Impostazioni (#129).
String copyErroreAssistente(SottotipoSistema sottotipo) => switch (sottotipo) {
  SottotipoSistema.erroreRete =>
    'Connessione assente. Riprova quando sei di nuovo online.',
  SottotipoSistema.erroreProvider =>
    'Il Provider AI Testuale non risponde correttamente. Verifica la '
        'configurazione in Impostazioni.',
  SottotipoSistema.infoSttFallback => throw StateError(
    'infoSttFallback non è mai generato da AssistenteClient — riservato '
    'al fallback STT (#120), fuori scope di questa mappatura.',
  ),
};

/// Interfaccia comune dei client del Provider AI Testuale (§10, uno per
/// brand come [CoverAnalysisClient] per il Visivo) — il provider effettivo
/// è selezionato a runtime dalle Impostazioni (RuoloProviderAi.testuale).
abstract interface class AssistenteClient {
  /// Conduce l'intero scambio di tool-calling per una singola domanda
  /// dell'utente — [storico] è la Conversazione già persistita fino
  /// all'ultimo Messaggio (che deve essere quello dell'utente appena
  /// inviato) — e ritorna il solo testo della risposta finale
  /// dell'Assistente. Ogni chiamata a un tool richiesta dal modello passa
  /// per [eseguiTool] (nome del tool, argomenti già decodificati dal JSON
  /// del modello) fornito dal chiamante (l'orchestratore, #132) — il client
  /// non conosce `ComicsRepository`. Solleva [AssistenteException] su
  /// fallimento di rete/provider o se il numero di round supera
  /// [assistenteMaxRoundTool].
  Future<String> chiedi({
    required List<TurnoConversazione> storico,
    required Future<Map<String, Object?>> Function(
      String nomeTool,
      Map<String, Object?> argomenti,
    )
    eseguiTool,
  });

  /// Verifica reale della configurazione corrente: una chiamata minima al
  /// provider per controllare che API key e modello siano validi, senza
  /// tool-calling — stesso pattern di `CoverAnalysisClient.verificaConnessione`
  /// (usata dal bottone "Verifica configurazione" di una futura sezione
  /// Provider AI Testuale in Impostazioni). Ritorna normalmente se la
  /// configurazione è valida, altrimenti solleva [AssistenteException].
  Future<void> verificaConnessione();
}
