import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Lato più lungo a cui ridimensionare la cover prima di inviarla al
/// provider AI (§6.1/§6.2) — oltre questa soglia i provider vision (Claude
/// compreso) la ridimensionano comunque lato loro prima di leggerla, quindi
/// inviare di più non migliora l'estrazione ma allunga l'upload e la
/// finestra in cui si rischia di superare `coverAnalysisTimeout`.
const latoMassimoCoverAI = 1568;

/// Qualità di ricompressione JPEG per l'invio al provider AI.
const qualitaJpegCoverAI = 85;

/// Ridimensiona/ricomprime [originale] per l'invio al provider AI se supera
/// [latoMassimoCoverAI] sul lato più lungo — una foto da fotocamera arriva
/// spesso satura di risoluzione (3-5+ MB) rispetto a quanto serve per
/// OCR/riconoscimento visivo, alzando inutilmente il rischio di timeout su
/// rete lenta (`AnalisiCopertinaPipeline`). Non tocca il file salvato della
/// Scansione, mostrato altrove nell'app alla risoluzione originale — questa
/// funzione elabora solo i byte spediti al provider.
///
/// Se [originale] è già entro la soglia resta invariata: nessuna
/// ricompressione inutile su un'immagine già piccola. Se i byte non sono
/// un'immagine decodificabile (dati corrotti, o placeholder nei test) li
/// lascia invariati anziché far fallire l'Analisi Copertina qui — un
/// eventuale problema reale emergerà comunque dalla chiamata al provider.
Uint8List comprimiCoverPerAI(Uint8List originale) {
  img.Image? decodificata;
  try {
    decodificata = img.decodeImage(originale);
  } on Object {
    // Alcuni decoder di `package:image` sollevano invece di tornare null su
    // byte troppo corti/malformati per riconoscere il formato (es. i
    // placeholder usati nei test) — stesso esito del caso "non
    // decodificabile" sopra.
    return originale;
  }
  if (decodificata == null) return originale;

  final latoMaggiore = decodificata.width > decodificata.height
      ? decodificata.width
      : decodificata.height;
  if (latoMaggiore <= latoMassimoCoverAI) return originale;

  final ridimensionata = decodificata.width >= decodificata.height
      ? img.copyResize(
          decodificata,
          width: latoMassimoCoverAI,
          interpolation: img.Interpolation.average,
        )
      : img.copyResize(
          decodificata,
          height: latoMassimoCoverAI,
          interpolation: img.Interpolation.average,
        );

  return img.encodeJpg(ridimensionata, quality: qualitaJpegCoverAI);
}
