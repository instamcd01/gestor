import 'dart:io';

import 'package:barcode_scan2/barcode_scan2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Abre a câmera pra ler um código de barras/QR e devolve o conteúdo bruto —
/// usado tanto pro código de barras (EAN) de produto quanto pra chave de
/// acesso de 44 dígitos impressa (como texto de barras Code-128) em cima de
/// qualquer DANFE, ambos evitando digitação manual. `null` sempre que não
/// deu pra ler (cancelado, sem câmera na plataforma, permissão negada) — quem
/// chama não precisa distinguir o motivo, só mostrar o valor se vier algo.
///
/// Só Android/iOS têm implementação nativa neste pacote (`barcode_scan2`) —
/// Windows/desktop e web não têm câmera suportada por ele, então nem tenta
/// (evita `MissingPluginException` travando a tela).
Future<String?> lerCodigoDeBarras(BuildContext context) async {
  if (!(Platform.isAndroid || Platform.isIOS)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Leitor de código de barras só está disponível no celular.')),
    );
    return null;
  }

  try {
    final resultado = await BarcodeScanner.scan();
    if (resultado.type != ResultType.Barcode) return null;
    final conteudo = resultado.rawContent.trim();
    return conteudo.isEmpty ? null : conteudo;
  } on PlatformException catch (e) {
    if (!context.mounted) return null;
    final mensagem = e.code == BarcodeScanner.cameraAccessDenied
        ? 'Permissão de câmera negada — habilite nas configurações do app pra usar o leitor.'
        : 'Erro ao abrir a câmera: ${e.message ?? e.code}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));
    return null;
  } catch (e) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao ler código de barras: $e')));
    return null;
  }
}
