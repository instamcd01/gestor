import 'package:flutter/material.dart';
import 'package:flutter_icons_null_safety/flutter_icons_null_safety.dart';
import 'package:gestor/screens/pagamento_credito_screen.dart';
import 'package:gestor/screens/pagamento_debito_screen.dart';
import 'package:provider/provider.dart';
import '../providers/cliente_provider.dart';
import 'cadastrar_cliente_screen.dart';
import 'pagamento_dinheiro_screen.dart';

class PagamentoScreen extends StatefulWidget {
  final double valorTotal;

  PagamentoScreen({required this.valorTotal});

  @override
  _PagamentoScreenState createState() => _PagamentoScreenState();
}

class _PagamentoScreenState extends State<PagamentoScreen> {
  String metodoPagamentoSelecionado = '';
  String? clienteSelecionado;

  // Função para alterar o método de pagamento selecionado
  void selecionarMetodoPagamento(String metodo) {
    setState(() {
      metodoPagamentoSelecionado = metodo;
    });
  }

  // Função para navegar para a tela de cadastro de cliente
  void cadastrarNovoCliente() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CadastrarClienteScreen(),
      ),
    );
  }

  // Função para navegar para a tela de pagamento correspondente
  void navegarParaTelaPagamento() {
    if (metodoPagamentoSelecionado == 'Dinheiro') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PagamentoDinheiroScreen(valorTotal: widget.valorTotal),
        ),
      );
    } else if (metodoPagamentoSelecionado == 'Cartão de Débito') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PagamentoCartaoDebitoScreen(valorTotal: widget.valorTotal),
        ),
      );
    } else if (metodoPagamentoSelecionado == 'Cartão de Crédito') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PagamentoCartaoCreditoScreen(valorTotal: widget.valorTotal),
        ),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final clientProvider = Provider.of<ClientProvider>(context);
    clienteSelecionado = clientProvider.clienteSelecionado; // Obtém o cliente selecionado do provider
  }

  @override
  Widget build(BuildContext context) {
    final clientProvider = Provider.of<ClientProvider>(context);
    final clientes = clientProvider.clientes; // Acessando a lista de clientes

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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            // Campo para selecionar o cliente
            Padding(
              padding: const EdgeInsets.only(bottom: 20.0),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blue),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String>(
                  value: clienteSelecionado,
                  hint: Text('Selecione um Cliente'),
                  isExpanded: true,
                  items: clientes.map((cliente) {
                    return DropdownMenuItem<String>(
                      value: cliente,
                      child: Text(cliente),
                    );
                  }).toList(),
                  onChanged: (novoCliente) {
                    setState(() {
                      clienteSelecionado = novoCliente;
                      clientProvider.setClienteSelecionado(novoCliente!); // Atualiza o cliente selecionado no provider
                    });
                  },
                ),
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
                      Icon(icone, size: 40, color: Colors.blue), // Ícone do método
                      SizedBox(height: 8),
                      Text(metodo), // Nome do método de pagamento
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
      ),
    );
  }
}
