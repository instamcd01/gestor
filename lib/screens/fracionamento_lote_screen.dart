import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/produto.dart';
import '../providers/produto_provider.dart';
import '../repositories/produto_repository.dart';
import '../utils/busca_utils.dart';
import '../utils/formatadores_input.dart';
import '../utils/produto_validators.dart';
import '../utils/variante_label_utils.dart';
import '../widgets/fracionamento_section.dart';

/// Versão em lote do diálogo "Fracionar em unidade menor" — seleciona vários
/// produtos "pai" de uma vez (aba 1) e cria um produto "filho" fracionado
/// pra cada um (aba 2), reaproveitando o mesmo cálculo/criação de
/// `fracionamento_section.dart`. Não mexe em nenhum estoque além do
/// filho recém-criado — nunca inferimos quantidade física por fórmula sem
/// dar chance de ajuste (ver feedback_nao_inferir_quantidade_fisica_real).
class FracionamentoLoteScreen extends StatefulWidget {
  const FracionamentoLoteScreen({super.key});

  @override
  State<FracionamentoLoteScreen> createState() => _FracionamentoLoteScreenState();
}

class _ConfigLinha {
  EixoFracionamento eixo = EixoFracionamento.peso;
  final pesoNovoController = TextEditingController();
  final fatorController = TextEditingController();
  final rotuloController = TextEditingController();
  final codigoBarrasController = TextEditingController();
  final estoqueController = TextEditingController();
  final margemController = TextEditingController();
  final apresentacaoController = TextEditingController();
  final precoController = TextEditingController();
  final precoIfoodController = TextEditingController();
  String? erro;

  void dispose() {
    pesoNovoController.dispose();
    fatorController.dispose();
    rotuloController.dispose();
    codigoBarrasController.dispose();
    estoqueController.dispose();
    margemController.dispose();
    apresentacaoController.dispose();
    precoController.dispose();
    precoIfoodController.dispose();
  }
}

class _FracionamentoLoteScreenState extends State<FracionamentoLoteScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _buscaController = TextEditingController();
  String _busca = '';
  bool _mostrarTodos = false;
  final Set<String> _selecionados = {};
  final Map<String, _ConfigLinha> _configs = {};
  bool _criando = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _buscaController.dispose();
    for (final config in _configs.values) {
      config.dispose();
    }
    super.dispose();
  }

  void _alternarSelecao(Produto produto, bool? marcado) {
    if (marcado == true) {
      final config = _ConfigLinha();
      setState(() {
        _selecionados.add(produto.id!);
        _configs[produto.id!] = config;
      });
      _carregarMargemSugerida(produto, config);
    } else {
      setState(() {
        _selecionados.remove(produto.id!);
        _configs.remove(produto.id!)?.dispose();
      });
    }
  }

  // Best-effort: reaproveita a última margem usada nesse fabricante (ou
  // categoria) só pra agilizar o preenchimento em série — nunca aplicada
  // sem o usuário poder ver/mudar antes de criar.
  Future<void> _carregarMargemSugerida(Produto pai, _ConfigLinha config) async {
    try {
      final sugestao = await ProdutoRepository().buscarMargemFracionadoSugerida(
        fabricante: pai.fabricante,
        categoria: pai.categoria,
      );
      if (sugestao != null && mounted && config.margemController.text.isEmpty) {
        setState(() => config.margemController.text = sugestao.toStringAsFixed(0));
      }
    } catch (_) {
      // sem sugestão, campo só fica em branco.
    }
  }

  int? _fatorDaLinha(Produto pai, _ConfigLinha config) => calcularFatorFracionamento(
        eixo: config.eixo,
        pai: pai,
        pesoNovoTexto: config.pesoNovoController.text,
        fatorTexto: config.fatorController.text,
      );

  Future<void> _criarTodos(List<Produto> produtos) async {
    // Valida tudo antes de criar qualquer coisa — evita criar metade dos
    // produtos e deixar o usuário sem saber quais linhas ainda precisam de
    // ajuste.
    var temErro = false;
    setState(() {
      for (final id in _selecionados) {
        final pai = produtos.firstWhere((p) => p.id == id);
        final config = _configs[id]!;
        final fator = _fatorDaLinha(pai, config);
        final rotulo = config.rotuloController.text.trim();
        if (fator == null || fator < 1) {
          config.erro = config.eixo == EixoFracionamento.peso
              ? 'Peso não divide o peso do pai em partes inteiras.'
              : 'Informe quantas unidades = 1 do produto original.';
          temErro = true;
          continue;
        }
        if (rotulo.isEmpty) {
          config.erro = 'Informe um rótulo (ex: "1kg").';
          temErro = true;
          continue;
        }
        final erroCodigoBarras = ProdutoValidators.codigoBarras(config.codigoBarrasController.text);
        if (erroCodigoBarras != null) {
          config.erro = erroCodigoBarras;
          temErro = true;
          continue;
        }
        final margemTexto = config.margemController.text.trim().replaceAll(',', '.');
        if (margemTexto.isNotEmpty && double.tryParse(margemTexto) == null) {
          config.erro = 'Margem alvo inválida — use só números (ex: 80).';
          temErro = true;
          continue;
        }
        final erroPreco = ProdutoValidators.precoVenda(config.precoController.text);
        if (config.precoController.text.trim().isNotEmpty && erroPreco != null) {
          config.erro = erroPreco;
          temErro = true;
          continue;
        }
        config.erro = null;
      }
    });

    if (temErro) {
      _tabController.animateTo(1);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Corrija os campos destacados antes de continuar.')),
      );
      return;
    }

    setState(() => _criando = true);
    final provider = context.read<ProdutoProvider>();
    final falhas = <String>[];
    final idsCriados = <String>[];

    for (final id in _selecionados.toList()) {
      final pai = produtos.firstWhere((p) => p.id == id);
      final config = _configs[id]!;
      final fator = _fatorDaLinha(pai, config)!;
      final estoqueOverride = int.tryParse(config.estoqueController.text.trim());
      final margemTexto = config.margemController.text.trim().replaceAll(',', '.');
      final apresentacaoTexto = config.apresentacaoController.text.trim();
      final filho = construirProdutoFracionado(
        pai: pai,
        eixo: config.eixo,
        fator: fator,
        rotulo: config.rotuloController.text.trim(),
        codigoBarras: config.codigoBarrasController.text,
        pesoNovoExplicito: double.tryParse(config.pesoNovoController.text.trim().replaceAll(',', '.')),
        estoqueInicial: estoqueOverride,
        margemAlvoFracionado: margemTexto.isEmpty ? null : double.tryParse(margemTexto),
        apresentacaoExplicita: apresentacaoTexto.isEmpty ? null : apresentacaoTexto,
        preco: ProdutoValidators.parseNumero(config.precoController.text),
        precoIfood: ProdutoValidators.parseNumero(config.precoIfoodController.text),
      );
      try {
        await provider.adicionarProduto(filho);
        idsCriados.add(id);
      } catch (e) {
        falhas.add('${pai.nome}: $e');
      }
    }

    // Remove da seleção só quem deu certo — quem falhou continua na tela
    // pra tentar de novo sem precisar reconfigurar tudo.
    setState(() {
      for (final id in idsCriados) {
        _selecionados.remove(id);
        _configs.remove(id)?.dispose();
      }
      _criando = false;
    });

    if (!mounted) return;

    if (falhas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${idsCriados.length} produto(s) fracionado(s) criado(s).')),
      );
      Navigator.of(context).pop();
    } else {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('${idsCriados.length} criado(s), ${falhas.length} falharam'),
          content: SingleChildScrollView(child: Text(falhas.join('\n\n'))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendi')),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final produtos = context.watch<ProdutoProvider>().produtos;

    final candidatos = produtos.where((p) {
      if (p.id == null) return false;
      if (p.ehKit) return false;
      if (!_mostrarTodos && p.fracionadoDeId != null) return false;
      return contemTodasPalavras(p.nome, _busca) || p.codigoBarras.toLowerCase().contains(_busca.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Criar Fracionamento em Massa'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: 'Selecionar'),
            Tab(text: 'Configurar (${_selecionados.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _abaSelecionar(candidatos),
          _abaConfigurar(produtos),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _selecionados.isEmpty || _criando ? null : () => _criarTodos(produtos),
            icon: _criando
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.call_split),
            label: Text(_criando
                ? 'Criando...'
                : 'Criar ${_selecionados.length} produto(s) fracionado(s)'),
          ),
        ),
      ),
    );
  }

  Widget _abaSelecionar(List<Produto> candidatos) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                controller: _buscaController,
                decoration: const InputDecoration(
                  hintText: 'Buscar produto (nome ou código de barras)',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _busca = v),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Mostrar também produtos já fracionados'),
                value: _mostrarTodos,
                onChanged: (v) => setState(() => _mostrarTodos = v ?? false),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: candidatos.length,
            itemBuilder: (context, i) {
              final produto = candidatos[i];
              final marcado = _selecionados.contains(produto.id);
              return CheckboxListTile(
                value: marcado,
                onChanged: (v) => _alternarSelecao(produto, v),
                title: Text(produto.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${produto.categoria}${produto.peso != null ? ' • ${formatarPeso(produto.peso!)}' : ''} • estoque: ${produto.estoqueAtual}',
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _abaConfigurar(List<Produto> produtos) {
    if (_selecionados.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nenhum produto selecionado ainda. Volte pra aba "Selecionar" e marque os produtos-pai que você quer fracionar.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final id in _selecionados)
          _CardConfiguracao(
            pai: produtos.firstWhere((p) => p.id == id),
            config: _configs[id]!,
            fatorAtual: (config) => _fatorDaLinha(produtos.firstWhere((p) => p.id == id), config),
            onRemover: () => _alternarSelecao(produtos.firstWhere((p) => p.id == id), false),
            onMudou: () => setState(() {}),
          ),
      ],
    );
  }
}

class _CardConfiguracao extends StatefulWidget {
  final Produto pai;
  final _ConfigLinha config;
  final int? Function(_ConfigLinha) fatorAtual;
  final VoidCallback onRemover;
  final VoidCallback onMudou;

  const _CardConfiguracao({
    required this.pai,
    required this.config,
    required this.fatorAtual,
    required this.onRemover,
    required this.onMudou,
  });

  @override
  State<_CardConfiguracao> createState() => _CardConfiguracaoState();
}

class _CardConfiguracaoState extends State<_CardConfiguracao> {
  double? _precoSugerido(Produto pai, _ConfigLinha config, int? fator) {
    if (fator == null) return null;
    final margem = double.tryParse(config.margemController.text.trim().replaceAll(',', '.'));
    if (margem == null) return null;
    return (pai.custo / fator) * (1 + margem / 100);
  }

  String _previewMargem(Produto pai, _ConfigLinha config, int fator) {
    final sugestao = _precoSugerido(pai, config, fator);
    if (sugestao == null) return '';
    return ' Custo: R\$ ${(pai.custo / fator).toStringAsFixed(2)} · Preço sugerido: R\$ ${sugestao.toStringAsFixed(2)}.';
  }

  // Só preenche se o campo ainda estiver vazio — pra não sobrescrever um
  // preço que o usuário já digitou manualmente por cima da sugestão (mesmo
  // critério de _textoInicial em campanha_detalhe_screen.dart).
  void _autoPreencherPrecoSugerido(Produto pai, _ConfigLinha config, int? fator) {
    if (config.precoController.text.trim().isNotEmpty) return;
    final sugestao = _precoSugerido(pai, config, fator);
    if (sugestao != null) {
      config.precoController.text = ProdutoValidators.formatarMoeda(sugestao);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final pai = widget.pai;
    final fator = widget.fatorAtual(config);
    final sugestaoEstoque = fator != null ? pai.estoqueAtual * fator : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(pai.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: widget.onRemover, tooltip: 'Remover'),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<EixoFracionamento>(
              segments: const [
                ButtonSegment(value: EixoFracionamento.peso, label: Text('Por peso')),
                ButtonSegment(value: EixoFracionamento.quantidade, label: Text('Por quantidade')),
              ],
              selected: {config.eixo},
              onSelectionChanged: (s) => setState(() {
                config.eixo = s.first;
                config.erro = null;
                widget.onMudou();
              }),
            ),
            const SizedBox(height: 8),
            if (config.eixo == EixoFracionamento.peso) ...[
              if (pai.peso == null)
                const Text('Produto original não tem peso cadastrado — use "Por quantidade".',
                    style: TextStyle(color: Colors.red))
              else
                TextField(
                  controller: config.pesoNovoController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Peso do novo produto (kg)',
                    helperText: 'Peso do original: ${formatarPeso(pai.peso!)}',
                  ),
                  onChanged: (_) => setState(() {
                    widget.onMudou();
                    _autoPreencherPrecoSugerido(pai, config, widget.fatorAtual(config));
                  }),
                ),
            ] else
              TextField(
                controller: config.fatorController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantas unidades = 1 unidade do original?',
                  helperText: 'Ex: pacote com 4 → digite 4',
                ),
                onChanged: (_) => setState(() {
                  widget.onMudou();
                  _autoPreencherPrecoSugerido(pai, config, widget.fatorAtual(config));
                }),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: config.rotuloController,
              decoration: const InputDecoration(
                labelText: 'Rótulo desta variante',
                helperText: 'Ex: "1kg" ou "Unidade avulsa"',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: config.apresentacaoController,
              decoration: const InputDecoration(
                labelText: 'Apresentação (opcional)',
                helperText: 'Ex: "Pote", "Sachê", "Caixa". Em branco: repete a do produto original.',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: config.codigoBarrasController,
              keyboardType: TextInputType.number,
              inputFormatters: [DigitosInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Código de barras (opcional)',
                helperText: 'Em branco: sistema gera um código interno sozinho',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: config.estoqueController,
              keyboardType: TextInputType.number,
              inputFormatters: [DigitosInputFormatter()],
              decoration: InputDecoration(
                labelText: 'Estoque inicial (opcional)',
                helperText: sugestaoEstoque != null
                    ? 'Em branco usa a sugestão: $sugestaoEstoque (pai atual × fator)'
                    : 'Em branco usa pai.estoqueAtual × fator',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: config.margemController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Margem alvo sobre custo do pai (%, opcional)',
                helperText: 'Preenchido, preço se recalcula sozinho quando o custo do pai mudar. '
                    'Em branco: preço 100% manual.',
              ),
              onChanged: (_) => setState(() {
                _autoPreencherPrecoSugerido(pai, config, widget.fatorAtual(config));
              }),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: config.precoController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [MoedaInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Preço de venda (R\$, opcional)',
                helperText: 'Com margem preenchida acima, já vem sugerido — pode ajustar. Em branco: cria com R\$0 pra configurar depois.',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: config.precoIfoodController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [MoedaInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Preço no iFood (R\$, opcional)',
                helperText: 'Em branco: usa o mesmo preço de venda na exportação do catálogo iFood.',
              ),
            ),
            if (fator != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Fator: 1 do original = $fator deste.${_previewMargem(pai, config, fator)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            if (config.erro != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(config.erro!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }
}
