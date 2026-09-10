import 'package:flutter/material.dart';
import 'package:gestor/screens/adicionar_cliente_screen.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/cliente_provider.dart';
import '../repositories/cliente_repository.dart';
import '../widgets/categoria_cliente_badge.dart';
import '../widgets/estado_erro_lista.dart';
import '../widgets/importar_clientes_planilha.dart';
import 'cliente_detalhes_screen.dart';
import '../models/cliente.dart';

class ClientesScreen extends StatefulWidget {
  @override
  _ClientesScreenState createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _textoPesquisa = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    Future.microtask(() {
      Provider.of<ClientProvider>(context, listen: false).carregarClientesDoFirestore();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
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
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Clientes'),
            Tab(text: 'Histórico Kyte'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAbaClientes(context, auth),
          const _AbaHistoricoKyte(),
        ],
      ),
    );
  }

  Widget _buildAbaClientes(BuildContext context, AuthProvider auth) {
    final clientProvider = Provider.of<ClientProvider>(context);
    final clientesFiltrados = clientProvider.clientes;
    final colorScheme = Theme.of(context).colorScheme;
    // Reforça na UI o que já é bloqueado no banco (trigger) — vendedor não
    // exclui cliente.
    final podeExcluir = auth.podeExcluir;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${clientesFiltrados.length} cliente(s)',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
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

/// Cadastros "consultivos" do histórico do Kyte (sem login, sem pets, só
/// preservam pedidos antigos — ver [[gestor_vinculo_cliente_cross_canal]]
/// na memória do projeto). Lista própria (busca própria, filtrada em
/// memória) — não são clientes ativos, sem opção de excluir.
class _AbaHistoricoKyte extends StatefulWidget {
  const _AbaHistoricoKyte();

  @override
  State<_AbaHistoricoKyte> createState() => _AbaHistoricoKyteState();
}

class _AbaHistoricoKyteState extends State<_AbaHistoricoKyte> {
  final _repository = ClienteRepository();
  late Future<List<Cliente>> _futureClientes;
  String _textoPesquisa = '';

  @override
  void initState() {
    super.initState();
    _futureClientes = _repository.listarHistoricoKyte();
  }

  Future<void> _recarregar() async {
    setState(() => _futureClientes = _repository.listarHistoricoKyte());
    await _futureClientes;
  }

  Future<void> _verDetalhes(Cliente cliente) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ClienteDetalhesScreen(cliente: cliente)),
    );
    // Cobre o caso de "Usar este cadastro" promover o cliente e sair dessa
    // lista (ele deixa de ser histórico Kyte) — recarrega sempre que volta
    // porque é barato (257 linhas) e evita item fantasma na tela.
    if (mounted) await _recarregar();
  }

  // Lista já vem inteira do banco (só 257 linhas hoje) — filtra em
  // memória em vez de ida ao servidor a cada letra digitada, mesmo
  // espírito do ClientProvider.pesquisarClientes.
  List<Cliente> _filtrar(List<Cliente> clientes) {
    if (_textoPesquisa.isEmpty) return clientes;
    final termo = _textoPesquisa.toLowerCase();
    return clientes.where((c) {
      return c.nome.toLowerCase().contains(termo) ||
          (c.telefoneKyte ?? '').contains(termo);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FutureBuilder<List<Cliente>>(
      future: _futureClientes,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return EstadoErroLista(
            mensagem: 'Erro ao carregar histórico do Kyte: ${snapshot.error}',
            onTentarNovamente: _recarregar,
          );
        }

        final todos = snapshot.data ?? [];
        final clientes = _filtrar(todos);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                onChanged: (texto) => setState(() => _textoPesquisa = texto),
                decoration: const InputDecoration(
                  hintText: 'Pesquisar por nome ou telefone',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${clientes.length} cadastro(s)',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            Expanded(
              child: clientes.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _recarregar,
                      child: ListView(
                        children: [
                          const SizedBox(height: 100),
                          Center(
                            child: Text(
                              todos.isEmpty ? 'Nenhum cadastro de histórico do Kyte.' : 'Nenhum resultado pra essa busca.',
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _recarregar,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: clientes.length,
                        itemBuilder: (context, index) {
                          final cliente = clientes[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              onTap: () => _verDetalhes(cliente),
                              leading: CircleAvatar(
                                backgroundColor: colorScheme.tertiaryContainer,
                                child: Text(
                                  cliente.nome.isNotEmpty ? cliente.nome[0].toUpperCase() : '?',
                                  style: TextStyle(color: colorScheme.onTertiaryContainer, fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(
                                cliente.nome,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                '${cliente.telefoneKyte ?? "sem telefone"} • '
                                '${cliente.numeroCompras ?? 0} pedido(s) • '
                                'R\$${(cliente.totalGasto ?? 0).toStringAsFixed(2)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: cliente.pessoaId != null ? const Icon(Icons.link, size: 20) : null,
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}
