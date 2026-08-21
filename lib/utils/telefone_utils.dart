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

/// Normaliza pro formato que o Supabase Auth usa no login por SMS —
/// dígitos com DDI 55 na frente, sem "+", sem máscara. É o formato que fica
/// gravado em `auth.users.phone`/`auth.jwt()->>'phone'` depois do OTP
/// (confirmado direto no banco: `+5521...` enviado pro signInWithOtp vira
/// `5521...` sem o "+" quando o Supabase grava/expõe no JWT). Usado sempre
/// que o app escreve `clientes.telefone` esperando que a RPC
/// `entrar_ou_criar_cliente` consiga casar por telefone depois (ver
/// `ClienteRepository.redefinirAcesso`) — o campo de "Editar Dados" comum
/// não passa por aqui, então um telefone salvo só ali (com máscara) não
/// bate com o JWT até passar por uma ação que normalize.
String normalizarTelefoneParaAuth(String texto) {
  var digitos = texto.replaceAll(RegExp(r'[^0-9]'), '');
  if (!digitos.startsWith('55') || digitos.length < 12) {
    digitos = '55$digitos';
  }
  return digitos;
}

/// Monta o link do wa.me a partir de um telefone em qualquer formato já
/// salvo no banco. Sem normalizar primeiro, um número já salvo com o "55"
/// (comum em dados vindos de outras origens) virava "5555..." no link e o
/// WhatsApp não encontrava o contato.
///
/// Um "+" no início marca "já é internacional, não mexe" — usado pra
/// clientes de outros países (chegam assim via integração do WhatsApp,
/// ver telefone.replace('+','') condicional no n8n). Sem essa saída, todo
/// telefone levava "55" na frente e o link saía errado pra quem não é
/// do Brasil.
String linkWhatsApp(String telefone) {
  if (telefone.trim().startsWith('+')) {
    return 'https://wa.me/${telefone.replaceAll(RegExp(r'[^0-9]'), '')}';
  }
  return 'https://wa.me/55${normalizarTelefoneBr(telefone)}';
}
