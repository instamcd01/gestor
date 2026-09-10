import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/produto.dart';
import '../providers/auth_provider.dart';
import '../providers/produto_provider.dart';
import '../repositories/produto_repository.dart';
import '../utils/formatadores_input.dart';
import '../utils/produto_validators.dart';
import 'form_section.dart';

/// Seção "Fracionamento" em editar_produto_screen.dart — permite criar (a
/// partir de um pacote maior) um produto "filho" que representa a mesma
/// mercadoria fracionada em unidades menores (ex: abrir um pacote de 10kg
/// pra vender em unidades de 1kg). Estoque dos dois fica vinculado por
/// trigger no banco (`sincronizar_estoque_pai_fracionado`) — diferente de
/// "família de variantes" (ver FamiliaVariantesSection), que é só
/// agrupamento de exibição, sem relação de estoque real.
class FracionamentoSection extends StatelessWidget {
  final Produto produtoAtual;
  final ValueChanged<Produto> onAbrirProduto;
  final TextEditingController margemAlvoFracionadoController;

  const FracionamentoSection({
    super.key,
    required this.produtoAtual,
    required this.onAbrirProduto,
    required this.margemAlvoFracionadoController,
  });

  @override
  Widget build(BuildContext context) {
    final produtoProvider = context.watch<ProdutoProvider>();
    final produtos = produtoProvider.produtos;

    // Este produto É o filho fracionado de outro.
    if (produtoAtual.fracionadoDeId != null) {
      final pai = produtos.where((p) => p.id == produtoAtual.fracionadoDeId).firstOrNull;
      return FormSection(
        titulo: 'Fracionamento',
        children: [
          Text(
            'Este produto é fracionado de outro — 1 unidade de "${pai?.nome ?? "produto removido"}" '
            'equivale a ${produtoAtual.fatorFracionamento ?? "?"} unidades deste.',
          ),
          Text(
            'O estoque real fica guardado aqui; o do produto maior é recalculado automaticamente.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: margemAlvoFracionadoController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Margem alvo sobre custo do pai (%, opcional)',
              helperText: 'Preenchido, o preço deste produto se recalcula sozinho sempre que o custo do pai mudar. '
                  'Em branco, preço fica 100% manual (salva ao clicar em "Salvar Alterações").',
            ),
          ),
          if (pai != null)
            OutlinedButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: Text('Abrir "${pai.nome}"'),
              onPressed: () => onAbrirProduto(pai),
            ),
        ],
      );
    }

    // Este produto É pai de um (ou mais) fracionado(s).
    final filhos = produtos.where((p) => p.fracionadoDeId == produtoAtual.id).toList();
    if (filhos.isNotEmpty) {
      return FormSection(
        titulo: 'Fracionamento',
        children: [
          Text(
            'O estoque exibido aqui é calculado automaticamente a partir do(s) produto(s) fracionado(s):',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          for (final filho in filhos)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.call_split, size: 20),
              title: Text(filho.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('1 unidade daqui = ${filho.fatorFracionamento} de "${filho.nome}"'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onAbrirProduto(filho),
            ),
        ],
      );
    }

    // Nenhum vínculo ainda — oferece criar um.
    return FormSection(
      titulo: 'Fracionamento',
      children: [
        Text(
          'Se este produto é vendido também em unidades menores (ex: abrir um pacote de 10kg pra vender '
          'em pacotes de 1kg), crie o produto fracionado aqui — o estoque dos dois fica vinculado.',
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.call_split),
          label: const Text('Fracionar em unidade menor'),
          onPressed: () => _abrirDialogoFracionar(context),
        ),
      ],
    );
  }

  Future<void> _abrirDialogoFracionar(BuildContext context) async {
    final novoProduto = await showDialog<Produto>(
      context: context,
      builder: (_) => _DialogoCriarFracionado(produtoPai: produtoAtual),
    );
    if (novoProduto == null || !context.mounted) return;

    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;

    try {
      final criado = await context.read<ProdutoProvider>().adicionarProduto(novoProduto);
      if (!context.mounted) return;
      onAbrirProduto(criado);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao criar produto fracionado: $e')));
      }
    }
  }
}

enum EixoFracionamento { peso, quantidade }

/// Calcula o fator de fracionamento a partir do eixo escolhido — reaproveitado
/// pelo diálogo de criação individual e pela tela de criação em massa
/// (`fracionamento_lote_screen.dart`). Por peso: exige que o peso do pai
/// divida em partes inteiras (senão o estoque vinculado ficaria errado). Por
/// quantidade: o fator é digitado direto.
int? calcularFatorFracionamento({
  required EixoFracionamento eixo,
  required Produto pai,
  String? pesoNovoTexto,
  String? fatorTexto,
}) {
  if (eixo == EixoFracionamento.quantidade) {
    return int.tryParse((fatorTexto ?? '').trim());
  }
  final pesoPai = pai.peso;
  if (pesoPai == null || pesoPai <= 0) return null;
  final pesoNovo = double.tryParse((pesoNovoTexto ?? '').trim().replaceAll(',', '.'));
  if (pesoNovo == null || pesoNovo <= 0) return null;
  final fator = pesoPai / pesoNovo;
  final fatorArredondado = fator.round();
  // Só aceita se a divisão for bem próxima de um número inteiro — senão o
  // usuário provavelmente digitou um peso que não é uma fração exata do
  // pai, e forçar um fator errado bagunçaria o estoque vinculado.
  if ((fator - fatorArredondado).abs() > 0.01) return null;
  return fatorArredondado;
}

/// Monta o `Produto` filho a partir do pai + configuração de fracionamento —
/// mesma lógica usada pelo diálogo individual e pela criação em massa.
/// [estoqueInicial] nulo usa a sugestão padrão (`pai.estoqueAtual * fator`);
/// passar um valor explícito permite o usuário corrigir a sugestão (nunca
/// calculamos estoque físico sozinhos sem dar chance de ajuste — ver
/// feedback_nao_inferir_quantidade_fisica_real).
Produto construirProdutoFracionado({
  required Produto pai,
  required EixoFracionamento eixo,
  required int fator,
  required String rotulo,
  String codigoBarras = '',
  double? pesoNovoExplicito,
  int? estoqueInicial,
  double? margemAlvoFracionado,
}) {
  final pesoNovo = eixo == EixoFracionamento.peso
      ? pesoNovoExplicito
      : (pai.peso != null ? pai.peso! / fator : null);

  return Produto(
    nome: pai.nome, // provisório — o trigger do banco recompõe a partir dos campos estruturados, se houver
    preco: 0,
    descricao: pai.descricao,
    categoria: pai.categoria,
    subcategoria: pai.subcategoria,
    peso: pesoNovo,
    volume: pai.volume,
    ativo: true,
    estoqueAtual: estoqueInicial ?? (pai.estoqueAtual * fator),
    estoqueMinimo: 0,
    imagemUrl: pai.imagemUrl,
    imagemUrlSecundaria: pai.imagemUrlSecundaria,
    // Vazio = o banco gera um EAN interno sozinho (faixa "2xxx", nunca
    // colide com código de fabricante real). Se o lojista já sabe que
    // esse tamanho fracionado tem EAN próprio de fábrica, informar aqui
    // evita ter que criar e editar de novo só pra trocar o código.
    codigoBarras: codigoBarras.trim(),
    custo: pai.custo / fator,
    exibirNoCatalogo: pai.exibirNoCatalogo,
    empresa: pai.empresa,
    fabricante: pai.fabricante,
    unidadeMedida: pai.unidadeMedida,
    nomeComercial: pai.nomeComercial,
    tipoProduto: pai.tipoProduto,
    especie: pai.especie,
    fase: pai.fase,
    porte: pai.porte,
    sabor: pai.sabor,
    dose: pai.dose,
    composicao: pai.composicao,
    apresentacao: eixo == EixoFracionamento.quantidade ? rotulo : pai.apresentacao,
    nomeManualOverride: pai.nomeManualOverride,
    produtoPaiId: pai.produtoPaiId ?? pai.id,
    tipoVariacao: eixo == EixoFracionamento.peso ? 'peso' : 'quantidade',
    varianteLabel: rotulo,
    cicloRecompraDias: pai.cicloRecompraDias,
    fracionadoDeId: pai.id,
    fatorFracionamento: fator,
    margemAlvoFracionado: margemAlvoFracionado,
  );
}

class _DialogoCriarFracionado extends StatefulWidget {
  final Produto produtoPai;

  const _DialogoCriarFracionado({required this.produtoPai});

  @override
  State<_DialogoCriarFracionado> createState() => _DialogoCriarFracionadoState();
}

class _DialogoCriarFracionadoState extends State<_DialogoCriarFracionado> {
  EixoFracionamento _eixo = EixoFracionamento.peso;
  final _pesoNovoController = TextEditingController();
  final _fatorController = TextEditingController();
  final _rotuloController = TextEditingController();
  final _codigoBarrasController = TextEditingController();
  final _margemController = TextEditingController();
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregarMargemSugerida();
  }

  Future<void> _carregarMargemSugerida() async {
    try {
      final sugestao = await ProdutoRepository().buscarMargemFracionadoSugerida(
        fabricante: widget.produtoPai.fabricante,
        categoria: widget.produtoPai.categoria,
      );
      if (sugestao != null && mounted && _margemController.text.isEmpty) {
        setState(() => _margemController.text = sugestao.toStringAsFixed(0));
      }
    } catch (_) {
      // best-effort — sem sugestão, o campo só fica em branco.
    }
  }

  @override
  void dispose() {
    _pesoNovoController.dispose();
    _fatorController.dispose();
    _rotuloController.dispose();
    _codigoBarrasController.dispose();
    _margemController.dispose();
    super.dispose();
  }

  String _previewMargem(int fator) {
    final margem = double.tryParse(_margemController.text.trim().replaceAll(',', '.'));
    if (margem == null) return '';
    final custoFilho = widget.produtoPai.custo / fator;
    final precoSugerido = custoFilho * (1 + margem / 100);
    return ' Custo: R\$ ${custoFilho.toStringAsFixed(2)} · Preço sugerido: R\$ ${precoSugerido.toStringAsFixed(2)}.';
  }

  int? get _fatorCalculado => calcularFatorFracionamento(
        eixo: _eixo,
        pai: widget.produtoPai,
        pesoNovoTexto: _pesoNovoController.text,
        fatorTexto: _fatorController.text,
      );

  void _confirmar() {
    final fator = _fatorCalculado;
    final rotulo = _rotuloController.text.trim();
    if (fator == null || fator < 1) {
      setState(() => _erro = _eixo == EixoFracionamento.peso
          ? 'Informe um peso que divida o peso do produto original em partes inteiras.'
          : 'Informe quantas unidades equivalem a 1 unidade do produto original.');
      return;
    }
    if (rotulo.isEmpty) {
      setState(() => _erro = 'Informe um rótulo pra identificar esta variante (ex: "1kg", "Unidade avulsa").');
      return;
    }
    final erroCodigoBarras = ProdutoValidators.codigoBarras(_codigoBarrasController.text);
    if (erroCodigoBarras != null) {
      setState(() => _erro = erroCodigoBarras);
      return;
    }

    final margemTexto = _margemController.text.trim().replaceAll(',', '.');
    final margem = margemTexto.isEmpty ? null : double.tryParse(margemTexto);
    if (margemTexto.isNotEmpty && margem == null) {
      setState(() => _erro = 'Margem alvo inválida — use só números (ex: 80).');
      return;
    }

    final filho = construirProdutoFracionado(
      pai: widget.produtoPai,
      eixo: _eixo,
      fator: fator,
      rotulo: rotulo,
      codigoBarras: _codigoBarrasController.text,
      pesoNovoExplicito: double.tryParse(_pesoNovoController.text.trim().replaceAll(',', '.')),
      margemAlvoFracionado: margem,
    );

    Navigator.of(context).pop(filho);
  }

  @override
  Widget build(BuildContext context) {
    final pesoPai = widget.produtoPai.peso;
    return AlertDialog(
      title: const Text('Fracionar em unidade menor'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('A partir de "${widget.produtoPai.nome}"', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            SegmentedButton<EixoFracionamento>(
              segments: const [
                ButtonSegment(value: EixoFracionamento.peso, label: Text('Por peso')),
                ButtonSegment(value: EixoFracionamento.quantidade, label: Text('Por quantidade')),
              ],
              selected: {_eixo},
              onSelectionChanged: (s) => setState(() {
                _eixo = s.first;
                _erro = null;
              }),
            ),
            const SizedBox(height: 12),
            if (_eixo == EixoFracionamento.peso) ...[
              if (pesoPai == null)
                const Text('O produto original não tem peso cadastrado — use "Por quantidade".',
                    style: TextStyle(color: Colors.red))
              else ...[
                Text('Peso do original: $pesoPai kg'),
                TextField(
                  controller: _pesoNovoController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Peso do novo produto (kg)'),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ] else
              TextField(
                controller: _fatorController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantas unidades = 1 unidade do original?',
                  helperText: 'Ex: pacote com 4 → digite 4',
                ),
                onChanged: (_) => setState(() {}),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _rotuloController,
              decoration: const InputDecoration(
                labelText: 'Rótulo desta variante',
                helperText: 'Ex: "1kg" ou "Unidade avulsa"',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codigoBarrasController,
              keyboardType: TextInputType.number,
              inputFormatters: [DigitosInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Código de barras (Opcional)',
                helperText: 'Só se esse tamanho já tiver EAN próprio de fábrica — '
                    'em branco, o sistema gera um código interno sozinho',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _margemController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Margem alvo sobre custo do pai (%, opcional)',
                helperText: 'Preço = custo/unidade do pai × (1 + margem). Deixe em branco pra preço 100% manual '
                    '(ex: unidade avulsa). Preenchido, o preço se recalcula sozinho sempre que o custo do pai mudar.',
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_fatorCalculado != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Fator: 1 unidade do original = $_fatorCalculado deste. '
                  'Estoque inicial sugerido: ${widget.produtoPai.estoqueAtual * _fatorCalculado!}.'
                  '${_previewMargem(_fatorCalculado!)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            if (_erro != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_erro!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _confirmar, child: const Text('Criar')),
      ],
    );
  }
}
