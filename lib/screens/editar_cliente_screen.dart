import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:provider/provider.dart';

import '../models/cliente.dart';
import '../models/pet.dart';
import '../providers/auth_provider.dart';
import '../providers/cliente_provider.dart';
import '../services/cep_service.dart';
import '../services/distancia_service.dart';
import '../utils/cliente_validators.dart';
import '../utils/formatadores_input.dart';
import '../widgets/form_section.dart';
import 'cadastro_pet_screen.dart';
import 'editar_pet_screen.dart';
import 'selecionar_localizacao_screen.dart';

class EditarClienteScreen extends StatefulWidget {
  final Cliente clienteSelecionado;

  EditarClienteScreen({required this.clienteSelecionado});

  @override
  _EditarClienteScreenState createState() => _EditarClienteScreenState();
}

class _EditarClienteScreenState extends State<EditarClienteScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nomeController;
  late TextEditingController _celularController;
  late TextEditingController _enderecoController;
  late TextEditingController _numeroController;
  late TextEditingController _bairroController;
  late TextEditingController _cidadeController;
  late TextEditingController _estadoController;
  late TextEditingController _cepController;
  late TextEditingController _complementoController;
  late TextEditingController _emailController;
  late TextEditingController _cpfController;
  late TextEditingController _observacaoController;
  late TextEditingController _saldoController;
  final TextEditingController _outroCanalController = TextEditingController();
  late TextEditingController _aniversarioController;
  final _numeroFocusNode = FocusNode();
  final _cepFocusNode = FocusNode();

  List<Pet> _pets = [];
  bool _aceitaMarketing = false;
  bool _aceitaLembreteWhatsapp = false;
  bool _salvando = false;
  bool _autopreenchendoEndereco = false;

  double? _rangeDistancia;
  int? _estimativaEntrega;
  double? _latitude;
  double? _longitude;

  List<String> _canais = [];
  bool _canaisCarregados = false;
  String? _canalSelecionado;

  @override
  void initState() {
    super.initState();
    final cliente = widget.clienteSelecionado;
    _nomeController = TextEditingController(text: cliente.nome);
    _celularController = TextEditingController(text: cliente.celular);
    _enderecoController = TextEditingController(text: cliente.endereco);
    _numeroController = TextEditingController(text: cliente.numero);
    _bairroController = TextEditingController(text: cliente.bairro);
    _cidadeController = TextEditingController(text: cliente.cidade);
    _estadoController = TextEditingController(text: cliente.estado);
    _cepController = TextEditingController(text: cliente.cep);
    _complementoController = TextEditingController(text: cliente.complemento);
    _emailController = TextEditingController(text: cliente.email);
    _cpfController = TextEditingController(text: cliente.cpf);
    _observacaoController = TextEditingController(text: cliente.observacao);
    _saldoController = TextEditingController(text: ClienteValidators.formatarMoeda(cliente.saldo));
    _aniversarioController = TextEditingController(text: ClienteValidators.formatarData(cliente.aniversario));
    _aceitaMarketing = cliente.aceitaMarketing ?? false;
    _aceitaLembreteWhatsapp = cliente.aceitaLembreteWhatsapp;
    _pets = cliente.pets.toList();
    _rangeDistancia = cliente.rangeDistancia;
    _estimativaEntrega = cliente.estimativaEntrega;
    _latitude = cliente.latitude;
    _longitude = cliente.longitude;

    _numeroFocusNode.addListener(_aoSairDoCampoNumero);
    _cepFocusNode.addListener(_aoSairDoCampoCep);
    _carregarCanais();
  }

  void _aoSairDoCampoNumero() {
    if (!_numeroFocusNode.hasFocus) {
      _autopreencherEndereco();
    }
  }

  void _aoSairDoCampoCep() {
    if (!_cepFocusNode.hasFocus) {
      _autopreencherPorCep();
    }
  }

  /// CEP é a fonte mais confiável de endereço no Brasil — mesmo nome de
  /// rua pode existir em bairros/cidades diferentes, mas o CEP não repete.
  /// Diferente do preenchimento por rua+número, esse aqui sobrescreve
  /// rua/bairro/cidade/UF quando encontra o CEP.
  Future<void> _autopreencherPorCep() async {
    final cep = _cepController.text.trim();
    if (ClienteValidators.cep(cep) != null) return;

    setState(() => _autopreenchendoEndereco = true);
    final encontrado = await CepService.buscarPorCep(cep);
    if (!mounted) return;

    setState(() {
      if (encontrado != null) {
        if (encontrado.rua.isNotEmpty) _enderecoController.text = encontrado.rua;
        if (encontrado.bairro.isNotEmpty) _bairroController.text = encontrado.bairro;
        if (encontrado.cidade.isNotEmpty) _cidadeController.text = encontrado.cidade;
        if (encontrado.estado.isNotEmpty) _estadoController.text = encontrado.estado;
      }
      _autopreenchendoEndereco = false;
    });
  }

  Future<void> _selecionarNoMapa() async {
    final posicaoInicial = (_latitude != null && _longitude != null)
        ? LatLng(_latitude!, _longitude!)
        : null;
    final enderecoAtual = DistanciaService.montarEnderecoCliente(
      endereco: _enderecoController.text.trim(),
      numero: _numeroController.text.trim(),
      bairro: _bairroController.text.trim(),
      cidade: _cidadeController.text.trim(),
      estado: _estadoController.text.trim(),
      cep: _cepController.text.trim(),
    );

    final posicaoEscolhida = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => SelecionarLocalizacaoScreen(
          posicaoInicial: posicaoInicial,
          enderecoInicial: enderecoAtual,
        ),
      ),
    );
    if (posicaoEscolhida == null) return;

    setState(() {
      _latitude = posicaoEscolhida.latitude;
      _longitude = posicaoEscolhida.longitude;
      _autopreenchendoEndereco = true;
    });

    final encontrado = await DistanciaService.buscarEnderecoPorCoordenadas(
      latitude: posicaoEscolhida.latitude,
      longitude: posicaoEscolhida.longitude,
    );
    if (!mounted) return;

    setState(() {
      if ((encontrado?.rua ?? '').isNotEmpty) _enderecoController.text = encontrado!.rua!;
      if ((encontrado?.numero ?? '').isNotEmpty) _numeroController.text = encontrado!.numero!;
      if ((encontrado?.bairro ?? '').isNotEmpty) _bairroController.text = encontrado!.bairro!;
      if ((encontrado?.cidade ?? '').isNotEmpty) _cidadeController.text = encontrado!.cidade!;
      if ((encontrado?.estado ?? '').isNotEmpty) _estadoController.text = encontrado!.estado!;
      if ((encontrado?.cep ?? '').isNotEmpty) _cepController.text = encontrado!.cep!;
      _autopreenchendoEndereco = false;
    });
  }

  /// Assim que o usuário sai do campo "Número", busca bairro/cidade/UF/CEP
  /// automaticamente (Google Geocoding) — só preenche o que ainda estiver
  /// vazio, nunca sobrescreve algo que o usuário já digitou.
  Future<void> _autopreencherEndereco() async {
    final rua = _enderecoController.text.trim();
    final numero = _numeroController.text.trim();
    if (rua.isEmpty || numero.isEmpty) return;
    if (_bairroController.text.isNotEmpty &&
        _cidadeController.text.isNotEmpty &&
        _estadoController.text.isNotEmpty &&
        _cepController.text.isNotEmpty) {
      return;
    }

    setState(() => _autopreenchendoEndereco = true);
    final encontrado = await DistanciaService.buscarEnderecoPorRuaNumero(
      rua: rua,
      numero: numero,
    );
    if (!mounted) return;

    setState(() {
      if (_bairroController.text.isEmpty && (encontrado?.bairro ?? '').isNotEmpty) {
        _bairroController.text = encontrado!.bairro!;
      }
      if (_cidadeController.text.isEmpty && (encontrado?.cidade ?? '').isNotEmpty) {
        _cidadeController.text = encontrado!.cidade!;
      }
      if (_estadoController.text.isEmpty && (encontrado?.estado ?? '').isNotEmpty) {
        _estadoController.text = encontrado!.estado!;
      }
      if (_cepController.text.isEmpty && (encontrado?.cep ?? '').isNotEmpty) {
        _cepController.text = encontrado!.cep!;
      }
      _autopreenchendoEndereco = false;
    });
  }

  Future<void> _carregarCanais() async {
    final canais = await carregarCanaisOrigem();
    if (!mounted) return;

    setState(() {
      // `canais` já pode trazer "Outro canal" (fallback de carregarCanaisOrigem()
      // quando a tabela `canais_origem` está vazia/falha, ou um canal real
      // cadastrado com esse nome) — sem filtrar primeiro, duplicava a opção
      // e o DropdownButtonFormField quebrava (exige exatamente 1 item por valor).
      _canais = [...canais.where((c) => c != 'Outro canal'), 'Outro canal'];
      _canaisCarregados = true;

      final cliente = widget.clienteSelecionado;
      if (_canais.contains(cliente.canalOrigem)) {
        _canalSelecionado = cliente.canalOrigem;
      } else if ((cliente.canalOrigem ?? '').isNotEmpty) {
        _canalSelecionado = 'Outro canal';
        _outroCanalController.text = cliente.canalOrigem!;
      }
    });
  }

  /// Monta o Cliente atualizado com os dados do formulário + a lista de
  /// pets atual (que pode já ter sido mexida sem o usuário ter apertado
  /// "Salvar" ainda — ex: acabou de adicionar um pet).
  Cliente _montarClienteAtualizado() {
    String canalOrigem;
    if (_canalSelecionado == 'Outro canal') {
      canalOrigem = _outroCanalController.text.trim();
    } else {
      canalOrigem = _canalSelecionado ?? '';
    }

    return Cliente(
      idCliente: widget.clienteSelecionado.idCliente,
      nome: _nomeController.text.trim(),
      celular: _celularController.text.trim(),
      email: _emailController.text.trim(),
      endereco: _enderecoController.text.trim(),
      numero: _numeroController.text.trim(),
      bairro: _bairroController.text.trim(),
      cidade: _cidadeController.text.trim(),
      estado: _estadoController.text.trim().toUpperCase(),
      cep: _cepController.text.trim(),
      complemento: _complementoController.text.trim(),
      cpf: _cpfController.text.trim(),
      // tipoPessoa/cnpj/razaoSocial ainda não são editáveis nesta tela —
      // sem preservar explicitamente do cliente original, qualquer salvamento
      // aqui (mesmo só corrigindo endereço) apagaria silenciosamente esses
      // 3 campos (voltando pro default 'fisica'/'' do construtor), mesma
      // classe de bug já documentada com Venda.copyWith().
      tipoPessoa: widget.clienteSelecionado.tipoPessoa,
      cnpj: widget.clienteSelecionado.cnpj,
      razaoSocial: widget.clienteSelecionado.razaoSocial,
      observacao: _observacaoController.text.trim(),
      saldo: ClienteValidators.parseNumero(_saldoController.text) ?? 0.0,
      pets: _pets,
      canalOrigem: canalOrigem,
      aniversario: ClienteValidators.parseData(_aniversarioController.text),
      aceitaMarketing: _aceitaMarketing,
      aceitaLembreteWhatsapp: _aceitaLembreteWhatsapp,
      dataCadastro: widget.clienteSelecionado.dataCadastro,
      quantidadeCompras: widget.clienteSelecionado.quantidadeCompras,
      rangeDistancia: _rangeDistancia,
      estimativaEntrega: _estimativaEntrega,
      latitude: _latitude,
      longitude: _longitude,
    );
  }

  /// Persiste a lista de pets atual sem sair da tela — usado quando o
  /// usuário adiciona/edita/remove um pet, pra poder mexer em vários sem
  /// ser jogado de volta pros detalhes do cliente a cada um.
  Future<void> _salvarPetsSemFechar() async {
    final atualizado = _montarClienteAtualizado();
    await Provider.of<ClientProvider>(context, listen: false).atualizarCliente(atualizado);
  }

  Future<void> _salvarClienteEFechar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _salvando = true);
    try {
      final empresaId = context.read<AuthProvider>().empresaId;

      if (_canalSelecionado == 'Outro canal') {
        final novoCanal = _outroCanalController.text.trim();
        if (novoCanal.isNotEmpty && empresaId != null) {
          await adicionarCanalOrigem(novoCanal, empresaId);
        }
      }

      // Recalcula a rota real (Google Maps) da empresa até o endereço
      // atual do cliente — o endereço pode ter mudado desde a última vez.
      // Se tem coordenadas exatas (escolhidas no mapa), usa elas — são
      // mais precisas que o endereço em texto.
      final enderecoCliente = (_latitude != null && _longitude != null)
          ? '$_latitude,$_longitude'
          : DistanciaService.montarEnderecoCliente(
              endereco: _enderecoController.text.trim(),
              numero: _numeroController.text.trim(),
              bairro: _bairroController.text.trim(),
              cidade: _cidadeController.text.trim(),
              estado: _estadoController.text.trim(),
              cep: _cepController.text.trim(),
            );
      if (empresaId != null && enderecoCliente != null) {
        final enderecoEmpresa = await DistanciaService.buscarEnderecoEmpresa(empresaId);
        if (enderecoEmpresa != null) {
          final rota = await DistanciaService.calcularRota(
            origem: enderecoEmpresa,
            destino: enderecoCliente,
          );
          if (rota != null) {
            _rangeDistancia = rota.distanciaKm;
            _estimativaEntrega = rota.duracaoMin;
          }
        }
      }

      final clienteAtualizado = _montarClienteAtualizado();
      if (!mounted) return;
      await Provider.of<ClientProvider>(context, listen: false).atualizarCliente(clienteAtualizado);
      if (!mounted) return;
      Navigator.pop(context, clienteAtualizado);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar cliente: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _celularController.dispose();
    _enderecoController.dispose();
    _numeroController.dispose();
    _bairroController.dispose();
    _cidadeController.dispose();
    _estadoController.dispose();
    _cepController.dispose();
    _complementoController.dispose();
    _emailController.dispose();
    _cpfController.dispose();
    _observacaoController.dispose();
    _saldoController.dispose();
    _outroCanalController.dispose();
    _aniversarioController.dispose();
    _numeroFocusNode.dispose();
    _cepFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Saldo é crédito/débito de verdade — vendedor não pode setar um valor
    // arbitrário direto no cadastro. Ajuste de saldo passa a ser possível
    // só via "Adicionar Crédito"/"Registrar Débito" (tela de detalhes),
    // que por sua vez também é restrita a dono/gerente.
    final isVendedor = context.watch<AuthProvider>().isVendedor;

    return Scaffold(
      appBar: AppBar(
        title: Text('Editar Cliente'),
        actions: [
          _salvando
              ? Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
                  ),
                )
              : IconButton(icon: Icon(Icons.save), tooltip: 'Salvar', onPressed: _salvarClienteEFechar),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            FormSection(
              titulo: 'Dados do cliente',
              children: [
                _buildTextField('Nome', _nomeController, validator: ClienteValidators.nome),
                _buildTextField(
                  'Celular',
                  _celularController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [TelefoneInputFormatter()],
                  validator: ClienteValidators.celular,
                ),
                _buildTextField('Email', _emailController,
                    keyboardType: TextInputType.emailAddress, validator: ClienteValidators.email),
                _buildTextField(
                  'CPF',
                  _cpfController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [CpfInputFormatter()],
                  validator: ClienteValidators.cpf,
                ),
              ],
            ),
            const SizedBox(height: 16),

            FormSection(
              titulo: 'Endereço',
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Preencha rua e número (ou o CEP) — o resto é buscado automaticamente.',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _selecionarNoMapa,
                      icon: Icon(Icons.map_outlined, size: 18),
                      label: Text('Mapa'),
                    ),
                  ],
                ),
                _buildTextField('Endereço (Rua)', _enderecoController),
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: _buildTextField(
                        'Número',
                        _numeroController,
                        keyboardType: TextInputType.number,
                        focusNode: _numeroFocusNode,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: _buildTextField('Complemento', _complementoController)),
                  ],
                ),
                if (_autopreenchendoEndereco) const LinearProgressIndicator(),
                _buildTextField('Bairro', _bairroController),
                Row(
                  children: [
                    Expanded(flex: 3, child: _buildTextField('Cidade', _cidadeController)),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: _buildTextField(
                        'UF',
                        _estadoController,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 2,
                        validator: ClienteValidators.estado,
                      ),
                    ),
                  ],
                ),
                _buildTextField(
                  'CEP',
                  _cepController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [CepInputFormatter()],
                  validator: ClienteValidators.cep,
                  focusNode: _cepFocusNode,
                ),
                Text(
                  _rangeDistancia != null && _estimativaEntrega != null
                      ? 'Distância: ${_rangeDistancia!.toStringAsFixed(1)} km • '
                          'Tempo estimado: $_estimativaEntrega min'
                      : 'Distância e tempo de entrega são recalculados automaticamente '
                          'pela rota até esse endereço ao salvar.',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 16),

            FormSection(
              titulo: 'Informações adicionais',
              children: [
                _buildTextField('Observação', _observacaoController, maxLines: 3),
                if (!isVendedor)
                  _buildTextField(
                    'Saldo (R\$)',
                    _saldoController,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [MoedaInputFormatter()],
                    validator: ClienteValidators.saldo,
                  ),
                if (!_canaisCarregados)
                  const Center(child: CircularProgressIndicator())
                else
                  DropdownButtonFormField<String>(
                    value: _canalSelecionado,
                    items: _canais.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (valor) {
                      setState(() {
                        _canalSelecionado = valor;
                        if (valor != 'Outro canal') _outroCanalController.clear();
                      });
                    },
                    decoration: const InputDecoration(labelText: 'Canal de Origem'),
                  ),
                if (_canalSelecionado == 'Outro canal')
                  TextFormField(
                    controller: _outroCanalController,
                    decoration: const InputDecoration(labelText: 'Digite o canal'),
                  ),
                _buildTextField(
                  'Aniversário (DD/MM/AAAA) (Opcional)',
                  _aniversarioController,
                  keyboardType: TextInputType.datetime,
                  inputFormatters: [DataInputFormatter()],
                  validator: ClienteValidators.data,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Aceita receber promoções?'),
                  value: _aceitaMarketing,
                  onChanged: (v) => setState(() => _aceitaMarketing = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aceita lembrete de recompra por WhatsApp?'),
                  subtitle: const Text('Avisa quando um produto que ele costuma comprar provavelmente está acabando.'),
                  value: _aceitaLembreteWhatsapp,
                  onChanged: (v) => setState(() => _aceitaLembreteWhatsapp = v),
                ),
              ],
            ),
            const SizedBox(height: 16),

            FormSection(
              titulo: 'Pets',
              children: [
                OutlinedButton.icon(
                  icon: Icon(Icons.pets),
                  label: Text('Adicionar Pet'),
                  onPressed: () async {
                    final pet = await Navigator.push<Pet>(
                      context,
                      MaterialPageRoute(builder: (_) => CadastroPetScreen()),
                    );
                    if (pet != null) {
                      setState(() => _pets.add(pet));
                      await _salvarPetsSemFechar();
                    }
                  },
                ),
                if (_pets.isEmpty)
                  Text('Nenhum pet cadastrado ainda.', style: TextStyle(color: colorScheme.onSurfaceVariant))
                else
                  Column(
                    children: _pets.asMap().entries.map((entry) {
                    final i = entry.key;
                    final pet = entry.value;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: pet.imagemUrl.isNotEmpty
                              ? Image.network(pet.imagemUrl, fit: BoxFit.cover)
                              : Container(
                                  color: colorScheme.surfaceContainerHighest,
                                  child: Icon(Icons.pets, color: colorScheme.onSurfaceVariant),
                                ),
                        ),
                      ),
                      title: Text(pet.nome),
                      subtitle: Text('${pet.especie} - ${pet.raca}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Editar',
                            onPressed: () async {
                              final petEditado = await Navigator.push<Pet>(
                                context,
                                MaterialPageRoute(builder: (_) => EditarPetScreen(pet: pet)),
                              );
                              if (petEditado != null) {
                                setState(() => _pets[i] = petEditado);
                                await _salvarPetsSemFechar();
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Remover',
                            onPressed: () async {
                              setState(() => _pets.removeAt(i));
                              await _salvarPetsSemFechar();
                            },
                          ),
                        ],
                      ),
                    );
                  }).toList()),
              ],
            ),
            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _salvando ? null : _salvarClienteEFechar,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
              child: _salvando
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary),
                    )
                  : Text('Salvar Cliente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    TextCapitalization textCapitalization = TextCapitalization.none,
    int? maxLines = 1,
    int? maxLength,
    FocusNode? focusNode,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      textCapitalization: textCapitalization,
      maxLines: maxLines,
      maxLength: maxLength,
      decoration: InputDecoration(labelText: label, counterText: ''),
    );
  }
}
