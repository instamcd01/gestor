import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  // Estado da última sincronização com a API do marketplace (preenchido pelo
  // n8n depois de cada tentativa) — só pra exibição, não é editado aqui.
  final Map<String, Map<String, dynamic>> _statusSincronizacao = {};
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
        if (existente != null && existente['ultima_sincronizacao_em'] != null) {
          _statusSincronizacao[marketplace.id] = {
            'status': existente['sincronizacao_status'] as String?,
            'em': DateTime.tryParse(existente['ultima_sincronizacao_em'] as String? ?? ''),
            'erro': existente['sincronizacao_erro'] as String?,
          };
        }
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

  /// Linha pequena abaixo do canal mostrando se a última tentativa de
  /// sincronizar esse produto com a API do marketplace deu certo, falhou, ou
  /// ainda nunca rodou. Preenchido pelo n8n depois de cada mudança de preço
  /// ou estoque — aqui só lemos e mostramos, não editamos.
  Widget _statusSincronizacaoWidget(String marketplaceId) {
    final info = _statusSincronizacao[marketplaceId];
    if (info == null) {
      return Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 6),
        child: Row(
          children: [
            Icon(Icons.schedule, size: 14, color: Colors.grey[500]),
            const SizedBox(width: 4),
            Text(
              'Ainda não sincronizado com a plataforma',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    final status = info['status'] as String?;
    final em = info['em'] as DateTime?;
    final erro = info['erro'] as String?;
    final sucesso = status == 'sucesso';

    final horario = em != null ? DateFormat('dd/MM HH:mm').format(em.toLocal()) : '';

    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 6),
      child: InkWell(
        onTap: sucesso ? null : () => _mostrarDetalheErro(erro),
        child: Row(
          children: [
            Icon(
              sucesso ? Icons.check_circle : Icons.error_outline,
              size: 14,
              color: sucesso ? Colors.green[700] : Colors.red[700],
            ),
            const SizedBox(width: 4),
            Text(
              sucesso ? 'Sincronizado às $horario' : 'Falha ao sincronizar às $horario — toque para detalhes',
              style: TextStyle(
                fontSize: 12,
                color: sucesso ? Colors.green[700] : Colors.red[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDetalheErro(String? erro) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Falha ao sincronizar'),
        content: Text(erro ?? 'A plataforma não informou o motivo da falha.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
        ],
      ),
    );
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                if (disponivel) _statusSincronizacaoWidget(marketplace.id),
              ],
            ),
          );
        }),
      ],
    );
  }
}
