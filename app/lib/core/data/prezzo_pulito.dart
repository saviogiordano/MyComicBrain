import 'package:mycomicbrain/core/domain/copia.dart';

/// Converte un prezzo di copertina in testo libero (es. "€ 5,30" o "$3.99" —
/// letto dall'AI su `Edizione.coverPrice`, o digitato dall'utente sullo
/// stesso campo in `InserisciManualmentePage`) in un importo numerico +
/// valuta da usare come prezzo di acquisto di default sulla Copia appena
/// creata. Un fumetto americano riporta il prezzo in dollari: `$` nel testo
/// è l'unico segnale disponibile (nessun campo valuta strutturato
/// nell'estrazione, §6.1/§6.2), assenza di `$` assume EUR (fumetti
/// italiani/europei, maggioranza del catalogo). Prende il primo numero
/// trovato nel testo e normalizza la virgola italiana come separatore
/// decimale; `null` se il testo non contiene un numero.
({double importo, ValutaPrezzo valuta})? prezzoDaTesto(String? raw) {
  final testo = raw?.trim();
  if (testo == null || testo.isEmpty) return null;
  final match = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(testo);
  if (match == null) return null;
  var numero = match.group(0)!;
  if (numero.contains(',')) {
    numero = numero.replaceAll('.', '').replaceAll(',', '.');
  }
  final importo = double.tryParse(numero);
  if (importo == null) return null;
  final valuta = testo.contains(r'$') ? ValutaPrezzo.usd : ValutaPrezzo.eur;
  return (importo: importo, valuta: valuta);
}
