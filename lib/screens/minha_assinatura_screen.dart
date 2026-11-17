import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/plataforma_config.dart';

/// Assinatura da loja na INARI (Onda 3): plano, situação, próxima cobrança,
/// assinar/trocar de plano e cancelar. Tudo vem da RPC `minha_assinatura`
/// (só a própria loja). Pagar, trocar e cancelar acontecem no site
/// (`/assinar`), aberto no navegador com um código de uso único de
/// `iniciar_conexao('assinatura')` — o mesmo esquema da conexão com o
/// Mercado Pago. Só o dono gera o código (o banco recusa os demais).
class MinhaAssinaturaScreen extends StatefulWidget {
  const MinhaAssinaturaScreen({super.key});

  @override
  State<MinhaAssinaturaScreen> createState() => _MinhaAssinaturaScreenState();
}

class _MinhaAssinaturaScreenState extends State<MinhaAssinaturaScreen> {
  Map<String, dynamic>? _dados;
  String? _erro;
  bool _carregando = true;
  bool _abrindo = false;

  static final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  static final _data = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final resposta = await Supabase.instance.client.rpc('minha_assinatura');
      if (!mounted) return;
      setState(() {
        _dados = resposta == null ? null : Map<String, dynamic>.from(resposta as Map);
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar a assinatura.';
        _carregando = false;
      });
    }
  }

  /// Abre o site de assinatura com um código de uso único (30 min).
  Future<void> _abrirSite({String? plano, bool cancelar = false}) async {
    if (_abrindo) return;
    setState(() => _abrindo = true);
    try {
      final codigo = await Supabase.instance.client.rpc('iniciar_conexao', params: {'p_tipo': 'assinatura'}) as String;
      final uri = Uri.https(kDominioBaseLojas, '/assinar', {
        'codigo': codigo,
        if (plano != null) 'plano': plano,
        if (cancelar) 'acao': 'cancelar',
      });
      final abriu = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!abriu && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível abrir o navegador.')));
      }
    } catch (e) {
      if (mounted) {
        final texto = e.toString().contains('Só o dono')
            ? 'Só o dono da loja pode mexer na assinatura.'
            : 'Não foi possível abrir a assinatura. Tente de novo.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
      }
    } finally {
      if (mounted) setState(() => _abrindo = false);
    }
  }

  DateTime? _dataDe(String chave) {
    final valor = _dados?[chave];
    return valor == null ? null : DateTime.tryParse(valor.toString())?.toLocal();
  }

  String _moedaDe(dynamic valor) => valor == null ? '' : _moeda.format((valor as num).toDouble());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Minha assinatura')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? _Erro(texto: _erro!, onTentar: _carregar)
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _cartaoSituacao(context),
                      const SizedBox(height: 20),
                      if (_dados?['situacao'] != 'interna') ..._planos(context),
                    ],
                  ),
                ),
    );
  }

  Widget _cartaoSituacao(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final situacao = (_dados?['situacao'] as String?) ?? 'sem_assinatura';
    final planoNome = _dados?['plano_nome'] as String?;
    final preco = _dados?['preco_mensal'];
    final testeFim = _dataDe('teste_fim');
    final pagoAte = _dataDe('pago_ate');
    final limite = _dataDe('limite_carencia');
    final automatica = _dados?['cobranca_automatica'] == true;
    final canceladaEm = _dataDe('cancelada_em');

    final (String titulo, String texto, Color cor, IconData icone) = switch (situacao) {
      'interna' => (
          'Plano interno',
          'Esta loja usa a INARI sem cobrança.',
          cores.primary,
          Icons.verified_outlined,
        ),
      'teste' => (
          'Teste grátis',
          testeFim != null
              ? 'Seu teste vai até ${_data.format(testeFim)} (${_diasAte(testeFim)}). Escolha um plano antes disso para não ter interrupção.'
              : 'Você está no período de teste.',
          Colors.blue,
          Icons.hourglass_bottom_outlined,
        ),
      'ativa' => (
          'Assinatura ativa',
          [
            if (pagoAte != null) 'Pago até ${_data.format(pagoAte)}.',
            automatica
                ? 'A próxima cobrança é automática pelo Mercado Pago.'
                : canceladaEm != null
                    ? 'A cobrança automática foi cancelada; a loja funciona até o fim do período pago.'
                    : 'Sem cobrança automática ligada.',
          ].join(' '),
          Colors.green,
          Icons.check_circle_outline,
        ),
      'atrasada' => (
          'Pagamento atrasado',
          limite != null
              ? 'Não recebemos o pagamento. Regularize até ${_data.format(limite)} para a loja não ficar só em modo leitura.'
              : 'Não recebemos o pagamento. Regularize para a loja não ficar só em modo leitura.',
          Colors.orange,
          Icons.warning_amber_outlined,
        ),
      'suspensa' => (
          'Loja em modo leitura',
          'A assinatura está sem pagamento. Seus dados estão guardados: escolha um plano para voltar a usar tudo.',
          cores.error,
          Icons.lock_outline,
        ),
      _ => (
          'Sem assinatura',
          'Escolha um plano para usar a INARI.',
          cores.outline,
          Icons.info_outline,
        ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone, color: cor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(titulo, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: cor)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(texto),
            if (planoNome != null && situacao != 'interna') ...[
              const SizedBox(height: 12),
              Text(
                'Plano: $planoNome${preco != null ? ' · ${_moedaDe(preco)}/mês' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            if (situacao == 'ativa' && automatica) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _abrindo ? null : () => _confirmarCancelamento(context),
                  style: TextButton.styleFrom(foregroundColor: cores.error),
                  child: const Text('Cancelar assinatura'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _planos(BuildContext context) {
    final planos = ((_dados?['planos'] as List?) ?? const []).map((p) => Map<String, dynamic>.from(p as Map)).toList();
    if (planos.isEmpty) return const [];
    final atual = _dados?['plano'] as String?;
    final situacao = _dados?['situacao'] as String?;
    final assinando = situacao == 'ativa' && _dados?['cobranca_automatica'] == true;

    return [
      Text('Planos', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      for (final p in planos)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(p['nome'] as String? ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    ),
                    if (p['preco_mensal'] != null)
                      Text('${_moedaDe(p['preco_mensal'])}/mês', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                if ((p['descricao'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(p['descricao'] as String),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: p['slug'] == atual && assinando
                      ? const Chip(label: Text('Seu plano'))
                      : FilledButton(
                          onPressed: _abrindo ? null : () => _abrirSite(plano: p['slug'] as String?),
                          child: Text(assinando ? 'Trocar para este' : 'Assinar este plano'),
                        ),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 8),
      Text(
        'O pagamento é feito pelo Mercado Pago, no navegador. Depois de pagar, volte aqui e puxe a tela para atualizar.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ];
  }

  Future<void> _confirmarCancelamento(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar a assinatura?'),
        content: const Text(
            'A cobrança automática para. A loja continua funcionando até o fim do período pago e nenhum dado é apagado.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continuar')),
        ],
      ),
    );
    if (ok == true) await _abrirSite(cancelar: true);
  }

  String _diasAte(DateTime data) {
    final dias = data.difference(DateTime.now()).inDays;
    if (dias <= 0) return 'termina hoje';
    if (dias == 1) return 'falta 1 dia';
    return 'faltam $dias dias';
  }
}

class _Erro extends StatelessWidget {
  const _Erro({required this.texto, required this.onTentar});
  final String texto;
  final VoidCallback onTentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(texto),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onTentar, child: const Text('Tentar de novo')),
        ],
      ),
    );
  }
}
