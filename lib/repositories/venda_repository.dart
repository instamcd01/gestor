import '../config/supabase_config.dart';
import '../models/cliente.dart';
import '../models/produto.dart';
import '../models/venda.dart';

/// Camada de acesso a dados de vendas. Cada "Venda" do app vira um registro
/// em `pedidos` (+ `itens_pedido`) no Supabase — a mesma tabela usada pelos
/// pedidos vindos de WhatsApp/iFood/site, só que com origem = 'loja_fisica'.
class VendaRepository {
  static const _selectComItensECliente =
      '*, cliente:clientes(*), itens_pedido(*, produtos(*))';

  Future<List<Venda>> listar() async {
    final data = await supabase
        .from('pedidos')
        .select(_selectComItensECliente)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);

    return (data as List)
        .map((row) => _vendaFromRow(row as Map<String, dynamic>))
        .toList();
  }

  /// Histórico de compras de um cliente específico (usado na aba "Compras"
  /// da tela de detalhes do cliente).
  Future<List<Venda>> listarPorCliente(String clienteId) async {
    final data = await supabase
        .from('pedidos')
        .select(_selectComItensECliente)
        .eq('cliente_id', clienteId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);

    return (data as List)
        .map((row) => _vendaFromRow(row as Map<String, dynamic>))
        .toList();
  }

  Future<Venda> registrar(Venda venda, {required String empresaId}) async {
    final lucroTotal = venda.itens.fold<double>(0, (soma, i) => soma + i.lucroTotal);
    final margemPercentual = venda.valorTotal > 0 ? (lucroTotal / venda.valorTotal * 100) : 0.0;

    // Venda de balcão (sem entrega) já sai como entregue — o cliente leva o
    // produto na hora. Venda com entrega entra pendente e passa pela Fila
    // de Pedidos até ser marcada como entregue de fato.
    final statusInicial = venda.temEntrega ? StatusPedido.pendente : StatusPedido.entregue;

    final pedidoInserido = await supabase
        .from('pedidos')
        .insert({
          'empresa_id': empresaId,
          'cliente_id': venda.cliente.idCliente,
          'status': statusInicial,
          'origem': 'app',
          'origem_tipo': 'proprio',
          'canal_venda': 'loja_fisica',
          'tipo_pagamento': venda.metodoPagamento,
          'status_pagamento': 'pago',
          'valor_produtos': venda.subtotal,
          'valor_entrega': venda.valorEntrega,
          'desconto': venda.desconto,
          'valor_total': venda.valorTotal,
          'custo_total': venda.custoTotal,
          'lucro_bruto': lucroTotal,
          'margem_percentual': margemPercentual,
          'observacoes': venda.observacao,
          'metadata': {
            'valorPago': venda.valorPago,
            'troco': venda.troco,
            'saldoUsado': venda.saldoUsado,
            'entregaSelecionada': venda.entregaSelecionada,
            'pagamentosDetalhados': venda.pagamentosDetalhados,
          },
        })
        .select()
        .single();

    final pedidoId = pedidoInserido['id'] as String;

    if (venda.itens.isNotEmpty) {
      final itensPayload = venda.itens.map((item) {
        final margemItem = item.precoUnitario > 0
            ? ((item.precoUnitario - item.custoUnitario) / item.precoUnitario * 100)
            : 0.0;
        return {
          'pedido_id': pedidoId,
          'produto_id': item.produto.id,
          'quantidade': item.quantidade,
          'preco_unitario': item.precoUnitario,
          'custo_unitario': item.custoUnitario,
          'subtotal': item.precoTotal,
          'margem_item': margemItem,
        };
      }).toList();

      await supabase.from('itens_pedido').insert(itensPayload);
    }

    return Venda(
      idVenda: pedidoId,
      cliente: venda.cliente,
      dataVenda: DateTime.tryParse(pedidoInserido['created_at'].toString())?.toLocal() ?? DateTime.now(),
      subtotal: venda.subtotal,
      desconto: venda.desconto,
      saldoUsado: venda.saldoUsado,
      valorEntrega: venda.valorEntrega,
      entregaSelecionada: venda.entregaSelecionada,
      valorTotal: venda.valorTotal,
      valorPago: venda.valorPago,
      troco: venda.troco,
      metodoPagamento: venda.metodoPagamento,
      totalItens: venda.totalItens,
      itens: venda.itens,
      custoTotal: venda.custoTotal,
      lucroTotal: lucroTotal,
      observacao: venda.observacao,
      pagamentosDetalhados: venda.pagamentosDetalhados,
      status: pedidoInserido['status']?.toString() ?? StatusPedido.entregue,
      canalVenda: pedidoInserido['canal_venda']?.toString() ?? 'loja_fisica',
    );
  }

  /// Avança o pedido pro próximo status do ciclo de vida (ver
  /// `Venda.proximoStatus`) — usado pela Fila de Pedidos.
  Future<void> avancarStatus(String idVenda, String novoStatus) async {
    await supabase.from('pedidos').update({'status': novoStatus}).eq('id', idVenda);
  }

  /// Cancela uma venda já registrada: devolve estoque, devolve saldo do
  /// cliente usado como pagamento e recalcula as métricas do cliente —
  /// tudo dentro da função `cancelar_pedido` no banco (atômico). Pedidos
  /// com status 'entregue'/'concluido' são bloqueados por trigger contra
  /// qualquer outra edição, só a transição para 'cancelado' é permitida.
  Future<void> cancelar(String idVenda) async {
    await supabase.rpc('cancelar_pedido', params: {'p_pedido_id': idVenda});
  }

  /// Abate o valor usado do saldo (crédito interno) do cliente, registrando
  /// a movimentação no extrato (ver `registrar_movimentacao_saldo` no banco).
  Future<void> descontarSaldoCliente(String clienteId, double valorUsado, {String? pedidoId}) async {
    if (valorUsado <= 0) return;

    await supabase.rpc('registrar_movimentacao_saldo', params: {
      'p_cliente_id': clienteId,
      'p_tipo': 'debito',
      'p_valor': valorUsado,
      'p_motivo': 'Usado como pagamento em venda',
      'p_pedido_id': pedidoId,
    });
  }

  Venda _vendaFromRow(Map<String, dynamic> row) {
    final clienteRow = row['cliente'] as Map<String, dynamic>?;
    final cliente = clienteRow != null
        ? Cliente.fromSupabase(clienteRow)
        : Cliente(
            nome: 'Cliente não informado',
            celular: '',
            email: '',
            endereco: '',
            complemento: '',
            cpf: '',
            observacao: '',
            saldo: 0,
            pets: [],
          );

    final metadata = (row['metadata'] as Map<String, dynamic>?) ?? {};
    final itensRows = (row['itens_pedido'] as List?) ?? [];

    final itens = itensRows.map((itemRow) {
      final produtoRow = itemRow['produtos'] as Map<String, dynamic>?;
      final produto = produtoRow != null
          ? Produto.fromSupabase(produtoRow)
          : Produto(
              nome: 'Produto removido',
              preco: 0,
              descricao: '',
              categoria: '',
              estoqueAtual: 0,
              estoqueMinimo: 0,
              imagemUrl: '',
              codigoBarras: '',
              custo: 0,
            );

      return ItemVenda(
        produto: produto,
        quantidade: (itemRow['quantidade'] as num?)?.toInt() ?? 0,
        precoUnitario: (itemRow['preco_unitario'] as num?)?.toDouble() ?? 0.0,
        // Custo histórico gravado no momento da venda — não o custo atual
        // do produto, que pode ter mudado desde então.
        custoUnitario: (itemRow['custo_unitario'] as num?)?.toDouble(),
      );
    }).toList();

    Map<String, double>? pagamentosDetalhados;
    if (metadata['pagamentosDetalhados'] != null) {
      pagamentosDetalhados = Map<String, dynamic>.from(metadata['pagamentosDetalhados'])
          .map((k, v) => MapEntry(k, (v as num).toDouble()));
    }

    return Venda(
      idVenda: row['id'] as String?,
      cliente: cliente,
      dataVenda: DateTime.tryParse(row['created_at'].toString())?.toLocal() ?? DateTime.now(),
      subtotal: (row['valor_produtos'] as num?)?.toDouble() ?? 0.0,
      desconto: (row['desconto'] as num?)?.toDouble() ?? 0.0,
      saldoUsado: (metadata['saldoUsado'] as num?)?.toDouble() ?? 0.0,
      valorEntrega: (row['valor_entrega'] as num?)?.toDouble() ?? 0.0,
      entregaSelecionada: metadata['entregaSelecionada']?.toString() ?? '',
      valorTotal: (row['valor_total'] as num?)?.toDouble() ?? 0.0,
      valorPago: (metadata['valorPago'] as num?)?.toDouble() ?? 0.0,
      troco: (metadata['troco'] as num?)?.toDouble() ?? 0.0,
      metodoPagamento: row['tipo_pagamento']?.toString() ?? '',
      pagamentosDetalhados: pagamentosDetalhados,
      totalItens: itens.fold<int>(0, (soma, i) => soma + i.quantidade),
      custoTotal: (row['custo_total'] as num?)?.toDouble() ?? 0.0,
      lucroTotal: (row['lucro_bruto'] as num?)?.toDouble() ?? 0.0,
      observacao: row['observacoes']?.toString() ?? '',
      itens: itens,
      status: row['status']?.toString() ?? StatusPedido.entregue,
      canalVenda: row['canal_venda']?.toString() ?? 'loja_fisica',
    );
  }
}
