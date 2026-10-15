import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/supabase_config.dart';
import '../screens/opcoes_pagamento_screen.dart' show metodosPagamentoDisponiveis;

/// Formas de pagamento ativas da loja atual, na ordem configurada.
///
/// Carregada uma vez ao entrar na loja (e guardada NESTE aparelho, por
/// empresa) pra tela de pagamento já nascer na ordem certa. Antes, cada
/// tela abria com a ordem padrão do app e trocava pra ordem da loja quando
/// o banco respondia — os botões mudavam de lugar embaixo do dedo.
/// `null` = ainda não sabe (sem cache e sem resposta do banco).
class MetodosPagamentoProvider with ChangeNotifier {
  List<String>? _metodos;
  String? _empresaId;

  List<String>? get metodos => _metodos;

  String _chaveCache(String empresaId) => 'metodos_pagamento_ativos_$empresaId';

  Future<void> definirEmpresa(String empresaId) async {
    _empresaId = empresaId;
    _metodos = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cache = prefs.getStringList(_chaveCache(empresaId));
      if (cache != null && cache.isNotEmpty && _empresaId == empresaId) {
        _metodos = cache;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Erro ao ler cache de formas de pagamento: $e');
    }
    await carregar();
  }

  Future<void> carregar() async {
    final empresaId = _empresaId;
    if (empresaId == null) return;
    try {
      final data = await supabase
          .from('empresas')
          .select('metodos_pagamento_ativos')
          .eq('id', empresaId)
          .single();
      if (_empresaId != empresaId) return;
      final metodos = (data['metodos_pagamento_ativos'] as List?)?.map((m) => m.toString()).toList();
      // Loja sem configuração salva usa a ordem padrão (mesmo critério de antes).
      await atualizar(metodos != null && metodos.isNotEmpty ? metodos : metodosPagamentoDisponiveis);
    } catch (e) {
      // Mantém o cache — melhor que voltar pra ordem padrão por uma falha
      // de rede momentânea.
      debugPrint('Erro ao carregar formas de pagamento: $e');
      // Sem cache nem banco: ordem padrão, pra tela não ficar carregando pra sempre.
      if (_metodos == null && _empresaId == empresaId) {
        _metodos = List.unmodifiable(metodosPagamentoDisponiveis);
        notifyListeners();
      }
    }
  }

  /// Chamado também por Opções de Pagamento depois de salvar, pra mudança
  /// valer na hora sem reabrir o app.
  Future<void> atualizar(List<String> metodos) async {
    final empresaId = _empresaId;
    if (empresaId == null) return;
    final mudou = _metodos == null ||
        _metodos!.length != metodos.length ||
        Iterable<int>.generate(metodos.length).any((i) => _metodos![i] != metodos[i]);
    _metodos = List.unmodifiable(metodos);
    if (mudou) notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_chaveCache(empresaId), metodos);
    } catch (e) {
      debugPrint('Erro ao salvar cache de formas de pagamento: $e');
    }
  }
}
