import 'package:flutter/material.dart';

class DescontoScreen extends StatefulWidget {
  final double valorTotal;
  final Function(double) onDescontoAplicado;

  DescontoScreen({required this.valorTotal, required this.onDescontoAplicado});

  @override
  _DescontoScreenState createState() => _DescontoScreenState();
}

class _DescontoScreenState extends State<DescontoScreen> {
  double descontoValor = 0.0;
  double descontoPercentual = 0.0;

  @override
  Widget build(BuildContext context) {
    double valorFinal = widget.valorTotal - descontoValor - (widget.valorTotal * (descontoPercentual / 100));

    return Scaffold(
      appBar: AppBar(
        title: Text('Aplicar Desconto'),
        actions: [
          IconButton(
            icon: Icon(Icons.clear),
            onPressed: () {
              setState(() {
                descontoValor = 0.0;
                descontoPercentual = 0.0;
              });
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(
                labelText: 'Desconto em Valor (R\$)',
                prefixText: 'R\$ ',
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: (value) {
                setState(() {
                  descontoValor = double.tryParse(value) ?? 0.0;
                });
              },
            ),
            TextField(
              decoration: InputDecoration(
                labelText: 'Desconto Percentual (%)',
                suffixText: '%',
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: (value) {
                setState(() {
                  descontoPercentual = double.tryParse(value) ?? 0.0;
                });
              },
            ),
            SizedBox(height: 20),
            Text(
              'Valor Final: R\$ ${valorFinal.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                widget.onDescontoAplicado(valorFinal);
                Navigator.pop(context);
              },
              child: Text('Aplicar Desconto'),
            ),
          ],
        ),
      ),
    );
  }
}
