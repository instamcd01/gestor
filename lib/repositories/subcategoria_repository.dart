import '../config/supabase_config.dart';

/// Subcategorias são sempre escopadas a uma categoria — o mesmo texto
/// (ex. "Adultos") significa coisas diferentes em categorias diferentes.
/// Criação centralizada aqui pra que cadastro/edição de produto e a tela
/// Gerenciar Categorias apliquem a mesma regra de duplicidade.
class SubcategoriaRepository {
  /// Cria a subcategoria em [categoriaId] e devolve o nome gravado. Se já
  /// existir uma com o mesmo nome (sem diferenciar maiúsculas), não cria
  /// outra: devolve o nome da existente pra ela ser selecionada.
  ///
  /// O índice único do banco (categoria_id, nome) diferencia maiúsculas,
  /// então a checagem case-insensitive tem que ser feita aqui.
  Future<String> criarOuObter({
    required String categoriaId,
    required String nome,
  }) async {
    final nomeLimpo = nome.trim();
    if (nomeLimpo.isEmpty) throw ArgumentError('Nome da subcategoria vazio');

    final existentes = List<Map<String, dynamic>>.from(await supabase
        .from('subcategorias')
        .select('nome, ordem, empresa_id')
        .eq('categoria_id', categoriaId));

    for (final s in existentes) {
      final atual = s['nome'] as String;
      if (atual.toLowerCase() == nomeLimpo.toLowerCase()) return atual;
    }

    final empresaId = existentes.isNotEmpty
        ? existentes.first['empresa_id'] as String
        : (await supabase.from('categorias').select('empresa_id').eq('id', categoriaId).single())['empresa_id']
            as String;
    final proximaOrdem = existentes.isEmpty
        ? 0
        : existentes.map((s) => s['ordem'] as int).reduce((a, b) => a > b ? a : b) + 1;

    await supabase.from('subcategorias').insert({
      'nome': nomeLimpo,
      'ordem': proximaOrdem,
      'empresa_id': empresaId,
      'categoria_id': categoriaId,
    });
    return nomeLimpo;
  }
}
