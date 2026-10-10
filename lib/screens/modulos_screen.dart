import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/modulo.dart';
import '../providers/modulo_provider.dart';
import '../widgets/aviso_banner.dart';
import '../widgets/estado_erro_lista.dart';
import 'catalogo_online_hub_screen.dart';
import 'config_automacoes_whatsapp_screen.dart';
import 'config_petcash_screen.dart';
import 'historico_entradas_screen.dart';
import 'integrar_plataformas_screen.dart';

/// "Loja de aplicativos" do Gestor: o dono instala/desinstala os módulos
/// da loja (tabela `modulos`). A BASE não aparece aqui — toda loja tem.
/// Regras de dono e de dependência são do banco (`instalar_modulo` /
/// `desinstalar_modulo`); esta tela só antecipa o aviso e mostra o erro
/// que vier de lá. Desinstalar nunca apaga dados.
class ModulosScreen extends StatefulWidget {
  const ModulosScreen({super.key});

  @override
  State<ModulosScreen> createState() => _ModulosScreenState();
}

/// `modulos.icone` guarda o nome do Material Icon — mapeado aqui porque
/// Flutter não resolve ícone por string em tempo de execução.
const _icones = <String, IconData>{
  'storefront': Icons.storefront_outlined,
  'pets': Icons.pets_outlined,
  'chat': Icons.chat_outlined,
  'smart_toy': Icons.smart_toy_outlined,
  'campaign': Icons.campaign_outlined,
  'delivery_dining': Icons.delivery_dining_outlined,
  'two_wheeler': Icons.two_wheeler_outlined,
  'description': Icons.description_outlined,
  'inventory': Icons.inventory_2_outlined,
  'alt_route': Icons.alt_route,
  'calculate': Icons.calculate_outlined,
  'event_note': Icons.event_note_outlined,
  'photo_camera': Icons.photo_camera_outlined,
};

/// Onde configurar cada módulo logo depois de instalar — só os que já têm
/// tela de configuração no app.
Widget? _telaConfiguracao(String slug) => switch (slug) {
      Modulos.lojaOnline => const CatalogoOnlineHubScreen(),
      Modulos.petcash => const ConfigPetCashScreen(),
      Modulos.marketing => const ConfigAutomacoesWhatsappScreen(),
      Modulos.ifood || Modulos.food99 => const IntegrarPlataformasScreen(),
      Modulos.notasFiscais => const HistoricoEntradasScreen(),
      _ => null,
    };

class _ModulosScreenState extends State<ModulosScreen> {
  String? _processando;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ModuloProvider>().carregar();
    });
  }

  String _nomes(List<String> slugs, List<Modulo> todos) =>
      slugs.map((s) => todos.where((m) => m.slug == s).firstOrNull?.nome ?? s).join(', ');

  Future<void> _instalar(Modulo modulo) async {
    final provider = context.read<ModuloProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _processando = modulo.slug);
    try {
      await provider.instalar(modulo.slug);
      final tela = _telaConfiguracao(modulo.slug);
      messenger.showSnackBar(SnackBar(
        content: Text('${modulo.nome} instalado.'),
        action: tela == null
            ? null
            : SnackBarAction(
                label: 'Configurar',
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => tela)),
              ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e is PostgrestException ? e.message : 'Erro ao instalar: $e')));
    } finally {
      if (mounted) setState(() => _processando = null);
    }
  }

  Future<void> _desinstalar(Modulo modulo) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Desinstalar ${modulo.nome}?'),
        content: const Text(
          'As telas desse módulo somem do menu e ele para de funcionar na sua loja. '
          'Nenhum dado é apagado: se você instalar de novo, tudo volta como estava.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Desinstalar')),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    final provider = context.read<ModuloProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _processando = modulo.slug);
    try {
      await provider.desinstalar(modulo.slug);
      messenger.showSnackBar(SnackBar(content: Text('${modulo.nome} desinstalado.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e is PostgrestException ? e.message : 'Erro ao desinstalar: $e')));
    } finally {
      if (mounted) setState(() => _processando = null);
    }
  }

  Widget _card(Modulo modulo, List<Modulo> todos) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final ativos = {for (final m in todos.where((m) => m.ativo)) m.slug};
    final faltando = modulo.dependeDe.where((s) => !ativos.contains(s)).toList();
    final dependentesAtivos =
        todos.where((m) => m.ativo && m.dependeDe.contains(modulo.slug)).map((m) => m.slug).toList();
    final processando = _processando == modulo.slug;

    Widget botao;
    if (processando) {
      botao = const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2));
    } else if (modulo.ativo) {
      botao = OutlinedButton(
        onPressed: _processando != null || dependentesAtivos.isNotEmpty ? null : () => _desinstalar(modulo),
        child: const Text('Desinstalar'),
      );
    } else {
      botao = FilledButton(
        onPressed: _processando != null || faltando.isNotEmpty ? null : () => _instalar(modulo),
        child: const Text('Instalar'),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icones[modulo.icone] ?? Icons.extension_outlined,
                    color: modulo.ativo ? colorScheme.primary : colorScheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(modulo.nome, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (modulo.ativo)
                  Chip(
                    label: const Text('Instalado'),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                    backgroundColor: colorScheme.primaryContainer,
                    labelStyle: TextStyle(color: colorScheme.onPrimaryContainer),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(modulo.descricao, style: textTheme.bodyMedium),
            if (modulo.dependeDe.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                faltando.isEmpty
                    ? 'Usa: ${_nomes(modulo.dependeDe, todos)}'
                    : 'Instale antes: ${_nomes(faltando, todos)}',
                style: textTheme.bodySmall?.copyWith(
                  color: faltando.isEmpty ? colorScheme.onSurfaceVariant : colorScheme.error,
                  fontWeight: faltando.isEmpty ? null : FontWeight.w600,
                ),
              ),
            ],
            if (modulo.aproveita.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Fica melhor com: ${_nomes(modulo.aproveita, todos)}',
                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
            if (modulo.ativo && dependentesAtivos.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Para desinstalar, desinstale antes: ${_nomes(dependentesAtivos, todos)}',
                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerRight, child: botao),
          ],
        ),
      ),
    );
  }

  Widget _secao(String titulo, List<Modulo> modulos, List<Modulo> todos) {
    if (modulos.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4, top: 8),
          child: Text(
            titulo,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary),
          ),
        ),
        for (final m in modulos) _card(m, todos),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ModuloProvider>();
    final todos = provider.modulos.where((m) => m.disponivel || m.ativo).toList();

    Widget corpo;
    if (todos.isEmpty && provider.carregando) {
      corpo = const Center(child: CircularProgressIndicator());
    } else if (todos.isEmpty && provider.erro != null) {
      corpo = EstadoErroLista(mensagem: provider.erro!, onTentarNovamente: provider.carregar);
    } else {
      corpo = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const AvisoBanner(
            texto: 'Instale só o que a sua loja usa. Vendas, produtos, estoque, clientes, '
                'pedidos e caixa já fazem parte do Gestor e não precisam ser instalados.',
          ),
          const SizedBox(height: 8),
          _secao('Instalados', todos.where((m) => m.ativo).toList(), todos),
          _secao('Disponíveis', todos.where((m) => !m.ativo).toList(), todos),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Módulos')),
      body: corpo,
    );
  }
}
