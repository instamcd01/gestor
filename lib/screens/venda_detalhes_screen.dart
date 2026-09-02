import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/venda.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/aviso_banner.dart';
import '../providers/historico_vendas_provider.dart';
import '../repositories/venda_repository.dart';
import '../utils/canal_venda_utils.dart';
import '../utils/telefone_utils.dart';
import 'recibo_screen.dart';
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
  late Future<List<EventoStatusPedido>> _historicoFuture;

  @override
  void initState() {
    super.initState();
    _venda = widget.venda;
    _historicoFuture = _venda.idVenda != null
        ? VendaRepository().historicoStatus(_venda.idVenda!)
        : Future.value(const []);
  }

  Future<void> _abrirWhatsApp(String numero) async {
    if (normalizarTelefoneBr(numero).isEmpty) return;
    final uri = Uri.parse(linkWhatsApp(numero));
    if (await canLaunchUrl(uri)) {
      // Sem isso, em alguns aparelhos o link abre numa webview dentro do
      // próprio Gestor em vez de abrir o WhatsApp de verdade.
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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

  /// Mesma distinção do fila_pedidos_screen: iFood usa agendado/entregaPrevista*,
  /// pedido com checkout do app (loja física/WhatsApp/site) usa
  /// agendadoManualmente/previsaoEntrega* — ver comentário no model Venda.
  DateTime? _previsaoInicio(Venda venda) => venda.previsaoEntregaInicio ?? venda.entregaPrevistaInicio;
  DateTime? _previsaoFim(Venda venda) => venda.previsaoEntregaFim ?? venda.entregaPrevistaFim;
  bool _ehAgendado(Venda venda) => venda.agendado || venda.agendadoManualmente;

  bool _temPrevisaoEntrega(Venda venda) => _previsaoFim(venda) != null;

  /// Usado tanto no resumo fixo (topo) quanto no card "Pagamento" da aba —
  /// mesmo texto nos dois lugares, um método só pra não desalinhar depois.
  String _resumoFormaPagamento(Venda venda) {
    if (venda.ehMarketplace) {
      return '${venda.metodoPagamento} — ${venda.pagoPeloMarketplace ? "já pago pelo iFood" : "cobrar na entrega"}';
    }
    if (venda.pagoOnline) {
      // "Pagamento Online" sozinho não dizia se foi crédito/débito/Pix nem
      // quantas parcelas — usa o detalhe real quando disponível (pedidos
      // antigos, de antes dessa informação ser gravada, caem no rótulo
      // genérico mesmo).
      return '${venda.detalheFormaPagamentoOnline ?? venda.metodoPagamento} — já pago, NÃO cobrar na entrega';
    }
    return venda.metodoPagamento;
  }

  String _labelPrevisaoEntrega(Venda venda) {
    if (_ehAgendado(venda)) return venda.retirada ? 'Retirada agendada' : 'Entrega agendada';
    if (venda.modalidade == 'economica') return 'Entrega econômica';
    return 'Previsão de entrega';
  }

  String _formatarPrevisaoEntrega(Venda venda) {
    final formato = DateFormat('dd/MM HH:mm');
    final fim = _previsaoFim(venda)!;
    if (_ehAgendado(venda)) {
      final inicio = _previsaoInicio(venda);
      return inicio != null ? '${formato.format(inicio)} - ${formato.format(fim)}' : '~${formato.format(fim)}';
    }
    // previsaoEntregaFim aqui guarda a mesma hora-do-dia do pedido (só a
    // DATA já pula dias fechados — ver `finalizar_pedido_site`) — mostrar a
    // hora seria enganoso, mesmo ajuste já feito no site e na Fila de
    // Pedidos (ver `Venda.modalidade`).
    if (venda.modalidade == 'economica') return 'Até ${DateFormat('dd/MM').format(fim)}';
    return '~${formato.format(fim)}';
  }

  void _verRecibo() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ReciboScreen(venda: _venda)));
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
      // Pedido explícito do usuário: sem isso, nenhum cancelamento manual
      // (a maioria dos casos) registrava motivo nenhum — a tela de detalhe
      // só mostrava "VENDA CANCELADA" sem dar pra saber depois se foi o
      // cliente que desistiu, produto em falta, etc. Campo opcional (não
      // trava quem só quer cancelar rápido), mas sempre grava um código
      // ('cancelado_pela_loja') pra já dar pra saber QUEM cancelou mesmo
      // sem texto — ver Venda.origemCancelamento.
      final controladorMotivo = TextEditingController();
      final confirmou = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cancelar venda'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Isso vai devolver os itens ao estoque, devolver o saldo do cliente usado (se houve) '
                'e marcar a venda como cancelada. Essa ação não pode ser desfeita.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controladorMotivo,
                maxLength: 200,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Motivo do cancelamento (opcional)',
                  hintText: 'Ex: cliente desistiu, produto em falta...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
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
      motivoCodigo = 'cancelado_pela_loja';
      final texto = controladorMotivo.text.trim();
      motivoDescricao = texto.isEmpty ? null : texto;
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
        _venda = _venda.copyWith(
          status: 'cancelado',
          motivoCancelamentoCodigo: motivoCodigo,
          motivoCancelamentoDescricao: motivoDescricao,
        );
        _historicoFuture = VendaRepository().historicoStatus(_venda.idVenda!);
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

  /// Estorna o pagamento de verdade no Mercado Pago (dinheiro volta pro
  /// cliente) e cancela a venda em seguida — ver
  /// VendaRepository.estornarPagamentoOnline. Ação irreversível de dinheiro
  /// de verdade, por isso a confirmação explícita antes.
  Future<void> _confirmarEstorno() async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Estornar pagamento'),
        content: const Text(
          'Isso devolve o dinheiro pro cliente de verdade, através do Mercado Pago, e cancela a venda '
          '(devolvendo os itens ao estoque). Essa ação não pode ser desfeita. Confirmar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Estornar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmou != true || !mounted || _venda.idVenda == null) return;

    final historicoProvider = Provider.of<HistoricoVendasProvider>(context, listen: false);
    setState(() => _processando = true);
    try {
      await historicoProvider.estornarPagamentoOnline(_venda.idVenda!);
      if (!mounted) return;
      setState(() {
        _venda = _venda.copyWith(status: 'cancelado');
        _historicoFuture = VendaRepository().historicoStatus(_venda.idVenda!);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pagamento estornado e venda cancelada.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível estornar: $e')),
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
      // Sem autofocus + sem fechar tocando fora: com o teclado aberto (via
      // autofocus) e o diálogo fechando por barrier-dismiss no mesmo frame,
      // bate num bug conhecido do framework do Flutter (assert
      // `_dependents.isEmpty` ao desativar o Overlay/IME) — só os botões
      // fecham o diálogo agora.
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar com código'),
        content: TextField(
          controller: controller,
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

  /// Recarrega a venda do banco pra checar se o webhook do Mercado Pago já
  /// confirmou um Pix/cartão que ainda estava pendente — a tela não tem
  /// realtime, então sem isso o lojista só saberia fechando e reabrindo (ou
  /// puxando a Fila de Pedidos pra atualizar) em vez de conferir aqui mesmo.
  Future<void> _verificarPagamentoAgora() async {
    if (_venda.idVenda == null) return;
    setState(() => _processando = true);
    try {
      final atualizada = await VendaRepository().buscarPorId(_venda.idVenda!);
      if (!mounted) return;
      setState(() => _venda = atualizada);
      if (!atualizada.aguardandoPagamento && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pagamento confirmado!')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível verificar agora: $e')),
      );
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
    // Custo/lucro/margem — vendedor não vê, nem o card interno nem por item.
    final podeVerFinancas = context.watch<AuthProvider>().podeVerFinancas;
    final authProvider = context.watch<AuthProvider>();
    final podeEstornar = authProvider.isDono || authProvider.isGerente;
    final cancelada = venda.cancelada;

    // Antes era 1 ListView só com tudo empilhado — difícil de escanear
    // rápido quando o que importa muda conforme o papel de quem olha
    // (vendedor só quer telefone/endereço pra despachar, dono também quer
    // conferir pagamento/financeiro). Pedido explícito do usuário: manter
    // status/total sempre visíveis no topo (não dependem de aba nenhuma) e
    // separar o resto em abas por assunto, mesmo padrão de
    // `cliente_detalhes_screen.dart` (`DefaultTabController`/`TabBar`), só
    // que com a área fixa fora da AppBar, entre ela e as abas.
    final abas = <Tab>[
      const Tab(text: 'Itens'),
      const Tab(text: 'Cliente'),
      const Tab(text: 'Pagamento'),
      const Tab(text: 'Histórico'),
      if (podeVerFinancas) const Tab(text: 'Financeiro'),
    ];
    final conteudoAbas = <Widget>[
      // Custo/lucro por item saiu daqui — vendedor via mesmo sem poder ver
      // finanças, e mistura preço de venda (o que interessa pra montar/
      // conferir o pedido) com margem (informação sensível). Foi pra dentro
      // da aba Financeiro junto do resto do que só quem tem permissão vê.
      _abaItens(venda, currencyFormat),
      _abaCliente(venda, temEntrega),
      // Pedido explícito do usuário: o resumo (canal/data) fica fixo acima
      // das abas, mas o detalhamento completo de valores (subtotal/
      // descontos/cupons/entrega) mora aqui, junto da forma de pagamento.
      _abaPagamento(venda, currencyFormat, podeEstornar, temEntrega),
      _abaHistorico(venda),
      if (podeVerFinancas) _abaFinanceiro(venda, currencyFormat),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Venda - ${venda.cliente.nome}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'Ver recibo',
            onPressed: _verRecibo,
          ),
          // Estorno é dinheiro voltando de verdade pro cliente (diferente de
          // cancelar um pedido pago na entrega, que nunca chegou a cobrar) —
          // só faz sentido pra venda paga online, e só dono/gerente decide
          // isso, mesma restrição já aplicada no endpoint que faz o estorno.
          if (!cancelada && venda.pagoOnline && podeEstornar)
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Estornar pagamento',
              onPressed: _processando ? null : _confirmarEstorno,
            ),
          if (!cancelada)
            IconButton(
              icon: const Icon(Icons.cancel_outlined),
              tooltip: 'Cancelar venda',
              onPressed: _processando ? null : _confirmarCancelamento,
            ),
        ],
      ),
      body: DefaultTabController(
        length: abas.length,
        child: Stack(
          children: [
            Opacity(
              opacity: cancelada ? 0.6 : 1,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Column(
                      children: [
                        if (cancelada) _bannerCancelada(),
                        if (!cancelada && venda.pagoOnline) _bannerPagoOnline(),
                        if (!cancelada && venda.aguardandoPagamento) ...[
                          _bannerAguardandoPagamento(),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: _processando ? null : _verificarPagamentoAgora,
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Verificar pagamento agora'),
                              ),
                            ),
                          ),
                        ],
                        // Resumo fixo: só o essencial pra identificar o
                        // pedido de relance (canal + quando foi criado) e o
                        // valor principal — o detalhamento completo
                        // (subtotal/descontos/cupons/entrega) mora na aba
                        // Pagamento agora, pedido explícito do usuário.
                        Row(
                          children: [
                            Icon(iconeCanalVenda(venda.canalVenda),
                                size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${rotuloCanalVenda(venda.canalVenda)} • '
                                '${DateFormat('dd/MM/yyyy HH:mm').format(venda.dataVenda)}',
                                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Total',
                                style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            Text(
                              currencyFormat.format(venda.valorTotal),
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.payment, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _resumoFormaPagamento(venda),
                                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Divider(height: 1),
                      ],
                    ),
                  ),
                  TabBar(
                    tabs: abas,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelColor: Theme.of(context).colorScheme.primary,
                    unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  Expanded(child: TabBarView(children: conteudoAbas)),
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
      ),
      bottomNavigationBar: (!cancelada && venda.proximoStatus != null)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _processando ? null : _avancarStatus,
                    icon: const Icon(Icons.arrow_forward),
                    label: Text('Marcar: ${StatusPedido.rotulo(venda.proximoStatus!)}'),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  /// Mesma ação/RPC de `fila_pedidos_screen._avancarStatus` — faltava dar
  /// pra avançar o status direto daqui, sem precisar voltar pra Fila de
  /// Pedidos pra fazer a mesma coisa que já se está olhando aqui.
  Future<void> _avancarStatus() async {
    final proximo = _venda.proximoStatus;
    if (proximo == null || _venda.idVenda == null) return;

    setState(() => _processando = true);
    try {
      await Provider.of<HistoricoVendasProvider>(context, listen: false)
          .avancarStatusPedido(_venda.idVenda!, proximo);
      if (!mounted) return;
      setState(() {
        _venda = _venda.copyWith(status: proximo);
        _historicoFuture = VendaRepository().historicoStatus(_venda.idVenda!);
      });
    } catch (e) {
      if (!mounted) return;
      final mensagem = e is PostgrestException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível atualizar o pedido: $mensagem')),
      );
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Widget _abaItens(Venda venda, NumberFormat currencyFormat) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
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
          // Custo/lucro por item foi pra aba Financeiro (junto do resto que
          // só quem tem permissão vê) — aqui é só o que qualquer um precisa
          // pra montar/conferir o pedido.
          ...venda.itens.map((item) => _itemCard(item, currencyFormat)),
        if (venda.observacao.isNotEmpty)
          _card(
            titulo: 'Observações',
            child: Text(venda.observacao, style: const TextStyle(fontStyle: FontStyle.italic)),
          ),
      ],
    );
  }

  Widget _abaCliente(Venda venda, bool temEntrega) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _card(
          titulo: venda.retirada ? 'Retirada' : 'Entrega',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_temPrevisaoEntrega(venda))
                _linhaInfo(Icons.schedule, _labelPrevisaoEntrega(venda), _formatarPrevisaoEntrega(venda)),
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
                          ? AppTheme.tomAdaptavel(Colors.orange, Theme.of(context).brightness)
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
      ],
    );
  }

  Widget _abaPagamento(Venda venda, NumberFormat currencyFormat, bool podeEstornar, bool temEntrega) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Detalhamento completo (subtotal/descontos/cupons/entrega) — o
        // resumo fixo acima das abas mostra só o total, pedido explícito do
        // usuário pra não poluir o que fica sempre visível.
        _card(
          titulo: 'Valores',
          child: Column(
            children: [
              _linhaValor('Subtotal', venda.subtotal, currencyFormat),
              if (venda.desconto > 0)
                _linhaValor(
                  venda.campanhaMarketplace != null ? 'Desconto (${venda.campanhaMarketplace})' : 'Desconto',
                  -venda.desconto,
                  currencyFormat,
                  cor: Colors.red,
                ),
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
        if (venda.taxaServicoCliente != null && venda.taxaServicoCliente! > 0)
          Padding(
            padding: const EdgeInsets.only(top: 0, bottom: 8),
            child: Text(
              'Taxa de serviço da iFood: ${currencyFormat.format(venda.taxaServicoCliente)} '
              '(receita da iFood, não da loja)',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),

        _card(
          titulo: 'Pedido',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (venda.numeroExibicaoMarketplace != null)
                _linhaInfo(Icons.confirmation_number_outlined, 'Número do pedido (iFood)',
                    '#${venda.numeroExibicaoMarketplace}'),
              _linhaInfo(Icons.receipt_long, 'ID da Venda', venda.idVenda ?? '-'),
            ],
          ),
        ),

        _card(
          titulo: 'Pagamento',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _linhaInfo(Icons.payment, 'Forma de Pagamento', _resumoFormaPagamento(venda)),
              // IDs técnicos do Mercado Pago — só quem pode estornar
              // (dono/gerente) precisa disso, e só serve pra buscar o
              // pagamento no painel deles em caso de dúvida/disputa.
              if (podeEstornar && venda.mercadoPagoPaymentId != null)
                _linhaInfo(Icons.tag, 'ID pagamento (Mercado Pago)', venda.mercadoPagoPaymentId!),
              if (podeEstornar && venda.mercadoPagoRefundId != null)
                _linhaInfo(Icons.tag, 'ID estorno (Mercado Pago)', venda.mercadoPagoRefundId!),
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

        if (venda.ehMarketplace && !venda.cancelada && !venda.finalizada) _cardMarketplaceAcompanhamento(venda),
      ],
    );
  }

  /// Data/hora de cada etapa do pedido — não existia nenhum registro disso
  /// antes de hoje (`pedido_status_historico`, populado por trigger a cada
  /// mudança de `pedidos.status`). Pedidos de antes dessa tabela existir só
  /// têm 1 entrada (o status atual, na data de criação) — limitação
  /// conhecida, não dá pra reconstruir transições que já aconteceram.
  Widget _abaHistorico(Venda venda) {
    return FutureBuilder<List<EventoStatusPedido>>(
      future: _historicoFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Não foi possível carregar o histórico: ${snapshot.error}'),
            ),
          );
        }
        final eventos = snapshot.data ?? const [];
        if (eventos.isEmpty) {
          return const Center(child: Text('Sem histórico disponível.', style: TextStyle(color: Colors.grey)));
        }
        final dateFormat = DateFormat('dd/MM/yyyy • HH:mm');
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: eventos.length,
          itemBuilder: (context, index) {
            final evento = eventos[index];
            final ultimo = index == eventos.length - 1;
            final cor = ultimo ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant;
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.only(top: 3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ultimo ? cor : Colors.transparent,
                          border: Border.all(color: cor, width: 2),
                        ),
                      ),
                      if (!ultimo)
                        Expanded(
                          child: Container(width: 2, color: Theme.of(context).colorScheme.outlineVariant),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            StatusPedido.rotulo(evento.status),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: ultimo ? FontWeight.bold : FontWeight.w600,
                              color: ultimo ? Theme.of(context).colorScheme.onSurface : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateFormat.format(evento.dataHora),
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _abaFinanceiro(Venda venda, NumberFormat currencyFormat) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _cardInterno(venda, currencyFormat),
        if (venda.itens.isNotEmpty) _cardLucroPorItem(venda, currencyFormat),
      ],
    );
  }

  /// Custo/lucro/margem por item — vivia dentro do card de cada item na aba
  /// Itens (visível pra qualquer um que tivesse permissão), mudou pra cá a
  /// pedido do usuário: aba Itens agora é só o que serve pra montar/conferir
  /// o pedido, financeiro fica todo junto numa aba só.
  Widget _cardLucroPorItem(Venda venda, NumberFormat currencyFormat) {
    final brightness = Theme.of(context).brightness;
    final corVerde = AppTheme.tomAdaptavel(Colors.green, brightness);
    final corVermelho = AppTheme.tomAdaptavel(Colors.red, brightness);
    return _card(
      titulo: 'Lucro por Item',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in venda.itens) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${item.quantidade}x ${item.produto.nome}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'custo ${currencyFormat.format(item.custoUnitario * item.quantidade)}',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${item.lucroTotal >= 0 ? '+' : ''}${currencyFormat.format(item.lucroTotal)} '
                  '(${item.margemPercentual.toStringAsFixed(0)}%)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: item.lucroTotal >= 0 ? corVerde : corVermelho,
                  ),
                ),
              ),
            ),
            if (item != venda.itens.last) const Divider(height: 12),
          ],
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
              venda.entregadorTipo == 'MERCHANT'
                  ? 'Esse pedido é entregue pela própria loja — não tem rastreio da iFood.'
                  : 'Rastreio ainda não disponível — só aparece quando a entrega usa entregador da própria iFood.',
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
                        ? AppTheme.tomAdaptavel(Colors.green, Theme.of(context).brightness)
                        : venda.codigoConfirmacaoStatus == 'invalido'
                            ? AppTheme.tomAdaptavel(Colors.red, Theme.of(context).brightness)
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
          if (venda.codigoRetiradaExibicao != null && venda.codigoRetiradaExibicao!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.qr_code_2, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  'Código de retirada: ${venda.codigoRetiradaExibicao}',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
          if (venda.linkConfirmacaoEntrega != null && venda.linkConfirmacaoEntrega!.isNotEmpty) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: () async {
                final uri = Uri.parse(venda.linkConfirmacaoEntrega!);
                if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              child: Row(
                children: [
                  Icon(Icons.link, size: 16, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Abrir confirmação de entrega (99Food)',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline),
                  ),
                ],
              ),
            ),
          ],
          if (venda.marketplacePedidoId != null) ...[
            const Divider(height: 20),
            if (venda.politicaSubstituicao != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      venda.politicaSubstituicao == 'STORE_REMOVE_ITEMS' ? Icons.block : Icons.swap_horiz,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        venda.politicaSubstituicao == 'STORE_REMOVE_ITEMS'
                            ? 'Cliente NÃO autoriza substituição — só remover item em falta'
                            : 'Cliente autoriza substituição de item em falta',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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

  Widget _bannerPagoOnline() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AvisoBanner(
        tipo: TipoAviso.sucesso,
        icone: Icons.check_circle_outline,
        negrito: true,
        texto: 'Já pago online (${_venda.detalheFormaPagamentoOnline ?? _venda.metodoPagamento}) — NÃO cobrar na entrega.',
      ),
    );
  }

  Widget _bannerAguardandoPagamento() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AvisoBanner(
        tipo: TipoAviso.alerta,
        icone: Icons.hourglass_empty,
        negrito: true,
        texto: 'Aguardando confirmação do pagamento online (${_venda.metodoPagamento}) — ainda NÃO cobrar do cliente.',
      ),
    );
  }

  Widget _bannerCancelada() {
    // Distingue de um cancelamento comum (nunca chegou a cobrar nada) —
    // aqui o dinheiro já voltou de verdade pro cliente via Mercado Pago,
    // informação relevante pra qualquer um que abrir essa venda depois,
    // não só pra quem tem permissão de estornar.
    final String texto;
    if (_venda.estornadoOnline) {
      texto = 'VENDA CANCELADA — pagamento estornado em '
          '${DateFormat("dd/MM/yyyy 'às' HH:mm").format(_venda.mercadoPagoEstornadoEm!)}, '
          'dinheiro já devolvido ao cliente pelo Mercado Pago.';
    } else {
      // Pedido explícito do usuário: dizer QUEM cancelou (cliente/loja/
      // sistema, deduzido em Venda.origemCancelamento) e o PORQUÊ, quando
      // disponível — vendas canceladas antes dessa gravação existir (ou
      // com o campo de motivo deixado em branco) caem no fallback
      // "motivo não informado", sem inventar um motivo que não existe.
      final origemLabel = switch (_venda.origemCancelamento) {
        'cliente' => 'pelo cliente',
        'sistema' => 'pelo sistema',
        _ => 'pela loja',
      };
      final motivo = _venda.motivoCancelamentoDescricao?.trim();
      final motivoTexto = (motivo != null && motivo.isNotEmpty) ? motivo : 'motivo não informado';
      texto = 'VENDA CANCELADA $origemLabel — $motivoTexto';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AvisoBanner(
        tipo: TipoAviso.erro,
        icone: Icons.block,
        negrito: true,
        texto: texto,
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

  /// Antes vinha com cadeado + fundo laranja + `ExpansionTile` (fazia
  /// sentido quando era 1 card colapsado a mais numa lista só com tudo) —
  /// hoje é o conteúdo inteiro da própria aba "Financeiro", que já não
  /// aparece pra quem não tem permissão (vendedor não vê nem a aba). O
  /// cadeado/"informações internas" ficava redundante com isso, dava a
  /// entender que ainda precisava de outra camada de esconderijo. Card
  /// normal agora, mesmo padrão visual do resto da tela.
  Widget _cardInterno(Venda venda, NumberFormat currencyFormat) {
    final brightness = Theme.of(context).brightness;
    final corLaranja = AppTheme.tomAdaptavel(Colors.orange, brightness);
    final corVerde = AppTheme.tomAdaptavel(Colors.green, brightness);

    return _card(
      titulo: 'Informações Financeiras',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            _linhaValor('Custo Total', venda.custoTotal, currencyFormat, cor: corLaranja),
            _linhaValor('Lucro Total (só produto)', venda.lucroTotal, currencyFormat, cor: corVerde),
            _linhaValor(
              'Margem (só produto)',
              null,
              currencyFormat,
              textoCustomizado: venda.valorTotal > 0
                  ? '${(venda.lucroTotal / venda.valorTotal * 100).toStringAsFixed(1)}%'
                  : '-',
              cor: corVerde,
            ),
            // "Lucro Total" acima só desconta custo de produto — cada linha
            // abaixo é um custo operacional real que a loja também paga
            // nessa venda especificamente (configurados em Configurações >
            // Custos Operacionais, ou capturados direto da API do gateway/
            // marketplace), só aparecendo quando existir de fato pra essa
            // venda — sem isso "Lucro Total" ficava sistematicamente
            // otimista, escondendo embalagem/entrega/taxas de quem decide
            // preço e promoção.
            if (venda.custoEmbalagem != null ||
                venda.custoEntregaReal != null ||
                venda.taxaMaquininha != null ||
                venda.mercadoPagoTaxa != null ||
                (venda.ehMarketplace && (venda.taxaComissaoMarketplace != null || venda.taxaGatewayMarketplace != null))) ...[
              const Divider(height: 20),
              if (venda.custoEmbalagem != null)
                _linhaValor('Embalagem', -venda.custoEmbalagem!, currencyFormat, cor: corLaranja),
              if (venda.custoEntregaReal != null)
                _linhaValor('Entrega própria', -venda.custoEntregaReal!, currencyFormat, cor: corLaranja),
              if (venda.taxaMaquininha != null)
                _linhaValor('Taxa maquininha', -venda.taxaMaquininha!, currencyFormat, cor: corLaranja),
              if (venda.mercadoPagoTaxa != null)
                _linhaValor('Taxa Mercado Pago', -venda.mercadoPagoTaxa!, currencyFormat, cor: corLaranja),
              if (venda.ehMarketplace && venda.taxaComissaoMarketplace != null)
                _linhaValor('Comissão marketplace', -venda.taxaComissaoMarketplace!, currencyFormat, cor: corLaranja),
              if (venda.ehMarketplace && venda.taxaGatewayMarketplace != null)
                _linhaValor('Taxa pagamento (marketplace)', -venda.taxaGatewayMarketplace!, currencyFormat,
                    cor: corLaranja),
              _linhaValor('Lucro líquido real', venda.lucroLiquidoReal, currencyFormat,
                  cor: corVerde, destaque: true),
              _linhaValor(
                'Margem líquida real',
                null,
                currencyFormat,
                textoCustomizado: venda.valorTotal > 0
                    ? '${(venda.lucroLiquidoReal / venda.valorTotal * 100).toStringAsFixed(1)}%'
                    : '-',
                cor: corVerde,
              ),
            ],
        ],
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

  /// Custo/lucro por item mora só na aba Financeiro agora (`_cardLucroPorItem`)
  /// — este card fica só com o que qualquer um precisa pra montar/conferir
  /// o pedido (produto, quantidade, preço, observação do cliente).
  Widget _itemCard(ItemVenda item, NumberFormat currencyFormat) {
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
                  '${item.quantidade}x ${currencyFormat.format(item.precoUnitario)}',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                if (item.observacaoCliente != null && item.observacaoCliente!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '"${item.observacaoCliente}"',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: AppTheme.tomAdaptavel(Colors.orange, Theme.of(context).brightness),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(currencyFormat.format(item.precoTotal), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      ),
    );
  }
}
