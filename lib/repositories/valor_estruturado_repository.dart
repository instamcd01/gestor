import '../config/supabase_config.dart';
import '../utils/busca_utils.dart';

/// Rótulo amigável de cada um dos 8 campos estruturados de variante — usado
/// tanto no seletor de campo da tela de gerenciamento quanto em qualquer
/// outro lugar que precise mostrar o nome de um campo pro usuário.
const Map<String, String> rotulosCamposEstruturados = {
  'nome_comercial': 'Nome comercial',
  'especie': 'Espécie',
  'fase': 'Fase',
  'porte': 'Porte',
  'sabor': 'Sabor',
  'dose': 'Dose',
  'composicao': 'Composição/princípio ativo',
  'apresentacao': 'Apresentação',
};

/// Vocabulário curado dos 8 campos estruturados de variante
/// (`valores_estruturados_variante`) — fonte das sugestões de autocompletar
/// em cadastro/editar produto (ver `campos_estruturados_variante.dart`) e
/// da tela de gerenciamento (`GerenciarValoresEstruturadosScreen`). Ao
/// contrário de escanear `produtos` toda vez, é uma tabela própria: dá pra
/// renomear (cascateando pro catálogo) ou excluir um valor com erro de
/// digitação, mesmo padrão de `categorias`.
class ValorEstruturadoRepository {
  /// `categoria` nula = valor "global" (vale pra qualquer categoria, mesmo
  /// critério de `termos_variacao`), não "todas as categorias".
  Future<List<Map<String, dynamic>>> listar({
    required String campo,
    String? categoria,
  }) async {
    var query = supabase.from('valores_estruturados_variante').select('id, campo, categoria, valor').eq('campo', campo);
    query = categoria == null ? query.isFilter('categoria', null) : query.eq('categoria', categoria);
    final data = await query.order('valor');
    return List<Map<String, dynamic>>.from(data);
  }

  /// Carrega tudo de uma vez, agrupado por categoria — usado pro
  /// autocompletar nos campos de cadastro/edição (mesmo padrão de
  /// `carregarCamposEstruturadosPorCategoria`: uma consulta só, não 8).
  /// Valores "globais" (categoria nula) entram na chave `''`, e a tela que
  /// consome combina `porCategoria[categoria] + porCategoria['']` — ver
  /// `campos_estruturados_variante.dart`.
  Future<Map<String, Map<String, List<String>>>> carregarPorCategoria() async {
    final linhas = await supabase.from('valores_estruturados_variante').select('campo, categoria, valor');
    final porCategoria = <String, Map<String, Set<String>>>{};
    for (final linha in (linhas as List)) {
      final categoria = linha['categoria'] as String? ?? '';
      final campo = linha['campo'] as String;
      final valor = linha['valor'] as String;
      final porCampo = porCategoria.putIfAbsent(categoria, () => {});
      (porCampo[campo] ??= <String>{}).add(valor);
    }
    return porCategoria.map(
      (categoria, porCampo) => MapEntry(
        categoria,
        porCampo.map((campo, valores) => MapEntry(campo, valores.toList()..sort())),
      ),
    );
  }

  /// Garante que [valor] existe no vocabulário desse campo/categoria — não
  /// duplica (comparação sem acento/maiúscula). Chamado ao salvar um
  /// produto pra popular o vocabulário sozinho, sem exigir um botão
  /// "adicionar" separado no formulário — digitar e salvar já basta, igual
  /// funcionava antes desta tabela existir.
  Future<void> garantir({
    required String empresaId,
    required String campo,
    String? categoria,
    required String valor,
  }) async {
    final valorLimpo = valor.trim();
    if (valorLimpo.isEmpty) return;

    final existentes = await listar(campo: campo, categoria: categoria);
    final jaExiste = existentes.any(
      (e) => normalizarBusca(e['valor'] as String) == normalizarBusca(valorLimpo),
    );
    if (jaExiste) return;

    await supabase.from('valores_estruturados_variante').insert({
      'empresa_id': empresaId,
      'campo': campo,
      'categoria': categoria,
      'valor': valorLimpo,
    });
  }

  /// Adiciona explicitamente (tela de gerenciamento) — mesma checagem
  /// anti-duplicata de `garantir`, mas sempre tenta inserir mesmo que o
  /// chamador não tenha acabado de salvar um produto.
  Future<void> adicionar({
    required String empresaId,
    required String campo,
    String? categoria,
    required String valor,
  }) =>
      garantir(empresaId: empresaId, campo: campo, categoria: categoria, valor: valor);

  /// Renomeia um valor e cascateia pra todos os produtos que o usam nesse
  /// campo (escopado à mesma categoria do valor, se houver) — mesmo padrão
  /// de `_editarCategoria` em produto_categorias_screen.dart. Também serve
  /// pra "mesclar": renomeie um valor pro texto exato de outro já existente
  /// e depois exclua o duplicado.
  Future<void> renomear({
    required String id,
    required String campo,
    String? categoria,
    required String valorAntigo,
    required String novoValor,
  }) async {
    final novoValorLimpo = novoValor.trim();
    if (novoValorLimpo.isEmpty || novoValorLimpo == valorAntigo) return;

    await supabase.from('valores_estruturados_variante').update({'valor': novoValorLimpo}).eq('id', id);

    var query = supabase.from('produtos').update({campo: novoValorLimpo}).eq(campo, valorAntigo);
    if (categoria != null) query = query.eq('categoria', categoria);
    await query;
  }

  Future<void> excluir(String id) async {
    await supabase.from('valores_estruturados_variante').delete().eq('id', id);
  }
}
