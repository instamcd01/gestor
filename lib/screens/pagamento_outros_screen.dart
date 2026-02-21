// import 'package:flutter/material.dart';
// import '../models/cliente.dart';
// import '../models/produto.dart';
// import 'conclusao_venda_screen.dart';
//
// class PagamentoOutrosScreen extends StatefulWidget {
//   final double valorTotal;
//   final List<Map<String, dynamic>> carrinho;
//   final Cliente cliente;
//   final double desconto;
//   final double valorEntrega;
//   final String entregaSelecionada;
//   final double saldoUsado;
//
//   PagamentoOutrosScreen({
//     required this.valorTotal,
//     required this.carrinho,
//     required this.cliente,
//     required this.desconto,
//     required this.valorEntrega,
//     required this.entregaSelecionada,
//     this.saldoUsado = 0.0,
//   });
//
//   @override
//   _PagamentoOutrosScreenState createState() => _PagamentoOutrosScreenState();
// }
//
// class _PagamentoOutrosScreenState extends State<PagamentoOutrosScreen> {
//   Map<String, double> pagamentos = {}; // chave: método, valor: quanto pagar
//   double totalPago = 0.0;
//
//   final TextEditingController _valorController = TextEditingController();
//   String metodoSelecionado = 'Dinheiro';
//
//   final List<String> metodosDisponiveis = [
//     'Dinheiro',
//     'Cartão de Débito',
//     'Cartão de Crédito',
//     'Pix',
//     'Link de Pagamento',
//     'Saldo Cliente',
//   ];
//
//   double get valorRestante {
//     double restante = widget.valorTotal - totalPago;
//     print("🔍 [LOG] Cálculo valorRestante -> valorTotal: ${widget.valorTotal}, totalPago: $totalPago, restante: $restante");
//     return restante < 0 ? 0.0 : restante;
//   }
//
//   void adicionarPagamento() {
//     final valor = double.tryParse(_valorController.text) ?? 0.0;
//     print("🔍 [LOG] Tentando adicionar pagamento -> método: $metodoSelecionado, valor digitado: $valor");
//
//     if (valor <= 0) {
//       print("⚠️ [LOG] Valor inválido (<=0), não será adicionado.");
//       return;
//     }
//     if (valor > valorRestante) {
//       print("⚠️ [LOG] Valor excede restante. valor: $valor, restante: $valorRestante");
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('Valor excede o restante a pagar.')),
//       );
//       return;
//     }
//
//     setState(() {
//       pagamentos[metodoSelecionado] = (pagamentos[metodoSelecionado] ?? 0.0) + valor;
//       totalPago += valor;
//       print("✅ [LOG] Pagamento adicionado -> $metodoSelecionado: $valor | TotalPago atualizado: $totalPago");
//       print("📊 [LOG] Lista de pagamentos: $pagamentos");
//       _valorController.clear();
//     });
//   }
//
//   void removerPagamento(String metodo) {
//     print("🔍 [LOG] Removendo pagamento -> método: $metodo, valor: ${pagamentos[metodo]}");
//     setState(() {
//       totalPago -= pagamentos[metodo]!;
//       pagamentos.remove(metodo);
//       print("✅ [LOG] Pagamento removido. TotalPago atualizado: $totalPago");
//       print("📊 [LOG] Lista de pagamentos: $pagamentos");
//     });
//   }
//
//   void finalizarPagamento() {
//     print("🔍 [LOG] Finalizando pagamento...");
//     print("➡️ valorTotal: ${widget.valorTotal}, totalPago: $totalPago, saldoUsado: ${widget.saldoUsado}, desconto: ${widget.desconto}, entrega: ${widget.valorEntrega}");
//
//     if (totalPago < widget.valorTotal) {
//       print("❌ [LOG] Pagamento incompleto! totalPago: $totalPago, necessário: ${widget.valorTotal}");
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('Pagamento incompleto.')),
//       );
//       return;
//     }
//
//     print("✅ [LOG] Pagamento concluído! Redirecionando para ConclusaoVendaScreen...");
//     Navigator.pushReplacement(
//       context,
//       MaterialPageRoute(
//         builder: (_) => ConclusaoVendaScreen(
//           valorTotal: widget.valorTotal,
//           carrinho: widget.carrinho,
//           cliente: widget.cliente,
//           metodoPagamento: 'Outros', // indicando pagamento dividido
//           desconto: widget.desconto,
//           valorEntrega: widget.valorEntrega,
//           entregaSelecionada: widget.entregaSelecionada,
//           saldoUsado: widget.saldoUsado,
//           pagamentosDetalhados: pagamentos,
//         ),
//       ),
//     );
//   }
//
//   @override
//   void dispose() {
//     _valorController.dispose();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     print("🔍 [LOG] Build chamado -> valorTotal: ${widget.valorTotal}, desconto: ${widget.desconto}, entrega: ${widget.valorEntrega}, saldoUsado: ${widget.saldoUsado}");
//     return Scaffold(
//       appBar: AppBar(title: Text('Pagamento Outros')),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Text('Cliente: ${widget.cliente.nome}', style: TextStyle(fontSize: 18)),
//             SizedBox(height: 10),
//             Text('Valor restante a pagar: R\$ ${valorRestante.toStringAsFixed(2)}',
//                 style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
//             SizedBox(height: 20),
//
//             DropdownButtonFormField<String>(
//               value: metodoSelecionado,
//               items: metodosDisponiveis
//                   .map((m) => DropdownMenuItem(value: m, child: Text(m)))
//                   .toList(),
//               onChanged: (valor) => setState(() => metodoSelecionado = valor!),
//               decoration: InputDecoration(labelText: 'Selecionar método', border: OutlineInputBorder()),
//             ),
//             SizedBox(height: 8),
//             Row(
//               children: [
//                 Expanded(
//                   child: TextField(
//                     controller: _valorController,
//                     keyboardType: TextInputType.numberWithOptions(decimal: true),
//                     decoration: InputDecoration(
//                       labelText: 'Valor a pagar',
//                       border: OutlineInputBorder(),
//                     ),
//                   ),
//                 ),
//                 SizedBox(width: 10),
//                 ElevatedButton(onPressed: adicionarPagamento, child: Text('Adicionar')),
//               ],
//             ),
//             SizedBox(height: 20),
//             Text('Pagamentos adicionados:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
//             ...pagamentos.entries.map((e) {
//               return ListTile(
//                 title: Text('${e.key}: R\$ ${e.value.toStringAsFixed(2)}'),
//                 trailing: IconButton(
//                   icon: Icon(Icons.delete, color: Colors.red),
//                   onPressed: () => removerPagamento(e.key),
//                 ),
//               );
//             }).toList(),
//             Spacer(),
//             Center(
//               child: ElevatedButton(
//                 onPressed: valorRestante == 0 ? finalizarPagamento : null,
//                 child: Text('Finalizar Pagamento'),
//                 style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 50)),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

import 'package:flutter/material.dart';
import '../models/cliente.dart';
import 'conclusao_venda_screen.dart';

class PagamentoOutrosScreen extends StatefulWidget {
  final double valorTotal;
  final List<Map<String, dynamic>> carrinho;
  final Cliente cliente;
  final double desconto;
  final double valorEntrega;
  final String entregaSelecionada;
  final double saldoUsado;

  PagamentoOutrosScreen({
    required this.valorTotal,
    required this.carrinho,
    required this.cliente,
    required this.desconto,
    required this.valorEntrega,
    required this.entregaSelecionada,
    this.saldoUsado = 0.0,
  });

  @override
  _PagamentoOutrosScreenState createState() => _PagamentoOutrosScreenState();
}

class _PagamentoOutrosScreenState extends State<PagamentoOutrosScreen> {
  Map<String, double> pagamentos = {}; // chave: método, valor: quanto pagar
  double totalPago = 0.0;

  final TextEditingController _valorController = TextEditingController();
  String metodoSelecionado = 'Dinheiro';

  final List<String> metodosDisponiveis = [
    'Dinheiro',
    'Cartão de Débito',
    'Cartão de Crédito',
    'Pix',
    'Link de Pagamento',
    'Saldo Cliente',
  ];

  /// Função auxiliar para arredondar valores monetários
  double arredondar(double valor) {
    return double.parse(valor.toStringAsFixed(2));
  }

  double get valorRestante {
    double restante = arredondar(widget.valorTotal - totalPago);
    return restante < 0 ? 0.0 : restante;
  }

  void adicionarPagamento() {
    final valor = double.tryParse(_valorController.text) ?? 0.0;
    if (valor <= 0) return;
    if (valor > valorRestante) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Valor excede o restante a pagar.')),
      );
      return;
    }
    setState(() {
      pagamentos[metodoSelecionado] =
          arredondar((pagamentos[metodoSelecionado] ?? 0.0) + valor);
      totalPago = arredondar(totalPago + valor);
      _valorController.clear();
    });

    print("🔍 [LOG] Pagamento adicionado -> $metodoSelecionado: R\$ $valor");
    print("🔍 [LOG] TotalPago: $totalPago / ValorTotal: ${widget.valorTotal}");
  }

  void removerPagamento(String metodo) {
    setState(() {
      totalPago = arredondar(totalPago - pagamentos[metodo]!);
      pagamentos.remove(metodo);
    });

    print("🔍 [LOG] Pagamento removido -> $metodo");
    print("🔍 [LOG] TotalPago: $totalPago / ValorTotal: ${widget.valorTotal}");
  }

  void finalizarPagamento() {
    print("🔍 [LOG] Finalizar -> TotalPago: $totalPago | ValorTotal: ${widget.valorTotal}");

    if (arredondar(totalPago) < arredondar(widget.valorTotal)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pagamento incompleto.')),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ConclusaoVendaScreen(
          valorTotal: arredondar(widget.valorTotal),
          carrinho: widget.carrinho,
          cliente: widget.cliente,
          metodoPagamento: 'Outros', // indicando pagamento dividido
          desconto: widget.desconto,
          valorEntrega: widget.valorEntrega,
          entregaSelecionada: widget.entregaSelecionada,
          saldoUsado: widget.saldoUsado,
          pagamentosDetalhados: pagamentos,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _valorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print("🔍 [LOG] ValorTotal recebido na tela: ${widget.valorTotal}");

    return Scaffold(
      appBar: AppBar(title: Text('Pagamento Outros')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cliente: ${widget.cliente.nome}', style: TextStyle(fontSize: 18)),
            SizedBox(height: 10),
            Text(
              'Valor restante a pagar: R\$ ${valorRestante.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),

            DropdownButtonFormField<String>(
              value: metodoSelecionado,
              items: metodosDisponiveis
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (valor) => setState(() => metodoSelecionado = valor!),
              decoration: InputDecoration(
                labelText: 'Selecionar método',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _valorController,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Valor a pagar',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                ElevatedButton(onPressed: adicionarPagamento, child: Text('Adicionar')),
              ],
            ),
            SizedBox(height: 20),
            Text('Pagamentos adicionados:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ...pagamentos.entries.map((e) {
              return ListTile(
                title: Text('${e.key}: R\$ ${e.value.toStringAsFixed(2)}'),
                trailing: IconButton(
                  icon: Icon(Icons.delete, color: Colors.red),
                  onPressed: () => removerPagamento(e.key),
                ),
              );
            }).toList(),
            Spacer(),
            Center(
              child: ElevatedButton(
                onPressed: valorRestante == 0 ? finalizarPagamento : null,
                child: Text('Finalizar Pagamento'),
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 50),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
