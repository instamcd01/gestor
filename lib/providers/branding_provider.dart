import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/supabase_config.dart';
import '../models/marca_ativo.dart';
import '../models/modelo_visual.dart';
import '../repositories/marca_repository.dart';
import '../repositories/modelo_visual_repository.dart';
import '../theme/app_theme.dart';

const _chaveCacheCorPrimaria = 'branding_cache_cor_primaria';
const _chaveCacheCorSecundaria = 'branding_cache_cor_secundaria';
const _chaveCacheTema = 'branding_cache_tema';
const _chaveCacheLayoutSidebar = 'branding_cache_layout_sidebar';
const _chaveCacheEmpresa = 'branding_cache_empresa_id';
const _chaveCacheNome = 'branding_cache_nome';
// Posições de imagem do próprio app guardadas no cache (as do site não
// importam aqui).
const _posicoesApp = ['app_inicio', 'app_drawer', 'app_sidebar'];
String _chaveCacheMarca(String posicao) => 'branding_cache_marca_$posicao';

/// O que mostrar numa posição de marca do app (topo, menu, barra lateral).
/// `padrao` = a loja não configurou nada ali → identidade INARI ("INARI
/// por fora", a loja personaliza se quiser — ver Kit de Marca).
class MarcaExibicao {
  final String? url;
  final bool texto;

  const MarcaExibicao.imagem(String this.url) : texto = false;
  const MarcaExibicao.texto()
      : url = null,
        texto = true;
  const MarcaExibicao.padrao()
      : url = null,
        texto = false;

  bool get padrao => url == null && !texto;

  String get _codificada => url != null ? 'url:$url' : (texto ? 'texto' : 'padrao');

  static MarcaExibicao? _decodificar(String? valor) {
    if (valor == null) return null;
    if (valor.startsWith('url:')) return MarcaExibicao.imagem(valor.substring(4));
    return valor == 'texto' ? const MarcaExibicao.texto() : const MarcaExibicao.padrao();
  }
}

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
  final MarcaRepository _marcaRepository = MarcaRepository();

  String? _empresaId;
  String? _nomeEmpresa;
  ModeloVisual? _modelo;
  List<ModeloVisual> _modelosDisponiveis = [];

  // Kit de marca: galeria de ativos (mascote/logo/nome-imagem) + qual
  // ativo (ou "texto simples") aparece em cada posição do app/site.
  List<MarcaAtivo> _ativos = [];
  Map<String, MarcaPosicao> _posicoes = {};

  // null = herda o padrão do modelo escolhido; não-null = sobrepõe.
  Color? _corPrimariaOverride;
  Color? _corSecundariaOverride;
  // Escuro até `carregarBranding` trazer a preferência real da empresa: a
  // tela de login é a primeira impressão do app e não deve piscar claro
  // (ou depender do tema do sistema) antes do login acontecer.
  ThemeMode _temaModo = ThemeMode.dark;
  bool _carregando = false;

  // Preenchido por `carregarCachePrevio` a partir do último branding
  // carregado com sucesso NESTE aparelho (SharedPreferences) — só usado
  // enquanto `_modelo` ainda não chegou de verdade do Supabase. Sem isso,
  // toda abertura do app mostrava a cor/layout padrão por um instante antes
  // de "pular" pra cor real da empresa.
  LayoutNavegacao? _layoutCache;

  // Mesmo motivo, pro nome e as logos do topo/menu: sem isso a abertura
  // mostrava "INARI" → nome em texto → logo deslocada → logo no lugar.
  // Só valem enquanto o Kit de Marca real não chegou (`_marcaCarregada`),
  // e só se forem da MESMA loja (ver `carregarBranding`).
  String? _empresaCache;
  String? _nomeCache;
  Map<String, MarcaExibicao> _marcasCache = {};
  bool _marcaCarregada = false;

  ModeloVisual? get modelo => _modelo;
  List<ModeloVisual> get modelosDisponiveis => _modelosDisponiveis;
  ThemeMode get temaModo => _temaModo;
  bool get carregando => _carregando;
  LayoutNavegacao get layoutNavegacao => _modelo?.layoutNavegacao ?? _layoutCache ?? LayoutNavegacao.drawer;

  /// Nome da empresa — fallback textual pra qualquer posição em modo
  /// "texto" ('INARI' só se ainda não carregou/sem empresa, nunca deveria
  /// aparecer de verdade pro usuário final).
  String get nomeEmpresa => _nomeEmpresa ?? 'INARI';

  /// Nome pro topo/menu: o carregado, senão o do cache deste aparelho, senão
  /// null (primeiro uso) — quem mostra deixa vazio em vez de exibir "INARI"
  /// e trocar logo depois.
  String? get nomeParaExibir => _nomeEmpresa ?? _nomeCache;

  List<MarcaAtivo> get ativosDeMarca => _ativos;
  List<MarcaAtivo> ativosDeMarcaPorTipo(String tipo) => _ativos.where((a) => a.tipo == tipo).toList();
  MarcaPosicao? posicaoDeMarca(String posicao) => _posicoes[posicao];

  /// URL da imagem configurada pra essa posição — null quando o modo é
  /// "texto" (mostrar o nome da empresa) ou nada foi configurado ainda.
  String? urlParaPosicao(String posicao) {
    if (!_marcaCarregada) return _marcasCache[posicao]?.url;
    final p = _posicoes[posicao];
    if (p == null || p.modo != 'imagem' || p.ativoId == null) return null;
    for (final ativo in _ativos) {
      if (ativo.id == p.ativoId) return ativo.url;
    }
    return null;
  }

  /// O que mostrar na posição: imagem da loja, nome em texto (escolha da
  /// loja) ou o padrão INARI (nada configurado). null = ainda carregando no
  /// primeiro uso deste aparelho (quem mostra deixa vazio).
  MarcaExibicao? marcaPara(String posicao) {
    if (!_marcaCarregada) return _marcasCache[posicao];
    final p = _posicoes[posicao];
    if (p == null) return const MarcaExibicao.padrao();
    if (p.modo == 'imagem') {
      final url = urlParaPosicao(posicao);
      return url == null ? const MarcaExibicao.padrao() : MarcaExibicao.imagem(url);
    }
    return const MarcaExibicao.texto();
  }

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
        // Tema de fábrica INARI (loja não escolheu cor própria): barra do
        // topo grafite. Com cor própria, a barra segue a cor da loja.
        corTopo: AppTheme.colorParaHex(corPrimaria).toUpperCase() == AppThemeDefaults.corPrimaria.toUpperCase()
            ? AppThemeDefaults.fundoLogo
            : null,
      );

  /// Restaura, a partir do cache local deste aparelho, a cor/tema/layout do
  /// último branding carregado com sucesso — chamado em `main()` ANTES do
  /// primeiro frame, pra já nascer com a cor real da empresa em vez da cor
  /// padrão. `carregarBranding` continua rodando normalmente depois (via
  /// AuthGate) pra confirmar/atualizar contra o Supabase; se os valores não
  /// mudaram desde o último uso (caso comum), a troca é invisível.
  Future<void> carregarCachePrevio() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final corPrimariaHex = prefs.getString(_chaveCacheCorPrimaria);
      if (corPrimariaHex != null) _corPrimariaOverride = AppTheme.hexParaColor(corPrimariaHex);

      final corSecundariaHex = prefs.getString(_chaveCacheCorSecundaria);
      if (corSecundariaHex != null) _corSecundariaOverride = AppTheme.hexParaColor(corSecundariaHex);

      final temaSalvo = prefs.getString(_chaveCacheTema);
      if (temaSalvo != null) _temaModo = _temaModoFromString(temaSalvo);

      final layoutSidebar = prefs.getBool(_chaveCacheLayoutSidebar);
      if (layoutSidebar != null) _layoutCache = layoutSidebar ? LayoutNavegacao.sidebar : LayoutNavegacao.drawer;

      _empresaCache = prefs.getString(_chaveCacheEmpresa);
      _nomeCache = prefs.getString(_chaveCacheNome);
      _marcasCache = {
        for (final posicao in _posicoesApp)
          if (MarcaExibicao._decodificar(prefs.getString(_chaveCacheMarca(posicao))) case final marca?) posicao: marca,
      };

      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao carregar cache local de branding: $e');
      // Sem cache disponível (primeira instalação, erro de leitura) — segue
      // com os valores padrão normalmente, `carregarBranding` corrige assim
      // que a rede/autenticação estiverem prontas.
    }
  }

  /// Guarda localmente (neste aparelho) o branding resolvido, pra
  /// `carregarCachePrevio` usar na próxima abertura do app. Best-effort —
  /// falha aqui não deve impedir nada, por isso não é aguardado/propagado.
  Future<void> _salvarCacheLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_chaveCacheCorPrimaria, AppTheme.colorParaHex(corPrimaria));
      await prefs.setString(_chaveCacheCorSecundaria, AppTheme.colorParaHex(corSecundaria));
      await prefs.setString(_chaveCacheTema, _temaModoToString(_temaModo));
      await prefs.setBool(_chaveCacheLayoutSidebar, layoutNavegacao == LayoutNavegacao.sidebar);
      if (_empresaId != null) await prefs.setString(_chaveCacheEmpresa, _empresaId!);
      if (_nomeEmpresa != null) await prefs.setString(_chaveCacheNome, _nomeEmpresa!);
      if (_marcaCarregada) {
        for (final posicao in _posicoesApp) {
          await prefs.setString(_chaveCacheMarca(posicao), marcaPara(posicao)!._codificada);
        }
      }
    } catch (e) {
      debugPrint('Erro ao salvar cache local de branding: $e');
    }
  }

  /// Busca o branding salvo da empresa e o catálogo de modelos disponíveis.
  Future<void> carregarBranding(String empresaId) async {
    _empresaId = empresaId;
    // Cache de outra loja (outro login neste aparelho) não serve: melhor
    // topo vazio por um instante do que a logo da loja errada.
    if (_empresaCache != null && _empresaCache != empresaId) {
      _nomeCache = null;
      _marcasCache = {};
    }
    _carregando = true;
    notifyListeners();

    try {
      // Tudo é buscado ANTES de aplicar: aplicar o nome antes das imagens
      // deixava o topo num estado intermediário (nome em texto) sempre que
      // outro provider redesenhava a tela no meio do carregamento.
      final data = await supabase
          .from('empresas')
          .select('nome, cor_primaria, cor_secundaria, tema_preferido, modelo_visual_id')
          .eq('id', empresaId)
          .single();
      final resultados = await Future.wait([
        _modeloRepository.listarAtivos(),
        _marcaRepository.listarAtivos(),
        _marcaRepository.listarPosicoes(),
      ]);

      _nomeEmpresa = data['nome']?.toString();
      _corPrimariaOverride = data['cor_primaria'] != null ? AppTheme.hexParaColor(data['cor_primaria']) : null;
      _corSecundariaOverride = data['cor_secundaria'] != null ? AppTheme.hexParaColor(data['cor_secundaria']) : null;
      _temaModo = _temaModoFromString(data['tema_preferido']);
      _modelosDisponiveis = resultados[0] as List<ModeloVisual>;
      _ativos = resultados[1] as List<MarcaAtivo>;
      _posicoes = {for (final p in resultados[2] as List<MarcaPosicao>) p.posicao: p};
      _marcaCarregada = true;

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

      unawaited(_salvarCacheLocal());
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
    unawaited(_salvarCacheLocal());

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
    unawaited(_salvarCacheLocal());

    if (_empresaId == null) return;

    await supabase.from('empresas').update({
      if (corPrimaria != null)
        'cor_primaria': AppTheme.colorParaHex(corPrimaria),
      if (corSecundaria != null)
        'cor_secundaria': AppTheme.colorParaHex(corSecundaria),
    }).eq('id', _empresaId!);
  }

  /// Envia uma imagem nova pro kit de marca (mascote/logo/nome-imagem) e
  /// recarrega a galeria local. Ver [MarcaRepository.enviar] pra regra de
  /// "tipo único substitui" vs. "mascote sempre adiciona".
  Future<MarcaAtivo> enviarAtivoDeMarca({
    required Uint8List bytes,
    required String tipo,
    String? rotulo,
  }) async {
    if (_empresaId == null) throw StateError('Sem empresa logada');
    final ordem = tipo == 'mascote' ? ativosDeMarcaPorTipo('mascote').length : 0;
    final ativo = await _marcaRepository.enviar(
      bytes: bytes,
      empresaId: _empresaId!,
      tipo: tipo,
      rotulo: rotulo,
      ordem: ordem,
    );
    await _recarregarKitDeMarca();
    return ativo;
  }

  Future<void> excluirAtivoDeMarca(String ativoId) async {
    await _marcaRepository.excluirAtivo(ativoId);
    await _recarregarKitDeMarca();
  }

  Future<void> atualizarRotuloDeMarca(String ativoId, String rotulo) async {
    await _marcaRepository.atualizarRotulo(ativoId, rotulo);
    await _recarregarKitDeMarca();
  }

  /// Define o que aparece numa posição (`site_header`, `app_drawer`, etc.)
  /// — `modo='texto'` mostra o nome da empresa, `modo='imagem'` mostra o
  /// ativo indicado.
  Future<void> definirPosicaoDeMarca({
    required String posicao,
    required String modo,
    String? ativoId,
  }) async {
    if (_empresaId == null) return;
    await _marcaRepository.definirPosicao(
      empresaId: _empresaId!,
      posicao: posicao,
      modo: modo,
      ativoId: ativoId,
    );
    await _recarregarKitDeMarca();
  }

  Future<void> _recarregarKitDeMarca() async {
    final resultados = await Future.wait([
      _marcaRepository.listarAtivos(),
      _marcaRepository.listarPosicoes(),
    ]);
    _ativos = resultados[0] as List<MarcaAtivo>;
    _posicoes = {for (final p in resultados[1] as List<MarcaPosicao>) p.posicao: p};
    notifyListeners();
    unawaited(_salvarCacheLocal());
  }

  /// Atualiza a preferência de tema claro/escuro/sistema.
  Future<void> atualizarTemaPreferido(ThemeMode modo) async {
    _temaModo = modo;
    notifyListeners();
    unawaited(_salvarCacheLocal());

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
    unawaited(_salvarCacheLocal());

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
