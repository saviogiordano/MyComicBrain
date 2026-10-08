import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/auth/requisiti_password.dart';

void main() {
  test('una password valida soddisfa tutti i requisiti', () {
    expect(requisitiMancanti('Segreta123'), isEmpty);
  });

  test('segnala ogni requisito mancante', () {
    expect(requisitiMancanti(''), RequisitoPassword.values.toSet());
    expect(requisitiMancanti('Ab1'), {RequisitoPassword.lunghezza});
    expect(requisitiMancanti('segreta123'), {RequisitoPassword.maiuscola});
    expect(requisitiMancanti('SEGRETA123'), {RequisitoPassword.minuscola});
    expect(requisitiMancanti('SegretaXyz'), {RequisitoPassword.numero});
  });

  test('le lettere accentate non contano come maiuscole/minuscole ASCII', () {
    // Supabase ("lower_upper_letters_digits") controlla solo a-z, A-Z, 0-9.
    expect(requisitiMancanti('èèèèÈÈ12'), {
      RequisitoPassword.minuscola,
      RequisitoPassword.maiuscola,
    });
  });
}
