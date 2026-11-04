import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/produto.dart';
import '../providers/produto_provider.dart';
import '../utils/formatadores_input.dart';
import '../utils/produto_validators.dart';
import 'canais_marketplace_section.dart';
import 'motivo_ajuste_estoque_dialog.dart';

/// Edição rápida do produto no painel ao lado da tabela (Gestor no PC):
/// só o que se mexe no dia a dia — preço, promoção, estoque, custo, código
/// de barras e onde está à venda. O resto fica na "Ficha completa" (a tela
/// de edição de sempre).
///
/// Mesmas regras da ficha completa, sem copiar nada:
/// - estoque passa pelo `ajustar_estoque` com motivo e trava (se vendeu
///   com a tela aberta, recusa em vez de sobrescrever);
/// - canais usam o próprio [CanaisMarketplaceSection] (preço por canal e
///   situação da sincronização);
/// - o cadastro grava SÓ os campos deste painel, nunca o produto inteiro
///   da memória (não desfaz o que outra tela mudou nesse meio-tempo).
class ProdutoEdicaoRapida extends StatefulWidget {
  final Produto produto;
  final VoidCallback onAbrirFicha;

  /// Depois de salvar (pra a tela recarregar os canais da tabela).
  final VoidCallback onSalvo;

  /// true enquanto há alteração não salva — a tela consulta antes de trocar
  /// de produto, pra perguntar em vez de perder o que foi digitado.
  final ValueNotifier<bool> temAlteracoes;

  const ProdutoEdicaoRapida({
    super.key,
    required this.produto,
    required this.onAbrirFicha,
    required this.onSalvo,
    required this.temAlteracoes,
  });

  @override
  State<ProdutoEdicaoRapida> createState() => _ProdutoEdicaoRapidaState();
}

class _ProdutoEdicaoRapidaState extends State<ProdutoEdicaoRapida> {
  final _formKey = GlobalKey<FormState>();
  final _canaisKey = GlobalKey<CanaisMarketplaceSectionState>();
  late final _preco = TextEditingController(text: ProdutoValidators.formatarMoeda(widget.produto.preco));
  late final _promocional =
      TextEditingController(text: ProdutoValidators.formatarMoeda(widget.produto.precoPromocional));
  late final _custo = TextEditingController(text: ProdutoValidators.formatarMoeda(widget.produto.custo));
  late final _estoque = TextEditingController(text: '${widget.produto.estoqueAtual}');
  late final _codigoBarras = TextEditingController(text: widget.produto.codigoBarras);
  late bool _site = widget.produto.exibirNoCatalogo;
  late int _estoqueBase = widget.produto.estoqueAtual;
  bool _salvando = false;
  late final Map<TextEditingController, String> _textoInicial = {
    for (final c in [_preco, _promocional, _custo, _estoque, _codigoBarras]) c: c.text,
  };

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_atalho);
    widget.temAlteracoes.value = false;
    for (final c in _textoInicial.keys) {
      c.addListener(_conferirAlteracoes);
    }
  }

  /// Compara com o que abriu (não só "digitou algo"): apagar e redigitar o
  /// mesmo valor não conta como alteração.
  void _conferirAlteracoes() {
    final alterado = _textoInicial.entries.any((e) => e.key.text != e.value) ||
        _site != widget.produto.exibirNoCatalogo ||
        (_canaisKey.currentState?.alterado ?? false);
    if (alterado != widget.temAlteracoes.value && mounted) {
      setState(() => widget.temAlteracoes.value = alterado);
    }
  }

  /// Ctrl+S salva. Ouvinte global (enquanto o painel está aberto) porque no
  /// navegador o campo de texto em foco segura o atalho e ele nunca chegaria
  /// num `CallbackShortcuts` acima; devolver true também impede o "Salvar
  /// página" do navegador.
  bool _atalho(KeyEvent evento) {
    if (evento is! KeyDownEvent || evento.logicalKey != LogicalKeyboardKey.keyS) return false;
    if (!HardwareKeyboard.instance.isControlPressed && !HardwareKeyboard.instance.isMetaPressed) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    // Guardada por trás de outra seção do menu lateral (ver
    // SidebarHomeShell): o atalho não pode salvar o que não está à vista.
    if (!TickerMode.valuesOf(context).enabled) return false;
    _salvar();
    return true;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_atalho);
    for (final c in [_preco, _promocional, _custo, _estoque, _codigoBarras]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_salvando || !_formKey.currentState!.validate()) return;
    final produto = widget.produto;
    final provider = context.read<ProdutoProvider>();
    final mensageiro = ScaffoldMessenger.of(context);

    final estoqueDigitado = int.tryParse(_estoque.text.trim());
    final mudouEstoque = estoqueDigitado != null && estoqueDigitado != _estoqueBase;
    ({String motivo, String? observacao})? ajuste;
    if (mudouEstoque) {
      ajuste = await perguntarMotivoAjusteEstoque(
        context,
        nomeProduto: produto.nome,
        de: _estoqueBase,
        para: estoqueDigitado,
      );
      if (ajuste == null || !mounted) return;
    }

    setState(() => _salvando = true);
    try {
      if (mudouEstoque) {
        try {
          await provider.ajustarEstoque(
            produtoId: produto.id!,
            quantidadeNova: estoqueDigitado,
            motivo: ajuste!.motivo,
            observacao: ajuste.observacao,
            quantidadeEsperada: _estoqueBase,
          );
          _estoqueBase = estoqueDigitado;
        } catch (e) {
          final real = provider.getProdutoPorId(produto.id!)?.estoqueAtual;
          mensageiro.showSnackBar(SnackBar(
            duration: const Duration(seconds: 6),
            content: Text(real != null && real != _estoqueBase
                ? 'O estoque mudou para $real enquanto o painel estava aberto (venda ou entrada). '
                    'Confira e salve de novo — nada foi alterado.'
                : 'Erro ao ajustar estoque: $e'),
          ));
          return;
        }
      }

      final preco = ProdutoValidators.parseNumero(_preco.text)!;
      final campos = <String, dynamic>{
        'preco': preco,
        'preco_promocional': ProdutoValidators.parseNumero(_promocional.text),
        'custo': ProdutoValidators.parseNumero(_custo.text) ?? produto.custo,
        'codigo_barras': _codigoBarras.text.trim(),
        if (_site != produto.exibirNoCatalogo) 'exibir_no_catalogo': _site,
      };
      await provider.atualizarCampos(produto.id!, campos);
      await _canaisKey.currentState?.salvar(produto.id!, preco);
      mensageiro.showSnackBar(const SnackBar(content: Text('Produto salvo.')));
      widget.temAlteracoes.value = false;
      widget.onSalvo();
    } catch (e) {
      mensageiro.showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final produto = widget.produto;
    final cores = Theme.of(context).colorScheme;
    final apagado = TextStyle(fontSize: 12, color: cores.onSurfaceVariant);

    Widget titulo(String texto) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(texto.toUpperCase(),
              style: TextStyle(
                  fontSize: 11, letterSpacing: 0.5, fontWeight: FontWeight.w600, color: cores.onSurfaceVariant)),
        );

    InputDecoration campo(String rotulo, {String? prefixo, String? ajuda}) => InputDecoration(
          labelText: rotulo,
          prefixText: prefixo,
          helperText: ajuda,
          isDense: true,
        );

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 64,
                        height: 64,
                        color: cores.surfaceContainerHighest,
                        child: produto.imagemUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: produto.imagemUrlExibicao,
                                fit: BoxFit.cover,
                                memCacheWidth: 160,
                                errorWidget: (_, __, ___) =>
                                    Icon(Icons.inventory_2_outlined, color: cores.onSurfaceVariant),
                              )
                            : Icon(Icons.inventory_2_outlined, color: cores.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(produto.nome,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.25)),
                          const SizedBox(height: 4),
                          Text(
                            [
                              produto.categoria.isNotEmpty ? produto.categoria : 'Sem categoria',
                              if (!produto.ativo) 'inativo',
                            ].join(' · '),
                            style: apagado,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                titulo('Preço'),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _preco,
                        decoration: campo('Preço de venda', prefixo: 'R\$ ', ajuda: 'Site, app e balcão'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [MoedaInputFormatter()],
                        validator: ProdutoValidators.precoVenda,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _promocional,
                        decoration: campo('Preço promocional', prefixo: 'R\$ ', ajuda: 'Vazio = sem promoção'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [MoedaInputFormatter()],
                        validator: (v) => ProdutoValidators.precoPromocional(v, _preco.text),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _custo,
                        decoration: campo('Custo', prefixo: 'R\$ '),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [MoedaInputFormatter()],
                        validator: ProdutoValidators.custo,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _estoque,
                        decoration: campo('Estoque', ajuda: 'Mudou? pede o motivo'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [InteiroInputFormatter()],
                        validator: (v) => ProdutoValidators.estoqueInteiro(v, campo: 'o estoque'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _codigoBarras,
                  decoration: campo('Código de barras'),
                  keyboardType: TextInputType.number,
                  validator: ProdutoValidators.codigoBarras,
                ),
                titulo('Onde está à venda'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Site e app da loja'),
                  subtitle: Text(
                    !produto.ativo
                        ? 'Produto inativo: não aparece em lugar nenhum'
                        : _site
                            ? 'Aparece no catálogo online'
                            : 'Oculto do catálogo online',
                    style: apagado,
                  ),
                  value: _site,
                  onChanged: (v) {
                    setState(() => _site = v);
                    _conferirAlteracoes();
                  },
                ),
                CanaisMarketplaceSection(
                  key: _canaisKey,
                  produtoId: produto.id,
                  compacto: true,
                  onAlterado: _conferirAlteracoes,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (widget.temAlteracoes.value)
            Container(
              width: double.infinity,
              color: cores.tertiaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.edit_note, size: 18, color: cores.onTertiaryContainer),
                  const SizedBox(width: 8),
                  Text('Alterações não salvas', style: TextStyle(fontSize: 13, color: cores.onTertiaryContainer)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _salvando ? null : _salvar,
                    child: _salvando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Salvar  ·  Ctrl S'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: widget.onAbrirFicha,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Ficha completa'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
