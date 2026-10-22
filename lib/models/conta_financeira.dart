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
  });

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

  const MovimentacaoFinanceira({
    required this.id,
    required this.contaId,
    required this.data,
    required this.entrada,
    required this.valor,
    this.descricao,
    required this.statusConferencia,
  });

  factory MovimentacaoFinanceira.fromSupabase(Map<String, dynamic> row) => MovimentacaoFinanceira(
        id: row['id'] as String,
        contaId: row['conta_id'] as String,
        data: DateTime.parse(row['data'] as String),
        entrada: row['tipo'] == 'entrada',
        valor: (row['valor'] as num).toDouble(),
        descricao: row['descricao'] as String?,
        statusConferencia: row['status_conferencia'] as String? ?? 'pendente',
      );
}

class ResultadoImportacao {
  final int novas;
  final int repetidas;
  final double? saldoFinal;

  const ResultadoImportacao({required this.novas, required this.repetidas, this.saldoFinal});
}
