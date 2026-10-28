import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../repositories/conversa_whatsapp_repository.dart';
import 'carrinhos_do_dia_screen.dart';

String _hora(DateTime d) {
  final agora = DateTime.now();
  final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (d.year == agora.year && d.month == agora.month && d.day == agora.day) return hm;
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} $hm';
}

/// Conversas do WhatsApp da loja dos últimos 7 dias — o que o atendente
/// virtual respondeu e quem está esperando o dono.
class ConversasWhatsappScreen extends StatefulWidget {
  const ConversasWhatsappScreen({super.key});

  @override
  State<ConversasWhatsappScreen> createState() => _ConversasWhatsappScreenState();
}

class _ConversasWhatsappScreenState extends State<ConversasWhatsappScreen> {
  late Future<List<ConversaWhatsappResumo>> _future;
  bool _incluirTestes = false;

  @override
  void initState() {
    super.initState();
    _future = ConversaWhatsappRepository().listarRecentes();
  }

  Future<void> _recarregar() async {
    setState(() => _future = ConversaWhatsappRepository().listarRecentes(incluirTestes: _incluirTestes));
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversas do WhatsApp'),
        actions: [
          // Conversas do simulador de testes do atendente virtual (números 55219000000xx).
          IconButton(
            tooltip: _incluirTestes ? 'Esconder conversas de teste' : 'Mostrar conversas de teste',
            icon: Icon(_incluirTestes ? Icons.science : Icons.science_outlined),
            onPressed: () {
              _incluirTestes = !_incluirTestes;
              _recarregar();
            },
          ),
        ],
      ),
      body: FutureBuilder<List<ConversaWhatsappResumo>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro ao carregar: ${snapshot.error}'));
          }
          final conversas = snapshot.data ?? [];
          if (conversas.isEmpty) {
            return const Center(child: Text('Nenhuma conversa nos últimos 7 dias.'));
          }
          return RefreshIndicator(
            onRefresh: _recarregar,
            child: ListView.separated(
              itemCount: conversas.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final c = conversas[i];
                final cor = Theme.of(context).colorScheme;
                return ListTile(
                  leading: Icon(
                    c.esperandoDono ? Icons.notifications_active : (c.roboPausado ? Icons.person : Icons.smart_toy_outlined),
                    color: c.esperandoDono ? cor.error : null,
                  ),
                  title: Text(c.clienteNome),
                  subtitle: Text(
                    '${c.esperandoDono ? (c.chamouDonoMotivo == 'fechar_pedido' ? 'Quer fechar pedido • ' : 'Precisa de você • ') : ''}'
                    '${c.ultimaDoCliente ? '' : 'Loja: '}${c.ultimaMensagem}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(_hora(c.ultimaEm), style: Theme.of(context).textTheme.bodySmall),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ConversaWhatsappScreen(conversaId: c.conversaId)),
                    );
                    if (mounted) _recarregar();
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Uma conversa: resumo do pedido que o atendente virtual montou, atalho
/// pro rascunho em "Carrinhos do dia" e controle do robô nesta conversa.
class ConversaWhatsappScreen extends StatefulWidget {
  final String conversaId;

  const ConversaWhatsappScreen({super.key, required this.conversaId});

  @override
  State<ConversaWhatsappScreen> createState() => _ConversaWhatsappScreenState();
}

class _ConversaWhatsappScreenState extends State<ConversaWhatsappScreen> {
  final _repo = ConversaWhatsappRepository();
  late Future<ConversaWhatsappDetalhe?> _future;
  bool _alterandoRobo = false;

  @override
  void initState() {
    super.initState();
    _future = _repo.buscar(widget.conversaId);
  }

  void _recarregar() => setState(() => _future = _repo.buscar(widget.conversaId));

  Future<void> _alternarRobo(ConversaWhatsappResumo c) async {
    setState(() => _alterandoRobo = true);
    try {
      // Pausa por 12h: tempo de o dono fechar o atendimento sem o robô atravessar.
      await _repo.pausarRobo(c.conversaId, c.roboPausado ? 0 : 12);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(c.roboPausado ? 'Atendente virtual religado nesta conversa.' : 'Atendente virtual pausado por 12h nesta conversa.'),
      ));
      _recarregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível: $e')));
    } finally {
      if (mounted) setState(() => _alterandoRobo = false);
    }
  }

  Future<void> _abrirWhatsapp(String telefone) async {
    final numero = telefone.replaceAll(RegExp(r'\D'), '');
    final ok = await launchUrl(Uri.parse('https://wa.me/$numero'), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não consegui abrir o WhatsApp.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ConversaWhatsappDetalhe?>(
      future: _future,
      builder: (context, snapshot) {
        final detalhe = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(detalhe?.resumo.clienteNome ?? 'Conversa'),
            actions: [
              if (detalhe != null)
                IconButton(
                  tooltip: 'Abrir no WhatsApp',
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () => _abrirWhatsapp(detalhe.resumo.telefone),
                ),
              IconButton(tooltip: 'Atualizar', icon: const Icon(Icons.refresh), onPressed: _recarregar),
            ],
          ),
          body: Builder(builder: (context) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) return Center(child: Text('Erro ao carregar: ${snapshot.error}'));
            if (detalhe == null) return const Center(child: Text('Conversa não encontrada.'));
            return Column(
              children: [
                _cabecalho(context, detalhe),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: detalhe.mensagens.length,
                    itemBuilder: (context, i) => _balao(context, detalhe.mensagens[detalhe.mensagens.length - 1 - i]),
                  ),
                ),
              ],
            );
          }),
        );
      },
    );
  }

  Widget _cabecalho(BuildContext context, ConversaWhatsappDetalhe d) {
    final c = d.resumo;
    final tema = Theme.of(context);
    final end = d.enderecoPedido;
    final enderecoTexto = end == null
        ? null
        : [end['rua'], end['numero'], end['complemento'], end['bairro']].where((v) => v != null && '$v'.isNotEmpty).join(', ') +
            (end['referencia'] != null ? ' (ref: ${end['referencia']})' : '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c.esperandoDono && d.resumoParaDono != null) ...[
            Text(c.chamouDonoMotivo == 'fechar_pedido' ? 'Pedido pra confirmar' : 'Precisa de você',
                style: tema.textTheme.titleSmall?.copyWith(color: tema.colorScheme.error)),
            const SizedBox(height: 4),
            Text(d.resumoParaDono!),
            const SizedBox(height: 8),
          ] else if (enderecoTexto != null) ...[
            Text('Endereço informado: $enderecoTexto'),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (c.chamouDonoMotivo == 'fechar_pedido')
                FilledButton.icon(
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text('Abrir rascunho'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CarrinhosDoDiaScreen()),
                  ),
                ),
              OutlinedButton.icon(
                icon: _alterandoRobo
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(c.roboPausado ? Icons.smart_toy_outlined : Icons.pan_tool_outlined),
                label: Text(c.roboPausado ? 'Religar atendente virtual' : 'Assumir (pausar robô 12h)'),
                onPressed: _alterandoRobo ? null : () => _alternarRobo(c),
              ),
            ],
          ),
          if (c.roboPausado)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Robô pausado até ${_hora(c.roboPausadoAte!)}', style: tema.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }

  Widget _balao(BuildContext context, MensagemWhatsapp m) {
    final cor = Theme.of(context).colorScheme;
    final doCliente = m.autor == AutorMensagem.cliente;
    final fundo = switch (m.autor) {
      AutorMensagem.cliente => cor.surfaceContainerHighest,
      AutorMensagem.robo => cor.secondaryContainer,
      AutorMensagem.loja => cor.primaryContainer,
    };
    final rotulo = switch (m.autor) {
      AutorMensagem.cliente => '',
      AutorMensagem.robo => 'Atendente virtual • ',
      AutorMensagem.loja => 'Loja • ',
    };
    return Align(
      alignment: doCliente ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(m.texto),
            const SizedBox(height: 2),
            Text('$rotulo${_hora(m.criadaEm)}', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
