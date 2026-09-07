import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/marketplace.dart';
import '../models/marketplace_config.dart';
import '../providers/auth_provider.dart';
import '../repositories/marketplace_config_repository.dart';
import '../repositories/marketplace_repository.dart';
import '../widgets/aviso_banner.dart';
import 'integracao_ifood_screen.dart';
import 'plataforma_detalhe_screen.dart';

/// Configurações > Integrar com Plataformas: diretório das plataformas
/// (iFood, 99Food, Rappi...), restrito ao dono da empresa (credenciais são
/// dado sensível). Cada card abre a tela dedicada daquela plataforma — pra
/// iFood, uma tela rica (pausa/retomar loja, reconciliação, catálogo,
/// histórico); pras demais, só a config de credenciais até a integração
/// ganhar recursos próprios. Nenhuma chamada de API acontece a partir do
/// app — quem autentica de verdade com a API de cada plataforma é o n8n,
/// que lê a mesma tabela (`empresa_marketplace_config`).
class IntegrarPlataformasScreen extends StatefulWidget {
  const IntegrarPlataformasScreen({super.key});

  @override
  State<IntegrarPlataformasScreen> createState() => _IntegrarPlataformasScreenState();
}

class _IntegrarPlataformasScreenState extends State<IntegrarPlataformasScreen> {
  final _marketplaceRepository = MarketplaceRepository();
  final _configRepository = MarketplaceConfigRepository();

  List<Marketplace> _marketplaces = [];
  Map<String, MarketplaceConfig> _configs = {};
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final marketplaces = await _marketplaceRepository.listarAtivos();
      final configs = await _configRepository.listar();
      if (mounted) {
        setState(() {
          _marketplaces = marketplaces;
          _configs = {for (final c in configs) c.marketplaceId: c};
          _carregando = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar integrações: $e');
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _abrirPlataforma(Marketplace marketplace) {
    final destino = marketplace.nome.toLowerCase() == 'ifood'
        ? IntegracaoIfoodScreen(marketplace: marketplace)
        : PlataformaDetalheScreen(marketplace: marketplace);
    Navigator.push(context, MaterialPageRoute(builder: (_) => destino)).then((_) => _carregar());
  }

  Widget _cardPlataforma(Marketplace marketplace) {
    final config = _configs[marketplace.id];
    final ativo = config?.ativo ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          Icons.storefront,
          color: ativo ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        title: Text(marketplace.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(ativo ? 'Ativo' : 'Não configurado'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _abrirPlataforma(marketplace),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final souDono = context.watch<AuthProvider>().papel == 'dono';

    return Scaffold(
      appBar: AppBar(title: const Text('Integrar com Plataformas')),
      body: !souDono
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Apenas o dono da empresa pode configurar integrações com marketplaces.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            )
          : _carregando
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: AvisoBanner(
                        texto: 'As credenciais salvas aqui já são usadas por integrações ativas (hoje, '
                            'iFood) — mantenha atualizadas. Plataformas sem integração construída ainda '
                            'ficam com as credenciais só guardadas até lá.',
                      ),
                    ),
                    if (_marketplaces.isEmpty)
                      Center(
                        child: Text(
                          'Nenhuma plataforma disponível.',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      )
                    else
                      ..._marketplaces.map(_cardPlataforma),
                  ],
                ),
    );
  }
}
