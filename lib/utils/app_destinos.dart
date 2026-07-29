import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/produto.dart';
import '../providers/historico_vendas_provider.dart';
import '../providers/notificacao_provider.dart';
import '../providers/produto_provider.dart';
import '../screens/avaliacoes_disputas_screen.dart';
import '../screens/catalogo_online_screen.dart';
import '../screens/cliente_screen.dart';
import '../screens/configuracoes_screen.dart';
import '../screens/desempenho_equipe_screen.dart';
import '../screens/estatisticas_screen.dart';
import '../screens/financas_screen.dart';
import '../screens/fila_pedidos_screen.dart';
import '../screens/historico_vendas_screen.dart';
import '../screens/inicio_screen.dart';
import '../screens/meu_desempenho_screen.dart';
import '../screens/notificacoes_screen.dart';
import '../screens/produtos_screen.dart';
import '../screens/usuarios_screen.dart';
import '../screens/vendas_screen.dart';

bool _produtoComEstoqueBaixo(Produto p) =>
    p.ativo && p.estoqueMinimo > 0 && p.estoqueAtual > 0 && p.estoqueAtual <= p.estoqueMinimo;

/// Um destino de navegação principal do app (usado tanto pelo shell de
/// Drawer quanto pelo de Sidebar) — fonte única, evita a lista duplicada
/// que existia manualmente entre o Grid e o Drawer da Home.
class AppDestino {
  final String titulo;
  final IconData icone;
  final WidgetBuilder builder;

  /// Contagem pro badge do ícone (ex: pedidos em andamento, estoque baixo,
  /// notificações não lidas) — null ou 0 não mostra nada.
  final int Function(BuildContext context)? contador;

  /// Quais papéis veem este destino no menu — null significa "todos".
  /// Isso é só conveniência de UI (esconder o que a pessoa não deveria
  /// nem precisar ver); a proteção de verdade é RLS/trigger no banco,
  /// que já existe pras telas sensíveis (Finanças/Usuários acessam dados
  /// que o papel restrito já não consegue ler ou alterar de qualquer jeito).
  final List<String>? papeisPermitidos;

  const AppDestino({
    required this.titulo,
    required this.icone,
    required this.builder,
    this.contador,
    this.papeisPermitidos,
  });

  bool visivelPara(String? papel) => papeisPermitidos == null || papeisPermitidos!.contains(papel);

  Widget construirIcone(BuildContext context, {Color? color}) {
    final n = contador?.call(context) ?? 0;
    final icone_ = Icon(icone, color: color);
    if (n <= 0) return icone_;
    return Badge(label: Text(n > 99 ? '99+' : '$n'), child: icone_);
  }
}

final List<AppDestino> appDestinos = [
  AppDestino(titulo: 'Início', icone: Icons.home_outlined, builder: (_) => const InicioScreen()),
  AppDestino(
    titulo: 'Notificações',
    icone: Icons.notifications_outlined,
    builder: (_) => const NotificacoesScreen(),
    contador: (context) => context.watch<NotificacaoProvider>().totalNaoLidas,
  ),
  AppDestino(titulo: 'Vender', icone: Icons.shopping_cart_outlined, builder: (_) => VendasScreen()),
  AppDestino(
    titulo: 'Pedidos',
    icone: Icons.pets,
    builder: (_) => const FilaPedidosScreen(),
    contador: (context) => context.watch<HistoricoVendasProvider>().pedidosAtivos.length,
  ),
  AppDestino(
    titulo: 'Produtos',
    icone: Icons.local_mall,
    builder: (_) => ProdutosScreen(),
    contador: (context) =>
        context.watch<ProdutoProvider>().produtos.where(_produtoComEstoqueBaixo).length,
  ),
  AppDestino(titulo: 'Histórico', icone: Icons.history, builder: (_) => const HistoricoVendasScreen()),
  AppDestino(titulo: 'Meu Desempenho', icone: Icons.insights_outlined, builder: (_) => const MeuDesempenhoScreen()),
  AppDestino(
    titulo: 'Desempenho da Equipe',
    icone: Icons.groups_outlined,
    builder: (_) => const DesempenhoEquipeScreen(),
    papeisPermitidos: ['dono', 'gerente'],
  ),
  AppDestino(titulo: 'Clientes', icone: Icons.person, builder: (_) => ClientesScreen()),
  AppDestino(
    titulo: 'Catálogo Online',
    icone: Icons.book_online,
    builder: (_) => const CatalogoOnlineScreen(),
    papeisPermitidos: ['dono', 'gerente'],
  ),
  AppDestino(
    titulo: 'Finanças',
    icone: Icons.money,
    builder: (_) => const FinancasScreen(),
    papeisPermitidos: ['dono', 'gerente'],
  ),
  AppDestino(
    titulo: 'Estatísticas',
    icone: Icons.area_chart,
    builder: (_) => const EstatisticasScreen(),
    papeisPermitidos: ['dono', 'gerente'],
  ),
  AppDestino(
    titulo: 'Avaliações',
    icone: Icons.reviews_outlined,
    builder: (_) => const AvaliacoesDisputasScreen(),
    papeisPermitidos: ['dono', 'gerente'],
  ),
  AppDestino(
    titulo: 'Usuários',
    icone: Icons.person_pin,
    builder: (_) => const UsuariosScreen(),
    papeisPermitidos: ['dono'],
  ),
  AppDestino(
    titulo: 'Configurações',
    icone: Icons.settings,
    builder: (_) => const ConfiguracoesScreen(),
    papeisPermitidos: ['dono', 'gerente'],
  ),
];

/// Lista de destinos já filtrada pro papel do usuário — usar esta em vez de
/// `appDestinos` diretamente em qualquer shell de navegação.
List<AppDestino> destinosParaPapel(String? papel) =>
    appDestinos.where((d) => d.visivelPara(papel)).toList();
