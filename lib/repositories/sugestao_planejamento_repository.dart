import '../config/supabase_config.dart';
import '../models/pedido_compra.dart';
import '../models/sugestao_planejamento.dart';
import 'pedido_compra_repository.dart';

/// Busca as sugestões automáticas da aba "Sugestões" do Planejamento —
/// cada fonte é independente (uma falhar não deve derrubar as outras),
/// por isso o provider chama estes métodos separadamente com Future.wait
/// + captura de erro por fonte, não um método único que agrega tudo.
class SugestaoPlanejamentoRepository {
  final PedidoCompraRepository _pedidoCompraRepository = PedidoCompraRepository();

  /// Reaproveita a RPC `sugestoes_pedido_compra` já usada pela feature de
  /// Pedido de Compra a Fornecedor — não duplica a lógica de estoque
  /// baixo/venda média, só reexpõe o mesmo resultado aqui.
  Future<List<SugestaoCompra>> buscarSugestoesCompra({required String empresaId}) {
    return _pedidoCompraRepository.buscarSugestoes(empresaId: empresaId);
  }

  /// RPC `clientes_devido_recompra` — a ordem devolvida pelo Postgres não é
  /// garantida ao passar por uma função de tabela via PostgREST, então
  /// reordena aqui (mais tempo parado primeiro) em vez de confiar no
  /// `order by` interno da função.
  Future<List<SugestaoRecompra>> buscarSugestoesRecompra({required String empresaId}) async {
    final data = await supabase.rpc('clientes_devido_recompra', params: {'p_empresa_id': empresaId});
    final lista = (data as List).map((row) => SugestaoRecompra.fromSupabase(row as Map<String, dynamic>)).toList();
    lista.sort((a, b) => b.diasDesdeUltimaCompra.compareTo(a.diasDesdeUltimaCompra));
    return lista;
  }

  /// RPC `contatos_campanha_parados` — mesma ressalva de ordenação da
  /// recompra, reordena aqui (mais tempo parado primeiro).
  Future<List<SugestaoContatoParado>> buscarContatosParados({required String empresaId}) async {
    final data = await supabase.rpc('contatos_campanha_parados', params: {'p_empresa_id': empresaId});
    final lista =
        (data as List).map((row) => SugestaoContatoParado.fromSupabase(row as Map<String, dynamic>)).toList();
    lista.sort((a, b) => b.diasParado.compareTo(a.diasParado));
    return lista;
  }

  /// Leitura direta de `posts_conteudo` (status pendente de aprovação) —
  /// sem RPC, sem lógica própria. A tabela existe mas fica vazia até a
  /// automação `gestor-conteudo-social` ser implantada; isso é esperado,
  /// não um erro — a UI deve mostrar um aviso explicando, não só "vazio".
  Future<List<PostConteudoPendente>> buscarConteudoPendente({required String empresaId}) async {
    final data = await supabase
        .from('posts_conteudo')
        .select('id, pilar, formato, tema, canal, criado_em')
        .eq('empresa_id', empresaId)
        .eq('status', 'pendente_aprovacao')
        .order('criado_em', ascending: true);
    return (data as List).map((row) => PostConteudoPendente.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  /// Marca que o lembrete de recompra foi enviado — reaproveita a RPC já
  /// existente (`marcar_lembrete_recompra_enviado`), usada hoje pelo
  /// fluxo de WhatsApp via n8n. Chamada quando o usuário adiciona a
  /// sugestão ao plano, pra não repetir a mesma sugestão amanhã (respeita
  /// o cooldown já embutido em `clientes_devido_recompra`).
  Future<void> marcarLembreteRecompraEnviado(String clienteId) async {
    await supabase.rpc('marcar_lembrete_recompra_enviado', params: {'p_cliente_id': clienteId});
  }
}
