import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/conta_financeira.dart';
import '../utils/ofx_parser.dart';

/// Contas da loja, "onde cai cada coisa" e extrato importado. RLS de
/// `contas_financeiras*`/`movimentacoes_financeiras` limita a dono/gerente
/// da própria loja.
class ContaFinanceiraRepository {
  final _supabase = Supabase.instance.client;

  Future<List<ContaFinanceira>> listar(String empresaId) async {
    final data = await _supabase
        .from('contas_financeiras')
        .select()
        .eq('empresa_id', empresaId)
        .order('ativa', ascending: false)
        .order('nome');
    return (data as List).map((r) => ContaFinanceira.fromSupabase(r as Map<String, dynamic>)).toList();
  }

  Future<void> salvar({
    required String empresaId,
    String? id,
    required String nome,
    required String tipo,
    required String provedor,
    String? identificacao,
    bool ativa = true,
  }) async {
    final dados = {
      'empresa_id': empresaId,
      'nome': nome,
      'tipo': tipo,
      'provedor': provedor,
      'identificacao': (identificacao?.trim().isEmpty ?? true) ? null : identificacao!.trim(),
      'ativa': ativa,
    };
    if (id == null) {
      await _supabase.from('contas_financeiras').insert(dados);
    } else {
      await _supabase.from('contas_financeiras').update(dados).eq('id', id);
    }
  }

  /// origem → conta_id
  Future<Map<String, String>> listarDestinos(String empresaId) async {
    final data = await _supabase.from('contas_financeiras_destinos').select('origem, conta_id').eq('empresa_id', empresaId);
    return {for (final r in data as List) r['origem'] as String: r['conta_id'] as String};
  }

  Future<void> definirDestino({required String empresaId, required String origem, String? contaId}) async {
    if (contaId == null) {
      await _supabase.from('contas_financeiras_destinos').delete().eq('empresa_id', empresaId).eq('origem', origem);
    } else {
      await _supabase
          .from('contas_financeiras_destinos')
          .upsert({'empresa_id': empresaId, 'origem': origem, 'conta_id': contaId}, onConflict: 'empresa_id,origem');
    }
  }

  Future<List<MovimentacaoFinanceira>> listarMovimentacoes({required String contaId, int limite = 300}) async {
    final data = await _supabase
        .from('movimentacoes_financeiras')
        .select('id, conta_id, data, tipo, valor, descricao, status_conferencia, dados_brutos')
        .eq('conta_id', contaId)
        .order('data', ascending: false)
        .order('created_at', ascending: false)
        .limit(limite);
    return (data as List).map((r) => MovimentacaoFinanceira.fromSupabase(r as Map<String, dynamic>)).toList();
  }

  /// Grava o extrato sem duplicar: (conta_id, id_externo) é único, e o
  /// upsert com ignoreDuplicates só devolve as linhas que entraram de fato.
  /// O saldo do arquivo só substitui o da conta se for mais novo.
  Future<ResultadoImportacao> importarOfx({
    required String empresaId,
    required ContaFinanceira conta,
    required String arquivoNome,
    required ExtratoOfx extrato,
  }) async {
    final usuarioId = _supabase.auth.currentUser?.id;
    final importacao = await _supabase
        .from('importacoes_extrato')
        .insert({
          'empresa_id': empresaId,
          'conta_id': conta.id,
          'origem': 'arquivo',
          'arquivo_nome': arquivoNome,
          'formato': 'ofx',
          'periodo_inicio': _dia(extrato.inicio),
          'periodo_fim': _dia(extrato.fim),
          'saldo_final': extrato.saldoFinal,
          'criado_por': usuarioId,
        })
        .select('id')
        .single();
    final importacaoId = importacao['id'] as String;

    var novas = 0;
    final linhas = extrato.lancamentos
        .map((l) => {
              'empresa_id': empresaId,
              'conta_id': conta.id,
              'importacao_id': importacaoId,
              'id_externo': l.idExterno,
              'data': _dia(l.data),
              'tipo': l.entrada ? 'entrada' : 'saida',
              'valor': l.valor,
              'descricao': l.descricao.isEmpty ? null : l.descricao,
              'dados_brutos': {'trntype': l.tipoOfx},
            })
        .toList();
    for (var i = 0; i < linhas.length; i += 500) {
      final lote = linhas.sublist(i, i + 500 > linhas.length ? linhas.length : i + 500);
      final inseridas = await _supabase
          .from('movimentacoes_financeiras')
          .upsert(lote, onConflict: 'conta_id,id_externo', ignoreDuplicates: true)
          .select('id');
      novas += (inseridas as List).length;
    }
    final repetidas = linhas.length - novas;

    await _supabase.from('importacoes_extrato').update({'qtd_novas': novas, 'qtd_repetidas': repetidas}).eq('id', importacaoId);

    final saldoEm = extrato.saldoEm ?? extrato.fim;
    if (extrato.saldoFinal != null &&
        saldoEm != null &&
        (conta.saldoAtualizadoEm == null || !saldoEm.isBefore(conta.saldoAtualizadoEm!))) {
      await _supabase.from('contas_financeiras').update({
        'saldo_atual': extrato.saldoFinal,
        'saldo_atualizado_em': saldoEm.toIso8601String(),
        'ultima_sincronizacao_em': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', conta.id);
    } else {
      await _supabase
          .from('contas_financeiras')
          .update({'ultima_sincronizacao_em': DateTime.now().toUtc().toIso8601String()})
          .eq('id', conta.id);
    }

    return ResultadoImportacao(novas: novas, repetidas: repetidas, saldoFinal: extrato.saldoFinal);
  }

  /// Grava Client ID/Secret e o certificado no Vault (RPC confere se é
  /// dono/gerente da loja) e já busca saldo e extrato pra confirmar que a
  /// conexão funciona — erro do Inter volta como exceção com a mensagem dele.
  Future<double?> conectarInter({
    required String contaId,
    required String clientId,
    required String clientSecret,
    required String certificado,
    required String chave,
    String? contaCorrente,
  }) async {
    await _supabase.rpc('conta_conectar_inter', params: {
      'p_conta_id': contaId,
      'p_client_id': clientId,
      'p_client_secret': clientSecret,
      'p_certificado': certificado,
      'p_chave': chave,
      'p_conta_corrente': contaCorrente,
    });
    return sincronizarAgora(contaId);
  }

  /// Stone (API de Conciliação, modo cliente): StoneCode + chave criada no
  /// Portal Stone. Já baixa os primeiros dias pra confirmar.
  Future<Map<String, dynamic>> conectarStone({
    required String contaId,
    required String stoneCode,
    required String chave,
  }) async {
    await _supabase.rpc('conta_conectar_stone', params: {
      'p_conta_id': contaId,
      'p_stone_code': stoneCode,
      'p_chave': chave,
    });
    return _sincronizar(contaId);
  }

  Future<Map<String, dynamic>> _sincronizar(String contaId) async {
    final r = await _supabase.functions.invoke('contas-sync', body: {'conta_id': contaId});
    final resultado = ((r.data as Map?)?['resultados'] as List?)?.cast<Map>().firstOrNull;
    if (resultado == null) throw Exception('A conta não está conectada');
    if (resultado['erro'] != null) throw Exception(resultado['erro']);
    return Map<String, dynamic>.from(resultado);
  }

  /// Sincroniza uma conta conectada (Inter/Stone) na hora; devolve o saldo
  /// quando o provedor informa (Inter).
  Future<double?> sincronizarAgora(String contaId) async =>
      ((await _sincronizar(contaId))['saldo'] as num?)?.toDouble();

  /// Vendas no cartão da maquininha, mais novas primeiro.
  Future<List<VendaCartao>> listarVendasCartao({required String contaId, int limite = 300}) async {
    final data = await _supabase
        .from('vendas_cartao')
        .select('id, capturada_em, tipo, bandeira, parcelas, valor_bruto, valor_liquido, taxa, previsao_pagamento, '
            'valor_cancelado, vinculo, pedido:pedidos(numero_sequencial)')
        .eq('conta_id', contaId)
        .order('capturada_em', ascending: false)
        .limit(limite);
    return (data as List).map((r) => VendaCartao.fromSupabase(r as Map<String, dynamic>)).toList();
  }

  Future<void> desconectar(String contaId) => _supabase.rpc('conta_desconectar', params: {'p_conta_id': contaId});

  static String? _dia(DateTime? d) => d?.toIso8601String().split('T').first;
}
