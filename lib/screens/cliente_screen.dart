import 'package:flutter/material.dart';
import 'package:gestor/screens/adicionar_cliente_screen.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/cliente_provider.dart';
import '../widgets/categoria_cliente_badge.dart';
import '../widgets/estado_erro_lista.dart';
import '../widgets/importar_clientes_planilha.dart';
import 'cliente_detalhes_screen.dart';
import '../models/cliente.dart';

class ClientesScreen extends StatefulWidget {
  @override
  _ClientesScreenState createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  String _textoPesquisa = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      Provider.of<ClientProvider>(context, listen: false).carregarClientesDoFirestore();
    });
  }

  void _cadastrarNovoCliente() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdicionarClienteScreen(),
      ),
    );
  }

  Future<void> _importarClientes() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => const ImportarClientesScreen(),
    ));
    if (mounted) {
      Provider.of<ClientProvider>(context, listen: false).carregarClientes();
    }
  }

  void _aplicarFiltro() {
    Provider.of<ClientProvider>(context, listen: false).pesquisarClientes(_textoPesquisa);
  }

  void _verDetalhesCliente(Cliente cliente) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ClienteDetalhesScreen(cliente: cliente),
      ),
    );
  }

  List<Widget> _iconesDePets(Cliente cliente) {
    final counts = <String, int>{};

    for (final pet in cliente.pets) {
      counts[pet.especie] = (counts[pet.especie] ?? 0) + 1;
    }

    final emojiMap = {
      'Cão': '🐶',
      'Gato': '🐱',
      'Passarinho': '🐦',
      'Peixe': '🐟',
      'Coelho': '🐰',
    };

    List<Widget> emojis = [];

    for (var especie in counts.keys) {
      final emoji = emojiMap[especie];
      if (emoji != null) {
        emojis.add(Text(emoji * counts[especie]!));
      }
    }

    return emojis;
  }



  Future<void> _confirmarExclusao(ClientProvider clientProvider, Cliente cliente) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Excluir Cliente'),
        content: Text('Tem certeza que deseja excluir ${cliente.nome}?'),
        actions: [
          TextButton(child: Text('Cancelar'), onPressed: () => Navigator.of(ctx).pop(false)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await clientProvider.removerClienteDoFirestore(cliente);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível excluir o cliente: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientProvider = Provider.of<ClientProvider>(context);
    final clientesFiltrados = clientProvider.clientes;
    final colorScheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    // Reforça na UI o que já é bloqueado no banco (trigger) — vendedor não
    // exclui cliente.
    final podeExcluir = auth.podeExcluir;

    return Scaffold(
      appBar: AppBar(
        title: Text('Clientes (${clientesFiltrados.length})'),
        actions: [
          // Importar/exportar mexe na base de clientes inteira (telefone,
          // endereço, CPF, saldo) de uma vez só — bulk admin, não venda do
          // dia a dia. Vendedor não deveria conseguir baixar isso.
          if (!auth.isVendedor)
            IconButton(
              icon: const Icon(Icons.upload_file),
              onPressed: _importarClientes,
              tooltip: 'Importar/Exportar Planilha',
            ),
          IconButton(
            icon: Icon(Icons.person_add),
            onPressed: _cadastrarNovoCliente,
            tooltip: 'Cadastrar Novo Cliente',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              onChanged: (texto) {
                setState(() {
                  _textoPesquisa = texto;
                });
                _aplicarFiltro();
              },
              decoration: const InputDecoration(
                hintText: 'Pesquisar por nome, celular ou endereço',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: clientProvider.carregando
                ? const Center(child: CircularProgressIndicator())
                : clientProvider.erro != null
                    ? EstadoErroLista(
                        mensagem: clientProvider.erro!,
                        onTentarNovamente: clientProvider.carregarClientes,
                      )
                    : clientesFiltrados.isEmpty
                    ? _estadoVazio(colorScheme)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: clientesFiltrados.length,
                        itemBuilder: (context, index) {
                          final cliente = clientesFiltrados[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              onTap: () => _verDetalhesCliente(cliente),
                              leading: CircleAvatar(
                                backgroundColor: colorScheme.primaryContainer,
                                child: Text(
                                  cliente.nome.isNotEmpty ? cliente.nome[0].toUpperCase() : '?',
                                  style: TextStyle(color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      cliente.nome,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  CategoriaClienteBadge(categoria: cliente.categoriaCliente),
                                ],
                              ),
                              subtitle: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${cliente.celular} • Saldo R\$${cliente.saldo.toStringAsFixed(2)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  ..._iconesDePets(cliente),
                                ],
                              ),
                              trailing: podeExcluir
                                  ? IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      tooltip: 'Excluir',
                                      onPressed: () => _confirmarExclusao(clientProvider, cliente),
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _estadoVazio(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 56, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              _textoPesquisa.isNotEmpty ? 'Nenhum cliente encontrado' : 'Nenhum cliente cadastrado ainda',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              _textoPesquisa.isNotEmpty
                  ? 'Tente buscar por outro termo.'
                  : 'Toque no ícone de "+" pra cadastrar o primeiro.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
