import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gestor/providers/carrinho_provider.dart';
import 'package:gestor/providers/produto_provider.dart';
import 'package:gestor/models/cliente.dart';
import 'package:gestor/models/zona_entrega.dart';
import 'package:gestor/screens/opcao_entrega_screen.dart';
import 'package:gestor/screens/pagamento_screen.dart';
import 'package:gestor/widgets/preco_com_desconto.dart';
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';
import '../providers/zona_entrega_provider.dart';
import '../repositories/carrinho_cliente_repository.dart';
import '../repositories/cliente_repository.dart';
import '../services/distancia_service.dart';
import '../utils/agendamento_utils.dart';

/// Resolve e já seleciona a zona de entrega do cliente no `CarrinhoProvider`
/// — usa a distância já salva no cadastro dele (mesmo campo que
/// `OpcaoEntregaScreen` usa/alimenta) e, se não tiver, calcula na hora.
/// Necessário sempre que um cliente é selecionado FORA do fluxo normal via
/// `OpcaoEntregaScreen` (que já faz isso sozinho) — sem chamar isso, frete e
/// "falta pro frete grátis" ficam em branco (bug real 10/09, achado ao
/// retomar um carrinho salvo em "Carrinhos do dia").
Future<void> resolverZonaEntregaParaCliente(
  BuildContext context,
  Cliente cliente,
  CarrinhoProvider carrinhoProvider,
) async {
  final zonaProvider = context.read<ZonaEntregaProvider>();
  var distanciaKm = cliente.rangeDistancia;

  if (distanciaKm == null) {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null || cliente.enderecoCompleto.isEmpty) return;
    final enderecoEmpresa = await DistanciaService.buscarEnderecoEmpresa(empresaId);
    if (enderecoEmpresa == null) return;
    final rota = await DistanciaService.calcularRota(
      origem: enderecoEmpresa,
      destino: (cliente.latitude != null && cliente.longitude != null)
          ? '${cliente.latitude},${cliente.longitude}'
          : cliente.enderecoCompleto,
    );
    if (rota == null) return;
    distanciaKm = rota.distanciaKm;
    if (cliente.idCliente != null) {
      unawaited(ClienteRepository().atualizarDistancia(
        cliente.idCliente!,
        rangeDistancia: rota.distanciaKm,
        estimativaEntrega: rota.duracaoMin,
      ));
    }
  }

  carrinhoProvider.selecionarZonaEntrega(zonaProvider.zonaParaDistancia(distanciaKm));
}

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
  bool _salvandoOrcamento = false;
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
      if (cliente.idCliente != null) await _carregarCarrinhoExistente(cliente.idCliente!, carrinhoProvider);
    }
  }

  /// Se o cliente recém-selecionado já tem algo no carrinho compartilhado
  /// (WhatsApp/site, ou um orçamento que você mesmo salvou antes pra ele),
  /// já mescla com o que estiver sendo montado agora — evita ter que ir
  /// procurar em "Carrinhos do dia" quando é só continuar direto daqui.
  Future<void> _carregarCarrinhoExistente(String clienteId, CarrinhoProvider carrinhoProvider) async {
    try {
      final carrinhoExistente = await CarrinhoClienteRepository().consultar(clienteId);
      if (carrinhoExistente.vazio || !mounted) return;
      final catalogo = Provider.of<ProdutoProvider>(context, listen: false).produtos;
      final ignorados = carrinhoProvider.mesclarItensRemotos(catalogo, carrinhoExistente.itens);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          ignorados.isEmpty
              ? 'Itens que esse cliente já tinha no carrinho foram adicionados aqui.'
              : 'Itens do carrinho anterior adicionados (${ignorados.length} não puderam ser trazidos: ${ignorados.join(", ")}).',
        )),
      );
    } catch (e) {
      debugPrint('Erro ao carregar carrinho existente do cliente: $e');
    }
  }

  Future<void> _salvarOrcamento(CarrinhoProvider carrinhoProvider) async {
    final cliente = carrinhoProvider.clienteSelecionado;
    if (cliente?.idCliente == null) return;

    setState(() => _salvandoOrcamento = true);
    try {
      final itensPayload = carrinhoProvider.itens
          .map((i) => {'produto_id': i.produto.id, 'quantidade': i.quantidade})
          .toList();
      await CarrinhoClienteRepository().salvarComoStaff(cliente!.idCliente!, itensPayload);
      carrinhoProvider.limparCarrinho();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Orçamento salvo pra ${cliente.nome} — retome em "Carrinhos do dia".')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível salvar: $e')));
    } finally {
      if (mounted) setState(() => _salvandoOrcamento = false);
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
          // Salva esse carrinho no cliente selecionado (mesma tabela do
          // WhatsApp/site) e libera o carrinho ativo pra montar outro do
          // zero — pra quando outro cliente precisa de atenção no meio do
          // atendimento (ver [[gestor_multiplos_atendimentos_carrinho]]).
          if (!vazio && carrinhoProvider.clienteSelecionado != null)
            IconButton(
              icon: _salvandoOrcamento
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_outlined),
              tooltip: 'Salvar orçamento e começar outro',
              onPressed: _salvandoOrcamento ? null : () => _salvarOrcamento(carrinhoProvider),
            ),
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
                        carrinhoProvider.clienteSelecionado!.enderecoExibicao,
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
                // "Entrega" só pode dizer "Frete Grátis" depois de um cliente
                // selecionado — sem cliente, valorEntregaCalculado também dá 0
                // (nada foi calculado ainda), e mostrar "Grátis" nesse ponto
                // já enganou cliente que recebeu print da tela achando que o
                // frete tava confirmado (bug real 10/09).
                _linhaResumo(
                  context,
                  'Entrega',
                  carrinhoProvider.clienteSelecionado == null
                      ? 'A calcular'
                      : (carrinhoProvider.valorEntregaCalculado == 0
                          ? 'Frete Grátis'
                          : 'R\$ ${carrinhoProvider.valorEntregaCalculado.toStringAsFixed(2)}'),
                  cor: carrinhoProvider.clienteSelecionado != null && carrinhoProvider.valorEntregaCalculado == 0
                      ? Colors.green
                      : null,
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
        ? produto.imagemUrlExibicao
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
