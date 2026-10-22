/// Conta da loja onde o dinheiro entra/sai (`contas_financeiras`) — banco,
/// maquininha, pagamento online ou caixa físico. Cada loja cadastra as
/// suas; nada aqui é fixo da Delivery Pet.
class ContaFinanceira {
  final String id;
  final String nome;
  final String tipo;
  final String provedor;
  final String conector;
  final String? identificacao;
  final bool ativa;
  final double? saldoAtual;
  final DateTime? saldoAtualizadoEm;
  final DateTime? ultimaSincronizacaoEm;
  final String? ultimoErro;

  const ContaFinanceira({
    required this.id,
    required this.nome,
    required this.tipo,
    required this.provedor,
    required this.conector,
    this.identificacao,
    this.ativa = true,
    this.saldoAtual,
    this.saldoAtualizadoEm,
    this.ultimaSincronizacaoEm,
    this.ultimoErro,
  });

  /// Atualiza sozinha (n8n/serviço de bancos) — sem importação de arquivo.
  bool get automatica => conector == 'api';

  static const tipos = {
    'banco': 'Banco',
    'maquininha': 'Maquininha',
    'pagamento_online': 'Pagamento online',
    'caixa': 'Caixa físico',
  };

  /// Provedores com conector próprio planejado; qualquer outro entra como
  /// "outro" e usa importação de arquivo.
  static const provedores = {
    'inter': 'Banco Inter',
    'ton': 'Ton',
    'stone': 'Stone',
    'mercado_pago': 'Mercado Pago',
    'outro': 'Outro',
  };

  String get tipoRotulo => tipos[tipo] ?? tipo;
  String get provedorRotulo => provedores[provedor] ?? provedor;

  factory ContaFinanceira.fromSupabase(Map<String, dynamic> row) => ContaFinanceira(
        id: row['id'] as String,
        nome: row['nome'] as String,
        tipo: row['tipo'] as String,
        provedor: row['provedor'] as String? ?? 'outro',
        conector: row['conector'] as String? ?? 'arquivo',
        identificacao: row['identificacao'] as String?,
        ativa: row['ativa'] as bool? ?? true,
        saldoAtual: (row['saldo_atual'] as num?)?.toDouble(),
        saldoAtualizadoEm: row['saldo_atualizado_em'] != null ? DateTime.parse(row['saldo_atualizado_em'] as String).toLocal() : null,
        ultimaSincronizacaoEm:
            row['ultima_sincronizacao_em'] != null ? DateTime.parse(row['ultima_sincronizacao_em'] as String).toLocal() : null,
        ultimoErro: row['ultimo_erro'] as String?,
      );
}

/// "Onde cai cada coisa" (`contas_financeiras_destinos`). [modulos]: só
/// aparece pra loja que tem o canal (iFood, site...); null = toda loja.
class OrigemDinheiro {
  final String slug;
  final String rotulo;
  final List<String>? modulos;

  const OrigemDinheiro(this.slug, this.rotulo, {this.modulos});

  static const todas = [
    OrigemDinheiro('pix', 'Pix da loja'),
    OrigemDinheiro('maquininha', 'Maquininha (cartão)'),
    OrigemDinheiro('dinheiro', 'Dinheiro'),
    OrigemDinheiro('boleto', 'Boleto'),
    OrigemDinheiro('site', 'Pagamentos do site', modulos: ['loja_online']),
    OrigemDinheiro('repasse_ifood', 'Repasse do iFood', modulos: ['ifood']),
    OrigemDinheiro('repasse_99food', 'Repasse do 99Food', modulos: ['99food']),
  ];
}

class MovimentacaoFinanceira {
  final String id;
  final String contaId;
  final DateTime data;
  final bool entrada;
  final double valor;
  final String? descricao;
  final String statusConferencia;

  /// Só conector por API: taxa descontada e quando o dinheiro fica
  /// disponível (Mercado Pago libera cartão depois da venda).
  final double? taxa;
  final bool? liberado;
  final DateTime? liberacao;

  const MovimentacaoFinanceira({
    required this.id,
    required this.contaId,
    required this.data,
    required this.entrada,
    required this.valor,
    this.descricao,
    required this.statusConferencia,
    this.taxa,
    this.liberado,
    this.liberacao,
  });

  bool get conferida => statusConferencia == 'conferida';

  factory MovimentacaoFinanceira.fromSupabase(Map<String, dynamic> row) => MovimentacaoFinanceira(
        id: row['id'] as String,
        contaId: row['conta_id'] as String,
        data: DateTime.parse(row['data'] as String),
        entrada: row['tipo'] == 'entrada',
        valor: (row['valor'] as num).toDouble(),
        descricao: row['descricao'] as String?,
        statusConferencia: row['status_conferencia'] as String? ?? 'pendente',
        taxa: ((row['dados_brutos'] as Map?)?['taxa'] as num?)?.toDouble(),
        liberado: (row['dados_brutos'] as Map?)?['liberado'] as bool?,
        liberacao: (row['dados_brutos'] as Map?)?['liberacao'] != null
            ? DateTime.tryParse((row['dados_brutos'] as Map)['liberacao'] as String)?.toLocal()
            : null,
      );
}

/// Venda no cartão vinda da maquininha (`vendas_cartao`): o que vai cair,
/// com a taxa real da adquirente e o pedido do Gestor quando casou.
class VendaCartao {
  final String id;
  final DateTime capturadaEm;
  final String tipo;
  final String? bandeira;
  final int parcelas;
  final double valorBruto;
  final double valorLiquido;
  final double taxa;
  final DateTime? previsaoPagamento;
  final double valorCancelado;
  final String? vinculo;
  final int? pedidoNumero;

  const VendaCartao({
    required this.id,
    required this.capturadaEm,
    required this.tipo,
    this.bandeira,
    required this.parcelas,
    required this.valorBruto,
    required this.valorLiquido,
    required this.taxa,
    this.previsaoPagamento,
    this.valorCancelado = 0,
    this.vinculo,
    this.pedidoNumero,
  });

  String get tipoRotulo => switch (tipo) {
        'debito' => 'Débito',
        'credito' => parcelas > 1 ? 'Crédito ${parcelas}x' : 'Crédito',
        'pre_pago' => 'Pré-pago',
        'voucher' => 'Voucher',
        _ => 'Cartão',
      };

  double get taxaPercentual => valorBruto == 0 ? 0 : taxa / valorBruto * 100;

  factory VendaCartao.fromSupabase(Map<String, dynamic> row) => VendaCartao(
        id: row['id'] as String,
        capturadaEm: DateTime.parse(row['capturada_em'] as String).toLocal(),
        tipo: row['tipo'] as String,
        bandeira: row['bandeira'] as String?,
        parcelas: (row['parcelas'] as num?)?.toInt() ?? 1,
        valorBruto: (row['valor_bruto'] as num).toDouble(),
        valorLiquido: (row['valor_liquido'] as num).toDouble(),
        taxa: (row['taxa'] as num?)?.toDouble() ?? 0,
        previsaoPagamento: row['previsao_pagamento'] != null ? DateTime.parse(row['previsao_pagamento'] as String) : null,
        valorCancelado: (row['valor_cancelado'] as num?)?.toDouble() ?? 0,
        vinculo: row['vinculo'] as String?,
        pedidoNumero: ((row['pedido'] as Map?)?['numero_sequencial'] as num?)?.toInt(),
      );
}

/// Movimentação que a classificação automática não explicou (status
/// pendente/sugerida) — com a explicação do porquê em [sugestao].
class Achado {
  final String id;
  final String contaNome;
  final DateTime data;
  final bool entrada;
  final double valor;
  final String? descricao;
  final String? sugestao;

  const Achado({
    required this.id,
    required this.contaNome,
    required this.data,
    required this.entrada,
    required this.valor,
    this.descricao,
    this.sugestao,
  });

  /// Texto sugerido pra "fazer sempre assim": a descrição sem números
  /// (datas, documentos, valores mudam a cada lançamento).
  String get textoRegra => (descricao ?? '')
      .replaceAll(RegExp(r'[\d./-]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((p) => p.length > 1)
      .take(4)
      .join(' ');

  factory Achado.fromSupabase(Map<String, dynamic> row) => Achado(
        id: row['id'] as String,
        contaNome: (row['conta'] as Map?)?['nome'] as String? ?? '',
        data: DateTime.parse(row['data'] as String),
        entrada: row['tipo'] == 'entrada',
        valor: (row['valor'] as num).toDouble(),
        descricao: row['descricao'] as String?,
        sugestao: row['sugestao'] as String?,
      );
}

class ResultadoImportacao {
  final int novas;
  final int repetidas;
  final double? saldoFinal;

  const ResultadoImportacao({required this.novas, required this.repetidas, this.saldoFinal});
}
