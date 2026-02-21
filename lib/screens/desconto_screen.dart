// import 'package:flutter/material.dart';
//
// class DescontoScreen extends StatefulWidget {
//   final double valorTotal;
//   // final Function(double) onDescontoAplicado;
//
//   DescontoScreen({required this.valorTotal,
//     // required this.onDescontoAplicado
//   });
//
//
//   @override
//   _DescontoScreenState createState() => _DescontoScreenState();
// }
//
// class _DescontoScreenState extends State<DescontoScreen> {
//   double descontoValor = 0.0;
//   double descontoPercentual = 0.0;
//
//   @override
//   Widget build(BuildContext context) {
//     double valorFinal = widget.valorTotal - descontoValor - (widget.valorTotal * (descontoPercentual / 100));
//     valorFinal = valorFinal < 0 ? 0.0 : valorFinal;
//
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Aplicar Desconto'),
//         actions: [
//           IconButton(
//             icon: Icon(Icons.clear),
//             onPressed: () {
//               setState(() {
//                 descontoValor = 0.0;
//                 descontoPercentual = 0.0;
//               });
//             },
//           ),
//         ],
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           children: [
//             TextField(
//               decoration: InputDecoration(
//                 labelText: 'Desconto em Valor (R\$)',
//                 prefixText: 'R\$ ',
//               ),
//               keyboardType: TextInputType.numberWithOptions(decimal: true),
//               onChanged: (value) {
//                 setState(() {
//                   descontoValor = double.tryParse(value) ?? 0.0;
//                 });
//               },
//             ),
//             TextField(
//               decoration: InputDecoration(
//                 labelText: 'Desconto Percentual (%)',
//                 suffixText: '%',
//               ),
//               keyboardType: TextInputType.numberWithOptions(decimal: true),
//               onChanged: (value) {
//                 setState(() {
//                   descontoPercentual = double.tryParse(value) ?? 0.0;
//                 });
//               },
//             ),
//             SizedBox(height: 20),
//             Text(
//               'Valor Final: R\$ ${valorFinal.toStringAsFixed(2)}',
//               style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
//             ),
//             SizedBox(height: 20),
//             ElevatedButton(
//               onPressed: () {
//                 // widget.onDescontoAplicado(valorFinal);
//                 Navigator.pop(context, valorFinal);
//               },
//               child: Text('Aplicar Desconto'),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }




import 'package:flutter/material.dart';

class DescontoScreen extends StatefulWidget {
  final double valorTotal;

  DescontoScreen({required this.valorTotal});

  @override
  _DescontoScreenState createState() => _DescontoScreenState();
}

class _DescontoScreenState extends State<DescontoScreen> {
  double descontoValor = 0.0;
  double descontoPercentual = 0.0;

  final TextEditingController _valorController = TextEditingController();
  final TextEditingController _percentualController = TextEditingController();

  bool _atualizando = false; // Para evitar loop de atualização

  @override
  void dispose() {
    _valorController.dispose();
    _percentualController.dispose();
    super.dispose();
  }

  void _atualizarValor(String value) {
    if (_atualizando) return;
    _atualizando = true;

    setState(() {
      descontoValor = double.tryParse(value) ?? 0.0;
      if (descontoValor > widget.valorTotal) descontoValor = widget.valorTotal;

      // Atualiza percentual
      descontoPercentual = widget.valorTotal == 0 ? 0 : (descontoValor / widget.valorTotal) * 100;
      _percentualController.text = descontoPercentual.toStringAsFixed(2);
    });

    _atualizando = false;
  }

  void _atualizarPercentual(String value) {
    if (_atualizando) return;
    _atualizando = true;

    setState(() {
      descontoPercentual = double.tryParse(value) ?? 0.0;
      if (descontoPercentual > 100) descontoPercentual = 100;

      // Atualiza valor
      descontoValor = (descontoPercentual / 100) * widget.valorTotal;
      _valorController.text = descontoValor.toStringAsFixed(2);
    });

    _atualizando = false;
  }

  double get valorFinal {
    double finalValue = widget.valorTotal - descontoValor;
    if (finalValue < 0) finalValue = 0.0;
    return finalValue;
  }

  void resetar() {
    setState(() {
      descontoValor = 0.0;
      descontoPercentual = 0.0;
      _valorController.clear();
      _percentualController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Aplicar Desconto'),
        actions: [
          IconButton(
            icon: Icon(Icons.clear),
            onPressed: resetar,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _valorController,
              decoration: InputDecoration(
                labelText: 'Desconto em Valor (R\$)',
                prefixText: 'R\$ ',
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: _atualizarValor,
            ),
            SizedBox(height: 10),
            TextField(
              controller: _percentualController,
              decoration: InputDecoration(
                labelText: 'Desconto Percentual (%)',
                suffixText: '%',
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: _atualizarPercentual,
            ),
            SizedBox(height: 20),
            Text(
              'Valor Final: R\$ ${valorFinal.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, valorFinal); // retorna o valor do desconto
              },
              child: Text('Aplicar Desconto'),
            ),
          ],
        ),
      ),
    );
  }
}
