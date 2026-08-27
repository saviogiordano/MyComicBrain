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
