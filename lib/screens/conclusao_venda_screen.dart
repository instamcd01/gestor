import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class ConclusaoVendaScreen extends StatelessWidget {
  final double valorTotal;

  ConclusaoVendaScreen({required this.valorTotal});

  // Função para gerar o PDF do recibo
  Future<void> gerarRecibo(BuildContext context) async {
    final pdf = pw.Document();

    // Adiciona uma página ao PDF
    pdf.addPage(pw.Page(
      build: (pw.Context context) {
        return pw.Center(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Recibo de Venda',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  )),
              pw.SizedBox(height: 20),
              pw.Text('Data: ${DateTime.now().toString()}'),
              pw.SizedBox(height: 10),
              pw.Text('Valor Total: R\$ ${valorTotal.toStringAsFixed(2)}'),
              pw.SizedBox(height: 20),
              pw.Text('Obrigado por sua compra!',
                  style: pw.TextStyle(fontSize: 16)),
            ],
          ),
        );
      },
    ));

    // Obter o diretório de downloads no Android
    final directory = await getExternalStorageDirectory();
    final downloadDirectory = Directory('${directory!.path}/Download'); // Define o diretório de downloads
    if (!await downloadDirectory.exists()) {
      await downloadDirectory.create(recursive: true);
    }

    final file = File('${downloadDirectory.path}/recibo_venda.pdf');

    // Salva o arquivo PDF no diretório de downloads
    await file.writeAsBytes(await pdf.save());

    // Exibe uma mensagem de sucesso
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Recibo baixado com sucesso!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Venda Concluída'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 100,
            ),
            SizedBox(height: 20),
            Text(
              'Venda Concluída com Sucesso!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Text(
              'Valor Total: R\$ ${valorTotal.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 20),
            ),
            SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () {
                // Chama a função de geração de PDF
                gerarRecibo(context);
              },
              icon: Icon(Icons.download),
              label: Text('Baixar Recibo'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
                textStyle: TextStyle(fontSize: 18),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                // Navegar para a tela de vendas
                Navigator.popUntil(
                    context, (route) => route.isFirst); // Voltar para a tela inicial
              },
              icon: Icon(Icons.shopping_bag),
              label: Text('Nova Venda'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
                textStyle: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
