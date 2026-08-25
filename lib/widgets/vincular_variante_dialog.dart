import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/produto.dart';
import '../providers/produto_provider.dart';
import '../repositories/valor_estruturado_repository.dart';
import '../utils/busca_utils.dart';
import '../utils/variante_label_utils.dart';
import 'campo_com_sugestao.dart';

const List<String> _tiposVariacao = ['peso', 'volume', 'dose', 'sabor', 'apresentacao', 'outro'];

/// Só estes 3 eixos têm vocabulário curado em `valores_estruturados_variante`
/// (peso/volume são colunas numéricas próprias, sem lista de valores; "outro"
/// é livre por natureza) — os demais caem pra campo de texto comum.
const List<String> _tiposComVocabulario = ['dose', 'sabor', 'apresentacao'];

/// Vincula manualmente dois produtos como variantes um do outro — pra
/// quando o produto não aparece nas sugestões automáticas (ver
/// `sugestoes_variante`, que só detecta por campos estruturados iguais ou
/// semelhança de nome). Dois passos: escolher o outro produto, depois
/// definir o eixo e o rótulo de cada lado — mesmos campos de
/// `DialogoRevisaoVariante`, só que sem uma sugestão pronta por trás.
class VincularVarianteDialog extends StatefulWidget {
  final Produto produto;

  const VincularVarianteDialog({super.key, required this.produto});

  @override
  State<VincularVarianteDialog> createState() => _VincularVarianteDialogState();
}

class _VincularVarianteDialogState extends State<VincularVarianteDialog> {
  final _valorRepository = ValorEstruturadoRepository();
  Produto? _candidato;
  final _buscaController = TextEditingController();
  late TextEditingController _labelProdutoController;
  late TextEditingController _labelCandidatoController;
  String _tipoVariacao = 'peso';
  bool _processando = false;

  /// Mesmo formato de `CamposEstruturadosVariante`: categoria -> campo ->
  /// valores. Carregado uma vez só (igual cadastro/edição de produto),
  /// os campos de "Opção" combinam categoria específica + globais na hora
  /// de montar a lista de sugestões.
  Map<String, Map<String, List<String>>> _valoresPorCategoria = {};

  @override
  void initState() {
    super.initState();
    // labelPadraoVariante() cai pro campo estruturado correspondente
    // (peso/dose/sabor...) quando `varianteLabel` ainda não existe — que é
    // sempre o caso aqui, já que este diálogo só aparece pra produto ainda
    // solto (nunca foi vinculado antes, nunca teve variante_label setado).
    _labelProdutoController = TextEditingController(text: labelPadraoVariante(widget.produto, _tipoVariacao));
    _labelCandidatoController = TextEditingController();
    _carregarValores();
  }

  Future<void> _carregarValores() async {
    try {
      final valores = await _valorRepository.carregarPorCategoria();
      if (mounted) setState(() => _valoresPorCategoria = valores);
    } catch (e) {
      debugPrint('Erro ao carregar vocabulário de variante: $e');
    }
  }

  List<String> _sugestoesPara(String campo, String categoria) {
    if (!_tiposComVocabulario.contains(campo)) return const [];
    final especificos = _valoresPorCategoria[categoria]?[campo] ?? const <String>[];
    final globais = _valoresPorCategoria['']?[campo] ?? const <String>[];
    if (globais.isEmpty) return especificos;
    return {...especificos, ...globais}.toList()..sort();
  }

  @override
  void dispose() {
    _buscaController.dispose();
    _labelProdutoController.dispose();
    _labelCandidatoController.dispose();
    super.dispose();
  }

  // Mesmo critério do trigger `detectar_sugestao_variante` (banco): compara
  // os 5 campos variáveis entre os dois produtos e, se exatamente 1 for
  // diferente, é esse o eixo real da variação. Ambíguo (0 ou 2+ diferentes)
  // não tenta adivinhar — mantém o eixo que já estava selecionado.
  static const _camposVariaveis = ['dose', 'apresentacao', 'sabor', 'peso', 'volume'];

  Object? _valorCampo(Produto p, String campo) {
    switch (campo) {
      case 'dose':
        return p.dose;
      case 'apresentacao':
        return p.apresentacao;
      case 'sabor':
        return p.sabor;
      case 'peso':
        return p.peso;
      case 'volume':
        return p.volume;
    }
    return null;
  }

  String? _detectarEixo(Produto a, Produto b) {
    String? campoDiferente;
    var diferentes = 0;
    for (final campo in _camposVariaveis) {
      if (_valorCampo(a, campo) != _valorCampo(b, campo)) {
        diferentes++;
        campoDiferente = campo;
      }
    }
    return diferentes == 1 ? campoDiferente : null;
  }

  // Sempre repõe os dois rótulos a partir do que já está no cadastro
  // estruturado de cada produto pro eixo atual — nunca deixa um rótulo de
  // um eixo anterior sobrar quando o eixo muda.
  void _repreencherRotulos(Produto candidato) {
    _labelProdutoController.text = labelPadraoVariante(widget.produto, _tipoVariacao);
    _labelCandidatoController.text = labelPadraoVariante(candidato, _tipoVariacao);
  }

  void _selecionarCandidato(Produto p) {
    setState(() {
      _candidato = p;
      final eixoDetectado = _detectarEixo(widget.produto, p);
      if (eixoDetectado != null) _tipoVariacao = eixoDetectado;
      _repreencherRotulos(p);
    });
  }

  Future<void> _vincular() async {
    final candidato = _candidato;
    if (candidato == null) return;
    setState(() => _processando = true);
    try {
      await context.read<ProdutoProvider>().vincularVarianteManualmente(
            produtoId: widget.produto.id!,
            produtoCandidatoId: candidato.id!,
            tipoVariacao: _tipoVariacao,
            varianteLabelProduto: _labelProdutoController.text,
            varianteLabelCandidato: _labelCandidatoController.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível vincular: $e')),
        );
        setState(() => _processando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidato = _candidato;

    if (candidato == null) {
      final todos = context.watch<ProdutoProvider>().produtos;
      final busca = _buscaController.text;
      final resultados = (busca.isEmpty
              ? todos
              : todos.where((p) => contemTodasPalavras(p.nome, busca)))
          .where((p) => p.id != widget.produto.id)
          .take(30)
          .toList();

      return AlertDialog(
        title: const Text('Vincular a outro produto'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Column(
            children: [
              TextField(
                controller: _buscaController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Buscar produto',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: resultados.isEmpty
                    ? const Center(child: Text('Nenhum produto encontrado.'))
                    : ListView.builder(
                        itemCount: resultados.length,
                        itemBuilder: (context, i) {
                          final p = resultados[i];
                          return ListTile(
                            title: Text(p.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text('R\$ ${p.preco.toStringAsFixed(2)}'),
                            onTap: () => _selecionarCandidato(p),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Vincular a outro produto'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _tipoVariacao,
              decoration: const InputDecoration(labelText: 'Eixo da variação'),
              items: [
                for (final tipo in _tiposVariacao)
                  DropdownMenuItem(value: tipo, child: Text(rotuloTipoVariacao(tipo))),
              ],
              onChanged: (v) => setState(() {
                _tipoVariacao = v!;
                _repreencherRotulos(candidato);
              }),
            ),
            const SizedBox(height: 16),
            Text(widget.produto.nome, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
            CampoComSugestao(
              controller: _labelProdutoController,
              label: 'Opção deste produto',
              sugestoes: _sugestoesPara(_tipoVariacao, widget.produto.categoria),
            ),
            const SizedBox(height: 16),
            Text(candidato.nome, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
            CampoComSugestao(
              controller: _labelCandidatoController,
              label: 'Opção do outro produto',
              sugestoes: _sugestoesPara(_tipoVariacao, candidato.categoria),
            ),
          ],
        ),
      ),
      actions: _processando
          ? [const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())]
          : [
              TextButton(onPressed: () => setState(() => _candidato = null), child: const Text('Voltar')),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              FilledButton(onPressed: _vincular, child: const Text('Vincular')),
            ],
    );
  }
}
