import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'aparencia_screen.dart';
import 'configuracao_entrega_screen.dart';
import 'configuracao_notificacoes_screen.dart';
import 'dados_loja_screen.dart';
import 'catalogo_online_screen.dart';
import 'banners_loja_screen.dart';
import 'kit_de_marca_screen.dart';
import 'horario_funcionamento_screen.dart';
import 'meu_recibo_screen.dart';
import 'opcoes_pagamento_screen.dart';
import 'regras_venda_screen.dart';
import 'cupons_screen.dart';
import 'config_cupom_automatico_screen.dart';
import 'metricas_cupons_screen.dart';
import 'exportar_relatorios_screen.dart';
import 'historico_entradas_screen.dart';
import 'importar_nota_fiscal_screen.dart';
import 'integrar_plataformas_screen.dart';
import 'mercado_pago_conectar_screen.dart';
import '../providers/auth_provider.dart';
import '../widgets/menu_secao.dart';

// Tela principal de configurações do app
class ConfiguracoesScreen extends StatelessWidget {
  const ConfiguracoesScreen({super.key});

  Future<void> _confirmarSaida(BuildContext context) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair'),
        content: const Text('Tem certeza que deseja sair da sua conta?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirmou == true && context.mounted) context.read<AuthProvider>().sair();
  }

  @override
  Widget build(BuildContext context) {
    // Kit de Marca mexe na identidade visual mostrada a QUALQUER cliente/
    // usuário (site e app) — igual usuários/finanças, é decisão só do
    // dono, nem gerente vê esse item (pedido explícito do usuário).
    final isDono = context.watch<AuthProvider>().isDono;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações do App'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MenuSecao(
            titulo: 'Loja',
            itens: [
              MenuItem('Dados da Loja', Icons.store_outlined, const DadosLojaScreen()),
              MenuItem('Horário de Funcionamento', Icons.schedule_outlined, const GeralScreen()),
              MenuItem('Aparência e Marca', Icons.palette_outlined, const AparenciaScreen()),
              if (isDono) MenuItem('Kit de Marca', Icons.auto_awesome_mosaic_outlined, const KitDeMarcaScreen()),
              MenuItem('Catálogo Online', Icons.storefront_outlined, const CatalogoOnlineScreen()),
              MenuItem('Banners da Home', Icons.view_carousel_outlined, const BannersLojaScreen()),
              MenuItem('Meu Recibo', Icons.receipt_long_outlined, const MeuReciboScreen()),
              MenuItem('Notificações', Icons.notifications_outlined, const ConfiguracaoNotificacoesScreen()),
            ],
          ),
          const SizedBox(height: 20),
          MenuSecao(
            titulo: 'Vendas',
            itens: [
              MenuItem('Opções de Pagamento', Icons.payment_outlined, const OpcoesPagamentoScreen()),
              if (isDono)
                MenuItem('Pagamento Online', Icons.account_balance_wallet_outlined, const MercadoPagoConectarScreen()),
              MenuItem('Pedidos e Vendas', Icons.shopping_cart_outlined, const PedidosVendasScreen()),
              MenuItem('Opções de Entrega', Icons.local_shipping_outlined, const ConfiguracaoEntregaScreen()),
              MenuItem('Cupons de Desconto', Icons.local_offer_outlined, const CuponsScreen()),
              MenuItem('Métricas de Cupons', Icons.bar_chart_outlined, const MetricasCuponsScreen()),
              MenuItem('Cupom Automático', Icons.auto_awesome_outlined, const ConfigCupomAutomaticoScreen()),
            ],
          ),
          const SizedBox(height: 20),
          MenuSecao(
            titulo: 'Dados e integrações',
            itens: [
              MenuItem('Importar Nota Fiscal', Icons.upload_file_outlined, const ImportarNotaFiscalScreen()),
              MenuItem('Notas Fiscais Importadas', Icons.history_outlined, const HistoricoEntradasScreen()),
              MenuItem('Exportar Relatórios', Icons.file_download_outlined, const ExportarRelatoriosScreen()),
              MenuItem(
                  'Integrar com Plataformas', Icons.integration_instructions_outlined, const IntegrarPlataformasScreen()),
            ],
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _confirmarSaida(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.4)),
              minimumSize: const Size(double.infinity, 48),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Sair'),
          ),
        ],
      ),
    );
  }
}
