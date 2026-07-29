import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/usuario.dart';
import '../providers/auth_provider.dart';
import '../providers/usuario_provider.dart';
import '../utils/formatadores_input.dart';

/// Autoatendimento: qualquer papel (inclusive vendedor) edita o próprio
/// nome/telefone por aqui — a tela de Usuários é restrita ao dono, então
/// sem isso ninguém além do dono tinha como preencher/corrigir os próprios
/// dados depois do cadastro inicial.
class MeuPerfilScreen extends StatefulWidget {
  const MeuPerfilScreen({super.key});

  @override
  State<MeuPerfilScreen> createState() => _MeuPerfilScreenState();
}

class _MeuPerfilScreenState extends State<MeuPerfilScreen> {
  final _nomeController = TextEditingController();
  final _telefoneController = TextEditingController();
  bool _carregando = true;
  bool _salvando = false;
  bool _preenchido = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _telefoneController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    await context.read<UsuarioProvider>().carregar();
    if (mounted) setState(() => _carregando = false);
  }

  String _inicial(Usuario eu) {
    if (eu.nome?.isNotEmpty == true) return eu.nome![0].toUpperCase();
    if (eu.email?.isNotEmpty == true) return eu.email![0].toUpperCase();
    return '?';
  }

  void _preencherSeNecessario(Usuario eu) {
    if (_preenchido) return;
    _preenchido = true;
    _nomeController.text = eu.nome ?? '';
    _telefoneController.text = eu.telefone ?? '';
  }

  Future<void> _salvar(String meuId) async {
    setState(() => _salvando = true);
    try {
      await context.read<UsuarioProvider>().atualizarDados(
            meuId,
            nome: _nomeController.text.trim(),
            telefone: _telefoneController.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dados salvos com sucesso!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final meuId = auth.usuarioAtual?.id;
    final colorScheme = Theme.of(context).colorScheme;

    final usuarios = context.watch<UsuarioProvider>().usuarios;
    Usuario? eu;
    for (final u in usuarios) {
      if (u.id == meuId) {
        eu = u;
        break;
      }
    }
    if (eu != null) _preencherSeNecessario(eu);

    return Scaffold(
      appBar: AppBar(title: const Text('Meu Perfil')),
      body: (_carregando || eu == null)
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 36,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Text(
                      _inicial(eu),
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: colorScheme.onPrimaryContainer),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Chip(
                    label: Text(eu.rotuloPapel),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _nomeController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nome completo',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _telefoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [TelefoneInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Telefone',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.mail_outline),
                  title: Text(eu.email ?? '-'),
                  subtitle: const Text('E-mail (não editável por aqui)'),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: (_salvando || meuId == null) ? null : () => _salvar(meuId),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                  child: _salvando
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Salvar'),
                ),
              ],
            ),
    );
  }
}
