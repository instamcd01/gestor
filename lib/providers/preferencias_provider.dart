import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chaveBarraLateralFixa = 'barra_lateral_fixa';

/// Preferências de UI salvas localmente NESTE dispositivo (SharedPreferences),
/// diferente do branding em `BrandingProvider` — que é por empresa, salvo no
/// Supabase e vale pra todo mundo que usa aquela empresa. Aqui é só "como eu,
/// nesse aparelho, quero que a navegação se comporte".
class PreferenciasProvider with ChangeNotifier {
  bool _barraLateralFixa = false;
  bool _carregado = false;

  /// Sidebar (layout "Moderno") sempre visível e em modo ícone, mesmo em
  /// telas estreitas — em vez de cair pro Drawer/hambúrguer abaixo de 600dp.
  bool get barraLateralFixa => _barraLateralFixa;
  bool get carregado => _carregado;

  Future<void> carregar() async {
    if (_carregado) return;
    final prefs = await SharedPreferences.getInstance();
    _barraLateralFixa = prefs.getBool(_chaveBarraLateralFixa) ?? false;
    _carregado = true;
    notifyListeners();
  }

  Future<void> definirBarraLateralFixa(bool valor) async {
    _barraLateralFixa = valor;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_chaveBarraLateralFixa, valor);
  }
}
