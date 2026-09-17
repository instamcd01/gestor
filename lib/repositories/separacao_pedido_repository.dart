import '../config/supabase_config.dart';

/// Separação de pedido de Mercado na iFood (Picking API) — trocar/remover
/// item em falta na hora de separar o pedido. Todas as escritas aqui
/// disparam triggers no banco que chamam a API de verdade via n8n; o app
/// nunca fala com a iFood diretamente.
class SeparacaoPedidoRepository {
  Future<void> iniciar(String marketplacePedidoId) async {
    await supabase
        .from('marketplace_pedidos')
        .update({'separacao_status': 'separando', 'separacao_erro': null}).eq('id', marketplacePedidoId);
  }

  Future<void> finalizar(String marketplacePedidoId) async {
    await supabase
        .from('marketplace_pedidos')
        .update({'separacao_status': 'finalizada', 'separacao_erro': null}).eq('id', marketplacePedidoId);
  }

  Future<void> removerItem({required String marketplacePedidoId, required String itemPedidoId}) async {
    await supabase.from('marketplace_separacao_acoes').insert({
      'marketplace_pedido_id': marketplacePedidoId,
      'item_pedido_id': itemPedidoId,
      'tipo_acao': 'remover',
    });
  }

  Future<void> substituirItem({
    required String marketplacePedidoId,
    required String itemPedidoId,
    required String produtoSubstitutoId,
    required double quantidade,
  }) async {
    await supabase.from('marketplace_separacao_acoes').insert({
      'marketplace_pedido_id': marketplacePedidoId,
      'item_pedido_id': itemPedidoId,
      'tipo_acao': 'substituir',
      'produto_substituto_id': produtoSubstitutoId,
      'quantidade': quantidade,
    });
  }

  /// Adiciona um item que não veio no pedido original (ex: cliente pediu por
  /// telefone durante a separação). `produtoId` reaproveita a mesma coluna
  /// `produto_substituto_id` usada em `substituirItem` — o trigger
  /// `notificar_separacao_acao` só usa esse campo pra resolver EAN/preço,
  /// não importa se é "substituto" ou "novo item".
  Future<void> adicionarItem({
    required String marketplacePedidoId,
    required String produtoId,
    required double quantidade,
  }) async {
    await supabase.from('marketplace_separacao_acoes').insert({
      'marketplace_pedido_id': marketplacePedidoId,
      'tipo_acao': 'adicionar',
      'produto_substituto_id': produtoId,
      'quantidade': quantidade,
    });
  }

  /// Muda a quantidade de um item que já está no pedido (sem trocar de
  /// produto) — ex: cliente tinha pedido 3un mas só tem 2 disponíveis.
  Future<void> modificarItem({
    required String marketplacePedidoId,
    required String itemPedidoId,
    required double quantidade,
  }) async {
    await supabase.from('marketplace_separacao_acoes').insert({
      'marketplace_pedido_id': marketplacePedidoId,
      'item_pedido_id': itemPedidoId,
      'tipo_acao': 'modificar',
      'quantidade': quantidade,
    });
  }

  /// Estado real de cada ação registrada — o app só grava a intenção na
  /// hora (`status='pendente'`), quem confirma se a iFood aceitou ou
  /// rejeitou é o n8n de forma assíncrona (`aplicada`/`erro` + mensagem
  /// real). Nunca assumir sucesso só porque o insert deu certo.
  Future<List<Map<String, dynamic>>> buscarAcoes(String marketplacePedidoId) async {
    final data = await supabase
        .from('marketplace_separacao_acoes')
        .select('*, produtos:produto_substituto_id(nome)')
        .eq('marketplace_pedido_id', marketplacePedidoId)
        .order('created_at');
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// Itens conforme a própria iFood confirmou na consulta automática que
  /// roda logo depois de finalizar a separação — só existe depois de
  /// `finalizar()`, é a fonte de verdade real (não o que o app assumiu).
  Future<Map<String, dynamic>?> buscarConfirmacaoPosSeparacao(String marketplacePedidoId) async {
    return await supabase
        .from('marketplace_pedidos')
        .select('itens_confirmados_ifood, separacao_confirmada_em')
        .eq('id', marketplacePedidoId)
        .maybeSingle();
  }
}
