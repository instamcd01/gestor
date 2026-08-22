import '../config/supabase_config.dart';
import '../models/importacao_planilha.dart';

/// Histórico de importações por planilha (produtos e clientes) — registrado
/// no fim de cada tentativa, sucesso ou erro, pra dar visibilidade de
/// quando/quantos/o que deu errado sem precisar confiar só na memória.
class ImportacaoPlanilhaRepository {
  Future<void> registrar({
    required String empresaId,
    required String tipo,
    String? nomeArquivo,
    required int totalLinhas,
    required int novos,
    required int atualizados,
    required int linhasIgnoradas,
    required String status,
    String? mensagemErro,
  }) async {
    await supabase.from('importacoes_planilha').insert({
      'empresa_id': empresaId,
      'tipo': tipo,
      'nome_arquivo': nomeArquivo,
      'total_linhas': totalLinhas,
      'novos': novos,
      'atualizados': atualizados,
      'linhas_ignoradas': linhasIgnoradas,
      'status': status,
      'mensagem_erro': mensagemErro,
    });
  }

  Future<List<ImportacaoPlanilha>> listar({String? tipo}) async {
    var query = supabase.from('importacoes_planilha').select();
    if (tipo != null) query = query.eq('tipo', tipo);
    final data = await query.order('criado_em', ascending: false).limit(100);
    return (data as List).map((row) => ImportacaoPlanilha.fromSupabase(row as Map<String, dynamic>)).toList();
  }
}
