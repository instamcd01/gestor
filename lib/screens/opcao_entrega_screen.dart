import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/cliente.dart';
import '../models/zona_entrega.dart';
import '../providers/auth_provider.dart';
import '../providers/cliente_provider.dart';
import '../providers/zona_entrega_provider.dart';
import '../repositories/cliente_repository.dart';
import '../services/distancia_service.dart';
import 'adicionar_cliente_screen.dart';
import 'configuracao_entrega_screen.dart';

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

  bool _retirarNaLoja = false;
  double? _distanciaKm;
  int? _estimativaMin;
  bool _calculandoDistancia = false;
  ZonaEntrega? _zonaEncontrada;

  @override
  void initState() {
    super.initState();
    _carregarClientes();
  }

  @override
  void dispose() {
    _buscaClienteController.dispose();
    super.dispose();
  }

  Future<void> _carregarClientes() async {
    await Provider.of<ClientProvider>(context, listen: false).carregarClientes();
    if (!mounted) return;
    setState(() => _carregandoClientes = false);

    final clienteJaSelecionado =
        Provider.of<ClientProvider>(context, listen: false).clienteSelecionado;
    if (clienteJaSelecionado != null) {
      _selecionarCliente(clienteJaSelecionado);
    }
  }

  void _filtrarClientes(String texto, List<Cliente> todosClientes) {
    setState(() {
      _clientesFiltrados = todosClientes
          .where((c) =>
              c.nome.toLowerCase().contains(texto.toLowerCase()) ||
              c.celular.toLowerCase().contains(texto.toLowerCase()) ||
              c.enderecoCompleto.toLowerCase().contains(texto.toLowerCase()))
          .toList();
    });
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

  void _resolverZona() {
    if (_distanciaKm == null) return;
    final zona = context.read<ZonaEntregaProvider>().zonaParaDistancia(_distanciaKm!);
    setState(() => _zonaEncontrada = zona);
  }

  void _abrirRotaNoGoogleMaps() async {
    if (_clienteSelecionado == null) return;
    final destino = Uri.encodeComponent(_clienteSelecionado!.enderecoCompleto);
    final url = 'https://www.google.com/maps/dir/?api=1&destination=$destino&travelmode=driving';
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
    if (_retirarNaLoja) return true;
    return _zonaEncontrada != null;
  }

  void _confirmar() {
    if (!_podeConfirmar) return;
    Navigator.pop(context, {
      'cliente': _clienteSelecionado,
      'zona': _retirarNaLoja ? null : _zonaEncontrada,
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
                          ? cliente.enderecoCompleto
                          : cliente.celular),
                      trailing: const Icon(Icons.person),
                      selected: _clienteSelecionado?.idCliente == cliente.idCliente,
                      onTap: () => _selecionarCliente(cliente),
                    );
                  },
                ),

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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Não foi possível calcular a distância até esse cliente. '
          'Confira o endereço cadastrado dele.',
          style: TextStyle(color: Colors.red[700]),
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
