import 'package:flutter/material.dart';
import 'package:flutter_icons_null_safety/flutter_icons_null_safety.dart';
import 'package:gestor/screens/pagamento_link_screen.dart';
import 'package:gestor/screens/pagamento_outros_screen.dart';
import 'package:gestor/screens/pagamento_pix_screen.dart';
import 'package:provider/provider.dart';

import '../models/cliente.dart';
import '../providers/cliente_provider.dart';
import 'adicionar_cliente_screen.dart';
import 'pagamento_credito_screen.dart';
import 'pagamento_debito_screen.dart';
import 'pagamento_dinheiro_screen.dart';
import 'desconto_screen.dart';

class PagamentoScreen extends StatefulWidget {
  final double valorTotal;
  final String idVenda;
  final Cliente cliente;
  final List<Map<String, dynamic>> carrinho;
  final double desconto;
  final double valorEntrega;
  final String entregaSelecionada;
  // final double saldoUsado = 0.0;

  PagamentoScreen({
    required this.valorTotal,
    required this.idVenda,
    required this.carrinho,
    required this.cliente,
    required this.desconto,
    required this.valorEntrega,
    required this.entregaSelecionada,
  });

  @override
  _PagamentoScreenState createState() => _PagamentoScreenState();
}

class _PagamentoScreenState extends State<PagamentoScreen> {
  String metodoPagamentoSelecionado = '';
  final TextEditingController _saldoController = TextEditingController();
  late double desconto;
  late double valorTotal;
  late double valorEntrega;
  double saldoUsado = 0.0;

  @override
  void initState() {
        super.initState();
    desconto = widget.desconto;
    valorEntrega = widget.valorEntrega;
    valorTotal = widget.valorTotal;
  }
  @override
  void dispose() {
    _saldoController.dispose();
    super.dispose();
  }
  void aplicarSaldo(double valor) {
    final saldoDisponivel = widget.cliente.saldo;

    if (valor <= 0) return;
    if (valor > saldoDisponivel) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saldo insuficiente.')),
      );
      return;
    }
    if (valor > widget.valorTotal) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saldo não pode ser maior que o valor total.')),
      );
      return;
    }

    setState(() {
      saldoUsado = valor;
      valorTotal = widget.valorTotal - saldoUsado - desconto + valorEntrega;
    });
  }

  void limparSaldo() {
    setState(() {
     saldoUsado = 0.0;
      valorTotal = widget.valorTotal - desconto + valorEntrega;
      _saldoController.clear();
    });
  }


  void selecionarMetodoPagamento(String metodo) {
    setState(() {
      metodoPagamentoSelecionado = metodo;
    });
  }

  void aplicarDesconto() async {
    final novoValorComDesconto = await Navigator.push<double>(
      context,
      MaterialPageRoute(
        builder: (context) => DescontoScreen(
          valorTotal: valorTotal,
          // onDescontoAplicado: (novoValor) {
          //   Navigator.pop(context, novoValor);
          // },
        ),
      ),
    );

    if (novoValorComDesconto != null && novoValorComDesconto < valorTotal) {
      setState(() {
        desconto = valorTotal - novoValorComDesconto;
        valorTotal = novoValorComDesconto;
      });
    }
  }

  void limparDesconto() {
    setState(() {
      desconto = 0.0;
      valorTotal = widget.valorTotal;
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

    valorTotal = double.parse(valorTotal.toStringAsFixed(2));

    // 🔹 LOG COMPLETO DOS DADOS
    print('=== Dados enviados para tela de pagamento ===');
    print('Método de pagamento selecionado: $metodoPagamentoSelecionado');
    print('Valor Total: $valorTotal');
    print('Valor Entrega: $valorEntrega');
    print('Desconto: $desconto');
    print('Cliente: ${widget.cliente.nome}, ${widget.cliente.endereco}, ${widget.cliente.celular}, Saldo: ${widget.cliente.saldo}');
    print('EntregaSelecionada recebida: ${widget.entregaSelecionada}');
    print('Saldo usado: $saldoUsado');
    print('Carrinho:');
    for (var item in widget.carrinho) {
      final produto = item['produto'];
      final quantidade = item['quantidade'];
      print('- Produto: ${produto.nome}, Preço: ${produto.preco}, Estoque: ${produto.estoqueAtual}, Quantidade: $quantidade');
    }
    print('=== Debug Saldo ===');
    print('Cliente: ${widget.cliente.nome}');
    print('Saldo disponível: ${widget.cliente.saldo}');
    print('Saldo a usar: $saldoUsado');
   if (metodoPagamentoSelecionado == 'Dinheiro') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PagamentoDinheiroScreen(
            valorTotal: valorTotal,
            carrinho: widget.carrinho,
            metodoPagamento: metodoPagamentoSelecionado,
            cliente: widget.cliente,
            desconto: desconto,
            valorEntrega: widget.valorEntrega,          // ⬅️ Novo
            entregaSelecionada: widget.entregaSelecionada,
            saldoUsado: saldoUsado,
          ),
        ),
      );
    } else if (metodoPagamentoSelecionado == 'Cartão de Débito') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PagamentoCartaoDebitoScreen(
            valorTotal: valorTotal,
            carrinho: widget.carrinho,
            metodoPagamento: metodoPagamentoSelecionado,
            cliente: widget.cliente,
            desconto: desconto,
            valorEntrega: widget.valorEntrega,          // ⬅️ Novo
            entregaSelecionada: widget.entregaSelecionada,
            saldoUsado: saldoUsado,
          ),
        ),
      );
    } else if (metodoPagamentoSelecionado == 'Cartão de Crédito') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PagamentoCartaoCreditoScreen(
            valorTotal: valorTotal,
            carrinho: widget.carrinho,
            metodoPagamento: metodoPagamentoSelecionado,
            cliente: widget.cliente,
            desconto: desconto,
            valorEntrega: widget.valorEntrega,          // ⬅️ Novo
            entregaSelecionada: widget.entregaSelecionada,
            saldoUsado: saldoUsado,
          ),
        ),
      );
    }
   else if (metodoPagamentoSelecionado == 'Pix') {
     Navigator.push(
       context,
       MaterialPageRoute(
         builder: (context) => PagamentoPixScreen(
           valorTotal: valorTotal,
           carrinho: widget.carrinho,
           metodoPagamento: metodoPagamentoSelecionado,
           cliente: widget.cliente,
           desconto: desconto,
           valorEntrega: widget.valorEntrega,
           entregaSelecionada: widget.entregaSelecionada,
           saldoUsado: saldoUsado,
         ),
       ),
     );
   }
   else if (metodoPagamentoSelecionado == 'Link de Pagamento') {
     Navigator.push(
       context,
       MaterialPageRoute(
         builder: (context) => PagamentoLinkScreen(
           valorTotal: valorTotal,
           carrinho: widget.carrinho,
           metodoPagamento: metodoPagamentoSelecionado,
           cliente: widget.cliente,
           desconto: desconto,
           valorEntrega: widget.valorEntrega,
           entregaSelecionada: widget.entregaSelecionada,
           saldoUsado: saldoUsado,
         ),
       ),
     );
   }
   else if (metodoPagamentoSelecionado == 'Outros') {
     Navigator.push(
       context,
       MaterialPageRoute(
         builder: (_) => PagamentoOutrosScreen(
           valorTotal: valorTotal,
           carrinho: widget.carrinho,
           cliente: widget.cliente,
           desconto: desconto,
           valorEntrega: widget.valorEntrega,
           entregaSelecionada: widget.entregaSelecionada,
           saldoUsado: saldoUsado,
         ),
       ),
     );
   }

  }

  @override
  Widget build(BuildContext context) {
    final cliente = widget.cliente;

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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 📌 DADOS DO CLIENTE
            Text(
              'Dados do Cliente',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Card(
              elevation: 2,
              margin: EdgeInsets.symmetric(vertical: 8),
              child: ListTile(
                title: Text(cliente.nome),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Celular: ${cliente.celular}'),
                    Text('Endereço: ${cliente.endereco}'),
                    Text('Saldo: R\$ ${cliente.saldo.toStringAsFixed(2)}'),
                  ],
                ),
              ),
            ),

            // 📦 RESUMO DA COMPRA
            SizedBox(height: 16),
            Text(
              'Resumo da Compra',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            ...widget.carrinho.map((item) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    Text('${item['quantidade']} x ', style: TextStyle(fontSize: 16)),
                    Expanded(
                      child: Text(
                        item['produto'].nome,
                        style: TextStyle(fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(' - R\$ ${item['produto'].preco}', style: TextStyle(fontSize: 16)),
                  ],
                ),
              );
            }).toList(),

            SizedBox(height: 10),

            // 🚚 Valor da Entrega
            Row(
              children: [
                Text(
                  'Entrega:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                SizedBox(width: 8),
                Text(
                  valorEntrega == 0 ? 'Frete Grátis' : 'R\$ ${valorEntrega.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 16,
                    color: valorEntrega == 0 ? Colors.green : Colors.black,
                    fontWeight: valorEntrega == 0 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),

            // 🎯 Desconto (se houver)
            if (desconto > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Row(
                  children: [
                    Text(
                      'Desconto:',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    SizedBox(width: 8),
                    Text(
                      '- R\$ ${desconto.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),

            SizedBox(height: 20),
            Center(
              child: Text(
                'Valor Total: R\$ ${valorTotal.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(height: 10),
            if (desconto == 0)
            ElevatedButton.icon(
              onPressed: aplicarDesconto,
              icon: Icon(Icons.percent),
              label: Text('Aplicar Desconto'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                minimumSize: Size(double.infinity, 50),
              ),
            ),
            if (desconto > 0)
              ElevatedButton.icon(
                onPressed: limparDesconto,
                icon: Icon(Icons.delete_forever),
                label: Text('Remover Desconto'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  minimumSize: Size(double.infinity, 50),
                ),
              ),

            SizedBox(height: 20),

            // ✅ CAMPO PARA USAR SALDO
            Text(
              'Usar Saldo do Cliente',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _saldoController,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Digite o valor do saldo a usar',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () {
                    final valor = double.tryParse(_saldoController.text) ?? 0.0;
                    aplicarSaldo(valor);
                  },
                  child: Text('Aplicar'),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () => aplicarSaldo(cliente.saldo),
                  child: Text('Usar Todo Saldo'),
                ),
                SizedBox(width: 10),
                if (saldoUsado > 0)
                  ElevatedButton(
                    onPressed: limparSaldo,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: Text('Remover Saldo'),
                  ),
              ],
            ),

            if (saldoUsado > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'Saldo aplicado: R\$ ${saldoUsado.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 16, color: Colors.green, fontWeight: FontWeight.w500),
                ),
              ),
            SizedBox(height: 30),

            // 💳 OPÇÕES DE PAGAMENTO
            Text(
              'Selecione o Método de Pagamento',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
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
                  {'metodo': 'Pix', 'icone': Icons.pix},
                  {'metodo': 'Link de Pagamento', 'icone': Icons.link},
                  {'metodo': 'Outros', 'icone': Icons.more_horiz},
                ];

                String metodo = opcoesPagamento[index]['metodo']!;
                IconData icone = opcoesPagamento[index]['icone']!;

                return GestureDetector(
                  onTap: () => selecionarMetodoPagamento(metodo),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icone, size: 40, color: Colors.blue),
                      SizedBox(height: 8),
                      Text(metodo, textAlign: TextAlign.center),
                    ],
                  ),
                );
              },
            ),

            SizedBox(height: 30),
            ElevatedButton(
              onPressed: metodoPagamentoSelecionado.isEmpty ? null : navegarParaTelaPagamento,
              child: Text('Avançar'),
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
