import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/despesa.dart';
import '../models/venda.dart';
import '../providers/despesa_provider.dart';
import '../providers/historico_vendas_provider.dart';
import '../utils/canal_venda_utils.dart';

/// Configurações > Exportar Relatórios: exporta vendas ou despesas de um
/// período pra planilha (.xlsx), pra abrir no Excel/Google Sheets.
class ExportarRelatoriosScreen extends StatefulWidget {
  const ExportarRelatoriosScreen({super.key});

  @override
  State<ExportarRelatoriosScreen> createState() => _ExportarRelatoriosScreenState();
}

class _ExportarRelatoriosScreenState extends State<ExportarRelatoriosScreen> {
  late DateTimeRange _periodo;
  String _filtroRotulo = 'Este mês';
  bool _exportando = false;

  @override
  void initState() {
    super.initState();
    final hoje = DateTime.now();
    _periodo = DateTimeRange(start: DateTime(hoje.year, hoje.month, 1), end: hoje);
  }

  bool _dentroDoPeriodo(DateTime data) {
    final inicio = DateTime(_periodo.start.year, _periodo.start.month, _periodo.start.day);
    final fim = DateTime(_periodo.end.year, _periodo.end.month, _periodo.end.day, 23, 59, 59);
    return !data.isBefore(inicio) && !data.isAfter(fim);
  }

  Future<void> _escolherPeriodo(String rotulo) async {
    final hoje = DateTime.now();
    DateTimeRange novoPeriodo;
    switch (rotulo) {
      case 'Este mês':
        novoPeriodo = DateTimeRange(start: DateTime(hoje.year, hoje.month, 1), end: hoje);
        break;
      case 'Mês passado':
        novoPeriodo = DateTimeRange(start: DateTime(hoje.year, hoje.month - 1, 1), end: DateTime(hoje.year, hoje.month, 0));
        break;
      case 'Este ano':
        novoPeriodo = DateTimeRange(start: DateTime(hoje.year, 1, 1), end: hoje);
        break;
      case 'Personalizado':
        final escolhido = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: hoje,
          initialDateRange: _periodo,
        );
        if (escolhido == null) return;
        novoPeriodo = escolhido;
        break;
      default:
        return;
    }
    setState(() {
      _periodo = novoPeriodo;
      _filtroRotulo = rotulo;
    });
  }

  Future<void> _exportarESalvar(Excel workbook, String nomeArquivo, String textoCompartilhar) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$nomeArquivo');
    final bytes = workbook.encode();
    if (bytes == null) throw Exception('Falha ao gerar a planilha.');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)], text: textoCompartilhar);
  }

  Future<void> _exportarVendas() async {
    setState(() => _exportando = true);
    try {
      final provider = context.read<HistoricoVendasProvider>();
      await provider.carregarVendas();
      if (!mounted) return;

      final vendas = provider.vendas.where((v) => _dentroDoPeriodo(v.dataVenda)).toList()
        ..sort((a, b) => a.dataVenda.compareTo(b.dataVenda));

      final workbook = Excel.createExcel();
      final sheet = workbook['Vendas'];
      workbook.delete('Sheet1');

      sheet.appendRow([
        TextCellValue('Data'),
        TextCellValue('Cliente'),
        TextCellValue('Status'),
        TextCellValue('Forma de Pagamento'),
        TextCellValue('Canal'),
        TextCellValue('Subtotal'),
        TextCellValue('Desconto'),
        TextCellValue('Entrega'),
        TextCellValue('Total'),
        TextCellValue('Custo'),
        TextCellValue('Lucro'),
      ]);

      final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
      for (final Venda venda in vendas) {
        sheet.appendRow([
          TextCellValue(dateFormat.format(venda.dataVenda)),
          TextCellValue(venda.cliente.nome),
          TextCellValue(StatusPedido.rotulo(venda.status)),
          TextCellValue(venda.metodoPagamento),
          TextCellValue(rotuloCanalVenda(venda.canalVenda)),
          DoubleCellValue(venda.subtotal),
          DoubleCellValue(venda.desconto),
          DoubleCellValue(venda.valorEntrega),
          DoubleCellValue(venda.valorTotal),
          DoubleCellValue(venda.custoTotal),
          DoubleCellValue(venda.lucroTotal),
        ]);
      }

      await _exportarESalvar(
        workbook,
        'vendas_${DateFormat('yyyyMMdd').format(_periodo.start)}_${DateFormat('yyyyMMdd').format(_periodo.end)}.xlsx',
        'Relatório de vendas (${vendas.length} registros)',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao exportar vendas: $e')));
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Future<void> _exportarDespesas() async {
    setState(() => _exportando = true);
    try {
      final provider = context.read<DespesaProvider>();
      await provider.carregar();
      if (!mounted) return;

      final despesas = provider.despesas.where((d) => _dentroDoPeriodo(d.dataVencimento)).toList()
        ..sort((a, b) => a.dataVencimento.compareTo(b.dataVencimento));

      final workbook = Excel.createExcel();
      final sheet = workbook['Despesas'];
      workbook.delete('Sheet1');

      sheet.appendRow([
        TextCellValue('Descrição'),
        TextCellValue('Categoria'),
        TextCellValue('Fornecedor'),
        TextCellValue('Vencimento'),
        TextCellValue('Pagamento'),
        TextCellValue('Status'),
        TextCellValue('Valor'),
      ]);

      final dateFormat = DateFormat('dd/MM/yyyy');
      for (final Despesa despesa in despesas) {
        sheet.appendRow([
          TextCellValue(despesa.descricao),
          TextCellValue(despesa.categoria),
          TextCellValue(despesa.fornecedor?.nome ?? ''),
          TextCellValue(dateFormat.format(despesa.dataVencimento)),
          TextCellValue(despesa.dataPagamento != null ? dateFormat.format(despesa.dataPagamento!) : ''),
          TextCellValue(despesa.atrasada ? 'Atrasada' : (despesa.paga ? 'Paga' : (despesa.cancelada ? 'Cancelada' : 'Pendente'))),
          DoubleCellValue(despesa.valor),
        ]);
      }

      await _exportarESalvar(
        workbook,
        'despesas_${DateFormat('yyyyMMdd').format(_periodo.start)}_${DateFormat('yyyyMMdd').format(_periodo.end)}.xlsx',
        'Relatório de despesas (${despesas.length} registros)',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao exportar despesas: $e')));
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar: AppBar(title: const Text('Exportar Relatórios')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Escolha o período e o relatório que quer exportar em planilha (.xlsx).',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ...['Este mês', 'Mês passado', 'Este ano', 'Personalizado'].map((rotulo) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(rotulo),
                          selected: _filtroRotulo == rotulo,
                          onSelected: _exportando ? null : (_) => _escolherPeriodo(rotulo),
                        ),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${dateFormat.format(_periodo.start)} - ${dateFormat.format(_periodo.end)}',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 24),
            if (_exportando)
              const Center(child: CircularProgressIndicator())
            else ...[
              Card(
                child: ListTile(
                  leading: Icon(Icons.point_of_sale, color: Theme.of(context).colorScheme.primary),
                  title: const Text('Exportar Vendas'),
                  subtitle: const Text('Todas as vendas do período, com status e valores'),
                  trailing: const Icon(Icons.download),
                  onTap: _exportarVendas,
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long, color: Colors.red),
                  title: const Text('Exportar Despesas'),
                  subtitle: const Text('Todas as despesas com vencimento no período'),
                  trailing: const Icon(Icons.download),
                  onTap: _exportarDespesas,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
