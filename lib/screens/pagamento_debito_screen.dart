// pagamento_cartao_debito_screen.dart
import 'package:flutter/material.dart';

import 'conclusao_venda_screen.dart';

class PagamentoCartaoDebitoScreen extends StatefulWidget {
  final double valorTotal;

  PagamentoCartaoDebitoScreen({required this.valorTotal});

  @override
  _PagamentoCartaoDebitoScreenState createState() =>
      _PagamentoCartaoDebitoScreenState();
}

class _PagamentoCartaoDebitoScreenState
    extends State<PagamentoCartaoDebitoScreen> {
  TextEditingController _valorController = TextEditingController();
  double valorPago = 0.0;
  double valorFaltante = 0.0;

  void calcularValorFaltante() {
    double valor = double.tryParse(_valorController.text) ?? 0.0;
    setState(() {
      valorPago = valor;
      valorFaltante = widget.valorTotal - valorPago;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Pagamento: Cartão de Débito'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Text(
              'Valor Total: R\$ ${widget.valorTotal.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            SizedBox(height: 30),
            TextField(
              controller: _valorController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Valor do Pagamento',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                calcularValorFaltante();
              },
            ),
            SizedBox(height: 30),
            // Exibindo a diferença, se houver
            if (valorFaltante > 0)
              Text(
                'Faltando: R\$ ${valorFaltante.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                if (valorFaltante > 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Pagamento incompleto!')),
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        ConclusaoVendaScreen(valorTotal: widget.valorTotal),
                  ),
                );
              },
              child: Text('Concluir'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
                textStyle: TextStyle(fontSize: 18),
              ),
            ),
            // ElevatedButton(
            //   onPressed: valorFaltante > 0
            //       ? null // Desabilita o botão se ainda faltar valor
            //       : () {
            //     ScaffoldMessenger.of(context).showSnackBar(
            //       SnackBar(
            //         content: Text('Pagamento com Cartão de Débito realizado!'),
            //       ),
            //     );
            //     Navigator.pop(context);
            //   },
            //   child: Text(valorFaltante > 0
            //       ? 'Finalizar Pagamento' // Caso haja falta, o texto muda
            //       : 'Concluir'),
            //   style: ElevatedButton.styleFrom(
            //     minimumSize: Size(double.infinity, 50),
            //     textStyle: TextStyle(fontSize: 18),
            //   ),
            // ),
          ],
        ),
      ),
    );
  }
}
