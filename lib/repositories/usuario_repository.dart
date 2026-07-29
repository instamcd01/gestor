import 'dart:math';

import '../config/supabase_config.dart';
import '../models/convite_empresa.dart';
import '../models/usuario.dart';

class UsuarioRepository {
  static const _caracteresCodigo = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // sem O/0, I/1 (confunde na leitura)

  Future<List<Usuario>> listar() async {
    final data = await supabase.from('usuarios').select().order('created_at');
    return (data as List).map((row) => Usuario.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  Future<void> atualizarPapel(String usuarioId, String papel) async {
    await supabase.from('usuarios').update({'papel': papel}).eq('id', usuarioId);
  }

  Future<void> atualizarAtivo(String usuarioId, bool ativo) async {
    await supabase.from('usuarios').update({'ativo': ativo}).eq('id', usuarioId);
  }

  /// Atualiza nome/telefone de um usuário. Cada um só entra no UPDATE se
  /// foi informado — permite editar só um dos dois sem sobrescrever o outro
  /// com null.
  Future<void> atualizarDados(String usuarioId, {String? nome, String? telefone}) async {
    final dados = <String, dynamic>{};
    if (nome != null) dados['nome'] = nome;
    if (telefone != null) dados['telefone'] = telefone;
    if (dados.isEmpty) return;
    await supabase.from('usuarios').update(dados).eq('id', usuarioId);
  }

  Future<List<ConviteEmpresa>> listarConvites() async {
    final data = await supabase
        .from('convites_empresa')
        .select()
        .order('created_at', ascending: false);
    return (data as List).map((row) => ConviteEmpresa.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  /// Gera um código de convite pra empresa. Tenta algumas vezes em caso de
  /// colisão (extremamente improvável com 8 caracteres, mas o código tem
  /// UNIQUE no banco — não custa nada tratar).
  Future<ConviteEmpresa> gerarConvite({
    required String empresaId,
    required String criadoPor,
    required String papel,
  }) async {
    for (var tentativa = 0; tentativa < 5; tentativa++) {
      final codigo = _gerarCodigo();
      try {
        final row = await supabase
            .from('convites_empresa')
            .insert({
              'empresa_id': empresaId,
              'codigo': codigo,
              'papel': papel,
              'criado_por': criadoPor,
            })
            .select()
            .single();
        return ConviteEmpresa.fromSupabase(row);
      } catch (e) {
        if (tentativa == 4) rethrow;
      }
    }
    throw StateError('Não foi possível gerar um código de convite único.');
  }

  Future<void> revogarConvite(String conviteId) async {
    await supabase
        .from('convites_empresa')
        .update({'expira_em': DateTime.now().toIso8601String()})
        .eq('id', conviteId);
  }

  String _gerarCodigo() {
    final random = Random.secure();
    return List.generate(8, (_) => _caracteresCodigo[random.nextInt(_caracteresCodigo.length)]).join();
  }
}
