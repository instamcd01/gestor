// import 'dart:convert';
// import 'dart:math';
// import 'package:flutter/material.dart';
// import 'package:gestor/screens/adicionar_cliente_screen.dart';
// import 'package:provider/provider.dart';
// import 'package:http/http.dart' as http;
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:url_launcher/url_launcher.dart';
//
// import '../models/cliente.dart';
// import '../providers/cliente_provider.dart';
// import 'gerenciar_entrega_screen.dart';
//
// class OpcaoEntregaScreen extends StatefulWidget {
//   final Map<String, Map<String, double>> opcoesEntrega;
//   final Function(String, double) onSelecionarEntrega;
//   final double subtotal;
//
//   OpcaoEntregaScreen({
//     required this.opcoesEntrega,
//     required this.onSelecionarEntrega,
//     required this.subtotal,
//   });
//
//   @override
//   _OpcaoEntregaScreenState createState() => _OpcaoEntregaScreenState();
// }
//
// class _OpcaoEntregaScreenState extends State<OpcaoEntregaScreen> {
//   final _enderecoLojaController = TextEditingController(text: "Rua Antonio Jacinto de Oliveira, 2 - Campo Grande, Rio de Janeiro, RJ");
//   final _enderecoClienteController = TextEditingController();
//
//   Cliente? clienteSelecionado;
//   String tipoEntrega = 'Frete grátis';
//   String entregaSelecionada = '0-2km';
//   double valorFrete = 0.0;
//   double? distanciaKm;
//   bool temFreteGratis = false;
//   String? tempoEstimado;
//   LatLng? lojaLatLng;
//   LatLng? clienteLatLng;
//   GoogleMapController? _mapController;
//
//   @override
//   void initState() {
//     super.initState();
//     _carregarDadosIniciais();
//   }
//
//   Future<void> _carregarDadosIniciais() async {
//     final cliente = Provider.of<ClientProvider>(context, listen: false).clienteSelecionado;
//     if (cliente != null && cliente.endereco.isNotEmpty) {
//       setState(() {
//         clienteSelecionado = cliente;
//         _enderecoClienteController.text = cliente.endereco;
//       });
//     }
//     await _calcularDistanciaEAtualizarFrete();
//   }
//
//   Future<void> _calcularDistanciaEAtualizarFrete() async {
//     final origem = _enderecoLojaController.text;
//     final destino = _enderecoClienteController.text;
//
//     if (origem.isEmpty || destino.isEmpty) return;
//
//     final geoKey = 'AIzaSyDAZwBuEKJ5PkDR4N-Lp_a4yrDRY9zFav0';
//     try {
//       final geoOrigem = await http.get(Uri.parse(
//           'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(origem)}&key=$geoKey'));
//       final geoDestino = await http.get(Uri.parse(
//           'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(destino)}&key=$geoKey'));
//
//       final origemJson = json.decode(geoOrigem.body);
//       final destinoJson = json.decode(geoDestino.body);
//
//       if (origemJson['status'] != 'OK' || destinoJson['status'] != 'OK') {
//         _showSnack('Erro ao buscar localização');
//         return;
//       }
//
//       final origemLoc = origemJson['results'][0]['geometry']['location'];
//       final destinoLoc = destinoJson['results'][0]['geometry']['location'];
//       lojaLatLng = LatLng(origemLoc['lat'], origemLoc['lng']);
//       clienteLatLng = LatLng(destinoLoc['lat'], destinoLoc['lng']);
//
//       final distUrl = Uri.parse(
//           'https://maps.googleapis.com/maps/api/distancematrix/json?origins=${origemLoc['lat']},${origemLoc['lng']}&destinations=${destinoLoc['lat']},${destinoLoc['lng']}&mode=motorcycle&key=$geoKey&units=metric');
//       final distRes = await http.get(distUrl);
//       final distJson = json.decode(distRes.body);
//
//       if (distJson['status'] != 'OK') {
//         _showSnack('Erro ao calcular distância');
//         return;
//       }
//
//       final distMeters = distJson['rows'][0]['elements'][0]['distance']['value'];
//       final element = distJson['rows'][0]['elements'][0];
//      final durationText = element['duration']['text'];
//       final distKm = distMeters / 1000.0;
//
//       setState(() {
//         distanciaKm = distKm;
//         tempoEstimado = durationText;
//         entregaSelecionada = _faixaParaDistancia(distKm);
//         _verificarFreteGratis();
//         widget.onSelecionarEntrega(entregaSelecionada, valorFrete);
//         _moveCamera();
//       });
//     } catch (e) {
//       _showSnack('Erro ao calcular rota: $e');
//     }
//   }
//
//   void _abrirRotaNoGoogleMaps() async {
//     if (lojaLatLng == null || clienteLatLng == null) return;
//     final url = 'https://www.google.com/maps/dir/?api=1&origin=${lojaLatLng!.latitude},${lojaLatLng!.longitude}&destination=${clienteLatLng!.latitude},${clienteLatLng!.longitude}&travelmode=driving';
//     if (await canLaunchUrl(Uri.parse(url))) {
//       await launchUrl(Uri.parse(url));
//     } else {
//       _showSnack('Não foi possível abrir o Google Maps');
//     }
//   }
//
//   void _showSnack(String msg) {
//     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
//   }
//
//   String _faixaParaDistancia(double km) {
//     if (km <= 2) return '0-2km';
//     if (km <= 5) return '2-5km';
//     if (km <= 7) return '5-7km';
//     if (km <= 10) return '7-10km';
//     if (km <= 13) return '10-13km';
//     if (km <= 15) return '13-15km';
//     if (km <= 17) return '15-17km';
//     if (km <= 20) return '17-20km';
//     if (km <= 25) return '20-25km';
//     return '25-30km';
//   }
//
//   void _verificarFreteGratis() {
//     final minimoGratis = widget.opcoesEntrega['Frete grátis']![entregaSelecionada] ?? 9999.0;
//     temFreteGratis = widget.subtotal >= minimoGratis;
//     valorFrete = temFreteGratis
//         ? 0.0
//         : widget.opcoesEntrega['Entrega paga']![entregaSelecionada]!;
//   }
//
//   void _moveCamera() {
//     if (_mapController == null || lojaLatLng == null || clienteLatLng == null) return;
//     final bounds = LatLngBounds(
//       southwest: LatLng(
//         min(lojaLatLng!.latitude, clienteLatLng!.latitude),
//         min(lojaLatLng!.longitude, clienteLatLng!.longitude),
//       ),
//       northeast: LatLng(
//         max(lojaLatLng!.latitude, clienteLatLng!.latitude),
//         max(lojaLatLng!.longitude, clienteLatLng!.longitude),
//       ),
//     );
//     _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final clienteProvider = Provider.of<ClientProvider>(context);
//     final markers = <Marker>{};
//
//     if (lojaLatLng != null) {
//       markers.add(Marker(
//         markerId: MarkerId('loja'),
//         position: lojaLatLng!,
//         infoWindow: InfoWindow(title: 'Loja'),
//       ));
//     }
//     if (clienteLatLng != null) {
//       markers.add(Marker(
//         markerId: MarkerId('cliente'),
//         position: clienteLatLng!,
//         infoWindow: InfoWindow(title: 'Cliente'),
//         icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
//       ));
//     }
//
//     return Scaffold(
//       appBar: AppBar(title: Text('Entrega')),
//       body: SingleChildScrollView(
//         child: Padding(
//           padding: const EdgeInsets.all(16.0),
//           child: Column(
//             children: [
//               DropdownButtonFormField<Cliente>(
//                 value: clienteSelecionado,
//                 hint: Text('Selecione um cliente'),
//                 onChanged: (cliente) {
//                   setState(() {
//                     clienteSelecionado = cliente;
//                     _enderecoClienteController.text = cliente?.endereco ?? '';
//                     _calcularDistanciaEAtualizarFrete();
//                   });
//                 },
//                 items: clienteProvider.clientes.map((cliente) {
//                   return DropdownMenuItem(
//                     value: cliente,
//                     child: Text(cliente.nome),
//                   );
//                 }).toList(),
//               ),
//               Align(
//                 alignment: Alignment.centerRight,
//                 child: TextButton(
//                   onPressed: () async {
//                     await Navigator.push(
//                       context,
//                       MaterialPageRoute(builder: (_) => AdicionarClienteScreen(onSalvar: (Cliente c) {})),
//                     );
//                     setState(() {});
//                   },
//                   child: Text('Cadastrar novo cliente'),
//                 ),
//               ),
//               TextFormField(
//                 controller: _enderecoLojaController,
//                 decoration: InputDecoration(labelText: 'Endereço da Loja'),
//                 onChanged: (_) => _calcularDistanciaEAtualizarFrete(),
//               ),
//               TextFormField(
//                 controller: _enderecoClienteController,
//                 decoration: InputDecoration(labelText: 'Endereço do Cliente'),
//                 onChanged: (_) => _calcularDistanciaEAtualizarFrete(),
//               ),
//               SizedBox(height: 10),
//               Container(
//                 height: 400,
//                 child: GoogleMap(
//                   initialCameraPosition: CameraPosition(
//                     target: LatLng(-22.9, -43.18),
//                     zoom: 13,
//                   ),
//                   markers: markers,
//                   onMapCreated: (ctrl) => _mapController = ctrl,
//                 ),
//               ),
//               SizedBox(height: 10),
//             if (distanciaKm != null && tempoEstimado != null) ...[
//       Card(
//       margin: EdgeInsets.symmetric(vertical: 10),
//       elevation: 2,
//       child: Padding(
//         padding: const EdgeInsets.all(12.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Text('Distância: ${distanciaKm!.toStringAsFixed(2)} km'),
//             Text('Tempo estimado: $tempoEstimado'),
//           ],
//         ),
//       ),
//     ),
//               DropdownButton<String>(
//                 value: entregaSelecionada,
//                 onChanged: (v) {
//                   setState(() {
//                     entregaSelecionada = v!;
//                     _verificarFreteGratis();
//                     widget.onSelecionarEntrega(entregaSelecionada, valorFrete);
//                   });
//                 },
//                 items: widget.opcoesEntrega[tipoEntrega]!
//                     .keys
//                     .map((e) => DropdownMenuItem(value: e, child: Text(e)))
//                     .toList(),
//               ),
//               Text(
//                 temFreteGratis
//                     ? 'Frete grátis para esta distância!'
//                     : 'Custo de entrega: R\$ ${valorFrete.toStringAsFixed(2)}',
//                 style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//               ),
//               SizedBox(height: 10),
//               ElevatedButton(
//                 onPressed: _abrirRotaNoGoogleMaps,
//                 child: Text('Abrir no Google Maps'),
//               ),
//               ElevatedButton(
//                 onPressed: () => Navigator.push(
//                   context,
//                   MaterialPageRoute(
//                     builder: (_) => GerenciarEntregaScreen(
//                       opcoesEntrega: widget.opcoesEntrega,
//                       onSalvarOpcoesEntrega: (novasOpcoes) {
//                         setState(() => widget.opcoesEntrega.clear());
//                         widget.opcoesEntrega.addAll(novasOpcoes);
//                       },
//                     ),
//                   ),
//                 ),
//                 child: Text('Editar Opções de Entrega'),
//               ),
//               ElevatedButton(
//                 onPressed: () {
//                   if (clienteSelecionado != null && entregaSelecionada != null) {
//                     Navigator.pop(context, {
//                       'cliente': clienteSelecionado,
//                     });
//                   }
//                 },
//                 child: Text('Confirmar Entrega'),
//               )
//             ],
//           ]),
//         ),
//       ),
//     );
//   }
// }

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:gestor/screens/adicionar_cliente_screen.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../models/cliente.dart';
import '../providers/cliente_provider.dart';
import 'gerenciar_entrega_screen.dart';

class OpcaoEntregaScreen extends StatefulWidget {
  final Map<String, Map<String, double>> opcoesEntrega;
  final Function(String, double) onSelecionarEntrega;
  final double subtotal;

  OpcaoEntregaScreen({
    required this.opcoesEntrega,
    required this.onSelecionarEntrega,
    required this.subtotal,
  });

  @override
  _OpcaoEntregaScreenState createState() => _OpcaoEntregaScreenState();
}

class _OpcaoEntregaScreenState extends State<OpcaoEntregaScreen> {
  final _enderecoLojaController = TextEditingController(
      text: "Rua Antonio Jacinto de Oliveira, 2 - Campo Grande, Rio de Janeiro, RJ");
  final _enderecoClienteController = TextEditingController();
  final _buscaClienteController = TextEditingController();
  Cliente? clienteSelecionado;
  String tipoEntrega = 'Frete grátis';
  String entregaSelecionada = '0-2km';
  double valorFrete = 0.0;
  double? distanciaKm;
  bool temFreteGratis = false;
  String? tempoEstimado;
  String? prazoEstimadoFaixa;
  List<Cliente> _clientesFiltrados = [];
  bool _carregandoDistancia = false;

  @override
  void initState() {
    super.initState();
    _carregarDadosIniciais();
  }

  Future<void> _carregarDadosIniciais() async {
    final cliente =
        Provider.of<ClientProvider>(context, listen: false).clienteSelecionado;

    if (cliente != null && cliente.endereco.isNotEmpty) {
      setState(() {
        clienteSelecionado = cliente;
        _enderecoClienteController.text = cliente.endereco;

        // Preenche automaticamente a faixa de entrega e distância
        if (cliente.rangeDistancia != null) {
          entregaSelecionada = _faixaParaDistancia(cliente.rangeDistancia!);
          distanciaKm = cliente.rangeDistancia;
        }

        // Preenche estimativa de entrega
        if (cliente.estimativaEntrega != null) {
          tempoEstimado = '${cliente.estimativaEntrega} min';
        }

        // Calcula o prazo estimado da faixa
        prazoEstimadoFaixa = _prazoPorFaixa(entregaSelecionada);

        _verificarFreteGratis();
        widget.onSelecionarEntrega(entregaSelecionada, valorFrete);
           });
    } else {
      await _calcularDistanciaEAtualizarFrete();
      // LOGS
      print('=== _calcularDistanciaEAtualizarFrete ===');
      print('Distância calculada: $distanciaKm km');
      print('Entrega selecionada: $entregaSelecionada');
      print('Valor do frete: $valorFrete');
      print('Tempo estimado: $tempoEstimado');
      print('Prazo faixa: $prazoEstimadoFaixa');
    }
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371; // raio da Terra em km
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  Future<void> _calcularDistanciaEAtualizarFrete() async {
    final origem = _enderecoLojaController.text;
    final destino = _enderecoClienteController.text;

    if (origem.isEmpty || destino.isEmpty) return;
    setState(() => _carregandoDistancia = true);
    final geoKey = 'SUA_API_KEY_AQUI'; // Geocoding API
    try {
      final geoOrigem = await http.get(Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(origem)}&key=$geoKey'));
      final geoDestino = await http.get(Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(destino)}&key=$geoKey'));

      final origemJson = json.decode(geoOrigem.body);
      final destinoJson = json.decode(geoDestino.body);

      if (origemJson['status'] != 'OK' || destinoJson['status'] != 'OK') {
        _showSnack('Erro ao buscar localização');
        return;
      }

      final origemLoc = origemJson['results'][0]['geometry']['location'];
      final destinoLoc = destinoJson['results'][0]['geometry']['location'];

      final lat1 = origemLoc['lat'];
      final lon1 = origemLoc['lng'];
      final lat2 = destinoLoc['lat'];
      final lon2 = destinoLoc['lng'];

      final distKm = _haversine(lat1, lon1, lat2, lon2);
      final tempoMin = (distKm / 40) * 60; // 40 km/h
      final durationText = "${tempoMin.toStringAsFixed(0)} min";

      setState(() {
        distanciaKm = distKm;
        tempoEstimado = durationText;

        // Mantém tempo real se houver entrega expressa
        if (tempoEstimado == null) tempoEstimado = durationText;

        entregaSelecionada = _faixaParaDistancia(distKm);
        prazoEstimadoFaixa = _prazoPorFaixa(entregaSelecionada);

        _verificarFreteGratis();
        widget.onSelecionarEntrega(entregaSelecionada, valorFrete);
      });
    } catch (e) {
      _showSnack('Erro ao calcular rota: $e');
    }
  }

  void _abrirRotaNoGoogleMaps() async {
    final origem = Uri.encodeComponent(_enderecoLojaController.text);
    final destino = Uri.encodeComponent(_enderecoClienteController.text);
    final url =
        'https://www.google.com/maps/dir/?api=1&origin=$origem&destination=$destino&travelmode=driving';

    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      _showSnack('Não foi possível abrir o Google Maps');
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _faixaParaDistancia(double km) {
    if (km <= 2) return '0-2km';
    if (km <= 5) return '2-5km';
    if (km <= 7) return '5-7km';
    if (km <= 10) return '7-10km';
    if (km <= 13) return '10-13km';
    if (km <= 15) return '13-15km';
    if (km <= 17) return '15-17km';
    if (km <= 20) return '17-20km';
    if (km <= 25) return '20-25km';
    return '25-30km';
  }

  String _formatarTempo(int minutos) {
    if (minutos < 60) return '$minutos min';
    final h = minutos ~/ 60;
    final m = minutos % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m}min';
  }

  String _prazoPorFaixa(String faixa) {
    final Map<String, int> inicio = {
      '0-2km': 20,
      '2-5km': 30,
      '5-7km': 40,
      '7-10km': 50,
      '10-13km': 60,
      '13-15km': 70,
      '15-17km': 80,
      '17-20km': 90,
      '20-25km': 100,
      '25-30km': 110,
    };
    final Map<String, int> fim = {
      '0-2km': 40,
      '2-5km': 50,
      '5-7km': 60,
      '7-10km': 70,
      '10-13km': 80,
      '13-15km': 90,
      '15-17km': 100,
      '17-20km': 110,
      '20-25km': 120,
      '25-30km': 130,
    };

    int start = inicio[faixa] ?? 0;
    int end = fim[faixa] ?? 0;

    return '${_formatarTempo(start)} - ${_formatarTempo(end)}';
  }

  void _verificarFreteGratis() {
    final minimoGratis =
        widget.opcoesEntrega['Frete grátis']![entregaSelecionada] ?? 9999.0;
    temFreteGratis = widget.subtotal >= minimoGratis;
    valorFrete = temFreteGratis
        ? 0.0
        : widget.opcoesEntrega['Entrega paga']![entregaSelecionada]!;
  }
  void _filtrarClientes(String texto, List<Cliente> todosClientes) {
    setState(() {
      _clientesFiltrados = todosClientes
          .where((c) =>
      c.nome.toLowerCase().contains(texto.toLowerCase()) ||
          c.celular.toLowerCase().contains(texto.toLowerCase()) ||
          c.endereco.toLowerCase().contains(texto.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final clienteProvider = Provider.of<ClientProvider>(context);
    final todosClientes = clienteProvider.clientes;
    final clientesParaMostrar =
    _buscaClienteController.text.isEmpty && _clientesFiltrados.isEmpty
        ? todosClientes.take(5).toList()
        : _clientesFiltrados;


    return Scaffold(
      appBar: AppBar(title: Text('Entrega')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(children: [
            TextField(
              controller: _buscaClienteController,
              decoration: InputDecoration(
                labelText: 'Buscar cliente (nome, celular ou endereço)',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (texto) => _filtrarClientes(texto, todosClientes),
            ),
            const SizedBox(height: 8),

            // 🔽 LISTA DE CLIENTES FILTRADOS
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: clientesParaMostrar.length,
              itemBuilder: (context, index) {
                final cliente = clientesParaMostrar[index];
                return ListTile(
                  title: Text(cliente.nome),
                  subtitle: Text(cliente.celular),
                  trailing: Icon(Icons.person),
                  onTap: () async {
                    setState(() {
                      clienteSelecionado = cliente;
                      _buscaClienteController.text = cliente.nome;
                      _enderecoClienteController.text = cliente.endereco;
                      _clientesFiltrados.clear();
                    });

                    if (cliente.rangeDistancia != null) {
                      entregaSelecionada =
                          _faixaParaDistancia(cliente.rangeDistancia!);
                      distanciaKm = cliente.rangeDistancia;
                    }
                    if (cliente.estimativaEntrega != null) {
                      tempoEstimado = '${cliente.estimativaEntrega} min';
                    }

                    prazoEstimadoFaixa = _prazoPorFaixa(entregaSelecionada);
                    _verificarFreteGratis();
                    widget.onSelecionarEntrega(entregaSelecionada, valorFrete);
                  },
                );
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            AdicionarClienteScreen(onSalvar: (Cliente c) {})),
                  );
                  setState(() {});
                },
                child: Text('Cadastrar novo cliente'),
              ),
            ),
            TextFormField(
              controller: _enderecoLojaController,
              decoration: InputDecoration(labelText: 'Endereço da Loja'),
              onChanged: (_) => _calcularDistanciaEAtualizarFrete(),
            ),
            TextFormField(
              controller: _enderecoClienteController,
              decoration: InputDecoration(labelText: 'Endereço do Cliente'),
              onChanged: (_) => _calcularDistanciaEAtualizarFrete(),
            ),
            SizedBox(height: 10),
            if (distanciaKm != null && tempoEstimado != null) ...[
              Card(
                margin: EdgeInsets.symmetric(vertical: 10),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Distância: ${distanciaKm!.toStringAsFixed(2)} km'),
                      Text('Estimativa de entrega real: $tempoEstimado'),
                      if (prazoEstimadoFaixa != null)
                        Text('Prazo por faixa: $prazoEstimadoFaixa'),
                    ],
                  ),
                ),
              ),
            ],
            DropdownButton<String>(
              value: entregaSelecionada,
              onChanged: (v) {
                setState(() {
                  entregaSelecionada = v!;
                  prazoEstimadoFaixa = _prazoPorFaixa(entregaSelecionada);
                  _verificarFreteGratis();
                  widget.onSelecionarEntrega(entregaSelecionada, valorFrete);
                });
              },
              items: widget.opcoesEntrega[tipoEntrega]!
                  .keys
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
            ),
            Text(
              temFreteGratis
                  ? 'Frete grátis para esta distância!'
                  : 'Custo de entrega: R\$ ${valorFrete.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: _abrirRotaNoGoogleMaps,
              child: Text('Abrir no Google Maps'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GerenciarEntregaScreen(
                    opcoesEntrega: widget.opcoesEntrega,
                    onSalvarOpcoesEntrega: (novasOpcoes) {
                      setState(() => widget.opcoesEntrega.clear());
                      widget.opcoesEntrega.addAll(novasOpcoes);
                    },
                  ),
                ),
              ),
              child: Text('Editar Opções de Entrega'),
            ),
            ElevatedButton(
              onPressed: () {
                if (clienteSelecionado != null && entregaSelecionada != null) {
                  final dadosEntrega = {
                    'cliente': clienteSelecionado,
                    'entregaSelecionada': entregaSelecionada,
                    'valorFrete': valorFrete,
                    'temFreteGratis': temFreteGratis,
                    'distanciaKm': distanciaKm,
                    'prazoEstimadoFaixa': prazoEstimadoFaixa,
                    'tempoEstimado': tempoEstimado,
                  };

                  // LOG no console para ver todos os dados
                  print('🔹 Dados que serão passados da tela de entrega: $dadosEntrega');
                  Navigator.pop(context, {
                    'cliente': clienteSelecionado,
                  });
                }
              },
              child: Text('Confirmar Entrega'),
            )
          ]),
        ),
      ),
    );
  }
}
