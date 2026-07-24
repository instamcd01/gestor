import 'package:flutter/material.dart';

import '../screens/avaliacoes_disputas_screen.dart';
import '../screens/catalogo_online_screen.dart';
import '../screens/cliente_screen.dart';
import '../screens/configuracoes_screen.dart';
import '../screens/estatisticas_screen.dart';
import '../screens/financas_screen.dart';
import '../screens/fila_pedidos_screen.dart';
import '../screens/historico_vendas_screen.dart';
import '../screens/produtos_screen.dart';
import '../screens/usuarios_screen.dart';
import '../screens/vendas_screen.dart';

/// Um destino de navegação principal do app (usado tanto pelo shell de
/// Drawer quanto pelo de Sidebar) — fonte única, evita a lista duplicada
/// que existia manualmente entre o Grid e o Drawer da Home.
class AppDestino {
  final String titulo;
  final IconData icone;
  final WidgetBuilder builder;

  const AppDestino({required this.titulo, required this.icone, required this.builder});
}

final List<AppDestino> appDestinos = [
  AppDestino(titulo: 'Vender', icone: Icons.shopping_cart_outlined, builder: (_) => VendasScreen()),
  AppDestino(titulo: 'Pedidos', icone: Icons.pets, builder: (_) => const FilaPedidosScreen()),
  AppDestino(titulo: 'Produtos', icone: Icons.local_mall, builder: (_) => ProdutosScreen()),
  AppDestino(titulo: 'Histórico', icone: Icons.history, builder: (_) => const HistoricoVendasScreen()),
  AppDestino(titulo: 'Clientes', icone: Icons.person, builder: (_) => ClientesScreen()),
  AppDestino(titulo: 'Catálogo Online', icone: Icons.book_online, builder: (_) => const CatalogoOnlineScreen()),
  AppDestino(titulo: 'Finanças', icone: Icons.money, builder: (_) => const FinancasScreen()),
  AppDestino(titulo: 'Estatísticas', icone: Icons.area_chart, builder: (_) => const EstatisticasScreen()),
  AppDestino(titulo: 'Avaliações', icone: Icons.reviews_outlined, builder: (_) => const AvaliacoesDisputasScreen()),
  AppDestino(titulo: 'Usuários', icone: Icons.person_pin, builder: (_) => const UsuariosScreen()),
  AppDestino(titulo: 'Configurações', icone: Icons.settings, builder: (_) => const ConfiguracoesScreen()),
];
