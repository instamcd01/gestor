import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/auth_provider.dart';
import '../screens/cadastro_produto_screen.dart';
import '../screens/catalogo_online_hub_screen.dart';
import '../screens/configuracao_entrega_screen.dart';
import '../screens/dados_loja_screen.dart';
import '../screens/horario_funcionamento_screen.dart';
import '../screens/usuarios_screen.dart';
import '../screens/vendas_screen.dart';

/// Guia "Primeiros passos" da tela Início, pra loja que acabou de chegar.
///
/// Só aparece pro dono, enquanto falta algum passo e ele não fechou o guia.
/// A situação de cada passo vem do banco (`primeiros_passos_loja`), então o
/// guia se atualiza sozinho quando a pessoa volta de uma tela.
class PrimeirosPassosCard extends StatefulWidget {
  /// PC: uma faixa de uma linha com o próximo passo (a tela Início do PC tem
  /// altura fixa e não cabe a lista inteira); a lista abre numa janela.
  final bool compacto;

  const PrimeirosPassosCard({super.key, this.compacto = false});

  @override
  State<PrimeirosPassosCard> createState() => _PrimeirosPassosCardState();
}

class _Passo {
  final String chave;
  final String titulo;
  final String detalhe;
  final IconData icone;
  final Widget Function() tela;
  const _Passo(this.chave, this.titulo, this.detalhe, this.icone, this.tela);
}

final _passos = <_Passo>[
  _Passo('dados_loja', 'Dados da loja', 'Telefone e endereço aparecem no recibo e no site',
      Icons.storefront_outlined, () => const DadosLojaScreen()),
  _Passo('horario', 'Horário de funcionamento', 'Quando a loja recebe pedidos',
      Icons.schedule_outlined, () => const GeralScreen()),
  _Passo('produtos', 'Cadastrar produtos', 'Um por um ou por planilha, na tela Produtos',
      Icons.inventory_2_outlined, () => const CadastroProdutoScreen()),
  _Passo('entrega', 'Taxas de entrega', 'Bairros ou distâncias que a loja atende',
      Icons.delivery_dining_outlined, () => const ConfiguracaoEntregaScreen()),
  _Passo('equipe', 'Chamar a equipe', 'Cada pessoa com o próprio acesso',
      Icons.group_add_outlined, () => const UsuariosScreen()),
  _Passo('site', 'Ligar o site da loja', 'Catálogo online pros clientes pedirem',
      Icons.language_outlined, () => const CatalogoOnlineHubScreen()),
  _Passo('primeira_venda', 'Fazer a primeira venda', 'Pode ser uma venda de teste no balcão',
      Icons.point_of_sale_outlined, () => VendasScreen()),
];

class _PrimeirosPassosCardState extends State<PrimeirosPassosCard> {
  Map<String, bool>? _feitos;
  bool _fechado = true;

  String _chavePref(String empresaId) => 'primeiros_passos_fechado_$empresaId';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final auth = context.read<AuthProvider>();
    final empresaId = auth.empresaId;
    if (!auth.isDono || empresaId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final fechado = prefs.getBool(_chavePref(empresaId)) ?? false;
      if (fechado) {
        if (mounted) setState(() => _fechado = true);
        return;
      }
      final resposta = await Supabase.instance.client.rpc('primeiros_passos_loja');
      final mapa = (resposta as Map).map((k, v) => MapEntry(k.toString(), v == true));
      if (!mounted) return;
      setState(() {
        _feitos = mapa;
        _fechado = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar primeiros passos: $e');
    }
  }

  Future<void> _fechar() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_chavePref(empresaId), true);
    if (mounted) setState(() => _fechado = true);
  }

  Future<void> _abrir(_Passo passo) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => passo.tela()));
    if (mounted) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final feitos = _feitos;
    if (_fechado || feitos == null) return const SizedBox.shrink();
    final total = _passos.length;
    final concluidos = _passos.where((p) => feitos[p.chave] == true).length;
    if (concluidos == total) return const SizedBox.shrink();

    final cores = Theme.of(context).colorScheme;
    if (widget.compacto) {
      final proximo = _passos.firstWhere((p) => feitos[p.chave] != true);
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.flag_outlined, color: cores.primary),
              const SizedBox(width: 10),
              Text('Primeiros passos · $concluidos de $total', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Próximo: ${proximo.titulo}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cores.onSurfaceVariant)),
              ),
              FilledButton.tonal(onPressed: () => _abrir(proximo), child: const Text('Fazer agora')),
              const SizedBox(width: 8),
              TextButton(onPressed: () => _verTodos(feitos), child: const Text('Ver todos')),
              IconButton(tooltip: 'Fechar o guia', icon: const Icon(Icons.close), onPressed: _fechar),
            ],
          ),
        ),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Primeiros passos', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text('$concluidos de $total feitos',
                          style: TextStyle(fontSize: 13, color: cores.onSurfaceVariant)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar o guia',
                  icon: const Icon(Icons.close),
                  onPressed: _fechar,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 8, 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: concluidos / total, minHeight: 6),
              ),
            ),
            ..._lista(feitos, cores),
          ],
        ),
      ),
    );
  }

  Future<void> _verTodos(Map<String, bool> feitos) async {
    final cores = Theme.of(context).colorScheme;
    final escolhido = await showDialog<_Passo>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Primeiros passos'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: _lista(feitos, cores, aoTocar: (p) => Navigator.pop(ctx, p))),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))],
      ),
    );
    if (escolhido != null && mounted) _abrir(escolhido);
  }

  List<Widget> _lista(Map<String, bool> feitos, ColorScheme cores, {void Function(_Passo)? aoTocar}) {
    return [
            for (final passo in _passos)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(right: 8),
                leading: Icon(
                  feitos[passo.chave] == true ? Icons.check_circle : passo.icone,
                  color: feitos[passo.chave] == true ? Colors.green : cores.primary,
                ),
                title: Text(
                  passo.titulo,
                  style: TextStyle(
                    decoration: feitos[passo.chave] == true ? TextDecoration.lineThrough : null,
                    color: feitos[passo.chave] == true ? cores.onSurfaceVariant : null,
                  ),
                ),
                subtitle: feitos[passo.chave] == true ? null : Text(passo.detalhe),
                trailing: feitos[passo.chave] == true ? null : const Icon(Icons.chevron_right),
                onTap: () => aoTocar != null ? aoTocar(passo) : _abrir(passo),
              ),
    ];
  }
}
