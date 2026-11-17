import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/venda.dart';
import '../models/zona_entrega.dart';
import '../providers/auth_provider.dart';
import '../providers/historico_vendas_provider.dart';

/// Menu "Editar pedido" (Fila e detalhes da venda): trocar entrega/retirada
/// ou zona, marcar pago antecipado e voltar status marcado por engano.
/// Toda regra fica no banco (`alterar_entrega_pedido`,
/// `marcar_pagamento_pedido`, `voltar_status_pedido`); aqui só a escolha.
/// [aoAlterar] roda depois de salvar (ex: detalhes recarrega a venda — a
/// Fila já atualiza pelo provider).
class MenuEditarPedido extends StatelessWidget {
  final Venda venda;
  final VoidCallback? aoAlterar;
  final bool comoBotao;

  const MenuEditarPedido({super.key, required this.venda, this.aoAlterar, this.comoBotao = false});

  static bool temOpcoes(Venda venda, {required bool dono}) => _opcoes(venda, dono: dono).isNotEmpty;

  static List<(String, IconData, String)> _opcoes(Venda venda, {required bool dono}) {
    final anteriores = venda.status == StatusPedido.entregue && !dono ? const <String>[] : venda.statusAnteriores;
    return [
      if (venda.podeTrocarEntrega)
        ('entrega', Icons.swap_horiz, venda.temEntrega ? 'Trocar entrega / retirada' : 'Trocar pra entrega'),
      if (venda.podeMarcarPago && !venda.pagoAntecipado) ('pago', Icons.price_check, 'Marcar como pago'),
      if (venda.pagoAntecipado) ('desfazer_pago', Icons.money_off, 'Voltar a cobrar (desfazer pago)'),
      if (anteriores.isNotEmpty) ('voltar', Icons.undo, 'Voltar status'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final dono = context.watch<AuthProvider>().isDono;
    final opcoes = _opcoes(venda, dono: dono);
    if (opcoes.isEmpty) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      tooltip: 'Editar pedido',
      onSelected: (acao) => _executar(context, acao),
      itemBuilder: (_) => [
        for (final (valor, icone, texto) in opcoes)
          PopupMenuItem(value: valor, child: ListTile(leading: Icon(icone), title: Text(texto), contentPadding: EdgeInsets.zero)),
      ],
      child: comoBotao
          ? IgnorePointer(
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Editar pedido'),
              ),
            )
          : const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.more_vert)),
    );
  }

  Future<void> _executar(BuildContext context, String acao) async {
    final provider = context.read<HistoricoVendasProvider>();
    final id = venda.idVenda!;
    final numero = venda.numeroSequencial != null ? ' #${venda.numeroSequencial}' : '';

    Future<void> Function()? salvar;
    String? sucesso;
    switch (acao) {
      case 'entrega':
        final escolha = await showDialog<({String? zonaId})>(
          context: context,
          builder: (_) => _TrocarEntregaDialog(venda: venda),
        );
        if (escolha == null) return;
        salvar = () => provider.alterarEntregaPedido(id, escolha.zonaId);
        sucesso = escolha.zonaId == null ? 'Pedido$numero virou retirada na loja.' : 'Entrega do pedido$numero atualizada.';
      case 'pago':
      case 'desfazer_pago':
        final pago = acao == 'pago';
        final ok = await _confirmar(
          context,
          titulo: pago ? 'Marcar pedido$numero como pago?' : 'Voltar a cobrar o pedido$numero?',
          texto: pago
              ? 'Use quando o cliente já pagou (ex: Pix antes da entrega). A Fila passa a mostrar "Já pago — não cobrar".'
              : 'O pedido volta a aparecer como "a cobrar" na entrega/retirada.',
          botao: pago ? 'Marcar pago' : 'Voltar a cobrar',
        );
        if (!ok) return;
        salvar = () => provider.marcarPagamentoPedido(id, pago);
        sucesso = pago ? 'Pedido$numero marcado como pago.' : 'Pedido$numero volta a ser cobrado.';
      case 'voltar':
        final status = await showDialog<String>(
          context: context,
          builder: (_) => _VoltarStatusDialog(venda: venda),
        );
        if (status == null) return;
        salvar = () => provider.voltarStatusPedido(id, status);
        sucesso = 'Pedido$numero voltou pra "${StatusPedido.rotulo(status, retirada: !venda.temEntrega)}".';
    }
    if (salvar == null || !context.mounted) return;

    final mensageiro = ScaffoldMessenger.of(context);
    try {
      await salvar();
      mensageiro.showSnackBar(SnackBar(content: Text(sucesso!)));
      aoAlterar?.call();
    } catch (e) {
      mensageiro.showSnackBar(SnackBar(
        content: Text(e is PostgrestException ? e.message : 'Não foi possível salvar. Tente de novo.'),
        backgroundColor: Colors.red.shade700,
      ));
    }
  }

  Future<bool> _confirmar(BuildContext context, {required String titulo, required String texto, required String botao}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogo, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogo, true), child: Text(botao)),
        ],
      ),
    );
    return ok == true;
  }
}

/// Retirada na loja ou uma zona de entrega ativa, com o frete que vai
/// ficar (mesma regra do carrinho/banco: grátis a partir do mínimo da zona).
class _TrocarEntregaDialog extends StatefulWidget {
  final Venda venda;
  const _TrocarEntregaDialog({required this.venda});

  @override
  State<_TrocarEntregaDialog> createState() => _TrocarEntregaDialogState();
}

class _TrocarEntregaDialogState extends State<_TrocarEntregaDialog> {
  static const _retirada = '__retirada__';
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  List<ZonaEntrega> _zonas = [];
  bool _carregando = true;
  String? _selecionado;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    try {
      final data = await Supabase.instance.client
          .from('zonas_entrega')
          .select()
          .eq('empresa_id', empresaId ?? '')
          .eq('ativo', true)
          .order('ordem');
      _zonas = (data as List).map((r) => ZonaEntrega.fromSupabase(r as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Zonas de entrega não carregadas: $e');
    }
    if (!mounted) return;
    setState(() => _carregando = false);
  }

  double _frete(ZonaEntrega zona) {
    final minimo = zona.valorMinimoFreteGratis;
    return minimo != null && widget.venda.subtotal >= minimo ? 0 : zona.valor;
  }

  /// Opção marcada hoje: retirada, ou a zona gravada no pedido (pelo nome).
  String get _atual {
    if (!widget.venda.temEntrega) return _retirada;
    return _zonas.where((z) => z.nome == widget.venda.entregaSelecionada).firstOrNull?.id ?? '__zona_antiga__';
  }

  @override
  Widget build(BuildContext context) {
    final venda = widget.venda;
    final selecionado = _selecionado ?? _atual;
    final zona = _zonas.where((z) => z.id == selecionado).firstOrNull;
    final freteNovo = selecionado == _retirada ? 0.0 : (zona != null ? _frete(zona) : venda.valorEntrega);
    final mudou = _selecionado != null && _selecionado != _atual && (selecionado == _retirada || zona != null);
    final endereco = venda.cliente.enderecoCompleto;

    return AlertDialog(
      title: const Text('Entrega ou retirada'),
      content: SizedBox(
        width: 420,
        child: _carregando
            ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: RadioGroup<String>(
                  groupValue: selecionado,
                  onChanged: (v) => setState(() => _selecionado = v),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const RadioListTile(value: _retirada, title: Text('Retirada na loja'), subtitle: Text('Sem frete')),
                      for (final z in _zonas)
                        RadioListTile(
                          value: z.id!,
                          title: Text('Entrega — ${z.nome}'),
                          subtitle: Text(_frete(z) == 0 ? 'Frete grátis' : 'Frete ${_moeda.format(_frete(z))}'),
                        ),
                      if (selecionado != _retirada && endereco.trim().isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('Cliente sem endereço cadastrado — confira antes de mandar pra entrega.',
                              style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ),
                      if (mudou) ...[
                        const Divider(height: 24),
                        Text('Frete: ${_moeda.format(venda.valorEntrega)} → ${_moeda.format(freteNovo)}'),
                        Text(
                          'Total: ${_moeda.format(venda.valorTotal)} → ${_moeda.format(venda.valorTotal - venda.valorEntrega + freteNovo)}'
                          '${venda.parcelasCartao != null && venda.parcelasCartao! > 1 ? ' + juros do parcelamento' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: mudou ? () => Navigator.pop(context, (zonaId: selecionado == _retirada ? null : zona!.id)) : null,
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

class _VoltarStatusDialog extends StatefulWidget {
  final Venda venda;
  const _VoltarStatusDialog({required this.venda});

  @override
  State<_VoltarStatusDialog> createState() => _VoltarStatusDialogState();
}

class _VoltarStatusDialogState extends State<_VoltarStatusDialog> {
  late String _status = widget.venda.statusAnteriores.first;

  @override
  Widget build(BuildContext context) {
    final venda = widget.venda;
    final retirada = !venda.temEntrega;
    return AlertDialog(
      title: Text('Voltar status — hoje: ${StatusPedido.rotulo(venda.status, retirada: retirada)}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<String>(
              groupValue: _status,
              onChanged: (v) => setState(() => _status = v ?? _status),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final s in venda.statusAnteriores)
                    RadioListTile(value: s, title: Text(StatusPedido.rotulo(s, retirada: retirada))),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              venda.status == StatusPedido.entregue
                  ? 'O pedido volta pra Fila. Se o pagamento foi confirmado só por ter sido marcado entregue, ele volta a ficar a cobrar. O cliente não recebe mensagem.'
                  : 'Pra corrigir um status marcado por engano. O cliente não recebe mensagem.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, _status), child: const Text('Voltar status')),
      ],
    );
  }
}
