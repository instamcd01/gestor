import 'package:flutter/material.dart';

import '../models/marketplace.dart';
import '../models/marketplace_config.dart';
import '../screens/configuracao_entrega_99food_screen.dart';

/// Card expansível de credenciais/config de um marketplace — usado tanto na
/// tela dedicada do iFood quanto na tela genérica de plataformas sem
/// recursos próprios ainda (99Food, Rappi...).
class MarketplaceConfigCard extends StatefulWidget {
  final Marketplace marketplace;
  final MarketplaceConfig config;
  final ValueChanged<MarketplaceConfig> onSalvar;
  final bool iniciaExpandido;

  const MarketplaceConfigCard({
    super.key,
    required this.marketplace,
    required this.config,
    required this.onSalvar,
    this.iniciaExpandido = false,
  });

  @override
  State<MarketplaceConfigCard> createState() => _MarketplaceConfigCardState();
}

class _MarketplaceConfigCardState extends State<MarketplaceConfigCard> {
  late bool _ativo;
  late final TextEditingController _idLojaController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _apiSecretController;
  late final TextEditingController _observacoesController;
  String? _modoEntrega;
  bool _mostrarSecret = false;
  late bool _expandido;

  @override
  void initState() {
    super.initState();
    _ativo = widget.config.ativo;
    _idLojaController = TextEditingController(text: widget.config.idLojaPlataforma);
    _apiKeyController = TextEditingController(text: widget.config.apiKey);
    _apiSecretController = TextEditingController(text: widget.config.apiSecret);
    _observacoesController = TextEditingController(text: widget.config.observacoes);
    _modoEntrega = widget.config.modoEntrega;
    _expandido = widget.iniciaExpandido;
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
      modoEntrega: _modoEntrega,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Modo de entrega',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [
                      (null, 'Não definido'),
                      (ModoEntrega.propria, 'Entrega própria'),
                      (ModoEntrega.plataforma, 'Entrega pela plataforma'),
                    ].map((opcao) {
                      final (valor, rotulo) = opcao;
                      return ChoiceChip(
                        label: Text(rotulo),
                        selected: _modoEntrega == valor,
                        onSelected: (_) => setState(() => _modoEntrega = valor),
                      );
                    }).toList(),
                  ),
                  if (widget.marketplace.nome == '99Food') ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ConfiguracaoEntrega99FoodScreen()),
                      ),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Configurar zonas de entrega da 99Food'),
                    ),
                  ],
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
