import 'package:flutter/material.dart';

import '../models/marketplace.dart';
import '../repositories/marketplace_repository.dart';
import '../repositories/produto_canal_repository.dart';
import '../utils/formatadores_input.dart';
import '../utils/produto_validators.dart';

/// Seção de formulário pra escolher em quais marketplaces (iFood, 99Food,
/// Rappi, ...) um produto fica disponível, com preço específico opcional
/// por canal. Usado tanto no cadastro quanto na edição de produto.
///
/// Como o produto pode ainda não ter [produtoId] no momento do cadastro,
/// a gravação em `produto_canal` não acontece sozinha: a tela pai chama
/// [CanaisMarketplaceSectionState.salvar] depois de salvar o produto em si
/// e já ter um id definitivo.
class CanaisMarketplaceSection extends StatefulWidget {
  final String? produtoId;

  const CanaisMarketplaceSection({super.key, this.produtoId});

  @override
  State<CanaisMarketplaceSection> createState() => CanaisMarketplaceSectionState();
}

class CanaisMarketplaceSectionState extends State<CanaisMarketplaceSection> {
  final _marketplaceRepository = MarketplaceRepository();
  final _produtoCanalRepository = ProdutoCanalRepository();

  List<Marketplace> _marketplaces = [];
  final Map<String, bool> _disponivel = {};
  final Map<String, TextEditingController> _precoControllers = {};
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final marketplaces = await _marketplaceRepository.listarAtivos();

      final canaisExistentes = <String, Map<String, dynamic>>{};
      if (widget.produtoId != null) {
        final canais = await _produtoCanalRepository.listarPorProduto(widget.produtoId!);
        for (final canal in canais) {
          canaisExistentes[canal['marketplace_id'] as String] = canal;
        }
      }

      for (final marketplace in marketplaces) {
        final existente = canaisExistentes[marketplace.id];
        _disponivel[marketplace.id] = existente?['disponivel'] as bool? ?? false;
        _precoControllers[marketplace.id] = TextEditingController(
          text: ProdutoValidators.formatarMoeda(
              (existente?['preco'] as num?)?.toDouble()),
        );
      }

      if (mounted) {
        setState(() {
          _marketplaces = marketplaces;
          _carregando = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar marketplaces: $e');
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// Grava a disponibilidade/preço escolhidos em `produto_canal`.
  /// Chamado pela tela pai depois que o produto já tem um [produtoId] salvo.
  Future<void> salvar(String produtoId, double precoPadrao) async {
    for (final marketplace in _marketplaces) {
      final preco = ProdutoValidators.parseNumero(_precoControllers[marketplace.id]?.text) ??
          precoPadrao;

      await _produtoCanalRepository.salvar(
        produtoId: produtoId,
        marketplaceId: marketplace.id,
        preco: preco,
        disponivel: _disponivel[marketplace.id] ?? false,
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _precoControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_marketplaces.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Disponibilidade em Marketplaces',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Ative os canais em que este produto deve aparecer. Deixe o preço em branco pra usar o preço de venda padrão.',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 8),
        ..._marketplaces.map((marketplace) {
          final disponivel = _disponivel[marketplace.id] ?? false;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 3,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(marketplace.nome),
                    value: disponivel,
                    onChanged: (value) => setState(() => _disponivel[marketplace.id] = value),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _precoControllers[marketplace.id],
                    enabled: disponivel,
                    decoration: const InputDecoration(
                      labelText: 'Preço',
                      prefixText: 'R\$ ',
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [MoedaInputFormatter()],
                    validator: disponivel ? ProdutoValidators.precoOpcional : null,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
