import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/convite_empresa.dart';
import '../models/usuario.dart';
import '../providers/auth_provider.dart';
import '../providers/usuario_provider.dart';
import '../utils/formatadores_input.dart';

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

    final papelEscolhido = await _escolherPapelParaConvite();
    if (papelEscolhido == null || !mounted) return;

    try {
      final convite = await context
          .read<UsuarioProvider>()
          .gerarConvite(criadoPor: meuId, papel: papelEscolhido);
      if (!mounted) return;
      await _mostrarCodigoGerado(convite);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível gerar o convite: $e')),
      );
    }
  }

  Future<String?> _escolherPapelParaConvite() {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Convidar como...'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('Vendedor'),
              subtitle: const Text('Vender, pedidos, produtos, clientes — sem financeiro nem exclusões'),
              onTap: () => Navigator.pop(ctx, 'vendedor'),
            ),
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('Gerente'),
              subtitle: const Text('Tudo, exceto gerenciar usuários'),
              onTap: () => Navigator.pop(ctx, 'gerente'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        ],
      ),
    );
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
            Text('Passe esse código pra pessoa entrar como ${Usuario.rotulosPapel[convite.papel] ?? convite.papel}. '
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

  /// Edita nome/telefone — usado tanto pra alguém editar os próprios dados
  /// (qualquer papel) quanto pelo dono editando os dados de outro usuário
  /// da equipe. Papel/status continuam num diálogo separado (`_editarUsuario`),
  /// já que são reforçados por trigger no banco — e principalmente pra NUNCA
  /// encadear um showDialog logo depois de fechar outro: fechar um diálogo e
  /// abrir outro no mesmo frame corrompe o Overlay do Flutter (RenderFlex
  /// overflow gigante + assert `_dependents.isEmpty`), então cada ação tem
  /// seu próprio ponto de entrada direto na lista, nunca um dialog chamando
  /// outro.
  ///
  /// IMPORTANTE: os controllers NÃO são descartados (`.dispose()`) logo
  /// depois do `showDialog` retornar — o retorno acontece assim que
  /// `Navigator.pop` é chamado, mas o `AlertDialog`/`TextField` continuam
  /// montados durante a animação de saída (fade-out). Descartar o controller
  /// nesse meio tempo, com o TextField ainda vivo usando ele, corrompe o
  /// layout na próxima pintura (mesmo RenderFlex overflow gigante de antes,
  /// só que agora em QUALQUER forma de fechar o diálogo — Cancelar, Salvar,
  /// tocar fora). É um leak pequeno e proposital: mesmo padrão já usado nos
  /// outros diálogos avulsos do app (nenhum deles descarta o controller).
  Future<void> _editarNomeTelefone(Usuario usuario) async {
    final nomeController = TextEditingController(text: usuario.nome ?? '');
    final telefoneController = TextEditingController(text: usuario.telefone ?? '');

    final salvou = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar dados'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: nomeController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome completo',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: telefoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: [TelefoneInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Telefone',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );

    final nome = nomeController.text.trim();
    final telefone = telefoneController.text.trim();

    if (salvou != true || !mounted) return;

    try {
      await context.read<UsuarioProvider>().atualizarDados(usuario.id, nome: nome, telefone: telefone);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível salvar: $e')),
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
              title: const Text('Vendedor'),
              value: 'vendedor',
              groupValue: usuario.papel,
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
            RadioListTile<String>(
              title: const Text('Gerente'),
              value: 'gerente',
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
                          '${usuario.rotuloPapel}'
                          '${ehEuMesmo ? ' • você' : ''}'
                          '${usuario.ativo ? '' : ' • inativo'}'
                          '${usuario.telefone?.isNotEmpty == true ? ' • ${usuario.telefone}' : ''}',
                        ),
                        trailing: souDono && !ehEuMesmo
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    tooltip: 'Editar nome e telefone',
                                    onPressed: () => _editarNomeTelefone(usuario),
                                  ),
                                  const Icon(Icons.chevron_right),
                                ],
                              )
                            : (ehEuMesmo ? const Icon(Icons.edit_outlined) : null),
                        onTap: ehEuMesmo
                            ? () => _editarNomeTelefone(usuario)
                            : (souDono ? () => _editarUsuario(usuario, souDono, ehEuMesmo) : null),
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
                          subtitle: Text(
                              '${Usuario.rotulosPapel[convite.papel] ?? convite.papel} • válido até ${dateFormat.format(convite.expiraEm)}'),
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
