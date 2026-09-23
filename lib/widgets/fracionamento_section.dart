import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../models/produto.dart';
import '../providers/auth_provider.dart';
import '../providers/produto_provider.dart';
import '../repositories/marketplace_repository.dart';
import '../repositories/produto_canal_repository.dart';
import '../repositories/produto_repository.dart';
import '../utils/formatadores_input.dart';
import '../utils/produto_validators.dart';
import '../utils/variante_label_utils.dart';
import 'busca_produto_sheet.dart';
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

  /// Reabre a tela ATUAL com o produto recarregado — usado depois de vincular
  /// a um produto existente, porque estoque/custo/preço deste produto mudam
  /// no banco e os campos de texto da tela ficariam com o valor antigo (um
  /// "Salvar Alterações" em seguida sobrescreveria o estoque recém-calculado).
  final ValueChanged<Produto> onRecarregarProduto;

  const FracionamentoSection({
    super.key,
    required this.produtoAtual,
    required this.onAbrirProduto,
    required this.margemAlvoFracionadoController,
    required this.onRecarregarProduto,
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (pai != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: Text('Abrir "${pai.nome}"'),
                  onPressed: () => onAbrirProduto(pai),
                ),
              OutlinedButton.icon(
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Trocar produto pai'),
                onPressed: () => _abrirDialogoTrocarPai(context, produtos, pai),
              ),
            ],
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
          'em pacotes de 1kg), crie o produto fracionado aqui — o estoque dos dois fica vinculado. '
          'Se os dois produtos já estão cadastrados (ex: caixa com 20 e o sachê avulso), use "Vincular".',
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.call_split),
              label: const Text('Fracionar em unidade menor'),
              onPressed: () => _abrirDialogoFracionar(context),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.link),
              label: const Text('Vincular unidade já cadastrada'),
              onPressed: () => _vincularExistente(context, produtos, esteEhOPai: true),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Vincular à embalagem já cadastrada'),
              onPressed: () => _vincularExistente(context, produtos, esteEhOPai: false),
            ),
          ],
        ),
      ],
    );
  }

  /// Liga este produto a outro JÁ CADASTRADO — [esteEhOPai] true: este é a
  /// embalagem fechada e o usuário escolhe a unidade; false: este é a
  /// unidade e escolhe a embalagem. Mesmo vínculo do "Fracionar" (ver
  /// `ProdutoRepository.vincularFracionamentoExistente`), só sem criar
  /// produto novo.
  Future<void> _vincularExistente(BuildContext context, List<Produto> produtos, {required bool esteEhOPai}) async {
    // Mesmas regras que o banco valida (1 embalagem : 1 unidade, sem kit,
    // sem quem já participa de outro fracionamento) — filtradas aqui pra
    // não oferecer uma opção que só daria erro depois.
    final idsQueSaoPai = produtos.map((p) => p.fracionadoDeId).whereType<String>().toSet();
    final candidatos = produtos
        .where((p) =>
            p.id != null &&
            p.id != produtoAtual.id &&
            !p.ehKit &&
            p.fracionadoDeId == null &&
            !idsQueSaoPai.contains(p.id))
        .toList();
    // Mesma família de variantes primeiro (caso comum: caixa e sachê já
    // agrupados como variantes um do outro), depois alfabético.
    final familiaAtual = produtoAtual.produtoPaiId ?? produtoAtual.id;
    bool mesmaFamilia(Produto p) => (p.produtoPaiId ?? p.id) == familiaAtual;
    candidatos.sort((a, b) {
      final fa = mesmaFamilia(a) ? 0 : 1;
      final fb = mesmaFamilia(b) ? 0 : 1;
      return fa != fb ? fa - fb : a.nome.compareTo(b.nome);
    });

    final outro = await showModalBottomSheet<Produto>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BuscaProdutoSheet(produtos: candidatos, permiteCadastrarNovo: false),
    );
    if (outro == null || !context.mounted) return;

    final pai = esteEhOPai ? produtoAtual : outro;
    final filho = esteEhOPai ? outro : produtoAtual;

    final confirmado = await showDialog<_ConfiguracaoVinculo>(
      context: context,
      builder: (_) => _DialogoVincularExistente(pai: pai, filho: filho),
    );
    if (confirmado == null || !context.mounted) return;

    final provider = context.read<ProdutoProvider>();
    try {
      await provider.vincularFracionamentoExistente(
        paiId: pai.id!,
        filhoId: filho.id!,
        fator: confirmado.fator,
        estoqueFilho: confirmado.estoqueFilho,
        margemAlvo: confirmado.margemAlvo,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vinculado: 1 "${pai.nome}" = ${confirmado.fator} "${filho.nome}".')),
      );
      final recarregado = provider.getProdutoPorId(produtoAtual.id!);
      if (recarregado != null) onRecarregarProduto(recarregado);
    } catch (e) {
      if (context.mounted) {
        // Mensagem da RPC já vem pronta pra exibir (ex: "já tem uma unidade
        // fracionada vinculada").
        final mensagem = e is PostgrestException ? e.message : e.toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao vincular: $mensagem')));
      }
    }
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
      // Mesmo passo da criação em massa: preço no iFood só produz efeito de
      // verdade em produto_canal (o switch/preço reais de "Disponibilidade em
      // Marketplaces") — produtos.preco_ifood sozinho é só fallback legado da
      // exportação de planilha. Best-effort: se falhar, o produto já foi
      // criado igual, só não habilita o canal sozinho.
      if (novoProduto.precoIfood != null && criado.id != null) {
        try {
          final marketplaces = await MarketplaceRepository().listarAtivos();
          final ifood = marketplaces.where((m) => m.nome == 'iFood').firstOrNull;
          if (ifood != null) {
            await ProdutoCanalRepository().salvar(
              produtoId: criado.id!,
              marketplaceId: ifood.id,
              preco: novoProduto.precoIfood!,
              disponivel: true,
            );
          }
        } catch (_) {
          // segue sem — produto já foi criado, só não habilita o canal.
        }
      }
      if (!context.mounted) return;
      onAbrirProduto(criado);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao criar produto fracionado: $e')));
      }
    }
  }

  /// Religa este produto (já fracionado) a um pai diferente — ex: comprava
  /// fracionando do pacote de 10kg, passou a comprar do de 20kg, mas quer
  /// manter o produto de 10kg ativo à venda normalmente, só sem o vínculo.
  /// Não move nenhum estoque físico: o produto fracionado continua com o
  /// mesmo estoque que já tinha, só passa a alimentar o cálculo automático
  /// de um pai diferente (ver `sincronizar_estoque_pai_fracionado`).
  Future<void> _abrirDialogoTrocarPai(BuildContext context, List<Produto> produtos, Produto? paiAtual) async {
    final candidatos = produtos
        .where((p) => p.id != null && p.id != produtoAtual.id && p.id != paiAtual?.id && p.ativo && !p.ehKit)
        .toList()
      ..sort((a, b) => a.nome.compareTo(b.nome));

    final novoPai = await showModalBottomSheet<Produto>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BuscaProdutoSheet(produtos: candidatos, permiteCadastrarNovo: false),
    );
    if (novoPai == null || !context.mounted) return;

    // Peso é a única condição estruturada da qual dá pra derivar o fator
    // sozinho (novoPai.peso ÷ peso deste produto); fracionamento por
    // quantidade não tem um número comparável entre os dois, então pede
    // pro usuário confirmar/digitar.
    int? fatorSugerido;
    if (produtoAtual.tipoVariacao == 'peso' && produtoAtual.peso != null && novoPai.peso != null) {
      fatorSugerido = calcularFatorFracionamento(
        eixo: EixoFracionamento.peso,
        pai: novoPai,
        pesoNovoTexto: produtoAtual.peso.toString(),
      );
    }

    if (!context.mounted) return;
    final fator = await showDialog<int>(
      context: context,
      builder: (_) => _DialogoConfirmarTrocaPai(
        produtoAtual: produtoAtual,
        novoPai: novoPai,
        fatorSugerido: fatorSugerido,
      ),
    );
    if (fator == null || !context.mounted) return;

    final atualizado = _comNovoPai(produtoAtual, novoPaiId: novoPai.id!, fator: fator);
    try {
      await context.read<ProdutoProvider>().atualizarProduto(atualizado);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Vínculo trocado pra "${novoPai.nome}".')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao trocar vínculo: $e')));
      }
    }
  }
}

/// Mesma instância de `produtoAtual`, só com o vínculo de fracionamento
/// apontando pro novo pai — `fracionadoDeId`/`fatorFracionamento` são
/// `final` no model, então precisa reconstruir o objeto inteiro (mesmo
/// padrão do salvar comum em editar_produto_screen.dart, que também
/// reconstrói tudo campo a campo).
Produto _comNovoPai(Produto atual, {required String novoPaiId, required int fator}) {
  return Produto(
    id: atual.id,
    nome: atual.nome,
    preco: atual.preco,
    precoPromocional: atual.precoPromocional,
    descricao: atual.descricao,
    categoria: atual.categoria,
    subcategoria: atual.subcategoria,
    sku: atual.sku,
    peso: atual.peso,
    volume: atual.volume,
    ativo: atual.ativo,
    estoqueAtual: atual.estoqueAtual,
    estoqueMinimo: atual.estoqueMinimo,
    imagemUrl: atual.imagemUrl,
    imagemUrlSecundaria: atual.imagemUrlSecundaria,
    updatedAt: atual.updatedAt,
    codigoBarras: atual.codigoBarras,
    custo: atual.custo,
    destacar: atual.destacar,
    exibirNoCatalogo: atual.exibirNoCatalogo,
    precoIfood: atual.precoIfood,
    validade: atual.validade,
    markup: atual.markup,
    lucro: atual.lucro,
    empresa: atual.empresa,
    precoConcorrencia: atual.precoConcorrencia,
    fabricante: atual.fabricante,
    estoqueId: atual.estoqueId,
    unidadeMedida: atual.unidadeMedida,
    permiteFracionamento: atual.permiteFracionamento,
    fracionadoDeId: novoPaiId,
    fatorFracionamento: fator,
    margemAlvoFracionado: atual.margemAlvoFracionado,
    precoCalculadoAutomatico: atual.precoCalculadoAutomatico,
    revisarPreco: atual.revisarPreco,
    nomeComercial: atual.nomeComercial,
    tipoProduto: atual.tipoProduto,
    especie: atual.especie,
    fase: atual.fase,
    porte: atual.porte,
    sabor: atual.sabor,
    dose: atual.dose,
    composicao: atual.composicao,
    apresentacao: atual.apresentacao,
    nomeManualOverride: atual.nomeManualOverride,
    produtoPaiId: atual.produtoPaiId,
    tipoVariacao: atual.tipoVariacao,
    varianteLabel: atual.varianteLabel,
    camposEstruturadosPersonalizados: atual.camposEstruturadosPersonalizados,
    cicloRecompraDias: atual.cicloRecompraDias,
    ehKit: atual.ehKit,
  );
}

class _DialogoConfirmarTrocaPai extends StatefulWidget {
  final Produto produtoAtual;
  final Produto novoPai;
  final int? fatorSugerido;

  const _DialogoConfirmarTrocaPai({
    required this.produtoAtual,
    required this.novoPai,
    required this.fatorSugerido,
  });

  @override
  State<_DialogoConfirmarTrocaPai> createState() => _DialogoConfirmarTrocaPaiState();
}

class _DialogoConfirmarTrocaPaiState extends State<_DialogoConfirmarTrocaPai> {
  late final _fatorController =
      TextEditingController(text: widget.fatorSugerido?.toString() ?? '');
  String? _erro;

  @override
  void dispose() {
    _fatorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final calculadoSozinho = widget.fatorSugerido != null;
    return AlertDialog(
      title: const Text('Trocar produto pai'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('"${widget.produtoAtual.nome}" vai passar a ser fracionado de "${widget.novoPai.nome}".'),
          const SizedBox(height: 12),
          TextField(
            controller: _fatorController,
            keyboardType: TextInputType.number,
            enabled: !calculadoSozinho,
            decoration: InputDecoration(
              labelText: 'Quantas unidades = 1 de "${widget.novoPai.nome}"?',
              helperText: calculadoSozinho
                  ? 'Calculado automaticamente a partir do peso dos dois produtos.'
                  : 'Não deu pra calcular sozinho (peso não cadastrado nos dois, ou não divide em partes '
                      'inteiras) — digite manualmente.',
              errorText: _erro,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final fator = int.tryParse(_fatorController.text.trim());
            if (fator == null || fator < 1) {
              setState(() => _erro = 'Informe um número inteiro maior que zero.');
              return;
            }
            Navigator.pop(context, fator);
          },
          child: const Text('Confirmar troca'),
        ),
      ],
    );
  }
}

class _ConfiguracaoVinculo {
  final int fator;
  final int estoqueFilho;
  final double? margemAlvo;

  const _ConfiguracaoVinculo({required this.fator, required this.estoqueFilho, this.margemAlvo});
}

/// Sugere o fator (quantas unidades = 1 embalagem) pra vincular dois produtos
/// já existentes. Primeiro pelo número escrito na embalagem ("Caixa com 20",
/// "Caixa 20und", "Display 12 unidades") — o caso comum (sachê, petisco) é
/// por QUANTIDADE, e peso não serve (achado real: caixa 1,7kg ÷ sachê 90g =
/// 18,9, porque o peso bruto inclui embalagem). Peso só como 2ª tentativa,
/// pro granel (saco 10kg → pacote 1kg), onde não há número de unidades.
int? sugerirFatorVinculo(Produto pai, Produto filho) {
  final padroes = [
    RegExp(r'\bcom\s+(\d{1,4})\b', caseSensitive: false),
    RegExp(r'\b(\d{1,4})\s*(?:und|unid|unidades|un|sach[eê]s?|pe[cç]as|x)\b', caseSensitive: false),
  ];
  for (final texto in [pai.apresentacao, pai.varianteLabel, pai.nome]) {
    if (texto == null || texto.isEmpty) continue;
    for (final padrao in padroes) {
      final numero = int.tryParse(padrao.firstMatch(texto)?.group(1) ?? '');
      if (numero != null && numero > 1) return numero;
    }
  }
  if (filho.peso != null && filho.peso! > 0) {
    return calcularFatorFracionamento(
      eixo: EixoFracionamento.peso,
      pai: pai,
      pesoNovoTexto: filho.peso.toString(),
    );
  }
  return null;
}

/// Diálogo do "Vincular" — só o que muda num vínculo entre produtos que já
/// existem: fator, estoque REAL da unidade (obrigatório — o estoque da
/// embalagem passa a ser calculado a partir dele, então nunca é deduzido
/// sozinho, ver feedback_nao_inferir_quantidade_fisica_real) e margem alvo
/// opcional. Nome, EAN, preço e rótulo o produto já tem.
class _DialogoVincularExistente extends StatefulWidget {
  final Produto pai;
  final Produto filho;

  const _DialogoVincularExistente({required this.pai, required this.filho});

  @override
  State<_DialogoVincularExistente> createState() => _DialogoVincularExistenteState();
}

class _DialogoVincularExistenteState extends State<_DialogoVincularExistente> {
  late final int? _fatorSugerido = sugerirFatorVinculo(widget.pai, widget.filho);
  late final _fatorController = TextEditingController(text: _fatorSugerido?.toString() ?? '');
  final _estoqueController = TextEditingController();
  final _margemController = TextEditingController();
  String? _erro;

  @override
  void dispose() {
    _fatorController.dispose();
    _estoqueController.dispose();
    _margemController.dispose();
    super.dispose();
  }

  int? get _fator {
    final fator = int.tryParse(_fatorController.text.trim());
    return fator != null && fator > 1 ? fator : null;
  }

  double? get _margem => double.tryParse(_margemController.text.trim().replaceAll(',', '.'));

  void _confirmar() {
    final fator = _fator;
    final estoque = int.tryParse(_estoqueController.text.trim());
    if (fator == null) {
      setState(() => _erro = 'Informe quantas unidades vêm em 1 embalagem (número inteiro maior que 1).');
      return;
    }
    if (estoque == null || estoque < 0) {
      setState(() => _erro = 'Informe quantas unidades existem hoje na loja, contando as das embalagens fechadas.');
      return;
    }
    if (_margemController.text.trim().isNotEmpty && (_margem == null || _margem! < 0)) {
      setState(() => _erro = 'Margem alvo inválida — use só números (ex: 40).');
      return;
    }
    Navigator.of(context).pop(_ConfiguracaoVinculo(fator: fator, estoqueFilho: estoque, margemAlvo: _margem));
  }

  @override
  Widget build(BuildContext context) {
    final pai = widget.pai;
    final filho = widget.filho;
    final fator = _fator;
    final moeda = ProdutoValidators.formatarMoeda;
    final estiloAjuda = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);

    String? resumoCusto;
    if (fator != null) {
      final custoNovo = pai.custo / fator;
      final margem = _margem;
      resumoCusto = 'Custo da unidade: R\$ ${moeda(filho.custo)} → R\$ ${moeda(custoNovo)} (embalagem ÷ $fator). ';
      if (margem != null) {
        resumoCusto += 'Preço passa a ser calculado: R\$ ${moeda(custoNovo * (1 + margem / 100))}.';
      } else if (custoNovo > 0) {
        final margemAtual = (filho.preco / custoNovo - 1) * 100;
        resumoCusto += 'Preço atual R\$ ${moeda(filho.preco)} continua (≈ ${margemAtual.toStringAsFixed(0)}% sobre o custo novo).';
      }
    }

    return AlertDialog(
      title: const Text('Vincular produtos já cadastrados'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Embalagem: ${pai.nome}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Unidade: ${filho.nome}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: _fatorController,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() => _erro = null),
              decoration: InputDecoration(
                labelText: 'Quantas unidades vêm em 1 embalagem?',
                helperText: _fatorSugerido != null
                    ? 'Sugerido pelo cadastro da embalagem — confira.'
                    : 'Não deu pra sugerir sozinho — digite.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _estoqueController,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() => _erro = null),
              decoration: InputDecoration(
                labelText: 'Estoque real da unidade hoje',
                helperText: 'Conte tudo em unidades: embalagens fechadas × ${fator ?? "?"} + avulsas.\n'
                    'No sistema hoje: embalagem = ${pai.estoqueAtual}, unidade = ${filho.estoqueAtual}.',
                helperMaxLines: 3,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _margemController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() => _erro = null),
              decoration: const InputDecoration(
                labelText: 'Margem alvo sobre custo (%, opcional)',
                helperText: 'Preenchida, o preço da unidade se recalcula sozinho quando o custo da embalagem mudar.',
                helperMaxLines: 2,
              ),
            ),
            if (resumoCusto != null) ...[
              const SizedBox(height: 12),
              Text(resumoCusto, style: estiloAjuda),
            ],
            const SizedBox(height: 8),
            Text(
              'Depois de vincular, o estoque da embalagem é calculado a partir da unidade, vender a embalagem '
              'desconta ${fator ?? "N"} unidades, e a entrada de nota da embalagem soma nas unidades.',
              style: estiloAjuda,
            ),
            if (_erro != null) ...[
              const SizedBox(height: 8),
              Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _confirmar, child: const Text('Vincular')),
      ],
    );
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
  /// Preenche o "Cadastro estruturado" — em branco cai no padrão de sempre
  /// (rótulo pra eixo quantidade, apresentação do pai pra eixo peso).
  String? apresentacaoExplicita,
  /// Preço de venda no site — em branco cria com 0, exatamente como antes
  /// (quem não passar nada continua vendo o comportamento de sempre).
  double? preco,
  double? precoIfood,
}) {
  final pesoNovo = eixo == EixoFracionamento.peso
      ? pesoNovoExplicito
      : (pai.peso != null ? pai.peso! / fator : null);

  return Produto(
    nome: pai.nome, // provisório — o trigger do banco recompõe a partir dos campos estruturados, se houver
    preco: preco ?? 0,
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
    apresentacao: apresentacaoExplicita ?? (eixo == EixoFracionamento.quantidade ? rotulo : pai.apresentacao),
    nomeManualOverride: pai.nomeManualOverride,
    produtoPaiId: pai.produtoPaiId ?? pai.id,
    tipoVariacao: eixo == EixoFracionamento.peso ? 'peso' : 'quantidade',
    varianteLabel: rotulo,
    cicloRecompraDias: pai.cicloRecompraDias,
    fracionadoDeId: pai.id,
    fatorFracionamento: fator,
    margemAlvoFracionado: margemAlvoFracionado,
    precoIfood: precoIfood,
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
  final _apresentacaoController = TextEditingController();
  final _codigoBarrasController = TextEditingController();
  final _estoqueController = TextEditingController();
  final _margemController = TextEditingController();
  final _precoController = TextEditingController();
  final _precoIfoodController = TextEditingController();
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
    _apresentacaoController.dispose();
    _codigoBarrasController.dispose();
    _estoqueController.dispose();
    _margemController.dispose();
    _precoController.dispose();
    _precoIfoodController.dispose();
    super.dispose();
  }

  // Mesmo comportamento da criação em massa: com margem preenchida, o
  // trigger do banco `aplicar_margem_fracionado_na_criacao` sempre recalcula
  // o preço a partir dela ao criar, ignorando qualquer preço que o app
  // mande — por isso o campo fica travado mostrando o valor real que vai
  // ser salvo. Sem margem, volta a ser 100% manual.
  void _sincronizarPrecoComMargem(int? fator) {
    if (_margemController.text.trim().isEmpty) return;
    final sugestao = _precoSugerido(fator);
    if (sugestao != null) {
      _precoController.text = ProdutoValidators.formatarMoeda(sugestao);
    }
  }

  double? _precoSugerido(int? fator) {
    if (fator == null) return null;
    final margem = double.tryParse(_margemController.text.trim().replaceAll(',', '.'));
    if (margem == null) return null;
    return (widget.produtoPai.custo / fator) * (1 + margem / 100);
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
    final erroPreco = ProdutoValidators.precoVenda(_precoController.text);
    if (_precoController.text.trim().isNotEmpty && erroPreco != null) {
      setState(() => _erro = erroPreco);
      return;
    }

    final apresentacaoTexto = _apresentacaoController.text.trim();
    final filho = construirProdutoFracionado(
      pai: widget.produtoPai,
      eixo: _eixo,
      fator: fator,
      rotulo: rotulo,
      codigoBarras: _codigoBarrasController.text,
      pesoNovoExplicito: double.tryParse(_pesoNovoController.text.trim().replaceAll(',', '.')),
      estoqueInicial: int.tryParse(_estoqueController.text.trim()),
      margemAlvoFracionado: margem,
      apresentacaoExplicita: apresentacaoTexto.isEmpty ? null : apresentacaoTexto,
      preco: ProdutoValidators.parseNumero(_precoController.text),
      precoIfood: ProdutoValidators.parseNumero(_precoIfoodController.text),
    );

    Navigator.of(context).pop(filho);
  }

  @override
  Widget build(BuildContext context) {
    final pesoPai = widget.produtoPai.peso;
    final fator = _fatorCalculado;
    _sincronizarPrecoComMargem(fator);
    final sugestaoEstoque = fator != null ? widget.produtoPai.estoqueAtual * fator : null;
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
                Text('Peso do original: ${formatarPeso(pesoPai)}'),
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
              controller: _apresentacaoController,
              decoration: const InputDecoration(
                labelText: 'Apresentação (opcional)',
                helperText: 'Ex: "Pote", "Sachê", "Caixa". Em branco: repete a do produto original.',
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
              controller: _estoqueController,
              keyboardType: TextInputType.number,
              inputFormatters: [DigitosInputFormatter()],
              decoration: InputDecoration(
                labelText: 'Estoque inicial (opcional)',
                helperText: sugestaoEstoque != null
                    ? 'Em branco usa a sugestão: $sugestaoEstoque (pai atual × fator)'
                    : 'Em branco usa pai.estoqueAtual × fator',
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
            const SizedBox(height: 12),
            TextField(
              controller: _precoController,
              enabled: _margemController.text.trim().isEmpty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [MoedaInputFormatter()],
              decoration: InputDecoration(
                labelText: 'Preço de venda (R\$, opcional)',
                helperText: _margemController.text.trim().isNotEmpty
                    ? 'Controlado pela margem acima — o banco recalcula sozinho ao criar.'
                    : 'Em branco: cria com R\$0 pra configurar depois.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _precoIfoodController,
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
                  'Fator: 1 unidade do original = $fator deste. '
                  'Estoque inicial sugerido: ${widget.produtoPai.estoqueAtual * fator}.'
                  '${_previewMargem(fator)}',
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
