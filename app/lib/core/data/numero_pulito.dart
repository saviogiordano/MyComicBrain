/// Ripulisce un'etichetta di numero letta da una copertina (es. `"#700"`)
/// dal prefisso `#` e dagli spazi — `null`/vuota resta tale. Le copertine
/// USA riportano quasi sempre il numero preceduto da `#`; senza questa
/// pulizia l'etichetta sporca rompe sia il parsing intero (`int.tryParse`
/// fallisce silenziosamente, lasciando `issueNumber` a `null`) sia la
/// ricerca ComicVine per numero (`issue_number` su ComicVine non porta mai
/// il `#`).
String? numeroPulito(String? label) {
  final pulito = label?.trim().replaceFirst(RegExp(r'^#\s*'), '');
  return pulito == null || pulito.isEmpty ? null : pulito;
}

/// Estrae la parte intera di un'etichetta di numero, usata come
/// `Edizioni.issueNumber` per l'ordinamento e la griglia numerica di Serie
/// (§11/#99). `int.tryParse` da solo fallisce su numeri con decimale
/// (`"679.1"`, tipici di storyline che si incastrano fra due numeri
/// regolari) restituendo `null` — l'Edizione veniva salvata correttamente
/// ma spariva dalla griglia dei numeri posseduti (bug osservato da utente).
/// La parte intera (`679`) resta un posizionamento ragionevole nella
/// griglia, sullo stesso slot del numero "679" se posseduto (stesso
/// trattamento riservato alle variant, vedi `serie_dettaglio_page.dart`).
/// `issueNumberLabel` continua a portare l'etichetta completa per display e
/// matching testuale.
///
/// L'etichetta ripulita deve però essere *interamente* numerica (a parte
/// l'eventuale decimale): un'etichetta come `"42 Variant"` resta senza
/// `issueNumber` (comportamento voluto, vedi
/// `inserisci_manualmente_page_test.dart`) invece di risolvere a `42` come
/// farebbe un semplice "prendi le cifre iniziali".
int? numeroIntero(String? label) {
  final pulito = numeroPulito(label);
  if (pulito == null) return null;
  final match = RegExp(r'^(\d+)(?:\.\d+)?$').firstMatch(pulito);
  return match == null ? null : int.tryParse(match.group(1)!);
}

/// Il numero come `double`, solo quando l'etichetta è un vero numero
/// decimale (es. `"699.1"`) — a differenza di [numeroIntero] (che tronca lo
/// stesso decimale alla parte intera per `Edizioni.issueNumber`, usato per
/// ordinamento e conteggio mancanti/§17), questo valore serve solo alla
/// griglia numerica di Serie (§11/#99) per dare a un "point one" una cella
/// propria fra il numero intero precedente e successivo invece di fonderlo
/// in quello intero come una variant di copertina (richiesta utente: un
/// "699.1" è un albo a sé con propria uscita, non una variant del #699 —
/// bug osservato: spariva del tutto dalla griglia, raggiungibile solo
/// tramite il selettore di `_apriNumero` quando anche il #699 era
/// posseduto). `null` per un'etichetta puramente intera (`"699"`) o non
/// numerica (`"42 Variant"`, `"Annual 1"`) — quei casi restano fusi nello
/// slot intero come oggi.
double? numeroDecimale(String? label) {
  final pulito = numeroPulito(label);
  if (pulito == null) return null;
  final match = RegExp(r'^\d+\.\d+$').firstMatch(pulito);
  return match == null ? null : double.tryParse(pulito);
}
