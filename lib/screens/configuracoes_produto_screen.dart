import 'package:flutter/material.dart';
import 'gerenciar_categorias_screen.dart';
import 'gerenciar_termos_variacao_screen.dart';
import 'fabricante_screen.dart';
import 'ciclo_recompra_padrao_screen.dart';
import 'estrutura_nome_produto_screen.dart';
import '../widgets/menu_secao.dart';

/// Hub de configurações relacionadas a produto — hoje só Categorias, mas é
/// o lugar certo pra qualquer configuração futura de catálogo (ficha
/// técnica, atributos por marketplace etc.), sem precisar inventar outro
/// ponto de entrada na hora. Aberto pelo ícone de configurações na AppBar
/// de ProdutosScreen, não misturado nas Configurações gerais do app.
class ConfiguracoesProdutoScreen extends StatelessWidget {
  const ConfiguracoesProdutoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações do Produto')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MenuSecao(
            titulo: 'Catálogo',
            itens: [
              MenuItem(
                'Categorias',
                Icons.category_outlined,
                const GerenciarCategoriasScreen(),
              ),
              MenuItem(
                'Fabricantes',
                Icons.factory_outlined,
                const FabricanteScreen(),
              ),
              MenuItem(
                'Termos de variante',
                Icons.style_outlined,
                const GerenciarTermosVariacaoScreen(),
              ),
              MenuItem(
                'Estrutura do Nome',
                Icons.text_fields_outlined,
                const EstruturaNomeProdutoScreen(),
              ),
              MenuItem(
                'Ciclo de Recompra Padrão',
                Icons.replay_circle_filled_outlined,
                const CicloRecompraPadraoScreen(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
