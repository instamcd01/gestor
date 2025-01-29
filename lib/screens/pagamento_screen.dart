// import 'package:flutter/material.dart';
// import 'package:flutter_icons_null_safety/flutter_icons_null_safety.dart';
// import 'package:gestor/screens/adicionar_cliente_screen.dart';
// import 'package:gestor/screens/pagamento_credito_screen.dart';
// import 'package:gestor/screens/pagamento_debito_screen.dart';
// import 'package:provider/provider.dart';
// import '../models/cliente.dart';
// import '../providers/cliente_provider.dart';
// import 'editar_cliente_screen.dart';
// import 'pagamento_dinheiro_screen.dart';
//
// class PagamentoScreen extends StatefulWidget {
//   final double valorTotal;
//   // late Cliente _cliente;
//
//   PagamentoScreen({required this.valorTotal});
//
//   @override
//   _PagamentoScreenState createState() => _PagamentoScreenState();
// }
//
// class _PagamentoScreenState extends State<PagamentoScreen> {
//   String metodoPagamentoSelecionado = '';
//   String? clienteSelecionado;
//
//   // Função para alterar o método de pagamento selecionado
//   void selecionarMetodoPagamento(String metodo) {
//     setState(() {
//       metodoPagamentoSelecionado = metodo;
//     });
//   }
//
//   // Função para navegar para a tela de cadastro de cliente
//   void cadastrarNovoCliente() {
//     Navigator.push(
//       context,
//       MaterialPageRoute(
//         builder: (context) => AdicionarClienteScreen(onSalvar: (Cliente ) {  },),
//       ),
//     );
//   }
//
//   // Função para navegar para a tela de pagamento correspondente
//   void navegarParaTelaPagamento() {
//     if (metodoPagamentoSelecionado == 'Dinheiro') {
//       Navigator.push(
//         context,
//         MaterialPageRoute(
//           builder: (context) => PagamentoDinheiroScreen(valorTotal: widget.valorTotal),
//         ),
//       );
//     } else if (metodoPagamentoSelecionado == 'Cartão de Débito') {
//       Navigator.push(
//         context,
//         MaterialPageRoute(
//           builder: (context) => PagamentoCartaoDebitoScreen(valorTotal: widget.valorTotal),
//         ),
//       );
//     } else if (metodoPagamentoSelecionado == 'Cartão de Crédito') {
//       Navigator.push(
//         context,
//         MaterialPageRoute(
//           builder: (context) => PagamentoCartaoCreditoScreen(valorTotal: widget.valorTotal),
//         ),
//       );
//     }
//   }
//
//   @override
//   void didChangeDependencies() {
//     super.didChangeDependencies();
//     final clientProvider = Provider.of<ClientProvider>(context);
//     clienteSelecionado = clientProvider.clienteSelecionado as String?; // Obtém o cliente selecionado do provider
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final clientProvider = Provider.of<ClientProvider>(context);
//     final clientes = clientProvider.clientes; // Acessando a lista de clientes
//
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Método de Pagamento'),
//         actions: [
//           IconButton(
//             icon: Icon(Icons.person_add),
//             onPressed: cadastrarNovoCliente,
//             tooltip: 'Cadastrar Novo Cliente',
//           ),
//         ],
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.start,
//           crossAxisAlignment: CrossAxisAlignment.center,
//           children: <Widget>[
//             // Campo para selecionar o cliente
//             Padding(
//               padding: const EdgeInsets.only(bottom: 20.0),
//               child: Container(
//                 decoration: BoxDecoration(
//                   border: Border.all(color: Colors.blue),
//                   borderRadius: BorderRadius.circular(8),
//                 ),
//                 child: DropdownButton<String>(
//                   value: clienteSelecionado,
//                   hint: Text('Selecione um Cliente'),
//                   isExpanded: true,
//                   items: clientes.map((cliente) {
//                     return DropdownMenuItem<String>(
//                       value: cliente.nome,
//                       child: Text(cliente.nome),
//                     );
//                   }).toList(),
//                   onChanged: (novoCliente) {
//                     setState(() {
//                       clienteSelecionado = novoCliente;
//                       clientProvider.setClienteSelecionado(novoCliente! as Cliente); // Atualiza o cliente selecionado no provider
//                     });
//                   },
//                 ),
//               ),
//             ),
//
//             // Exibindo o valor total no centro da tela
//             Text(
//               'Valor Total: R\$ ${widget.valorTotal.toStringAsFixed(2)}',
//               style: TextStyle(
//                 fontSize: 24,
//                 fontWeight: FontWeight.bold,
//                 color: Colors.black,
//               ),
//             ),
//             SizedBox(height: 30),
//
//             // Exibindo as opções de pagamento com ícones
//             GridView.builder(
//               shrinkWrap: true,
//               gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
//                 crossAxisCount: 3,
//                 crossAxisSpacing: 10,
//                 mainAxisSpacing: 20,
//               ),
//               itemCount: 6,
//               itemBuilder: (context, index) {
//                 List<Map<String, dynamic>> opcoesPagamento = [
//                   {'metodo': 'Dinheiro', 'icone': Icons.money},
//                   {'metodo': 'Cartão de Débito', 'icone': FlutterIcons.credit_card_outline_mco},
//                   {'metodo': 'Cartão de Crédito', 'icone': FlutterIcons.credit_card_mdi},
//                   {'metodo': 'Saldo Cliente', 'icone': Icons.account_balance_wallet},
//                   {'metodo': 'Link de Pagamento', 'icone': Icons.link},
//                   {'metodo': 'Outros', 'icone': Icons.more_horiz},
//                 ];
//
//                 String metodo = opcoesPagamento[index]['metodo']!;
//                 IconData icone = opcoesPagamento[index]['icone']!;
//
//                 return GestureDetector(
//                   onTap: () {
//                     selecionarMetodoPagamento(metodo);
//                   },
//                   child: Column(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     children: <Widget>[
//                       Icon(icone, size: 40, color: Colors.blue), // Ícone do método
//                       SizedBox(height: 8),
//                       Text(metodo), // Nome do método de pagamento
//                     ],
//                   ),
//                 );
//               },
//             ),
//             SizedBox(height: 30),
//
//             // Botão Avançar
//             ElevatedButton(
//               onPressed: metodoPagamentoSelecionado.isEmpty
//                   ? null
//                   : navegarParaTelaPagamento,
//               child: Text('Avançar'),
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

/////////////////
import 'package:flutter/material.dart';
import 'package:flutter_icons_null_safety/flutter_icons_null_safety.dart';
import 'package:provider/provider.dart';
import '../models/cliente.dart';
import '../providers/cliente_provider.dart';
import 'adicionar_cliente_screen.dart';
import 'pagamento_credito_screen.dart';
import 'pagamento_debito_screen.dart';
import 'pagamento_dinheiro_screen.dart';

class PagamentoScreen extends StatefulWidget {
  final double valorTotal;
  final String idVenda;
  final String idCliente;
  final List<Map<String, dynamic>> carrinho;

  PagamentoScreen({required this.valorTotal,
    // required List<Map<String, dynamic>> carrinho,
    required this.idVenda,
    required this.carrinho,
    required this.idCliente});

  @override
  _PagamentoScreenState createState() => _PagamentoScreenState();
}

class _PagamentoScreenState extends State<PagamentoScreen> {
  String metodoPagamentoSelecionado = '';
  Cliente? clienteSelecionado;

  void selecionarMetodoPagamento(String metodo) {
    setState(() {
      metodoPagamentoSelecionado = metodo;
    });
  }

  void cadastrarNovoCliente() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdicionarClienteScreen(
          onSalvar: (Cliente cliente) {
            Provider.of<ClientProvider>(context, listen: false).addCliente(cliente);
          },
        ),
      ),
    );
  }

  void navegarParaTelaPagamento() {
    print('Método de pagamento selecionado: $metodoPagamentoSelecionado');
    print('Valor Total: ${widget.valorTotal}');
    print('carrinho: ${widget.carrinho.map((item) => 'Produto: ${item['produto'].nome}, Preço: ${item['produto'].preco}, Quantidade: ${item['quantidade']}').toList()}');

    if (metodoPagamentoSelecionado == 'Dinheiro') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PagamentoDinheiroScreen(valorTotal: widget.valorTotal, carrinho: widget.carrinho,),
        ),
      );
    } else if (metodoPagamentoSelecionado == 'Cartão de Débito') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PagamentoCartaoDebitoScreen(valorTotal: widget.valorTotal, carrinho: [],),
        ),
      );
    } else if (metodoPagamentoSelecionado == 'Cartão de Crédito') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PagamentoCartaoCreditoScreen(valorTotal: widget.valorTotal, carrinho: [],),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientProvider = Provider.of<ClientProvider>(context);
    final clientes = clientProvider.clientes;

    return Scaffold(
      appBar: AppBar(
        title: Text('Método de Pagamento'),
        actions: [
          IconButton(
            icon: Icon(Icons.person_add),
            onPressed: cadastrarNovoCliente,
            tooltip: 'Cadastrar Novo Cliente',
          ),
        ],
      ),

    body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(bottom: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumo da Compra',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: 10),
                    // Exibindo os itens do carrinho em uma única linha
                    ...widget.carrinho.map((item) {
                      // Log para verificar o item
                      print('Produto: ${item['produto'].nome}');
                      print('Quantidade: ${item['quantidade']}');
                      print('Preço Unitário: ${item['produto'].preco}');
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5.0),
                        child: Row(
                          children: [
                            Text(
                              '${item['quantidade']} x ',
                              style: TextStyle(fontSize: 16),
                            ),
                            Expanded(
                              child: Text(
                                item['produto'].nome,
                                style: TextStyle(
                                  fontSize: 16,
                                  overflow: TextOverflow.ellipsis, // Trunca o texto se for muito longo
                                ),
                              ),
                            ),
                            Text(
                              ' - R\$ ${item['produto'].preco}',
                              style: TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    SizedBox(height: 10),
     Padding(


        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            // Campo para selecionar o cliente
            Padding(
              padding: const EdgeInsets.only(bottom: 20.0),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.blue),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<Cliente>(
                      value: clienteSelecionado,
                      hint: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text('Selecione um Cliente'),
                      ),
                      isExpanded: true,
                      items: clientes.map((cliente) {
                        return DropdownMenuItem<Cliente>(
                          value: cliente,
                          child: Text(cliente.nome),
                        );
                      }).toList(),
                      onChanged: (novoCliente) {
                        setState(() {
                          clienteSelecionado = novoCliente;
                          clientProvider.setClienteSelecionado(novoCliente!);
                        });
                      },
                    ),
                  ),
                  if (clienteSelecionado != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10.0),
                      child: Text(
                        'Saldo: R\$ ${clienteSelecionado!.saldo.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Exibindo o valor total no centro da tela
            Text(
              'Valor Total: R\$ ${widget.valorTotal.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            SizedBox(height: 30),

            // Exibindo as opções de pagamento com ícones
            GridView.builder(
              shrinkWrap: true,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 20,
              ),
              itemCount: 6,
              itemBuilder: (context, index) {
                List<Map<String, dynamic>> opcoesPagamento = [
                  {'metodo': 'Dinheiro', 'icone': Icons.money},
                  {'metodo': 'Cartão de Débito', 'icone': FlutterIcons.credit_card_outline_mco},
                  {'metodo': 'Cartão de Crédito', 'icone': FlutterIcons.credit_card_mdi},
                  {'metodo': 'Saldo Cliente', 'icone': Icons.account_balance_wallet},
                  {'metodo': 'Link de Pagamento', 'icone': Icons.link},
                  {'metodo': 'Outros', 'icone': Icons.more_horiz},
                ];

                String metodo = opcoesPagamento[index]['metodo']!;
                IconData icone = opcoesPagamento[index]['icone']!;

                return GestureDetector(
                  onTap: () {
                    selecionarMetodoPagamento(metodo);
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(icone, size: 40, color: Colors.blue),
                      SizedBox(height: 8),
                      Text(metodo),
                    ],
                  ),
                );
              },
            ),
            SizedBox(height: 30),

            // Botão Avançar
            ElevatedButton(
              onPressed: metodoPagamentoSelecionado.isEmpty
                  ? null
                  : navegarParaTelaPagamento,
              child: Text('Avançar'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
                textStyle: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),]
    )
    )])))
    );
  }
}

// import 'package:flutter/material.dart';
// import 'package:flutter_icons_null_safety/flutter_icons_null_safety.dart';
// import 'package:provider/provider.dart';
// import '../models/cliente.dart';
// import '../providers/cliente_provider.dart';
// import 'adicionar_cliente_screen.dart';
// import 'pagamento_credito_screen.dart';
// import 'pagamento_debito_screen.dart';
// import 'pagamento_dinheiro_screen.dart';
//
// class PagamentoScreen extends StatefulWidget {
//   final double valorTotal;
//   final List<Map<String, dynamic>> carrinho;
//
//   PagamentoScreen({required this.valorTotal, required this.carrinho});
//
//   @override
//   _PagamentoScreenState createState() => _PagamentoScreenState();
// }
//
// class _PagamentoScreenState extends State<PagamentoScreen> {
//   String metodoPagamentoSelecionado = '';
//   Cliente? clienteSelecionado;
//
//   void selecionarMetodoPagamento(String metodo) {
//     setState(() {
//       metodoPagamentoSelecionado = metodo;
//     });
//   }
//
//   void cadastrarNovoCliente() {
//     Navigator.push(
//       context,
//       MaterialPageRoute(
//         builder: (context) => AdicionarClienteScreen(
//           onSalvar: (Cliente cliente) {
//             Provider.of<ClientProvider>(context, listen: false).addCliente(cliente);
//           },
//         ),
//       ),
//     );
//   }
//
//   void navegarParaTelaPagamento() {
//     if (metodoPagamentoSelecionado == 'Dinheiro') {
//       Navigator.push(
//         context,
//         MaterialPageRoute(
//           builder: (context) => PagamentoDinheiroScreen(valorTotal: widget.valorTotal,carrinho: widget.carrinho,),
//         ),
//       );
//     } else if (metodoPagamentoSelecionado == 'Cartão de Débito') {
//       Navigator.push(
//         context,
//         MaterialPageRoute(
//           builder: (context) => PagamentoCartaoDebitoScreen(valorTotal: widget.valorTotal, carrinho: widget.carrinho),
//         ),
//       );
//     } else if (metodoPagamentoSelecionado == 'Cartão de Crédito') {
//       Navigator.push(
//         context,
//         MaterialPageRoute(
//           builder: (context) => PagamentoCartaoCreditoScreen(valorTotal: widget.valorTotal, carrinho: widget.carrinho),
//         ),
//       );
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final clientProvider = Provider.of<ClientProvider>(context);
//     final clientes = clientProvider.clientes;
//
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Método de Pagamento'),
//         actions: [
//           IconButton(
//             icon: Icon(Icons.person_add),
//             onPressed: cadastrarNovoCliente,
//             tooltip: 'Cadastrar Novo Cliente',
//           ),
//         ],
//       ),
//       body: SingleChildScrollView(
//         child: Padding(
//           padding: const EdgeInsets.all(16.0),
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.start,
//             crossAxisAlignment: CrossAxisAlignment.center,
//             children: <Widget>[
//               Padding(
//                 padding: const EdgeInsets.only(bottom: 20.0),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       'Resumo da Compra',
//                       style: TextStyle(
//                         fontSize: 20,
//                         fontWeight: FontWeight.bold,
//                         color: Colors.black,
//                       ),
//                     ),
//                     SizedBox(height: 10),
//                     // Exibindo os itens do carrinho em uma única linha
//                     ...widget.carrinho.map((item) {
//                       // Log para verificar o item
//                       print('Produto: ${item['produto'].nome}');
//                       print('Quantidade: ${item['quantidade']}');
//                       print('Preço Unitário: ${item['produto'].preco}');
//                       return Padding(
//                         padding: const EdgeInsets.symmetric(vertical: 5.0),
//                         child: Row(
//                           children: [
//                             Text(
//                               '${item['quantidade']} x ',
//                               style: TextStyle(fontSize: 16),
//                             ),
//                             Expanded(
//                               child: Text(
//                                 item['produto'].nome,
//                                 style: TextStyle(
//                                   fontSize: 16,
//                                   overflow: TextOverflow.ellipsis, // Trunca o texto se for muito longo
//                                 ),
//                               ),
//                             ),
//                             Text(
//                               ' - R\$ ${item['produto'].preco}',
//                               style: TextStyle(fontSize: 16),
//                             ),
//                           ],
//                         ),
//                       );
//                     }).toList(),
//                     SizedBox(height: 10),
//                     // Exibindo o valor total
//                     Text(
//                       'Valor Total: R\$ ${widget.valorTotal.toStringAsFixed(2)}',
//                       style: TextStyle(
//                         fontSize: 18,
//                         fontWeight: FontWeight.bold,
//                         color: Colors.green,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//
//               // Campo para selecionar o cliente
//               Padding(
//                 padding: const EdgeInsets.only(bottom: 20.0),
//                 child: Column(
//                   children: [
//                     Container(
//                       decoration: BoxDecoration(
//                         border: Border.all(color: Colors.blue),
//                         borderRadius: BorderRadius.circular(8),
//                       ),
//                       child: DropdownButton<Cliente>(
//                         value: clienteSelecionado,
//                         hint: Padding(
//                           padding: const EdgeInsets.symmetric(horizontal: 8.0),
//                           child: Text('Selecione um Cliente'),
//                         ),
//                         isExpanded: true,
//                         items: clientes.map((cliente) {
//                           return DropdownMenuItem<Cliente>(
//                             value: cliente,
//                             child: Text(cliente.nome),
//                           );
//                         }).toList(),
//                         onChanged: (novoCliente) {
//                           setState(() {
//                             clienteSelecionado = novoCliente;
//                             clientProvider.setClienteSelecionado(novoCliente!);
//                           });
//                         },
//                       ),
//                     ),
//                     if (clienteSelecionado != null)
//                       Padding(
//                         padding: const EdgeInsets.only(top: 10.0),
//                         child: Text(
//                           'Saldo: R\$ ${clienteSelecionado!.saldo.toStringAsFixed(2)}',
//                           style: TextStyle(
//                             fontSize: 16,
//                             fontWeight: FontWeight.bold,
//                             color: Colors.green,
//                           ),
//                         ),
//                       ),
//                   ],
//                 ),
//               ),
//
//               // Exibindo as opções de pagamento com ícones
//               GridView.builder(
//                 shrinkWrap: true,
//                 gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
//                   crossAxisCount: 3,
//                   crossAxisSpacing: 10,
//                   mainAxisSpacing: 20,
//                 ),
//                 itemCount: 6,
//                 itemBuilder: (context, index) {
//                   List<Map<String, dynamic>> opcoesPagamento = [
//                     {'metodo': 'Dinheiro', 'icone': Icons.money},
//                     {'metodo': 'Cartão de Débito', 'icone': FlutterIcons.credit_card_outline_mco},
//                     {'metodo': 'Cartão de Crédito', 'icone': FlutterIcons.credit_card_mdi},
//                     {'metodo': 'Saldo Cliente', 'icone': Icons.account_balance_wallet},
//                     {'metodo': 'Link de Pagamento', 'icone': Icons.link},
//                     {'metodo': 'Outros', 'icone': Icons.more_horiz},
//                   ];
//
//                   String metodo = opcoesPagamento[index]['metodo']!;
//                   IconData icone = opcoesPagamento[index]['icone']!;
//
//                   return GestureDetector(
//                     onTap: () {
//                       selecionarMetodoPagamento(metodo);
//                     },
//                     child: Column(
//                       mainAxisAlignment: MainAxisAlignment.center,
//                       children: <Widget>[
//                         Icon(icone, size: 40, color: Colors.blue),
//                         SizedBox(height: 8),
//                         Text(metodo),
//                       ],
//                     ),
//                   );
//                 },
//               ),
//               SizedBox(height: 30),
//
//               // Botão Avançar
//               ElevatedButton(
//                 onPressed: metodoPagamentoSelecionado.isEmpty
//                     ? null
//                     : (){
//                   print('Método de pagamento selecionado: $metodoPagamentoSelecionado');
//
//                   navegarParaTelaPagamento();
//                 },
//
//                 child: Text('Avançar'),
//                 style: ElevatedButton.styleFrom(
//                   minimumSize: Size(double.infinity, 50),
//                   textStyle: TextStyle(fontSize: 18),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
//
