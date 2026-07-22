import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/marketplace.dart';
import '../models/marketplace_config.dart';
import '../providers/auth_provider.dart';
import '../repositories/marketplace_config_repository.dart';
import '../repositories/marketplace_repository.dart';

/// Configurações > Integrar com Plataformas: onde ficam guardadas as
/// credenciais de cada marketplace (iFood, 99Food, Rappi...) pra quando a
/// integração de API de verdade for construída. Nenhuma chamada de API
/// acontece a partir daqui — é só armazenamento estruturado, restrito ao
/// dono da empresa (credenciais são dado sensível).
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
      setState(() {
        _marketplaces = marketplaces;
        _configs = {for (final c in configs) c.marketplaceId: c};
        _carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar integrações: $e');
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvarConfig(MarketplaceConfig config) async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;

    try {
      await _configRepository.salvar(config, empresaId: empresaId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuração salva.')),
        );
      }
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    }
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
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[100]!),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'A integração de API com cada plataforma ainda não existe — isso só guarda '
                              'as credenciais pra quando ela for construída.',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
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
                      ..._marketplaces.map((marketplace) => _MarketplaceConfigCard(
                            marketplace: marketplace,
                            config: _configs[marketplace.id] ?? MarketplaceConfig(marketplaceId: marketplace.id),
                            onSalvar: _salvarConfig,
                          )),
                  ],
                ),
    );
  }
}

class _MarketplaceConfigCard extends StatefulWidget {
  final Marketplace marketplace;
  final MarketplaceConfig config;
  final ValueChanged<MarketplaceConfig> onSalvar;

  const _MarketplaceConfigCard({required this.marketplace, required this.config, required this.onSalvar});

  @override
  State<_MarketplaceConfigCard> createState() => _MarketplaceConfigCardState();
}

class _MarketplaceConfigCardState extends State<_MarketplaceConfigCard> {
  late bool _ativo;
  late final TextEditingController _idLojaController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _apiSecretController;
  late final TextEditingController _observacoesController;
  bool _mostrarSecret = false;
  bool _expandido = false;

  @override
  void initState() {
    super.initState();
    _ativo = widget.config.ativo;
    _idLojaController = TextEditingController(text: widget.config.idLojaPlataforma);
    _apiKeyController = TextEditingController(text: widget.config.apiKey);
    _apiSecretController = TextEditingController(text: widget.config.apiSecret);
    _observacoesController = TextEditingController(text: widget.config.observacoes);
  }

  @override
  void dispose() {
    _idLojaController.dispose();
    _apiKeyController.dispose();
    _apiSecretController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }

  void _salvar() {
    widget.onSalvar(MarketplaceConfig(
      id: widget.config.id,
      marketplaceId: widget.marketplace.id,
      ativo: _ativo,
      idLojaPlataforma: _idLojaController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      apiSecret: _apiSecretController.text.trim(),
      observacoes: _observacoesController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          SwitchListTile(
            title: Text(widget.marketplace.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(_ativo ? 'Ativo' : 'Inativo'),
            value: _ativo,
            onChanged: (v) => setState(() => _ativo = v),
            secondary: IconButton(
              icon: Icon(_expandido ? Icons.expand_less : Icons.expand_more),
              onPressed: () => setState(() => _expandido = !_expandido),
            ),
          ),
          if (_expandido)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  TextField(
                    controller: _idLojaController,
                    decoration: const InputDecoration(labelText: 'ID da loja na plataforma'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyController,
                    decoration: const InputDecoration(labelText: 'API Key'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiSecretController,
                    obscureText: !_mostrarSecret,
                    decoration: InputDecoration(
                      labelText: 'API Secret',
                      suffixIcon: IconButton(
                        icon: Icon(_mostrarSecret ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _mostrarSecret = !_mostrarSecret),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _observacoesController,
                    decoration: const InputDecoration(labelText: 'Observações'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _salvar,
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                    child: const Text('Salvar'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
