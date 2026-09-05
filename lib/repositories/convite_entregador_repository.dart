import 'dart:math';

import '../config/supabase_config.dart';
import '../models/convite_entregador.dart';

/// Convite pra um entregador vincular a própria conta no app "Entregador"
/// (Fase 1 do app do entregador — ver docs/superpowers/specs/2026-09-04-app-entregador-fase1-design.md).
/// Mesmo padrão de `UsuarioRepository.gerarConvite`, mas escopado a um
/// `entregador_id` específico em vez de um `papel` genérico de staff.
class ConviteEntregadorRepository {
  static const _caracteresCodigo = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  Future<ConviteEntregador> gerar({
    required String empresaId,
    required String entregadorId,
    required String criadoPor,
  }) async {
    for (var tentativa = 0; tentativa < 5; tentativa++) {
      final codigo = _gerarCodigo();
      try {
        final row = await supabase
            .from('convites_entregador')
            .insert({
              'empresa_id': empresaId,
              'entregador_id': entregadorId,
              'codigo': codigo,
              'criado_por': criadoPor,
            })
            .select()
            .single();
        return ConviteEntregador.fromSupabase(row);
      } catch (e) {
        if (tentativa == 4) rethrow;
      }
    }
    throw StateError('Não foi possível gerar um código de convite único.');
  }

  /// Convites ainda não usados (vencidos ou não) — a UI decide o que mostrar
  /// sobre expiração, igual `UsuarioRepository.listarConvites` faz pros
  /// convites de equipe.
  Future<List<ConviteEntregador>> listarPendentes() async {
    final rows = await supabase
        .from('convites_entregador')
        .select('*, entregador:entregadores(nome)')
        .isFilter('usado_em', null)
        .order('created_at', ascending: false);
    return (rows as List).map((r) => ConviteEntregador.fromSupabase(r as Map<String, dynamic>)).toList();
  }

  Future<void> revogar(String conviteId) async {
    await supabase
        .from('convites_entregador')
        .update({'expira_em': DateTime.now().toIso8601String()})
        .eq('id', conviteId);
  }

  String _gerarCodigo() {
    final random = Random.secure();
    return List.generate(8, (_) => _caracteresCodigo[random.nextInt(_caracteresCodigo.length)]).join();
  }
}
