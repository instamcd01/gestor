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
import '../repositories/venda_repository.dart';
import 'separacao_pedido_screen.dart';

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

  /// Pedidos iFood vêm com um número de telefone mascarado (proxy 0800) —
  /// WhatsApp não funciona com ele, só ligação de voz. O código localizador
  /// (se a iFood mandou algum) fica só como texto de apoio na tela, já que
  /// não há garantia de que o discador do Android aceite DTMF automático via
  /// URI em todo aparelho/operadora.
  /// `;` no URI `tel:` é o separador de DTMF pós-discagem do Android (pede
  /// confirmação antes de enviar os tons) — com isso o discador já liga pro
  /// 0800 mascarado E envia o código do localizador, sem precisar digitar
  /// nada manualmente.
  Future<void> _ligarViaIfood(Venda venda) async {
    final numeroLimpo = venda.cliente.celular.replaceAll(RegExp(r'[^0-9]'), '');
    if (numeroLimpo.isEmpty) return;
    final localizador = venda.telefoneLocalizadorValido ? venda.telefoneLocalizador : null;
    final destino = localizador != null ? '$numeroLimpo;$localizador' : numeroLimpo;
    final uri = Uri.parse('tel:$destino');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  /// Prefere as coordenadas exatas do endereço de entrega (cadastradas pelo
  /// próprio cliente no app da iFood) quando existirem — muito mais confiável
  /// que buscar o texto do endereço, que pode não geolocalizar direito.
  Future<void> _abrirMapa(String endereco, {double? latitude, double? longitude}) async {
    final Uri uri;
    if (latitude != null && longitude != null) {
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$latitude,$longitude');
    } else {
      if (endereco.isEmpty) return;
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(endereco)}');
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  bool _temPrevisaoEntrega(Venda venda) => venda.entregaPrevistaFim != null;

  String _formatarPrevisaoEntrega(Venda venda) {
    final formato = DateFormat('dd/MM HH:mm');
    if (venda.agendado && venda.entregaPrevistaInicio != null) {
      return '${formato.format(venda.entregaPrevistaInicio!)} - ${formato.format(venda.entregaPrevistaFim!)}';
    }
    return '~${formato.format(venda.entregaPrevistaFim!)}';
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

  /// Motivos de cancelamento aceitos pela API de pedidos da iFood (códigos
  /// observados via `GET /order/v1.0/orders/{id}/cancellationReasons` para
  /// esse merchant — a lista é fixa aqui porque o app não pode chamar a API
  /// da iFood diretamente, só o n8n tem as credenciais).
  static const _motivosCancelamentoIfood = [
    (codigo: '801', descricao: 'Problemas de sistema na loja'),
    (codigo: '503', descricao: 'Item indisponível/desatualizado'),
    (codigo: '815', descricao: 'A loja está passando por dificuldades internas'),
    (codigo: '805', descricao: 'A loja está sem entregadores disponíveis'),
    (codigo: '807', descricao: 'O pedido está fora da área de entrega'),
    (codigo: '804', descricao: 'O endereço está incompleto e o cliente não atende'),
    (codigo: '818', descricao: 'O valor da taxa de entrega está errado'),
    (codigo: '820', descricao: 'A entrega é em uma área de risco'),
    (codigo: '808', descricao: 'Suspeita de golpe ou trote'),
  ];

  /// Pra pedidos de marketplace (iFood), pede o motivo do cancelamento —
  /// esse motivo é repassado pro n8n avisar a iFood, ao invés de sempre usar
  /// o mesmo motivo genérico (que pode prejudicar a loja nas métricas dela).
  Future<({String codigo, String descricao})?> _escolherMotivoCancelamentoIfood() {
    var selecionado = _motivosCancelamentoIfood.first;
    return showDialog<({String codigo, String descricao})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Motivo do cancelamento'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Esse pedido veio do iFood — escolha o motivo que será informado a ele.',
                ),
                const SizedBox(height: 8),
                ...(_motivosCancelamentoIfood.map((motivo) => RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(motivo.descricao),
                      value: motivo.codigo,
                      groupValue: selecionado.codigo,
                      onChanged: (_) => setDialogState(() => selecionado = motivo),
                    ))),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Voltar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, selecionado),
              child: const Text('Cancelar venda', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmarCancelamento() async {
    final ehIfood = _venda.canalVenda == 'ifood';
    String? motivoCodigo;
    String? motivoDescricao;

    if (ehIfood) {
      final motivo = await _escolherMotivoCancelamentoIfood();
      if (motivo == null || !mounted) return;
      motivoCodigo = motivo.codigo;
      motivoDescricao = motivo.descricao;
    } else {
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
              child: const Text('Cancelar venda', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirmou != true || !mounted) return;
    }

    if (_venda.idVenda == null || !mounted) return;

    final historicoProvider = Provider.of<HistoricoVendasProvider>(context, listen: false);
    setState(() => _processando = true);
    try {
      await historicoProvider.cancelarVenda(
        _venda.idVenda!,
        motivoCodigo: motivoCodigo,
        motivoDescricao: motivoDescricao,
      );
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

  /// Confirmação por código de retirada/entrega (iFood). O código digitado
  /// aqui dispara a validação de verdade contra a API via trigger no banco;
  /// como a resposta chega assíncrona (n8n), a tela espera um pouco e
  /// recarrega a venda pra mostrar o resultado — não é instantâneo.
  Future<void> _confirmarComCodigo() async {
    final controller = TextEditingController();
    final codigo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar com código'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(hintText: 'Código informado pelo cliente/entregador'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Confirmar')),
        ],
      ),
    );
    if (codigo == null || codigo.isEmpty || _venda.idVenda == null || !mounted) return;

    setState(() => _processando = true);
    try {
      await VendaRepository().confirmarComCodigo(_venda.idVenda!, codigo);
      await Future.delayed(const Duration(seconds: 3));
      final vendaAtualizada = await VendaRepository().buscarPorId(_venda.idVenda!);
      if (!mounted) return;
      setState(() => _venda = vendaAtualizada);
      final valido = vendaAtualizada.codigoConfirmacaoStatus == 'valido';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(valido
            ? 'Código confirmado.'
            : (vendaAtualizada.codigoConfirmacaoErro ?? 'Código inválido, tente novamente.')),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível validar o código.')));
      }
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _abrirRastreioNoMapa() async {
    final lat = _venda.rastreioLatitude;
    final lng = _venda.rastreioLongitude;
    if (lat == null || lng == null) return;
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
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
                      if (venda.numeroExibicaoMarketplace != null)
                        _linhaInfo(Icons.confirmation_number_outlined, 'Número do pedido (iFood)',
                            '#${venda.numeroExibicaoMarketplace}'),
                      _linhaInfo(Icons.calendar_today,
                          'Data', DateFormat('dd/MM/yyyy • HH:mm').format(venda.dataVenda)),
                      _linhaInfo(
                        Icons.payment,
                        'Forma de Pagamento',
                        venda.ehMarketplace
                            ? '${venda.metodoPagamento} — ${venda.pagoPeloMarketplace ? "já pago pelo iFood" : "cobrar na entrega"}'
                            : venda.metodoPagamento,
                      ),
                      if (venda.ehMarketplace && _temPrevisaoEntrega(venda))
                        _linhaInfo(Icons.schedule, venda.agendado ? 'Entrega agendada' : 'Previsão de entrega',
                            _formatarPrevisaoEntrega(venda)),
                      if (venda.cliente.celular.isNotEmpty)
                        _linhaComAcao(
                          icon: Icons.phone,
                          label: 'Telefone',
                          valor: venda.cliente.celular,
                          iconAcao: venda.ehMarketplace ? Icons.call : Icons.chat,
                          corAcao: venda.ehMarketplace ? Theme.of(context).colorScheme.primary : Colors.green,
                          onTap: venda.ehMarketplace
                              ? () => _ligarViaIfood(venda)
                              : () => _abrirWhatsApp(venda.cliente.celular),
                        ),
                      if (venda.ehMarketplace && venda.cliente.celular.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 28, bottom: 4),
                          child: Text(
                            venda.telefoneLocalizador != null
                                ? (venda.telefoneLocalizadorValido
                                    ? 'Número mascarado pela iFood — o discador já vai enviar o código automaticamente após ligar.'
                                    : 'Número mascarado pela iFood — o código de acesso já expirou, a ligação pode não completar.')
                                : 'Número mascarado pela iFood — não funciona pra WhatsApp, só ligação.',
                            style: TextStyle(
                              fontSize: 11,
                              color: (venda.telefoneLocalizador != null && !venda.telefoneLocalizadorValido)
                                  ? Colors.orange[800]
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (temEntrega && venda.cliente.enderecoCompleto.isNotEmpty)
                        _linhaComAcao(
                          icon: Icons.location_on,
                          label: 'Endereço',
                          valor: venda.cliente.enderecoCompleto,
                          iconAcao: Icons.map,
                          corAcao: Theme.of(context).colorScheme.primary,
                          onTap: () => _abrirMapa(
                            venda.cliente.enderecoCompleto,
                            latitude: venda.cliente.latitude,
                            longitude: venda.cliente.longitude,
                          ),
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

                if (venda.ehMarketplace && !venda.cancelada && !venda.finalizada) _cardMarketplaceAcompanhamento(venda),

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

  Widget _cardMarketplaceAcompanhamento(Venda venda) {
    final dateFormat = DateFormat('dd/MM HH:mm');
    return _card(
      titulo: 'Acompanhamento iFood',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (venda.temRastreio) ...[
            InkWell(
              onTap: _abrirRastreioNoMapa,
              child: Row(
                children: [
                  Icon(Icons.location_on, size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      venda.rastreioEtaEntrega != null
                          ? 'Rastreio: chegada prevista ${dateFormat.format(venda.rastreioEtaEntrega!)}'
                          : 'Ver posição do entregador no mapa',
                      style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(Icons.open_in_new, size: 16, color: Theme.of(context).colorScheme.primary),
                ],
              ),
            ),
            if (venda.rastreioAtualizadoEm != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 26),
                child: Text(
                  'Atualizado às ${dateFormat.format(venda.rastreioAtualizadoEm!)}',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: 10),
          ] else
            Text(
              'Rastreio ainda não disponível — só aparece quando a entrega usa entregador da própria iFood.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  venda.codigoConfirmacaoStatus == 'valido'
                      ? 'Código confirmado ✓'
                      : venda.codigoConfirmacaoStatus == 'invalido'
                          ? (venda.codigoConfirmacaoErro ?? 'Código inválido')
                          : 'Confirme direto aqui — sem precisar abrir o link da iFood.',
                  style: TextStyle(
                    fontSize: 13,
                    color: venda.codigoConfirmacaoStatus == 'valido'
                        ? Colors.green[700]
                        : venda.codigoConfirmacaoStatus == 'invalido'
                            ? Colors.red
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (venda.codigoConfirmacaoStatus != 'valido')
                TextButton(
                  onPressed: _processando ? null : _confirmarComCodigo,
                  child: const Text('Confirmar código'),
                ),
            ],
          ),
          if (venda.marketplacePedidoId != null) ...[
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    venda.separacaoStatus == 'finalizada'
                        ? 'Separação do pedido finalizada'
                        : venda.separacaoStatus == 'separando'
                            ? 'Separação em andamento'
                            : 'Item faltando na separação (pedido de Mercado)?',
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => SeparacaoPedidoScreen(venda: venda)),
                  ),
                  child: Text(venda.separacaoStatus == null ? 'Separar pedido' : 'Ver separação'),
                ),
              ],
            ),
          ],
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
