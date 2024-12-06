import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

class GerarPlanilhaBaseScreen extends StatelessWidget {
  // Função para gerar a planilha base
  Future<void> gerarPlanilhaBase(BuildContext context) async {
    var excel = Excel.createExcel(); // Cria uma nova planilha
    Sheet sheet = excel['Produtos']; // Cria uma aba chamada "Produtos"

    // Definindo as colunas da planilha
    sheet.appendRow([
      'Nome',
      'Categoria',
      'Código de Barras',
      'Custo',
      'Preço',
      'Preço Ifood',
      'Validade',
      'Estoque Atual',
      'Estoque Mínimo',
      'Markup',
      'Lucro',
      'Preço Concorrência',
      'Empresa',
      'ID',
      'Preço Promocional',
      'Destacar',
      'Exibir no Catálogo'
    ]);

    // Obter o diretório onde o arquivo será salvo
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/produtos_template.xlsx');

    // Salvar o arquivo Excel no diretório
    final bytes = await excel.encode() ?? [];
    await file.writeAsBytes(bytes);

    // Usando share_plus para compartilhar o arquivo gerado
    await Share.shareFiles([file.path], text: 'Aqui está a planilha de produtos para preenchimento!');

    // Exibir informativo com o local onde o arquivo foi salvo
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Planilha gerada com sucesso! Salva em: ${file.path}',
          style: TextStyle(fontSize: 16),
        ),
        duration: Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Gerar Planilha Base'),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: () => gerarPlanilhaBase(context),
          child: Text('Gerar Planilha Base'),
        ),
      ),
    );
  }
}
