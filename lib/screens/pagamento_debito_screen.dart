// pagamento_cartao_debito_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/cliente.dart';
import '../models/venda.dart';
import '../providers/historico_vendas_provider.dart';
import 'conclusao_venda_screen.dart';

class PagamentoCartaoDebitoScreen extends StatefulWidget {
  final double valorTotal;
  final List<Map<String, dynamic>> carrinho;

  PagamentoCartaoDebitoScreen({required this.valorTotal, required this.carrinho});

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
  void concluirVenda() {
    if (valorFaltante > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pagamento incompleto!')),
      );
      return;
    }
    final itensVenda = widget.carrinho.map<ItemVenda>((item) {
      return ItemVenda(
        produto: item['nome'].nome,      // Adapte conforme sua estrutura de Map
        precoTotal: item['preco'].preco,    // Adapte conforme sua estrutura de Map
        quantidade: item['quantidade'].quantidade, // Adapte conforme sua estrutura de Map
      );
    }).toList();



    final historicoVendasProvider =
    Provider.of<HistoricoVendasProvider>(context, listen: false);

    // Criação de um objeto Cliente de exemplo (substitua conforme necessário)
    Cliente clienteExemplo = Cliente(idCliente: '', nome: '', celular: '', email: '', endereco: '', complemento: '', cpf: '', pet: [], observacao: '', saldo: 0.0); // Supondo que o nome seja o único parâmetro

    historicoVendasProvider.adicionarVenda(
      Venda(
        cliente: clienteExemplo, // Passando o objeto Cliente
        metodoPagamento: 'Cartão de Débito',
        valorTotal: widget.valorTotal,
        itens: itensVenda, // Se você tiver itens, coloque-os aqui
        idVenda: '', // O ID deve ser gerado ou atribuído aqui
        dataVenda: DateTime.now(), // Passando a data atual como DateTime
      ),
    );

    Navigator.pushReplacementNamed(context, '/historico_vendas');
  }

  // void concluirVenda() {
  //   if (valorFaltante > 0) {
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(content: Text('Pagamento incompleto!')),
  //     );
  //     return;
  //   }
  //
  //   final historicoVendasProvider =
  //   Provider.of<HistoricoVendasProvider>(context, listen: false);
  //
  //   historicoVendasProvider.adicionarVenda(
  //     Venda(
  //       cliente: 'Cliente Exemplo', // Substitua com o nome do cliente selecionado
  //       metodoPagamento: 'Cartão de Débito',
  //       valorTotal: widget.valorTotal, itens: [], id: '', dataVenda: DateTime,
  //     ),
  //   );
  //
  //   Navigator.pushReplacementNamed(context, '/historico_vendas');
  // }
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
                        ConclusaoVendaScreen(valorTotal: widget.valorTotal, carrinho: widget.carrinho,),
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
