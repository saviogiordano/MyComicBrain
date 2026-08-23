/// Stato di un'Identificazione (§6.3, deciso su #53): stesso schema a stati
/// di `AnalisiCopertina` (`pending` alla creazione, `inCorso` durante la
/// generazione dei Candidati, poi `completata` o `fallita`) — ma un'entità
/// distinta nel dominio (vedi `CONTEXT.md`), non lo stesso stato riusato.
/// `completata` copre anche il caso "zero Candidati trovati": nessuno stato
/// speciale, la differenza è l'assenza di righe `Candidati`. `fallita` è
/// riservato a un errore tecnico (es. database esterno irraggiungibile) ed è
/// terminale — nessun retry automatico né manuale, come `AnalisiCopertina`.
enum StatoIdentificazione { pending, inCorso, completata, fallita }

/// Provenienza di un Candidato (§6.3, deciso su #53): `interno` se combacia
/// con un'Edizione già catalogata (`edizioneId` valorizzato, confermarlo
/// aggiunge solo una nuova Copia), `esterno` se proviene da ComicVine e non
/// ha ancora una riga Edizione propria (confermarlo crea Opera/Edizione/Copia
/// da zero, con i campi grezzi della riga come dati di partenza).
enum FonteCandidato { interno, esterno }

/// Una riga `Candidati` letta per lo schermo di conferma (§6.3, deciso su
/// #54/#59) — proiezione di sola lettura, distinta dal tipo di scrittura
/// `ComicsRepository.aggiungiCandidato`. `edizioneId` è valorizzato solo per
/// `source = interno`; i campi grezzi coprono il caso `esterno`.
class Candidato {
  const Candidato({
    required this.id,
    required this.source,
    required this.punteggio,
    required this.scelto,
    this.edizioneId,
    this.title,
    this.seriesName,
    this.issueNumberLabel,
    this.publisher,
    this.year,
    this.coverImageUrl,
  });

  final int id;
  final FonteCandidato source;
  final double punteggio;
  final bool scelto;
  final int? edizioneId;
  final String? title;
  final String? seriesName;
  final String? issueNumberLabel;
  final String? publisher;
  final int? year;
  final String? coverImageUrl;
}

/// Esito osservabile dell'Identificazione di una Scansione, per lo schermo
/// di conferma (#59): `pending` finché la pipeline non ha ancora creato la
/// riga `Identificazione` per questa Scansione (stesso significato di
/// `StatoAnalisiScansione` in `analisi_copertina.dart`), `candidati` vuoto
/// finché non è `completata` o se l'Identificazione non ne ha trovato
/// nessuno.
typedef EsitoIdentificazione = ({
  StatoIdentificazione stato,
  String? errorMessage,
  List<Candidato> candidati,
});
