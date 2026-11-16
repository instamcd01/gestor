import 'package:diacritic/diacritic.dart';

String normalizarBusca(String texto) => removeDiacritics(texto).toLowerCase();

/// Cada palavra de [busca] precisa aparecer em [textoAlvo], em qualquer
/// ordem/posição — ex: busca "racao salmao" bate em "Ração ... Sabor Salmão".
bool contemTodasPalavras(String textoAlvo, String busca) {
  final termo = normalizarBusca(busca).trim();
  if (termo.isEmpty) return true;
  final alvo = normalizarBusca(textoAlvo);
  final palavras = termo.split(RegExp(r'\s+'));
  return palavras.every((p) => alvo.contains(p));
}

/// Nome sem o sufixo " – Fabricante" do padrão de nome, só quando o sufixo
/// é mesmo o fabricante cadastrado (em 3 produtos o sufixo é a marca — fica).
String nomeSemFabricante(String nome, String? fabricante) {
  final n = normalizarBusca(nome);
  final fab = normalizarBusca(fabricante ?? '').trim();
  if (fab.isEmpty) return n;
  final m = RegExp(r'^(.*)\s[–—-]\s([^–—]+)$').firstMatch(n);
  if (m == null) return n;
  final sufixo = m.group(2)!.trim();
  final sufixoJunto = sufixo.replaceAll(RegExp(r'\s+'), '');
  final fabJunto = fab.replaceAll(RegExp(r'\s+'), '');
  final primeiraSufixo = sufixo.split(RegExp(r'\s+')).first;
  final primeiraFab = fab.split(RegExp(r'\s+')).first;
  if (sufixoJunto.contains(primeiraFab) || fabJunto.contains(primeiraSufixo)) return m.group(1)!;
  return n;
}

/// Busca de PRODUTO (mesma regra do site e do WhatsApp — `produto_bate_padroes`
/// no banco): cada palavra precisa estar no texto (nome sem o sufixo do
/// fabricante + marca) OU fazer parte do nome do fabricante; e pelo menos uma
/// palavra precisa estar no texto ou ser o fabricante inteiro.
/// "premier" = linha Premier; "golden premier" = Golden; "premierpet" = tudo.
/// Achado 16/11: "premier" trazia toda a Golden (nome termina em "– PremieRpet").
bool produtoBateBusca(String nome, String busca, {String? marca, String? fabricante}) {
  final termo = normalizarBusca(busca).trim();
  if (termo.isEmpty) return true;
  final fabJunto = normalizarBusca(fabricante ?? '').replaceAll(RegExp(r'\s+'), '');
  final alvo = '${nomeSemFabricante(nome, fabricante)} ${normalizarBusca(marca ?? '')}';
  final palavras = termo.split(RegExp(r'\s+'));
  bool noTexto(String p) => alvo.contains(p);
  bool parteDoFabricante(String p) => p.length >= 3 && fabJunto.contains(p);
  return palavras.every((p) => noTexto(p) || parteDoFabricante(p)) &&
      palavras.any((p) => noTexto(p) || (fabJunto.isNotEmpty && fabJunto == p));
}
