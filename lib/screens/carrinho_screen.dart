import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gestor/providers/carrinho_provider.dart';
import 'package:gestor/models/cliente.dart';
import 'package:gestor/models/zona_entrega.dart';
import 'package:gestor/screens/opcao_entrega_screen.dart';
import 'package:gestor/screens/pagamento_screen.dart';
import 'package:gestor/widgets/preco_com_desconto.dart';
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';
import '../utils/agendamento_utils.dart';

class CarrinhoScreen extends StatefulWidget {
  final String idVenda;

  const CarrinhoScreen({
    Key? key,
    required this.idVenda,
  }) : super(key: key);

  @override
  State<CarrinhoScreen> createState() => _CarrinhoScreenState();
}

class _CarrinhoScreenState extends State<CarrinhoScreen> {
  late String idVenda;
  double? _valorMinimoPedido;
  final TextEditingController _cupomController = TextEditingController();

  @override
  void dispose() {
    _cupomController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    idVenda = widget.idVenda.isNotEmpty ? widget.idVenda : const Uuid().v4();
    _carregarValorMinimo();
  }

  Future<void> _carregarValorMinimo() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    try {
      final data = await supabase
          .from('empresas')
          .select('valor_minimo_pedido')
          .eq('id', empresaId)
          .single();
      final valor = (data['valor_minimo_pedido'] as num?)?.toDouble();
      if (mounted) setState(() => _valorMinimoPedido = valor);
    } catch (e) {
      debugPrint('Erro ao carregar valor mínimo de pedido: $e');
    }
  }

  Future<void> selecionarCliente(CarrinhoProvider carrinhoProvider) async {
    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OpcaoEntregaScreen(
          subtotal: carrinhoProvider.subtotal,
        ),
      ),
    );

    if (resultado != null && resultado is Map<String, dynamic>) {
      final Cliente cliente = resultado['cliente'];
      final ZonaEntrega? zona = resultado['zona'];
      final JanelaHorarioAgendamento? agendamento = resultado['agendamento'];
      carrinhoProvider.selecionarCliente(cliente);
      carrinhoProvider.selecionarZonaEntrega(zona);
      carrinhoProvider.selecionarAgendamento(agendamento);
    }
  }

  @override
  Widget build(BuildContext context) {
    final carrinhoProvider = context.watch<CarrinhoProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final vazio = carrinhoProvider.itens.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Carrinho de Compras'),
        actions: [
          if (!vazio)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Esvaziar carrinho',
              onPressed: () {
                carrinhoProvider.limparCarrinho();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Carrinho esvaziado!')),
                );
              },
            ),
        ],
      ),
      body: vazio ? _estadoVazio(colorScheme) : _corpo(context, carrinhoProvider, colorScheme),
    );
  }

  Widget _estadoVazio(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shopping_bag_outlined, size: 56, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'Seu carrinho está vazio',
              style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              'Volte pra tela de venda e adicione produtos.',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _corpo(BuildContext context, CarrinhoProvider carrinhoProvider, ColorScheme colorScheme) {
    final abaixoDoMinimo =
        _valorMinimoPedido != null && carrinhoProvider.totalCarrinho < _valorMinimoPedido!;
    final podeAvancar = carrinhoProvider.clienteSelecionado != null && !abaixoDoMinimo;

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            itemCount: carrinhoProvider.itens.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final item = carrinhoProvider.itens[i];
              return _itemCard(context, carrinhoProvider, item, colorScheme);
            },
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (carrinhoProvider.clienteSelecionado != null)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(carrinhoProvider.clienteSelecionado!.nome),
                      subtitle: Text(
                        carrinhoProvider.clienteSelecionado!.enderecoCompleto,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: TextButton(
                        onPressed: () => selecionarCliente(carrinhoProvider),
                        child: const Text('Trocar'),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OutlinedButton.icon(
                      onPressed: () => selecionarCliente(carrinhoProvider),
                      icon: const Icon(Icons.person_add_alt),
                      label: const Text('Selecionar Cliente'),
                    ),
                  ),

                _cupomSection(context, carrinhoProvider),
                const SizedBox(height: 8),

                _linhaResumo(context, 'Subtotal', 'R\$ ${carrinhoProvider.subtotal.toStringAsFixed(2)}'),
                if (carrinhoProvider.desconto > 0)
                  _linhaResumo(
                    context,
                    carrinhoProvider.cupomAplicado != null ? 'Cupom (${carrinhoProvider.cupomAplicado!.codigo})' : 'Desconto',
                    '- R\$ ${carrinhoProvider.desconto.toStringAsFixed(2)}',
                    cor: Colors.green,
                  ),
                _linhaResumo(
                  context,
                  'Entrega',
                  carrinhoProvider.valorEntregaCalculado == 0
                      ? 'Frete Grátis'
                      : 'R\$ ${carrinhoProvider.valorEntregaCalculado.toStringAsFixed(2)}',
                  cor: carrinhoProvider.valorEntregaCalculado == 0 ? Colors.green : null,
                ),
                if (carrinhoProvider.valorFaltanteParaFreteGratis > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Faltam R\$ ${carrinhoProvider.valorFaltanteParaFreteGratis.toStringAsFixed(2)} para frete grátis',
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                const Divider(height: 20),
                _linhaResumo(
                  context,
                  'Total',
                  'R\$ ${carrinhoProvider.totalCarrinho.toStringAsFixed(2)}',
                  negrito: true,
                  tamanho: 20,
                ),

                if (abaixoDoMinimo)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Pedido mínimo: R\$ ${_valorMinimoPedido!.toStringAsFixed(2)} '
                      '(faltam R\$ ${(_valorMinimoPedido! - carrinhoProvider.totalCarrinho).toStringAsFixed(2)})',
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),

                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: !podeAvancar
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PagamentoScreen(
                                idVenda: idVenda,
                                valorTotal: carrinhoProvider.totalCarrinho,
                                carrinho: carrinhoProvider.itens.map((item) => item.toMap()).toList(),
                                cliente: carrinhoProvider.clienteSelecionado!,
                                desconto: carrinhoProvider.desconto,
                                cupomId: carrinhoProvider.cupomAplicado?.id,
                                valorEntrega: carrinhoProvider.valorEntregaCalculado,
                                entregaSelecionada: carrinhoProvider.entregaSelecionadaId,
                                zonaEntrega: carrinhoProvider.zonaEntregaSelecionada,
                                agendamento: carrinhoProvider.agendamentoSelecionado,
                              ),
                            ),
                          );
                        },
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                  child: Text(
                    '${carrinhoProvider.totalUnidades} ite${carrinhoProvider.totalUnidades == 1 ? 'm' : 'ns'} — '
                    'Ir para pagamento',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _itemCard(
    BuildContext context,
    CarrinhoProvider carrinhoProvider,
    ItemCarrinho item,
    ColorScheme colorScheme,
  ) {
    final produto = item.produto;
    final quantidade = item.quantidade;
    final imagemUrl = produto.imagemUrl.isNotEmpty
        ? produto.imagemUrl
        : 'http://imagens.lukz.com.br/produtos/${produto.codigoBarras}.png';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Image.network(
                  imagemUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: colorScheme.surfaceContainerHighest,
                    child: Icon(Icons.image_not_supported_outlined, size: 20, color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(produto.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  PrecoComDesconto(produto: produto),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.remove),
                    onPressed: () => carrinhoProvider.atualizarQuantidadeProduto(produto.id!, quantidade - 1),
                  ),
                  Text(quantidade.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  IconButton(
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add),
                    onPressed: () => carrinhoProvider.atualizarQuantidadeProduto(produto.id!, quantidade + 1),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remover',
              onPressed: () => carrinhoProvider.removerProduto(produto.id!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linhaResumo(BuildContext context, String rotulo, String valor, {Color? cor, bool negrito = false, double tamanho = 15}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(rotulo, style: TextStyle(fontSize: tamanho, fontWeight: negrito ? FontWeight.bold : FontWeight.w500)),
          Text(
            valor,
            style: TextStyle(fontSize: tamanho, fontWeight: negrito ? FontWeight.bold : FontWeight.normal, color: cor),
          ),
        ],
      ),
    );
  }

  Widget _cupomSection(BuildContext context, CarrinhoProvider carrinhoProvider) {
    final cupom = carrinhoProvider.cupomAplicado;

    if (cupom != null) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.local_offer, color: Colors.green, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '"${cupom.codigo}" aplicado',
                style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.green),
              ),
            ),
            TextButton(
              onPressed: carrinhoProvider.removerCupom,
              child: const Text('Remover'),
            ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _cupomController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Cupom de desconto',
                  isDense: true,
                ),
              ),
              if (carrinhoProvider.erroCupom != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    carrinhoProvider.erroCupom!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: OutlinedButton(
            onPressed: carrinhoProvider.validandoCupom
                ? null
                : () {
                    final empresaId = context.read<AuthProvider>().empresaId;
                    if (empresaId == null) return;
                    carrinhoProvider.aplicarCupom(empresaId, _cupomController.text);
                  },
            child: Text(carrinhoProvider.validandoCupom ? '...' : 'Aplicar'),
          ),
        ),
      ],
    );
  }
}
