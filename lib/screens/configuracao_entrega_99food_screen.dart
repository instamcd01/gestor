import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/zona_entrega.dart';
import '../providers/zona_entrega_99food_provider.dart';
import '../utils/cliente_validators.dart';
import '../utils/formatadores_input.dart';
import '../widgets/estado_erro_lista.dart';

/// Configuração de zonas de entrega específica da 99Food (distância x preço),
/// independente da configuração da loja própria (Configurações > Opções de
/// Entrega) — decisão explícita do usuário: cada canal configura suas zonas
/// separadamente, sem sincronização automática entre elas.
///
/// A sincronização com a 99Food (n8n) representa essas faixas como UMA área
/// única (média de preço/tempo) porque a API da 99Food não aceita áreas de
/// entrega sobrepostas pro mesmo horário — ver gestor_99food_integration_architecture.
class ConfiguracaoEntrega99FoodScreen extends StatefulWidget {
  const ConfiguracaoEntrega99FoodScreen({super.key});

  @override
  State<ConfiguracaoEntrega99FoodScreen> createState() => _ConfiguracaoEntrega99FoodScreenState();
}

class _ConfiguracaoEntrega99FoodScreenState extends State<ConfiguracaoEntrega99FoodScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ZonaEntrega99FoodProvider>().carregarZonas();
    });
  }

  Future<void> _abrirFormulario({ZonaEntrega? zonaExistente}) async {
    final zonas = context.read<ZonaEntrega99FoodProvider>().zonas;
    final salvo = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormularioZonaEntrega99Food(
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
      await context.read<ZonaEntrega99FoodProvider>().excluirZona(zona.id!);
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
    final provider = context.watch<ZonaEntrega99FoodProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Zonas de Entrega — 99Food')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add),
        label: const Text('Nova zona'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'A 99Food não aceita várias faixas de preço sobrepostas — essas zonas '
                      'são sincronizadas como uma área única (média de preço e tempo). '
                      'Configure aqui só pra referência e para calcular essa média.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (provider.carregando)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (provider.erro != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: EstadoErroLista(mensagem: provider.erro!, onTentarNovamente: provider.carregarZonas),
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
                        if (zona.estimativaMinMin != null && zona.estimativaMinMax != null)
                          Text(
                            'Estimativa: ${zona.estimativaMinMin} a ${zona.estimativaMinMax} min',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
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

class _FormularioZonaEntrega99Food extends StatefulWidget {
  final ZonaEntrega? zonaExistente;
  final List<ZonaEntrega> zonasExistentes;

  const _FormularioZonaEntrega99Food({this.zonaExistente, required this.zonasExistentes});

  @override
  State<_FormularioZonaEntrega99Food> createState() => _FormularioZonaEntrega99FoodState();
}

class _FormularioZonaEntrega99FoodState extends State<_FormularioZonaEntrega99Food> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomeController;
  late final TextEditingController _minController;
  late final TextEditingController _maxController;
  late final TextEditingController _valorController;
  late final TextEditingController _estimativaMinController;
  late final TextEditingController _estimativaMaxController;
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
    _estimativaMinController = TextEditingController(text: zona?.estimativaMinMin?.toString() ?? '');
    _estimativaMaxController = TextEditingController(text: zona?.estimativaMinMax?.toString() ?? '');
    _ativo = zona?.ativo ?? true;
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _minController.dispose();
    _maxController.dispose();
    _valorController.dispose();
    _estimativaMinController.dispose();
    _estimativaMaxController.dispose();
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

  String? _validarEstimativa() {
    final minTexto = _estimativaMinController.text.trim();
    final maxTexto = _estimativaMaxController.text.trim();
    if (minTexto.isEmpty && maxTexto.isEmpty) return null;

    final min = int.tryParse(minTexto);
    final max = int.tryParse(maxTexto);
    if (min == null || max == null) return 'Informe os dois campos de estimativa, ou deixe os dois em branco';
    if (max < min) return 'Estimativa "até" deve ser maior ou igual à "de"';
    return null;
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    final sobreposicao = _validarSobreposicao();
    if (sobreposicao != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sobreposicao)));
      return;
    }

    final erroEstimativa = _validarEstimativa();
    if (erroEstimativa != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erroEstimativa)));
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
        ativo: _ativo,
        estimativaMinMin: int.tryParse(_estimativaMinController.text.trim()),
        estimativaMinMax: int.tryParse(_estimativaMaxController.text.trim()),
      );

      final provider = context.read<ZonaEntrega99FoodProvider>();
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
              widget.zonaExistente != null ? 'Editar Zona (99Food)' : 'Nova Zona (99Food)',
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
            Text(
              'Estimativa de entrega (opcional)',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _estimativaMinController,
                    decoration: const InputDecoration(labelText: 'De (min)'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [InteiroInputFormatter()],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _estimativaMaxController,
                    decoration: const InputDecoration(labelText: 'Até (min)'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [InteiroInputFormatter()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
