/// Uma linha do extrato de estoque de um produto (tabela
/// `movimentacoes_estoque`, lida pela RPC `listar_movimentacoes_estoque`).
/// Gravada só por trigger no banco — qualquer mudança de saldo entra aqui,
/// inclusive as que não vieram do app (n8n, iFood, kit, granel).
class MovimentacaoEstoque {
  final String id;
  final DateTime criadoEm;
  final String tipo;
  final int delta;
  final int quantidadeAnterior;
  final int quantidadeNova;

  /// 'kit' / 'granel' quando o saldo mudou por reflexo de outro produto
  /// (componente do kit vendido, pai/filho do granel).
  final String? sincronizacao;
  final String? motivo;
  final String? observacao;
  final String? usuarioNome;
  final String? origemTecnica;
  final String? referenciaTipo;
  final String? referenciaId;
  final String? referenciaDescricao;
  final String? canal;

  /// Só vem preenchida quando o tipo é 'desconhecido': o comando SQL que
  /// mudou o saldo sem dizer o porquê — pista pra achar o caminho esquecido.
  final String? consulta;

  const MovimentacaoEstoque({
    required this.id,
    required this.criadoEm,
    required this.tipo,
    required this.delta,
    required this.quantidadeAnterior,
    required this.quantidadeNova,
    this.sincronizacao,
    this.motivo,
    this.observacao,
    this.usuarioNome,
    this.origemTecnica,
    this.referenciaTipo,
    this.referenciaId,
    this.referenciaDescricao,
    this.canal,
    this.consulta,
  });

  factory MovimentacaoEstoque.fromSupabase(Map<String, dynamic> row) => MovimentacaoEstoque(
        id: row['id'] as String,
        criadoEm: DateTime.parse(row['created_at'] as String).toLocal(),
        tipo: row['tipo'] as String,
        delta: (row['delta'] as num).toInt(),
        quantidadeAnterior: (row['quantidade_anterior'] as num).toInt(),
        quantidadeNova: (row['quantidade_nova'] as num).toInt(),
        sincronizacao: row['sincronizacao'] as String?,
        motivo: row['motivo'] as String?,
        observacao: row['observacao'] as String?,
        usuarioNome: row['usuario_nome'] as String?,
        origemTecnica: row['origem_tecnica'] as String?,
        referenciaTipo: row['referencia_tipo'] as String?,
        referenciaId: row['referencia_id'] as String?,
        referenciaDescricao: row['referencia_descricao'] as String?,
        canal: row['canal'] as String?,
        consulta: row['consulta'] as String?,
      );

  String get tipoLegivel => switch (tipo) {
        'venda' => 'Venda',
        'cancelamento_venda' => 'Venda cancelada (devolvido)',
        'ajuste_pedido_ifood' => 'Ajuste de pedido iFood',
        'entrada_nota' => 'Entrada de nota fiscal',
        'entrada_manual' => 'Entrada manual',
        'ajuste_manual' => 'Ajuste manual',
        'saldo_inicial' => 'Saldo inicial (cadastro)',
        'inicio_historico' => 'Início do histórico',
        'vinculo_granel' => 'Vínculo de granel',
        'composicao_kit' => 'Composição do kit alterada',
        'sincronizacao' => 'Sincronização automática',
        'desconhecido' => 'Origem não identificada',
        _ => tipo,
      };
}

/// Motivos do ajuste manual — o código vai pro banco, o rótulo pra tela.
const motivosAjusteEstoque = <String, String>{
  'contagem': 'Contagem física (conferi na prateleira)',
  'avaria': 'Avaria / produto danificado',
  'vencimento': 'Perda por vencimento',
  'uso_interno': 'Uso interno / brinde',
  'devolucao_cliente': 'Devolução de cliente',
  'correcao_cadastro': 'Correção de erro de cadastro',
  'importacao_planilha': 'Importação de planilha',
  'outro': 'Outro',
};

String rotuloMotivoAjusteEstoque(String? codigo) =>
    codigo == null ? '' : (motivosAjusteEstoque[codigo] ?? codigo);
