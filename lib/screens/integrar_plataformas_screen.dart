import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/interrupcao_marketplace.dart';
import '../models/marketplace.dart';
import '../models/marketplace_config.dart';
import '../providers/auth_provider.dart';
import '../repositories/interrupcao_marketplace_repository.dart';
import '../repositories/marketplace_config_repository.dart';
import '../repositories/marketplace_repository.dart';

/// Configurações > Integrar com Plataformas: onde ficam guardadas as
/// credenciais de cada marketplace (iFood, 99Food, Rappi...), restrito ao
/// dono da empresa (credenciais são dado sensível). Nenhuma chamada de API
/// acontece a partir do app — quem autentica de verdade com a API de cada
/// plataforma é o n8n, que lê essa mesma tabela (`empresa_marketplace_config`).
/// Pra iFood essa integração já está ativa; pra marketplaces sem workflow
/// de n8n construído ainda, as credenciais ficam só guardadas até lá.
class IntegrarPlataformasScreen extends StatefulWidget {
  const IntegrarPlataformasScreen({super.key});

  @override
  State<IntegrarPlataformasScreen> createState() => _IntegrarPlataformasScreenState();
}

class _IntegrarPlataformasScreenState extends State<IntegrarPlataformasScreen> {
  final _marketplaceRepository = MarketplaceRepository();
  final _configRepository = MarketplaceConfigRepository();
  final _interrupcaoRepository = InterrupcaoMarketplaceRepository();

  List<Marketplace> _marketplaces = [];
  Map<String, MarketplaceConfig> _configs = {};
  InterrupcaoMarketplace? _interrupcaoAtiva;
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
      final interrupcao = await _interrupcaoRepository.buscarAtiva();
      setState(() {
        _marketplaces = marketplaces;
        _configs = {for (final c in configs) c.marketplaceId: c};
        _interrupcaoAtiva = interrupcao;
        _carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar integrações: $e');
      if (mounted) setState(() => _carregando = false);
    }
  }

  Marketplace? get _ifood {
    for (final m in _marketplaces) {
      if (m.nome.toLowerCase() == 'ifood') return m;
    }
    return null;
  }

  Future<void> _pausarLoja() async {
    final ifood = _ifood;
    final empresaId = context.read<AuthProvider>().empresaId;
    if (ifood == null || empresaId == null) return;

    final motivoController = TextEditingController();
    Duration duracaoEscolhida = const Duration(hours: 1);

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Pausar loja no iFood'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: motivoController,
                decoration: const InputDecoration(labelText: 'Motivo (ex: acabou o estoque)'),
              ),
              const SizedBox(height: 16),
              const Text('Por quanto tempo?', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ('30 min', const Duration(minutes: 30)),
                  ('1 hora', const Duration(hours: 1)),
                  ('2 horas', const Duration(hours: 2)),
                  ('Resto do dia', null),
                ].map((opcao) {
                  final (rotulo, duracao) = opcao;
                  final selecionado = duracao == duracaoEscolhida ||
                      (duracao == null && duracaoEscolhida == _ateOFimDoDia());
                  return ChoiceChip(
                    label: Text(rotulo),
                    selected: selecionado,
                    onSelected: (_) => setDialogState(() => duracaoEscolhida = duracao ?? _ateOFimDoDia()),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Pausar')),
          ],
        ),
      ),
    );
    if (confirmado != true) return;
    final motivo = motivoController.text.trim().isEmpty ? 'Pausa manual' : motivoController.text.trim();

    try {
      await _interrupcaoRepository.pausar(
        empresaId: empresaId,
        marketplaceId: ifood.id,
        motivo: motivo,
        fim: DateTime.now().add(duracaoEscolhida),
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Loja pausada.')));
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível pausar a loja.')));
      }
    }
  }

  Duration _ateOFimDoDia() {
    final agora = DateTime.now();
    final fimDoDia = DateTime(agora.year, agora.month, agora.day, 23, 59);
    return fimDoDia.difference(agora);
  }

  Future<void> _retomarLoja() async {
    final interrupcao = _interrupcaoAtiva;
    if (interrupcao == null) return;
    try {
      await _interrupcaoRepository.cancelar(interrupcao.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Loja reaberta.')));
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível reabrir a loja.')));
      }
    }
  }

  Widget _cardPausaLoja() {
    if (_ifood == null) return const SizedBox.shrink();
    final interrupcao = _interrupcaoAtiva;
    final dateFormat = DateFormat('dd/MM HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: interrupcao == null
            ? Row(
                children: [
                  Icon(Icons.storefront, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Loja aberta no iFood')),
                  OutlinedButton(onPressed: _pausarLoja, child: const Text('Pausar loja')),
                ],
              )
            : Row(
                children: [
                  const Icon(Icons.pause_circle_outline, color: Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Loja pausada: ${interrupcao.motivo}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('Até ${dateFormat.format(interrupcao.fim)}',
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        if (interrupcao.status == 'erro' && interrupcao.erro != null)
                          Text(interrupcao.erro!, style: const TextStyle(fontSize: 12, color: Colors.red)),
                      ],
                    ),
                  ),
                  TextButton(onPressed: _retomarLoja, child: const Text('Retomar agora')),
                ],
              ),
      ),
    );
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
                    _cardPausaLoja(),
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
                              'As credenciais salvas aqui já são usadas por integrações ativas (hoje, '
                              'iFood) — mantenha atualizadas. Plataformas sem integração construída ainda '
                              'ficam com as credenciais só guardadas até lá.',
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
