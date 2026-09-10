import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/item_carrinho_cliente.dart';
import '../providers/carrinho_provider.dart';
import '../providers/cliente_provider.dart';
import '../providers/produto_provider.dart';
import '../repositories/carrinho_cliente_repository.dart';
import 'carrinho_screen.dart';

/// Lista os carrinhos ativos/não vazios de hoje (compartilhados com
/// WhatsApp/site, ou salvos por um vendedor via o botão "Salvar" em
/// `CarrinhoScreen`) — acessível de `VendasScreen`, pra retomar o
/// atendimento de um cliente específico sem montar tudo de novo.
class CarrinhosDoDiaScreen extends StatefulWidget {
  const CarrinhosDoDiaScreen({super.key});

  @override
  State<CarrinhosDoDiaScreen> createState() => _CarrinhosDoDiaScreenState();
}

class _CarrinhosDoDiaScreenState extends State<CarrinhosDoDiaScreen> {
  late Future<List<CarrinhoAtivoResumo>> _futureCarrinhos;
  final Set<String> _abrindoClienteIds = {};

  @override
  void initState() {
    super.initState();
    _futureCarrinhos = CarrinhoClienteRepository().listarAtivosHoje();
  }

  Future<void> _abrir(CarrinhoAtivoResumo resumo) async {
    final carrinhoProvider = context.read<CarrinhoProvider>();

    // Já tem outro cliente sendo montado sem salvar — avisa antes de
    // descartar, nunca perde trabalho em andamento silenciosamente.
    if (carrinhoProvider.itens.isNotEmpty &&
        carrinhoProvider.clienteSelecionado?.idCliente != resumo.clienteId) {
      final confirmou = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Descartar carrinho em andamento?'),
          content: Text(
            'Você tem um carrinho não salvo pra outro cliente. Abrir o de ${resumo.clienteNome} '
            'descarta o que está montado agora — volte e toque em "Salvar" antes, se quiser manter.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Descartar e abrir')),
          ],
        ),
      );
      if (confirmou != true || !mounted) return;
    }

    setState(() => _abrindoClienteIds.add(resumo.clienteId));
    try {
      final cliente = context
          .read<ClientProvider>()
          .clientes
          .where((c) => c.idCliente == resumo.clienteId)
          .firstOrNull;
      if (cliente == null) {
        throw Exception('Cliente não encontrado na lista carregada — recarregue a tela de Clientes e tente de novo.');
      }
      final carrinhoCliente = await CarrinhoClienteRepository().consultar(resumo.clienteId);
      if (!mounted) return;

      carrinhoProvider.limparCarrinho();
      carrinhoProvider.selecionarCliente(cliente);
      final catalogo = context.read<ProdutoProvider>().produtos;
      final ignorados = carrinhoProvider.mesclarItensRemotos(catalogo, carrinhoCliente.itens);

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const CarrinhoScreen(idVenda: '')),
      );
      if (ignorados.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${ignorados.length} item(ns) não puderam ser trazidos: ${ignorados.join(", ")}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível abrir: $e')));
      }
    } finally {
      if (mounted) setState(() => _abrindoClienteIds.remove(resumo.clienteId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Carrinhos do dia')),
      body: FutureBuilder<List<CarrinhoAtivoResumo>>(
        future: _futureCarrinhos,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro ao carregar: ${snapshot.error}'));
          }
          final carrinhos = snapshot.data ?? [];
          if (carrinhos.isEmpty) {
            return const Center(child: Text('Nenhum carrinho em aberto hoje.'));
          }
          return ListView.separated(
            itemCount: carrinhos.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final resumo = carrinhos[i];
              final abrindo = _abrindoClienteIds.contains(resumo.clienteId);
              return ListTile(
                leading: const Icon(Icons.shopping_bag_outlined),
                title: Text(resumo.clienteNome),
                subtitle: Text('${resumo.quantidadeItens} item(ns) • R\$ ${resumo.valorTotal.toStringAsFixed(2)}'),
                trailing: abrindo
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.chevron_right),
                onTap: abrindo ? null : () => _abrir(resumo),
              );
            },
          );
        },
      ),
    );
  }
}
