// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import '../models/cliente.dart';
// import '../providers/pedido_provider.dart';
// import 'conclusao_venda_screen.dart'; // Importar a nova tela
//
// class PagamentoDinheiroScreen extends StatefulWidget {
//   final double valorTotal;
//   final List<Map<String, dynamic>> carrinho;
//   final String? idCliente; // PARÂMETRO ADICIONADO/VERIFICADO
//   final String metodoPagamento;
//   final Cliente cliente;
//   PagamentoDinheiroScreen({required this.valorTotal, required this.carrinho, this.idCliente, required this.metodoPagamento,required this.cliente});
//
//   @override
//   _PagamentoDinheiroScreenState createState() =>
//       _PagamentoDinheiroScreenState();
// }
//
// class _PagamentoDinheiroScreenState extends State<PagamentoDinheiroScreen> {
//   TextEditingController _valorRecebidoController = TextEditingController();
//   double _troco = 0.0;
//   double _valorFaltando = 0.0;
//
//   @override
//   void dispose() {
//     _valorRecebidoController.dispose();
//     super.dispose();
//   }
//
//   void calcularTrocoOuFalta() {
//     double valorRecebido = double.tryParse(_valorRecebidoController.text) ?? 0.0;
//     if (valorRecebido > widget.valorTotal) {
//       setState(() {
//         _troco = valorRecebido - widget.valorTotal;
//         _valorFaltando = 0.0;
//       });
//     } else {
//       setState(() {
//         _valorFaltando = widget.valorTotal - valorRecebido;
//         _troco = 0.0;
//       });
//     }
//   }
//
//   void concluirPagamento(BuildContext context) {
//     final pedidoProvider = Provider.of<PedidoProvider>(context, listen: false);
//     pedidoProvider.adicionarPedido(
//       Pedido(
//         codigo: DateTime.now().millisecondsSinceEpoch.toString(),
//         cliente: 'Cliente Padrão', // Substituir pelo nome do cliente real
//         valor: widget.valorTotal,
//         status: 'Concluído',
//         vendedor: 'Loja A', // Substituir pela loja ou vendedor real
//       ),
//     );
//     // Pagamento em dinheiro é considerado "processado" localmente
//     print('Pagamento com ${widget.metodoPagamento} confirmado.');
//     print('Valor Total: ${widget.valorTotal}');
//     print('Valor Recebido: $_valorRecebidoController');
//     print('Troco: $_troco');
//
//     // Navegar para a tela de pedidos
//     // Navigator.pushReplacementNamed(context, '/historico_vendas');
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Pagamento - ${widget.metodoPagamento}'),
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.center,
//           children: <Widget>[
//             Text(
//               'Valor Total: R\$ ${widget.valorTotal.toStringAsFixed(2)}',
//               style: TextStyle(
//                 fontSize: 24,
//                 fontWeight: FontWeight.bold,
//                 color: Colors.black,
//               ),
//             ),
//             SizedBox(height: 30),
//             TextField(
//               controller: _valorRecebidoController,
//               keyboardType: TextInputType.number,
//               decoration: InputDecoration(
//                 labelText: 'Valor Recebido',
//                 border: OutlineInputBorder(),
//               ),
//               onChanged: (value) {
//                 calcularTrocoOuFalta();
//               },
//             ),
//             SizedBox(height: 20),
//             if (_troco > 0)
//               Text(
//                 'Troco: R\$ ${_troco.toStringAsFixed(2)}',
//                 style: TextStyle(
//                   fontSize: 20,
//                   color: Colors.green,
//                 ),
//               ),
//             if (_valorFaltando > 0)
//               Text(
//                 'Falta: R\$ ${_valorFaltando.toStringAsFixed(2)}',
//                 style: TextStyle(
//                   fontSize: 20,
//                   color: Colors.red,
//                 ),
//               ),
//             SizedBox(height: 30),
//             ElevatedButton(
//               onPressed: () {
//                 if (_valorFaltando > 0) {
//                   ScaffoldMessenger.of(context).showSnackBar(
//                     SnackBar(content: Text('Pagamento incompleto!')),
//                   );
//                   return;
//                 }
//                 Navigator.push(
//                   context,
//                   MaterialPageRoute(
//                     builder: (context) =>
//                         ConclusaoVendaScreen(valorTotal: widget.valorTotal,carrinho: widget.carrinho,idCliente: widget.idCliente, metodoPagamento: widget.metodoPagamento,cliente: widget.cliente,),
//                   ),
//                 );
//                 concluirPagamento(context);
//               },
//               child: Text('Concluir'),
//               style: ElevatedButton.styleFrom(
//                 minimumSize: Size(double.infinity, 50),
//                 textStyle: TextStyle(fontSize: 18),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }


import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/cliente.dart';
import 'conclusao_venda_screen.dart';

class PagamentoDinheiroScreen extends StatefulWidget {
  final double valorTotal;
  final List<Map<String, dynamic>> carrinho;
  final String? idCliente;
  final String metodoPagamento;
  final Cliente cliente;
  final double desconto;
  final double valorEntrega;
  final String entregaSelecionada;
  final double saldoUsado;

  PagamentoDinheiroScreen({
    required this.valorTotal,
    required this.carrinho,
    this.idCliente,
    required this.metodoPagamento,
    required this.cliente,
    this.desconto= 0.0,
    required this.valorEntrega,
    required this.entregaSelecionada,
    required this.saldoUsado,
  });

  @override
  _PagamentoDinheiroScreenState createState() => _PagamentoDinheiroScreenState();
}

class _PagamentoDinheiroScreenState extends State<PagamentoDinheiroScreen> {
  TextEditingController _valorRecebidoController = TextEditingController();
  double _troco = 0.0;
  double _valorFaltando = 0.0;
  double _valorPago = 0.0;
  double _desconto = 0.0;
  double _saldoUsado = 0.0;
  @override
  void initState() {
    super.initState();
    _desconto = widget.desconto; // Inicializa o desconto com o valor passado do widget
    _saldoUsado = widget.saldoUsado;
    print('initState: desconto = $_desconto, valorTotal = ${widget.valorTotal}');
  }

  @override
  void dispose() {
    _valorRecebidoController.dispose();
    super.dispose();
  }

  void calcularTrocoOuFalta() {
    double valorRecebido = double.tryParse(_valorRecebidoController.text) ?? 0.0;
    setState(() {
      _valorPago = valorRecebido;
      if (valorRecebido >= widget.valorTotal) {
        _troco = valorRecebido - widget.valorTotal;
        _valorFaltando = 0.0;
      } else {
        _troco = 0.0;
        _valorFaltando = widget.valorTotal - valorRecebido;
      }
    });
  }

  void concluirPagamento() {
    if (_valorFaltando > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pagamento incompleto!')),
      );
      return;
    }
    print('=== Dados enviados para ConclusaoVendaScreen ===');
    print('Valor Total: ${widget.valorTotal}');
    print('Valor Entrega: ${widget.valorEntrega}');
    print('Entrega Selecionada: ${widget.entregaSelecionada}');
    print('Valor Pago: $_valorPago');
    print('Troco: $_troco');
    print('Desconto: $_desconto');
    print('Método de Pagamento: ${widget.metodoPagamento}');
    print('ID Cliente: ${widget.idCliente}');
    print('Cliente: ${widget.cliente.nome}, ${widget.cliente.endereco}, ${widget.cliente.celular}, Saldo: ${widget.cliente.saldo}');
    print('Carrinho:');
    for (var item in widget.carrinho) {
      final produto = item['produto'];
      final quantidade = item['quantidade'];
      print('- Produto: ${produto.nome}, Preço: ${produto.preco}, Estoque: ${produto.estoqueAtual}, Quantidade: $quantidade');


  }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConclusaoVendaScreen(
          valorTotal: widget.valorTotal,
          carrinho: widget.carrinho,
          idCliente: widget.idCliente,
          metodoPagamento: widget.metodoPagamento,
          cliente: widget.cliente,
          valorPago: _valorPago,
          troco: _troco,
          desconto: _desconto,
          valorEntrega: widget.valorEntrega,
          entregaSelecionada: widget.entregaSelecionada,
          saldoUsado: widget.saldoUsado,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Pagamento - ${widget.metodoPagamento}')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              'Valor Total: R\$ ${widget.valorTotal.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 30),
            TextField(
              controller: _valorRecebidoController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Valor Recebido',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => calcularTrocoOuFalta(),
            ),
            SizedBox(height: 20),
            if (_troco > 0)
              Text(
                'Troco: R\$ ${_troco.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 20, color: Colors.green),
              ),
            if (_valorFaltando > 0)
              Text(
                'Falta: R\$ ${_valorFaltando.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 20, color: Colors.red),
              ),
            if (_desconto > 0)
            Text(
              'Desconto: R\$ ${_desconto.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 20, color: Colors.red),
            ),
            Text(
              'Saldo utilizado: R\$ ${_saldoUsado.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 20, color: Colors.red),
            ),
            SizedBox(height: 30),
            ElevatedButton(
              onPressed: concluirPagamento,
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
