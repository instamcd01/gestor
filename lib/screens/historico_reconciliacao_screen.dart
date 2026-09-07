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
                          return Card(
                            margin: EdgeInsets.zero,
                            child: ListTile(
                              leading: Icon(icone, color: cor),
                              title: Text(_rotuloTipo(item.tipo), style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.mensagem),
                                  Text(
                                    dateFormat.format(item.executadoEm),
                                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
