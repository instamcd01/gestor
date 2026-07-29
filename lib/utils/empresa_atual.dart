import '../config/supabase_config.dart';

/// Retorna o `empresa_id` do usuário autenticado, ou null se não identificado.
Future<String?> obterEmpresaIdAtual() async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;
  final usuario = await supabase
      .from('usuarios')
      .select('empresa_id')
      .eq('id', userId)
      .maybeSingle();
  return usuario?['empresa_id'] as String?;
}
