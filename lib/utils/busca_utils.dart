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
