import 'package:flutter/material.dart';
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
  Widget build(BuildContext context) {
    final entradaProvider = context.watch<EntradaProvider>();
    final despesas = context.watch<DespesaProvider>().despesas;
    final carregandoPrimeiraVez = _carregandoPainel && _chegaram.isEmpty && entradaProvider.entradas.isEmpty;

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
