import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/sugestao_produto_cliente.dart';
import '../repositories/sugestao_produto_cliente_repository.dart';
import '../widgets/estado_erro_lista.dart';

const Map<String, (String, IconData, Color)> _statusInfo = {
  'pendente': ('Pendente', Icons.schedule, Colors.orange),
  'avaliado': ('Avaliado', Icons.visibility_outlined, Colors.blue),
  'comprado': ('Incluído no pedido', Icons.check_circle_outline, Colors.green),
};

const List<String> _cicloStatus = ['pendente', 'avaliado', 'comprado'];

/// Produtos que clientes procuraram no site e não acharam — enviados via
/// `enviar_sugestao_produto_cliente` (RPC, aceita envio anônimo) quando a
/// busca não retorna nada. Cada linha soma quantas vezes o mesmo termo
/// (normalizado) já apareceu, pra ajudar a priorizar o que vale a pena
/// incluir no próximo pedido a fornecedor.
class SugestoesProdutoClienteScreen extends StatefulWidget {
  const SugestoesProdutoClienteScreen({super.key});

  @override
  State<SugestoesProdutoClienteScreen> createState() => _SugestoesProdutoClienteScreenState();
}

class _SugestoesProdutoClienteScreenState extends State<SugestoesProdutoClienteScreen> {
  final _repository = SugestaoProdutoClienteRepository();
  List<SugestaoProdutoCliente> _sugestoes = [];
  bool _carregando = true;
  String? _erro;
  bool _mostrarSoPendentes = true;

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
      final sugestoes = await _repository.listar();
      if (!mounted) return;
      setState(() {
        _sugestoes = sugestoes;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao carregar sugestões: $e';
        _carregando = false;
      });
    }
  }

  Future<void> _avancarStatus(SugestaoProdutoCliente s) async {
    final indiceAtual = _cicloStatus.indexOf(s.status);
    final novoStatus = _cicloStatus[(indiceAtual + 1) % _cicloStatus.length];

    final indice = _sugestoes.indexWhere((x) => x.id == s.id);
    setState(() {
      _sugestoes[indice] = SugestaoProdutoCliente(
        id: s.id,
        termoBuscado: s.termoBuscado,
        mensagem: s.mensagem,
        contato: s.contato,
        status: novoStatus,
        createdAt: s.createdAt,
        avaliadoEm: novoStatus == 'pendente' ? null : DateTime.now(),
        clienteNome: s.clienteNome,
        clienteTelefone: s.clienteTelefone,
      );
    });

    try {
      await _repository.marcarStatus(s.id, novoStatus);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível atualizar: $e')),
      );
      _carregar();
    }
  }

  /// Quantas vezes esse termo (sem acento/maiúscula) já apareceu no total
  /// carregado — ajuda a notar "3 pessoas pediram isso" de relance.
  Map<String, int> get _contagemPorTermo {
    final contagem = <String, int>{};
    for (final s in _sugestoes) {
      final chave = s.termoBuscado.trim().toLowerCase();
      contagem[chave] = (contagem[chave] ?? 0) + 1;
    }
    return contagem;
  }

  @override
  Widget build(BuildContext context) {
    final visiveis =
        _mostrarSoPendentes ? _sugestoes.where((s) => s.pendente).toList() : _sugestoes;
    final contagem = _contagemPorTermo;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sugestões de Clientes'),
        actions: [
          IconButton(
            icon: Icon(_mostrarSoPendentes ? Icons.filter_alt : Icons.filter_alt_off_outlined),
            tooltip: _mostrarSoPendentes ? 'Mostrando só pendentes — toque pra ver tudo' : 'Mostrando tudo — toque pra ver só pendentes',
            onPressed: () => setState(() => _mostrarSoPendentes = !_mostrarSoPendentes),
          ),
        ],
      ),
      body: _carregando && _sugestoes.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _erro != null && _sugestoes.isEmpty
              ? EstadoErroLista(mensagem: _erro!, onTentarNovamente: _carregar)
              : visiveis.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            const SizedBox(height: 16),
                            Text(
                              _mostrarSoPendentes
                                  ? 'Nenhuma sugestão pendente.'
                                  : 'Nenhuma sugestão recebida ainda.',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _carregar,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: visiveis.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final s = visiveis[i];
                          final (rotulo, icone, cor) = _statusInfo[s.status]!;
                          final vezes = contagem[s.termoBuscado.trim().toLowerCase()] ?? 1;

                          return ListTile(
                            leading: IconButton(
                              icon: Icon(icone, color: cor),
                              tooltip: '$rotulo — toque pra avançar',
                              onPressed: () => _avancarStatus(s),
                            ),
                            title: Row(
                              children: [
                                Expanded(child: Text(s.termoBuscado, style: const TextStyle(fontWeight: FontWeight.w600))),
                                if (vezes > 1)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text('${vezes}x', style: Theme.of(context).textTheme.bodySmall),
                                  ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (s.mensagem != null && s.mensagem!.isNotEmpty) Text(s.mensagem!),
                                if (s.clienteNome != null || s.contato != null)
                                  Text(
                                    s.clienteNome ?? s.contato ?? '',
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                                  ),
                                Text(
                                  DateFormat('dd/MM/yyyy HH:mm').format(s.createdAt.toLocal()),
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11),
                                ),
                              ],
                            ),
                            isThreeLine: true,
                          );
                        },
                      ),
                    ),
    );
  }
}
