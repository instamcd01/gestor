import 'package:flutter/material.dart';
import 'package:gestor/models/produto.dart';
import 'package:gestor/models/cliente.dart';
import 'package:gestor/screens/desconto_screen.dart';
import 'package:gestor/screens/opcao_entrega_screen.dart';
import 'package:gestor/screens/pagamento_screen.dart';
import 'package:uuid/uuid.dart';

class CarrinhoScreen extends StatefulWidget {
  final List<Map<String, dynamic>> carrinho;
  final double valorTotal;
  final String idVenda;
  final String idCliente;

  CarrinhoScreen({
    required this.carrinho,
    required this.valorTotal,
    required this.idVenda,
    required this.idCliente,
  });

  @override
  _CarrinhoScreenState createState() => _CarrinhoScreenState();
}

class _CarrinhoScreenState extends State<CarrinhoScreen> {
  final String idVenda = Uuid().v4();
  // double desconto = 0.0;
  double valorEntrega = 0.0;
  double valorEntregaNormal = 0.0;
  String entregaSelecionada = '0-2km';
  Cliente? clienteSelecionado;

  final Map<String, Map<String, double>> opcoesEntrega = {
    'Frete grátis': {
      '0-2km': 0.0,
      '2-5km': 50.0,
      '5-7km': 70.0,
      '7-10km': 100.0,
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
      '5-7km': 7.99,
      '7-10km': 9.99,
      '10-13km': 12.99,
      '13-15km': 14.99,
      '15-17km': 16.99,
      '17-20km': 19.99,
      '20-25km': 24.99,
      '25-30km': 29.99,
    },
  };

  double getSubtotal() {
    double subtotal = 0.0;
    for (var item in widget.carrinho) {
      subtotal += item['produto'].preco * item['quantidade'];
    }
    return subtotal;
  }

  double calcularFaltandoParaFreteGratis(double subtotal) {
    double valorMinimo = opcoesEntrega['Frete grátis']![entregaSelecionada] ?? 0.0;
    if (subtotal < valorMinimo) {
      return valorMinimo - subtotal;
    }
    return 0.0;
  }

  String getTotalUnidades() {
    double totalUnidades = 0;
    for (var item in widget.carrinho) {
      totalUnidades += item['quantidade'];
    }
    return totalUnidades == totalUnidades.toInt()
        ? totalUnidades.toInt().toString()
        : totalUnidades.toString();
  }

  @override
  Widget build(BuildContext context) {
    double subtotal = getSubtotal();
    double faltandoParaFreteGratis = calcularFaltandoParaFreteGratis(subtotal);
    valorEntrega = faltandoParaFreteGratis <= 0 ? 0.0 : valorEntregaNormal;
    // double totalComDesconto = subtotal - desconto + valorEntrega;
    double totalComEntrega = subtotal + valorEntrega;

    print('=== CarrinhoScreen ===');
    print('Subtotal: $subtotal');
    print('Entrega selecionada: $entregaSelecionada');
    print('Valor do frete: $valorEntrega');
    print('Total com entrega: $totalComEntrega');
    print('Cliente selecionado: $clienteSelecionado');
    return Scaffold(
      appBar: AppBar(
        title: Text('Carrinho de Compras'),
        actions: [
          IconButton(
            icon: Icon(Icons.delete),
            onPressed: () {
              setState(() {
                widget.carrinho.clear();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Carrinho esvaziado!')),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView.builder(
                itemCount: widget.carrinho.length,
                itemBuilder: (ctx, i) {
                  final produto = widget.carrinho[i]['produto'] as Produto;
                  final quantidade = widget.carrinho[i]['quantidade'];
                  final excedeuEstoque = quantidade > produto.estoqueAtual;

                  return ListTile(
                    title: Text(produto.nome),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Preço: R\$ ${produto.preco.toStringAsFixed(2)}'),
                        if (excedeuEstoque)
                          Text(
                            'Verifique o estoque disponível (${produto.estoqueAtual})',
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.remove),
                          onPressed: () {
                            setState(() {
                              if (quantidade > 1) {
                                widget.carrinho[i]['quantidade']--;
                              }
                            });
                          },
                        ),
                        Text(quantidade.toString()),
                        IconButton(
                          icon: Icon(Icons.add),
                          onPressed: () {
                            setState(() {
                              widget.carrinho[i]['quantidade']++;
                            });
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.delete),
                          onPressed: () {
                            setState(() {
                              widget.carrinho.removeAt(i);
                            });
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            ElevatedButton(
              onPressed: () async {

              final resultado = await Navigator.push(

                  context,
                  MaterialPageRoute(
                    builder: (context) => OpcaoEntregaScreen(
                      opcoesEntrega: opcoesEntrega,
                      onSelecionarEntrega: (entrega, valor) {
                        setState(() {
                          entregaSelecionada = entrega;
                          valorEntregaNormal = valor;
                        });
                      },
                      subtotal: subtotal,
                    ),
                  ),
                );

                if (resultado != null && resultado is Map<String, dynamic>) {
                  setState(() {
                    clienteSelecionado = resultado['cliente'];
                                     });
                }
              },
              child: Text('Selecionar Cliente'),
            ),
            // ElevatedButton(
            //   onPressed: () {
            //     Navigator.push(
            //       context,
            //       MaterialPageRoute(
            //         builder: (context) => DescontoScreen(
            //           valorTotal: subtotal,
            //           onDescontoAplicado: (novoValor) {
            //             setState(() {
            //               desconto = subtotal - novoValor;
            //             });
            //           },
            //         ),
            //       ),
            //     );
            //   },
            //   child: Text('Aplicar Desconto'),
            // ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Subtotal: R\$ ${subtotal.toStringAsFixed(2)}'),
                // Text('Desconto aplicado: -R\$ ${desconto.toStringAsFixed(2)}'),
                Text.rich(
                  valorEntrega == 0
                      ? TextSpan(
                    text: 'Valor da entrega: ',
                    style: TextStyle(color: Colors.black),
                    children: [
                      TextSpan(
                        text: 'Frete Grátis',
                        style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                    ],
                  )
                      : TextSpan(
                    text: 'Valor da entrega: +R\$ ${valorEntrega.toStringAsFixed(2)}',
                    style: TextStyle(color: Colors.black),
                  ),
                ),
                Divider(),
                Text(
                  'Total: R\$ ${totalComEntrega.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                if (faltandoParaFreteGratis > 0)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Faltam R\$ ${faltandoParaFreteGratis.toStringAsFixed(2)} para frete grátis',
                      style: TextStyle(fontSize: 16, color: Colors.red),
                    ),
                  ),
              ],
            ),
            ElevatedButton(
              onPressed: (clienteSelecionado == null )
                  ? null
                  : () {

                // Cria um Map com todos os dados que serão passados
                final dadosPagamento = {
                  'idVenda': idVenda,
                  'valorTotal': totalComEntrega,
                  'carrinho': widget.carrinho,
                  'cliente': clienteSelecionado,
                  'desconto': 0.0, // ou variável de desconto se aplicável
                  'valorEntrega': valorEntrega,
                };

                print('🔹 Dados para PagamentoScreen:');
                print('idVenda: $idVenda');
                print('valorTotal: $totalComEntrega');
                print('valorEntrega: $valorEntrega');
                print('desconto: 0.0');
                print('Entrega selecionada antes de ir para PagamentoScreen: $entregaSelecionada');

                print('Cliente: ${clienteSelecionado?.nome}, ${clienteSelecionado?.endereco}');

                print('Carrinho:');
                for (var item in widget.carrinho) {
                  final produto = item['produto'] as Produto;
                  final quantidade = item['quantidade'];
                  print('- ${produto.nome} | Preço: ${produto.preco} | Quantidade: $quantidade');
                }

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PagamentoScreen(
                      idVenda: idVenda,
                      valorTotal: totalComEntrega,
                      carrinho: widget.carrinho,
                      cliente: clienteSelecionado!,
                      desconto: 0.0,
                      valorEntrega: valorEntrega,
                      entregaSelecionada: entregaSelecionada,
                    ),
                  ),
                );
              },
              child: Text(
                '${getTotalUnidades()} Itens - R\$ ${totalComEntrega.toStringAsFixed(2)}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

