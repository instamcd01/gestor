import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/convite_empresa.dart';
import '../models/usuario.dart';
import '../providers/auth_provider.dart';
import '../providers/usuario_provider.dart';

/// Gestão de equipe: quem tem acesso à empresa, com qual papel, e convites
/// pendentes pra novas pessoas entrarem. Substitui a versão antiga que
/// mostrava uma lista de usuários fixa no código (com senha em texto puro
/// na tela de detalhes!) — usuarios.id é sempre uma conta real do Supabase
/// Auth, então "adicionar alguém" é sempre via código de convite.
class UsuariosScreen extends StatefulWidget {
  const UsuariosScreen({super.key});

  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends State<UsuariosScreen> {
  @override
  void initState() {
    super.initState();
    Provider.of<UsuarioProvider>(context, listen: false).carregar();
  }

  Future<void> _gerarConvite(bool souDono) async {
    if (!souDono) return;

    final auth = context.read<AuthProvider>();
    final meuId = auth.usuarioAtual?.id;
    if (meuId == null) return;

    try {
      final convite = await context
          .read<UsuarioProvider>()
          .gerarConvite(criadoPor: meuId, papel: 'funcionario');
      if (!mounted) return;
      await _mostrarCodigoGerado(convite);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível gerar o convite: $e')),
      );
    }
  }

  Future<void> _mostrarCodigoGerado(ConviteEmpresa convite) async {
    final dateFormat = DateFormat('dd/MM/yyyy');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Convite gerado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Passe esse código pra pessoa entrar como funcionário. '
                'Ela cria a própria conta na tela de login e usa esse código em vez de criar uma empresa nova.'),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                convite.codigo,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Válido até ${dateFormat.format(convite.expiraEm)}',
              style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: convite.codigo));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Código copiado.')),
                );
              }
            },
            child: const Text('Copiar código'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _revogarConvite(ConviteEmpresa convite) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revogar convite'),
        content: Text('O código ${convite.codigo} deixará de funcionar. Confirmar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Revogar')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    try {
      await context.read<UsuarioProvider>().revogarConvite(convite.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível revogar: $e')),
      );
    }
  }

  Future<void> _editarUsuario(Usuario usuario, bool souDono, bool ehEuMesmo) async {
    if (!souDono || ehEuMesmo) return;

    final novoPapel = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(usuario.nome?.isNotEmpty == true ? usuario.nome! : (usuario.email ?? 'Usuário')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: const Text('Funcionário'),
              value: 'funcionario',
              groupValue: usuario.papel,
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
            RadioListTile<String>(
              title: const Text('Dono'),
              value: 'dono',
              groupValue: usuario.papel,
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
            const Divider(),
            ListTile(
              leading: Icon(usuario.ativo ? Icons.block : Icons.check_circle, color: usuario.ativo ? Colors.red : Colors.green),
              title: Text(usuario.ativo ? 'Desativar acesso' : 'Reativar acesso'),
              onTap: () => Navigator.pop(ctx, usuario.ativo ? '_desativar' : '_reativar'),
            ),
          ],
        ),
      ),
    );

    if (novoPapel == null || !mounted) return;

    try {
      final provider = context.read<UsuarioProvider>();
      if (novoPapel == '_desativar') {
        await provider.atualizarAtivo(usuario.id, false);
      } else if (novoPapel == '_reativar') {
        await provider.atualizarAtivo(usuario.id, true);
      } else if (novoPapel != usuario.papel) {
        await provider.atualizarPapel(usuario.id, novoPapel);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível atualizar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<UsuarioProvider>();
    final souDono = auth.papel == 'dono';
    final meuId = auth.usuarioAtual?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Usuários'),
        actions: [
          if (souDono)
            IconButton(
              icon: const Icon(Icons.person_add_alt),
              tooltip: 'Gerar convite',
              onPressed: () => _gerarConvite(souDono),
            ),
        ],
      ),
      body: provider.carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: provider.carregar,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Text(
                      'Equipe',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                  ...provider.usuarios.map((usuario) {
                    final ehEuMesmo = usuario.id == meuId;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: usuario.ativo ? Theme.of(context).colorScheme.primaryContainer : Colors.grey[300],
                          child: Icon(
                            usuario.isDono ? Icons.star : Icons.person,
                            color: usuario.ativo ? Theme.of(context).colorScheme.primary : Colors.grey[600],
                          ),
                        ),
                        title: Text(
                          (usuario.nome?.isNotEmpty == true ? usuario.nome! : usuario.email) ?? 'Usuário',
                          style: TextStyle(
                            decoration: usuario.ativo ? null : TextDecoration.lineThrough,
                          ),
                        ),
                        subtitle: Text(
                          '${usuario.isDono ? 'Dono' : 'Funcionário'}'
                          '${ehEuMesmo ? ' • você' : ''}'
                          '${usuario.ativo ? '' : ' • inativo'}',
                        ),
                        trailing: souDono && !ehEuMesmo ? const Icon(Icons.chevron_right) : null,
                        onTap: souDono ? () => _editarUsuario(usuario, souDono, ehEuMesmo) : null,
                      ),
                    );
                  }),
                  if (souDono && provider.convitesPendentes.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      child: Text(
                        'Convites pendentes',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                    ...provider.convitesPendentes.map((convite) {
                      final dateFormat = DateFormat('dd/MM/yyyy');
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.mail_outline, color: Colors.orange),
                          title: Text(convite.codigo, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                          subtitle: Text('Funcionário • válido até ${dateFormat.format(convite.expiraEm)}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            tooltip: 'Revogar',
                            onPressed: () => _revogarConvite(convite),
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
    );
  }
}
