import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/supabase_config.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  bool _modoCadastro = false;
  bool _carregando = false;
  bool _mostrarSenha = false;

  // Kit de Marca > "Tela de login" — busca ANTES de qualquer autenticação
  // (view `app_login_marca_publico`, legível por `anon`). Só existe 1
  // empresa de verdade usando isso hoje, então a view devolve a config
  // dela direto, sem precisar saber quem vai logar. null = mantém o
  // logo genérico da plataforma (asset local).
  String? _logoConfigurado;

  @override
  void initState() {
    super.initState();
    _carregarLogoConfigurado();
  }

  Future<void> _carregarLogoConfigurado() async {
    try {
      final data = await supabase.from('app_login_marca_publico').select().maybeSingle();
      if (data == null || data['modo'] != 'imagem') return;
      final url = data['url'] as String?;
      if (mounted && url != null) setState(() => _logoConfigurado = url);
    } catch (e) {
      debugPrint('Erro ao buscar logo configurado pro login: $e');
      // Mantém o logo genérico — tela de login nunca deve travar por causa
      // de personalização visual.
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _carregando = true);
    final auth = context.read<AuthProvider>();

    final sucesso = _modoCadastro
        ? await auth.cadastrar(_emailController.text.trim(), _senhaController.text)
        : await auth.entrar(_emailController.text.trim(), _senhaController.text);

    setState(() => _carregando = false);

    if (!sucesso && mounted && auth.erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.erro!)),
      );
    } else if (sucesso && _modoCadastro && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conta criada! Verifique seu e-mail se for solicitado.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          // Fundo em degradê + brilhos ambiente: a tela de login roda
          // sempre no tema escuro (ver BrandingProvider._temaModo padrão),
          // já que é a primeira impressão do app e ainda não há empresa
          // logada pra definir o tema real.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colorScheme.surfaceContainerLowest,
                    colorScheme.surface,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -90,
            right: -70,
            child: _BrilhoAmbiente(cor: colorScheme.primary, tamanho: 260),
          ),
          Positioned(
            bottom: -110,
            left: -90,
            child: _BrilhoAmbiente(cor: colorScheme.secondary, tamanho: 280),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 550),
                    curve: Curves.easeOutCubic,
                    builder: (context, valor, child) => Opacity(
                      opacity: valor,
                      child: Transform.translate(
                        offset: Offset(0, (1 - valor) * 24),
                        child: child,
                      ),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: SizedBox(
                              width: 200,
                              height: 200,
                              child: _logoConfigurado != null
                                  ? Image.network(
                                      _logoConfigurado!,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) =>
                                          Image.asset('lib/assets/images/logo.png', fit: BoxFit.contain),
                                    )
                                  : Image.asset('lib/assets/images/logo.png', fit: BoxFit.contain),
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            _modoCadastro ? 'Criar sua conta' : 'Bem-vindo de volta',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSurface,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _modoCadastro
                                ? 'Comece cadastrando o acesso da sua empresa.'
                                : 'Acesse o painel de gestão do seu negócio.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 32),
                          Container(
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autovalidateMode: AutovalidateMode.onUserInteraction,
                                  decoration: const InputDecoration(
                                    labelText: 'E-mail',
                                    prefixIcon: Icon(Icons.mail_outline),
                                  ),
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty) ? 'Informe seu e-mail' : null,
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _senhaController,
                                  obscureText: !_mostrarSenha,
                                  textInputAction: TextInputAction.done,
                                  autovalidateMode: AutovalidateMode.onUserInteraction,
                                  onFieldSubmitted: (_) => _carregando ? null : _enviar(),
                                  decoration: InputDecoration(
                                    labelText: 'Senha',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      icon: Icon(_mostrarSenha
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined),
                                      tooltip: _mostrarSenha ? 'Ocultar senha' : 'Mostrar senha',
                                      onPressed: () => setState(() => _mostrarSenha = !_mostrarSenha),
                                    ),
                                  ),
                                  validator: (v) =>
                                      (v == null || v.isEmpty) ? 'Informe sua senha' : null,
                                ),
                                const SizedBox(height: 22),
                                ElevatedButton(
                                  onPressed: _carregando ? null : _enviar,
                                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                                  child: _carregando
                                      ? SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: colorScheme.onPrimary,
                                          ),
                                        )
                                      : Text(_modoCadastro ? 'Criar conta' : 'Entrar'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: () => setState(() => _modoCadastro = !_modoCadastro),
                            child: Text(
                              _modoCadastro
                                  ? 'Já tenho uma conta — entrar'
                                  : 'Ainda não tenho conta — criar agora',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Brilho ambiente decorativo (glow) usado no fundo da tela de login,
/// pra dar profundidade ao tema escuro sem depender de assets extras.
class _BrilhoAmbiente extends StatelessWidget {
  const _BrilhoAmbiente({required this.cor, required this.tamanho});

  final Color cor;
  final double tamanho;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: tamanho,
        height: tamanho,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [cor.withValues(alpha: 0.28), cor.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
