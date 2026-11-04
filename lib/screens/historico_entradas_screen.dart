import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/despesa.dart';
import '../models/entrada.dart';
import '../models/pedido_compra.dart';
import '../providers/despesa_provider.dart';
import '../providers/entrada_provider.dart';
import '../providers/produto_provider.dart';
import '../repositories/nfe_pendente_entrada_repository.dart';
import '../repositories/pedido_compra_repository.dart';
import '../repositories/revisao_preco_repository.dart';
import '../services/nfe_xml_parser.dart';
import '../widgets/estado_erro_lista.dart';
import 'analise_produtos_screen.dart';
import 'despesas_screen.dart';
import 'importar_nota_fiscal_screen.dart';
import 'notas_pendentes_entrada_screen.dart';
import 'pedido_compra_detalhe_screen.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _dataCurta = DateFormat('dd/MM');

// Sem `DateFormat('MMMM', 'pt_BR')` de propósito: o app não chama
// `initializeDateFormatting('pt_BR')` (ver planejamento_screen.dart).
const _meses = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

String _digitos(String texto) => texto.replaceAll(RegExp(r'[^0-9]'), '');

/// Nota que o poll da Sefaz já baixou e ainda não virou entrada. `nfe`
/// null = XML num formato que o parser não leu (mostra só a chave).
class _NotaChegou {
  final NfePendenteEntrada pendente;
  final NfeImportada? nfe;
  final PedidoCompra? pedidoAberto;

  _NotaChegou(this.pendente, this.nfe, this.pedidoAberto);
}

/// Central de recebimento de mercadoria: o que chegou da Sefaz e falta dar
/// entrada, o que foi pedido e ainda não chegou, quanto isso custou no
/// mês — e, por último, o histórico do que já foi lançado. Antes era só a
/// lista do histórico, e as notas que a Sefaz traz sozinha (o caminho de
/// quase toda nota) ficavam escondidas dentro de "Importar".
/// `ImportarNotaFiscalScreen` continua à parte porque também é aberta a
/// partir de "Receber Pedido de Compra" (`pedido_compra_detalhe_screen.dart`).
class HistoricoEntradasScreen extends StatefulWidget {
  const HistoricoEntradasScreen({super.key});

  @override
  State<HistoricoEntradasScreen> createState() => _HistoricoEntradasScreenState();
}

class _HistoricoEntradasScreenState extends State<HistoricoEntradasScreen> {
  bool _carregandoPainel = true;
  List<_NotaChegou> _chegaram = [];
  List<PedidoCompra> _aCaminho = [];
  Set<String> _produtosMaisCaros = {};
  String? _erroPainel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _carregar();
    });
  }

  Future<void> _carregar() async {
    setState(() {
      _carregandoPainel = true;
      _erroPainel = null;
    });
    final entradaProvider = context.read<EntradaProvider>();
    final despesaProvider = context.read<DespesaProvider>();
    final produtoProvider = context.read<ProdutoProvider>();
    try {
      final resultados = await Future.wait([
        NfePendenteEntradaRepository().listar(),
        PedidoCompraRepository().listar(),
        RevisaoPrecoRepository().carregar(),
        entradaProvider.carregar(),
        despesaProvider.carregar(),
        if (produtoProvider.produtos.isEmpty) produtoProvider.carregarProdutos(),
      ]);
      final pendentes = resultados[0] as List<NfePendenteEntrada>;
      final pedidos = (resultados[1] as List<PedidoCompra>)
          .where((p) => p.status == StatusPedidoCompra.enviado || p.status == StatusPedidoCompra.confirmado)
          .toList();
      final contextoPrecos = resultados[2] as Map<String, RevisaoPrecoContexto>;

      final chegaram = <_NotaChegou>[];
      for (final pendente in pendentes) {
        NfeImportada? nfe;
        try {
          nfe = NfeXmlParser.parse(pendente.xml);
        } catch (_) {
          // XML já validado pela Sefaz; formato inesperado ainda aparece,
          // só com a chave (ver NotasPendentesEntradaScreen).
        }
        final cnpj = nfe == null ? '' : _digitos(nfe.fornecedorDetectado.cnpjCpf);
        PedidoCompra? pedido;
        if (cnpj.isNotEmpty) {
          for (final p in pedidos) {
            if (_digitos(p.fornecedor.cnpjCpf) == cnpj) {
              pedido = p;
              break;
            }
          }
        }
        chegaram.add(_NotaChegou(pendente, nfe, pedido));
      }
      chegaram.sort((a, b) => b.pendente.recebidoEm.compareTo(a.pendente.recebidoEm));

      // Pedido cuja nota já chegou aparece em "Chegou da Sefaz", não aqui.
      final pedidosComNota = {for (final c in chegaram) c.pedidoAberto?.id};
      final aCaminho = pedidos.where((p) => !pedidosComNota.contains(p.id)).toList()
        ..sort((a, b) => (a.dataEnvio ?? a.createdAt ?? DateTime.now())
            .compareTo(b.dataEnvio ?? b.createdAt ?? DateTime.now()));

      // Mesmo critério do filtro "Custo subiu" do Revisar preço.
      final maisCaros = <String>{};
      for (final p in produtoProvider.produtos) {
        final anterior = contextoPrecos[p.id]?.custoAnterior;
        if (p.id != null && p.revisarPreco && anterior != null && p.custo > anterior) maisCaros.add(p.id!);
      }

      if (!mounted) return;
      setState(() {
        _chegaram = chegaram;
        _aCaminho = aCaminho;
        _produtosMaisCaros = maisCaros;
        _carregandoPainel = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erroPainel = 'Erro ao carregar: $e';
        _carregandoPainel = false;
      });
    }
  }

  Future<void> _darEntrada(_NotaChegou nota) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ImportarNotaFiscalScreen(xmlInicial: nota.pendente.xml)),
    );
    if (mounted) _carregar();
  }

  Future<void> _naoEMercadoria(_NotaChegou nota) async {
    if (await dispensarNotaNaoMercadoria(context, nota.pendente, nota.nfe!) && mounted) _carregar();
  }

  Future<void> _importarManual() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportarNotaFiscalScreen()));
    if (mounted) _carregar();
  }

  @override
  void dispose() {
    _conferenciaAlterada.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entradaProvider = context.watch<EntradaProvider>();
    final despesas = context.watch<DespesaProvider>().despesas;
    final carregandoPrimeiraVez = _carregandoPainel && _chegaram.isEmpty && entradaProvider.entradas.isEmpty;

    // PC: lista de notas + conferência ao lado (ver `_layoutPc`).
    if (MediaQuery.sizeOf(context).width >= 1200) {
      return _layoutPc(context, entradaProvider, despesas, carregandoPrimeiraVez);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notas Fiscais'),
        bottom: _carregandoPainel && !carregandoPrimeiraVez
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importarManual,
        icon: const Icon(Icons.upload_file_outlined),
        label: const Text('Importar XML'),
      ),
      body: carregandoPrimeiraVez
          ? const Center(child: CircularProgressIndicator())
          : _erroPainel != null && entradaProvider.entradas.isEmpty && _chegaram.isEmpty
              ? EstadoErroLista(mensagem: _erroPainel!, onTentarNovamente: _carregar)
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    children: [
                      _resumoDoMes(context, entradaProvider.entradas, despesas),
                      const SizedBox(height: 20),
                      ..._secaoChegou(context),
                      const SizedBox(height: 20),
                      ..._secaoACaminho(context),
                      ..._secaoLancadas(context, entradaProvider.entradas),
                    ],
                  ),
                ),
    );
  }


  // ───────────────────────── PC (janela ≥ 1200 px) ─────────────────────────
  //
  // Lista de notas à esquerda e a conferência da nota escolhida ao lado — a
  // conferência é a própria ImportarNotaFiscalScreen (embutida), então
  // custo, estoque, boletos e bonificação seguem a regra de sempre.

  String? _chaveSelecionada;
  final _conferenciaAlterada = ValueNotifier<bool>(false);
  final Set<String> _mesesAbertos = {};

  /// Muda a cada cancelar/concluir: a conferência é recriada do zero (sem
  /// isso, cancelar voltava pra mesma nota com o que tinha sido digitado).
  int _versaoConferencia = 0;

  _NotaChegou? get _notaSelecionada =>
      _chegaram.where((n) => n.pendente.chave == _chaveSelecionada).firstOrNull;

  Future<bool> _podeTrocarDeNota() async {
    if (!_conferenciaAlterada.value) return true;
    final sair = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Conferência não confirmada'),
        content: const Text('Você mexeu nesta nota e ainda não confirmou a entrada. Trocar de nota descarta o que foi feito.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Continuar nesta')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Trocar de nota')),
        ],
      ),
    );
    if (sair == true) _conferenciaAlterada.value = false;
    return sair == true;
  }

  Future<void> _selecionarNota(_NotaChegou? nota) async {
    if (nota?.pendente.chave == _chaveSelecionada) return;
    if (!await _podeTrocarDeNota() || !mounted) return;
    setState(() => _chaveSelecionada = nota?.pendente.chave);
  }

  void _trocarNotaPorTeclado(int passo) {
    if (_chegaram.isEmpty) return;
    final atual = _chegaram.indexWhere((n) => n.pendente.chave == _chaveSelecionada);
    final novo = atual < 0 ? 0 : (atual + passo).clamp(0, _chegaram.length - 1);
    _selecionarNota(_chegaram[novo]);
  }

  Widget _layoutPc(BuildContext context, EntradaProvider entradaProvider, List<Despesa> despesas, bool carregandoPrimeiraVez) {
    final cores = Theme.of(context).colorScheme;
    // Escolhe a primeira nota sozinho (e a próxima depois de dar entrada).
    if (_chaveSelecionada == null && _chegaram.isNotEmpty && !_carregandoPainel) {
      _chaveSelecionada = _chegaram.first.pendente.chave;
    }
    final selecionada = _notaSelecionada;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () => _trocarNotaPorTeclado(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () => _trocarNotaPorTeclado(-1),
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notas Fiscais'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              // Na barra colorida: texto e borda na cor do título (o padrão
              // saía na cor da barra e sumia).
              child: Builder(builder: (context) {
                final cor = AppBarTheme.of(context).foregroundColor ?? Theme.of(context).colorScheme.onPrimary;
                return OutlinedButton.icon(
                  onPressed: _importarManual,
                  style: OutlinedButton.styleFrom(foregroundColor: cor, side: BorderSide(color: cor.withValues(alpha: 0.7))),
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: const Text('Importar XML ou chave'),
                );
              }),
            ),
            IconButton(tooltip: 'Atualizar', icon: const Icon(Icons.refresh), onPressed: _carregar),
          ],
          bottom: _carregandoPainel && !carregandoPrimeiraVez
              ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
              : null,
        ),
        body: carregandoPrimeiraVez
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _resumoPc(context, entradaProvider.entradas, despesas),
                  const Divider(height: 1),
                  Expanded(
                    child: LayoutBuilder(builder: (context, limites) {
                      final larguraLista = (limites.maxWidth * 0.24).clamp(250.0, 360.0).toDouble();
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: larguraLista, child: _listaPc(context, entradaProvider.entradas)),
                          const VerticalDivider(width: 1),
                          Expanded(
                            child: selecionada == null
                                ? _conferenciaVazia(cores)
                                : selecionada.nfe == null
                                    ? _notaIlegivel(cores, selecionada)
                                    : ImportarNotaFiscalScreen(
                                        key: ValueKey('${selecionada.pendente.chave}-$_versaoConferencia'),
                                        xmlInicial: selecionada.pendente.xml,
                                        embutida: true,
                                        alterada: _conferenciaAlterada,
                                        onConcluida: () {
                                          setState(() {
                                            _chaveSelecionada = null;
                                            _versaoConferencia++;
                                          });
                                          _carregar();
                                        },
                                        onCancelar: () => setState(() => _versaoConferencia++),
                                      ),
                          ),
                        ],
                      );
                    }),
                  ),
                  const Divider(height: 1),
                  Container(
                    constraints: const BoxConstraints(minHeight: 30),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      [
                        'Tab próximo campo',
                        'Enter desce na mesma coluna',
                        'Ctrl Enter confirmar entrada',
                        'Alt ↑ ↓ trocar de nota',
                      ].join('     ·     '),
                      style: TextStyle(fontSize: 12, color: cores.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _conferenciaVazia(ColorScheme cores) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_chegaram.isEmpty ? Icons.check_circle_outline : Icons.touch_app_outlined,
                  size: 44, color: _chegaram.isEmpty ? cores.primary : cores.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                _chegaram.isEmpty ? 'Tudo em dia — nenhuma nota esperando entrada.' : 'Escolha uma nota à esquerda pra conferir.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text('Nota nova emitida pro CNPJ da loja aparece na lista sozinha.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cores.onSurfaceVariant)),
            ],
          ),
        ),
      );

  Widget _notaIlegivel(ColorScheme cores, _NotaChegou nota) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: cores.error),
              const SizedBox(height: 12),
              const Text('Não foi possível ler os detalhes desta nota.'),
              const SizedBox(height: 4),
              SelectableText('Chave ${nota.pendente.chave}', style: TextStyle(fontSize: 12, color: cores.onSurfaceVariant)),
            ],
          ),
        ),
      );

  Widget _resumoPc(BuildContext context, List<Entrada> entradas, List<Despesa> despesas) {
    final cores = Theme.of(context).colorScheme;
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final limite = hoje.add(const Duration(days: 7));
    // Mesmas contas do resumo do celular (`_resumoDoMes`).
    final doMes = entradas.where((e) {
      final data = e.dataEntrada.toLocal();
      return data.year == agora.year && data.month == agora.month;
    }).toList();
    final comprado = doMes.fold<double>(0, (s, e) => s + (e.valorTotalNota ?? e.valorTotalProdutos ?? 0));
    final deFornecedor = despesas.where((d) => d.fornecedor != null && d.status == StatusDespesa.pendente);
    final aVencer = deFornecedor
        .where((d) => !d.dataVencimento.isBefore(hoje) && !d.dataVencimento.isAfter(limite))
        .fold<double>(0, (s, d) => s + d.valor);
    final atrasado = deFornecedor.where((d) => d.atrasada).fold<double>(0, (s, d) => s + d.valor);

    Widget bloco({
      required String rotulo,
      required String valor,
      String? complemento,
      Color? corComplemento,
      VoidCallback? onTap,
    }) {
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
              decoration: BoxDecoration(
                border: Border.all(color: cores.outlineVariant),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rotulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cores.onSurfaceVariant)),
                  Text(valor, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  if (complemento != null)
                    Text('$complemento${onTap != null ? ' ›' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: corComplemento ?? cores.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          bloco(
            rotulo: 'Comprado em ${_meses[agora.month - 1]}',
            valor: _moeda.format(comprado),
            complemento: '${doMes.length} ${doMes.length == 1 ? 'nota lançada' : 'notas lançadas'}',
          ),
          const SizedBox(width: 12),
          bloco(
            rotulo: 'Boletos de fornecedor · próximos 7 dias',
            valor: _moeda.format(aVencer),
            complemento: atrasado > 0 ? '${_moeda.format(atrasado)} em atraso' : 'Ver boletos',
            corComplemento: atrasado > 0 ? cores.error : null,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DespesasScreen(
                  filtroInicial: atrasado > 0 ? 'Atrasadas' : 'Pendentes',
                  periodoVencimento: atrasado > 0 ? null : DateTimeRange(start: hoje, end: limite),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          bloco(
            rotulo: 'Custo subiu, preço ainda não revisado',
            valor: _produtosMaisCaros.isEmpty
                ? 'Nenhum produto'
                : '${_produtosMaisCaros.length} ${_produtosMaisCaros.length == 1 ? 'produto' : 'produtos'}',
            complemento: _produtosMaisCaros.isEmpty ? null : 'A margem desses produtos caiu',
            onTap: _produtosMaisCaros.isEmpty
                ? null
                : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => AnaliseProdutosScreen(produtosRevisarPreco: _produtosMaisCaros)),
                    );
                    if (mounted) _carregar();
                  },
          ),
        ],
      ),
    );
  }

  Widget _tituloPc(ColorScheme cores, String titulo, {String? detalhe}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Text.rich(
          TextSpan(
            text: titulo.toUpperCase(),
            style: const TextStyle(fontSize: 11, letterSpacing: 0.5, fontWeight: FontWeight.w700),
            children: [
              if (detalhe != null)
                TextSpan(
                  text: ' · $detalhe',
                  style: TextStyle(fontWeight: FontWeight.w400, letterSpacing: 0, color: cores.onSurfaceVariant),
                ),
            ],
          ),
        ),
      );

  Widget _listaPc(BuildContext context, List<Entrada> entradas) {
    final cores = Theme.of(context).colorScheme;
    final agora = DateTime.now();

    final porMes = <String, List<Entrada>>{};
    for (final e in entradas) {
      final data = e.dataEntrada.toLocal();
      porMes.putIfAbsent('${data.year}-${data.month.toString().padLeft(2, '0')}', () => []).add(e);
    }
    final chaves = porMes.keys.toList()..sort((a, b) => b.compareTo(a));
    final mesAtual = '${agora.year}-${agora.month.toString().padLeft(2, '0')}';

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        _tituloPc(cores, 'Chegou da Sefaz', detalhe: _chegaram.isEmpty ? 'tudo em dia' : 'falta dar entrada (${_chegaram.length})'),
        if (_erroPainel != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_erroPainel!, style: TextStyle(fontSize: 12, color: cores.error)),
          ),
        for (final nota in _chegaram) _linhaNotaPc(context, nota),
        if (_aCaminho.isNotEmpty) ...[
          _tituloPc(cores, 'A caminho', detalhe: 'pedido enviado, nota ainda não chegou (${_aCaminho.length})'),
          for (final pedido in _aCaminho)
            Builder(builder: (context) {
              final enviadoEm = pedido.dataEnvio ?? pedido.dataConfirmacao ?? pedido.createdAt;
              final dias = enviadoEm == null ? null : agora.difference(enviadoEm.toLocal()).inDays;
              final previsao = pedido.dataPrevistaEntrega?.toLocal();
              final atrasado = previsao != null && previsao.isBefore(DateTime(agora.year, agora.month, agora.day));
              return ListTile(
                dense: true,
                title: Text(pedido.fornecedor.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [
                    'Pedido #${pedido.numeroSequencial ?? ''}',
                    if (dias != null) dias == 0 ? 'enviado hoje' : 'enviado há $dias ${dias == 1 ? 'dia' : 'dias'}',
                    if (atrasado) 'atrasado (previsto ${_dataCurta.format(previsao)})',
                  ].join(' · '),
                  style: atrasado ? TextStyle(color: cores.error) : null,
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PedidoCompraDetalheScreen(pedidoId: pedido.id!)),
                  );
                  if (mounted) _carregar();
                },
              );
            }),
        ],
        _tituloPc(cores, 'Já lançadas'),
        if (entradas.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Nenhuma nota lançada ainda.', style: TextStyle(color: cores.onSurfaceVariant)),
          ),
        for (final chave in chaves) ...[
          Builder(builder: (context) {
            final ano = int.parse(chave.substring(0, 4));
            final mes = int.parse(chave.substring(5));
            final total = porMes[chave]!.fold<double>(0, (s, e) => s + (e.valorTotalNota ?? e.valorTotalProdutos ?? 0));
            final rotulo = ano == agora.year ? _meses[mes - 1] : '${_meses[mes - 1]} de $ano';
            final aberto = chave == mesAtual ? !_mesesAbertos.contains('-$chave') : _mesesAbertos.contains(chave);
            return InkWell(
              onTap: () => setState(() {
                // Mês atual começa aberto (marca '-chave' pra fechar); os outros, fechados.
                if (chave == mesAtual) {
                  _mesesAbertos.contains('-$chave') ? _mesesAbertos.remove('-$chave') : _mesesAbertos.add('-$chave');
                } else {
                  _mesesAbertos.contains(chave) ? _mesesAbertos.remove(chave) : _mesesAbertos.add(chave);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: Row(
                  children: [
                    Icon(aberto ? Icons.expand_more : Icons.chevron_right, size: 18, color: cores.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text('${rotulo[0].toUpperCase()}${rotulo.substring(1)} (${porMes[chave]!.length})',
                          style: TextStyle(fontWeight: FontWeight.w600, color: cores.onSurfaceVariant)),
                    ),
                    Text(_moeda.format(total), style: TextStyle(color: cores.onSurfaceVariant)),
                  ],
                ),
              ),
            );
          }),
          if (chave == mesAtual ? !_mesesAbertos.contains('-$chave') : _mesesAbertos.contains(chave))
            for (final entrada in porMes[chave]!)
              ListTile(
                dense: true,
                title: Text(entrada.fornecedor?.nome ?? 'Fornecedor não informado', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [
                    if (entrada.nfeNumero != null) 'NF ${entrada.nfeNumero}',
                    _dataCurta.format(entrada.dataEntrada.toLocal()),
                    if (entrada.pedidoCompraNumero != null) 'Pedido #${entrada.pedidoCompraNumero}',
                  ].join(' · '),
                ),
                trailing: Text(
                  _moeda.format(entrada.valorTotalNota ?? entrada.valorTotalProdutos ?? 0),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
        ],
      ],
    );
  }

  Widget _linhaNotaPc(BuildContext context, _NotaChegou nota) {
    final cores = Theme.of(context).colorScheme;
    final nfe = nota.nfe;
    final pedido = nota.pedidoAberto;
    final selecionada = nota.pendente.chave == _chaveSelecionada;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 3, 10, 3),
      child: Material(
        color: selecionada ? cores.primary.withValues(alpha: 0.10) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: selecionada ? cores.primary : cores.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _selecionarNota(nota),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(nfe?.fornecedorDetectado.nome ?? 'Nota ${nota.pendente.chave}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                          ),
                          if (nfe != null)
                            Text(_moeda.format(nfe.valorTotalNota),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                        ],
                      ),
                      Text(
                        nfe == null
                            ? 'Não foi possível ler os detalhes desta nota.'
                            : [
                                'NF ${nfe.numero ?? '?'}',
                                if (nfe.dataEmissao != null) 'emitida ${_dataCurta.format(nfe.dataEmissao!)}',
                                '${nfe.itens.length} ${nfe.itens.length == 1 ? 'item' : 'itens'}',
                              ].join(' · '),
                        style: TextStyle(fontSize: 12, color: cores.onSurfaceVariant),
                      ),
                      if (pedido != null)
                        Text('Bate com o Pedido #${pedido.numeroSequencial ?? ''}, em aberto',
                            style: TextStyle(fontSize: 12, color: cores.primary, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                if (nfe != null)
                  PopupMenuButton<String>(
                    tooltip: 'Mais opções',
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    onSelected: (_) async {
                      if (!await _podeTrocarDeNota() || !mounted) return;
                      if (await dispensarNotaNaoMercadoria(context, nota.pendente, nfe) && mounted) {
                        if (_chaveSelecionada == nota.pendente.chave) setState(() => _chaveSelecionada = null);
                        _carregar();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'nao_mercadoria',
                        child: ListTile(
                          leading: Icon(Icons.receipt_long_outlined),
                          title: Text('Não é mercadoria'),
                          subtitle: Text('Lançar como despesa ou dispensar'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tituloSecao(BuildContext context, String titulo, {String? detalhe}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text.rich(
        TextSpan(
          text: titulo.toUpperCase(),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(letterSpacing: 0.6, fontWeight: FontWeight.w700),
          children: [
            if (detalhe != null)
              TextSpan(
                text: ' · $detalhe',
                style: TextStyle(fontWeight: FontWeight.w400, letterSpacing: 0, color: colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  Widget _resumoDoMes(BuildContext context, List<Entrada> entradas, List<Despesa> despesas) {
    final colorScheme = Theme.of(context).colorScheme;
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final limite = hoje.add(const Duration(days: 7));

    final doMes = entradas.where((e) {
      final data = e.dataEntrada.toLocal();
      return data.year == agora.year && data.month == agora.month;
    }).toList();
    final comprado = doMes.fold<double>(0, (s, e) => s + (e.valorTotalNota ?? e.valorTotalProdutos ?? 0));

    // Boleto de fornecedor = despesa pendente com fornecedor (é como a
    // importação de NF-e cria cada parcela).
    final deFornecedor = despesas.where((d) => d.fornecedor != null && d.status == StatusDespesa.pendente);
    final aVencer = deFornecedor
        .where((d) => !d.dataVencimento.isBefore(hoje) && !d.dataVencimento.isAfter(limite))
        .fold<double>(0, (s, d) => s + d.valor);
    final atrasado = deFornecedor.where((d) => d.atrasada).fold<double>(0, (s, d) => s + d.valor);

    Widget linha({
      required IconData icone,
      required String rotulo,
      required String valor,
      String? complemento,
      Color? corComplemento,
      VoidCallback? onTap,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Icon(icone, size: 20, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rotulo, style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant)),
                    Text(valor, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    if (complemento != null)
                      Text(complemento, style: TextStyle(fontSize: 12.5, color: corComplemento ?? colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(
                'Em ${_meses[agora.month - 1]}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            linha(
              icone: Icons.shopping_bag_outlined,
              rotulo: 'Comprado',
              valor: _moeda.format(comprado),
              complemento: '${doMes.length} ${doMes.length == 1 ? 'nota lançada' : 'notas lançadas'}',
            ),
            linha(
              icone: Icons.receipt_long_outlined,
              rotulo: 'Boletos de fornecedor nos próximos 7 dias',
              valor: _moeda.format(aVencer),
              complemento: atrasado > 0 ? '${_moeda.format(atrasado)} em atraso' : null,
              corComplemento: colorScheme.error,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DespesasScreen(
                    filtroInicial: atrasado > 0 ? 'Atrasadas' : 'Pendentes',
                    periodoVencimento: atrasado > 0 ? null : DateTimeRange(start: hoje, end: limite),
                  ),
                ),
              ),
            ),
            linha(
              icone: Icons.trending_up,
              rotulo: 'Custo subiu, preço ainda não revisado',
              valor: _produtosMaisCaros.isEmpty
                  ? 'Nenhum produto'
                  : '${_produtosMaisCaros.length} ${_produtosMaisCaros.length == 1 ? 'produto' : 'produtos'}',
              complemento: _produtosMaisCaros.isEmpty ? null : 'A margem desses produtos caiu',
              onTap: _produtosMaisCaros.isEmpty
                  ? null
                  : () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AnaliseProdutosScreen(produtosRevisarPreco: _produtosMaisCaros),
                        ),
                      );
                      if (mounted) _carregar();
                    },
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _secaoChegou(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return [
      _tituloSecao(
        context,
        'Chegou da Sefaz',
        detalhe: _chegaram.isEmpty ? null : 'falta dar entrada (${_chegaram.length})',
      ),
      if (_chegaram.isEmpty && !_carregandoPainel)
        Card(
          child: ListTile(
            leading: Icon(Icons.check_circle_outline, color: colorScheme.primary),
            title: const Text('Tudo em dia'),
            subtitle: const Text('Nota nova emitida pro CNPJ da loja aparece aqui sozinha.'),
          ),
        ),
      for (final nota in _chegaram) _cardChegou(context, nota),
    ];
  }

  Widget _cardChegou(BuildContext context, _NotaChegou nota) {
    final colorScheme = Theme.of(context).colorScheme;
    final nfe = nota.nfe;
    final pedido = nota.pedidoAberto;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    nfe?.fornecedorDetectado.nome ?? 'Nota ${nota.pendente.chave}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                if (nfe != null) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(_moeda.format(nfe.valorTotalNota), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              nfe == null
                  ? 'Não foi possível ler os detalhes desta nota.'
                  : [
                      'NF ${nfe.numero ?? '?'}',
                      if (nfe.dataEmissao != null) 'emitida ${_dataCurta.format(nfe.dataEmissao!)}',
                      '${nfe.itens.length} ${nfe.itens.length == 1 ? 'item' : 'itens'}',
                    ].join(' · '),
              style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
            ),
            if (pedido != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.link, size: 16, color: colorScheme.primary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Bate com o Pedido #${pedido.numeroSequencial ?? ''}, em aberto',
                      style: TextStyle(fontSize: 12.5, color: colorScheme.primary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton(onPressed: () => _darEntrada(nota), child: const Text('Dar entrada')),
                if (nfe != null)
                  PopupMenuButton<String>(
                    tooltip: 'Mais opções',
                    onSelected: (_) => _naoEMercadoria(nota),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'nao_mercadoria',
                        child: ListTile(
                          leading: Icon(Icons.receipt_long_outlined),
                          title: Text('Não é mercadoria'),
                          subtitle: Text('Lançar como despesa ou dispensar'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _secaoACaminho(BuildContext context) {
    if (_aCaminho.isEmpty) return const [];
    final colorScheme = Theme.of(context).colorScheme;
    final agora = DateTime.now();
    return [
      _tituloSecao(context, 'A caminho', detalhe: 'pedido enviado, nota ainda não chegou (${_aCaminho.length})'),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < _aCaminho.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              Builder(builder: (context) {
                final pedido = _aCaminho[i];
                final enviadoEm = pedido.dataEnvio ?? pedido.dataConfirmacao ?? pedido.createdAt;
                final dias = enviadoEm == null ? null : agora.difference(enviadoEm.toLocal()).inDays;
                final previsao = pedido.dataPrevistaEntrega?.toLocal();
                final atrasado = previsao != null && previsao.isBefore(DateTime(agora.year, agora.month, agora.day));
                return ListTile(
                  title: Text(pedido.fornecedor.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [
                      'Pedido #${pedido.numeroSequencial ?? ''}',
                      if (dias != null) dias == 0 ? 'enviado hoje' : 'enviado há $dias ${dias == 1 ? 'dia' : 'dias'}',
                      if (atrasado) 'atrasado (previsto ${_dataCurta.format(previsao)})',
                    ].join(' · '),
                    style: atrasado ? TextStyle(color: colorScheme.error) : null,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => PedidoCompraDetalheScreen(pedidoId: pedido.id!)),
                    );
                    if (mounted) _carregar();
                  },
                );
              }),
            ],
          ],
        ),
      ),
      const SizedBox(height: 20),
    ];
  }

  List<Widget> _secaoLancadas(BuildContext context, List<Entrada> entradas) {
    final colorScheme = Theme.of(context).colorScheme;
    if (entradas.isEmpty) {
      return [
        _tituloSecao(context, 'Já lançadas'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('Nenhuma nota lançada ainda.', style: TextStyle(color: colorScheme.onSurfaceVariant)),
        ),
      ];
    }

    final porMes = <String, List<Entrada>>{};
    for (final e in entradas) {
      final data = e.dataEntrada.toLocal();
      porMes.putIfAbsent('${data.year}-${data.month.toString().padLeft(2, '0')}', () => []).add(e);
    }
    final chaves = porMes.keys.toList()..sort((a, b) => b.compareTo(a));

    return [
      _tituloSecao(context, 'Já lançadas'),
      for (final chave in chaves) ...[
        Builder(builder: (context) {
          final ano = int.parse(chave.substring(0, 4));
          final mes = int.parse(chave.substring(5));
          final total = porMes[chave]!.fold<double>(0, (s, e) => s + (e.valorTotalNota ?? e.valorTotalProdutos ?? 0));
          final rotulo = ano == DateTime.now().year ? _meses[mes - 1] : '${_meses[mes - 1]} de $ano';
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${rotulo[0].toUpperCase()}${rotulo.substring(1)}',
                    style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                  ),
                ),
                Text(_moeda.format(total), style: TextStyle(color: colorScheme.onSurfaceVariant)),
              ],
            ),
          );
        }),
        Card(
          clipBehavior: Clip.antiAlias,
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: [
              for (var i = 0; i < porMes[chave]!.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                Builder(builder: (context) {
                  final entrada = porMes[chave]![i];
                  return ListTile(
                    dense: true,
                    title: Text(
                      entrada.fornecedor?.nome ?? 'Fornecedor não informado',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        if (entrada.nfeNumero != null) 'NF ${entrada.nfeNumero}',
                        _dataCurta.format(entrada.dataEntrada.toLocal()),
                        if (entrada.pedidoCompraNumero != null) 'Pedido #${entrada.pedidoCompraNumero}',
                      ].join(' · '),
                    ),
                    trailing: Text(
                      _moeda.format(entrada.valorTotalNota ?? entrada.valorTotalProdutos ?? 0),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ],
    ];
  }
}
