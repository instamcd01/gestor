/// Tipo de desconto — percentual do valor elegível ou valor fixo em R$.
enum TipoDescontoCupom { percentual, fixo }

/// O que o cupom desconta: o pedido inteiro, ou só uma fatia dele
/// (categoria/subcategoria/marca/produtos específicos).
enum EscopoCupom { pedido, categoria, subcategoria, marca, produtos }

TipoDescontoCupom tipoDescontoDeTexto(String? texto) =>
    texto == 'fixo' ? TipoDescontoCupom.fixo : TipoDescontoCupom.percentual;

String tipoDescontoParaTexto(TipoDescontoCupom tipo) =>
    tipo == TipoDescontoCupom.fixo ? 'fixo' : 'percentual';

EscopoCupom escopoDeTexto(String? texto) {
  switch (texto) {
    case 'categoria':
      return EscopoCupom.categoria;
    case 'subcategoria':
      return EscopoCupom.subcategoria;
    case 'marca':
      return EscopoCupom.marca;
    case 'produtos':
      return EscopoCupom.produtos;
    default:
      return EscopoCupom.pedido;
  }
}

String escopoParaTexto(EscopoCupom escopo) => escopo.name;

class Cupom {
  final String? id;
  final String codigo;
  final TipoDescontoCupom tipoDesconto;
  final double valor;
  final EscopoCupom escopoTipo;
  final String? escopoValor;
  final String? clienteId;
  final String? clienteNome;
  final String? vendedorId;
  final String? vendedorNome;
  final String origem; // manual | auto_cliente | auto_vendedor
  final double? valorMinimoPedido;
  final int? usoMaximo;
  final int usos;
  final int? usoMaximoPorCliente;
  final DateTime? dataInicio;
  final DateTime? dataExpiracao;
  final bool ativo;
  final String? descricao;

  Cupom({
    this.id,
    required this.codigo,
    required this.tipoDesconto,
    required this.valor,
    this.escopoTipo = EscopoCupom.pedido,
    this.escopoValor,
    this.clienteId,
    this.clienteNome,
    this.vendedorId,
    this.vendedorNome,
    this.origem = 'manual',
    this.valorMinimoPedido,
    this.usoMaximo,
    this.usos = 0,
    this.usoMaximoPorCliente,
    this.dataInicio,
    this.dataExpiracao,
    this.ativo = true,
    this.descricao,
  });

  factory Cupom.fromSupabase(Map<String, dynamic> row) {
    return Cupom(
      id: row['id'] as String?,
      codigo: row['codigo']?.toString() ?? '',
      tipoDesconto: tipoDescontoDeTexto(row['tipo_desconto']?.toString()),
      valor: (row['valor'] as num?)?.toDouble() ?? 0,
      escopoTipo: escopoDeTexto(row['escopo_tipo']?.toString()),
      escopoValor: row['escopo_valor']?.toString(),
      clienteId: row['cliente_id'] as String?,
      clienteNome: row['clientes'] is Map ? (row['clientes']['nome']?.toString()) : null,
      vendedorId: row['vendedor_id'] as String?,
      vendedorNome: row['usuarios'] is Map ? (row['usuarios']['nome']?.toString()) : null,
      origem: row['origem']?.toString() ?? 'manual',
      valorMinimoPedido: (row['valor_minimo_pedido'] as num?)?.toDouble(),
      usoMaximo: row['uso_maximo'] as int?,
      usos: row['usos'] as int? ?? 0,
      usoMaximoPorCliente: row['uso_maximo_por_cliente'] as int?,
      dataInicio: row['data_inicio'] != null ? DateTime.parse(row['data_inicio']) : null,
      dataExpiracao: row['data_expiracao'] != null ? DateTime.parse(row['data_expiracao']) : null,
      ativo: row['ativo'] as bool? ?? true,
      descricao: row['descricao']?.toString(),
    );
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'codigo': codigo.trim().toUpperCase(),
      'tipo_desconto': tipoDescontoParaTexto(tipoDesconto),
      'valor': valor,
      'escopo_tipo': escopoParaTexto(escopoTipo),
      'escopo_valor': escopoValor,
      'cliente_id': clienteId,
      'vendedor_id': vendedorId,
      'origem': origem,
      'valor_minimo_pedido': valorMinimoPedido,
      'uso_maximo': usoMaximo,
      'uso_maximo_por_cliente': usoMaximoPorCliente,
      'data_inicio': dataInicio?.toIso8601String(),
      'data_expiracao': dataExpiracao?.toIso8601String(),
      'ativo': ativo,
      'descricao': descricao,
    };
  }
}

/// Resultado de validar_cupom — mesma função Postgres usada pelo site.
class ResultadoValidacaoCupom {
  final bool valido;
  final String? motivo;
  final String? cupomId;
  final double valorDesconto;
  final String? vendedorId;

  ResultadoValidacaoCupom({
    required this.valido,
    this.motivo,
    this.cupomId,
    this.valorDesconto = 0,
    this.vendedorId,
  });

  factory ResultadoValidacaoCupom.fromSupabase(Map<String, dynamic> row) {
    return ResultadoValidacaoCupom(
      valido: row['valido'] as bool? ?? false,
      motivo: row['motivo']?.toString(),
      cupomId: row['cupom_id'] as String?,
      valorDesconto: (row['valor_desconto'] as num?)?.toDouble() ?? 0,
      vendedorId: row['vendedor_id'] as String?,
    );
  }
}
