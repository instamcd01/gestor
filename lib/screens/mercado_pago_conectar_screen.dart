import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';
import '../widgets/aviso_banner.dart';
import '../widgets/form_section.dart';

/// Client ID da aplicação Mercado Pago DA PLATAFORMA (uma só, não muda por
/// loja) — aplicação "Delivery Pet MP" no painel do Mercado Pago
/// (developers.mercadopago.com/panel/app/8162106481494061). client_id não
/// é segredo (vai exposto na própria URL de autorização); o client_secret
/// fica só no servidor do site (env var), nunca aqui no app.
const String kMercadoPagoClientId = '8162106481494061';

/// URL base do site (gestor-loja) — usada pra montar o redirect_uri do
/// OAuth (`$kSiteBaseUrl/mp/callback`). Precisa bater exatamente com a URL
/// de redirecionamento cadastrada na aplicação do Mercado Pago.
const String kSiteBaseUrl = 'https://deliverypetexpress.com.br';

/// Configurações > Vendas > Pagamento Online: conectar a conta Mercado
/// Pago da loja (OAuth/split marketplace — o dinheiro cai direto pro
/// lojista, nunca passa pela plataforma) e escolher se o site oferece só
/// pagamento na entrega, só online, ou os dois. Restrito ao dono (mesma
/// regra de "Integrar com Plataformas": credencial é dado sensível).
///
/// O OAuth abre no navegador externo (não webview/deep link — mais simples
/// e sem dependência nova); a troca do código por token acontece inteira
/// no servidor do site (`/mp/callback`, tem o client_secret). O app só
/// reconsulta o status (`mp_esta_conectado`) quando volta a ficar em
/// primeiro plano, pra refletir sozinho depois que o lojista conectar.
class MercadoPagoConectarScreen extends StatefulWidget {
  const MercadoPagoConectarScreen({super.key});

  @override
  State<MercadoPagoConectarScreen> createState() => _MercadoPagoConectarScreenState();
}

class _MercadoPagoConectarScreenState extends State<MercadoPagoConectarScreen> with WidgetsBindingObserver {
  bool _carregando = true;
  bool _conectado = false;
  String _disponibilidade = 'entrega';

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
    // Recarrega ao voltar do navegador externo (fluxo de OAuth) — sem
    // isso, quem conecta a conta só veria o status atualizado saindo e
    // voltando manualmente pra essa tela.
    if (state == AppLifecycleState.resumed) _carregar();
  }

  Future<void> _carregar() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) {
      setState(() => _carregando = false);
      return;
    }
    try {
      final conectado = await supabase.rpc('mp_esta_conectado') as bool;
      final data = await supabase
          .from('empresas')
          .select('pagamento_online_disponibilidade')
          .eq('id', empresaId)
          .single();
      if (!mounted) return;
      setState(() {
        _conectado = conectado;
        _disponibilidade = data['pagamento_online_disponibilidade'] as String? ?? 'entrega';
        _carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar status do Mercado Pago: $e');
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _conectar() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;

    if (kMercadoPagoClientId.isEmpty || kSiteBaseUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Integração ainda não configurada — fale com o suporte.')),
      );
      return;
    }

    final redirectUri = Uri.encodeComponent('$kSiteBaseUrl/mp/callback');
    final uri = Uri.parse(
      'https://auth.mercadopago.com/authorization'
      '?response_type=code&client_id=$kMercadoPagoClientId&redirect_uri=$redirectUri&state=$empresaId',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o navegador.')),
      );
    }
  }

  Future<void> _mudarDisponibilidade(String valor) async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    final anterior = _disponibilidade;
    setState(() => _disponibilidade = valor);
    try {
      await supabase.from('empresas').update({'pagamento_online_disponibilidade': valor}).eq('id', empresaId);
    } catch (e) {
      if (mounted) {
        setState(() => _disponibilidade = anterior);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final souDono = context.watch<AuthProvider>().isDono;

    return Scaffold(
      appBar: AppBar(title: const Text('Pagamento Online')),
      body: !souDono
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Apenas o dono da empresa pode configurar pagamento online.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            )
          : _carregando
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const AvisoBanner(
                      texto: 'O cliente paga direto no site com cartão ou Pix, e o dinheiro cai na sua '
                          'própria conta Mercado Pago — nenhum valor passa pela conta da plataforma.',
                    ),
                    const SizedBox(height: 16),
                    FormSection(
                      titulo: 'Conexão com o Mercado Pago',
                      children: [
                        Row(
                          children: [
                            Icon(
                              _conectado ? Icons.check_circle : Icons.cancel_outlined,
                              color: _conectado ? Colors.green.shade600 : Theme.of(context).colorScheme.error,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_conectado ? 'Conta conectada' : 'Nenhuma conta conectada'),
                            ),
                          ],
                        ),
                        ElevatedButton(
                          onPressed: _conectar,
                          child: Text(_conectado ? 'Reconectar conta' : 'Conectar com Mercado Pago'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FormSection(
                      titulo: 'Disponibilidade no site',
                      children: [
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Só na entrega'),
                          subtitle: const Text('Dinheiro/Pix/Cartão cobrados na hora da entrega ou retirada'),
                          value: 'entrega',
                          groupValue: _disponibilidade,
                          onChanged: (v) => _mudarDisponibilidade(v!),
                        ),
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Só online'),
                          subtitle: const Text('Cliente só pode pagar pelo site, direto no checkout'),
                          value: 'online',
                          groupValue: _disponibilidade,
                          onChanged: _conectado ? (v) => _mudarDisponibilidade(v!) : null,
                        ),
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Os dois'),
                          subtitle: const Text('Cliente escolhe entre pagar online ou na entrega'),
                          value: 'ambos',
                          groupValue: _disponibilidade,
                          onChanged: _conectado ? (v) => _mudarDisponibilidade(v!) : null,
                        ),
                        if (!_conectado)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Conecte sua conta Mercado Pago acima pra habilitar essas opções.',
                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
    );
  }
}
