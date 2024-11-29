import 'package:flutter/material.dart';

import 'gerenciar_entrega_screen.dart';

class OpcaoEntregaScreen extends StatefulWidget {
  final Map<String, Map<String, double>> opcoesEntrega;
  final Function(String, double) onSelecionarEntrega;
  final double subtotal;  // Recebe o subtotal da compra

  OpcaoEntregaScreen({
    required this.opcoesEntrega,
    required this.onSelecionarEntrega,
    required this.subtotal,  // Passa o subtotal para verificar o frete grátis
  });

  @override
  _OpcaoEntregaScreenState createState() => _OpcaoEntregaScreenState();
}

Map<String, Map<String, double>> opcoesEntrega = {
  'Frete grátis': {
    '0-2km': 0.0,
    '2-5km': 50.0,
    '5-7km': 70.0,
    '10-13km': 120.0,
    '13-15km': 150.0,
    '15-17km': 170.0,
    '17-20km': 200.0,
    '20-25km': 250.0,
    '25-30km': 300.0,
  },
  'Entrega paga': {
    '0-2km': 0.0,
    '2-5km': 4.99,
    '0-5km': 4.99,
    '5-7km': 7.99,
    '10-13km': 12.99,
    '13-15km': 14.99,
    '15-17km': 16.99,
    '17-20km': 19.99,
    '20-25km': 24.99,
    '25-30km': 29.99,
  },
};

class _OpcaoEntregaScreenState extends State<OpcaoEntregaScreen> {
  String tipoEntrega = 'Frete grátis'; // Tipo inicial (frete grátis ou pago)
  String entregaSelecionada = '0-2km';  // Distância inicial
  double valorFrete = 0.0;
  bool temFreteGratis = false;

  @override
  void initState() {
    super.initState();
    _verificarFreteGratis();
  }

  void _verificarFreteGratis() {
    // Verifica se o subtotal atinge o valor mínimo para frete grátis na distância selecionada
    double valorMinimo = widget.opcoesEntrega['Frete grátis']![entregaSelecionada] ?? 0.0;
    temFreteGratis = widget.subtotal >= valorMinimo;
    valorFrete = temFreteGratis ? 0.0 : widget.opcoesEntrega['Entrega paga']![entregaSelecionada]!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Opção de Entrega'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Seletor de Distância
            DropdownButton<String>(
              value: entregaSelecionada,
              onChanged: (String? newValue) {
                setState(() {
                  entregaSelecionada = newValue!;
                  _verificarFreteGratis();  // Atualiza o frete após selecionar a distância
                });
                widget.onSelecionarEntrega(entregaSelecionada, valorFrete);
              },
              items: widget.opcoesEntrega[tipoEntrega]!.keys.map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
            ),
            SizedBox(height: 20),
            // Exibe a mensagem de frete grátis ou o valor da taxa de entrega
            Text(
              temFreteGratis
                  ? 'Você tem Frete Grátis!'
                  : 'Taxa de entrega: R\$ ${valorFrete.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GerenciarEntregaScreen(
                      opcoesEntrega: opcoesEntrega,
                      onSalvarOpcoesEntrega: (novasOpcoes) {
                        setState(() {
                          opcoesEntrega = novasOpcoes;
                        });
                      },
                    ),
                  ),
                );
              },
              child: Text('Gerenciar Opções de Entrega'),
            ),
            ElevatedButton(
              onPressed: () {
                // Volta para a tela anterior com a entrega selecionada
                Navigator.pop(context);
              },
              child: Text('Confirmar Entrega'),
            ),
          ],
        ),
      ),
    );
  }
}
