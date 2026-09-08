import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Largura máxima (px) e qualidade JPEG aplicadas antes do upload — mesmos
/// parâmetros usados no reprocessamento em lote das fotos de fornecedor
/// (ver memória do projeto), agora também no upload manual pelo app.
const _larguraMaximaPx = 1200;
const _qualidadeJpeg = 82;

/// Largura máxima (px) só pra tela de recorte — mais folgada que a final
/// (1200px), suficiente pra enquadrar bem numa tela de celular sem carregar
/// o arquivo bruto do picker inteiro (uma foto com fundo removido facilmente
/// sai em 3-4000px do app que gerou, bem mais do que qualquer tela precisa
/// mostrar).
const _larguraMaximaParaRecortePx = 1600;

/// Faz upload de uma imagem de produto pro bucket `produtos` do Supabase
/// Storage e retorna a URL pública. Antes de subir, redimensiona (largura
/// máx. 1200px) e recodifica sempre como JPEG com fundo branco — achata
/// qualquer transparência, evitando tanto arquivos gigantes (fotos de
/// celular sem compressão) quanto o bug de fundo preto que apareceu num
/// lote processado por um script `sharp` que não definia `background`.
///
/// O path no Storage segue a mesma convenção usada no reprocessamento em
/// lote das fotos de fornecedor: `{empresa}/{fabricante}/{codigo_barras}_{ordem}.jpg`
/// — fabricante vem do campo estruturado `produtos.fabricante` sempre que
/// preenchido (fonte confiável). Só cai pro heurístico (extrair do final do
/// nome, padrão "... — Fabricante", ou `marca`) pra produtos ainda sem esse
/// campo preenchido — `marca` neste banco historicamente guarda o
/// fornecedor/distribuidor, não o fabricante real (ver memória "Padrão de
/// nome de produto" do projeto), então é só o último recurso, não a fonte
/// primária. `upsert: true` porque recortar/substituir a imagem de um slot
/// (mesmo produto + mesma ordem) deve sobrescrever o arquivo antigo, não
/// acumular lixo no bucket.
///
/// `codigoBarras` só é usado como chave do arquivo quando é um código real
/// — "0"/vazio é placeholder de "sem código" usado por dezenas de produtos
/// (achado em produção: 15 produtos com fabricante vazio + código "0"
/// dividindo o mesmo path). Nesses casos cai pro `produtoId` (sempre único)
/// em vez do código, senão o upload de um produto sobrescreve, no mesmo
/// arquivo do Storage, a foto de outro produto sem relação nenhuma — o
/// upload aparentava corromper a imagem de um produto ao mexer em outro.
///
/// Lança exceção em caso de falha de rede — quem chama decide como
/// comunicar isso ao usuário. Compartilhado entre cadastro, edição e
/// galeria de imagens de produto (individual e em lote) pra não
/// triplicar a mesma lógica.
Future<String> uploadImagemProduto({
  required Uint8List bytes,
  required String empresaId,
  required String produtoId,
  required String nomeProduto,
  required String codigoBarras,
  required int ordem,
  String? fabricante,
  String? marca,
}) async {
  final bytesProcessados = await _redimensionarEAchatarFundo(bytes, _larguraMaximaPx);

  final fabricanteSlug = _slugify(_resolverFabricante(fabricante, nomeProduto, marca));
  final baseNome = _codigoBarrasValido(codigoBarras) ? codigoBarras.trim() : produtoId;
  final path = '$empresaId/$fabricanteSlug/${baseNome}_$ordem.jpg';

  await supabase.storage.from('produtos').uploadBinary(
        path,
        bytesProcessados,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
      );

  return supabase.storage.from('produtos').getPublicUrl(path);
}

/// Reduz a imagem ANTES de abrir a tela de recorte — mantém transparência
/// (sempre devolve PNG, que suporta alfa) porque o enquadramento precisa
/// mostrar o fundo removido de verdade; só vira branco depois, no upload
/// final. Ver `_decodificarReduzido` sobre por que isso usa `dart:ui` (rápido
/// em qualquer plataforma, inclusive web) em vez do pacote `image`.
Future<Uint8List> prepararImagemParaRecorte(Uint8List bytes) async {
  final imagemReduzida = await _decodificarReduzido(bytes, _larguraMaximaParaRecortePx);
  if (imagemReduzida == null) return bytes;
  final png = await imagemReduzida.toByteData(format: ui.ImageByteFormat.png);
  imagemReduzida.dispose();
  return png?.buffer.asUint8List() ?? bytes;
}

/// Decodifica (já reduzindo, via `targetWidth`) usando a engine do Flutter
/// (`dart:ui`/Skia) — a mesma que todo `Image.network`/`Image.memory` do app
/// já usa — em vez do pacote `image`, que é decodificação pura em Dart.
///
/// Isso importa especialmente na web: `compute()` (usado antes aqui) NÃO
/// roda em isolate de verdade nesse ambiente — é uma limitação documentada
/// do próprio Flutter (não existe isolate real no Dart compilado pra web),
/// então a função continuava rodando no mesmo thread da UI, travando a
/// aba inteira mesmo "rodando em isolate separada". `dart:ui` não tem esse
/// problema — decodifica/redimensiona usando a engine nativa (Skia/CanvasKit
/// na web), rápido e sem travar em qualquer plataforma.
///
/// Não verifica se a imagem já é menor que `larguraMaxima` antes de pedir o
/// `targetWidth` (evitaria um 2º decode só pra descobrir o tamanho, que
/// anularia o ganho de performance) — no pior caso (imagem já pequena),
/// o decoder não amplia a imagem além do tamanho original.
Future<ui.Image?> _decodificarReduzido(Uint8List bytes, int larguraMaxima) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: larguraMaxima);
    final frame = await codec.getNextFrame();
    return frame.image;
  } catch (_) {
    return null;
  }
}

/// Redimensiona (via `dart:ui`, ver `_decodificarReduzido`) e achata
/// qualquer transparência pra fundo branco desenhando num canvas nativo —
/// só a codificação final como JPEG usa o pacote `image` em Dart puro, e só
/// depois de já reduzida (rápido mesmo sem isolate de verdade, caso da web).
/// Se a decodificação falhar por algum motivo (formato inesperado etc),
/// sobe os bytes originais sem processar — nunca bloqueia o upload por
/// causa disso.
Future<Uint8List> _redimensionarEAchatarFundo(Uint8List bytesOriginais, int larguraMaxima) async {
  final decodificada = await _decodificarReduzido(bytesOriginais, larguraMaxima);
  if (decodificada == null) return bytesOriginais;

  final largura = decodificada.width;
  final altura = decodificada.height;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, largura.toDouble(), altura.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  canvas.drawImage(decodificada, ui.Offset.zero, ui.Paint());
  final composta = await recorder.endRecording().toImage(largura, altura);
  decodificada.dispose();

  final bytesRgba = await composta.toByteData(format: ui.ImageByteFormat.rawRgba);
  composta.dispose();
  if (bytesRgba == null) return bytesOriginais;

  final dadosCrus = _DadosImagemCrua(
    bytes: bytesRgba.buffer.asUint8List(),
    largura: largura,
    altura: altura,
  );
  return compute(_codificarJpeg, dadosCrus);
}

/// Só pra atravessar a fronteira do `compute()` com um argumento só.
class _DadosImagemCrua {
  final Uint8List bytes;
  final int largura;
  final int altura;
  const _DadosImagemCrua({required this.bytes, required this.largura, required this.altura});
}

Uint8List _codificarJpeg(_DadosImagemCrua dados) {
  final imagem = img.Image.fromBytes(
    width: dados.largura,
    height: dados.altura,
    bytes: dados.bytes.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(imagem, quality: _qualidadeJpeg);
}

/// "0" e vazio são os dois jeitos que este banco usa pra dizer "sem código
/// de barras real" (ver achado de colisão de path acima) — nenhum dos dois
/// serve como chave única de arquivo.
bool _codigoBarrasValido(String codigoBarras) {
  final normalizado = codigoBarras.trim();
  return normalizado.isNotEmpty && normalizado != '0';
}

/// Resolve o fabricante a usar na pasta do Storage, em ordem de confiança:
/// (1) campo estruturado `produtos.fabricante`, quando preenchido — única
/// fonte realmente confiável; (2) padrão `... — Fabricante` no final do
/// nome (aceita em-dash "—" e en-dash "–": checado direto no banco, a
/// maioria real dos produtos com travessão usa en-dash, não em-dash como os
/// exemplos da convenção original sugeriam); (3) `marca`, sabendo que neste
/// banco historicamente guarda o fornecedor/distribuidor, não o fabricante
/// real (ver memória "Padrão de nome de produto" do projeto) — por isso é
/// só o último recurso, nunca a primeira escolha.
String _resolverFabricante(String? fabricante, String nomeProduto, String? marca) {
  final fabricanteLimpo = fabricante?.trim();
  if (fabricanteLimpo != null && fabricanteLimpo.isNotEmpty) return fabricanteLimpo;

  final match = RegExp(r'[—–]\s*([^—–]+)$').firstMatch(nomeProduto);
  final extraidoDoNome = match?.group(1)?.trim();
  if (extraidoDoNome != null && extraidoDoNome.isNotEmpty) return extraidoDoNome;

  final marcaLimpa = marca?.trim();
  if (marcaLimpa != null && marcaLimpa.isNotEmpty) return marcaLimpa;

  return 'sem-fabricante';
}

const _comAcento = 'áàãâäéèêëíìîïóòõôöúùûüçñÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇÑ';
const _semAcento = 'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN';

/// Normaliza um texto pra usar como segmento de path no Storage: sem
/// acento, minúsculo, só `[a-z0-9-]`. Evita qualquer problema de
/// encoding/URL em nomes de fabricante com acento (Agener União, König etc).
String _slugify(String texto) {
  var resultado = texto;
  for (var i = 0; i < _comAcento.length; i++) {
    resultado = resultado.replaceAll(_comAcento[i], _semAcento[i]);
  }
  resultado = resultado
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  return resultado.isEmpty ? 'sem-fabricante' : resultado;
}
