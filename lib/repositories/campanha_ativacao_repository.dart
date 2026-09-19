import '../config/supabase_config.dart';
import '../models/campanha_ativacao.dart';

class CampanhaAtivacaoRepository {
  Future<List<CampanhaAtivacao>> listar() async {
    final data = await supabase
        .from('campanhas_ativacao')
        .select()
        .isFilter('deleted_at', null)
        .order('criado_em', ascending: false);
    return (data as List).map((row) => CampanhaAtivacao.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  Future<List<CampanhaAtivacao>> listarArquivadas() async {
    final data = await supabase
        .from('campanhas_ativacao')
        .select()
        .not('deleted_at', 'is', null)
        .order('deleted_at', ascending: false);
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

  /// Soft-delete (mesmo padrão de `clientes`/`produtos`) — os contatos e o
  /// histórico da campanha continuam intactos, só some da lista principal.
  /// Métricas de OUTRAS campanhas nunca são afetadas: são sempre calculadas
  /// na hora a partir de `clientes`/`pedidos`, nunca guardadas na campanha.
  Future<void> arquivar(String campanhaId) async {
    await supabase
        .from('campanhas_ativacao')
        .update({'deleted_at': DateTime.now().toIso8601String()}).eq('id', campanhaId);
  }

  /// Salva o corpo da mensagem (sem a saudação) como padrão da campanha —
  /// sobrevive a qualquer recarga da tela daqui pra frente, substitui a
  /// sugestão padrão por perfil (vip/inativo/genérico) que existia antes.
  /// `null` limpa o padrão salvo, voltando pra sugestão original.
  Future<void> salvarMensagemPadrao(String campanhaId, String? mensagem) async {
    await supabase.from('campanhas_ativacao').update({'mensagem_padrao': mensagem}).eq('id', campanhaId);
  }

  Future<void> desarquivar(String campanhaId) async {
    await supabase.from('campanhas_ativacao').update({'deleted_at': null}).eq('id', campanhaId);
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

  /// Alterna o marcador de "já enviei" de um único contato — usado pelo
  /// checkbox na tela de detalhe (fluxo manual, um contato por vez).
  Future<void> marcarEnviado(String contatoId, bool enviado) async {
    await supabase
        .from('campanha_contatos')
        .update({'enviado_em': enviado ? DateTime.now().toIso8601String() : null}).eq('id', contatoId);
  }

  /// Prévia de clientes que batem com os critérios escolhidos na tela de
  /// filtros reutilizável — não grava nada, só lista pra conferência antes
  /// de confirmar. `prioridade_ordenacao` já vem calculada pelo banco a
  /// partir de [ordenarPor]/[ordem].
  Future<List<ClienteFiltradoCampanha>> filtrarClientes({
    int? diasInatividadeMin,
    int? diasInatividadeMax,
    int? qtdPedidosMin,
    int? qtdPedidosMax,
    double? valorTotalMin,
    double? valorTotalMax,
    double? ticketMedioMin,
    double? ticketMedioMax,
    List<String>? canais,
    List<String>? segmentos,
    bool? aceitaMarketing,
    List<String>? especies,
    bool? jaUsouCupom,
    String ordenarPor = 'recencia',
    String ordem = 'desc',
  }) async {
    final data = await supabase.rpc('filtrar_clientes_campanha', params: {
      'p_dias_inatividade_min': diasInatividadeMin,
      'p_dias_inatividade_max': diasInatividadeMax,
      'p_qtd_pedidos_min': qtdPedidosMin,
      'p_qtd_pedidos_max': qtdPedidosMax,
      'p_valor_total_min': valorTotalMin,
      'p_valor_total_max': valorTotalMax,
      'p_ticket_medio_min': ticketMedioMin,
      'p_ticket_medio_max': ticketMedioMax,
      'p_canais': canais,
      'p_segmentos': segmentos,
      'p_aceita_marketing': aceitaMarketing,
      'p_especies': especies,
      'p_ja_usou_cupom': jaUsouCupom,
      'p_ordenar_por': ordenarPor,
      'p_ordem': ordem,
    });
    return (data as List)
        .map((row) => ClienteFiltradoCampanha.fromSupabase(row as Map<String, dynamic>))
        .toList();
  }

  /// Confirma a prévia de [filtrarClientes] como contatos reais da
  /// campanha — mesmo upsert por (campanha_id, telefone) da importação por
  /// planilha, então reaplicar o mesmo filtro depois só atualiza a
  /// prioridade/perfil em vez de duplicar.
  Future<int> adicionarContatosFiltrados({
    required String campanhaId,
    required String empresaId,
    required List<ClienteFiltradoCampanha> clientes,
  }) async {
    if (clientes.isEmpty) return 0;
    await supabase.from('campanha_contatos').upsert(
          clientes
              .map((c) => {
                    'campanha_id': campanhaId,
                    'empresa_id': empresaId,
                    'telefone': c.telefoneEfetivo,
                    'nome_whatsapp': c.nome,
                    'origem': c.canalOrigem,
                    'valor_referencia': c.valorTotal,
                    'perfil': c.segmento,
                    'prioridade_ordenacao': c.prioridadeOrdenacao,
                  })
              .toList(),
          onConflict: 'campanha_id,telefone',
        );
    return clientes.length;
  }
}
