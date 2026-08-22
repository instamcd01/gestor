import '../config/supabase_config.dart';
import '../models/campanha_ativacao.dart';

class CampanhaAtivacaoRepository {
  Future<List<CampanhaAtivacao>> listar() async {
    final data = await supabase.from('campanhas_ativacao').select().order('criado_em', ascending: false);
    return (data as List).map((row) => CampanhaAtivacao.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  Future<CampanhaAtivacao> criar({
    required String empresaId,
    required String nome,
    String? descricao,
  }) async {
    final row = await supabase
        .from('campanhas_ativacao')
        .insert({'empresa_id': empresaId, 'nome': nome, 'descricao': descricao})
        .select()
        .single();
    return CampanhaAtivacao.fromSupabase(row);
  }

  /// Insere/atualiza contatos em lote — upsert por (campanha_id, telefone),
  /// então reimportar a mesma lista (nome do WhatsApp mudou, por exemplo)
  /// atualiza em vez de duplicar ou falhar na constraint única.
  Future<int> importarContatos({
    required String campanhaId,
    required String empresaId,
    required List<({String telefone, String? nomeWhatsapp, String? origem})> contatos,
  }) async {
    if (contatos.isEmpty) return 0;
    await supabase.from('campanha_contatos').upsert(
          contatos
              .map((c) => {
                    'campanha_id': campanhaId,
                    'empresa_id': empresaId,
                    'telefone': c.telefone,
                    'nome_whatsapp': c.nomeWhatsapp,
                    'origem': c.origem,
                  })
              .toList(),
          onConflict: 'campanha_id,telefone',
        );
    return contatos.length;
  }

  Future<MetricasCampanha> obterMetricas(String campanhaId) async {
    final data = await supabase.rpc('obter_metricas_campanha', params: {'p_campanha_id': campanhaId});
    final row = (data as List).first as Map<String, dynamic>;
    return MetricasCampanha.fromSupabase(row);
  }

  Future<List<ContatoCampanha>> listarContatos(String campanhaId) async {
    final data = await supabase.rpc('listar_contatos_campanha', params: {'p_campanha_id': campanhaId});
    return (data as List).map((row) => ContatoCampanha.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  /// Marca contatos como enviados agora — usado depois que o time confirma
  /// que a mensagem de convite foi de fato disparada pra esses telefones
  /// (o envio em si é manual/externo por enquanto, ver decisão pendente
  /// sobre canal de disparo em massa).
  Future<void> marcarEnviados(List<String> contatoIds) async {
    if (contatoIds.isEmpty) return;
    await supabase.from('campanha_contatos').update({'enviado_em': DateTime.now().toIso8601String()}).inFilter(
        'id', contatoIds);
  }
}
