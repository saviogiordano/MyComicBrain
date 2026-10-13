import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/numero_pulito.dart';
import 'package:mycomicbrain/core/data/prezzo_pulito.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/identificazione.dart';

/// Cosa scrive `ComicsRepository.confermaCandidato` (§6.3, #54/#59/#70),
/// derivato da Candidato e Analisi Copertina della Scansione. Condiviso dai
/// due adapter (ADR-0007): drift lo scrive in più insert, Supabase lo passa
/// alla RPC transazionale `conferma_candidato`.

/// L'Edizione da creare per un Candidato `esterno` (ComicVine), con Opera e
/// Serie di appartenenza. I campi bibliografici (§8.1) vengono
/// dall'Analisi Copertina quando disponibili: l'estrazione AI legge la
/// copertina scansionata stessa, mentre la risorsa `issue` di ComicVine non
/// espone quasi nessuno di questi campi (nemmeno l'editore, vedi
/// `MatchingEngine.candidatiEsterni`) — usarla come unica fonte lasciava
/// l'Edizione quasi vuota (bug osservato, deciso su #70). ComicVine resta
/// il ripiego per titolo/serie/numero/editore/anno quando l'AI non li ha
/// letti. Descrizione/Tipo di stampa/Classificazione (#71/#74) non hanno
/// ripiego: l'AI è l'unica fonte. La cover è a parte: la sceglie l'adapter.
typedef NuovaEdizione = ({
  String title,
  String? seriesName,
  String? publisher,
  int? issueNumber,
  String? issueNumberLabel,
  String? releaseDate,
  int? year,
  String? coverPrice,
  int? pageCount,
  String? language,
  String? color,
  String? ean,
  String? description,
  String? printingType,
  String? classificazione,
});

NuovaEdizione nuovaEdizioneDaCandidato(
  Candidato candidato,
  AnalisiCopertinaTableData analisi,
) {
  final issueNumberLabel =
      numeroPulito(analisi.issueNumberLabel) ?? candidato.issueNumberLabel;
  return (
    title:
        nonVuoto(analisi.title) ??
        candidato.title ??
        candidato.seriesName ??
        'Senza titolo',
    seriesName: nonVuoto(analisi.seriesName) ?? candidato.seriesName,
    publisher: nonVuoto(analisi.publisher) ?? candidato.publisher,
    issueNumber: numeroIntero(issueNumberLabel),
    issueNumberLabel: issueNumberLabel,
    releaseDate: nonVuoto(analisi.releaseDate),
    year: analisi.year ?? candidato.year,
    coverPrice: nonVuoto(analisi.price),
    pageCount: analisi.pageCount,
    language: nonVuoto(analisi.language),
    color: nonVuoto(analisi.color),
    // `barcode` prima di `isbn`, stessa priorità di
    // `InserisciManualmentePage._prefill`: sulle edizioni italiane da
    // edicola è quasi sempre l'EAN periodico quello riportato in copertina.
    ean: nonVuoto(analisi.barcode) ?? nonVuoto(analisi.isbn),
    description: nonVuoto(analisi.description),
    printingType: nonVuoto(analisi.printingType),
    classificazione: nonVuoto(analisi.classificazione),
  );
}

/// La Descrizione con cui completare un'Edizione già catalogata quando si
/// conferma un Candidato `interno` (richiesta utente): una trama letta da
/// questa Analisi Copertina non deve andare persa dietro una seconda Copia.
/// L'adapter la applica solo se l'Edizione non ne ha ancora una ("primo
/// valore buono vince", come per l'Edizione nuova).
String? descrizioneDaCompletare(AnalisiCopertinaTableData? analisi) =>
    nonVuoto(analisi?.description);

/// Il prezzo di acquisto con cui nasce la Copia confermata: il prezzo di
/// copertina letto dall'AI, quando c'è (punto di partenza modificabile
/// dalla Scheda — bug osservato: la Copia veniva creata senza condizione né
/// prezzo). La Condizione di default è [condizioneCopiaConfermata].
({double importo, ValutaPrezzo valuta})? prezzoCopiaConfermata(
  AnalisiCopertinaTableData? analisi,
) => prezzoDaTesto(analisi?.price);

const CondizioneCopia condizioneCopiaConfermata = CondizioneCopia.fine;

/// `null`/stringa vuota o di soli spazi normalizzati a `null` — stesso
/// trattamento di `InserisciManualmentePage._valore`: Claude a volte
/// restituisce una stringa vuota invece di `null` nonostante il prompt
/// (osservato empiricamente), che altrimenti scavalcherebbe il ripiego su
/// ComicVine come se fosse un valore valido.
String? nonVuoto(String? v) {
  final t = v?.trim();
  return (t == null || t.isEmpty) ? null : t;
}
