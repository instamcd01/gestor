import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/despesa.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import '../providers/auth_provider.dart';
import '../providers/despesa_provider.dart';
import '../providers/historico_vendas_provider.dart';
import '../providers/produto_provider.dart';
import '../theme/app_theme.dart';
import '../utils/app_destinos.dart';
import '../utils/canal_venda_utils.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

bool _mesmoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Números de vendas do Início (celular e PC, uma conta só). Vendedor vê só as
/// próprias vendas, mesma regra do Histórico e de "Meu Desempenho".
class ResumoVendasInicio {
  final List<Venda> hoje;
  final List<Venda> ontem;
  final List<Venda> mes;

  ResumoVendasInicio._(this.hoje, this.ontem, this.mes);

  factory ResumoVendasInicio.de(AuthProvider auth, List<Venda> todas, {DateTime? agora}) {
    final dia = agora ?? DateTime.now();
    final vendas = (auth.isVendedor ? todas.where((v) => v.vendedorId == auth.usuarioAtual?.id) : todas)
        .where((v) => v.finalizada)
        .toList();
    final anterior = dia.subtract(const Duration(days: 1));
    return ResumoVendasInicio._(
      vendas.where((v) => _mesmoDia(v.dataVenda, dia)).toList(),
      vendas.where((v) => _mesmoDia(v.dataVenda, anterior)).toList(),
      vendas.where((v) => v.dataVenda.year == dia.year && v.dataVenda.month == dia.month).toList(),
    );
  }

  static double somar(List<Venda> lista) => lista.fold(0.0, (soma, v) => soma + v.valorTotal);

  double get totalHoje => somar(hoje);
  double get totalOntem => somar(ontem);
  double get totalMes => somar(mes);

  /// Hoje contra ontem. null quando ontem não vendeu: com base 0, o percentual
  /// dispara pra infinito e não diz nada.
  double? get variacaoPct => totalOntem > 0 ? (totalHoje - totalOntem) / totalOntem * 100 : null;
}

/// Despesas já pagas neste mês (celular e PC, uma conta só).
double despesasPagasDoMes(List<Despesa> despesas, {DateTime? agora}) {
  final dia = agora ?? DateTime.now();
  return despesas
      .where((d) =>
          d.paga && d.dataPagamento != null && d.dataPagamento!.year == dia.year && d.dataPagamento!.month == dia.month)
      .fold(0.0, (soma, d) => soma + d.valor);
}

/// "Boa tarde, Lucas" (celular e PC).
String saudacaoDoInicio(String? nomeCompleto, {DateTime? agora}) {
  final hora = (agora ?? DateTime.now()).hour;
  final saudacao = hora < 12 ? 'Bom dia' : (hora < 18 ? 'Boa tarde' : 'Boa noite');
  final nome = nomeCompleto?.trim() ?? '';
  return nome.isEmpty ? saudacao : '$saudacao, ${nome.split(' ').first}';
}

/// Produtos em estoque baixo, os mais perto de acabar primeiro (proporção do
/// mínimo). Zerados contam à parte, em "sem estoque".
List<Produto> produtosEstoqueBaixo(List<Produto> produtos) {
  final baixos = produtos
      .where((p) => p.ativo && p.estoqueMinimo > 0 && p.estoqueAtual > 0 && p.estoqueAtual <= p.estoqueMinimo)
      .toList();
  baixos.sort((a, b) {
    final x = (a.estoqueAtual / a.estoqueMinimo).compareTo(b.estoqueAtual / b.estoqueMinimo);
    return x != 0 ? x : a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
  });
  return baixos;
}

/// Pedidos em andamento na ordem de quem precisa de ação primeiro: a etapa
/// mais atrás vem antes, e dentro dela o mais antigo.
List<Venda> pedidosPorEtapa(List<Venda> ativos) {
  int etapa(Venda v) {
    final i = StatusPedido.emAndamento.indexOf(v.status);
    return i < 0 ? StatusPedido.emAndamento.length : i;
  }

  return [...ativos]..sort((a, b) {
      final x = etapa(a).compareTo(etapa(b));
      return x != 0 ? x : a.dataVenda.compareTo(b.dataVenda);
    });
}

/// Início no PC (janela ≥ 1200 px): usa a largura toda, com os números no topo
/// e "Pedidos agora" e "Estoque baixo" lado a lado, mostrando quais são. Sem
/// consulta nova: usa os mesmos dados já carregados, e os pedidos chegam em
/// tempo real pelo provider. No celular segue o painel de sempre.
class InicioPc extends StatefulWidget {
  final bool mostrarAppBar;
  final double? lucroLiquidoReal;
  final Future<void> Function() recarregar;

  /// A tela voltou a aparecer: o que não chega em tempo real (lucro, despesas)
  /// pode ter mudado com o que foi feito nas outras seções.
  final VoidCallback aoVoltar;
  final VoidCallback abrirVender;
  final VoidCallback abrirPedidos;
  final VoidCallback abrirProdutos;
  final VoidCallback abrirFluxoCaixa;
  final VoidCallback abrirLucro;

  const InicioPc({
    super.key,
    required this.mostrarAppBar,
    required this.lucroLiquidoReal,
    required this.recarregar,
    required this.aoVoltar,
    required this.abrirVender,
    required this.abrirPedidos,
    required this.abrirProdutos,
    required this.abrirFluxoCaixa,
    required this.abrirLucro,
  });

  @override
  State<InicioPc> createState() => _InicioPcState();
}

class _InicioPcState extends State<InicioPc> {
  Timer? _relogio;
  bool _visivel = false;
  bool _primeiraVez = true;

  @override
  void initState() {
    super.initState();
    // O tempo de cada pedido e o "atrasado" dependem só do relógio.
    _relogio = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visivel = TickerMode.valuesOf(context).enabled;
    if (visivel && !_visivel) {
      if (_primeiraVez) {
        _primeiraVez = false; // A tela de fora já carregou tudo ao abrir.
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.aoVoltar();
        });
      }
    }
    _visivel = visivel;
  }

  Color _tom(MaterialColor cor) => AppTheme.tomAdaptavel(cor, Theme.of(context).brightness);

  void _abrirPedido(Venda v) {
    widget.abrirPedidos();
    pedidoParaAbrir.value = v.idVenda;
  }

  void _abrirProduto(Produto p) {
    widget.abrirProdutos();
    produtoParaAbrir.value = p.id;
  }

  @override
  Widget build(BuildContext context) {
    final corpo = LayoutBuilder(builder: (context, limites) {
      final conteudo = _conteudo(context, limites.maxWidth);
      // Janela muito baixa: rola a página em vez de espremer as listas.
      if (limites.maxHeight >= 560) return SizedBox(height: limites.maxHeight, child: conteudo(true));
      return SingleChildScrollView(child: SizedBox(height: 620, child: conteudo(true)));
    });

    final cores = Theme.of(context).colorScheme;
    final tela = Column(
      children: [
        Expanded(child: corpo),
        const Divider(height: 1),
        Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          alignment: Alignment.centerLeft,
          child: Text(
            ['F2 vender', 'F3 pedidos', 'F4 produtos', 'Clique num pedido ou produto pra abrir'].join('     ·     '),
            style: TextStyle(fontSize: 12, color: cores.onSurfaceVariant),
          ),
        ),
      ],
    );
    if (!widget.mostrarAppBar) return tela;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Início'),
        actions: [
          IconButton(tooltip: 'Atualizar', icon: const Icon(Icons.refresh), onPressed: widget.recarregar),
        ],
      ),
      body: tela,
    );
  }

  Widget Function(bool) _conteudo(BuildContext context, double largura) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<HistoricoVendasProvider>();
    final ativos = pedidosPorEtapa(provider.pedidosAtivos);
    final pendentes = ativos.where((v) => v.status == StatusPedido.pendente).length;
    // Resumo de estoque é gestão de catálogo: vendedor não vê, igual ao celular.
    final comEstoque = !auth.isVendedor;
    final compacto = largura < 1100;

    return (_) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _cabecalho(auth),
              if (pendentes > 0) ...[const SizedBox(height: 12), _bannerPendentes(pendentes)],
              const SizedBox(height: 12),
              _numeros(auth, provider.vendas, compacto),
              const SizedBox(height: 12),
              Expanded(
                child: comEstoque
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 3, child: _painelPedidos(ativos, largura * 0.6)),
                          const SizedBox(width: 12),
                          Expanded(flex: 2, child: _painelEstoque()),
                        ],
                      )
                    : _painelPedidos(ativos, largura),
              ),
            ],
          ),
        );
  }

  Widget _cabecalho(AuthProvider auth) {
    final botao = OutlinedButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 14));
    return Row(
      children: [
        Expanded(
          child: Text(
            saudacaoDoInicio(auth.nome),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 16)),
          onPressed: widget.abrirVender,
          child: const Text('Vender · F2'),
        ),
        const SizedBox(width: 8),
        OutlinedButton(style: botao, onPressed: widget.abrirPedidos, child: const Text('Pedidos · F3')),
        const SizedBox(width: 8),
        OutlinedButton(style: botao, onPressed: widget.abrirProdutos, child: const Text('Produtos · F4')),
      ],
    );
  }

  Widget _bannerPendentes(int pendentes) {
    final cor = _tom(Colors.orange);
    return Material(
      color: Colors.orange.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: widget.abrirPedidos,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  pendentes == 1 ? '1 pedido aguardando confirmação' : '$pendentes pedidos aguardando confirmação',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: cor),
                ),
              ),
              Text('Ver agora ›', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: cor)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _numeros(AuthProvider auth, List<Venda> vendas, bool compacto) {
    final resumo = ResumoVendasInicio.de(auth, vendas);
    final variacao = resumo.variacaoPct;
    String qtd(int n) => '$n venda${n == 1 ? '' : 's'}';
    final lucro = widget.lucroLiquidoReal;

    final cartoes = <Widget>[
      _cartaoNumero(
        'Hoje',
        _moeda.format(resumo.totalHoje),
        variacao == null
            ? qtd(resumo.hoje.length)
            : '${qtd(resumo.hoje.length)} · ${variacao >= 0 ? '▲' : '▼'} ${variacao.abs().toStringAsFixed(0)}%${compacto ? '' : ' vs ontem'}',
        corSub: variacao == null ? null : (variacao >= 0 ? _tom(Colors.green) : _tom(Colors.red)),
      ),
      _cartaoNumero('Ontem', _moeda.format(resumo.totalOntem), qtd(resumo.ontem.length)),
      _cartaoNumero('Este mês', _moeda.format(resumo.totalMes), qtd(resumo.mes.length),
          onTap: auth.podeVerFinancas ? widget.abrirFluxoCaixa : null),
      if (auth.podeVerFinancas) ...[
        _cartaoNumero(
          'Despesas do mês',
          _moeda.format(despesasPagasDoMes(context.watch<DespesaProvider>().despesas)),
          'pagas até hoje',
          onTap: widget.abrirFluxoCaixa,
        ),
        _cartaoNumero(
          'Lucro líquido real',
          lucro == null ? '—' : _moeda.format(lucro),
          lucro == null ? 'Carregando...' : 'no mês, já com custos',
          corValor: lucro == null ? null : (lucro >= 0 ? _tom(Colors.green) : _tom(Colors.red)),
          onTap: widget.abrirLucro,
        ),
      ],
    ];

    return Row(
      children: [
        for (final (i, c) in cartoes.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: c),
        ],
      ],
    );
  }

  Widget _cartaoNumero(String rotulo, String valor, String sub, {Color? corValor, Color? corSub, VoidCallback? onTap}) {
    final cores = Theme.of(context).colorScheme;
    return Material(
      color: cores.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: cores.outlineVariant.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rotulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cores.onSurfaceVariant)),
              const SizedBox(height: 2),
              // Valor em reais nunca é cortado: encolhe se não couber.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(valor, maxLines: 1, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: corValor)),
              ),
              const SizedBox(height: 2),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: corSub ?? cores.onSurfaceVariant,
                  fontWeight: corSub == null ? FontWeight.normal : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _caixaPainel({required String titulo, required String acao, required VoidCallback onAcao, required List<Widget> filhos}) {
    final cores = Theme.of(context).colorScheme;
    return Material(
      color: cores.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: cores.outlineVariant.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                Expanded(child: Text(titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                TextButton(onPressed: onAcao, child: Text(acao)),
              ],
            ),
          ),
          ...filhos,
        ],
      ),
    );
  }

  Widget _contador(String numero, String rotulo, Color? cor, VoidCallback onTap) {
    final cores = Theme.of(context).colorScheme;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: cores.outlineVariant.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: numero, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  TextSpan(text: ' $rotulo', style: const TextStyle(fontSize: 12)),
                ]),
                maxLines: 1,
                style: TextStyle(color: cor),
              ),
            ),
          ),
        ),
      ),
    );
  }

  ({Color cor, String texto}) _selo(Venda v) => switch (v.status) {
        StatusPedido.pendente => (cor: _tom(Colors.orange), texto: 'Pendente'),
        StatusPedido.preparando => (cor: _tom(Colors.blue), texto: 'Em preparo'),
        StatusPedido.pronto => (cor: _tom(Colors.teal), texto: 'Pronto'),
        StatusPedido.saiuParaEntrega => (cor: _tom(Colors.purple), texto: 'Saiu p/ entrega'),
        _ => (cor: Theme.of(context).colorScheme.onSurfaceVariant, texto: StatusPedido.rotulo(v.status)),
      };

  String _tempo(Venda v, DateTime agora) {
    if (v.agendado || v.agendadoManualmente) return 'agendado';
    final d = agora.difference(v.dataVenda);
    if (d.inMinutes < 1) return 'agora';
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    if (d.inHours < 24) return '${d.inHours} h';
    return '${d.inDays} d';
  }

  Widget _painelPedidos(List<Venda> ativos, double larguraAprox) {
    final cores = Theme.of(context).colorScheme;
    int conta(String status) => ativos.where((v) => v.status == status).length;
    final comCanal = larguraAprox >= 620;
    final agora = DateTime.now();

    return _caixaPainel(
      titulo: 'Pedidos agora',
      acao: 'Ver todos ›',
      onAcao: widget.abrirPedidos,
      filhos: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              _contador('${conta(StatusPedido.pendente)}', 'pendentes', _tom(Colors.orange), widget.abrirPedidos),
              const SizedBox(width: 8),
              _contador('${conta(StatusPedido.preparando)}', 'em preparo', _tom(Colors.blue), widget.abrirPedidos),
              const SizedBox(width: 8),
              _contador('${conta(StatusPedido.pronto)}', 'pronto', _tom(Colors.teal), widget.abrirPedidos),
              const SizedBox(width: 8),
              _contador('${conta(StatusPedido.saiuParaEntrega)}', 'saiu p/ entrega', _tom(Colors.purple), widget.abrirPedidos),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ativos.isEmpty
              ? Center(child: Text('Nenhum pedido em andamento', style: TextStyle(color: cores.onSurfaceVariant)))
              : ListView.builder(
                  itemExtent: 40,
                  itemCount: ativos.length,
                  itemBuilder: (_, i) => _linhaPedido(ativos[i], agora, comCanal, cores),
                ),
        ),
      ],
    );
  }

  Widget _linhaPedido(Venda v, DateTime agora, bool comCanal, ColorScheme cores) {
    final selo = _selo(v);
    final atrasado = v.atrasadoEm(agora);
    return InkWell(
      onTap: () => _abrirPedido(v),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cores.outlineVariant.withValues(alpha: 0.35)))),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              child: Text('#${v.numeroSequencial ?? '-'}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cores.onSurfaceVariant)),
            ),
            Expanded(
              child: Text(v.cliente.nome,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            if (comCanal)
              SizedBox(
                width: 82,
                child: Text(rotuloCanalVenda(v.canalVenda),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: cores.onSurfaceVariant)),
              ),
            SizedBox(
              width: 108,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: selo.cor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: Text(selo.texto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: selo.cor)),
                ),
              ),
            ),
            SizedBox(
              width: 84,
              child: Text(_moeda.format(v.valorTotal),
                  maxLines: 1, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            SizedBox(
              width: 62,
              child: Text(
                _tempo(v, agora),
                maxLines: 1,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  color: atrasado ? cores.error : cores.onSurfaceVariant,
                  fontWeight: atrasado ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _painelEstoque() {
    final cores = Theme.of(context).colorScheme;
    final produtos = context.watch<ProdutoProvider>().produtos;
    final ativos = produtos.where((p) => p.ativo).toList();
    final baixos = produtosEstoqueBaixo(ativos);
    final zerados = ativos.where((p) => p.estoqueAtual <= 0).length;
    final numero = NumberFormat.decimalPattern('pt_BR');
    final rotuloColuna = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: cores.onSurfaceVariant);

    return _caixaPainel(
      titulo: 'Estoque baixo',
      acao: 'Ver produtos ›',
      onAcao: widget.abrirProdutos,
      filhos: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              _contador(numero.format(ativos.length), 'ativos', null, widget.abrirProdutos),
              const SizedBox(width: 8),
              _contador(numero.format(baixos.length), 'baixo', baixos.isEmpty ? null : _tom(Colors.orange), widget.abrirProdutos),
              const SizedBox(width: 8),
              _contador(numero.format(zerados), 'sem estoque', zerados == 0 ? null : _tom(Colors.red), widget.abrirProdutos),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Row(
            children: [
              Expanded(child: Text('PRODUTO', style: rotuloColuna)),
              SizedBox(width: 44, child: Text('TEM', textAlign: TextAlign.right, style: rotuloColuna)),
              SizedBox(width: 62, child: Text('MÍNIMO', textAlign: TextAlign.right, style: rotuloColuna)),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: baixos.isEmpty
              ? Center(child: Text('Nenhum produto em estoque baixo', style: TextStyle(color: cores.onSurfaceVariant)))
              : ListView.builder(
                  itemExtent: 40,
                  itemCount: baixos.length,
                  itemBuilder: (_, i) {
                    final p = baixos[i];
                    return InkWell(
                      onTap: () => _abrirProduto(p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: cores.outlineVariant.withValues(alpha: 0.35))),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(p.nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                            ),
                            SizedBox(
                              width: 44,
                              child: Text('${p.estoqueAtual}',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _tom(Colors.orange))),
                            ),
                            SizedBox(
                              width: 62,
                              child: Text('${p.estoqueMinimo}',
                                  textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: cores.onSurfaceVariant)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
