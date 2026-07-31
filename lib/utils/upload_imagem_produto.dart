import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Largura máxima (px) e qualidade JPEG aplicadas antes do upload — mesmos
/// parâmetros usados no reprocessamento em lote das fotos de fornecedor
/// (ver memória do projeto), agora também no upload manual pelo app.
const _larguraMaximaPx = 1200;
const _qualidadeJpeg = 82;

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
/// Lança exceção em caso de falha de rede — quem chama decide como
/// comunicar isso ao usuário. Compartilhado entre cadastro, edição e
/// galeria de imagens de produto (individual e em lote) pra não
/// triplicar a mesma lógica.
Future<String> uploadImagemProduto({
  required Uint8List bytes,
  required String empresaId,
  required String nomeProduto,
  required String codigoBarras,
  required int ordem,
  String? fabricante,
  String? marca,
}) async {
  final bytesProcessados = _comprimirEAchatarFundo(bytes);

  final fabricanteSlug = _slugify(_resolverFabricante(fabricante, nomeProduto, marca));
  final baseNome = codigoBarras.trim().isNotEmpty ? codigoBarras.trim() : 'sem-codigo';
  final path = '$empresaId/$fabricanteSlug/${baseNome}_$ordem.jpg';

  await supabase.storage.from('produtos').uploadBinary(
        path,
        bytesProcessados,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
      );

  return supabase.storage.from('produtos').getPublicUrl(path);
}

/// Redimensiona e recodifica como JPEG com fundo branco. Se a decodificação
/// falhar por algum motivo (formato inesperado etc), sobe os bytes
/// originais sem processar — nunca bloqueia o upload por causa disso.
Uint8List _comprimirEAchatarFundo(Uint8List bytesOriginais) {
  final decodificada = img.decodeImage(bytesOriginais);
  if (decodificada == null) return bytesOriginais;

  final redimensionada = decodificada.width > _larguraMaximaPx
      ? img.copyResize(decodificada, width: _larguraMaximaPx)
      : decodificada;

  final comFundoBranco = img.Image(
    width: redimensionada.width,
    height: redimensionada.height,
    numChannels: 3,
  );
  img.fill(comFundoBranco, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(comFundoBranco, redimensionada);

  return img.encodeJpg(comFundoBranco, quality: _qualidadeJpeg);
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
