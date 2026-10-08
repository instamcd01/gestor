import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/supabase_config.dart';
import '../models/sugestao_produto_cliente.dart';
import '../repositories/sugestao_produto_cliente_repository.dart';
import '../widgets/estado_erro_lista.dart';

const Map<String, (String, IconData, Color)> _statusInfo = {
  'pendente': ('Pendente', Icons.schedule, Colors.orange),
  'avaliado': ('Avaliado', Icons.visibility_outlined, Colors.blue),
  'comprado': ('Incluído no pedido', Icons.check_circle_outline, Colors.green),
};

const List<String> _cicloStatus = ['pendente', 'avaliado', 'comprado'];

/// Produtos que clientes procuraram no site e não acharam — enviados via
/// `enviar_sugestao_produto_cliente` (RPC, aceita envio anônimo) quando a
/// busca não retorna nada. Cada linha soma quantas vezes o mesmo termo
/// (normalizado) já apareceu, pra ajudar a priorizar o que vale a pena
/// incluir no próximo pedido a fornecedor.
class SugestoesProdutoClienteScreen extends StatefulWidget {
  const SugestoesProdutoClienteScreen({super.key});

  @override
  State<SugestoesProdutoClienteScreen> createState() => _SugestoesProdutoClienteScreenState();
}

class _SugestoesProdutoClienteScreenState extends State<SugestoesProdutoClienteScreen> {
  final _repository = SugestaoProdutoClienteRepository();
  List<SugestaoProdutoCliente> _sugestoes = [];
  bool _carregando = true;
  String? _erro;
  bool _mostrarSoPendentes = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final sugestoes = await _repository.listar();
      if (!mounted) return;
      setState(() {
        _sugestoes = sugestoes;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao carregar sugestões: $e';
        _carregando = false;
      });
    }
  }

  Future<void> _avancarStatus(SugestaoProdutoCliente s) async {
    final indiceAtual = _cicloStatus.indexOf(s.status);
    final novoStatus = _cicloStatus[(indiceAtual + 1) % _cicloStatus.length];

    final indice = _sugestoes.indexWhere((x) => x.id == s.id);
    setState(() {
      _sugestoes[indice] = SugestaoProdutoCliente(
        id: s.id,
        termoBuscado: s.termoBuscado,
        mensagem: s.mensagem,
        contato: s.contato,
        status: novoStatus,
        createdAt: s.createdAt,
        avaliadoEm: novoStatus == 'pendente' ? null : DateTime.now(),
        clienteNome: s.clienteNome,
        clienteTelefone: s.clienteTelefone,
      );
    });

    try {
      await _repository.marcarStatus(s.id, novoStatus);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível atualizar: $e')),
      );
      _carregar();
    }
  }

  /// Quantas vezes esse termo (sem acento/maiúscula) já apareceu no total
  /// carregado — ajuda a notar "3 pessoas pediram isso" de relance.
  Map<String, int> get _contagemPorTermo {
    final contagem = <String, int>{};
    for (final s in _sugestoes) {
      final chave = s.termoBuscado.trim().toLowerCase();
      contagem[chave] = (contagem[chave] ?? 0) + 1;
    }
    return contagem;
  }

  @override
  Widget build(BuildContext context) {
    final visiveis = _mostrarSoPendentes ? _sugestoes.where((s) => s.pendente).toList() : _sugestoes;
    final contagem = _contagemPorTermo;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sugestões de Clientes'),
          bottom: const TabBar(tabs: [Tab(text: 'Pedidos de clientes'), Tab(text: 'Buscas sem resultado')]),
          actions: [
            IconButton(
              icon: Icon(_mostrarSoPendentes ? Icons.filter_alt : Icons.filter_alt_off_outlined),
              tooltip: _mostrarSoPendentes
                  ? 'Mostrando só pendentes — toque pra ver tudo'
                  : 'Mostrando tudo — toque pra ver só pendentes',
              onPressed: () => setState(() => _mostrarSoPendentes = !_mostrarSoPendentes),
            ),
          ],
        ),
        body: TabBarView(children: [_abaPedidos(context, visiveis, contagem), const _BuscasSemResultado()]),
      ),
    );
  }

  Widget _abaPedidos(BuildContext context, List<SugestaoProdutoCliente> visiveis, Map<String, int> contagem) {
    return _carregando && _sugestoes.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : _erro != null && _sugestoes.isEmpty
            ? EstadoErroLista(mensagem: _erro!, onTentarNovamente: _carregar)
            : visiveis.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(height: 16),
                          Text(
                            _mostrarSoPendentes ? 'Nenhuma sugestão pendente.' : 'Nenhuma sugestão recebida ainda.',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _carregar,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: visiveis.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final s = visiveis[i];
                        final (rotulo, icone, cor) = _statusInfo[s.status]!;
                        final vezes = contagem[s.termoBuscado.trim().toLowerCase()] ?? 1;

                        return ListTile(
                          leading: IconButton(
                            icon: Icon(icone, color: cor),
                            tooltip: '$rotulo — toque pra avançar',
                            onPressed: () => _avancarStatus(s),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                  child: Text(s.termoBuscado, style: const TextStyle(fontWeight: FontWeight.w600))),
                              if (vezes > 1)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text('${vezes}x', style: Theme.of(context).textTheme.bodySmall),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (s.mensagem != null && s.mensagem!.isNotEmpty) Text(s.mensagem!),
                              if (s.clienteNome != null || s.contato != null)
                                Text(
                                  s.clienteNome ?? s.contato ?? '',
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                                ),
                              Text(
                                DateFormat('dd/MM/yyyy HH:mm').format(s.createdAt.toLocal()),
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11),
                              ),
                            ],
                          ),
                          isThreeLine: true,
                        );
                      },
                    ),
                  );
  }
}

/// O que os clientes buscaram no site e não acharam à venda (`buscas_site`,
/// gravado pelo próprio site a cada busca desde 07/10) — demanda perdida que
/// antes não ficava registrada, já que quase ninguém usa o "Avise a gente".
/// "Tem, sem estoque" = produto cadastrado, só falta repor.
class _BuscasSemResultado extends StatefulWidget {
  const _BuscasSemResultado();

  @override
  State<_BuscasSemResultado> createState() => _BuscasSemResultadoState();
}

class _BuscasSemResultadoState extends State<_BuscasSemResultado> {
  late Future<List<Map<String, dynamic>>> _futuro = _buscar();

  Future<List<Map<String, dynamic>>> _buscar() async {
    final dados = await supabase.rpc('buscas_sem_resultado', params: {'p_dias': 30});
    return List<Map<String, dynamic>>.from(dados as List);
  }

  Future<void> _recarregar() async {
    setState(() {
      _futuro = _buscar();
    });
    await _futuro;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _futuro,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return EstadoErroLista(
              mensagem: 'Erro ao carregar buscas: ${snapshot.error}', onTentarNovamente: _recarregar);
        }
        final buscas = snapshot.data ?? [];
        return RefreshIndicator(
          onRefresh: _recarregar,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Últimos 30 dias. "Não temos" = vale avaliar incluir no catálogo; '
                  '"Tem, sem estoque" = já está cadastrado, só falta repor.',
                  style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                ),
              ),
              if (buscas.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.search, size: 56, color: colorScheme.onSurfaceVariant),
                      const SizedBox(height: 16),
                      const Text('Nenhuma busca sem resultado ainda.', textAlign: TextAlign.center),
                      const SizedBox(height: 4),
                      Text(
                        'As buscas do site passaram a ser registradas em 07/10 — a lista vai se formando com o uso.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              for (final b in buscas) ...[
                ListTile(
                  title: Text(b['termo']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text([
                    '${b['vezes']} ${b['vezes'] == 1 ? 'busca' : 'buscas'}',
                    if (b['ultima'] != null)
                      'última ${DateFormat('dd/MM').format(DateTime.parse(b['ultima'].toString()).toLocal())}',
                  ].join(' · ')),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: b['esgotado'] == true ? Colors.orange.withValues(alpha: 0.15) : colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      b['esgotado'] == true ? 'Tem, sem estoque' : 'Não temos',
                      style: TextStyle(
                        fontSize: 12,
                        color: b['esgotado'] == true ? Colors.orange.shade900 : colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
              ],
            ],
          ),
        );
      },
    );
  }
}
