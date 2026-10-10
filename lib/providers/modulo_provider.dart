import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/modulo.dart';
import '../repositories/modulo_repository.dart';

/// Módulos instalados na loja atual — decide o que aparece no menu, nas
/// Configurações e nos hubs. Só conveniência de UI: quem impede de verdade
/// a loja de usar um módulo desligado são os jobs/n8n/site checando
/// `modulo_ativo()` no banco.
///
/// Guarda o último resultado NESTE aparelho (por empresa) pra o menu já
/// nascer certo, sem "piscar" itens enquanto a rede responde — mesmo
/// motivo do cache do BrandingProvider. Sem cache e antes de carregar,
/// nenhum módulo aparece (loja nova só tem a base, então é o seguro).
class ModuloProvider with ChangeNotifier {
  final ModuloRepository _repository = ModuloRepository();

  List<Modulo> _modulos = [];
  Set<String> _ativos = {};
  bool _carregando = false;
  String? _erro;
  String? _empresaId;

  List<Modulo> get modulos => _modulos;
  bool get carregando => _carregando;
  String? get erro => _erro;

  bool ativo(String slug) => _ativos.contains(slug);

  /// Pra itens que servem a mais de um módulo (ex: Avaliações, usada por
  /// iFood e 99Food) — visível se QUALQUER um estiver ativo.
  bool algumAtivo(Iterable<String> slugs) => slugs.any(_ativos.contains);

  String _chaveCache(String empresaId) => 'modulos_ativos_$empresaId';

  Future<void> definirEmpresa(String empresaId) async {
    _empresaId = empresaId;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cache = prefs.getStringList(_chaveCache(empresaId));
      if (cache != null && _empresaId == empresaId) {
        _ativos = cache.toSet();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Erro ao ler cache de módulos: $e');
    }
    await carregar();
  }

  Future<void> carregar() async {
    final empresaId = _empresaId;
    if (empresaId == null) return;
    _carregando = true;
    _erro = null;
    notifyListeners();
    try {
      final modulos = await _repository.listar();
      if (_empresaId != empresaId) return;
      _modulos = modulos;
      _ativos = {for (final m in modulos.where((m) => m.ativo)) m.slug};
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_chaveCache(empresaId), _ativos.toList());
    } catch (e) {
      // Mantém o que veio do cache — melhor que esconder tudo por uma falha
      // de rede momentânea.
      _erro = 'Erro ao carregar módulos: $e';
      debugPrint(_erro);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> instalar(String slug) async {
    await _repository.instalar(slug);
    await carregar();
  }

  Future<void> desinstalar(String slug) async {
    await _repository.desinstalar(slug);
    await carregar();
  }
}
