import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/supabase_config.dart';
import '../models/cliente.dart';
import '../models/zona_entrega.dart';
import '../providers/auth_provider.dart';
import '../providers/cliente_provider.dart';
import '../providers/zona_entrega_provider.dart';
import '../repositories/cliente_repository.dart';
import '../services/distancia_service.dart';
import '../utils/agendamento_utils.dart';
import '../utils/busca_utils.dart';
import 'adicionar_cliente_screen.dart';
import 'configuracao_entrega_screen.dart';
import 'editar_cliente_screen.dart';

/// Escolhe o cliente da venda e resolve a entrega: usa a distância já
/// calculada e salva no cadastro do cliente (ver `DistanciaService`) pra
/// achar a zona de entrega correspondente em `ZonaEntregaProvider`. Se o
/// cliente ainda não tem distância salva, calcula na hora.
class OpcaoEntregaScreen extends StatefulWidget {
  final double subtotal;

  const OpcaoEntregaScreen({super.key, required this.subtotal});

  @override
  State<OpcaoEntregaScreen> createState() => _OpcaoEntregaScreenState();
}

class _OpcaoEntregaScreenState extends State<OpcaoEntregaScreen> {
  final _buscaClienteController = TextEditingController();

  Cliente? _clienteSelecionado;
  List<Cliente> _clientesFiltrados = [];
  bool _carregandoClientes = true;

  // Cadastros "consultivos" do histórico do Kyte (sem login, ficam fora da
  // lista normal — ver [[gestor_vinculo_cliente_cross_canal]]) só aparecem
  // aqui quando a busca acha um, com atalho pra promover na hora sem sair
  // do fluxo de venda pra achar de novo em Clientes > Histórico Kyte.
  List<Cliente> _todosClientesKyte = [];
  List<Cliente> _clientesKyteFiltrados = [];
  String? _promovendoKyteId;

  bool _retirarNaLoja = false;
  double? _distanciaKm;
  int? _estimativaMin;
  bool _calculandoDistancia = false;
  ZonaEntrega? _zonaEncontrada;

  Map<String, dynamic>? _horarioFuncionamento;
  bool _agendando = false;
  OpcaoDataAgendamento? _dataEscolhida;
  JanelaHorarioAgendamento? _janelaEscolhida;

  @override
  void initState() {
    super.initState();
    _carregarClientes();
    _carregarHorarioFuncionamento();
  }

  Future<void> _carregarHorarioFuncionamento() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    try {
      final data = await supabase
          .from('empresas')
          .select('horario_funcionamento')
          .eq('id', empresaId)
          .single();
      if (mounted) {
        setState(() {
          _horarioFuncionamento = data['horario_funcionamento'] as Map<String, dynamic>?;
          final opcoes = gerarOpcoesData(_horarioFuncionamento);
          _dataEscolhida = opcoes.isNotEmpty ? opcoes.first : null;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar horário de funcionamento: $e');
    }
  }

  @override
  void dispose() {
    _buscaClienteController.dispose();
    super.dispose();
  }

  Future<void> _carregarClientes() async {
    final kyte = await ClienteRepository().listarHistoricoKyte();
    await Provider.of<ClientProvider>(context, listen: false).carregarClientes();
    if (!mounted) return;
    setState(() {
      _todosClientesKyte = kyte;
      _carregandoClientes = false;
    });

    final clienteJaSelecionado =
        Provider.of<ClientProvider>(context, listen: false).clienteSelecionado;
    if (clienteJaSelecionado != null) {
      _selecionarCliente(clienteJaSelecionado);
    }
  }

  void _filtrarClientes(String texto, List<Cliente> todosClientes) {
    setState(() {
      _clientesFiltrados = todosClientes.where((c) {
        final textoCompleto = [c.nome, c.celular, c.enderecoCompleto].join(' ');
        return contemTodasPalavras(textoCompleto, texto);
      }).toList();
      _clientesKyteFiltrados = texto.trim().isEmpty
          ? []
          : _todosClientesKyte.where((c) {
              final textoCompleto = [c.nome, c.telefoneKyte ?? ''].join(' ');
              return contemTodasPalavras(textoCompleto, texto);
            }).toList();
    });
  }

  /// Promove o cadastro Kyte na hora (mesma RPC de `cliente_detalhes_screen`,
  /// ver [[gestor_vinculo_cliente_cross_canal]]) e já seleciona pra essa
  /// venda — evita sair da tela de entrega pra ir em Clientes > Histórico
  /// Kyte e voltar depois.
  Future<void> _usarCadastroKyte(Cliente cliente) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usar este cadastro'),
        content: Text(
          'O telefone ${cliente.telefoneKyte ?? ''} vira o telefone oficial desse cadastro e ele passa a '
          'fazer parte da lista normal de clientes. O histórico de pedidos continua o mesmo.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    setState(() => _promovendoKyteId = cliente.idCliente);
    try {
      await ClienteRepository().promoverHistoricoKyte(cliente.idCliente!);
      await _carregarClientes();
      if (!mounted) return;
      final promovido = Provider.of<ClientProvider>(context, listen: false)
          .clientes
          .firstWhere((c) => c.idCliente == cliente.idCliente, orElse: () => cliente);
      setState(() {
        _buscaClienteController.clear();
        _clientesFiltrados = [];
        _clientesKyteFiltrados = [];
      });
      await _selecionarCliente(promovido);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cadastro liberado — cliente selecionado pra essa venda.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível usar esse cadastro: $e')),
      );
    } finally {
      if (mounted) setState(() => _promovendoKyteId = null);
    }
  }

  Future<void> _selecionarCliente(Cliente cliente) async {
    setState(() {
      _clienteSelecionado = cliente;
      _buscaClienteController.text = cliente.nome;
      _clientesFiltrados = [];
      _distanciaKm = cliente.rangeDistancia;
      _estimativaMin = cliente.estimativaEntrega;
      _zonaEncontrada = null;
    });

    if (_distanciaKm == null) {
      await _calcularDistanciaAgora(cliente);
    } else {
      _resolverZona();
    }
  }

  /// Cliente ainda não tem distância salva (cadastro antigo, ou geocoding
  /// falhou na hora de salvar) — calcula agora em vez de travar a venda.
  Future<void> _calcularDistanciaAgora(Cliente cliente) async {
    final empresaId = context.read<AuthProvider>().empresaId;
    final enderecoCliente = cliente.enderecoCompleto;
    if (empresaId == null || enderecoCliente.isEmpty) return;

    setState(() => _calculandoDistancia = true);
    final enderecoEmpresa = await DistanciaService.buscarEnderecoEmpresa(empresaId);
    if (enderecoEmpresa != null) {
      final rota = await DistanciaService.calcularRota(
        origem: enderecoEmpresa,
        destino: (cliente.latitude != null && cliente.longitude != null)
            ? '${cliente.latitude},${cliente.longitude}'
            : enderecoCliente,
      );
      if (mounted && rota != null) {
        setState(() {
          _distanciaKm = rota.distanciaKm;
          _estimativaMin = rota.duracaoMin;
          // Atualiza o cliente em memória também — sem isso, quem confirma
          // a entrega logo em seguida ainda carregava a versão antiga (sem
          // distância) pro resto do checkout.
          if (_clienteSelecionado?.idCliente == cliente.idCliente) {
            _clienteSelecionado = _clienteSelecionado!.copyWith(
              rangeDistancia: rota.distanciaKm,
              estimativaEntrega: rota.duracaoMin,
            );
          }
        });
        // Salva no cadastro do cliente pra não precisar recalcular (chamada
        // paga à API) no próximo checkout — best-effort, não trava a venda
        // se falhar.
        if (cliente.idCliente != null) {
          unawaited(
            ClienteRepository().atualizarDistancia(
              cliente.idCliente!,
              rangeDistancia: rota.distanciaKm,
              estimativaEntrega: rota.duracaoMin,
            ),
          );
        }
      }
    }
    if (!mounted) return;
    setState(() => _calculandoDistancia = false);
    _resolverZona();
  }

  Future<void> _editarEnderecoClienteSelecionado() async {
    final cliente = _clienteSelecionado;
    if (cliente == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditarClienteScreen(clienteSelecionado: cliente)),
    );
    if (!mounted) return;
    // EditarClienteScreen já recalcula e salva a distância ao salvar — pega
    // a versão atualizada do provider (não a `cliente` capturada acima,
    // que ficou parada no que era antes de editar).
    final atualizado = Provider.of<ClientProvider>(context, listen: false)
        .clientes
        .firstWhere((c) => c.idCliente == cliente.idCliente, orElse: () => cliente);
    await _selecionarCliente(atualizado);
  }

  void _resolverZona() {
    if (_distanciaKm == null) return;
    final zona = context.read<ZonaEntregaProvider>().zonaParaDistancia(_distanciaKm!);
    setState(() => _zonaEncontrada = zona);
  }

  void _abrirRotaNoGoogleMaps() async {
    if (_clienteSelecionado == null) return;
    // Sem origin, o Google Maps usa a localização atual de quem abriu o
    // link — não a loja — e mostra uma rota totalmente diferente da que o
    // app calculou (achado real 12/09: usuário testando de outro lugar via
    // o botão viu 4,4km/11min, enquanto o cálculo real loja→cliente,
    // conferido direto na API, dava 6,1km/11min corretamente).
    final empresaId = context.read<AuthProvider>().empresaId;
    final enderecoEmpresa = empresaId != null ? await DistanciaService.buscarEnderecoEmpresa(empresaId) : null;
    final destino = Uri.encodeComponent(_clienteSelecionado!.enderecoCompleto);
    final origemParam = enderecoEmpresa != null ? '&origin=${Uri.encodeComponent(enderecoEmpresa)}' : '';
    final url = 'https://www.google.com/maps/dir/?api=1$origemParam&destination=$destino&travelmode=driving';
    if (!mounted) return;
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o Google Maps')),
      );
    }
  }

  bool get _podeConfirmar {
    if (_clienteSelecionado == null) return false;
    if (_agendando && _janelaEscolhida == null) return false;
    if (_retirarNaLoja) return true;
    return _zonaEncontrada != null;
  }

  void _confirmar() {
    if (!_podeConfirmar) return;
    Navigator.pop(context, {
      'cliente': _clienteSelecionado,
      'zona': _retirarNaLoja ? null : _zonaEncontrada,
      'agendamento': _agendando ? _janelaEscolhida : null,
    });
  }

  @override
  Widget build(BuildContext context) {
    final clienteProvider = context.watch<ClientProvider>();
    final todosClientes = clienteProvider.clientes;
    // A lista geral vem em ordem alfabética (certo pra buscar por nome),
    // mas o atalho "sem busca" faz mais sentido mostrar quem foi cadastrado
    // por último — é o caso mais comum de quem acabou de criar o cliente
    // durante a venda e precisa achá-lo rápido.
    final clientesParaMostrar = _buscaClienteController.text.isEmpty && _clientesFiltrados.isEmpty
        ? (List<Cliente>.from(todosClientes)
              ..sort((a, b) => (b.dataCadastro ?? DateTime(0)).compareTo(a.dataCadastro ?? DateTime(0))))
            .take(5)
            .toList()
        : _clientesFiltrados;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Entrega'),
        actions: [
          // Atalho pra configuração de zonas/preço de entrega — pulava o
          // menu Configurações (já restrito a dono/gerente) inteiro, então
          // vendedor conseguia mexer em preço de frete por aqui.
          if (context.watch<AuthProvider>().podeVerFinancas)
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Configurar zonas de entrega',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ConfiguracaoEntregaScreen()),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _buscaClienteController,
                decoration: const InputDecoration(
                  labelText: 'Buscar cliente (nome, celular ou endereço)',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (texto) {
                  setState(() {});
                  _filtrarClientes(texto, todosClientes);
                },
              ),
              const SizedBox(height: 8),

              if (_carregandoClientes)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: clientesParaMostrar.length,
                  itemBuilder: (context, index) {
                    final cliente = clientesParaMostrar[index];
                    return ListTile(
                      title: Text(cliente.nome),
                      subtitle: Text(cliente.enderecoCompleto.isNotEmpty
                          ? cliente.enderecoExibicao
                          : cliente.celular),
                      trailing: const Icon(Icons.person),
                      selected: _clienteSelecionado?.idCliente == cliente.idCliente,
                      onTap: () => _selecionarCliente(cliente),
                    );
                  },
                ),

              if (_clientesKyteFiltrados.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    'Encontrado no histórico Kyte (sem cadastro ativo)',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _clientesKyteFiltrados.length,
                  itemBuilder: (context, index) {
                    final cliente = _clientesKyteFiltrados[index];
                    return ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(cliente.nome),
                      subtitle: Text(cliente.telefoneKyte ?? ''),
                      trailing: _promovendoKyteId == cliente.idCliente
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : TextButton(
                              onPressed: () => _usarCadastroKyte(cliente),
                              child: const Text('Usar este cadastro'),
                            ),
                    );
                  },
                ),
              ],

              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.person_add),
                  label: const Text('Cadastrar novo cliente'),
                  onPressed: () async {
                    // Antes só recarregava a lista e deixava a pessoa achar
                    // o cliente recém-criado na mão (lista é alfabética,
                    // então ele quase nunca aparecia nos 5 primeiros) —
                    // agora seleciona direto, sem precisar procurar.
                    final novoCliente = await Navigator.push<Cliente>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AdicionarClienteScreen(),
                      ),
                    );
                    await _carregarClientes();
                    if (novoCliente != null && mounted) {
                      _selecionarCliente(novoCliente);
                    }
                  },
                ),
              ),

              if (_clienteSelecionado != null) ...[
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cliente vai retirar na loja'),
                  subtitle: const Text('Sem cobrança de entrega'),
                  value: _retirarNaLoja,
                  onChanged: (v) => setState(() => _retirarNaLoja = v),
                ),
                if (!_retirarNaLoja) _buildResumoEntrega(),
                const Divider(),
                _buildAgendamento(),
              ],

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _podeConfirmar ? _confirmar : null,
                  child: const Text('Confirmar Entrega'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Quero agora" (padrão) vs "Agendar" — mesmas janelas de 1h dentro do
  /// horário de funcionamento oferecidas no checkout do site, pro vendedor
  /// marcar hora quando o cliente pede por telefone/WhatsApp. Vale tanto
  /// pra entrega quanto pra retirada.
  Widget _buildAgendamento() {
    final opcoesData = gerarOpcoesData(_horarioFuncionamento);
    if (opcoesData.isEmpty) return const SizedBox.shrink();

    final janelasHorario = _dataEscolhida != null
        ? gerarJanelasHorario(_dataEscolhida!.data, _dataEscolhida!.diaSemana, _horarioFuncionamento)
        : <JanelaHorarioAgendamento>[];

    // Mesma faixa configurada na zona que vira a previsão automática
    // (ConclusaoVendaScreen) quando o vendedor não agenda — mostrada aqui
    // como legenda de "Quero agora", igual ao checkout do site.
    final estimativaMin = _zonaEncontrada?.estimativaMinMin;
    final estimativaMax = _zonaEncontrada?.estimativaMinMax;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Quando?', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ChoiceChip(
                    label: const Text('Quero agora'),
                    selected: !_agendando,
                    onSelected: (_) => setState(() {
                      _agendando = false;
                      _janelaEscolhida = null;
                    }),
                  ),
                  if (estimativaMin != null && estimativaMax != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4),
                      child: Text(
                        'Entrega estimada em $estimativaMin–$estimativaMax min',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChoiceChip(
                label: const Text('Agendar'),
                selected: _agendando,
                onSelected: (_) => setState(() => _agendando = true),
              ),
            ),
          ],
        ),
        if (_agendando) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: opcoesData.map((opcao) {
              return ChoiceChip(
                label: Text(opcao.label),
                selected: _dataEscolhida?.data == opcao.data,
                onSelected: (_) => setState(() {
                  _dataEscolhida = opcao;
                  _janelaEscolhida = null;
                }),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          if (janelasHorario.isEmpty)
            Text(
              'Sem horários disponíveis nesse dia.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: janelasHorario.map((janela) {
                return ChoiceChip(
                  label: Text(janela.label),
                  selected: _janelaEscolhida?.inicio == janela.inicio,
                  onSelected: (_) => setState(() => _janelaEscolhida = janela),
                );
              }).toList(),
            ),
        ],
      ],
    );
  }

  Widget _buildResumoEntrega() {
    if (_calculandoDistancia) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Calculando distância...'),
          ],
        ),
      );
    }

    if (_distanciaKm == null) {
      // O cliente CONTINUA selecionado aqui — só falta endereço válido pra
      // calcular a distância (comum em cadastro promovido do histórico
      // Kyte, que às vezes só tem nome+telefone, sem endereço nenhum).
      // Sem essa deixa clara, dava a impressão de que o cadastro "sumiu" e
      // levava a criar um duplicado — achado real 12/09 (Vanessa Souza:
      // pedido de R$119,90 foi parar num cadastro novo, separado dos 10
      // pedidos antigos dela, até eu mesclar de volta manualmente).
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Não foi possível calcular a distância até "${_clienteSelecionado?.nome}". '
              'O cadastro continua selecionado — só falta um endereço válido.',
              style: TextStyle(color: Colors.red[700]),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.edit_location_alt_outlined),
              label: const Text('Completar endereço do cliente'),
              onPressed: _editarEnderecoClienteSelecionado,
            ),
          ],
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Distância: ${_distanciaKm!.toStringAsFixed(1)} km'),
            if (_estimativaMin != null) Text('Tempo estimado: $_estimativaMin min'),
            TextButton.icon(
              onPressed: _abrirRotaNoGoogleMaps,
              icon: const Icon(Icons.map),
              label: const Text('Ver rota no Google Maps'),
            ),
            const Divider(),
            if (_zonaEncontrada == null)
              Text(
                'Nenhuma zona de entrega cadastrada cobre essa distância. '
                'Cadastre uma em Configurações > Opções de Entrega.',
                style: TextStyle(color: Colors.red[700]),
              )
            else ...[
              Text(
                'Zona: ${_zonaEncontrada!.nome}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Builder(builder: (context) {
                final freteGratis = _zonaEncontrada!.valorMinimoFreteGratis != null &&
                    widget.subtotal >= _zonaEncontrada!.valorMinimoFreteGratis!;
                return Text(
                  freteGratis
                      ? 'Frete grátis!'
                      : 'Valor da entrega: R\$ ${_zonaEncontrada!.valor.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: freteGratis ? Colors.green : null,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
