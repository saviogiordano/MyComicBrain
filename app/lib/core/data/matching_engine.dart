import 'dart:math' as math;

import 'package:mycomicbrain/core/data/comic_vine_client.dart';
import 'package:mycomicbrain/core/data/database.dart'
    show AnalisiCopertinaTableData;
import 'package:mycomicbrain/core/data/text_similarity.dart';
import 'package:mycomicbrain/core/domain/edizione_catalogo.dart';
import 'package:mycomicbrain/core/domain/identificazione.dart';

/// Un candidato generato dal motore di matching, non ancora persistito —
/// stessi campi di `CandidatiTable`/`ComicsRepository.aggiungiCandidato`
/// (§6.3, deciso su #53); [punteggio] è già sulla scala 0-100 della colonna.
class CandidatoProposto {
  const CandidatoProposto({
    required this.source,
    required this.punteggio,
    this.edizioneId,
    this.title,
    this.seriesName,
    this.issueNumberLabel,
    this.publisher,
    this.coverImageUrl,
  });

  final FonteCandidato source;
  final double punteggio;
  final int? edizioneId;
  final String? title;
  final String? seriesName;
  final String? issueNumberLabel;
  final String? publisher;
  final String? coverImageUrl;
}

/// Motore di matching e punteggio di confidenza per i candidati di
/// Identificazione (§6.3, algoritmo deciso su #52): un unico punteggio
/// combinato pesato per candidato, non una cascata a livelli con stop
/// anticipato. Pesi e soglie sono placeholder iniziali — da tarare in
/// seguito su scansioni reali (deciso su #52) — tenuti come costanti qui per
/// restare visibili e facili da cambiare in un solo posto.
class MatchingEngine {
  const MatchingEngine();

  /// Sotto questo punteggio (0-100) un candidato non viene proposto — e se
  /// nessun candidato *interno* lo supera, scatta il fallback su ComicVine
  /// (deciso su #52: stessa soglia usata sia per "abbastanza buono da
  /// mostrare" sia per "abbastanza buono da non serve altro", ragionevole
  /// per un placeholder iniziale).
  static const double sogliaMinima = 45;

  /// Quanti candidati proporre al massimo per un'Identificazione — oltre,
  /// l'elenco ordinato dello schermo di conferma (#54) non aggiungerebbe
  /// informazione utile.
  static const int massimoCandidati = 5;

  /// Soglia (0-1, similarità testuale sul solo nome) sopra la quale un nome
  /// di Serie esterno (es. `volume.name` di ComicVine) si considera lo
  /// stesso di una Serie già in catalogo, ai fini del bonus di contesto
  /// (Livello 5) — più severa della soglia sui candidati perché qui basta un
  /// falso positivo per attribuire un bonus alla serie sbagliata.
  static const double _sogliaMatchSerie = 0.75;

  // Pesi del segnale testuale (Livelli 2+4 accorpati, dominante — #52):
  // sommano a 100 sui campi presenti da entrambi i lati, rinormalizzati
  // quando qualche campo è escluso (vedi [_similaritaTestuale]).
  static const double _pesoSeriesName = 35;
  static const double _pesoTitle = 30;
  static const double _pesoIssueNumberLabel = 20;
  static const double _pesoPublisher = 15;

  /// Peso massimo del boost CV/tag (Livello 3, proxy testuale — #52):
  /// additivo, non può da solo produrre un candidato ad alta confidenza.
  static const double _pesoBoostCv = 10;

  /// Bonus di contesto (Livello 5 — #52): additivo e modesto.
  static const double _bonusContesto = 8;

  /// Genera i candidati dal catalogo interno (Opere/Serie/Edizioni),
  /// ordinati per punteggio decrescente, filtrati sotto [sogliaMinima] e
  /// tagliati a [massimoCandidati].
  List<CandidatoProposto> candidatiInterni({
    required AnalisiCopertinaTableData analisi,
    required List<EdizioneCatalogo> catalogo,
    required Map<int, Set<int>> numeriPossedutiPerSerie,
  }) {
    final candidati = <CandidatoProposto>[];
    for (final edizione in catalogo) {
      final punteggio = _punteggio(
        analisi: analisi,
        title: edizione.title,
        seriesName: edizione.seriesName,
        issueNumberLabel: edizione.issueNumberLabel,
        publisher: edizione.publisher,
        serieId: edizione.serieId,
        issueNumero: edizione.issueNumber,
        numeriPossedutiPerSerie: numeriPossedutiPerSerie,
      );
      if (punteggio < sogliaMinima) continue;
      candidati.add(
        CandidatoProposto(
          source: FonteCandidato.interno,
          punteggio: punteggio,
          edizioneId: edizione.edizioneId,
          title: edizione.title,
          seriesName: edizione.seriesName,
          issueNumberLabel: edizione.issueNumberLabel,
          publisher: edizione.publisher,
          coverImageUrl: edizione.coverImage,
        ),
      );
    }
    return _ordinaETaglia(candidati);
  }

  /// Genera i candidati dai risultati di ComicVine (fallback, deciso su
  /// #52), stesso punteggio combinato — senza `edizioneId` (nessuna riga
  /// Edizione ancora: il candidato scelto crea Opera/Edizione/Copia da
  /// zero, #50). Il bonus di contesto scatta comunque se il nome del volume
  /// combacia testualmente con una Serie già in catalogo.
  List<CandidatoProposto> candidatiEsterni({
    required AnalisiCopertinaTableData analisi,
    required List<ComicVineIssueMatch> risultati,
    required List<EdizioneCatalogo> catalogo,
    required Map<int, Set<int>> numeriPossedutiPerSerie,
  }) {
    final candidati = <CandidatoProposto>[];
    for (final issue in risultati) {
      final numero = _numeroDaLabel(issue.issueNumber);
      final punteggio = _punteggio(
        analisi: analisi,
        title: issue.name,
        seriesName: issue.volumeName,
        issueNumberLabel: issue.issueNumber,
        // La risorsa `issue` di ComicVine non espone l'editore.
        publisher: null,
        serieId: _risolviSerieId(issue.volumeName, catalogo),
        issueNumero: numero,
        numeriPossedutiPerSerie: numeriPossedutiPerSerie,
      );
      if (punteggio < sogliaMinima) continue;
      candidati.add(
        CandidatoProposto(
          source: FonteCandidato.esterno,
          punteggio: punteggio,
          title: issue.name,
          seriesName: issue.volumeName,
          issueNumberLabel: issue.issueNumber,
          coverImageUrl: issue.coverImageUrl,
        ),
      );
    }
    return _ordinaETaglia(candidati);
  }

  double _punteggio({
    required AnalisiCopertinaTableData analisi,
    required String? title,
    required String? seriesName,
    required String? issueNumberLabel,
    required String? publisher,
    required int? serieId,
    required int? issueNumero,
    required Map<int, Set<int>> numeriPossedutiPerSerie,
  }) {
    final testuale = _similaritaTestuale(
      analisi: analisi,
      title: title,
      seriesName: seriesName,
      issueNumberLabel: issueNumberLabel,
      publisher: publisher,
    );
    final boostCv = _boostCv(
      analisi: analisi,
      title: title,
      seriesName: seriesName,
      publisher: publisher,
    );
    final bonusContesto = _bonusDiContesto(
      serieId: serieId,
      issueNumero: issueNumero,
      numeriPossedutiPerSerie: numeriPossedutiPerSerie,
    );
    return math.min(100, testuale + boostCv + bonusContesto);
  }

  /// Media pesata delle similarità sui campi presenti da entrambi i lati —
  /// un campo `null`/vuoto in `AnalisiCopertina` (OCR incompleto) o sul
  /// candidato è escluso dal calcolo, non penalizzato (deciso su #52), coi
  /// pesi restanti rinormalizzati a somma 100.
  double _similaritaTestuale({
    required AnalisiCopertinaTableData analisi,
    required String? title,
    required String? seriesName,
    required String? issueNumberLabel,
    required String? publisher,
  }) {
    final contributi = <(double peso, double similarita)>[];
    void aggiungi(double peso, String? a, String? b) {
      final at = a?.trim();
      final bt = b?.trim();
      if (at == null || at.isEmpty || bt == null || bt.isEmpty) return;
      contributi.add((peso, similaritaTestuale(at, bt)));
    }

    aggiungi(_pesoSeriesName, analisi.seriesName, seriesName);
    aggiungi(_pesoTitle, analisi.title, title);
    aggiungi(_pesoIssueNumberLabel, analisi.issueNumberLabel, issueNumberLabel);
    aggiungi(_pesoPublisher, analisi.publisher, publisher);

    if (contributi.isEmpty) return 0;
    final pesoTotale = contributi.fold<double>(0, (s, c) => s + c.$1);
    final somma = contributi.fold<double>(0, (s, c) => s + c.$1 * c.$2);
    return (somma / pesoTotale) * 100;
  }

  /// Boost secondario e non generativo (Livello 3, proxy testuale — #52):
  /// niente vero image matching, si verifica quanti dei tag CV già estratti
  /// (`characters`/`coverStyleTags`/`visualElementTags`/loghi riconosciuti)
  /// corroborano il match comparendo nel testo del candidato (titolo/serie/
  /// editore) — un personaggio riconosciuto nel titolo, un logo che
  /// combacia col nome letto, ecc.
  double _boostCv({
    required AnalisiCopertinaTableData analisi,
    required String? title,
    required String? seriesName,
    required String? publisher,
  }) {
    final tag = <String>[
      ...analisi.characters,
      ...analisi.coverStyleTags,
      ...analisi.visualElementTags,
      if (analisi.recognizedPublisherLogo != null)
        analisi.recognizedPublisherLogo!,
      if (analisi.recognizedSeriesLogo != null) analisi.recognizedSeriesLogo!,
    ].map((t) => t.trim().toLowerCase()).where((t) => t.isNotEmpty).toSet();
    if (tag.isEmpty) return 0;

    final testo = [
      title,
      seriesName,
      publisher,
    ].whereType<String>().map((s) => s.toLowerCase()).join(' ');
    if (testo.isEmpty) return 0;

    final corroborati = tag.where(testo.contains).length;
    return _pesoBoostCv * (corroborati / tag.length);
  }

  /// Bonus additivo e modesto (Livello 5 — #52): scatta solo se il
  /// candidato è collegabile a una Serie già in catalogo e il suo numero è
  /// adiacente ai numeri già posseduti in quella Serie (es. si possiedono i
  /// numeri 1-3, il candidato è il 4).
  double _bonusDiContesto({
    required int? serieId,
    required int? issueNumero,
    required Map<int, Set<int>> numeriPossedutiPerSerie,
  }) {
    if (serieId == null || issueNumero == null) return 0;
    final posseduti = numeriPossedutiPerSerie[serieId];
    if (posseduti == null || posseduti.isEmpty) return 0;
    final adiacente =
        posseduti.contains(issueNumero - 1) ||
        posseduti.contains(issueNumero + 1);
    return adiacente ? _bonusContesto : 0;
  }

  /// La Serie del catalogo il cui nome combacia meglio con [seriesName]
  /// (sopra [_sogliaMatchSerie]), usata per collegare un candidato esterno
  /// al contesto della collezione (Livello 5) prima che esista una sua
  /// Edizione. `null` se nessuna Serie combacia abbastanza.
  int? _risolviSerieId(String? seriesName, List<EdizioneCatalogo> catalogo) {
    if (seriesName == null || seriesName.trim().isEmpty) return null;

    int? migliorId;
    var miglioreSimilarita = 0.0;
    final visti = <int>{};
    for (final edizione in catalogo) {
      final serieId = edizione.serieId;
      final nomeSerie = edizione.seriesName;
      if (serieId == null || nomeSerie == null || !visti.add(serieId)) continue;
      final similarita = similaritaTestuale(seriesName, nomeSerie);
      if (similarita > miglioreSimilarita) {
        miglioreSimilarita = similarita;
        migliorId = serieId;
      }
    }
    return miglioreSimilarita >= _sogliaMatchSerie ? migliorId : null;
  }

  List<CandidatoProposto> _ordinaETaglia(List<CandidatoProposto> candidati) {
    candidati.sort((a, b) => b.punteggio.compareTo(a.punteggio));
    return candidati.take(massimoCandidati).toList();
  }
}

/// Il numero intero da un'etichetta ComicVine (`issue_number`, es. `"42"`)
/// — `null` se non presente o non un intero puro (es. `"42.1"`, `"Annual
/// 1"`): il bonus di contesto confronta solo numeri interi comparabili con
/// `Edizioni.issueNumber`.
int? _numeroDaLabel(String? label) =>
    label == null ? null : int.tryParse(label.trim());
