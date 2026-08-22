import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/vinculo_cliente.dart';
import '../repositories/vinculo_cliente_repository.dart';

/// Fila de possíveis mesmas-pessoas detectadas por CPF/CNPJ entre canais
/// diferentes (site/WhatsApp/iFood/99Food/loja física) — staff confirma
/// ou rejeita, nunca acontece automático (ver `VinculoCliente`).
class VinculosClientesScreen extends StatefulWidget {
  const VinculosClientesScreen({super.key});

  @override
  State<VinculosClientesScreen> createState() => _VinculosClientesScreenState();
}

class _VinculosClientesScreenState extends State<VinculosClientesScreen> {
  final _repository = VinculoClienteRepository();
  late Future<List<VinculoCliente>> _futureVinculos;
  final Set<String> _emProcessamento = {};

  @override
  void initState() {
    super.initState();
    _futureVinculos = _repository.listarPendentes();
  }

  Future<void> _recarregar() async {
    setState(() => _futureVinculos = _repository.listarPendentes());
    await _futureVinculos;
  }

  Future<void> _confirmarEAgir(VinculoCliente vinculo, {required bool aprovar}) async {
    final valorEmRisco = vinculo.saldoEncontrado > 0 || vinculo.saldoPetCashEncontrado > 0;
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(aprovar ? 'Vincular cadastros?' : 'Rejeitar sugestão?'),
        content: Text(
          aprovar
              ? '"${vinculo.nomeNovo}" (novo, ${vinculo.canalNovo ?? "?"}) será vinculado a '
                  '"${vinculo.nomeEncontrado}" (${vinculo.canalEncontrado ?? "?"}, '
                  '${vinculo.totalPedidosEncontrado} pedido(s)'
                  '${valorEmRisco ? ", saldo ${currencyFormat.format(vinculo.saldoEncontrado)} + PetCash ${currencyFormat.format(vinculo.saldoPetCashEncontrado)}" : ""}).\n\n'
                  'O histórico consolidado passa a aparecer na ficha de ambos.'
              : 'A sugestão será descartada — os 2 cadastros continuam separados.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(aprovar ? 'Vincular' : 'Rejeitar')),
        ],
      ),
    );

    if (confirmou != true) return;

    setState(() => _emProcessamento.add(vinculo.id));
    try {
      if (aprovar) {
        await _repository.aprovar(vinculo.id);
      } else {
        await _repository.rejeitar(vinculo.id);
      }
      await _recarregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) setState(() => _emProcessamento.remove(vinculo.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Scaffold(
      appBar: AppBar(title: const Text('Vínculos de Clientes')),
      body: FutureBuilder<List<VinculoCliente>>(
        future: _futureVinculos,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro ao carregar vínculos: ${snapshot.error}'));
          }

          final vinculos = snapshot.data ?? [];
          if (vinculos.isEmpty) {
            return RefreshIndicator(
              onRefresh: _recarregar,
              child: ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('Nenhum vínculo pendente de revisão.')),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _recarregar,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: vinculos.length,
              itemBuilder: (context, index) {
                final vinculo = vinculos[index];
                final processando = _emProcessamento.contains(vinculo.id);
                final valorEmRisco = vinculo.saldoEncontrado > 0 || vinculo.saldoPetCashEncontrado > 0;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bateu por ${vinculo.criterio.toUpperCase()} • ${dateFormat.format(vinculo.criadoEm)}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(height: 8),
                        Text('Novo: ${vinculo.nomeNovo} (${vinculo.canalNovo ?? "?"}) — ${vinculo.telefoneNovo}'),
                        Text(
                          'Encontrado: ${vinculo.nomeEncontrado} (${vinculo.canalEncontrado ?? "?"}) — '
                          '${vinculo.telefoneEncontrado} — ${vinculo.totalPedidosEncontrado} pedido(s)',
                        ),
                        if (valorEmRisco)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Saldo: ${currencyFormat.format(vinculo.saldoEncontrado)} • '
                              'PetCash: ${currencyFormat.format(vinculo.saldoPetCashEncontrado)}',
                              style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.bold),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: processando ? null : () => _confirmarEAgir(vinculo, aprovar: false),
                              child: const Text('Rejeitar'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: processando ? null : () => _confirmarEAgir(vinculo, aprovar: true),
                              child: processando
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Text('Vincular'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
