import '../config/supabase_config.dart';
import '../models/conteudo_guia.dart';

/// Dicas do site (`conteudos_guia`). RLS: só dono/gerente da loja lê e edita.
/// Publicar = `status 'publicado'` — o trigger `conteudos_guia_set_updated_at`
/// preenche `publicado_em` na 1ª vez, e o site mostra em até 60 s (cache).
class ConteudoGuiaRepository {
  Future<List<ConteudoGuia>> listar() async {
    final data = await supabase.from('conteudos_guia').select().order('created_at', ascending: false);
    return (data as List).map((row) => ConteudoGuia.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  Future<void> atualizar(String id, Map<String, dynamic> campos) async {
    await supabase.from('conteudos_guia').update(campos).eq('id', id);
  }

  Future<void> publicar(String id) => atualizar(id, {'status': 'publicado'});

  Future<void> tirarDoSite(String id) => atualizar(id, {'status': 'rascunho'});

  Future<void> excluir(String id) async {
    await supabase.from('conteudos_guia').delete().eq('id', id);
  }
}
