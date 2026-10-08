/// Requisiti della password in registrazione (#171). Rispecchiano la
/// policy di Supabase Auth (minimo 8 caratteri, `lower_upper_letters_digits`)
/// così l'app blocca prima ciò che il server rifiuterebbe.
enum RequisitoPassword {
  lunghezza('Almeno 8 caratteri'),
  maiuscola('Una lettera maiuscola'),
  minuscola('Una lettera minuscola'),
  numero('Un numero');

  const RequisitoPassword(this.descrizione);

  final String descrizione;
}

/// I requisiti che [password] non soddisfa ancora; vuoto se è valida.
/// Come Supabase, conta solo lettere ASCII e cifre.
Set<RequisitoPassword> requisitiMancanti(String password) => {
  if (password.length < 8) RequisitoPassword.lunghezza,
  if (!password.contains(RegExp('[A-Z]'))) RequisitoPassword.maiuscola,
  if (!password.contains(RegExp('[a-z]'))) RequisitoPassword.minuscola,
  if (!password.contains(RegExp('[0-9]'))) RequisitoPassword.numero,
};
