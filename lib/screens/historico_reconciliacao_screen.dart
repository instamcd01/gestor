import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/reconciliacao_historico.dart';
import '../repositories/reconciliacao_historico_repository.dart';

/// Histórico permanente de reconciliação de estoque/financeiro e exportação
/// de catálogo pra um marketplace — aberto a partir da tela dedicada da
/// plataforma (ex: Integração iFood).
class HistoricoReconciliacaoScreen extends StatefulWidget {
  final String marketplaceId;
  final String nomeMarketplace;

  const HistoricoReconciliacaoScreen({super.key, required this.marketplaceId, required this.nomeMarketplace});

  @override
  State<HistoricoReconciliacaoScreen> createState() => _HistoricoReconciliacaoScreenState();
}

class _HistoricoReconciliacaoScreenState extends State<HistoricoReconciliacaoScreen> {
  final _repository = ReconciliacaoHistoricoRepository();
  List<ReconciliacaoHistorico> _historico = [];
  bool _carregando = true;
  String? _erro;

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
      final historico = await _repository.listar(widget.marketplaceId);
      if (mounted) setState(() => _historico = historico);
    } catch (e) {
      if (mounted) setState(() => _erro = 'Não foi possível carregar o histórico.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  (IconData, Color) _iconeECor(String tipo) {
    switch (tipo) {
      case TipoReconciliacaoHistorico.estoque:
        return (Icons.inventory_2_outlined, Colors.blue);
      case TipoReconciliacaoHistorico.financeiro:
        return (Icons.attach_money, Colors.green);
      case TipoReconciliacaoHistorico.catalogoExportado:
        return (Icons.storefront_outlined, Colors.deepOrange);
      default:
        return (Icons.history, Colors.grey);
    }
  }

  String _rotuloTipo(String tipo) {
    switch (tipo) {
      case TipoReconciliacaoHistorico.estoque:
        return 'Baixa de estoque';
      case TipoReconciliacaoHistorico.financeiro:
        return 'Fechamento financeiro';
      case TipoReconciliacaoHistorico.catalogoExportado:
        return 'Catálogo exportado';
      default:
        return tipo;
    }
  }

  String _rotuloMotivoExclusao(String? motivo) {
    switch (motivo) {
      case 'sem_ean':
        return 'Sem código de barras';
      case 'ean_zero':
        return 'Código de barras inválido (placeholder "0")';
      case 'sem_preco':
        return 'Sem preço válido';
      default:
        return 'Fora do catálogo';
    }
  }

  /// Lista de produto/item por trás de um card — mesmo formato pra "itens
  /// não catalogados" (baixa de estoque) e "produtos excluídos" (catálogo
  /// exportado), cada um com sua própria chave de nome/subtítulo.
  void _abrirLista({
    required String titulo,
    required List<dynamic> itens,
    required String Function(Map<String, dynamic>) nome,
    required String Function(Map<String, dynamic>) subtitulo,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                itemCount: itens.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = Map<String, dynamic>.from(itens[index] as Map);
                  return ListTile(
                    title: Text(nome(item)),
                    subtitle: Text(subtitulo(item)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(title: Text('Histórico — ${widget.nomeMarketplace}')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(child: Text(_erro!))
              : _historico.isEmpty
                  ? Center(
                      child: Text(
                        'Nenhuma reconciliação registrada ainda.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _carregar,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _historico.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = _historico[index];
                          final (icone, cor) = _iconeECor(item.tipo);

                          // Baixa de estoque: itens do relatório que não bateram com
                          // nenhum produto cadastrado (EAN sem match).
                          final itensNaoCatalogados =
                              item.detalhes['itens_nao_catalogados_detalhe'] as List<dynamic>?;
                          // Catálogo exportado: produtos que ficaram de fora (sem EAN
                          // válido ou sem preço).
                          final produtosExcluidos = item.detalhes['produtos_excluidos'] as List<dynamic>?;

                          VoidCallback? onTap;
                          String? resumoExtra;
                          if (itensNaoCatalogados != null && itensNaoCatalogados.isNotEmpty) {
                            resumoExtra = '${itensNaoCatalogados.length} item(ns) não catalogado(s) — toque pra ver';
                            onTap = () => _abrirLista(
                                  titulo: 'Itens não catalogados',
                                  itens: itensNaoCatalogados,
                                  nome: (i) => (i['nome_relatorio'] as String?) ?? 'Sem nome no relatório',
                                  subtitulo: (i) =>
                                      'EAN ${i['ean'] ?? '—'} · Qtd. ${i['quantidade'] ?? '—'}',
                                );
                          } else if (produtosExcluidos != null && produtosExcluidos.isNotEmpty) {
                            resumoExtra = '${produtosExcluidos.length} produto(s) fora do catálogo — toque pra ver';
                            onTap = () => _abrirLista(
                                  titulo: 'Produtos fora do catálogo',
                                  itens: produtosExcluidos,
                                  nome: (i) => (i['nome'] as String?) ?? 'Produto',
                                  subtitulo: (i) => _rotuloMotivoExclusao(i['motivo'] as String?),
                                );
                          }

                          return Card(
                            margin: EdgeInsets.zero,
                            child: ListTile(
                              leading: Icon(icone, color: cor),
                              title: Text(_rotuloTipo(item.tipo), style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.mensagem),
                                  if (resumoExtra != null)
                                    Text(
                                      resumoExtra,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                  Text(
                                    dateFormat.format(item.executadoEm),
                                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: onTap != null ? const Icon(Icons.chevron_right) : null,
                              onTap: onTap,
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
