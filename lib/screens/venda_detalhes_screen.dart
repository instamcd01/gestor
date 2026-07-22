import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/supabase_config.dart';
import '../models/venda.dart';
import '../providers/auth_provider.dart';
import '../providers/historico_vendas_provider.dart';

class VendaDetalhesScreen extends StatefulWidget {
  final Venda venda;

  const VendaDetalhesScreen({super.key, required this.venda});

  @override
  State<VendaDetalhesScreen> createState() => _VendaDetalhesScreenState();
}

class _VendaDetalhesScreenState extends State<VendaDetalhesScreen> {
  late Venda _venda;
  bool _processando = false;

  @override
  void initState() {
    super.initState();
    _venda = widget.venda;
  }

  Future<void> _abrirWhatsApp(String numero) async {
    final numeroLimpo = numero.replaceAll(RegExp(r'[^0-9]'), '');
    if (numeroLimpo.isEmpty) return;
    final uri = Uri.parse('https://wa.me/55$numeroLimpo');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _abrirMapa(String endereco) async {
    if (endereco.isEmpty) return;
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(endereco)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  pw.Widget _celulaRecibo(String texto, {bool cabecalho = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        texto,
        style: pw.TextStyle(fontWeight: cabecalho ? pw.FontWeight.bold : pw.FontWeight.normal),
      ),
    );
  }

  Future<Map<String, dynamic>> _carregarConfigRecibo() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return {};
    try {
      return await supabase
          .from('empresas')
          .select('nome, razao_social, cnpj, logo_url, recibo_mensagem, recibo_mostrar_logo, recibo_mostrar_cnpj')
          .eq('id', empresaId)
          .single();
    } catch (e) {
      debugPrint('Erro ao carregar configuração do recibo: $e');
      return {};
    }
  }

  Future<void> _compartilharRecibo() async {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final temEntrega = _venda.valorEntrega > 0 || _venda.entregaSelecionada.isNotEmpty;

    final config = await _carregarConfigRecibo();
    final mostrarLogo = config['recibo_mostrar_logo'] as bool? ?? true;
    final mostrarCnpj = config['recibo_mostrar_cnpj'] as bool? ?? true;
    final mensagemRodape = config['recibo_mensagem']?.toString() ?? '';
    final nomeLoja = config['nome']?.toString() ?? '';
    final razaoSocial = config['razao_social']?.toString() ?? '';
    final cnpj = config['cnpj']?.toString() ?? '';
    final logoUrl = config['logo_url']?.toString() ?? '';

    pw.MemoryImage? logoImagem;
    if (mostrarLogo && logoUrl.isNotEmpty) {
      try {
        final resposta = await http.get(Uri.parse(logoUrl));
        if (resposta.statusCode == 200) {
          logoImagem = pw.MemoryImage(resposta.bodyBytes);
        }
      } catch (e) {
        debugPrint('Erro ao baixar logo pro recibo: $e');
      }
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logoImagem != null) ...[
                pw.Center(child: pw.Image(logoImagem, height: 60)),
                pw.SizedBox(height: 8),
              ],
              pw.Text(
                nomeLoja.isNotEmpty ? nomeLoja : 'Recibo de Venda',
                style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
              ),
              if (mostrarCnpj && (razaoSocial.isNotEmpty || cnpj.isNotEmpty))
                pw.Text(
                  [razaoSocial, if (cnpj.isNotEmpty) 'CNPJ: $cnpj'].where((s) => s.isNotEmpty).join(' • '),
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                ),
              pw.SizedBox(height: 12),
              pw.Text('Cliente: ${_venda.cliente.nome}'),
              pw.Text('Data: ${DateFormat('dd/MM/yyyy HH:mm').format(_venda.dataVenda)}'),
              pw.Text('ID da Venda: ${_venda.idVenda ?? '-'}'),
              pw.Text('Forma de Pagamento: ${_venda.metodoPagamento}'),
              pw.SizedBox(height: 16),
              pw.Table(
                border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey600),
                columnWidths: const {
                  0: pw.FlexColumnWidth(4),
                  1: pw.FlexColumnWidth(1.3),
                  2: pw.FlexColumnWidth(2),
                  3: pw.FlexColumnWidth(2),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                    children: [
                      _celulaRecibo('Produto', cabecalho: true),
                      _celulaRecibo('Qtd', cabecalho: true),
                      _celulaRecibo('Unit.', cabecalho: true),
                      _celulaRecibo('Total', cabecalho: true),
                    ],
                  ),
                  ..._venda.itens.map((item) => pw.TableRow(children: [
                        _celulaRecibo(item.produto.nome),
                        _celulaRecibo('${item.quantidade}'),
                        _celulaRecibo(currencyFormat.format(item.precoUnitario)),
                        _celulaRecibo(currencyFormat.format(item.precoTotal)),
                      ])),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Subtotal: ${currencyFormat.format(_venda.subtotal)}'),
                    if (_venda.desconto > 0)
                      pw.Text('Desconto: -${currencyFormat.format(_venda.desconto)}'),
                    if (temEntrega)
                      pw.Text('Entrega: +${currencyFormat.format(_venda.valorEntrega)}'),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Total: ${currencyFormat.format(_venda.valorTotal)}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
                    ),
                    pw.Text('Valor Pago: ${currencyFormat.format(_venda.valorPago)}'),
                    if (_venda.troco > 0) pw.Text('Troco: ${currencyFormat.format(_venda.troco)}'),
                  ],
                ),
              ),
              if (_venda.observacao.isNotEmpty) ...[
                pw.SizedBox(height: 16),
                pw.Text('Observações: ${_venda.observacao}'),
              ],
              if (mensagemRodape.isNotEmpty) ...[
                pw.SizedBox(height: 20),
                pw.Center(
                  child: pw.Text(mensagemRodape, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
                ),
              ],
            ],
          );
        },
      ),
    );

    final directory = await getApplicationDocumentsDirectory();
    final nomeArquivo = 'recibo_${_venda.idVenda ?? DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${directory.path}/$nomeArquivo');
    await file.writeAsBytes(await pdf.save());

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Recibo da venda de ${_venda.cliente.nome}',
    );
  }

  Future<void> _confirmarCancelamento() async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar venda'),
        content: const Text(
          'Isso vai devolver os itens ao estoque, devolver o saldo do cliente usado (se houve) '
          'e marcar a venda como cancelada. Essa ação não pode ser desfeita. Confirmar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancelar Venda', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmou != true || _venda.idVenda == null || !mounted) return;

    final historicoProvider = Provider.of<HistoricoVendasProvider>(context, listen: false);
    setState(() => _processando = true);
    try {
      await historicoProvider.cancelarVenda(_venda.idVenda!);
      if (!mounted) return;
      setState(() {
        _venda = Venda(
          idVenda: _venda.idVenda,
          cliente: _venda.cliente,
          dataVenda: _venda.dataVenda,
          subtotal: _venda.subtotal,
          desconto: _venda.desconto,
          saldoUsado: _venda.saldoUsado,
          valorEntrega: _venda.valorEntrega,
          entregaSelecionada: _venda.entregaSelecionada,
          valorTotal: _venda.valorTotal,
          valorPago: _venda.valorPago,
          troco: _venda.troco,
          metodoPagamento: _venda.metodoPagamento,
          totalItens: _venda.totalItens,
          itens: _venda.itens,
          custoTotal: _venda.custoTotal,
          lucroTotal: _venda.lucroTotal,
          observacao: _venda.observacao,
          pagamentosDetalhados: _venda.pagamentosDetalhados,
          status: 'cancelado',
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Venda cancelada. Estoque e saldo do cliente foram estornados.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível cancelar a venda: $e')),
      );
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final venda = _venda;
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final temEntrega = venda.valorEntrega > 0 || venda.entregaSelecionada.isNotEmpty;
    final cancelada = venda.cancelada;

    return Scaffold(
      appBar: AppBar(
        title: Text('Venda - ${venda.cliente.nome}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Compartilhar recibo',
            onPressed: _compartilharRecibo,
          ),
          if (!cancelada)
            IconButton(
              icon: const Icon(Icons.cancel_outlined),
              tooltip: 'Cancelar venda',
              onPressed: _processando ? null : _confirmarCancelamento,
            ),
        ],
      ),
      body: Stack(
        children: [
          Opacity(
            opacity: cancelada ? 0.6 : 1,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (cancelada) _bannerCancelada(),

                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _linhaInfo(Icons.receipt_long, 'ID da Venda', venda.idVenda ?? '-'),
                      _linhaInfo(Icons.calendar_today,
                          'Data', DateFormat('dd/MM/yyyy • HH:mm').format(venda.dataVenda)),
                      _linhaInfo(Icons.payment, 'Forma de Pagamento', venda.metodoPagamento),
                      if (venda.cliente.celular.isNotEmpty)
                        _linhaComAcao(
                          icon: Icons.phone,
                          label: 'Telefone',
                          valor: venda.cliente.celular,
                          iconAcao: Icons.chat,
                          corAcao: Colors.green,
                          onTap: () => _abrirWhatsApp(venda.cliente.celular),
                        ),
                      if (temEntrega && venda.cliente.enderecoCompleto.isNotEmpty)
                        _linhaComAcao(
                          icon: Icons.location_on,
                          label: 'Endereço',
                          valor: venda.cliente.enderecoCompleto,
                          iconAcao: Icons.map,
                          corAcao: Theme.of(context).colorScheme.primary,
                          onTap: () => _abrirMapa(venda.cliente.enderecoCompleto),
                          ultima: true,
                        ),
                    ],
                  ),
                ),

                if (venda.pagamentosDetalhados != null && venda.pagamentosDetalhados!.isNotEmpty)
                  _card(
                    titulo: 'Pagamentos Detalhados',
                    child: Column(
                      children: venda.pagamentosDetalhados!.entries
                          .map((entry) => _linhaValor(entry.key, entry.value, currencyFormat))
                          .toList(),
                    ),
                  ),

                _card(
                  titulo: 'Valores',
                  child: Column(
                    children: [
                      _linhaValor('Subtotal', venda.subtotal, currencyFormat),
                      if (venda.desconto > 0)
                        _linhaValor('Desconto', -venda.desconto, currencyFormat, cor: Colors.red),
                      if (venda.saldoUsado > 0)
                        _linhaValor('Saldo utilizado', -venda.saldoUsado, currencyFormat, cor: Colors.red),
                      if (temEntrega)
                        _linhaValor(
                          venda.entregaSelecionada.isNotEmpty ? 'Entrega (${venda.entregaSelecionada})' : 'Entrega',
                          venda.valorEntrega,
                          currencyFormat,
                          cor: Theme.of(context).colorScheme.primary,
                        ),
                      const Divider(height: 20),
                      _linhaValor('Valor Total', venda.valorTotal, currencyFormat, destaque: true),
                      _linhaValor('Valor Pago', venda.valorPago, currencyFormat),
                      if (venda.troco > 0) _linhaValor('Troco', venda.troco, currencyFormat),
                    ],
                  ),
                ),

                _cardInterno(venda, currencyFormat),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Text(
                    'Itens (${venda.itens.length})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (venda.itens.isEmpty)
                  _card(child: const Text('Nenhum item encontrado.', style: TextStyle(color: Colors.grey)))
                else
                  ...venda.itens.map((item) => _itemCard(item, currencyFormat)),

                if (venda.observacao.isNotEmpty)
                  _card(
                    titulo: 'Observações',
                    child: Text(venda.observacao, style: const TextStyle(fontStyle: FontStyle.italic)),
                  ),

                const SizedBox(height: 12),
              ],
            ),
          ),
          if (_processando)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _bannerCancelada() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red),
      ),
      child: const Row(
        children: [
          Icon(Icons.block, color: Colors.red),
          SizedBox(width: 8),
          Text('VENDA CANCELADA', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _card({String? titulo, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (titulo != null) ...[
            Text(titulo, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
  }

  Widget _cardInterno(Venda venda, NumberFormat currencyFormat) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[100]!),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: const Icon(Icons.lock_outline, color: Colors.orange),
          title: const Text(
            'Informações internas (custo e lucro)',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            _linhaValor('Custo Total', venda.custoTotal, currencyFormat, cor: Colors.orange[800]),
            _linhaValor('Lucro Total', venda.lucroTotal, currencyFormat, cor: Colors.green[800]),
            _linhaValor(
              'Margem',
              null,
              currencyFormat,
              textoCustomizado: venda.valorTotal > 0
                  ? '${(venda.lucroTotal / venda.valorTotal * 100).toStringAsFixed(1)}%'
                  : '-',
              cor: Colors.green[800],
            ),
          ],
        ),
      ),
    );
  }

  Widget _linhaInfo(IconData icon, String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurface),
                children: [
                  TextSpan(text: '$label: ', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  TextSpan(text: valor, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linhaComAcao({
    required IconData icon,
    required String label,
    required String valor,
    required IconData iconAcao,
    required Color corAcao,
    required VoidCallback onTap,
    bool ultima = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(top: 6, bottom: ultima ? 0 : 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurface),
                children: [
                  TextSpan(text: '$label: ', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  TextSpan(text: valor, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(iconAcao, size: 20, color: corAcao),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linhaValor(
    String label,
    double? valor,
    NumberFormat format, {
    Color? cor,
    bool destaque = false,
    String? textoCustomizado,
  }) {
    final texto = textoCustomizado ?? '${valor! < 0 ? '-' : ''}${format.format(valor.abs())}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: destaque ? 16 : 14,
              fontWeight: destaque ? FontWeight.bold : FontWeight.normal,
              color: destaque ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            texto,
            style: TextStyle(
              fontSize: destaque ? 17 : 14,
              fontWeight: destaque ? FontWeight.bold : FontWeight.w600,
              color: cor ?? Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemCard(ItemVenda item, NumberFormat currencyFormat) {
    final lucroPositivo = item.lucroTotal >= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.produto.nome, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                  '${item.quantidade}x ${currencyFormat.format(item.precoUnitario)}  •  custo ${currencyFormat.format(item.custoUnitario)}',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(currencyFormat.format(item.precoTotal), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 2),
              Text(
                '${lucroPositivo ? '+' : ''}${currencyFormat.format(item.lucroTotal)} (${item.margemPercentual.toStringAsFixed(0)}%)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: lucroPositivo ? Colors.green[700] : Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
