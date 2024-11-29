import 'package:flutter/material.dart';

class PagamentoDinheiroScreen extends StatefulWidget {
  final double valorTotal;

  PagamentoDinheiroScreen({required this.valorTotal});

  @override
  _PagamentoDinheiroScreenState createState() =>
      _PagamentoDinheiroScreenState();
}

class _PagamentoDinheiroScreenState extends State<PagamentoDinheiroScreen> {
  TextEditingController _valorRecebidoController = TextEditingController();
  double _troco = 0.0;
  double _valorFaltando = 0.0;

  @override
  void dispose() {
    _valorRecebidoController.dispose();
    super.dispose();
  }

  void calcularTrocoOuFalta() {
    double valorRecebido = double.tryParse(_valorRecebidoController.text) ?? 0.0;
    if (valorRecebido > widget.valorTotal) {
      setState(() {
        _troco = valorRecebido - widget.valorTotal;
        _valorFaltando = 0.0;
      });
    } else {
      setState(() {
        _valorFaltando = widget.valorTotal - valorRecebido;
        _troco = 0.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Pagamento: Dinheiro'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            // Valor total do carrinho
            Text(
              'Valor Total: R\$ ${widget.valorTotal.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            SizedBox(height: 30),
            // Campo para o valor recebido
            TextField(
              controller: _valorRecebidoController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Valor Recebido',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                calcularTrocoOuFalta();
              },
            ),
            SizedBox(height: 20),
            // Exibindo o troco ou o valor que falta
            if (_troco > 0)
              Text(
                'Troco: R\$ ${_troco.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.green,
                ),
              ),
            if (_valorFaltando > 0)
              Text(
                'Falta: R\$ ${_valorFaltando.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.red,
                ),
              ),
            SizedBox(height: 30),
            // Botão para concluir o pagamento
            ElevatedButton(
              onPressed: () {
                // Implementar lógica de conclusão, pode ser uma navegação ou outra ação
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Pagamento concluído!'),
                  ),
                );
                Navigator.pop(context);  // Voltar para a tela anterior após o pagamento
              },
              child: Text('Concluir'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
                textStyle: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
