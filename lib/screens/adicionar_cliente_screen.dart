import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

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
import 'selecionar_localizacao_screen.dart';

class AdicionarClienteScreen extends StatefulWidget {
  AdicionarClienteScreen({super.key});

  @override
  _AdicionarClienteScreenState createState() => _AdicionarClienteScreenState();
}

class _AdicionarClienteScreenState extends State<AdicionarClienteScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nomeController = TextEditingController();
  final _celularController = TextEditingController();
  final _enderecoController = TextEditingController();
  final _numeroController = TextEditingController();
  final _bairroController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _estadoController = TextEditingController();
  final _cepController = TextEditingController();
  final _complementoController = TextEditingController();
  final _emailController = TextEditingController();
  final _cpfController = TextEditingController();
  final _observacaoController = TextEditingController();
  final _saldoController = TextEditingController();
  final _outroCanalController = TextEditingController();
  final _aniversarioController = TextEditingController();
  final _numeroFocusNode = FocusNode();
  final _cepFocusNode = FocusNode();

  List<Pet> _pets = [];
  bool _aceitaMarketing = false;
  bool _aceitaLembreteWhatsapp = false;
  bool _salvando = false;
  bool _autopreenchendoEndereco = false;
  double? _latitude;
  double? _longitude;

  List<String> _canais = [];
  bool _canaisCarregados = false;
  String? _canalSelecionado;

  @override
  void initState() {
    super.initState();
    _carregarCanais();
    _numeroFocusNode.addListener(_aoSairDoCampoNumero);
    _cepFocusNode.addListener(_aoSairDoCampoCep);
  }

  Future<void> _carregarCanais() async {
    final canais = await carregarCanaisOrigem();
    if (mounted) {
      setState(() {
        _canais = [...canais, 'Outro canal'];
        _canaisCarregados = true;
      });
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
  /// Por isso, diferente do preenchimento por rua+número, esse aqui
  /// sobrescreve rua/bairro/cidade/UF quando encontra o CEP.
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
      // Ponto escolhido manualmente é a fonte mais confiável possível —
      // sobrescreve o endereço em texto pra ficar coerente com o pino.
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

  void _abrirGoogleMaps(String endereco) async {
    if (endereco.isEmpty) return;
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(endereco)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir o Google Maps')),
      );
    }
  }

  Future<void> _salvarCliente() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _salvando = true);
    try {
      String canalOrigem;
      final empresaId = context.read<AuthProvider>().empresaId;
      if (_canalSelecionado == 'Outro canal') {
        canalOrigem = _outroCanalController.text.trim();
        if (canalOrigem.isNotEmpty && empresaId != null) {
          await adicionarCanalOrigem(canalOrigem, empresaId);
        }
      } else {
        canalOrigem = _canalSelecionado ?? '';
      }

      // Distância e tempo de entrega são calculados automaticamente pela
      // rota real (Google Maps), da empresa até o endereço do cliente —
      // não é mais um campo que o usuário preenche manualmente. Se o
      // cliente tem coordenadas exatas (escolhidas no mapa), usa elas —
      // são mais precisas que o endereço em texto.
      double? rangeDistancia;
      int? estimativaEntrega;
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
          rangeDistancia = rota?.distanciaKm;
          estimativaEntrega = rota?.duracaoMin;
        }
      }

      final cliente = Cliente(
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
        observacao: _observacaoController.text.trim(),
        saldo: ClienteValidators.parseNumero(_saldoController.text) ?? 0.0,
        pets: _pets,
        dataCadastro: DateTime.now(),
        aniversario: ClienteValidators.parseData(_aniversarioController.text),
        canalOrigem: canalOrigem,
        aceitaMarketing: _aceitaMarketing,
        aceitaLembreteWhatsapp: _aceitaLembreteWhatsapp,
        rangeDistancia: rangeDistancia,
        estimativaEntrega: estimativaEntrega,
        latitude: _latitude,
        longitude: _longitude,
      );

      if (!mounted) return;
      final clienteSalvo =
          await Provider.of<ClientProvider>(context, listen: false).addCliente(cliente);
      if (!mounted) return;
      Navigator.pop(context, clienteSalvo);
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
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Mesma razão do editar: saldo é crédito de verdade, vendedor não pode
    // conceder um valor arbitrário na criação do cliente.
    final isVendedor = context.watch<AuthProvider>().isVendedor;

    return Scaffold(
      appBar: AppBar(title: Text('Adicionar Cliente')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  _buildTextField(
                    'Email',
                    _emailController,
                    keyboardType: TextInputType.emailAddress,
                    validator: ClienteValidators.email,
                  ),
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
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _enderecoController,
                          decoration: const InputDecoration(labelText: 'Endereço (Rua)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.directions),
                        tooltip: 'Ver rota no Google Maps',
                        onPressed: () => _abrirGoogleMaps(_enderecoController.text),
                      ),
                    ],
                  ),
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
                      Expanded(
                        flex: 2,
                        child: _buildTextField('Complemento', _complementoController),
                      ),
                    ],
                  ),
                  if (_autopreenchendoEndereco) const LinearProgressIndicator(),
                  _buildTextField('Bairro', _bairroController),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _buildTextField('Cidade', _cidadeController),
                      ),
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
                    'Distância e tempo de entrega são calculados automaticamente '
                    'pela rota até esse endereço quando o cliente for salvo.',
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
                      items: _canais.map((c) {
                        return DropdownMenuItem(value: c, child: Text(c));
                      }).toList(),
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
                  // Opt-in específico pro lembrete automático de recompra
                  // (mesmo campo que o checkbox do login no site grava) —
                  // pra cliente que só compra por WhatsApp/loja física
                  // conseguir ser avisado também, sem depender dele logar
                  // no site pra ter essa chance.
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
                    label: Text('Cadastrar Pet'),
                    onPressed: () async {
                      final pet = await Navigator.push<Pet>(
                        context,
                        MaterialPageRoute(builder: (_) => CadastroPetScreen()),
                      );
                      if (pet != null) {
                        setState(() => _pets.add(pet));
                      }
                    },
                  ),
                  if (_pets.isEmpty)
                    Text(
                      'Nenhum pet cadastrado ainda.',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    )
                  else
                    Column(
                      children: _pets
                          .map((pet) => ListTile(
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
                              ))
                          .toList(),
                    ),
                ],
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _salvando ? null : _salvarCliente,
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                child: _salvando
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.onPrimary),
                      )
                    : Text('Salvar'),
              ),
            ],
          ),
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
