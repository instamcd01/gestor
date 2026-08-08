/// Um item do kit de marca da empresa — imagem enviada pelo dono, marcada
/// por tipo. 'mascote' é o único tipo que aceita várias linhas (galeria de
/// variações); os outros 3 têm no máximo 1 ativo por empresa (índice único
/// parcial no banco, upload novo substitui o anterior).
class MarcaAtivo {
  final String? id;
  final String tipo; // 'mascote' | 'logo_completa' | 'logo_slogan' | 'nome_loja_imagem'
  final String? rotulo;
  final String url;
  final int ordem;

  const MarcaAtivo({
    this.id,
    required this.tipo,
    this.rotulo,
    required this.url,
    this.ordem = 0,
  });

  factory MarcaAtivo.fromSupabase(Map<String, dynamic> row) {
    return MarcaAtivo(
      id: row['id'] as String?,
      tipo: row['tipo']?.toString() ?? '',
      rotulo: row['rotulo']?.toString(),
      url: row['url']?.toString() ?? '',
      ordem: (row['ordem'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'tipo': tipo,
      'rotulo': rotulo,
      'url': url,
      'ordem': ordem,
    };
  }
}

/// Rótulo amigável de cada tipo — usado nos títulos de seção da tela de
/// Kit de Marca.
const Map<String, String> rotulosTipoMarcaAtivo = {
  'mascote': 'Mascote',
  'logo_completa': 'Logo completa',
  'logo_slogan': 'Logo com slogan',
  'nome_loja_imagem': 'Nome da loja (imagem)',
};

/// Uma posição configurável de onde a marca aparece (header do site, topo
/// da barra lateral do app, etc.) — 'texto' mostra o nome da empresa como
/// texto simples, 'imagem' mostra o [ativo] resolvido.
class MarcaPosicao {
  final String? id;
  final String posicao; // 'site_header' | 'site_sidebar' | 'app_drawer' | 'app_sidebar'
  final String modo; // 'texto' | 'imagem'
  final String? ativoId;
  final MarcaAtivo? ativo; // preenchido só depois do join feito em MarcaRepository

  const MarcaPosicao({
    this.id,
    required this.posicao,
    this.modo = 'texto',
    this.ativoId,
    this.ativo,
  });

  factory MarcaPosicao.fromSupabase(Map<String, dynamic> row) {
    return MarcaPosicao(
      id: row['id'] as String?,
      posicao: row['posicao']?.toString() ?? '',
      modo: row['modo']?.toString() ?? 'texto',
      ativoId: row['ativo_id'] as String?,
    );
  }
}

/// Rótulo amigável de cada posição — usado na tela de Kit de Marca.
const Map<String, String> rotulosPosicao = {
  'site_header': 'Cabeçalho do site',
  'site_sidebar': 'Barra lateral do site',
  'app_inicio': 'Tela inicial do app (topo)',
  'app_drawer': 'Menu do app (celular)',
  'app_sidebar': 'Barra lateral do app (tablet/desktop)',
  'app_login': 'Tela de login do app',
};
