import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mycomicbrain/core/data/cover_compressor.dart';

Uint8List _jpegDi(int width, int height) {
  final immagine = img.Image(width: width, height: height);
  img.fill(immagine, color: img.ColorRgb8(120, 40, 200));
  return img.encodeJpg(immagine);
}

void main() {
  test(
    'immagine entro la soglia: torna invariata byte per byte',
    () {
      final originale = _jpegDi(800, 1200);

      final risultato = comprimiCoverPerAI(originale);

      expect(risultato, same(originale));
    },
  );

  test(
    'immagine oltre la soglia: ridimensionata al lato più lungo massimo',
    () {
      final originale = _jpegDi(2000, 3000);

      final risultato = comprimiCoverPerAI(originale);

      expect(risultato, isNot(same(originale)));
      expect(risultato.length, lessThan(originale.length));
      final decodificata = img.decodeImage(risultato)!;
      expect(decodificata.height, latoMassimoCoverAI);
      expect(decodificata.width, lessThan(decodificata.height));
    },
  );

  test(
    'landscape oltre la soglia: ridimensionata sulla larghezza',
    () {
      final originale = _jpegDi(3000, 2000);

      final risultato = comprimiCoverPerAI(originale);

      final decodificata = img.decodeImage(risultato)!;
      expect(decodificata.width, latoMassimoCoverAI);
      expect(decodificata.height, lessThan(decodificata.width));
    },
  );

  test(
    'byte non decodificabili (es. placeholder nei test): tornano invariati',
    () {
      final originale = Uint8List.fromList([1, 2, 3]);

      final risultato = comprimiCoverPerAI(originale);

      expect(risultato, same(originale));
    },
  );
}
