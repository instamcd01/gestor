// class Venda {
//   final String id;
//   final String clienteId;
//   final List<Map<String, dynamic>> produtos;
//   final DateTime data;
//   final double total;
//
//   Venda({
//     required this.id,
//     required this.clienteId,
//     required this.produtos,
//     required this.data,
//     required this.total,
//   });
// }


import 'package:gestor/models/cliente.dart';
import 'package:gestor/models/produto.dart';

class Venda {
  final Cliente cliente;
  final String idVenda;
  final DateTime dataVenda;
  final String metodoPagamento;
  final double valorTotal;
  final List<ItemVenda> itens;
  // final double custoTotal;

  Venda({
    required this.cliente,
    required this.idVenda,
    required this.dataVenda,
    required this.metodoPagamento,
    required this.valorTotal,
    // required this.custoTotal,
    required this.itens,
  });
}
class ItemVenda {
  final Produto produto;
   final int quantidade;
  final double precoTotal;

  ItemVenda({required this.produto, required this.quantidade, required this.precoTotal,});
}
// Definindo o método custoTotal
// double custoTotal() {
//   double custo = 0.0;
//   for (var produto in produto) {
//     custo += produto.custo; // Supondo que o ItemVenda tenha um campo 'custo'
//   }
//   return custo;
// }
// class Cliente {
//   final String nome;
//
//   Cliente({required this.nome});
// }



