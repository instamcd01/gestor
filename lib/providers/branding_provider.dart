import 'package:flutter/material.dart';
import '../config/supabase_config.dart';
import '../models/modelo_visual.dart';
import '../repositories/modelo_visual_repository.dart';
import '../theme/app_theme.dart';

/// Controla a identidade visual da empresa logada: qual modelo/tema
/// (`ModeloVisual`) ela escolheu, mais a personalização por cima (cor
/// primária/secundária, logo, modo claro/escuro/sistema). Cada empresa no
/// SaaS pode ter seu próprio branding — os valores vêm da tabela
/// `empresas` no Supabase; a lista de modelos disponíveis vem do catálogo
/// compartilhado `modelos_visuais`.
///
/// IMPORTANTE: `carregarBranding` precisa ser chamado com o empresa_id
/// do usuário logado assim que a autenticação estiver pronta. Até lá,
/// o app usa as cores/modelo padrão (AppThemeDefaults) como fallback.
class BrandingProvider with ChangeNotifier {
  final ModeloVisualRepository _modeloRepository = ModeloVisualRepository();

  String? _empresaId;
  ModeloVisual? _modelo;
  List<ModeloVisual> _modelosDisponiveis = [];

  // null = herda o padrão do modelo escolhido; não-null = sobrepõe.
  Color? _corPrimariaOverride;
  Color? _corSecundariaOverride;
  String? _logoUrl;
  ThemeMode _temaModo = ThemeMode.system;
  bool _carregando = false;

  ModeloVisual? get modelo => _modelo;
  List<ModeloVisual> get modelosDisponiveis => _modelosDisponiveis;
  String? get logoUrl => _logoUrl;
  ThemeMode get temaModo => _temaModo;
  bool get carregando => _carregando;
  LayoutNavegacao get layoutNavegacao => _modelo?.layoutNavegacao ?? LayoutNavegacao.drawer;

  Color get corPrimaria =>
      _corPrimariaOverride ??
      AppTheme.hexParaColor(_modelo?.corPrimariaPadrao ?? AppThemeDefaults.corPrimaria);

  Color get corSecundaria =>
      _corSecundariaOverride ??
      AppTheme.hexParaColor(_modelo?.corSecundariaPadrao ?? AppThemeDefaults.corSecundaria);

  ThemeData get temaClaro => _construirTema(Brightness.light);
  ThemeData get temaEscuro => _construirTema(Brightness.dark);

  ThemeData _construirTema(Brightness brightness) => AppTheme.build(
        corPrimaria: corPrimaria,
        corSecundaria: corSecundaria,
        brightness: brightness,
        fonte: _modelo?.fonte ?? 'Inter',
        radiusCard: _modelo?.radiusCard ?? 16,
        radiusBotao: _modelo?.radiusBotao ?? 12,
        radiusChip: _modelo?.radiusChip ?? 8,
        radiusFab: _modelo?.radiusFab ?? 16,
        cardElevado: _modelo?.cardElevado ?? false,
        densidadeCompacta: _modelo?.densidadeCompacta ?? false,
      );

  /// Busca o branding salvo da empresa e o catálogo de modelos disponíveis.
  Future<void> carregarBranding(String empresaId) async {
    _empresaId = empresaId;
    _carregando = true;
    notifyListeners();

    try {
      final data = await supabase
          .from('empresas')
          .select('cor_primaria, cor_secundaria, logo_url, tema_preferido, modelo_visual_id')
          .eq('id', empresaId)
          .single();

      _corPrimariaOverride = data['cor_primaria'] != null ? AppTheme.hexParaColor(data['cor_primaria']) : null;
      _corSecundariaOverride = data['cor_secundaria'] != null ? AppTheme.hexParaColor(data['cor_secundaria']) : null;
      _logoUrl = data['logo_url'];
      _temaModo = _temaModoFromString(data['tema_preferido']);

      _modelosDisponiveis = await _modeloRepository.listarAtivos();

      final modeloVisualId = data['modelo_visual_id'] as String?;
      ModeloVisual? modeloEncontrado;
      if (modeloVisualId != null) {
        for (final m in _modelosDisponiveis) {
          if (m.id == modeloVisualId) {
            modeloEncontrado = m;
            break;
          }
        }
      }
      _modelo = modeloEncontrado ?? (_modelosDisponiveis.isNotEmpty ? _modelosDisponiveis.first : null);
    } catch (e) {
      debugPrint('Erro ao carregar branding da empresa: $e');
      // Mantém os valores padrão em caso de falha — o app nunca deve
      // travar por causa de personalização visual.
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  /// Troca o modelo visual escolhido pela empresa. As sobreposições de
  /// cor/logo já feitas continuam valendo por cima do novo modelo.
  Future<void> escolherModelo(String modeloId) async {
    ModeloVisual? novoModelo;
    for (final m in _modelosDisponiveis) {
      if (m.id == modeloId) {
        novoModelo = m;
        break;
      }
    }
    if (novoModelo == null) return;

    _modelo = novoModelo;
    notifyListeners();

    if (_empresaId == null) return;
    try {
      await supabase.from('empresas').update({'modelo_visual_id': modeloId}).eq('id', _empresaId!);
    } catch (e) {
      debugPrint('Erro ao salvar modelo visual escolhido: $e');
      rethrow;
    }
  }

  /// Atualiza as cores da marca (sobreposição sobre o modelo) e salva.
  Future<void> atualizarCores({
    Color? corPrimaria,
    Color? corSecundaria,
  }) async {
    if (corPrimaria != null) _corPrimariaOverride = corPrimaria;
    if (corSecundaria != null) _corSecundariaOverride = corSecundaria;
    notifyListeners();

    if (_empresaId == null) return;

    await supabase.from('empresas').update({
      if (corPrimaria != null)
        'cor_primaria': AppTheme.colorParaHex(corPrimaria),
      if (corSecundaria != null)
        'cor_secundaria': AppTheme.colorParaHex(corSecundaria),
    }).eq('id', _empresaId!);
  }

  /// Atualiza a URL do logo (já hospedado no Supabase Storage) e salva.
  Future<void> atualizarLogo(String logoUrl) async {
    _logoUrl = logoUrl;
    notifyListeners();

    if (_empresaId == null) return;
    await supabase
        .from('empresas')
        .update({'logo_url': logoUrl}).eq('id', _empresaId!);
  }

  /// Atualiza a preferência de tema claro/escuro/sistema.
  Future<void> atualizarTemaPreferido(ThemeMode modo) async {
    _temaModo = modo;
    notifyListeners();

    if (_empresaId == null) return;
    await supabase.from('empresas').update({
      'tema_preferido': _temaModoToString(modo),
    }).eq('id', _empresaId!);
  }

  /// Remove as sobreposições de cor — volta a herdar direto do modelo
  /// visual escolhido (não força mais um hex fixo).
  Future<void> restaurarPadrao() async {
    _corPrimariaOverride = null;
    _corSecundariaOverride = null;
    notifyListeners();

    if (_empresaId == null) return;
    await supabase.from('empresas').update({
      'cor_primaria': null,
      'cor_secundaria': null,
    }).eq('id', _empresaId!);
  }

  ThemeMode _temaModoFromString(String? valor) {
    switch (valor) {
      case 'claro':
        return ThemeMode.light;
      case 'escuro':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _temaModoToString(ThemeMode modo) {
    switch (modo) {
      case ThemeMode.light:
        return 'claro';
      case ThemeMode.dark:
        return 'escuro';
      case ThemeMode.system:
        return 'sistema';
    }
  }
}
