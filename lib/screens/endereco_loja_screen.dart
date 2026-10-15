import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/plataforma_config.dart';
import '../config/supabase_config.dart';
import '../models/modulo.dart';
import '../providers/auth_provider.dart';
import '../providers/modulo_provider.dart';

/// Endereço do site da loja: subdomínio da plataforma (todo mundo) e domínio
/// próprio (módulo Domínio Próprio). Quem ativa de verdade (DNS conferido,
/// Easypanel, cadeado https) é o robô de domínios no n8n, a cada 5 min — esta
/// tela só pede/remove e mostra o andamento (`dominios_loja`).
class EnderecoLojaScreen extends StatefulWidget {
  const EnderecoLojaScreen({super.key});

  @override
  State<EnderecoLojaScreen> createState() => _EnderecoLojaScreenState();
}

class _EnderecoLojaScreenState extends State<EnderecoLojaScreen> {
  final _dominioController = TextEditingController();
  List<Map<String, dynamic>> _dominios = [];
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _dominioController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final data = await supabase
          .from('dominios_loja')
          .select('id, dominio, tipo, status, mensagem, www_ativo, ativado_em')
          .not('status', 'in', '(removido)')
          .order('created_at');
      if (!mounted) return;
      setState(() => _dominios = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      debugPrint('Erro ao carregar endereços da loja: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Map<String, dynamic>? _doTipo(String tipo, {required bool ativo}) {
    for (final d in _dominios) {
      if (d['tipo'] != tipo) continue;
      if (ativo == (d['status'] == 'ativo')) return d;
    }
    return null;
  }

  Future<void> _salvarDominio() async {
    final texto = _dominioController.text.trim();
    if (texto.isEmpty) return;
    setState(() => _salvando = true);
    try {
      await supabase.rpc('solicitar_dominio_proprio', params: {'p_dominio': texto});
      _dominioController.clear();
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      final msg = e is PostgrestException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _removerDominio() async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tirar o domínio próprio?'),
        content: const Text(
            'O site volta a ficar só no endereço da plataforma. Quem acessar pelo seu domínio não vai mais encontrar a loja.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tirar')),
        ],
      ),
    );
    if (confirmou != true) return;
    try {
      await supabase.rpc('remover_dominio_proprio');
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      final msg = e is PostgrestException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());

    final temModulo = context.watch<ModuloProvider>().ativo(Modulos.dominioProprio);
    final ehDono = context.watch<AuthProvider>().isDono;
    final subAtivo = _doTipo('subdominio', ativo: true);
    final subAndamento = _doTipo('subdominio', ativo: false);
    final proprioAtivo = _doTipo('proprio', ativo: true);
    final proprioAndamento = _doTipo('proprio', ativo: false);

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Endereço da plataforma', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (subAtivo == null && subAndamento == null)
            const _Aviso(
              icone: Icons.info_outline,
              texto: 'Defina o "Link da loja" na aba Catálogo para ganhar o seu endereço.',
            ),
          if (subAtivo != null) _CartaoDominio(dominio: subAtivo),
          if (subAndamento != null) _CartaoDominio(dominio: subAndamento),
          const SizedBox(height: 24),
          Text('Domínio próprio', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (!temModulo)
            const _Aviso(
              icone: Icons.workspace_premium_outlined,
              texto: 'Para usar um endereço seu (ex: minhaloja.com.br), instale o módulo Domínio Próprio '
                  'em Configurações › Aplicativos.',
            )
          else ...[
            if (proprioAtivo != null) _CartaoDominio(dominio: proprioAtivo),
            if (proprioAndamento != null) ...[
              _CartaoDominio(dominio: proprioAndamento),
              const SizedBox(height: 12),
              _InstrucoesDns(dominio: proprioAndamento['dominio'] as String),
            ],
            if (ehDono) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _dominioController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: proprioAtivo == null && proprioAndamento == null ? 'Seu domínio' : 'Trocar por outro domínio',
                  hintText: 'minhaloja.com.br',
                  helperText: 'Você precisa já ter comprado o domínio (ex: no Registro.br)',
                ),
                onSubmitted: (_) => _salvarDominio(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton(
                    onPressed: _salvando ? null : _salvarDominio,
                    child: Text(_salvando ? 'Salvando...' : 'Usar este domínio'),
                  ),
                  const SizedBox(width: 12),
                  if (proprioAtivo != null || proprioAndamento != null)
                    TextButton(onPressed: _removerDominio, child: const Text('Tirar domínio próprio')),
                ],
              ),
            ] else
              const _Aviso(icone: Icons.lock_outline, texto: 'Só o dono da loja pode mudar o domínio.'),
          ],
        ],
      ),
    );
  }
}

class _CartaoDominio extends StatelessWidget {
  final Map<String, dynamic> dominio;

  const _CartaoDominio({required this.dominio});

  @override
  Widget build(BuildContext context) {
    final status = dominio['status'] as String;
    final endereco = 'https://${dominio['dominio']}';
    final (rotulo, cor, icone) = switch (status) {
      'ativo' => ('No ar', Colors.green, Icons.check_circle),
      'ativando' => ('Ativando o cadeado de segurança', Colors.orange, Icons.hourglass_top),
      'erro' => ('Com problema', Colors.red, Icons.error_outline),
      'remover' => ('Saindo do ar', Colors.grey, Icons.remove_circle_outline),
      _ => ('Aguardando o apontamento', Colors.orange, Icons.hourglass_empty),
    };
    final mensagem = dominio['mensagem'] as String?;

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icone, color: cor),
        title: SelectableText(dominio['dominio'] as String),
        subtitle: Text([rotulo, if (mensagem != null && status != 'ativo') mensagem].join(' — ')),
        trailing: status == 'ativo'
            ? IconButton(
                tooltip: 'Copiar endereço',
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: endereco));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Endereço copiado')));
                },
              )
            : null,
      ),
    );
  }
}

class _InstrucoesDns extends StatelessWidget {
  final String dominio;

  const _InstrucoesDns({required this.dominio});

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.bodyMedium;
    final mono = estilo?.copyWith(fontFamily: 'monospace', fontWeight: FontWeight.bold);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Como apontar o $dominio', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text('No site onde você comprou o domínio (Registro.br, Hostinger, GoDaddy...), abra a parte de DNS '
                'e crie estes registros:', style: estilo),
            const SizedBox(height: 12),
            _LinhaDns(tipo: 'A', nome: '@ (ou deixe em branco)', valor: kIpServidorLojas, mono: mono),
            _LinhaDns(tipo: 'A', nome: 'www', valor: kIpServidorLojas, mono: mono),
            const SizedBox(height: 12),
            Text(
              'Apague outros registros A do mesmo nome, se existirem. Depois disso é automático: a gente confere a '
              'cada 5 minutos e liga o cadeado de segurança sozinho. A mudança de DNS pode levar de alguns minutos '
              'até algumas horas pra valer.',
              style: estilo,
            ),
          ],
        ),
      ),
    );
  }
}

class _LinhaDns extends StatelessWidget {
  final String tipo;
  final String nome;
  final String valor;
  final TextStyle? mono;

  const _LinhaDns({required this.tipo, required this.nome, required this.valor, required this.mono});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 32, child: Text(tipo, style: mono)),
          Expanded(child: Text(nome)),
          SelectableText(valor, style: mono),
          IconButton(
            tooltip: 'Copiar',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () => Clipboard.setData(ClipboardData(text: valor)),
          ),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final IconData icone;
  final String texto;

  const _Aviso({required this.icone, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(leading: Icon(icone), title: Text(texto)),
    );
  }
}
