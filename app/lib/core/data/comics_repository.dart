import 'dart:io';

import 'package:drift/drift.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/importazione_schema.dart';
import 'package:mycomicbrain/core/data/percorso_locale.dart' as percorso_locale;
import 'package:mycomicbrain/core/domain/analisi_copertina.dart';
import 'package:mycomicbrain/core/domain/catalogo_stampabile.dart';
import 'package:mycomicbrain/core/domain/conversazione.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/creator.dart';
import 'package:mycomicbrain/core/domain/dashboard_kpis.dart';
import 'package:mycomicbrain/core/domain/edizione_catalogo.dart';
import 'package:mycomicbrain/core/domain/edizione_collezione.dart';
import 'package:mycomicbrain/core/domain/edizione_dettaglio.dart';
import 'package:mycomicbrain/core/domain/esportazione.dart';
import 'package:mycomicbrain/core/domain/formato.dart';
import 'package:mycomicbrain/core/domain/genere.dart';
import 'package:mycomicbrain/core/domain/identificazione.dart';
import 'package:mycomicbrain/core/domain/ricerca_assistente.dart';
import 'package:mycomicbrain/core/domain/serie_dettaglio.dart';
import 'package:mycomicbrain/core/domain/serie_lista.dart';

/// Espone il dominio del catalogo (opera/edizione/copia, §36) all'UI senza
/// farle vedere il backend: prende e restituisce tipi di dominio. Fanno
/// ancora eccezione le righe drift restituite da [cercaCreator],
/// [cercaCharacter], [cercaTag], [cercaSerie] e
/// [analisiCopertinaPerScansione] (`CreatorData`, `CharacterData`, ...).
///
/// Interfaccia del seam del layer dati (ADR-0007), implementata da
/// `DriftComicsRepository` sia per la Modalità locale sia per la Replica
/// locale di un Profilo autenticato (ADR-0008), scelte da
/// `comicsRepositoryProvider` in base alla sessione. Per la Replica la
/// Conversazione sta su Supabase (`ArchivioConversazione`). Ogni metodo è
/// coperto dalla suite di contratto (`test/core/data/contratto/`).
abstract interface class ComicsRepository {
  /// Ci sono dati in Modalità locale da importare (ADR-0005)? Catalogo
  /// (Opere, Serie, Creator, Personaggi, Tag) o Scansioni — non la
  /// Conversazione, che non migra. Usato dal login (#171) per decidere se la
  /// Modalità locale si esaurisce subito.
  Future<bool> haDatiDaImportare();

  // --- Scrittura (usata dai test per costruire fixture; superficie minima
  // per il catalogo — nessuna schermata di questa mappa scrive dati). ---

  Future<String> aggiungiOpera({required String title, DateTime? createdAt});

  /// Riusa una Serie esistente con lo stesso nome (case-insensitive, a meno
  /// di spazi iniziali/finali) se c'è, altrimenti ne crea una nuova — a
  /// differenza di [aggiungiCreator] (nessun controllo di univocità, #64),
  /// qui la deduplica è necessaria: una Serie è un raggruppamento e i KPI
  /// "serie"/"serie complete"/"numeri mancanti" la contano per riga, quindi
  /// una riga duplicata per scansione (es. più numeri della stessa collana)
  /// gonfiava il conteggio serie invece di aggregarle.
  Future<String> aggiungiSerie({
    required String name,
    int? totalIssues,
    String? issn,
  });

  /// La Serie da dare all'Edizione [edizioneId], oggi nella Serie
  /// [serieId], quando nella Modifica della Scheda il nome della Serie
  /// diventa [nome]: se [serieId] contiene solo questa Edizione e nessun'altra
  /// Serie si chiama già [nome], la rinomina sul posto (numero totale, ISSN e
  /// cover restano); altrimenti è [aggiungiSerie] con [nome]. La Serie
  /// lasciata vuota la cancella poi [aggiornaEdizione].
  Future<String> nomeSerieDiEdizione({
    required String edizioneId,
    required String serieId,
    required String nome,
  });

  /// Ripara i dati creati prima della deduplica di [aggiungiSerie]: unisce
  /// le Serie con lo stesso nome (case-insensitive, a meno di spazi) in
  /// un'unica riga — quella con l'id più basso (la prima creata) — spostando
  /// le Edizioni delle altre sulla superstite e cancellando le righe di
  /// troppo. Idempotente e a costo trascurabile su una collezione personale,
  /// va richiamata ad ogni avvio invece che tracciata come "già eseguita
  /// una volta".
  Future<void> unisciSerieDuplicate();

  Future<String> aggiungiEdizione({
    required String operaId,
    String? serieId,
    String? publisher,
    int? issueNumber,
    String? issueNumberLabel,
    String? coverImage,
    String? releaseDate,
    String? coverPrice,
    int? pageCount,
    String? language,
    String? color,
    String? ean,
    String? volume,
    String? description,
    String? printingType,
    String? classificazione,
    int? year,
    FormatoEdizione? format,
    DateTime? createdAt,
  });

  Future<String> aggiungiCopia({
    required String edizioneId,
    required StatoCopia status,
    StatoLettura? readingStatus,
    CondizioneCopia? condition,
    double? purchasePrice,
    ValutaPrezzo? purchasePriceCurrency,
    DateTime? purchaseDate,
    String? seller,
    String? location,
    String? notes,
    double? valutazione,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? scansioneId,
  });

  /// Cerca Creator esistenti per nome (match parziale, per l'autocomplete
  /// della Scheda — vedi "Not yet specified" sulla mappa #63).
  Future<List<CreatorData>> cercaCreator(String query);

  /// Crea un nuovo Creator. Nessun controllo di univocità sul nome (#64).
  Future<String> aggiungiCreator(String name);

  /// Collega un Creator a un'Edizione con un ruolo. Ammessi più Creator con
  /// lo stesso ruolo sulla stessa Edizione e lo stesso Creator con ruoli
  /// diversi (#64).
  Future<void> collegaCreatorAEdizione({
    required String edizioneId,
    required String creatorId,
    required RuoloCreator ruolo,
  });

  /// Rimuove un collegamento Creator↔Edizione (riga ComicCreator).
  Future<void> rimuoviCreatorDaEdizione(String comicCreatorId);

  /// Legge tutti i Creator collegati a un'Edizione con il relativo ruolo,
  /// per il rendering della Scheda (§8.1).
  Future<List<CreatorConRuolo>> autoriDiEdizione(String edizioneId);

  // --- Personaggio (§9, deciso su #84) — stesso pattern di Creator/#64. ---

  /// Cerca Personaggi esistenti per nome (match parziale, per l'autocomplete
  /// dell'asse Personaggio della Collezione).
  Future<List<CharacterData>> cercaCharacter(String query);

  /// Crea un nuovo Personaggio. Nessun controllo di univocità sul nome
  /// (#84, stesso pattern di [aggiungiCreator]).
  Future<String> aggiungiCharacter(String name);

  /// Collega un Personaggio a un'Edizione.
  Future<void> collegaCharacterAEdizione({
    required String edizioneId,
    required String characterId,
  });

  /// Rimuove un collegamento Personaggio↔Edizione (riga ComicCharacter).
  Future<void> rimuoviCharacterDaEdizione(String comicCharacterId);

  // --- Tag personalizzati (§9, deciso su #82) — stesso pattern di Creator/#64. ---

  /// Cerca Tag esistenti per nome (match parziale, per l'autocomplete
  /// dell'asse Tag della Collezione).
  Future<List<TagTableData>> cercaTag(String query);

  /// Crea un nuovo Tag. Nessun vincolo di univocità sul nome (#82).
  Future<String> aggiungiTag(String name);

  /// Collega un Tag a un'Edizione.
  Future<void> collegaTagAEdizione({
    required String edizioneId,
    required String tagId,
  });

  /// Rimuove un collegamento Tag↔Edizione (riga EdizioneTag).
  Future<void> rimuoviTagDaEdizione(String edizioneTagId);

  // --- Genere (§9, deciso su #84) — enum multi-valore, sostituzione intera. ---

  /// Sostituisce l'intero insieme dei Generi di un'Edizione con [generi] —
  /// a differenza di Autore/Personaggio/Tag (collegamenti singoli aggiunti/
  /// rimossi uno a uno), il Genere è un piccolo enum chiuso: la UI lo tratta
  /// come un insieme di chip selezionate, non come voci con un proprio id da
  /// tracciare singolarmente.
  Future<void> impostaGeneriEdizione({
    required String edizioneId,
    required Set<GenereEdizione> generi,
  });

  /// Persiste una Scansione confermata (revisione ritaglio/rotazione, #24).
  /// Il riconoscimento (§6.3, collegamento a un'edizione) resta fuori scope
  /// di questa mappa — l'Analisi Copertina (§6.1, §6.2) parte separatamente,
  /// vedi [idScansionePerImmagine]/[avviaAnalisiCopertina].
  Future<String> aggiungiScansione({
    required String image,
    DateTime? createdAt,
  });

  /// L'id della Scansione salvata con questo percorso immagine — usato dalla
  /// pipeline di analisi OCR (#32) per collegare il batch di file in uscita
  /// dal riepilogo alla riga già persistita in `Scansioni` da [aggiungiScansione].
  Future<String> idScansionePerImmagine(String image);

  /// Il valore da passare come `coverImage` di [aggiungiEdizione] per usare
  /// la cover scansionata di questa Scansione (§6.3, deciso su #63) —
  /// `InserisciManualmentePage` non ha altrimenti nessuna cover da mostrare,
  /// a differenza di un Candidato che ne porta una propria (ComicVine o
  /// un'Edizione interna già catalogata). Relativizzato alla cartella base
  /// come `_coverImagePerCandidato`: `ScansioneStorage` salva `image` come
  /// percorso *assoluto* (sotto `scansioni/`, riconosciuto comunque da
  /// [percorso_locale.risolvi] anche non relativizzato), ma le nuove righe
  /// devono restare coerenti col formato relativo usato da qui in avanti.
  Future<String> coverImagePerScansione(String scansioneId);

  /// Rimuove una Scansione non ancora inviata alla pipeline (swipe-to-delete
  /// nel riepilogo, prima di "Fine") — solo la riga `Scansioni`: a questo
  /// punto del flusso non esiste ancora nessuna `AnalisiCopertina` collegata
  /// da ripulire. Il file immagine salvato va eliminato a parte con
  /// `ScansioneStorage.elimina`, non è responsabilità del repository.
  Future<void> eliminaScansione({required String id});

  /// Crea la riga `AnalisiCopertina` di una Scansione, in stato `inCorso` —
  /// la pipeline (#32) la crea appena prende in carico la Scansione, prima
  /// di chiamare Claude.
  Future<String> avviaAnalisiCopertina({
    required String scansioneId,
    DateTime? createdAt,
  });

  /// Manda una Scansione al riconoscimento senza avviarlo: crea la riga
  /// `AnalisiCopertina` in stato `pending`, che la pipeline prende in carico
  /// quando c'è la rete (ADR-0008, #210). Se la Scansione ha già un'Analisi
  /// Copertina, in qualunque stato, la lascia com'è e ne restituisce l'id.
  Future<String> accodaAnalisiCopertina({
    required String scansioneId,
    DateTime? createdAt,
  });

  /// Le Scansioni con l'Analisi Copertina ancora `pending`, nell'ordine in
  /// cui sono state accodate (quello del batch). Una riga rimasta senza la sua Scansione
  /// (eliminata dal riepilogo) non c'è.
  Stream<List<ScansioneInAttesa>> watchScansioniInAttesaDiAnalisi();

  /// Registra il risultato di un'Analisi Copertina completata con successo —
  /// campi grezzi e non parsati (#31, #48), `rawResponse` preserva l'intera
  /// risposta strutturata di Claude.
  Future<void> completaAnalisiCopertina({
    required String id,
    required String rawResponse,
    String? title,
    String? issueNumberLabel,
    String? publisher,
    String? seriesName,
    String? isbn,
    String? barcode,
    String? price,
    String? releaseDate,
    int? year,
    int? pageCount,
    String? language,
    String? color,
    String? issn,
    List<String> characters = const [],
    List<String> coverStyleTags = const [],
    List<String> visualElementTags = const [],
    String? recognizedPublisherLogo,
    String? recognizedSeriesLogo,
    String? printingType,
    String? classificazione,
    String? description,
    DateTime? completedAt,
  });

  /// Registra un fallimento dell'Analisi Copertina — nessun retry automatico
  /// (destinazione della mappa #27): lo stato resta `fallita`, `errorMessage`
  /// cattura il motivo per capirlo a posteriori.
  Future<void> fallisciAnalisiCopertina({
    required String id,
    required String errorMessage,
    DateTime? completedAt,
  });

  /// L'id della riga `AnalisiCopertina` già creata per questa Scansione —
  /// usato dal retry manuale (riepilogo) per riprendere la riga esistente
  /// invece di crearne una seconda, che romperebbe la relazione 1:1 con la
  /// Scansione.
  Future<String> idAnalisiCopertinaPerScansione(String scansioneId);

  /// Riporta un'Analisi Copertina `fallita` in stato `inCorso` per un nuovo
  /// tentativo — retry manuale dall'utente (nessun retry automatico, #27):
  /// azzera `errorMessage`/`completedAt` della riga esistente.
  Future<void> riavviaAnalisiCopertina({required String id});

  /// Lo stato osservabile dell'Analisi Copertina per la Scansione con questo
  /// percorso immagine — usato dal riepilogo per riflettere lo stato reale
  /// invece di un placeholder statico. `pending` finché la pipeline
  /// sequenziale non ha ancora creato la riga per questa Scansione.
  Stream<StatoAnalisiScansione> watchStatoAnalisiCopertina(String image);

  /// Se questa Scansione è già stata confermata: esiste già una `Copia` che
  /// la referenzia via `scansioneId` (deciso in sessione, richiesta utente).
  /// Copre entrambi i percorsi di conferma — [confermaCandidato] e
  /// l'inserimento manuale (`InserisciManualmentePage`, entrambi passano da
  /// [aggiungiCopia] con lo stesso `scansioneId`) — così il riepilogo può
  /// distinguere le righe già "Salvata" da quelle ancora da confermare e
  /// impedire una seconda conferma sulla stessa Scansione. `.watch()` invece
  /// di `watchSingleOrNull()` (a differenza di [watchStatoAnalisiCopertina]):
  /// qui il join può restituire più righe se in passato è già sfuggita una
  /// doppia conferma sulla stessa Scansione, e non deve far esplodere lo
  /// stream proprio nel caso che questo metodo serve a prevenire.
  Stream<bool> watchScansioneConfermata(String image);

  /// I percorsi immagine di tutte le Scansioni non ancora confermate (nessuna
  /// `Copia` che le referenzia, stesso criterio di [watchScansioneConfermata]
  /// ma per l'intero elenco), in ordine di creazione — usato dalla Dashboard
  /// per riproporre un batch il cui riepilogo è stato lasciato senza
  /// confermare tutte le righe (uscita verso la Dashboard, o qualunque altra
  /// tab, prima di "Vai alla Dashboard": quel riepilogo viveva solo nella
  /// lista `extra` passata alla rotta, persa non appena la pagina viene
  /// rimossa dallo stack — segnalato da utente). Ricostruisce da `Scansioni`
  /// + `AnalisiCopertina`/`Copie`, non da uno stato in memoria: la pipeline
  /// (`avviaBatch`) scrive comunque su queste tabelle anche a pagina chiusa,
  /// quindi riflette lo stato reale indipendentemente da quanto tempo fa il
  /// riepilogo è stato abbandonato.
  Stream<List<String>> watchImmaginiScansioniNonConfermate();

  /// Crea la riga `Identificazione` di una Scansione, in stato `inCorso` —
  /// la pipeline (§6.3, deciso su #53) la crea appena prende in carico la
  /// Scansione dopo il completamento dell'Analisi Copertina, sul modello di
  /// [avviaAnalisiCopertina].
  Future<String> avviaIdentificazione({
    required String scansioneId,
    DateTime? createdAt,
  });

  /// L'id della riga `Identificazione` già esistente per questa Scansione,
  /// se presente — usato per riprendere la riga invece di crearne una
  /// seconda, che romperebbe la relazione 1:1 con la Scansione (stesso
  /// motivo di [idAnalisiCopertinaPerScansione]). `null` se l'Analisi
  /// Copertina non ha ancora agganciato l'Identificazione (#58).
  Future<String?> idIdentificazionePerScansione(String scansioneId);

  /// Riporta un'Identificazione già esistente in stato `inCorso` per un
  /// nuovo giro (richiesta utente dal riepilogo: rieseguire l'Analisi
  /// Copertina di una Scansione già `completata` riaggancia anche
  /// l'Identificazione, #58) — ripulisce prima i Candidati proposti dal giro
  /// precedente: [watchIdentificazione] raggruppa per `scansioneId`, non per
  /// riga, quindi lasciarli mescolerebbe i Candidati vecchi a quelli nuovi.
  /// Sul modello di [riavviaAnalisiCopertina].
  Future<void> riavviaIdentificazione({required String id});

  /// Persiste un Candidato proposto per un'Identificazione — una riga per
  /// candidato, non appena proposto (deciso su #53), indipendentemente da
  /// quale verrà poi confermato con [marcaCandidatoScelto].
  Future<String> aggiungiCandidato({
    required String identificazioneId,
    required FonteCandidato source,
    required double punteggio,
    String? edizioneId,
    String? title,
    String? seriesName,
    String? issueNumberLabel,
    String? publisher,
    int? year,
    String? coverImageUrl,
  });

  /// Conclude un'Identificazione con successo — anche col caso "zero
  /// Candidati trovati" (nessuno stato speciale, deciso su #53): la tabella
  /// `Candidati` resta semplicemente senza righe per questa Identificazione.
  Future<void> completaIdentificazione({
    required String id,
    DateTime? completedAt,
  });

  /// Registra un fallimento tecnico dell'Identificazione (es. ComicVine
  /// irraggiungibile) — nessun retry automatico, sul modello di
  /// [fallisciAnalisiCopertina].
  Future<void> fallisciIdentificazione({
    required String id,
    required String errorMessage,
    DateTime? completedAt,
  });

  /// Marca il Candidato confermato dall'utente (schermo di conferma, #54) —
  /// la riga scelta fra quelle proposte per la stessa Identificazione.
  Future<void> marcaCandidatoScelto({required String id});

  /// L'esito osservabile dell'Identificazione di una Scansione — stato più
  /// Candidati ordinati per punteggio decrescente (schermo di conferma,
  /// #54/#59). `pending` finché la pipeline (§6.3, agganciata su #58) non ha
  /// ancora creato la riga `Identificazione` per questa Scansione, stesso
  /// significato di `watchStatoAnalisiCopertina`.
  Stream<EsitoIdentificazione> watchIdentificazione(String scansioneId);

  /// Conferma un Candidato (schermo di conferma, §6.3, deciso su #54/#59):
  /// marca la riga scelta e collega/crea la Copia risultante. Se `interno`
  /// (Edizione già catalogata), aggiunge solo una nuova Copia a
  /// quell'Edizione (più `_completaDescrizioneMancante`, vedi il commento
  /// lì); se `esterno` (ComicVine, nessuna Edizione propria ancora), crea
  /// Opera/Serie/Edizione da zero a partire dai campi grezzi del candidato
  /// prima di aggiungere la Copia. La Copia creata parte con condizione di
  /// default `fine` e prezzo di acquisto pre-compilato dal prezzo di
  /// copertina letto dall'AI su questa Scansione, quando disponibile (punto
  /// di partenza modificabile dalla Scheda, non un dato definitivo — bug
  /// osservato: la Copia veniva creata senza condizione né prezzo). Ritorna
  /// l'id della Copia creata.
  Future<String> confermaCandidato({
    required Candidato candidato,
    required String scansioneId,
  });

  /// La riga `AnalisiCopertina` completata di questa Scansione — letta dal
  /// motore di matching (#52/#57) per generare i Candidati di
  /// un'Identificazione. Presuppone che l'Analisi Copertina sia già
  /// `completata`: la pipeline (§6.3) avvia l'Identificazione solo dopo,
  /// stesso ordine del requisito.
  Future<AnalisiCopertinaTableData> analisiCopertinaPerScansione(
    String scansioneId,
  );

  /// Il catalogo interno (Opere/Serie/Edizioni) con Opera/Serie già risolte
  /// via join, pronto per il motore di matching (#52/#57) — nessun filtro:
  /// ogni Edizione è un candidato interno potenziale a prescindere da quante
  /// Copie possiede.
  Future<List<EdizioneCatalogo>> catalogoPerMatching();

  /// I numeri posseduti per Serie — stesso filtro "posseduto" del resto del
  /// catalogo (`status IN (posseduta, prestata)`, vedi `watchDashboardKpis`)
  /// — usati dal bonus di contesto del motore di matching (Livello 5,
  /// #52/#57): il numero di una Serie senza `issueNumber` non è comparabile
  /// e viene escluso.
  Future<Map<String, Set<int>>> numeriPossedutiPerSerie();

  // --- Valore stimato (§35, deciso su #157/#161). ---

  /// I dati identificativi di una Copia necessari a interrogare il
  /// provider di valutazione (titolo/serie/numero/editore dell'Edizione,
  /// Condizione della Copia) — letti da `ValoreStimatoPipeline` prima di
  /// chiamare il client, stesso ruolo di [catalogoPerMatching] per il
  /// motore di matching.
  Future<
    ({
      String title,
      String? seriesName,
      String? issueNumberLabel,
      String? publisher,
      CondizioneCopia? condition,
    })
  >
  copiaConEdizionePerId(String copiaId);

  /// Crea la riga `ValoreStimato` di una Copia al primo calcolo, oppure la
  /// riporta a `inCorso` per un ricalcolo successivo (creazione, cambio
  /// Condizione, refresh manuale — §35.3): a differenza di
  /// [avviaAnalisiCopertina] (sempre un insert, relazione 1:1 con una
  /// Scansione mai riusata), qui la stessa Copia innesca ripetutamente lo
  /// stesso calcolo, quindi la riga esistente va riusata, non duplicata
  /// (`uniqueKeys` su `copiaId` in `ValoreStimatoTable` lo impedirebbe
  /// comunque). `value`/`completedAt` di un calcolo precedente non vengono
  /// toccati qui: restano finché [completaValoreStimato] o
  /// [segnaValoreStimatoNonDisponibile] non li aggiornano.
  Future<String> avviaOrRiavviaValoreStimato({
    required String copiaId,
    DateTime? createdAt,
  });

  /// Registra un Valore stimato calcolato con successo, sempre in EUR
  /// (§35) — la conversione dalla valuta della fonte avviene nel client.
  Future<void> completaValoreStimato({
    required String id,
    required double value,
    DateTime? completedAt,
  });

  /// Segna una Copia come "non disponibile" (§35.2/§35.4): provider non
  /// configurato o Edizione/variant non coperta dalla fonte — placeholder
  /// permanente, non un errore da ritentare automaticamente. `value` viene
  /// azzerato: un'assenza di dati non deve mostrare un valore residuo di
  /// un calcolo precedente come se fosse ancora valido.
  Future<void> segnaValoreStimatoNonDisponibile({
    required String id,
    DateTime? completedAt,
  });

  /// Registra un errore transitorio (rete, timeout, rate-limit — §35.4):
  /// a differenza di [segnaValoreStimatoNonDisponibile], `value` e
  /// `completedAt` di un calcolo precedente riuscito **non** vengono
  /// toccati (`Value.absent()` implicito, i campi assenti dalla
  /// Companion) — un valore già noto resta più utile di nessun valore,
  /// anche se non più freschissimo, mentre lo stato `fallita` segnala
  /// comunque che l'ultimo tentativo non è riuscito.
  Future<void> fallisciValoreStimato({
    required String id,
    required String errorMessage,
  });

  // --- KPI della Dashboard (§4.1, regole fissate su #2). ---

  /// I numeri riassuntivi della Dashboard. Un'unica query: tutti i KPI di
  /// volume condividono lo stesso filtro "posseduto" (`status IN
  /// ('posseduta', 'prestata')` — una copia prestata resta posseduta, solo
  /// venduta/persa escono dai conteggi, vedi `CONTEXT.md`), e i numeri
  /// mancanti/serie complete condividono la stessa CTE ricorsiva 1..totale
  /// per serie (§17, §6 di `docs/research/drift-setup.md`).
  Stream<DashboardKpis> watchDashboardKpis();

  /// Le serie con "numeri totali" noto e almeno un numero mancante, con la
  /// percentuale di completamento (sezione "Serie incomplete" del
  /// prototipo). Le serie complete e quelle senza "numeri totali" non
  /// compaiono.
  Stream<List<SerieIncompleta>> watchSerieIncomplete();

  // --- Schermo Serie (§11, deciso su #97/#98/#99). ---

  /// L'elenco `/serie` raggruppato nelle tre sezioni fissate su #97: solo
  /// le serie con almeno un'edizione posseduta compaiono (stesso filtro del
  /// KPI "serie" della Dashboard, #2). Ordinamento delle sezioni deciso su
  /// #97: incomplete per percentuale di completamento crescente, le altre
  /// due alfabetiche.
  Stream<SerieLista> watchSerieLista();

  /// Il dettaglio `/serie/:id`: numeri posseduti, editore/anno derivati
  /// aggregando le edizioni della serie (nessun nuovo campo su
  /// `SerieTable`, deciso su #97), duplicati, cover (override o derivata
  /// dalla prima Edizione posseduta per numero, non per data di
  /// catalogazione). Null se la Serie non esiste (più cancellata nel
  /// frattempo).
  Stream<SerieDettaglio?> watchSerieDettaglio(String serieId);

  /// Aggiorna nome/numero totale/ISSN/cover di una Serie (§11, deciso su
  /// #99; cover aggiunta in sessione successiva) — unica scrittura UI su
  /// questi campi, finora popolati solo da `aggiungiSerie()` (ingestion AI).
  /// Nessun vincolo qui sul numero totale rispetto ai numeri già posseduti:
  /// lo valida la UI (`ModificaSerieSheet`) prima di chiamare questo
  /// metodo. `coverImage` è sempre scritto così com'è (null incluso):
  /// azzera l'override e fa tornare la Serie alla cover di default se lo
  /// sheet lo passa esplicitamente a null — stesso comportamento
  /// "sovrascrivi sempre" degli altri campi di questo metodo.
  Future<void> aggiornaSerie({
    required String id,
    required String name,
    int? totalIssues,
    String? issn,
    String? coverImage,
  });

  /// Le Edizioni possedute di una Serie, ordinate per numero e poi per data
  /// di catalogazione — usate sia dal tap su un numero della Scheda Serie
  /// (naviga diretto se una sola corrispondenza, altrimenti mostra un
  /// selettore quando più Edizioni condividono lo stesso `issueNumber`,
  /// es. variant) sia dal selettore "scegli da un'edizione della serie"
  /// nell'edit della cover.
  Future<List<EdizioneCatalogo>> edizioniPosseduteDiSerie(String serieId);

  /// La cover della prima Edizione posseduta di una Serie per numero (a
  /// parità di numero, per data di catalogazione) — stessa derivazione
  /// usata da [watchSerieDettaglio]
  /// quando non c'è override, usata da `ModificaSerieSheet` per
  /// l'anteprima dopo "torna al default" (l'override appena rimosso in UI
  /// non è ancora stato salvato, quindi il default va richiesto a parte).
  Future<String?> coverDefaultDiSerie(String serieId);

  /// Le ultime copie possedute aggiunte al catalogo (§4.1, carosello
  /// "Aggiunti di recente"), le più recenti per prime.
  Stream<List<ComicRecente>> watchAggiuntiDiRecente();

  /// Il valore di `Edizioni.coverImage` così com'è per un URL remoto
  /// (fallback ComicVine di `_coverImagePerCandidato`); per un percorso
  /// locale, ricostruito assoluto sulla cartella base *corrente* — vedi
  /// `percorso_locale.dart` sul perché non basta usare il valore in DB
  /// così com'è. `baseDirectory` è lazy (vedi [percorso_locale.risolvi]):
  /// non tocca `path_provider` per un URL remoto o un percorso che non
  /// corrisponde a nessuna sottocartella locale nota.
  Future<String?> risolviCoverImage(String? coverImage);

  // --- Scheda del fumetto (§8, deciso su #63/#65/#67/#68, implementato su
  // #69). ---

  /// L'Edizione con le sue Copie e i suoi Autori, per la Scheda — `null` se
  /// l'Edizione non esiste più (es. appena cancellata da un'altra sessione).
  /// Un solo join con `Copie`/`ComicCreator`/`Creator` in parallelo (prodotto
  /// cartesiano raggruppato per id in Dart, stesso pattern di
  /// [watchIdentificazione]) invece di combinare più stream: nessuna
  /// dipendenza da rxdart in questo repository.
  Stream<EdizioneDettaglio?> watchEdizione(String edizioneId);

  /// Il valore grezzo (relativo, non risolto) di `Edizioni.coverImage` — a
  /// differenza di [watchEdizione]/[risolviCoverImage] (che lo risolvono
  /// assoluto per la visualizzazione), serve alla modifica bibliografica
  /// (#67) per non alterare la cover quando l'utente non ne sceglie una
  /// nuova dalla galleria.
  Future<String?> coverImageGrezzoDi(String edizioneId);

  /// Ripristina `Edizioni.coverImage` per le righe rimaste a `null` per la
  /// race fra il salvataggio della modifica bibliografica e il fetch
  /// asincrono di [coverImageGrezzoDi] (bug osservato: modificare solo il
  /// numero da `ModificaSchedaPage` poteva cancellare la cover esistente).
  /// Recupera la cover dalla Scansione originale — mai cancellata una volta
  /// confermata in catalogo, vedi `ScansioneStorage.elimina` — tramite la
  /// prima Copia collegata che ne referenzia una (`Copie.scansioneId`).
  /// Azione di manutenzione una tantum (voce in Impostazioni): non tocca le
  /// Edizioni senza cover per altri motivi (mai scansionate, o già senza
  /// Copia/Scansione collegata). Ritorna il numero di Edizioni ripristinate.
  Future<int> ripristinaCoverMancantiDaScansione();

  /// Salva una cover scelta dalla galleria (`image_picker`) per la modifica
  /// bibliografica della Scheda (§8.1, deciso su #67) e la relativizza nello
  /// stesso formato del resto del catalogo — vedi `_coverImagePerCandidato`.
  Future<String> salvaCoverLocale(File file);

  /// Aggiorna il titolo dell'Opera collegata a un'Edizione (§8.1) — il
  /// titolo vive su `Opere`, non su `Edizioni` (§36, distinzione Opera/
  /// Edizione).
  Future<void> aggiornaTitoloOpera({
    required String operaId,
    required String title,
  });

  /// Aggiorna i campi bibliografici di un'Edizione (§8.1, flusso deciso su
  /// #67) — esclusi titolo ([aggiornaTitoloOpera]) e Autori
  /// ([collegaCreatorAEdizione]/[rimuoviCreatorDaEdizione]). Se l'Edizione
  /// cambia Serie, o non ne ha più, la Serie di prima si cancella quando
  /// resta senza Edizioni.
  Future<void> aggiornaEdizione({
    required String id,
    String? serieId,
    String? publisher,
    int? issueNumber,
    String? issueNumberLabel,
    String? coverImage,
    String? releaseDate,
    String? coverPrice,
    int? pageCount,
    String? language,
    String? color,
    String? ean,
    String? volume,
    String? description,
    int? year,
    FormatoEdizione? format,
  });

  /// Aggiorna i campi personali §8.2 di una Copia (flusso deciso su #67) —
  /// esclusi `status`/`readingStatus` (§8.3, [cambiaStatoCopia]): scrive
  /// solo le colonne qui elencate, lasciando lo stato invariato.
  Future<void> aggiornaCopia({
    required String id,
    CondizioneCopia? condition,
    double? purchasePrice,
    ValutaPrezzo? purchasePriceCurrency,
    DateTime? purchaseDate,
    String? seller,
    String? location,
    String? notes,
    double? valutazione,
  });

  /// Cambia lo stato di una Copia (§8.3, selettore singolo mutuamente
  /// esclusivo — deciso in apertura della mappa #63, vedi `voce_stato.dart`):
  /// scrive solo `status`/`readingStatus`, lasciando invariati i campi §8.2.
  Future<void> cambiaStatoCopia({
    required String id,
    required StatoCopia status,
    StatoLettura? readingStatus,
  });

  /// Imposta "In vendita" di una singola Copia (§8.4, deciso su #163/#164)
  /// — asse a sé come [cambiaStatoCopia]: scrive solo `forSale`, lasciando
  /// invariati gli altri campi §8.2/§8.3.
  Future<void> impostaInVendita({required String id, required bool inVendita});

  /// Azione in blocco "Segna come in vendita" dalla Collezione (§9, variante
  /// B decisa su #164): marca `forSale = true` su tutte le Copie possedute
  /// (`status` posseduta/prestata, stesso insieme di "copiePossedute"/badge
  /// duplicati) delle Edizioni indicate — la cascata "un'edizione con più
  /// copie marca tutte le copie possedute" decisa in fase di destinazione su
  /// #163. Ritorna il numero di Copie effettivamente scritte, per il
  /// feedback banner della UI.
  Future<int> segnaEdizioniInVendita(List<String> edizioneIds);

  /// Rimuove una singola Copia (§8.4). Se era l'ultima Copia della sua
  /// Edizione, elimina anche l'Edizione (deciso su #68: nessuno stato
  /// "orfana, 0 copie") — ritorna `true` in quel caso, così il chiamante
  /// (la Scheda) sa di dover navigare via. Come [eliminaEdizione], cancella
  /// anche la Serie rimasta senza Edizioni.
  Future<bool> rimuoviCopia(String id);

  /// Elimina un'intera Edizione con tutte le sue Copie (§8.4) — il bottone
  /// "Elimina edizione" sempre visibile deciso su #65/#68. La Serie rimasta
  /// senza Edizioni si cancella.
  Future<void> eliminaEdizione(String edizioneId);

  // --- Collezione (§9, deciso su #79/#90, split indice/hydration #113). ---

  /// L'indice leggero della Collezione (§9, deciso su #112/#113): tutti i
  /// valori dei 12 assi di filtro/ordinamento già risolti tranne la cover
  /// — filtro/ordinamento veri e propri restano lato Dart
  /// (`FiltriCollezioneLogic`, #85). Reattivo su tutto il catalogo
  /// posseduto (nessuna paginazione qui, #113): la paginazione riguarda
  /// solo l'hydration della cover, vedi [watchHydratazioneCollezione].
  ///
  /// Riusa la query di base di `_watchRigheEdizioniPossedute` più quattro
  /// letture bulk per gli assi many-to-many (Autore, Personaggio, Genere,
  /// Tag), raggruppate per `edizioneId` in Dart invece che unite in un solo
  /// join — un join simultaneo di 4 relazioni many-to-many produrrebbe un
  /// prodotto cartesiano per Edizione (lo stesso problema che [watchEdizione]
  /// evita avendo una sola relazione many-to-many, Autori, oltre a Copie).
  Stream<List<EdizioneCollezioneIndice>> watchIndiceCollezione();

  /// La cover risolta ([risolviCoverImage]) delle sole Edizioni in
  /// [edizioneIds] — la finestra caricata dallo scroll infinito della
  /// Collezione (§9, deciso su #112/#113), separata dall'indice leggero
  /// perché è l'unico campo costoso da risolvere per riga (vedi Note della
  /// mappa #112). Reattiva sull'intera finestra passata: nessuno stato
  /// tenuto fra chiamate, il caching/delta è responsabilità di #115.
  ///
  /// Un id il cui Edizione non è (più) posseduta è **omesso** dalla mappa
  /// risultante, mai presente con valore `null` (che significa invece
  /// "nessuna cover" per un'Edizione posseduta senza cover impostata).
  Stream<Map<String, String?>> watchHydratazioneCollezione(
    List<String> edizioneIds,
  );

  // --- Tool-calling dell'Assistente (§10, schema deciso su ADR-0002). ---

  /// Cerca Serie esistenti per nome (match parziale) — usato dal filtro
  /// `serie` di [cercaEdizioni] e dal tool `numeriMancantiSerie` (#132,
  /// composto sopra [watchSerieIncomplete]). Il chiamante distingue nessun
  /// match, un solo match o più match ambigui dalla lunghezza della lista
  /// risultante, stesso pattern di [cercaCreator]/[cercaCharacter]/[cercaTag].
  Future<List<SerieTableData>> cercaSerie(String query);

  /// Il tool `cercaEdizioni` dell'Assistente (§10, ADR-0002): i 9 assi di
  /// filtro sono tutti opzionali e combinati in AND sopra un'unica lettura
  /// di [watchIndiceCollezione] — nessuna query aggiuntiva oltre a
  /// [cercaSerie] per risolvere `serie` (una Serie può avere più match
  /// parziali, tutti inclusi nel filtro). `isbn` confronta
  /// [EdizioneCollezioneIndice.ean], già presente nella riga `Edizioni` del
  /// join sorgente. Tronca a 30 risultati: `totale` riporta il conteggio
  /// reale solo quando `troncato` è vero.
  Future<RisultatoCercaEdizioni> cercaEdizioni({
    String? titolo,
    String? serie,
    String? autore,
    String? editore,
    String? personaggio,
    String? tag,
    int? numero,
    String? isbn,
    String? testoLibero,
  });

  /// Il tool `conteggioPer` dell'Assistente (§10, ADR-0002): aggregazione
  /// lato Dart sopra [watchIndiceCollezione] (una Edizione posseduta = un
  /// conteggio, non una Copia: due copie della stessa Edizione contano una
  /// volta sola, coerente con gli altri assi della Collezione). Le Edizioni
  /// senza il campo richiesto (editore/anno assenti) sono escluse, non
  /// raggruppate in un "non specificato". Ordinato per conteggio decrescente.
  Future<Map<String, int>> conteggioPer(CampoConteggio campo);

  /// Il tool `serieQuasiComplete` dell'Assistente (§10, ADR-0002): filtro
  /// lato Dart su [watchSerieIncomplete] per percentuale di completamento
  /// ≥`_sogliaSerieQuasiCompleta`.
  Future<List<SerieIncompleta>> serieQuasiComplete();

  /// Il tool `trovaDuplicati` dell'Assistente (§10, ADR-0002): stessa CTE
  /// `edizioni_possedute` di [watchDashboardKpis] (conteggio copie per
  /// Edizione), qui proiettata sulle righe (titolo/serie/numero/editore)
  /// invece che sul solo conteggio — l'unica query SQL nuova di questo
  /// ticket, le altre riusano [watchIndiceCollezione]/[watchSerieIncomplete].
  Future<List<EdizioneDuplicata>> trovaDuplicati();

  // --- Conversazione dell'Assistente (§10/§24, deciso su #122/#124/#128). ---

  /// Id dell'unica Conversazione, creandola se non esiste ancora — vincolo
  /// di singleton solo applicativo (#128), non imposto dallo schema.
  Future<int> getOrCreaConversazione();

  /// Aggiunge un Messaggio alla Conversazione (§10/§24, deciso su #128).
  /// [edizioneIds] valorizzato solo per un Messaggio assistente con un
  /// risultato strutturato (variante A, #125) — riferimento vivo, risolto a
  /// runtime da [watchMessaggi], mai denormalizzato. [sottotipoSistema] solo
  /// per `ruolo = sistema`.
  Future<int> aggiungiMessaggio({
    required int conversazioneId,
    required RuoloMessaggio ruolo,
    required String testo,
    SottotipoSistema? sottotipoSistema,
    List<String> edizioneIds = const [],
    DateTime? createdAt,
  });

  /// I Messaggi della Conversazione in ordine cronologico, col blocco
  /// Edizioni risolto a runtime (#128) sopra [watchIndiceCollezione] — un
  /// `edizioneId` non più presente (Edizione cancellata) è omesso in
  /// silenzio, nessun placeholder.
  Stream<List<Messaggio>> watchMessaggi(int conversazioneId);

  /// Cancella l'intera Conversazione — tutti i suoi Messaggi, poi la riga
  /// stessa (§10, deciso su #122/#128) — mai singoli Messaggi. Cascata
  /// gestita in Dart, stesso pattern di [eliminaEdizione].
  Future<void> eliminaConversazione(int conversazioneId);

  // --- Export/import (§16, deciso su #139/#140). ---

  /// Tutte le Copie della collezione con Edizione/Opera/Serie/Autori
  /// collegati, una riga per Copia — base condivisa per l'export CSV/JSON
  /// (§16, deciso su #140). A differenza di [watchIndiceCollezione] non
  /// filtra per `status` (l'export è un'istantanea completa dei dati
  /// dell'utente, §19 Privacy: anche le Copie vendute/perse restano
  /// esportabili) e non risolve la cover (niente immagini, decisione mappa
  /// #139).
  Future<List<RigaEsportazioneCopia>> tutteLeCopiePerEsportazione();

  /// Tutte le Copie della collezione per il PDF/catalogo stampabile (§16,
  /// layout deciso su
  /// [#141](https://github.com/saviogiordano/MyComicBrain/issues/141)):
  /// stessa base non filtrata di [tutteLeCopiePerEsportazione] (istantanea
  /// completa, anche Copie vendute/perse), ma proiettata sui campi della
  /// variante C scelta — cover risolta inclusa.
  Future<List<RigaCatalogoStampabile>> tutteLeCopiePerCatalogoStampabile();

  /// Scrive le righe già validate da `analizzaCsvImportazione`/
  /// `analizzaJsonImportazione` (§16, deciso su
  /// [#142](https://github.com/saviogiordano/MyComicBrain/issues/142)):
  /// import additivo semplice, ogni riga crea sempre una nuova Opera,
  /// Edizione e Copia — nessuna euristica di merge/duplicate-detection con
  /// la collezione esistente. Autori sempre nuovi Creator ([aggiungiCreator],
  /// stesso non-dedup di #64); la Serie riusa invece l'invariante esistente
  /// di [aggiungiSerie] (dedup per nome) — quella non è una scelta
  /// dell'import ma la stessa regola che vale già per ogni altra scrittura
  /// di Serie nell'app (evita righe Serie duplicate che spaccherebbero i KPI
  /// "serie"/"serie complete"). Un'unica transazione per l'intero import:
  /// più rows sono già validate a monte, quindi un errore qui è un guasto
  /// del DB, non un dato scorretto — meglio annullare tutto che lasciare
  /// Opere/Edizioni orfane senza Copia.
  ///
  /// [copertine] (import da zip, vedi `analizzaZipImportazione`): immagini
  /// indicizzate col valore della colonna "Copertina". Salvate in
  /// `copertine/` prima della transazione (una volta per file, anche se più
  /// righe la condividono) e collegate all'Edizione col percorso relativo,
  /// come ogni altra cover locale. Una riga che punta a un file assente
  /// nello zip resta senza cover, non viene scartata.
  Future<void> importaRighe(
    List<RigaImportazioneParsata> righe, {
    Map<String, Uint8List> copertine = const {},
  });
}
