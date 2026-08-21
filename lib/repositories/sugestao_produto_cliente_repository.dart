import '../config/supabase_config.dart';
import '../models/sugestao_produto_cliente.dart';

/// Sugestões de produto enviadas pelo cliente no site, quando a busca não
/// acha nada — RLS já filtra pela empresa do usuário logado. Cliente nunca
/// escreve aqui direto: passa pela RPC `enviar_sugestao_produto_cliente`
/// (ver gestor-loja), que aceita envio anônimo.
class SugestaoProdutoClienteRepository {
  Future<List<SugestaoProdutoCliente>> listar() async {
    final data = await supabase
        .from('sugestoes_produto_cliente')
        .select('id, termo_buscado, mensagem, contato, status, created_at, avaliado_em, '
            'clientes(nome, telefone)')
        .order('created_at', ascending: false);

    return (data as List)
        .map((row) => SugestaoProdutoCliente.fromSupabase(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> marcarStatus(String id, String status) async {
    await supabase.from('sugestoes_produto_cliente').update({
      'status': status,
      'avaliado_em': status == 'pendente' ? null : DateTime.now().toIso8601String(),
    }).eq('id', id);
  }
}
