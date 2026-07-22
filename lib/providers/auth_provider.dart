import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Controla o estado de autenticação e a ligação usuário → empresa (tenant).
///
/// Fluxo:
/// 1. Usuário faz login/cadastro (Supabase Auth).
/// 2. Verificamos se ele já tem uma linha em `usuarios` (ou seja, já
///    pertence a uma empresa).
/// 3. Se não tiver, ele passa pelo onboarding (criar a empresa dele).
/// 4. Depois disso, `empresaId` fica disponível pro resto do app usar.
class AuthProvider with ChangeNotifier {
  String? _empresaId;
  String? _papel;
  bool _carregando = true;
  String? _erro;

  User? get usuarioAtual => supabase.auth.currentUser;
  bool get estaLogado => usuarioAtual != null;
  String? get empresaId => _empresaId;
  String? get papel => _papel;
  bool get carregando => _carregando;
  String? get erro => _erro;

  /// true quando o usuário está logado mas ainda não tem empresa vinculada
  /// (precisa passar pelo onboarding antes de usar o resto do app).
  bool get precisaOnboarding => estaLogado && _empresaId == null && !_carregando;

  AuthProvider() {
    // Reage a login/logout/refresh de sessão automaticamente.
    supabase.auth.onAuthStateChange.listen((_) => _verificarUsuario());
    _verificarUsuario();
  }

  Future<void> _verificarUsuario() async {
    _carregando = true;
    notifyListeners();

    if (!estaLogado) {
      _empresaId = null;
      _papel = null;
      _carregando = false;
      notifyListeners();
      return;
    }

    try {
      final data = await supabase
          .from('usuarios')
          .select('empresa_id, papel')
          .eq('id', usuarioAtual!.id)
          .maybeSingle();

      _empresaId = data?['empresa_id'];
      _papel = data?['papel'];
    } catch (e) {
      debugPrint('Erro ao verificar vínculo empresa/usuário: $e');
      _empresaId = null;
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<bool> entrar(String email, String senha) async {
    _erro = null;
    try {
      await supabase.auth.signInWithPassword(email: email, password: senha);
      return true;
    } on AuthException catch (e) {
      _erro = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> cadastrar(String email, String senha) async {
    _erro = null;
    try {
      await supabase.auth.signUp(email: email, password: senha);
      return true;
    } on AuthException catch (e) {
      _erro = e.message;
      notifyListeners();
      return false;
    }
  }

  /// Cria a empresa (tenant) e o vínculo de dono, usado só no onboarding
  /// do primeiro acesso.
  Future<bool> criarEmpresa(String nomeEmpresa) async {
    _erro = null;
    try {
      await supabase.rpc('criar_empresa_e_usuario_dono',
          params: {'p_nome_empresa': nomeEmpresa});
      await _verificarUsuario();
      return true;
    } on PostgrestException catch (e) {
      _erro = e.message;
      notifyListeners();
      return false;
    }
  }

  /// Entra numa empresa já existente usando um código de convite gerado
  /// por um "dono" — alternativa ao onboarding de criar empresa nova.
  Future<bool> entrarComConvite(String codigo) async {
    _erro = null;
    try {
      await supabase.rpc('entrar_empresa_com_convite', params: {'p_codigo': codigo});
      await _verificarUsuario();
      return true;
    } on PostgrestException catch (e) {
      _erro = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<void> sair() async {
    await supabase.auth.signOut();
  }
}
