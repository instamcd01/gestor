import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/marketplace.dart';
import '../models/marketplace_config.dart';
import '../providers/auth_provider.dart';
import '../repositories/marketplace_config_repository.dart';
import '../widgets/marketplace_config_card.dart';

/// Tela genérica de uma plataforma sem integração/recursos próprios
/// construídos ainda — só as credenciais, guardadas até a integração ser
/// feita de verdade (ver `IntegracaoIfoodScreen` pra ver como fica quando
/// cresce).
class PlataformaDetalheScreen extends StatefulWidget {
  final Marketplace marketplace;

  const PlataformaDetalheScreen({super.key, required this.marketplace});

  @override
  State<PlataformaDetalheScreen> createState() => _PlataformaDetalheScreenState();
}

class _PlataformaDetalheScreenState extends State<PlataformaDetalheScreen> {
  final _configRepository = MarketplaceConfigRepository();
  MarketplaceConfig? _config;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final configs = await _configRepository.listar();
      final config = configs.where((c) => c.marketplaceId == widget.marketplace.id).firstOrNull;
      if (mounted) {
        setState(() {
          _config = config ?? MarketplaceConfig(marketplaceId: widget.marketplace.id);
          _carregando = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar(MarketplaceConfig config) async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    try {
      await _configRepository.salvar(config, empresaId: empresaId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Configuração salva.')));
      await _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.marketplace.nome)),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: MarketplaceConfigCard(
                marketplace: widget.marketplace,
                config: _config!,
                onSalvar: _salvar,
                iniciaExpandido: true,
              ),
            ),
    );
  }
}
