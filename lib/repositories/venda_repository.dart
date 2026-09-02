import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/mercado_pago_config.dart';
import '../config/supabase_config.dart';
import '../models/cliente.dart';
import '../models/produto.dart';
import '../models/venda.dart';

/// Uma entrada da linha do tempo de status de um pedido (ver
/// `VendaRepository.historicoStatus`).
typedef EventoStatusPedido = ({String status, DateTime dataHora});

/// Camada de acesso a dados de vendas. Cada "Venda" do app vira um registro
/// em `pedidos` (+ `itens_pedido`) no Supabase — a mesma tabela usada pelos
/// pedidos vindos de WhatsApp/iFood/site, só que com origem = 'loja_fisica'.
class VendaRepository {
  // produtos!itens_pedido_produto_id_fkey (não só "produtos(*)") porque
  // itens_pedido ganhou uma 2ª FK pra produtos (grupo_kit_id, feature de
  // Kits) — sem desambiguar, o PostgREST não sabe por qual FK embutir e
  // toda consulta de vendas quebra com PGRST201 "more than one
  // relationship was found". A chave no JSON de resposta continua
  // "produtos" (o "!fkey" só escolhe o caminho, não vira alias).
  static const _selectComItensECliente =
      '*, cliente:clientes(*), itens_pedido(*, produtos!itens_pedido_produto_id_fkey(*)), '
      'marketplace_pedidos(id, rastreio_latitude, rastreio_longitude, rastreio_eta_entrega, rastreio_atualizado_em, '
      'separacao_status, separacao_erro, numero_exibicao, telefone_localizador, telefone_localizador_expira_em, '
      'codigo_retirada_exibicao, link_confirmacao_entrega, agendado, entrega_prevista_inicio, entrega_prevista_fim, '
      'taxa_servico_cliente, campanha_marketplace, cupom_marketplace, politica_substituicao, entregador_tipo, '
      'taxa_comissao, taxa_gateway)';
  // previsao_entrega_inicio/fim já vêm no '*' de pedidos (coluna própria,
  // não de marketplace_pedidos) — sem precisar listar explicitamente.

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
  /// Pedidos do cliente E de qualquer outro cadastro (outro canal) já
  /// vinculado a ele como a mesma pessoa (ver `listar_grupo_pessoa`,
  /// plano "Identidade de Cliente Cross-Canal") — sem vínculo nenhum,
  /// `listar_grupo_pessoa` devolve só o próprio id, comportamento
  /// idêntico ao de antes.
  Future<List<Venda>> listarPorCliente(String clienteId) async {
    final grupo = await supabase.rpc('listar_grupo_pessoa', params: {'p_cliente_id': clienteId});
    final ids = (grupo as List).map((r) => r['id'] as String).toList();

    final data = await supabase
        .from('pedidos')
        .select(_selectComItensECliente)
        .inFilter('cliente_id', ids)
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

    // Preencher a forma de pagamento na tela não significa que o dinheiro
    // já entrou — o app serve tanto de PDV (balcão/retirada, cobrado na
    // hora) quanto pra montar pedido de entrega (pagamento normalmente só
    // acontece quando o entregador chega). `venda.retirada` distingue os
    // dois casos (ao contrário de `temEntrega`, que trata "Retirada na
    // Loja" como entrega pra fins de fila de pedidos). Pra entrega de
    // verdade, o pagamento é confirmado automaticamente pelo banco no
    // momento em que o pedido é marcado como entregue (trigger
    // `confirmar_pagamento_entrega_loja_fisica`), não aqui.
    final statusPagamentoInicial = venda.retirada ? 'pago' : 'pendente';

    final itensPayload = venda.itens.map((item) {
      final margemItem = item.precoUnitario > 0
          ? ((item.precoUnitario - item.custoUnitario) / item.precoUnitario * 100)
          : 0.0;
      return {
        'produto_id': item.produto.id,
        'quantidade': item.quantidade,
        'preco_unitario': item.precoUnitario,
        'custo_unitario': item.custoUnitario,
        'subtotal': item.precoTotal,
        'margem_item': margemItem,
        'grupo_kit_id': item.grupoKitId,
      };
    }).toList();

    // pedido + itens numa transação só (função `registrar_pedido_completo`)
    // — antes eram dois inserts separados, e se o dos itens falhasse (ex:
    // trigger de estoque negativo, carrinho com item que ficou sem estoque
    // entre a seleção e o fechamento da venda), o pedido já criado ficava
    // órfão pra sempre na Fila de Pedidos com 0 itens.
    final pedidoInserido = await supabase.rpc('registrar_pedido_completo', params: {
      'p_pedido': {
        'empresa_id': empresaId,
        'cliente_id': venda.cliente.idCliente,
        'vendedor_id': supabase.auth.currentUser?.id,
        'status': statusInicial,
        'origem': 'app',
        'origem_tipo': 'proprio',
        'canal_venda': 'loja_fisica',
        'tipo_pagamento': venda.metodoPagamento,
        'status_pagamento': statusPagamentoInicial,
        'valor_produtos': venda.subtotal,
        'valor_entrega': venda.valorEntrega,
        'desconto': venda.desconto,
        // Cupom: o app já validou via CarrinhoProvider.aplicarCupom antes
        // de chegar aqui (mesmo momento em que já confia no desconto
        // manual digitado pelo atendente) — registrar_pedido_completo só
        // loga o uso atomicamente com a criação do pedido.
        'cupom_id': venda.cupomId,
        'valor_desconto_cupom': venda.cupomId != null ? venda.desconto : null,
        'valor_total': venda.valorTotal,
        'custo_total': venda.custoTotal,
        'lucro_bruto': lucroTotal,
        'margem_percentual': margemPercentual,
        'previsao_entrega_inicio': venda.previsaoEntregaInicio?.toIso8601String(),
        'previsao_entrega_fim': venda.previsaoEntregaFim?.toIso8601String(),
        'observacoes': venda.observacao,
        'metadata': {
          'valorPago': venda.valorPago,
          'troco': venda.troco,
          'saldoUsado': venda.saldoUsado,
          'entregaSelecionada': venda.entregaSelecionada,
          'pagamentosDetalhados': venda.pagamentosDetalhados,
          if (venda.agendadoManualmente) 'agendado': true,
        },
      },
      'p_itens': itensPayload,
    }) as Map<String, dynamic>;

    final pedidoId = pedidoInserido['id'] as String;

    return Venda(
      idVenda: pedidoId,
      numeroSequencial: (pedidoInserido['numero_sequencial'] as num?)?.toInt(),
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
      vendedorId: pedidoInserido['vendedor_id'] as String?,
      previsaoEntregaInicio: venda.previsaoEntregaInicio,
      previsaoEntregaFim: venda.previsaoEntregaFim,
      agendadoManualmente: venda.agendadoManualmente,
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
  Future<void> cancelar(String idVenda, {String? motivoCodigo, String? motivoDescricao}) async {
    await supabase.rpc('cancelar_pedido', params: {
      'p_pedido_id': idVenda,
      'p_motivo_codigo': motivoCodigo,
      'p_motivo_descricao': motivoDescricao,
    });
  }

  /// Estorna um pagamento online (Mercado Pago) e cancela a venda em
  /// seguida — o estorno em si só o site sabe fazer (é ele quem guarda o
  /// access_token do Mercado Pago da loja, o app nunca tem esse token), por
  /// isso a chamada HTTP autenticada com a própria sessão do app em vez de
  /// um RPC direto. `cancelar()` (RPC já existente) cuida de repor estoque
  /// e recalcular métricas do cliente — não duplicado aqui.
  Future<void> estornarPagamentoOnline(String idVenda) async {
    final sessao = supabase.auth.currentSession;
    if (sessao == null) throw Exception('Sessão expirada — entre de novo.');

    final resposta = await http.post(
      Uri.parse('$kSiteBaseUrl/api/mercadopago/estornar'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${sessao.accessToken}'},
      body: jsonEncode({'pedidoId': idVenda}),
    );

    if (resposta.statusCode != 200) {
      final corpo = jsonDecode(resposta.body) as Map<String, dynamic>;
      throw Exception(corpo['erro']?.toString() ?? 'Não foi possível estornar o pagamento.');
    }

    await cancelar(idVenda, motivoCodigo: 'estorno_pagamento', motivoDescricao: 'Pagamento estornado via Mercado Pago');
  }

  /// Confirma retirada/entrega por código (iFood) — o trigger cuida de
  /// validar de verdade contra a API a partir daqui. `codigo_confirmacao_status`
  /// fica 'pendente' até a resposta do n8n chegar; a tela recarrega a venda
  /// depois de um pequeno delay pra mostrar o resultado.
  Future<void> confirmarComCodigo(String idVenda, String codigo) async {
    await supabase.from('pedidos').update({
      'codigo_confirmacao_valor': codigo,
      'codigo_confirmacao_status': 'pendente',
      'codigo_confirmacao_erro': null,
    }).eq('id', idVenda);
  }

  Future<Venda> buscarPorId(String idVenda) async {
    final data = await supabase
        .from('pedidos')
        .select(_selectComItensECliente)
        .eq('id', idVenda)
        .single();
    return _vendaFromRow(data);
  }

  /// Linha do tempo de status do pedido (`pedido_status_historico`, criada
  /// por trigger a cada mudança de `pedidos.status`, populada desde
  /// 02/09/2026). Ordenado do mais antigo pro mais recente — leitura de
  /// timeline é natural nessa direção.
  Future<List<EventoStatusPedido>> historicoStatus(String idVenda) async {
    final data = await supabase
        .from('pedido_status_historico')
        .select('status, criado_em')
        .eq('pedido_id', idVenda)
        .order('criado_em');
    return (data as List)
        .map((row) => (
              status: row['status'] as String,
              dataHora: DateTime.parse(row['criado_em'] as String).toLocal(),
            ))
        .toList();
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
        id: itemRow['id'] as String?,
        produto: produto,
        quantidade: (itemRow['quantidade'] as num?)?.toInt() ?? 0,
        precoUnitario: (itemRow['preco_unitario'] as num?)?.toDouble() ?? 0.0,
        // Custo histórico gravado no momento da venda — não o custo atual
        // do produto, que pode ter mudado desde então.
        custoUnitario: (itemRow['custo_unitario'] as num?)?.toDouble(),
        observacaoCliente: itemRow['observacao_cliente']?.toString(),
        sugestoesSubstituicao: (itemRow['sugestoes_substituicao'] as List?)?.cast<Map<String, dynamic>>(),
        grupoKitId: itemRow['grupo_kit_id'] as String?,
      );
    }).toList();

    Map<String, double>? pagamentosDetalhados;
    if (metadata['pagamentosDetalhados'] != null) {
      pagamentosDetalhados = Map<String, dynamic>.from(metadata['pagamentosDetalhados'])
          .map((k, v) => MapEntry(k, (v as num).toDouble()));
    }

    final marketplacePedidoRow = row['marketplace_pedidos'] as Map<String, dynamic>?;

    return Venda(
      idVenda: row['id'] as String?,
      numeroSequencial: (row['numero_sequencial'] as num?)?.toInt(),
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
      vendedorId: row['vendedor_id'] as String?,
      motivoCancelamentoCodigo: row['motivo_cancelamento_codigo']?.toString(),
      motivoCancelamentoDescricao: row['motivo_cancelamento_descricao']?.toString(),
      marketplacePedidoId: marketplacePedidoRow?['id'] as String?,
      tipoEntregaMarketplace: row['tipo_entrega_marketplace']?.toString(),
      codigoConfirmacaoStatus: row['codigo_confirmacao_status']?.toString(),
      codigoConfirmacaoErro: row['codigo_confirmacao_erro']?.toString(),
      rastreioLatitude: (marketplacePedidoRow?['rastreio_latitude'] as num?)?.toDouble(),
      rastreioLongitude: (marketplacePedidoRow?['rastreio_longitude'] as num?)?.toDouble(),
      rastreioEtaEntrega: DateTime.tryParse(marketplacePedidoRow?['rastreio_eta_entrega']?.toString() ?? '')?.toLocal(),
      rastreioAtualizadoEm:
          DateTime.tryParse(marketplacePedidoRow?['rastreio_atualizado_em']?.toString() ?? '')?.toLocal(),
      separacaoStatus: marketplacePedidoRow?['separacao_status']?.toString(),
      separacaoErro: marketplacePedidoRow?['separacao_erro']?.toString(),
      numeroExibicaoMarketplace: marketplacePedidoRow?['numero_exibicao']?.toString(),
      telefoneLocalizador: marketplacePedidoRow?['telefone_localizador']?.toString(),
      telefoneLocalizadorExpiraEm:
          DateTime.tryParse(marketplacePedidoRow?['telefone_localizador_expira_em']?.toString() ?? '')?.toLocal(),
      codigoRetiradaExibicao: marketplacePedidoRow?['codigo_retirada_exibicao']?.toString(),
      linkConfirmacaoEntrega: marketplacePedidoRow?['link_confirmacao_entrega']?.toString(),
      statusPagamento: row['status_pagamento']?.toString(),
      mercadoPagoPaymentTypeId: metadata['mercadoPagoPaymentTypeId']?.toString(),
      mercadoPagoInstallments: (metadata['mercadoPagoInstallments'] as num?)?.toInt(),
      mercadoPagoPaymentId: metadata['mercadoPagoPaymentId']?.toString(),
      mercadoPagoRefundId: metadata['mercadoPagoRefundId']?.toString(),
      mercadoPagoEstornadoEm: DateTime.tryParse(metadata['estornadoEm']?.toString() ?? '')?.toLocal(),
      mercadoPagoTaxa: (metadata['mercadoPagoTaxa'] as num?)?.toDouble(),
      custoEmbalagem: (row['custo_embalagem_valor'] as num?)?.toDouble(),
      taxaMaquininha: (row['taxa_maquininha_valor'] as num?)?.toDouble(),
      custoEntregaReal: (row['custo_entrega_valor'] as num?)?.toDouble(),
      taxaComissaoMarketplace: (marketplacePedidoRow?['taxa_comissao'] as num?)?.toDouble(),
      taxaGatewayMarketplace: (marketplacePedidoRow?['taxa_gateway'] as num?)?.toDouble(),
      taxaServicoCliente: (marketplacePedidoRow?['taxa_servico_cliente'] as num?)?.toDouble(),
      campanhaMarketplace: marketplacePedidoRow?['campanha_marketplace']?.toString(),
      cupomMarketplace: marketplacePedidoRow?['cupom_marketplace']?.toString(),
      politicaSubstituicao: marketplacePedidoRow?['politica_substituicao']?.toString(),
      entregadorTipo: marketplacePedidoRow?['entregador_tipo']?.toString(),
      agendado: marketplacePedidoRow?['agendado'] as bool? ?? false,
      entregaPrevistaInicio:
          DateTime.tryParse(marketplacePedidoRow?['entrega_prevista_inicio']?.toString() ?? '')?.toLocal(),
      entregaPrevistaFim:
          DateTime.tryParse(marketplacePedidoRow?['entrega_prevista_fim']?.toString() ?? '')?.toLocal(),
      agendadoManualmente: metadata['agendado'] as bool? ?? false,
      previsaoEntregaInicio: DateTime.tryParse(row['previsao_entrega_inicio']?.toString() ?? '')?.toLocal(),
      previsaoEntregaFim: DateTime.tryParse(row['previsao_entrega_fim']?.toString() ?? '')?.toLocal(),
      modalidadeEntrega: metadata['modalidadeEntrega']?.toString(),
    );
  }
}
