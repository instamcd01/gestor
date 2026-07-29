import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Cores padrão do app, baseadas na identidade visual da Delivery Pet.
/// Usadas como fallback antes de carregar o branding da empresa (tenant)
/// vindo do Supabase, e como valor inicial pra novas empresas no SaaS.
class AppThemeDefaults {
  static const String corPrimaria = '#F5821F';
  static const String corSecundaria = '#1E3A5F';
}

/// Monta um ThemeData completo (Material 3) a partir das cores de marca
/// de uma empresa. Chamado toda vez que o branding muda, seja porque
/// outra empresa logou, seja porque o usuário editou as cores.
class AppTheme {
  static ThemeData build({
    required Color corPrimaria,
    required Color corSecundaria,
    required Brightness brightness,
    String fonte = 'Inter',
    double radiusCard = 16,
    double radiusBotao = 12,
    double radiusChip = 8,
    double radiusFab = 16,
    bool cardElevado = false,
    bool densidadeCompacta = false,
  }) {
    final isDark = brightness == Brightness.dark;

    // `primary`/`secondary` são forçados pra cor exata escolhida (não pro
    // tom que o algoritmo do Material derivaria do seed) — senão o botão/
    // ícone mostrado na tela pode ficar visivelmente diferente do hex que
    // a empresa escolheu no seletor de cor. `onPrimary`/`onSecondary`
    // também são recalculados a partir da cor exata (em vez de herdados
    // do seed) pra garantir contraste de texto legível com qualquer cor
    // customizada, nos dois temas.
    final colorScheme = ColorScheme.fromSeed(
      seedColor: corPrimaria,
      brightness: brightness,
      primary: corPrimaria,
      onPrimary: _corContrastante(corPrimaria),
      secondary: corSecundaria,
      onSecondary: _corContrastante(corSecundaria),
    );

    final baseTextTheme = _textThemeParaFonte(
      fonte,
      isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    );
    final tituloStyle = _fonteParaEstilo(fonte, fontSize: 20, fontWeight: FontWeight.w600, color: colorScheme.onPrimary);
    final botaoStyle = _fonteParaEstilo(fonte, fontSize: 15, fontWeight: FontWeight.w600);
    final chipStyle = _fonteParaEstilo(fonte, fontSize: 13);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF121417) : const Color(0xFFF7F7F8),
      textTheme: baseTextTheme,
      visualDensity: densidadeCompacta ? VisualDensity.compact : VisualDensity.standard,

      appBarTheme: AppBarTheme(
        // Cor cheia da marca (mesma dos botões/chip selecionado), não o
        // fundo neutro que o Material 3 usaria por padrão — pedido explícito
        // pra manter o topo de cada tela com a cor de marca em destaque.
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: tituloStyle,
      ),

      cardTheme: CardThemeData(
        elevation: cardElevado ? 2 : 0,
        color: cardElevado ? colorScheme.surface : colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: cardElevado ? BorderSide.none : BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusBotao),
          ),
          textStyle: botaoStyle,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusBotao),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusBotao),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusBotao),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusBotao),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        // Selecionado usa a mesma cor cheia dos botões (colorScheme.primary),
        // não o tom "container" pastel que o Material 3 geraria por padrão —
        // pedido explícito pra manter consistência visual com o resto do app.
        selectedColor: colorScheme.primary,
        // Sem cor explícita por estado, o texto do chip ficava sem cor
        // resolvida (mostrando branco em cima de fundo claro, ilegível) —
        // `WidgetStateColor` garante contraste correto tanto selecionado
        // quanto não, e acompanha automaticamente tema claro/escuro e a cor
        // de marca escolhida pela empresa (ambos já embutidos em colorScheme).
        labelStyle: chipStyle.copyWith(
          color: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colorScheme.onPrimary
                : colorScheme.onSurfaceVariant,
          ),
        ),
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusChip),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        elevation: 1,
      ),

      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusFab),
        ),
      ),

      // Cor secundária como acento visível (antes só entrava discretamente
      // em `colorScheme.secondary`, sem nenhum widget do tema consumindo
      // — por isso trocar essa cor "não mudava quase nada" na prática).
      progressIndicatorTheme: ProgressIndicatorThemeData(color: colorScheme.secondary),
      // Sem labelColor/unselectedLabelColor explícitos, o Material 3 usa
      // colorScheme.primary como cor do texto da aba selecionada por padrão
      // — mas o AppBar deste app já usa colorScheme.primary como FUNDO (ver
      // appBarTheme acima), então o nome da aba selecionada ficava com a
      // mesma cor do fundo atrás dela (texto invisível). onPrimary é a cor
      // já calculada pra ter contraste garantido contra colorScheme.primary.
      tabBarTheme: TabBarThemeData(
        indicatorColor: colorScheme.secondary,
        labelColor: colorScheme.onPrimary,
        unselectedLabelColor: colorScheme.onPrimary.withValues(alpha: 0.7),
      ),
    );
  }

  /// Tom de uma `MaterialColor` (verde/vermelho/laranja) com bom contraste
  /// nos dois temas — mais claro (300) no escuro, mais escuro (800) no claro.
  /// Usado em indicadores de valor (lucro, saldo, troco) que antes usavam
  /// sempre o mesmo tom fixo, ilegível quando o tema não "batia" com ele.
  static Color tomAdaptavel(MaterialColor cor, Brightness brightness) =>
      brightness == Brightness.dark ? cor.shade300 : cor.shade800;

  /// Escolhe preto ou branco pra sobrepor [cor], com base no brilho real
  /// dela — não no tom que o algoritmo do Material assumiria a partir de
  /// um seed. Cores de marca são escolhidas livremente pela empresa (podem
  /// ser bem claras ou bem escuras), então o contraste do texto/ícone por
  /// cima precisa ser calculado pra cor exata, não estimado.
  static Color _corContrastante(Color cor) {
    return ThemeData.estimateBrightnessForColor(cor) == Brightness.light
        ? Colors.black
        : Colors.white;
  }

  /// Mapeia o nome da fonte (vindo do modelo visual, no banco) pro
  /// TextTheme do google_fonts correspondente. Switch explícito em vez de
  /// lookup dinâmico por string — mais seguro contra nome não reconhecido
  /// (cai pro Inter, que já é o padrão do app).
  static TextTheme _textThemeParaFonte(String fonte, TextTheme base) {
    switch (fonte) {
      case 'Roboto':
        return GoogleFonts.robotoTextTheme(base);
      case 'Inter':
      default:
        return GoogleFonts.interTextTheme(base);
    }
  }

  static TextStyle _fonteParaEstilo(String fonte, {double? fontSize, FontWeight? fontWeight, Color? color}) {
    switch (fonte) {
      case 'Roboto':
        return GoogleFonts.roboto(fontSize: fontSize, fontWeight: fontWeight, color: color);
      case 'Inter':
      default:
        return GoogleFonts.inter(fontSize: fontSize, fontWeight: fontWeight, color: color);
    }
  }

  /// Converte uma cor hex ("#F5821F") em Color. Aceita com ou sem "#".
  static Color hexParaColor(String hex) {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.parse(h, radix: 16));
  }

  /// Converte uma Color de volta pra hex ("#F5821F"), pra salvar no banco.
  static String colorParaHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }
}
