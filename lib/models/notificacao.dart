/// Tipos de notificação — ver as triggers/jobs no banco (migrations
/// `trigger_notificacao_estoque_baixo`, `job_notificacao_pedido_parado`,
/// `job_notificacao_despesa_vencendo`, `trigger_notificacao_avaliacao_disputa_sync`)
/// que são a única fonte que grava nessa tabela.
class TipoNotificacao {
  static const estoqueBaixo = 'estoque_baixo';
  static const estoqueZerado = 'estoque_zerado';
  static const pedidoParado = 'pedido_parado';
  static const despesaVencendo = 'despesa_vencendo';
  static const despesaVencida = 'despesa_vencida';
  static const avaliacaoRecebida = 'avaliacao_recebida';
  static const disputaRecebida = 'disputa_recebida';
  static const syncFalhou = 'sync_falhou';
  static const custoAlterado = 'custo_alterado';
}

/// Uma categoria configurável no painel de preferências de notificação —
/// cobre 1 ou 2 `TipoNotificacao` (estoque baixo/zerado e despesa
/// vencendo/vencida compartilham a mesma chave, pois é o mesmo evento
/// de negócio em intensidades diferentes; não faz sentido separar).
class CategoriaNotificacao {
  final String chave;
  final String titulo;
  final String descricao;

  const CategoriaNotificacao({required this.chave, required this.titulo, required this.descricao});
}

const categoriasNotificacaoDisponiveis = [
  CategoriaNotificacao(
    chave: TipoNotificacao.estoqueBaixo,
    titulo: 'Estoque baixo ou zerado',
    descricao: 'Quando um produto atinge o estoque mínimo ou acaba.',
  ),
  CategoriaNotificacao(
    chave: TipoNotificacao.pedidoParado,
    titulo: 'Pedido parado',
    descricao: 'Quando um pedido fica mais de 15 minutos sem avançar.',
  ),
  CategoriaNotificacao(
    chave: TipoNotificacao.despesaVencendo,
    titulo: 'Despesas a vencer ou vencidas',
    descricao: 'Aviso diário de despesas vencendo amanhã ou já vencidas.',
  ),
  CategoriaNotificacao(
    chave: TipoNotificacao.avaliacaoRecebida,
    titulo: 'Avaliação recebida',
    descricao: 'Quando um cliente avalia um pedido no marketplace.',
  ),
  CategoriaNotificacao(
    chave: TipoNotificacao.disputaRecebida,
    titulo: 'Disputa recebida',
    descricao: 'Quando o marketplace abre uma contestação sobre um pedido.',
  ),
  CategoriaNotificacao(
    chave: TipoNotificacao.syncFalhou,
    titulo: 'Falha ao sincronizar produto',
    descricao: 'Quando um produto falha ao sincronizar com o marketplace.',
  ),
  CategoriaNotificacao(
    chave: TipoNotificacao.custoAlterado,
    titulo: 'Custo do produto alterado',
    descricao: 'Quando o custo de um produto muda (ex: importação de nota fiscal) — avisa pra revisar o preço de venda.',
  ),
];

/// Notificação in-app (linha da tabela `notificacoes`). Gerada só por
/// triggers/jobs `SECURITY DEFINER` no banco — o app nunca insere aqui,
/// só lê e marca como lida.
class Notificacao {
  final String id;
  final String tipo;
  final String titulo;
  final String mensagem;
  final String? entidadeTipo; // 'produto' | 'pedido' | 'despesa'
  final String? entidadeId;
  final bool lida;
  final DateTime createdAt;

  Notificacao({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.mensagem,
    this.entidadeTipo,
    this.entidadeId,
    required this.lida,
    required this.createdAt,
  });

  factory Notificacao.fromSupabase(Map<String, dynamic> row) {
    return Notificacao(
      id: row['id'] as String,
      tipo: row['tipo']?.toString() ?? '',
      titulo: row['titulo']?.toString() ?? '',
      mensagem: row['mensagem']?.toString() ?? '',
      entidadeTipo: row['entidade_tipo']?.toString(),
      entidadeId: row['entidade_id']?.toString(),
      lida: row['lida'] as bool? ?? false,
      createdAt: DateTime.parse(row['created_at'].toString()),
    );
  }
}
