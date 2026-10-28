import '../config/supabase_config.dart';

/// Uma conversa do WhatsApp da loja (atendente virtual + Lucas).
class ConversaWhatsappResumo {
  final String conversaId;
  final String? clienteId;
  final String clienteNome;
  final String telefone;
  final String ultimaMensagem;
  final bool ultimaDoCliente;
  final DateTime ultimaEm;
  final DateTime? chamouDonoEm;
  final String? chamouDonoMotivo;
  final DateTime? roboPausadoAte;

  ConversaWhatsappResumo({
    required this.conversaId,
    required this.clienteId,
    required this.clienteNome,
    required this.telefone,
    required this.ultimaMensagem,
    required this.ultimaDoCliente,
    required this.ultimaEm,
    required this.chamouDonoEm,
    required this.chamouDonoMotivo,
    required this.roboPausadoAte,
  });

  bool get roboPausado => roboPausadoAte != null && roboPausadoAte!.isAfter(DateTime.now());

  /// O atendente virtual chamou o dono nas últimas 6h (mesma janela do banco).
  bool get esperandoDono =>
      chamouDonoEm != null && DateTime.now().difference(chamouDonoEm!) < const Duration(hours: 6);

  factory ConversaWhatsappResumo.fromJson(Map<String, dynamic> j) => ConversaWhatsappResumo(
        conversaId: j['conversa_id'] as String,
        clienteId: j['cliente_id'] as String?,
        clienteNome: (j['cliente_nome'] ?? j['telefone'] ?? '').toString(),
        telefone: (j['telefone'] ?? '').toString(),
        ultimaMensagem: (j['ultima_mensagem'] ?? '').toString(),
        ultimaDoCliente: j['ultima_direcao'] == 'incoming',
        ultimaEm: DateTime.parse(j['ultima_em'] as String).toLocal(),
        chamouDonoEm: j['chamou_dono_em'] == null ? null : DateTime.parse(j['chamou_dono_em'] as String).toLocal(),
        chamouDonoMotivo: j['chamou_dono_motivo'] as String?,
        roboPausadoAte: j['robo_pausado_ate'] == null ? null : DateTime.parse(j['robo_pausado_ate'] as String).toLocal(),
      );
}

/// Quem escreveu cada mensagem: o cliente, o atendente virtual ou a loja (Lucas).
enum AutorMensagem { cliente, robo, loja }

class MensagemWhatsapp {
  final String texto;
  final AutorMensagem autor;
  final DateTime criadaEm;

  MensagemWhatsapp({required this.texto, required this.autor, required this.criadaEm});

  factory MensagemWhatsapp.fromJson(Map<String, dynamic> j) {
    final metadata = j['metadata'] is Map ? j['metadata'] as Map : const {};
    final autor = j['direcao'] == 'incoming'
        ? AutorMensagem.cliente
        : (metadata['origem'] == 'robo' ? AutorMensagem.robo : AutorMensagem.loja);
    return MensagemWhatsapp(
      texto: (j['conteudo'] ?? '[${j['tipo']}]').toString(),
      autor: autor,
      criadaEm: DateTime.parse(j['created_at'] as String).toLocal(),
    );
  }
}

/// Detalhe de uma conversa: o que o atendente virtual já passou pro dono
/// (resumo do pedido e endereço em partes) + as mensagens.
class ConversaWhatsappDetalhe {
  final ConversaWhatsappResumo resumo;
  final String? resumoParaDono;
  final Map<String, dynamic>? enderecoPedido;
  final List<MensagemWhatsapp> mensagens;

  ConversaWhatsappDetalhe({
    required this.resumo,
    required this.resumoParaDono,
    required this.enderecoPedido,
    required this.mensagens,
  });
}

class ConversaWhatsappRepository {
  Future<List<ConversaWhatsappResumo>> listarRecentes({int dias = 7}) async {
    final data = await supabase.rpc('whatsapp_conversas_recentes', params: {'p_dias': dias});
    return (data as List).map((e) => ConversaWhatsappResumo.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Funciona também pra conversa de teste (o toque no aviso "[TESTE]" abre ela),
  /// que a lista esconde de propósito.
  Future<ConversaWhatsappDetalhe?> buscar(String conversaId) async {
    final conversa = await supabase
        .from('conversas')
        .select('id, cliente_id, telefone, contexto, clientes(nome)')
        .eq('id', conversaId)
        .maybeSingle();
    if (conversa == null) return null;

    final mensagens = await supabase
        .from('mensagens')
        .select('conteudo, tipo, direcao, metadata, created_at')
        .eq('conversa_id', conversaId)
        .order('created_at', ascending: false)
        .limit(100);
    final lista = (mensagens as List).map((e) => MensagemWhatsapp.fromJson(e as Map<String, dynamic>)).toList().reversed.toList();

    final contexto = conversa['contexto'] is Map ? Map<String, dynamic>.from(conversa['contexto'] as Map) : <String, dynamic>{};
    final cliente = conversa['clientes'] is Map ? conversa['clientes'] as Map : const {};
    final ultima = lista.isNotEmpty ? lista.last : null;
    final resumo = ConversaWhatsappResumo.fromJson({
      'conversa_id': conversa['id'],
      'cliente_id': conversa['cliente_id'],
      'cliente_nome': (cliente['nome'] as String?)?.trim().isNotEmpty == true ? cliente['nome'] : conversa['telefone'],
      'telefone': conversa['telefone'],
      'ultima_mensagem': ultima?.texto ?? '',
      'ultima_direcao': ultima?.autor == AutorMensagem.cliente ? 'incoming' : 'outgoing',
      'ultima_em': (ultima?.criadaEm ?? DateTime.now()).toUtc().toIso8601String(),
      'chamou_dono_em': contexto['chamou_dono_em'],
      'chamou_dono_motivo': contexto['chamou_dono_motivo'],
      'robo_pausado_ate': contexto['robo_pausado_ate'],
    });
    return ConversaWhatsappDetalhe(
      resumo: resumo,
      resumoParaDono: contexto['chamou_dono_resumo'] as String?,
      enderecoPedido: contexto['endereco_pedido'] is Map ? Map<String, dynamic>.from(contexto['endereco_pedido'] as Map) : null,
      mensagens: lista,
    );
  }

  /// [horas] = 0 religa o atendente virtual nesta conversa.
  Future<DateTime?> pausarRobo(String conversaId, int horas) async {
    final ate = await supabase.rpc('whatsapp_pausar_robo', params: {'p_conversa_id': conversaId, 'p_horas': horas});
    return ate == null ? null : DateTime.parse(ate as String).toLocal();
  }
}
