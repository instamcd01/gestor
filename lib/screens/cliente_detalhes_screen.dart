import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/cliente.dart';
import '../models/item_carrinho_cliente.dart';
import '../models/movimentacao_saldo.dart';
import '../models/venda.dart';
import '../providers/auth_provider.dart';
import '../providers/cliente_provider.dart';
import '../repositories/carrinho_cliente_repository.dart';
import '../repositories/saldo_repository.dart';
import '../repositories/venda_repository.dart';
import '../utils/telefone_utils.dart';
import '../widgets/categoria_cliente_badge.dart';
import '../widgets/form_section.dart';
import 'editar_cliente_screen.dart';
import 'venda_detalhes_screen.dart';

class ClienteDetalhesScreen extends StatefulWidget {
  final Cliente cliente;

  const ClienteDetalhesScreen({super.key, required this.cliente});

  @override
  State<ClienteDetalhesScreen> createState() => _ClienteDetalhesScreenState();
}

class _ClienteDetalhesScreenState extends State<ClienteDetalhesScreen> {
  bool _excluindo = false;

  @override
  Widget build(BuildContext context) {
    // Observa o provider pra refletir mudanças feitas em outro lugar do app
    // (ex: uma venda alterando saldo/total gasto) sem precisar reabrir a tela.
    final clientProvider = context.watch<ClientProvider>();
    final cliente = widget.cliente.idCliente != null
        ? clientProvider.clientes.firstWhere(
            (c) => c.idCliente == widget.cliente.idCliente,
            orElse: () => widget.cliente,
          )
        : widget.cliente;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(cliente.nome),
          actions: [
            // Reforça na UI o que já é bloqueado no banco (trigger) —
            // vendedor não exclui cliente.
            if (context.watch<AuthProvider>().podeExcluir)
              IconButton(
                icon: _excluindo
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary),
                      )
                    : const Icon(Icons.delete),
                onPressed: _excluindo ? null : () => _confirmarDelecao(cliente),
              ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Dados'),
              Tab(text: 'Carrinho'),
              Tab(text: 'Compras'),
              Tab(text: 'Conta'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildDadosTab(context, cliente),
            _CarrinhoClienteTab(clienteId: cliente.idCliente ?? ''),
            _ComprasClienteTab(clienteId: cliente.idCliente),
            _ContaClienteTab(cliente: cliente),
          ],
        ),
      ),
    );
  }

  Widget _buildDadosTab(BuildContext context, Cliente cliente) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Center(
          child: CircleAvatar(
            radius: 40,
            backgroundColor: colorScheme.primaryContainer,
            child: Text(
              cliente.nome.isNotEmpty ? cliente.nome[0].toUpperCase() : '?',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: colorScheme.onPrimaryContainer),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(child: CategoriaClienteBadge(categoria: cliente.categoriaCliente)),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (cliente.celular.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.message, color: Colors.green),
                tooltip: 'Abrir WhatsApp',
                onPressed: () => _abrirWhatsApp(cliente.celular),
              ),
            if (cliente.email.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.email, color: Colors.blue),
                tooltip: 'Enviar e-mail',
                onPressed: () => _enviarEmail(cliente.email),
              ),
            if (cliente.enderecoCompleto.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.location_on, color: Colors.red),
                tooltip: 'Abrir no mapa',
                onPressed: () => _abrirMapa(cliente.enderecoCompleto),
              ),
          ],
        ),
        const SizedBox(height: 8),

        FormSection(
          titulo: 'Contato',
          children: [
            _buildClienteInfo('Celular/WhatsApp', cliente.celular),
            _buildClienteInfo('E-mail', cliente.email),
            _buildClienteInfo('CPF/CNPJ', cliente.cpf),
            _buildClienteInfo('Endereço', cliente.enderecoCompleto),
            _buildClienteInfo('Complemento', cliente.complemento),
            _buildClienteInfo('Distância',
                cliente.rangeDistancia != null ? '${cliente.rangeDistancia!.toStringAsFixed(2)} km' : 'Não informado'),
            _buildClienteInfo('Estimativa de entrega',
                cliente.estimativaEntrega != null ? '${cliente.estimativaEntrega} min' : 'Não informado'),
          ],
        ),
        const SizedBox(height: 16),

        FormSection(
          titulo: 'Preferências',
          children: [
            _buildClienteInfo('Observação', cliente.observacao),
            _buildClienteInfo('Canal de Origem', cliente.canalOrigem ?? 'Não informado'),
            _buildClienteInfo('Aniversário',
                cliente.aniversario != null ? dateFormat.format(cliente.aniversario!) : 'Não informado'),
            _buildClienteInfo('Aceita Marketing?', cliente.aceitaMarketing == true ? 'Sim' : 'Não'),
          ],
        ),
        const SizedBox(height: 16),

        FormSection(
          titulo: 'Resumo de compras',
          children: [
            _buildClienteInfo('Cliente desde',
                cliente.dataCadastro != null ? dateFormat.format(cliente.dataCadastro!) : 'Não informado'),
            _buildClienteInfo('Compras Realizadas', cliente.quantidadeCompras?.toString() ?? '0'),
            _buildClienteInfo('Total Gasto', 'R\$ ${(cliente.totalGasto ?? 0).toStringAsFixed(2)}'),
            _buildClienteInfo('Ticket Médio', 'R\$ ${(cliente.ticketMedio ?? 0).toStringAsFixed(2)}'),
            if (cliente.intervaloMedioRecompraDias != null)
              _buildClienteInfo(
                'Intervalo Médio Entre Pedidos',
                '${cliente.intervaloMedioRecompraDias!.toStringAsFixed(0)} dias',
              ),
          ],
        ),
        const SizedBox(height: 16),

        FormSection(
          titulo: 'Pets',
          children: [
            if (cliente.pets.isEmpty)
              Text('Nenhum pet registrado.', style: TextStyle(color: colorScheme.onSurfaceVariant))
            else
              Column(children: cliente.pets.map((pet) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: pet.imagemUrl.isNotEmpty
                            ? Image.network(
                                pet.imagemUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  color: colorScheme.surfaceContainerHighest,
                                  child: Icon(Icons.pets, color: colorScheme.onSurfaceVariant),
                                ),
                              )
                            : Container(
                                color: colorScheme.surfaceContainerHighest,
                                child: Icon(Icons.pets, color: colorScheme.onSurfaceVariant),
                              ),
                      ),
                    ),
                    title: Text(pet.nome),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${pet.especie} - ${pet.raca}${pet.porte.isNotEmpty ? ' • ${pet.porte}' : ''}'),
                        if (pet.alergias.isNotEmpty)
                          Text(
                            'Alergias: ${pet.alergias}',
                            style: TextStyle(color: Colors.red[700], fontSize: 12),
                          ),
                      ],
                    ),
                  )).toList()),
          ],
        ),
        const SizedBox(height: 24),

        ElevatedButton(
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EditarClienteScreen(clienteSelecionado: cliente),
              ),
            );
            // EditarClienteScreen já atualiza o ClientProvider antes de
            // voltar — o watch() no build cuida do resto.
          },
          style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
          child: const Text('Editar Dados'),
        ),
      ],
    );
  }

  Widget _buildClienteInfo(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value?.isNotEmpty == true ? value! : 'Não informado',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarDelecao(Cliente cliente) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text(
          cliente.saldo > 0
              ? 'Tem certeza de que deseja excluir este cliente? Ele ainda tem R\$ ${cliente.saldo.toStringAsFixed(2)} de saldo — esse valor deixará de ser rastreado.'
              : 'Tem certeza de que deseja excluir este cliente?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );

    if (confirmou != true || !mounted) return;

    final clientProvider = Provider.of<ClientProvider>(context, listen: false);
    setState(() => _excluindo = true);
    try {
      await clientProvider.removerClienteDoFirestore(cliente);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _excluindo = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível excluir o cliente: $e')),
      );
    }
  }

  Future<void> _abrirWhatsApp(String numero) async {
    if (normalizarTelefoneBr(numero).isEmpty) return;
    final uri = Uri.parse(linkWhatsApp(numero));
    if (await canLaunchUrl(uri)) {
      // Sem isso, em alguns aparelhos o link abre numa webview dentro do
      // próprio Gestor em vez de abrir o WhatsApp de verdade.
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _enviarEmail(String email) async {
    if (email.isEmpty) return;
    final uri = Uri(scheme: 'mailto', path: email);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _abrirMapa(String endereco) async {
    if (endereco.isEmpty) return;
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(endereco)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}

/// Aba "Carrinho": o carrinho ATIVO real desse cliente — o mesmo que o
/// agente de WhatsApp e o site usam (tabela `carrinho`/`carrinho_itens`
/// compartilhada). Permite ver e remover item na mão, útil quando o bot
/// trava numa operação ou quando o dono assume um atendimento.
class _CarrinhoClienteTab extends StatefulWidget {
  final String clienteId;

  const _CarrinhoClienteTab({required this.clienteId});

  @override
  State<_CarrinhoClienteTab> createState() => _CarrinhoClienteTabState();
}

class _CarrinhoClienteTabState extends State<_CarrinhoClienteTab> {
  final _repository = CarrinhoClienteRepository();
  late Future<CarrinhoCliente> _futureCarrinho;
  String? _removendoProdutoId;

  @override
  void initState() {
    super.initState();
    _futureCarrinho = _carregar();
  }

  Future<CarrinhoCliente> _carregar() {
    if (widget.clienteId.isEmpty) {
      return Future.value(CarrinhoCliente(itens: [], valorTotal: 0));
    }
    return _repository.consultar(widget.clienteId);
  }

  Future<void> _recarregar() async {
    setState(() => _futureCarrinho = _carregar());
    await _futureCarrinho;
  }

  Future<void> _removerItem(ItemCarrinhoCliente item) async {
    setState(() => _removendoProdutoId = item.produtoId);
    try {
      final novoCarrinho = await _repository.removerItem(
        widget.clienteId,
        produtoId: item.produtoId,
      );
      setState(() {
        _futureCarrinho = Future.value(novoCarrinho);
        _removendoProdutoId = null;
      });
    } catch (e) {
      setState(() => _removendoProdutoId = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível remover: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return FutureBuilder<CarrinhoCliente>(
      future: _futureCarrinho,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro ao carregar carrinho: ${snapshot.error}'));
        }
        final carrinho = snapshot.data!;
        if (carrinho.vazio) {
          return RefreshIndicator(
            onRefresh: _recarregar,
            child: ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Center(child: Text('Nenhum item no carrinho no momento.')),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _recarregar,
          child: ListView.builder(
            itemCount: carrinho.itens.length + 1,
            itemBuilder: (context, index) {
              if (index == carrinho.itens.length) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Total: ${currencyFormat.format(carrinho.valorTotal)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                );
              }
              final item = carrinho.itens[index];
              return ListTile(
                title: Text(item.nome),
                subtitle: Text('${item.quantidade}x ${currencyFormat.format(item.precoUnitario)}'),
                trailing: _removendoProdutoId == item.produtoId
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removerItem(item),
                      ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Aba "Compras": histórico de pedidos desse cliente (mesma tabela usada
/// pelo histórico geral de vendas), reaproveitando a tela de detalhes de
/// venda já existente pro toque em cada item.
class _ComprasClienteTab extends StatefulWidget {
  final String? clienteId;

  const _ComprasClienteTab({required this.clienteId});

  @override
  State<_ComprasClienteTab> createState() => _ComprasClienteTabState();
}

class _ComprasClienteTabState extends State<_ComprasClienteTab> {
  final _repository = VendaRepository();
  late Future<List<Venda>> _futureVendas;

  @override
  void initState() {
    super.initState();
    _futureVendas = _carregar();
  }

  Future<List<Venda>> _carregar() {
    final clienteId = widget.clienteId;
    if (clienteId == null) return Future.value([]);
    return _repository.listarPorCliente(clienteId);
  }

  Future<void> _recarregar() async {
    setState(() => _futureVendas = _carregar());
    await _futureVendas;
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return FutureBuilder<List<Venda>>(
      future: _futureVendas,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro ao carregar compras: ${snapshot.error}'));
        }

        final vendas = snapshot.data ?? [];
        if (vendas.isEmpty) {
          return RefreshIndicator(
            onRefresh: _recarregar,
            child: ListView(
              children: const [
                SizedBox(height: 120),
                Center(child: Text('Nenhuma compra registrada.')),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _recarregar,
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: vendas.length,
            itemBuilder: (context, index) {
              final venda = vendas[index];
              final cancelada = venda.cancelada;

              return Card(
                child: ListTile(
                  leading: Icon(
                    cancelada ? Icons.block : Icons.receipt,
                    color: cancelada ? Colors.grey : Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(
                    currencyFormat.format(venda.valorTotal),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      decoration: cancelada ? TextDecoration.lineThrough : null,
                      color: cancelada ? Colors.grey[600] : null,
                    ),
                  ),
                  subtitle: Text(
                    '${dateFormat.format(venda.dataVenda)} • ${venda.metodoPagamento}${cancelada ? ' • CANCELADA' : ''}',
                    style: cancelada ? TextStyle(color: Colors.grey[600]) : null,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => VendaDetalhesScreen(venda: venda)),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Aba "Conta": saldo atual + extrato de movimentações (crédito/débito),
/// com ações pra lançar ajustes manuais (ex: devolução, cortesia).
class _ContaClienteTab extends StatefulWidget {
  final Cliente cliente;

  const _ContaClienteTab({required this.cliente});

  @override
  State<_ContaClienteTab> createState() => _ContaClienteTabState();
}

class _ContaClienteTabState extends State<_ContaClienteTab> {
  final _repository = SaldoRepository();
  late Future<List<MovimentacaoSaldo>> _futureMovimentacoes;

  @override
  void initState() {
    super.initState();
    _futureMovimentacoes = _carregar();
  }

  @override
  void didUpdateWidget(covariant _ContaClienteTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cliente.idCliente != widget.cliente.idCliente) {
      setState(() => _futureMovimentacoes = _carregar());
    }
  }

  Future<List<MovimentacaoSaldo>> _carregar() {
    final clienteId = widget.cliente.idCliente;
    if (clienteId == null) return Future.value([]);
    return _repository.listarPorCliente(clienteId);
  }

  Future<void> _abrirDialogoMovimentacao(String tipo) async {
    final clienteId = widget.cliente.idCliente;
    if (clienteId == null) return;

    final valorController = TextEditingController();
    final motivoController = TextEditingController();

    final confirmou = await showDialog<bool>(
      context: context,
      // Sem autofocus + sem fechar tocando fora: com o teclado aberto (via
      // autofocus) e o diálogo fechando por barrier-dismiss no mesmo frame,
      // bate num bug conhecido do framework do Flutter (assert
      // `_dependents.isEmpty` ao desativar o Overlay/IME) — só os botões
      // fecham o diálogo agora.
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(tipo == 'credito' ? 'Adicionar Crédito' : 'Registrar Débito'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: valorController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor (R\$)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: motivoController,
              decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );

    if (confirmou != true || !mounted) return;

    final valor = double.tryParse(valorController.text.replaceAll(',', '.'));
    if (valor == null || valor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um valor válido.')),
      );
      return;
    }

    try {
      final novoSaldo = await _repository.registrarMovimentacao(
        clienteId: clienteId,
        tipo: tipo,
        valor: valor,
        motivo: motivoController.text.trim().isEmpty ? null : motivoController.text.trim(),
      );
      if (!mounted) return;
      Provider.of<ClientProvider>(context, listen: false).atualizarSaldoLocal(clienteId, novoSaldo);
      setState(() => _futureMovimentacoes = _carregar());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível registrar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Column(
      children: [
        Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text('Saldo Atual', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  currencyFormat.format(widget.cliente.saldo),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green),
                ),
                // Ajustar saldo é ação financeira — vendedor só enxerga o
                // saldo atual (precisa pra aplicar como pagamento numa
                // venda), não pode criar/remover crédito por conta própria.
                if (context.watch<AuthProvider>().podeVerFinancas) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // Sem Expanded, os dois botões (ícone + texto) somados
                      // ultrapassavam a largura da tela em telas estreitas —
                      // esse era o overflow reportado na aba Conta.
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _abrirDialogoMovimentacao('credito'),
                          icon: const Icon(Icons.add, color: Colors.green),
                          label: const Text('Adicionar Crédito'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _abrirDialogoMovimentacao('debito'),
                          icon: const Icon(Icons.remove, color: Colors.red),
                          label: const Text('Registrar Débito'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        // Só leitura aqui — PetCash é gerido pelo site (crédito automático
        // na entrega, consumo/expiração no checkout), sem botão de ajuste
        // manual como o saldo comum (diferente semântica: tem validade por
        // crédito, não é um saldo único fungível).
        if (widget.cliente.saldoPetCash > 0)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('🐾 PetCash Disponível', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    currencyFormat.format(widget.cliente.saldoPetCash),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: FutureBuilder<List<MovimentacaoSaldo>>(
            future: _futureMovimentacoes,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Erro ao carregar extrato: ${snapshot.error}'));
              }

              final movimentacoes = snapshot.data ?? [];
              if (movimentacoes.isEmpty) {
                return const Center(child: Text('Nenhuma movimentação registrada.'));
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: movimentacoes.length,
                itemBuilder: (context, index) {
                  final mov = movimentacoes[index];
                  return ListTile(
                    leading: Icon(
                      mov.isCredito ? Icons.arrow_upward : Icons.arrow_downward,
                      color: mov.isCredito ? Colors.green : Colors.red,
                    ),
                    title: Text(mov.motivo?.isNotEmpty == true ? mov.motivo! : (mov.isCredito ? 'Crédito' : 'Débito')),
                    subtitle: Text(dateFormat.format(mov.criadoEm)),
                    trailing: Text(
                      '${mov.isCredito ? '+' : '-'}${currencyFormat.format(mov.valor)}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: mov.isCredito ? Colors.green : Colors.red),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
