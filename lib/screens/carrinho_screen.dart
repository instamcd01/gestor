import 'package:flutter/material.dart';
import 'package:gestor/models/cliente.dart';
import 'package:gestor/models/cliente.dart';
import 'package:gestor/models/venda.dart';
import 'package:gestor/screens/pagamento_screen.dart'; // Importando a tela de pagamento
import 'package:uuid/uuid.dart';
import '../models/cliente.dart';
import '../models/produto.dart';
import 'desconto_screen.dart';
import 'gerenciar_entrega_screen.dart';
import 'opcao_entrega_screen.dart';

class CarrinhoScreen extends StatefulWidget {
  final List<Map<String, dynamic>> carrinho;
  final double valorTotal;
  final String idVenda;
  final String idCliente;

  CarrinhoScreen({required this.carrinho, required this.valorTotal, required this.idVenda, required this.idCliente});

  @override
  _CarrinhoScreenState createState() => _CarrinhoScreenState();
}

class _CarrinhoScreenState extends State<CarrinhoScreen> {
  final String idVenda = Uuid().v4();
  double desconto = 0.0;
  bool opcaoEntrega = false;
  double valorEntrega = 0.0;
  double valorEntregaNormal = 0.0; // Variável para armazenar o valor normal da entrega
  String entregaSelecionada = '0-5km';

  // Função para calcular o subtotal
  double getSubtotal() {
    double subtotal = 0.0;
    for (var item in widget.carrinho) {
      subtotal += item['produto'].preco * item['quantidade'];
    }
    return subtotal;
  }

  // Função para calcular o valor faltante para frete grátis
  double calcularFaltandoParaFreteGratis(double subtotal) {
    double valorMinimo = opcoesEntrega['Frete grátis']![entregaSelecionada] ?? 0.0;
    if (subtotal < valorMinimo) {
      return valorMinimo - subtotal;
    }
    return 0.0;
  }

  // Função para calcular o total de unidades no carrinho
  String getTotalUnidades() {
    double totalUnidades = 0;
    for (var item in widget.carrinho) {
      totalUnidades += item['quantidade'];
    }
    // Retorna como inteiro se for equivalente; caso contrário, como double formatado
    return totalUnidades == totalUnidades.toInt()
        ? totalUnidades.toInt().toString()
        : totalUnidades.toString();
  }

  @override
  Widget build(BuildContext context) {
    // Recalcular o subtotal sempre que a tela for reconstruída
    double subtotal = getSubtotal();

    // Calcular o valor faltante para frete grátis
    double faltandoParaFreteGratis = calcularFaltandoParaFreteGratis(subtotal);

    // Se o valor faltante for zero ou negativo, o frete será grátis (valorEntrega = 0)
    if (faltandoParaFreteGratis <= 0) {
      valorEntrega = 0.0;
    } else {
      // Restaurar o valor normal da entrega caso o frete grátis não seja mais aplicável
      valorEntrega = valorEntregaNormal;
    }

    // Calcular o total com desconto e entrega
    double totalComDesconto = subtotal - desconto + valorEntrega;

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
            // Exibe os produtos no carrinho
            Expanded(
              child: ListView.builder(
                itemCount: widget.carrinho.length,
                itemBuilder: (ctx, i) {
                  return ListTile(
                    title: Text(widget.carrinho[i]['produto'].nome),
                    subtitle: Text('Preço: R\$ ${widget.carrinho[i]['produto'].preco}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Campo para editar a quantidade
                        IconButton(
                          icon: Icon(Icons.remove),
                          onPressed: () {
                            setState(() {
                              if (widget.carrinho[i]['quantidade'] > 1) {
                                widget.carrinho[i]['quantidade']--;
                              }
                            });
                          },
                        ),
                        Text(widget.carrinho[i]['quantidade'].toString()),
                        IconButton(
                          icon: Icon(Icons.add),
                          onPressed: () {
                            setState(() {
                              widget.carrinho[i]['quantidade']++;
                            });
                          },
                        ),
                        // Ícone de exclusão do produto
                        IconButton(
                          icon: Icon(Icons.delete),
                          onPressed: () {
                            setState(() {
                              widget.carrinho.removeAt(i);
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Produto removido!')),
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => OpcaoEntregaScreen(
                      opcoesEntrega: opcoesEntrega,
                      onSelecionarEntrega: (entrega, valor) {
                        setState(() {
                          entregaSelecionada = entrega;
                          valorEntregaNormal = valor; // Salvar o valor normal da entrega
                          valorEntrega = valor; // Atualizar o valor da entrega
                        });
                      },
                      subtotal: subtotal, // Passando o subtotal correto
                    ),
                  ),
                );
              },
              child: Text('Selecionar Opção de Entrega'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DescontoScreen(
                      valorTotal: subtotal,
                      onDescontoAplicado: (novoValor) {
                        setState(() {
                          desconto = subtotal - novoValor;
                        });
                      },
                    ),
                  ),
                );
              },
              child: Text('Aplicar Desconto'),
            ),
            // Exibe os valores atualizados
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Subtotal: R\$ ${subtotal.toStringAsFixed(2)}'),
                Text('Desconto aplicado: -R\$ ${desconto.toStringAsFixed(2)}'),
                Text('Valor da entrega: +R\$ ${valorEntrega.toStringAsFixed(2)}'),
                Divider(),
                Text(
                  'Total: R\$ ${totalComDesconto.toStringAsFixed(2)}',
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
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Total: R\$ ${totalComDesconto.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            // Botão para finalizar a venda (exibindo total de itens e valor total)
            ElevatedButton(
              onPressed: () {
                print('Redirecionando para pagamento com carrinho: ${widget.carrinho.map((item) => 'Produto: ${item['produto'].nome}, Preço: ${item['produto'].preco}, Quantidade: ${item['quantidade']}').toList()}');

                // Redirecionar para a tela de pagamento
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PagamentoScreen(
                      idVenda: idVenda,
                      idCliente: widget.idCliente,
                      valorTotal: totalComDesconto,
                      carrinho: widget.carrinho,
                    ),
                  ),
                );
              },
              child: Text(
                '${getTotalUnidades()} Itens - R\$ ${totalComDesconto.toStringAsFixed(2)}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}


//
// import 'package:flutter/material.dart';
// import 'package:gestor/screens/pagamento_screen.dart'; // Importando a tela de pagamento
// import 'package:provider/provider.dart';
// import '../models/produto.dart';
// import 'desconto_screen.dart';
// import 'gerenciar_entrega_screen.dart';
// import 'opcao_entrega_screen.dart';
// import '../providers/carrinho_provider.dart';
//
// class CarrinhoScreen extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     final carrinhoProvider = Provider.of<CarrinhoProvider>(context);
//     double subtotal = carrinhoProvider.getSubtotal();
//     double faltandoParaFreteGratis = carrinhoProvider.calcularFaltandoParaFreteGratis(subtotal, opcoesEntrega);
//     double totalComDesconto = subtotal - carrinhoProvider.desconto + carrinhoProvider.valorEntrega;
//
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Carrinho de Compras'),
//         actions: [
//           IconButton(
//             icon: Icon(Icons.delete),
//             onPressed: () {
//               carrinhoProvider.clearCarrinho();
//               ScaffoldMessenger.of(context).showSnackBar(
//                 SnackBar(content: Text('Carrinho esvaziado!')),
//               );
//             },
//           ),
//         ],
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           children: <Widget>[
//             Expanded(
//               child: ListView.builder(
//                 itemCount: carrinhoProvider.carrinho.length,
//                 itemBuilder: (ctx, i) {
//                   return ListTile(
//                     title: Text(carrinhoProvider.carrinho[i]['produto'].nome),
//                     subtitle: Text('Preço: R\$ ${carrinhoProvider.carrinho[i]['produto'].preco}'),
//                     trailing: Row(
//                       mainAxisSize: MainAxisSize.min,
//                       children: [
//                         IconButton(
//                           icon: Icon(Icons.remove),
//                           onPressed: () {
//                             int novaQuantidade = carrinhoProvider.carrinho[i]['quantidade'] - 1;
//                             carrinhoProvider.atualizarQuantidade(i, novaQuantidade);
//                           },
//                         ),
//                         Text(carrinhoProvider.carrinho[i]['quantidade'].toString()),
//                         IconButton(
//                           icon: Icon(Icons.add),
//                           onPressed: () {
//                             int novaQuantidade = carrinhoProvider.carrinho[i]['quantidade'] + 1;
//                             carrinhoProvider.atualizarQuantidade(i, novaQuantidade);
//                           },
//                         ),
//                         IconButton(
//                           icon: Icon(Icons.delete),
//                           onPressed: () {
//                             carrinhoProvider.removerProduto(i);
//                             ScaffoldMessenger.of(context).showSnackBar(
//                               SnackBar(content: Text('Produto removido!')),
//                             );
//                           },
//                         ),
//                       ],
//                     ),
//                   );
//                 },
//               ),
//             ),
//             ElevatedButton(
//               onPressed: () {
//                 Navigator.push(
//                   context,
//                   MaterialPageRoute(
//                     builder: (context) => OpcaoEntregaScreen(
//                       opcoesEntrega: opcoesEntrega,
//                       onSelecionarEntrega: (entrega, valor) {
//                         carrinhoProvider.atualizarEntrega(entrega, valor);
//                       },
//                       subtotal: subtotal,
//                     ),
//                   ),
//                 );
//               },
//               child: Text('Selecionar Opção de Entrega'),
//             ),
//             ElevatedButton(
//               onPressed: () {
//                 Navigator.push(
//                   context,
//                   MaterialPageRoute(
//                     builder: (context) => DescontoScreen(
//                       valorTotal: subtotal,
//                       onDescontoAplicado: (novoValor) {
//                         carrinhoProvider.aplicarDesconto(novoValor);
//                       },
//                     ),
//                   ),
//                 );
//               },
//               child: Text('Aplicar Desconto'),
//             ),
//             Column(
//               crossAxisAlignment: CrossAxisAlignment.stretch,
//               children: [
//                 Text('Subtotal: R\$ ${subtotal.toStringAsFixed(2)}'),
//                 Text('Desconto aplicado: -R\$ ${carrinhoProvider.desconto.toStringAsFixed(2)}'),
//                 Text('Valor da entrega: +R\$ ${carrinhoProvider.valorEntrega.toStringAsFixed(2)}'),
//                 Divider(),
//                 Text(
//                   'Total: R\$ ${totalComDesconto.toStringAsFixed(2)}',
//                   style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
//                 ),
//                 if (faltandoParaFreteGratis > 0)
//                   Padding(
//                     padding: const EdgeInsets.all(8.0),
//                     child: Text(
//                       'Faltam R\$ ${faltandoParaFreteGratis.toStringAsFixed(2)} para frete grátis',
//                       style: TextStyle(fontSize: 16, color: Colors.red),
//                     ),
//                   ),
//               ],
//             ),
//             Padding(
//               padding: const EdgeInsets.all(8.0),
//               child: Text(
//                 'Total: R\$ ${totalComDesconto.toStringAsFixed(2)}',
//                 style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
//               ),
//             ),
//             ElevatedButton(
//               onPressed: () {
//                 Navigator.push(
//                   context,
//                   MaterialPageRoute(
//                     builder: (context) => PagamentoScreen(
//                       valorTotal: totalComDesconto,
//                       carrinho: carrinhoProvider.carrinho,
//                     ),
//                   ),
//                 );
//               },
//               child: Text(
//                 '${carrinhoProvider.carrinho.length} Itens - R\$ ${totalComDesconto.toStringAsFixed(2)}',
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
