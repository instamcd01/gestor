import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

/// Primeiro acesso: o usuário ainda não tem empresa vinculada. Ou ele cria
/// uma empresa nova (dono), ou entra numa já existente com um código de
/// convite gerado por um dono (funcionário).
class OnboardingEmpresaScreen extends StatefulWidget {
  const OnboardingEmpresaScreen({super.key});

  @override
  State<OnboardingEmpresaScreen> createState() => _OnboardingEmpresaScreenState();
}

class _OnboardingEmpresaScreenState extends State<OnboardingEmpresaScreen> {
  final _nomeController = TextEditingController();
  final _codigoController = TextEditingController();
  bool _temConvite = false;
  bool _carregando = false;

  @override
  void dispose() {
    _nomeController.dispose();
    _codigoController.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    final auth = context.read<AuthProvider>();
    setState(() => _carregando = true);

    final sucesso = _temConvite
        ? await auth.entrarComConvite(_codigoController.text.trim())
        : await auth.criarEmpresa(_nomeController.text.trim());

    if (!mounted) return;
    setState(() => _carregando = false);

    if (!sucesso && auth.erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.erro!)),
      );
    }
  }

  bool get _podeConfirmar => _temConvite
      ? _codigoController.text.trim().isNotEmpty
      : _nomeController.text.trim().isNotEmpty;

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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    _temConvite ? Icons.group_add_outlined : Icons.storefront,
                    size: 48,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _temConvite ? 'Entrar numa empresa existente' : 'Vamos configurar sua empresa',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _temConvite
                        ? 'Digite o código de convite que o dono da empresa te passou.'
                        : 'Esse é o primeiro acesso — só precisamos do nome do seu negócio pra criar seu espaço no sistema.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 28),
                  if (_temConvite)
                    TextField(
                      controller: _codigoController,
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Código de convite',
                        hintText: 'Ex: 7K3PQXZ2',
                        prefixIcon: Icon(Icons.key_outlined),
                      ),
                    )
                  else
                    TextField(
                      controller: _nomeController,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Nome da empresa',
                        hintText: 'Ex: Delivery Pet',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: (_carregando || !_podeConfirmar) ? null : _confirmar,
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                    child: _carregando
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary),
                          )
                        : Text(_temConvite ? 'Entrar na empresa' : 'Criar minha empresa'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _carregando
                        ? null
                        : () => setState(() => _temConvite = !_temConvite),
                    child: Text(
                      _temConvite
                          ? 'Na verdade, quero criar uma empresa nova'
                          : 'Já tenho um código de convite',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
