// import 'package:flutter/material.dart';
// import 'package:gestor/providers/carrinho_provider.dart';
// import 'package:gestor/providers/cliente_provider.dart';
// import 'package:gestor/providers/produto_provider.dart';
// import 'package:provider/provider.dart';
// import 'package:pdf/widgets.dart' as pw;
// import 'package:pdf/pdf.dart';
// import 'package:path_provider/path_provider.dart';
// import 'dart:io';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import '../models/cliente.dart';
// import '../models/venda.dart';
// import '../providers/historico_vendas_provider.dart';
// import '../providers/vendas_provider.dart';
//
// class ConclusaoVendaScreen extends StatefulWidget {
//   final double valorTotal;
//   final List<Map<String, dynamic>> carrinho;
//   final String? idCliente;
//   final String metodoPagamento;
//   final Cliente cliente;
//
//
//   ConclusaoVendaScreen({required this.valorTotal,required this.carrinho, this.idCliente, required this.metodoPagamento, required this.cliente,});
//
//
//   // Função para gerar o PDF do recibo
//   // Future<void> gerarRecibo(BuildContext context) async {
//   //   final pdf = pw.Document();
//   //
//   //   // Adiciona uma página ao PDF
//   //   pdf.addPage(pw.Page(
//   //     build: (pw.Context context) {
//   //       return pw.Center(
//   //         child: pw.Column(
//   //           crossAxisAlignment: pw.CrossAxisAlignment.start,
//   //           children: [
//   //             pw.Text('Recibo de Venda',
//   //                 style: pw.TextStyle(
//   //                   fontSize: 24,
//   //                   fontWeight: pw.FontWeight.bold,
//   //                 )),
//   //             pw.SizedBox(height: 20),
//   //             pw.Text('Data: ${DateTime.now().toString()}'),
//   //             pw.SizedBox(height: 10),
//   //             pw.Text('Valor Total: R\$ ${valorTotal.toStringAsFixed(2)}'),
//   //             pw.SizedBox(height: 20),
//   //             pw.Text('Itens Vendidos:', style: pw.TextStyle(fontSize: 18)),
//   //             pw.SizedBox(height: 10),
//   //             ...carrinho.map((item) => pw.Text(
//   //                 '- ${item.produto.nome} (Qtd: ${item.quantidade}) - R\$ ${item.precoTotal.toStringAsFixed(2)}')),
//   //             pw.SizedBox(height: 20),
//   //             pw.Text('Obrigado por sua compra!',
//   //                 style: pw.TextStyle(fontSize: 16)),
//   //           ],
//   //         ),
//   //       );
//   //     },
//   //   ));
//   //
//   //   // Obter o diretório de downloads no Android
//   //   final directory = await getExternalStorageDirectory();
//   //   final downloadDirectory = Directory('${directory!.path}/Download');
//   //   if (!await downloadDirectory.exists()) {
//   //     await downloadDirectory.create(recursive: true);
//   //   }
//   //
//   //   final file = File('${downloadDirectory.path}/recibo_venda.pdf');
//   //
//   //   // Salva o arquivo PDF no diretório de downloads
//   //   await file.writeAsBytes(await pdf.save());
//   //
//   //   // Exibe uma mensagem de sucesso
//   //   ScaffoldMessenger.of(context).showSnackBar(
//   //     SnackBar(content: Text('Recibo baixado com sucesso!')),
//   //   );
//   // }
//
//   // Função para adicionar a venda ao histórico (executada em 2º plano)
//   // void adicionarVendaAoHistorico(BuildContext context) async {
//   //   final historicoVendasProvider =
//   //   Provider.of<HistoricoVendasProvider>(context, listen: false);
//   //
//   //   // Acesse o cliente selecionado a partir do provider ou da forma que estiver sendo mantido
//   //   Cliente? clienteSelecionado = Provider.of<ClientProvider>(context, listen: false).clienteSelecionado;
//   //
//   //   // Criação da venda com base no cliente selecionado
//   //   historicoVendasProvider.adicionarVenda(
//   //     Venda(
//   //       cliente: clienteSelecionado, // Cliente obtido do provider
//   //       metodoPagamento: 'Cartão de Débito', // Substitua conforme necessário
//   //       valorTotal: valorTotal,
//   //       itens: [], // Adicione itens se necessário
//   //       id: DateTime.now().millisecondsSinceEpoch.toString(),
//   //       dataVenda: DateTime.now(),
//   //     ),
//   //   );
//   // }
// //   void adicionarVendaAoHistorico(BuildContext context) async {
// //     final historicoVendasProvider =
// //     Provider.of<HistoricoVendasProvider>(context, listen: false);
// //     final vendasProvider = Provider.of<VendasProvider>(context, listen: false);
// //
// //     // Acesse o cliente selecionado a partir do provider
// //     Cliente? clienteSelecionado =
// //         Provider.of<ClientProvider>(context, listen: false).clienteSelecionado;
// //
// //     if (clienteSelecionado == null) {
// //       // Exibe uma mensagem de erro caso o cliente não tenha sido selecionado
// //       ScaffoldMessenger.of(context).showSnackBar(
// //         SnackBar(content: Text('Erro: Nenhum cliente selecionado!')),
// //       );
// //       return; // Retorna sem adicionar a venda
// //     }
// // // Converte o carrinho para uma lista de ItemVenda
// //     List<ItemVenda> itensVenda = carrinho.map((item) {
// //
// //       return ItemVenda(
// //         produto: item['produto'].nome, // Acessando o nome do produto
// //         quantidade: item['quantidade'], // Acessando a quantidade
// //         precoTotal: item['produto'].preco * item['quantidade'], // Acessando o preço total
// //       );
// //     }).toList();
// //     // Criação da venda com base no cliente selecionado
// //     historicoVendasProvider.adicionarVenda(
// //       Venda(
// //         cliente: clienteSelecionado, // Cliente obtido do provider
// //         metodoPagamento: 'Cartão de Débito', // Substitua conforme necessário
// //         valorTotal: valorTotal,
// //         itens: List.from(itensVenda), // Adicione itens se necessário
// //         idVenda: DateTime.now().millisecondsSinceEpoch.toString(),
// //         dataVenda: DateTime.now(),
// //         // custoTotal: custoTotal,
// //       ),
// //     );
// //   }
//
//   // Função para adicionar a venda ao histórico (executada em 2º plano)
//
//   @override
//   _ConclusaoVendaScreenState createState() => _ConclusaoVendaScreenState();
// }
//
// class _ConclusaoVendaScreenState extends State<ConclusaoVendaScreen> {
//   bool _isVendaRegistrada = false; // Flag para registrar a venda apenas uma vez
//
//   @override
//   void initState() {
//     super.initState();
//     // Registrar a venda quando a tela é inicializada pela primeira vez
//     _registrarVendaAoIniciar();
//   }
//
//   Future<void> _registrarVendaAoIniciar() async {
//     if (!_isVendaRegistrada) {
//       try {
//         // Mapear o carrinho para o formato de itensVendidos
//         List<Map<String, dynamic>> itensVendidos = widget.carrinho.map((item) {
//           // Assumindo que item['produto'] é um objeto Produto ou tem os campos necessários
//           // e item['quantidade'] é a quantidade.
//           // Você pode precisar ajustar isso com base na estrutura exata do seu item['produto']
//           final produto = item['produto']; // Ex: Produto produto = item['produto'] as Produto;
//           final quantidade = item['quantidade'] as int;
//           final precoUnitario = (produto.precoPromocional ?? produto.preco) as double; // Usa preço promocional se disponível
//           final custo = produto.custo ?? 0.0;
//           return {
//             'produtoId': produto.id, // Supondo que seu objeto produto tenha um 'id'
//             'nomeProduto': produto.nome,
//             'quantidade': quantidade,
//             'precoUnitario': precoUnitario,
//             'precoTotalItem': precoUnitario * quantidade,
//             'Custo': custo,
//             'precoTotalCusto': custo * quantidade,
//           };
//         }).toList();
//
//         // Obter idCliente (exemplo, pode vir de um provider ou ser passado diretamente)
//         // Se você não tem um cliente selecionado, pode passar null ou um ID padrão.
//         String? clienteIdParaRegistro = widget.idCliente;
//         // Se você usa ClientProvider:
//         // final clientProvider = Provider.of<ClientProvider>(context, listen: false);
//         // clienteIdParaRegistro = clientProvider.clienteSelecionado?.id;
//
//
//         await registrarVendaNoFirestore(
//           idCliente: clienteIdParaRegistro ?? 'VENDA_SEM_CLIENTE',
//           itensVendidos: itensVendidos,
//           valorTotalVenda: widget.valorTotal,
//           metodoPagamento: widget.metodoPagamento,
//         );
//         await Provider.of<ProdutoProvider>(context, listen: false).carregarProdutos();
// // 🔄 Atualizar estoques dos produtos vendidos
//         final produtoProvider = Provider.of<ProdutoProvider>(context, listen: false);
//
//         for (var item in widget.carrinho) {
//           final produto = item['produto'];
//           final quantidadeVendida = item['quantidade'] as int;
//
//           await produtoProvider.atualizarEstoqueProduto(
//             produto.id,
//             quantidadeVendida,
//           );
//         }
//
//         setState(() {
//           _isVendaRegistrada = true;
//         });
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Venda registrada no sistema com sucesso!')),
//         );
//       } catch (e) {
//         print("Erro ao registrar venda na conclusão: $e");
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Erro ao registrar venda: ${e.toString()}')),
//         );
//         Provider.of<CarrinhoProvider>(context, listen: false).limparCarrinho();
// // Considere o que fazer se o registro falhar.
//         // Talvez impedir o usuário de prosseguir ou oferecer uma nova tentativa.
//       }
//     }
//   }
//
//   Future<void> registrarVendaNoFirestore({
//     required String idCliente, // Ou null se a venda não for vinculada a um cliente específico
//     required List<Map<String, dynamic>> itensVendidos, // Ex: [{'produtoId': 'xyz', 'nomeProduto': 'Produto A', 'quantidade': 2, 'precoUnitario': 10.00}]
//     required double valorTotalVenda,
//     required String metodoPagamento,
//     double? valorPago,
//     double? troco,
//     String? idTransacaoPagamento,
//     Map<String, dynamic>? detalhesEntrega, // Ex: {'tipo': 'Sedex', 'custo': 15.00, 'endereco': 'Rua X, 123'}
//     String? observacoes,
//   }) async {
//     FirebaseFirestore firestore = FirebaseFirestore.instance;
//
//     // Obtenha uma referência para a coleção 'vendas'.
//     // Se a coleção 'vendas' não existir, ela será criada automaticamente
//     // quando o primeiro documento for adicionado.
//     CollectionReference vendasRef = firestore.collection('vendas');
//     // Recupera dados do cliente
//
//     final cliente = widget.cliente;
//
//     // Dados adicionais
//     double valorLucroTotal = 0.0;
//     for (var item in itensVendidos) {
//       final precoCusto = item['precoCusto'] ?? 0.0;
//       final precoTotalItem = item['precoTotalItem'] ?? 0.0;
//       final lucroItem = precoTotalItem - (precoCusto * item['quantidade']);
//       valorLucroTotal += lucroItem;
//     }
//     try {
//       // Crie um mapa com os dados da venda
//       Map<String, dynamic> dadosVenda = {
//         'dataVenda': Timestamp.now(), // Data e hora atual
//         "idCliente": cliente.idCliente,
//         "nomeCliente": cliente?.nome ?? "Desconhecido",
//         "enderecoCliente": cliente?.endereco ?? "Não informado",
//         'metodoPagamento': widget.metodoPagamento,
//         'statusPagamento': 'pago',
//         'idTransacaoPagamento': idTransacaoPagamento,
//         'observacoes': observacoes,
//
//         "distanciaEntrega": detalhesEntrega?['distancia'] ?? 0.0,
//         "taxaEntrega": detalhesEntrega?['taxa'] ?? 0.0,
//         'detalhesEntrega': detalhesEntrega,
//
//         'valorTotal': widget.valorTotal,
//         "valorLucro": valorLucroTotal,
//         'itens': itensVendidos,
//         'valorPago': valorPago ?? valorTotalVenda,  // valor pago
//         'troco': troco ?? 0.0,
//       };
//
//       // Adicione um novo documento à coleção 'vendas'.
//       // O Firestore gerará automaticamente um ID único para este documento.
//       DocumentReference documentReference = await vendasRef.add(dadosVenda);
//
//       print('Venda registrada com sucesso! ID da Venda: ${documentReference.id}');
//
//       // Opcional: Se você precisar usar o ID da venda gerado para outras operações,
//       // você pode retorná-lo ou usá-lo aqui.
//
//     } catch (e) {
//       print('Erro ao registrar venda no Firestore: $e');
//       // Trate o erro apropriadamente (ex: log, mensagem para o usuário, tentativa de estorno se o pagamento passou mas o registro falhou)
//       throw e; // Re-lança a exceção se desejar que o chamador a trate
//     }
//   }
//
//   // Exemplo de como chamar a função:
//   void exemploDeUso() async {
//     List<Map<String, dynamic>> itens = [
//       {'produtoId': 'prod123', 'nomeProduto': 'Camiseta Legal', 'quantidade': 1, 'precoUnitario': 50.00},
//       {'produtoId': 'prod456', 'nomeProduto': 'Caneca Divertida', 'quantidade': 2, 'precoUnitario': 25.00},
//     ];
//
//     Map<String, dynamic> entrega = {
//       'tipo': 'Entrega Padrão',
//       'custo': 12.50,
//       'endereco': 'Rua Exemplo, 100, Cidade, UF'
//     };
//
//     await registrarVendaNoFirestore(
//       idCliente: 'cliente789',
//       itensVendidos: itens,
//       valorTotalVenda: 112.50, // (50*1) + (25*2) + 12.50
//       metodoPagamento: 'Cartão de Crédito',
//       idTransacaoPagamento: 'txn_abcdef123456',
//       detalhesEntrega: entrega,
//       observacoes: 'Cliente pediu para embrulhar para presente.',
//     );
//   }
//
//   void adicionarVendaAoHistorico(BuildContext context) async {
//     final historicoVendasProvider =
//     Provider.of<HistoricoVendasProvider>(context, listen: false);
//
//     Cliente clienteSelecionado = widget.cliente;
//
//     // Converte o carrinho para uma lista de ItemVenda
//     List<ItemVenda> itensVenda = widget.carrinho.map((item) {
//       return ItemVenda(
//         produto: item['produto'].nome,
//         quantidade: item['quantidade'],
//         precoTotal: item['produto'].preco * item['quantidade'],
//       );
//     }).toList();
//
//     // Criação da venda com base no cliente selecionado
//     historicoVendasProvider.adicionarVenda(
//       Venda(
//         cliente: clienteSelecionado,
//         metodoPagamento: widget.metodoPagamento,
//         valorTotal: widget.valorTotal,
//         itens: List.from(itensVenda),
//         idVenda: DateTime.now().millisecondsSinceEpoch.toString(),
//         dataVenda: DateTime.now(),
//       ),
//     );
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     // Chama a função para adicionar a venda ao histórico assim que a tela for exibida
//     adicionarVendaAoHistorico(context);
//
//
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Venda Concluída'),
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           crossAxisAlignment: CrossAxisAlignment.center,
//           children: [
//             Icon(
//               Icons.check_circle,
//               color: Colors.green,
//               size: 100,
//             ),
//             SizedBox(height: 20),
//             Text(
//               'Venda Concluída com Sucesso!',
//               style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
//             ),
//             SizedBox(height: 20),
//             Text(
//               'Valor Total: R\$ ${widget.valorTotal.toStringAsFixed(2)}',
//               style: TextStyle(fontSize: 20),
//             ),
//             SizedBox(height: 30),
//             ElevatedButton.icon(
//               onPressed: () {
//                 // Chama a função de geração de PDF
//                 // gerarRecibo(context);
//               },
//               icon: Icon(Icons.download),
//               label: Text('Baixar Recibo'),
//               style: ElevatedButton.styleFrom(
//                 minimumSize: Size(double.infinity, 50),
//                 textStyle: TextStyle(fontSize: 18),
//               ),
//             ),
//             SizedBox(height: 20),
//             ElevatedButton.icon(
//               onPressed: () {
//                 // Navigator.pushReplacementNamed(context, '/historico_vendas');
//                 // Navegar para a tela de vendas
//                 Navigator.popUntil(
//                     context, (route) => route.isFirst); // Voltar para a tela inicial
//               },
//               icon: Icon(Icons.shopping_bag),
//               label: Text('Nova Venda'),
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
//
//
//
//


import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../models/cliente.dart';
import '../models/produto.dart';
import '../providers/produto_provider.dart';

class ConclusaoVendaScreen extends StatefulWidget {
  final double valorTotal;
  final List<Map<String, dynamic>> carrinho; // Cada item: {produto, quantidade, precoUnitario, precoTotalItem}
  final String? idCliente;
  final String metodoPagamento;
  final Cliente cliente;
  final double? valorPago;
  final double? troco;
  final double desconto;
  final double valorEntrega;
  final String entregaSelecionada;
  final double saldoUsado;
  final Map<String, double>? pagamentosDetalhados;

  ConclusaoVendaScreen({
    required this.valorTotal,
    required this.carrinho,
    this.idCliente,
    required this.metodoPagamento,
    required this.cliente,
    this.valorPago,
    this.troco,
    required this.desconto,
    required this.valorEntrega,
    required this.entregaSelecionada,
    required this.saldoUsado,
    this.pagamentosDetalhados,
  });

  @override
  _ConclusaoVendaScreenState createState() => _ConclusaoVendaScreenState();
}

class _ConclusaoVendaScreenState extends State<ConclusaoVendaScreen> {
  bool _isRegistrado = false;

  @override
  void initState() {
    super.initState();
    print('=== Dados recebidos ConclusaoVendaScreen ===');
    print('Valor Total: ${widget.valorTotal}');
    print('Valor Entrega: ${widget.valorEntrega}');
    print('Entrega Selecionada: ${widget.entregaSelecionada}');
    print('Desconto: ${widget.desconto}');
    print('Método de Pagamento: ${widget.metodoPagamento}');
    print('Valor Pago: ${widget.valorPago ?? widget.valorTotal}');
    print('Troco: ${widget.troco ?? 0.0}');
    print('ID Cliente: ${widget.idCliente}');
    print('Cliente: ${widget.cliente.nome}, ${widget.cliente.endereco}, ${widget.cliente.celular}, Saldo: ${widget.cliente.saldo}');
    print('Carrinho:');
    for (var item in widget.carrinho) {
      final produto = item['produto'];
      final quantidade = item['quantidade'];
      print('- Produto: ${produto.nome}, Preço: ${produto.preco}, Estoque: ${produto.estoqueAtual}, Quantidade: $quantidade');
    }
    print('=== Debug Saldo na ConclusaoVendaScreen ===');
    print('Saldo recebido: ${widget.saldoUsado}');
    print('Saldo do cliente: ${widget.cliente.saldo}');

    _registrarVenda();
  }

  Future<void> _registrarVenda() async {
    if (_isRegistrado) return;

    try {
      List<Map<String, dynamic>> itensVendidos = [];

      for (var item in widget.carrinho) {
        final produto = item['produto'] as Produto;
        final quantidade = item['quantidade'] as int;
        final precoUnitario = (item['precoUnitario'] ?? produto.preco) as double;
        final precoTotalItem = (item['precoTotalItem'] ?? (precoUnitario * quantidade)) as double;

        itensVendidos.add({
          'produtoId': produto.id,
          'nomeProduto': produto.nome,
          'quantidade': quantidade,
          'precoUnitario': precoUnitario,
          'precoTotalItem': precoTotalItem,
          'custoUnitario': produto.custo,
          'custoTotal': produto.custo * quantidade,
        });
      }

      await FirebaseFirestore.instance.collection('vendas').add({
        'dataVenda': Timestamp.now(),
        'idCliente': widget.idCliente ?? 'VENDA_SEM_CLIENTE',
        'nomeCliente': widget.cliente.nome,
        'enderecoCliente': widget.cliente.endereco ?? '',
        'metodoPagamento': widget.metodoPagamento,
        'statusPagamento': 'pago',
        'itens': itensVendidos,
        'valorTotal': widget.valorTotal,
        // 'valorEntrega': valorEntrega,
        // 'tipoEntrega': tipoEntregaSelecionada,
        'valorPago': widget.valorPago ?? widget.valorTotal,
        'troco': widget.troco ?? 0.0,
        'desconto': widget.desconto,
        'saldoUsado': widget.saldoUsado,
        'valorEntrega': widget.valorEntrega,
        'entregaSelecionada': widget.entregaSelecionada,
        'pagamentosDetalhados': widget.pagamentosDetalhados ?? {},
      });
      final produtoProvider = Provider.of<ProdutoProvider>(context, listen: false);

      for (var item in widget.carrinho) {
        final produto = item['produto'] as Produto;
        final quantidade = item['quantidade'] as int;

        await produtoProvider.atualizarEstoqueProduto(
          produto.id!,
          quantidade,
        );
      }

      await _atualizarSaldoCliente();
      setState(() => _isRegistrado = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Venda registrada com sucesso!')),
      );
    } catch (e) {
      print('Erro ao registrar venda: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao registrar venda!')),
      );
    }
  }

  Future<void> _atualizarSaldoCliente() async {
    if (widget.saldoUsado <= 0) return; // Não precisa atualizar se não usou saldo
    try {
      double novoSaldo = widget.cliente.saldo - widget.saldoUsado;
      if (novoSaldo < 0) novoSaldo = 0.0;

      await FirebaseFirestore.instance
          .collection('clientes')
          .doc(widget.cliente.idCliente)
          .update({'saldo': novoSaldo});

      print('Saldo do cliente atualizado: R\$ $novoSaldo');
    } catch (e) {
      print('Erro ao atualizar saldo do cliente: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao atualizar saldo do cliente.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Venda Concluída')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 100),
            SizedBox(height: 20),
            Text(
              'Venda Concluída com Sucesso!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Text('Valor Total: R\$ ${widget.valorTotal.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 20)),

              SizedBox(height: 10),
              Text(
                'Desconto Aplicado: R\$ ${widget.desconto.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 18, color: Colors.red),
              ),
            SizedBox(height: 10),
            Text(
              'Saldo Utilizado: R\$ ${widget.saldoUsado.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 18, color: Colors.red),
            ),
            if (widget.pagamentosDetalhados != null && widget.pagamentosDetalhados!.isNotEmpty) ...[
              SizedBox(height: 20),
              Text('Pagamentos Detalhados:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ...widget.pagamentosDetalhados!.entries.map((e) => Text('${e.key}: R\$ ${e.value.toStringAsFixed(2)}')).toList(),
            ],

            if (widget.metodoPagamento.toLowerCase() == 'dinheiro') ...[
              SizedBox(height: 10),
              Text('Valor Pago: R\$ ${widget.valorPago?.toStringAsFixed(2) ?? widget.valorTotal.toStringAsFixed(2)}'),
              Text('Troco: R\$ ${widget.troco?.toStringAsFixed(2) ?? "0.00"}'),
                          ],
            SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
              child: Text('Nova Venda'),
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
