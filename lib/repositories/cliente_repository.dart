import '../config/supabase_config.dart';
import '../models/cliente.dart';
import '../models/pet.dart';
import '../utils/telefone_utils.dart';

/// Camada de acesso a dados de clientes e seus pets. O isolamento por
/// empresa é garantido pelo RLS — não filtramos empresa_id manualmente
/// nas leituras.
class ClienteRepository {
  static const _selectComPets = '*, pets(*)';

  Future<List<Cliente>> listar() async {
    final data = await supabase
        .from('clientes')
        .select(_selectComPets)
        .isFilter('deleted_at', null)
        .order('nome');

    return (data as List)
        .map((row) => Cliente.fromSupabase(row as Map<String, dynamic>))
        .toList();
  }

  Future<Cliente> criar(Cliente cliente, {required String empresaId}) async {
    final clienteInserido = await supabase
        .from('clientes')
        .insert({...cliente.toSupabaseMap(), 'empresa_id': empresaId})
        .select()
        .single();

    final clienteId = clienteInserido['id'] as String;
    final petsInseridos = await _inserirPets(cliente.pets, clienteId);

    return Cliente.fromSupabase({...clienteInserido, 'pets': petsInseridos});
  }

  Future<void> atualizar(Cliente cliente) async {
    if (cliente.idCliente == null) {
      throw ArgumentError('Cliente sem id não pode ser atualizado');
    }

    // saldo é sempre escrito via registrar_movimentacao_saldo (abaixo) pra
    // manter o extrato completo — não deixamos o update genérico tocar nele.
    final anterior = await supabase
        .from('clientes')
        .select('saldo')
        .eq('id', cliente.idCliente!)
        .single();
    final saldoAnterior = (anterior['saldo'] as num?)?.toDouble() ?? 0.0;

    final payload = cliente.toSupabaseMap()..remove('saldo');
    await supabase.from('clientes').update(payload).eq('id', cliente.idCliente!);

    final delta = cliente.saldo - saldoAnterior;
    if (delta.abs() >= 0.01) {
      await supabase.rpc('registrar_movimentacao_saldo', params: {
        'p_cliente_id': cliente.idCliente,
        'p_tipo': delta > 0 ? 'credito' : 'debito',
        'p_valor': delta.abs(),
        'p_motivo': 'Ajuste manual no cadastro do cliente',
      });
    }

    // Estratégia simples e segura pra sincronizar os pets: substitui todos.
    // Como o volume de pets por cliente é pequeno, o custo é desprezível.
    await supabase.from('pets').delete().eq('cliente_id', cliente.idCliente!);
    await _inserirPets(cliente.pets, cliente.idCliente!);
  }

  /// Guarda a distância/tempo de rota real (Google Maps) calculados pro
  /// endereço desse cliente — evita recalcular (chamada paga à API) no
  /// próximo checkout, e alimenta os cards da Fila de Pedidos. `metadata`
  /// é jsonb com outras chaves (observação, interesses etc.) — por isso lê
  /// e faz merge em vez de sobrescrever a coluna inteira.
  Future<void> atualizarDistancia(
    String clienteId, {
    required double rangeDistancia,
    required int estimativaEntrega,
  }) async {
    final atual = await supabase.from('clientes').select('metadata').eq('id', clienteId).single();
    final metadata = Map<String, dynamic>.from((atual['metadata'] as Map<String, dynamic>?) ?? {});
    metadata['rangeDistancia'] = rangeDistancia;
    metadata['estimativaEntrega'] = estimativaEntrega;
    await supabase.from('clientes').update({'metadata': metadata}).eq('id', clienteId);
  }

  /// Desfaz o vínculo de login do cliente (`auth_user_id`) — usado quando
  /// ele perdeu o telefone antigo e não consegue mais receber o SMS de
  /// verificação. Editar `telefone` sozinho não resolve: o login continua
  /// preso à sessão antiga até esse vínculo ser limpo. No próximo login
  /// com o número atualizado, `entrar_ou_criar_cliente` reconecta este
  /// mesmo cadastro (casa por telefone quando `auth_user_id is null`) em
  /// vez de criar um cliente novo do zero. Gatilho `trg_notificar_cliente_
  /// acesso_redefinido` grava a auditoria (quem fez, quando).
  ///
  /// [novoTelefone], se informado, já atualiza o telefone na mesma chamada
  /// (evita a equipe ter que passar por "Editar Dados" antes) — sempre
  /// normalizado via `normalizarTelefoneParaAuth`, porque a RPC de login só
  /// casa por telefone se o valor salvo bater exatamente com o formato que
  /// o Supabase Auth grava no JWT (dígitos + DDI 55, sem máscara) — salvar
  /// com máscara (como o "Editar Dados" comum faz) deixaria essa
  /// redefinição inútil na prática.
  Future<void> redefinirAcesso(String clienteId, {String? novoTelefone}) async {
    final payload = <String, dynamic>{'auth_user_id': null};
    if (novoTelefone != null && novoTelefone.trim().isNotEmpty) {
      payload['telefone'] = normalizarTelefoneParaAuth(novoTelefone);
    }
    await supabase.from('clientes').update(payload).eq('id', clienteId);
  }

  Future<void> excluir(String clienteId) async {
    await supabase
        .from('clientes')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', clienteId);
  }

  Future<List<Map<String, dynamic>>> _inserirPets(List<Pet> pets, String clienteId) async {
    if (pets.isEmpty) return [];

    final payload = pets.map((p) => {...p.toSupabaseMap(), 'cliente_id': clienteId}).toList();
    final inseridos = await supabase.from('pets').insert(payload).select();
    return List<Map<String, dynamic>>.from(inseridos);
  }
}
