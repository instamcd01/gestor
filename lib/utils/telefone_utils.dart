/// Normaliza um telefone brasileiro pra só dígitos, sem o código do país
/// (55) quando presente — cadastro manual no app nunca inclui, mas dados
/// vindos de planilha, iFood ou outras origens às vezes têm.
String normalizarTelefoneBr(String texto) {
  var digitos = texto.replaceAll(RegExp(r'[^0-9]'), '');
  if ((digitos.length == 12 || digitos.length == 13) && digitos.startsWith('55')) {
    digitos = digitos.substring(2);
  }
  return digitos;
}

/// Monta o link do wa.me a partir de um telefone em qualquer formato já
/// salvo no banco. Sem normalizar primeiro, um número já salvo com o "55"
/// (comum em dados vindos de outras origens) virava "5555..." no link e o
/// WhatsApp não encontrava o contato.
String linkWhatsApp(String telefone) => 'https://wa.me/55${normalizarTelefoneBr(telefone)}';
