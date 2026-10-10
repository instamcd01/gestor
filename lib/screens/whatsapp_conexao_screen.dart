import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/mercado_pago_config.dart';
import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';
import '../widgets/aviso_banner.dart';
import '../widgets/form_section.dart';

/// Módulo WhatsApp: conectar o número da loja pelo cadastro incorporado da
/// Meta (Coex — o mesmo número do WhatsApp Business do celular — ou número
/// novo). A janela da Meta só roda em página web, então abre o site
/// (`/whatsapp/conectar`) no navegador com um código de uso único gerado
/// aqui; a troca do código e a credencial ficam só no servidor (o app nunca
/// lê `access_token`, só o status). Mesmo esquema da conexão do Mercado
/// Pago: reconsulta o status ao voltar do navegador.
class WhatsappConexaoScreen extends StatefulWidget {
  const WhatsappConexaoScreen({super.key});

  @override
  State<WhatsappConexaoScreen> createState() => _WhatsappConexaoScreenState();
}

class _WhatsappConexaoScreenState extends State<WhatsappConexaoScreen> with WidgetsBindingObserver {
  bool _carregando = true;
  bool _abrindo = false;
  Map<String, dynamic>? _conexao;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _carregar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _carregar();
  }

  Future<void> _carregar() async {
    try {
      // Colunas explícitas: o banco só libera estas pro app (a credencial
      // da Meta não tem grant — `select('*')` falharia).
      final data = await supabase
          .from('empresa_whatsapp')
          .select(
              'numero_exibicao, nome_verificado, coexistencia, status, sync_historico_progresso, erro, conectado_em')
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _conexao = data;
        _carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar conexão do WhatsApp: $e');
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _conectar() async {
    setState(() => _abrindo = true);
    try {
      final codigo = await supabase.rpc('iniciar_conexao', params: {'p_tipo': 'whatsapp'}) as String;
      final uri = Uri.parse('$kSiteBaseUrl/whatsapp/conectar?t=$codigo');
      final abriu = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!abriu && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Não foi possível abrir o navegador.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is PostgrestException ? e.message : 'Erro ao iniciar a conexão: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _abrindo = false);
    }
  }

  Future<void> _desconectar() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desconectar o WhatsApp?'),
        content: const Text(
          'O sistema para de receber e enviar mensagens por este número (atendente, avisos de pedido e campanhas). '
          'O WhatsApp do celular continua funcionando.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Desconectar')),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    try {
      await supabase.rpc('desconectar_whatsapp');
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is PostgrestException ? e.message : 'Erro ao desconectar: $e')),
        );
      }
    }
  }

  Widget _status() {
    final c = _conexao;
    final status = c?['status'] as String?;
    if (c == null || status == 'desconectado') {
      return const AvisoBanner(texto: 'Nenhum número conectado.');
    }
    final numero = c['numero_exibicao'] as String? ?? 'Número conectado';
    final nome = c['nome_verificado'] as String?;
    final descricao = nome == null ? numero : '$numero · $nome';
    return switch (status) {
      'sincronizando' => AvisoBanner(
          tipo: TipoAviso.info,
          texto: '$descricao\nCopiando contatos e conversas dos últimos 6 meses'
              '${c['sync_historico_progresso'] == null ? '' : ' (${c['sync_historico_progresso']}%)'}. '
              'Pode usar normalmente enquanto isso.',
        ),
      'erro' => AvisoBanner(
          tipo: TipoAviso.erro,
          texto: '$descricao\nA conexão ficou incompleta: ${c['erro'] ?? 'erro desconhecido'}',
        ),
      _ => AvisoBanner(tipo: TipoAviso.sucesso, texto: '$descricao\nConectado'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final souDono = context.watch<AuthProvider>().isDono;
    final status = _conexao?['status'] as String?;
    final conectado = _conexao != null && status != 'desconectado';

    return Scaffold(
      appBar: AppBar(title: const Text('WhatsApp da Loja')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _status(),
                const SizedBox(height: 16),
                FormSection(
                  titulo: conectado ? 'Número conectado' : 'Como funciona',
                  children: [
                    const Text(
                      'Se o número da loja já está no WhatsApp Business do celular, escolha conectar a conta '
                      'existente: o celular continua funcionando e as conversas dos últimos 6 meses vêm junto.',
                    ),
                    const Text(
                      'No computador, use o WhatsApp Web pelo navegador — o app WhatsApp para Windows deixa de '
                      'funcionar com o número conectado.',
                    ),
                    if (!souDono)
                      const Text('Só o dono da loja pode conectar ou desconectar o número.')
                    else if (!conectado || status == 'erro')
                      FilledButton.icon(
                        onPressed: _abrindo ? null : _conectar,
                        icon: const Icon(Icons.link),
                        label: Text(status == 'erro' ? 'Conectar de novo' : 'Conectar meu WhatsApp'),
                      ),
                    if (souDono && conectado) OutlinedButton(onPressed: _desconectar, child: const Text('Desconectar')),
                  ],
                ),
              ],
            ),
    );
  }
}
