import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pedido_provider.dart';
import 'conclusao_venda_screen.dart'; // Importar a nova tela

class PagamentoDinheiroScreen extends StatefulWidget {
  final double valorTotal;
  final List<Map<String, dynamic>> carrinho;
  PagamentoDinheiroScreen({required this.valorTotal, required this.carrinho});

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

  void concluirPagamento(BuildContext context) {
    final pedidoProvider = Provider.of<PedidoProvider>(context, listen: false);
    pedidoProvider.adicionarPedido(
      Pedido(
        codigo: DateTime.now().millisecondsSinceEpoch.toString(),
        cliente: 'Cliente Padrão', // Substituir pelo nome do cliente real
        valor: widget.valorTotal,
        status: 'Concluído',
        vendedor: 'Loja A', // Substituir pela loja ou vendedor real
      ),
    );

    // Navegar para a tela de pedidos
    // Navigator.pushReplacementNamed(context, '/historico_vendas');
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
            ElevatedButton(
              onPressed: () {
                if (_valorFaltando > 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Pagamento incompleto!')),
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        ConclusaoVendaScreen(valorTotal: widget.valorTotal,carrinho: widget.carrinho,),
                  ),
                );
                concluirPagamento(context);
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
