import '../config/supabase_config.dart';
import '../models/tarefa.dart';

class TarefaRepository {
  Future<List<Tarefa>> listar() async {
    final data = await supabase
        .from('tarefas')
        .select()
        .order('data', ascending: true);

    return (data as List).map((row) => Tarefa.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  Future<Tarefa> criar(Tarefa tarefa, {required String empresaId, String? criadoPor}) async {
    final row = await supabase
        .from('tarefas')
        .insert({
          ...tarefa.toSupabaseMap(),
          'empresa_id': empresaId,
          'criado_por': criadoPor,
        })
        .select()
        .single();
    return Tarefa.fromSupabase(row);
  }

  Future<void> atualizar(Tarefa tarefa) async {
    if (tarefa.id == null) {
      throw ArgumentError('Tarefa sem id não pode ser atualizada');
    }
    await supabase.from('tarefas').update(tarefa.toSupabaseMap()).eq('id', tarefa.id!);
  }

  Future<void> concluir(String tarefaId, {required String concluidaPor}) async {
    await supabase.from('tarefas').update({
      'concluida': true,
      'concluida_em': DateTime.now().toIso8601String(),
      'concluida_por': concluidaPor,
    }).eq('id', tarefaId);
  }

  Future<void> reabrir(String tarefaId) async {
    await supabase.from('tarefas').update({
      'concluida': false,
      'concluida_em': null,
      'concluida_por': null,
    }).eq('id', tarefaId);
  }

  Future<void> excluir(String tarefaId) async {
    await supabase
        .from('tarefas')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', tarefaId);
  }
}
