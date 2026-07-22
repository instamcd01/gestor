import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/zona_entrega.dart';
import '../providers/auth_provider.dart';
import '../providers/zona_entrega_provider.dart';
import '../services/distancia_service.dart';
import '../utils/cliente_validators.dart';
import '../utils/formatadores_input.dart';
import 'dados_loja_screen.dart';

/// Configurações de entrega (Configurações > Opções de Entrega): as
/// faixas de distância x preço usadas no checkout pra calcular o frete a
/// partir da distância real até o cliente.
class ConfiguracaoEntregaScreen extends StatefulWidget {
  const ConfiguracaoEntregaScreen({super.key});

  @override
  State<ConfiguracaoEntregaScreen> createState() => _ConfiguracaoEntregaScreenState();
}

class _ConfiguracaoEntregaScreenState extends State<ConfiguracaoEntregaScreen> {
  String? _enderecoOrigem;
  bool _carregandoEndereco = true;

  @override
  void initState() {
    super.initState();
    _carregarEnderecoOrigem();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ZonaEntregaProvider>().carregarZonas();
    });
  }

  Future<void> _carregarEnderecoOrigem() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId != null) {
      _enderecoOrigem = await DistanciaService.buscarEnderecoEmpresa(empresaId);
    }
    if (mounted) setState(() => _carregandoEndereco = false);
  }

  Future<void> _abrirFormulario({ZonaEntrega? zonaExistente}) async {
    final zonas = context.read<ZonaEntregaProvider>().zonas;
    final salvo = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormularioZonaEntrega(
        zonaExistente: zonaExistente,
        zonasExistentes: zonas,
      ),
    );
    if (salvo == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(zonaExistente != null ? 'Zona atualizada!' : 'Zona criada!')),
      );
    }
  }

  Future<void> _excluirZona(ZonaEntrega zona) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir zona de entrega'),
        content: Text('Excluir "${zona.nome}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmar != true || zona.id == null) return;

    try {
      await context.read<ZonaEntregaProvider>().excluirZona(zona.id!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao excluir: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ZonaEntregaProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Opções de Entrega')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add),
        label: const Text('Nova zona'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.store),
              title: const Text('Endereço de origem'),
              subtitle: _carregandoEndereco
                  ? const Text('Carregando...')
                  : Text(_enderecoOrigem ?? 'Nenhum endereço cadastrado em Dados da Loja'),
              trailing: TextButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DadosLojaScreen()),
                  );
                  _carregarEnderecoOrigem();
                },
                child: const Text('Editar'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'É a partir desse endereço que a distância até cada cliente é calculada.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Faixas de Entrega',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            'O frete é calculado automaticamente pela faixa de distância em que o cliente cai.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          if (provider.carregando)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (provider.zonas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('Nenhuma zona de entrega cadastrada ainda.')),
            )
          else
            ...provider.zonas.map((zona) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(zona.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${zona.distanciaMinKm.toStringAsFixed(1)} a ${zona.distanciaMaxKm.toStringAsFixed(1)} km — '
                          'R\$ ${zona.valor.toStringAsFixed(2)}',
                        ),
                        if (zona.valorMinimoFreteGratis != null)
                          Text(
                            'Frete grátis a partir de R\$ ${zona.valorMinimoFreteGratis!.toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.green, fontSize: 12),
                          ),
                        if (!zona.ativo)
                          const Text('Desativada', style: TextStyle(color: Colors.red, fontSize: 12)),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _abrirFormulario(zonaExistente: zona),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _excluirZona(zona),
                        ),
                      ],
                    ),
                  ),
                )),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _FormularioZonaEntrega extends StatefulWidget {
  final ZonaEntrega? zonaExistente;
  final List<ZonaEntrega> zonasExistentes;

  const _FormularioZonaEntrega({this.zonaExistente, required this.zonasExistentes});

  @override
  State<_FormularioZonaEntrega> createState() => _FormularioZonaEntregaState();
}

class _FormularioZonaEntregaState extends State<_FormularioZonaEntrega> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomeController;
  late final TextEditingController _minController;
  late final TextEditingController _maxController;
  late final TextEditingController _valorController;
  late final TextEditingController _minimoFreteGratisController;
  late bool _ativo;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final zona = widget.zonaExistente;
    _nomeController = TextEditingController(text: zona?.nome ?? '');
    _minController = TextEditingController(
        text: zona != null ? zona.distanciaMinKm.toString().replaceAll('.', ',') : '');
    _maxController = TextEditingController(
        text: zona != null ? zona.distanciaMaxKm.toString().replaceAll('.', ',') : '');
    _valorController = TextEditingController(text: ClienteValidators.formatarMoeda(zona?.valor));
    _minimoFreteGratisController =
        TextEditingController(text: ClienteValidators.formatarMoeda(zona?.valorMinimoFreteGratis));
    _ativo = zona?.ativo ?? true;
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _minController.dispose();
    _maxController.dispose();
    _valorController.dispose();
    _minimoFreteGratisController.dispose();
    super.dispose();
  }

  String? _validarSobreposicao() {
    final min = ClienteValidators.parseNumero(_minController.text);
    final max = ClienteValidators.parseNumero(_maxController.text);
    if (min == null || max == null) return null;

    final candidata = ZonaEntrega(
      id: widget.zonaExistente?.id,
      nome: _nomeController.text,
      distanciaMinKm: min,
      distanciaMaxKm: max,
      valor: 0,
    );

    for (final outra in widget.zonasExistentes) {
      if (outra.id != null && outra.id == widget.zonaExistente?.id) continue;
      if (candidata.sobrepoe(outra)) {
        return 'Sobrepõe a faixa "${outra.nome}" (${outra.distanciaMinKm}–${outra.distanciaMaxKm} km)';
      }
    }
    return null;
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    final sobreposicao = _validarSobreposicao();
    if (sobreposicao != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sobreposicao)));
      return;
    }

    setState(() => _salvando = true);
    try {
      final zona = ZonaEntrega(
        id: widget.zonaExistente?.id,
        nome: _nomeController.text.trim(),
        distanciaMinKm: ClienteValidators.parseNumero(_minController.text)!,
        distanciaMaxKm: ClienteValidators.parseNumero(_maxController.text)!,
        valor: ClienteValidators.parseNumero(_valorController.text) ?? 0,
        valorMinimoFreteGratis: ClienteValidators.parseNumero(_minimoFreteGratisController.text),
        ativo: _ativo,
      );

      final provider = context.read<ZonaEntregaProvider>();
      if (widget.zonaExistente != null) {
        await provider.atualizarZona(zona);
      } else {
        await provider.criarZona(zona);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar zona: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.zonaExistente != null ? 'Editar Zona de Entrega' : 'Nova Zona de Entrega',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nomeController,
              decoration: const InputDecoration(labelText: 'Nome (ex: Até 5km)'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe um nome' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _minController,
                    decoration: const InputDecoration(labelText: 'De (km)'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [DecimalInputFormatter()],
                    validator: (v) {
                      final n = ClienteValidators.parseNumero(v);
                      if (n == null) return 'Obrigatório';
                      if (n < 0) return 'Não pode ser negativo';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _maxController,
                    decoration: const InputDecoration(labelText: 'Até (km)'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [DecimalInputFormatter()],
                    validator: (v) {
                      final max = ClienteValidators.parseNumero(v);
                      final min = ClienteValidators.parseNumero(_minController.text);
                      if (max == null) return 'Obrigatório';
                      if (min != null && max <= min) return 'Deve ser maior que "De"';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _valorController,
              decoration: const InputDecoration(labelText: 'Valor da entrega (R\$)', prefixText: 'R\$ '),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [MoedaInputFormatter()],
              validator: (v) {
                final n = ClienteValidators.parseNumero(v);
                if (n == null) return 'Obrigatório';
                if (n < 0) return 'Não pode ser negativo';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _minimoFreteGratisController,
              decoration: const InputDecoration(
                labelText: 'Frete grátis a partir de (R\$) (Opcional)',
                prefixText: 'R\$ ',
                helperText: 'Deixe em branco pra nunca ter frete grátis nessa faixa',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [MoedaInputFormatter()],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ativa'),
              value: _ativo,
              onChanged: (v) => setState(() => _ativo = v),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _salvando ? null : _salvar,
                child: _salvando
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Salvar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
