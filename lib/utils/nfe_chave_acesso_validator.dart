/// Valida o dígito verificador (módulo 11) da chave de acesso de 44
/// dígitos de uma NF-e — pega leitura errada de código de barras (DANFE
/// com mais de um código por perto, ex: boleto) ou digitação errada ANTES
/// de gastar uma chamada de verdade à Sefaz, que só devolveria "não
/// encontrado" (achado real 15/09: essa ambiguidade — chave errada vs.
/// nota realmente não indexada ainda — confundiu um caso de teste).
bool chaveDeAcessoValida(String chave) {
  if (chave.length != 44 || !RegExp(r'^\d{44}$').hasMatch(chave)) return false;

  final digitos43 = chave.substring(0, 43);
  final dvInformado = int.parse(chave.substring(43));

  var soma = 0;
  var peso = 2;
  for (var i = digitos43.length - 1; i >= 0; i--) {
    soma += int.parse(digitos43[i]) * peso;
    peso = peso == 9 ? 2 : peso + 1;
  }
  final resto = soma % 11;
  final dvCalculado = (resto == 0 || resto == 1) ? 0 : 11 - resto;

  return dvInformado == dvCalculado;
}
