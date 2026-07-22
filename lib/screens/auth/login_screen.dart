import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(Icons.pets, size: 36, color: colorScheme.primary),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _modoCadastro ? 'Criar sua conta' : 'Entrar no Gestor',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
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
                          icon: Icon(_mostrarSenha ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          tooltip: _mostrarSenha ? 'Ocultar senha' : 'Mostrar senha',
                          onPressed: () => setState(() => _mostrarSenha = !_mostrarSenha),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Informe sua senha' : null,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _carregando ? null : _enviar,
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                      child: _carregando
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary),
                            )
                          : Text(_modoCadastro ? 'Criar conta' : 'Entrar'),
                    ),
                    const SizedBox(height: 12),
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
    );
  }
}
