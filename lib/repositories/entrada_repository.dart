import '../config/supabase_config.dart';
import '../models/despesa.dart';
import '../models/entrada.dart';
import 'despesa_repository.dart';

/// Grava uma entrada de estoque (a partir de NF-e importada ou lançamento
/// manual) + seus itens + uma `Despesa` por parcela/boleto. A soma no
/// `estoque` acontece via trigger (`aplicar_entrada_estoque`) disparada
/// pelo insert em `itens_entrada` — este repository não mexe em estoque
/// diretamente.
class EntradaRepository {
  static const _selectComFornecedor = '*, fornecedor:fornecedores(*)';

  Future<List<Entrada>> listar() async {
    final data = await supabase
        .from('entradas')
        .select(_selectComFornecedor)
        .order('data_entrada', ascending: false);

    return (data as List).map((row) => Entrada.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  Future<Entrada> criar({
    required Entrada entrada,
    required String empresaId,
    String? fornecedorId,
    String? pedidoCompraId,
    List<ParcelaEntrada> parcelas = const [],
    String? criadoPor,
  }) async {
    final entradaRow = await supabase
        .from('entradas')
        .insert({
          ...entrada.toSupabaseMap(fornecedorId: fornecedorId, pedidoCompraId: pedidoCompraId),
          'empresa_id': empresaId,
        })
        .select(_selectComFornecedor)
        .single();
    final entradaId = entradaRow['id'] as String;

    if (entrada.itens.isNotEmpty) {
      await supabase.from('itens_entrada').insert(
            entrada.itens.map((item) => {...item.toSupabaseMap(), 'entrada_id': entradaId}).toList(),
          );
    }

    final despesaRepository = DespesaRepository();
    for (var i = 0; i < parcelas.length; i++) {
      final parcela = parcelas[i];
      final sufixoParcela = parcelas.length > 1 ? ' — parcela ${parcela.numero}/${parcelas.length}' : '';
      await despesaRepository.criar(
        Despesa(
          descricao: 'NF ${entrada.nfeNumero ?? "s/ número"}$sufixoParcela',
          categoria: 'Fornecedores',
          valor: parcela.valor,
          dataVencimento: parcela.vencimento,
          metodoPagamento: 'Boleto',
          codigoBarrasBoleto: parcela.codigoBarras,
        ),
        empresaId: empresaId,
        fornecedorId: fornecedorId,
        criadoPor: criadoPor,
      );
    }

    return Entrada.fromSupabase(entradaRow);
  }

  /// Leitura enxuta pra montar o gráfico "custo médio por fornecedor ao
  /// longo do tempo" — só os campos usados na agregação (feita em Dart na
  /// tela, não aqui), não o `Entrada`/`ItemEntrada` completo. Só itens já
  /// casados com produto (`produto_id` preenchido): custo de item ainda
  /// pendente de vínculo não é custo real de compra.
  Future<List<({String fornecedorId, String fornecedorNome, DateTime dataEntrada, double custoUnitario, double quantidade})>>
      buscarCustosPorFornecedor({required DateTime desde}) async {
    // Filtro de data e de fornecedor-nulo aplicado em Dart (não no
    // PostgREST) — filtrar por coluna de recurso aninhado tem sintaxe
    // própria/frágil no cliente Supabase; a tabela é pequena o bastante
    // (só itens de NF-e importada) pra não valer o risco de um filtro
    // remoto errado silenciosamente vazio.
    final data = await supabase
        .from('itens_entrada')
        .select('custo_unitario, quantidade, entrada:entradas(data_entrada, fornecedor_id, fornecedor:fornecedores(id, nome))')
        .not('produto_id', 'is', null);

    final resultado = <({String fornecedorId, String fornecedorNome, DateTime dataEntrada, double custoUnitario, double quantidade})>[];
    for (final row in data as List) {
      final entrada = row['entrada'] as Map<String, dynamic>?;
      final fornecedor = entrada?['fornecedor'] as Map<String, dynamic>?;
      if (entrada == null || fornecedor == null) continue;
      final dataEntrada = DateTime.parse(entrada['data_entrada'].toString());
      if (dataEntrada.isBefore(desde)) continue;
      resultado.add((
        fornecedorId: fornecedor['id'] as String,
        fornecedorNome: fornecedor['nome']?.toString() ?? '',
        dataEntrada: dataEntrada,
        custoUnitario: (row['custo_unitario'] as num?)?.toDouble() ?? 0.0,
        quantidade: (row['quantidade'] as num?)?.toDouble() ?? 0.0,
      ));
    }
    return resultado;
  }

  /// Último custo unitário efetivamente pago por produto (não importa o
  /// fornecedor) — usado pra avisar na montagem de um pedido de compra
  /// quando o custo atual está divergindo do que foi pago da última vez
  /// ("comprou por R$8 a última vez, esse fornecedor está cobrando R$11").
  /// Só itens já casados com produto (`produto_id` preenchido).
  Future<Map<String, ({double custoUnitario, String fornecedorNome, DateTime dataEntrada})>> buscarUltimoCustoPorProduto(
    List<String> produtoIds,
  ) async {
    if (produtoIds.isEmpty) return {};

    final data = await supabase
        .from('itens_entrada')
        .select('produto_id, custo_unitario, entrada:entradas(data_entrada, fornecedor:fornecedores(nome))')
        .inFilter('produto_id', produtoIds);

    final resultado = <String, ({double custoUnitario, String fornecedorNome, DateTime dataEntrada})>{};
    for (final row in data as List) {
      final produtoId = row['produto_id'] as String?;
      final entrada = row['entrada'] as Map<String, dynamic>?;
      if (produtoId == null || entrada == null) continue;
      final dataEntrada = DateTime.parse(entrada['data_entrada'].toString());
      final atual = resultado[produtoId];
      if (atual != null && !dataEntrada.isAfter(atual.dataEntrada)) continue;

      final fornecedor = entrada['fornecedor'] as Map<String, dynamic>?;
      resultado[produtoId] = (
        custoUnitario: (row['custo_unitario'] as num?)?.toDouble() ?? 0.0,
        fornecedorNome: fornecedor?['nome']?.toString() ?? '—',
        dataEntrada: dataEntrada,
      );
    }
    return resultado;
  }
}
