import 'package:flutter/material.dart';

import '../models/produto.dart';
import '../screens/cadastro_produto_screen.dart';
import '../utils/produto_validators.dart';

/// Bottom sheet de busca de produto reutilizado em qualquer fluxo que
/// precise escolher um produto do catálogo (sugestão de compra,
/// conferência do espelho, etc). Quando [permiteCadastrarNovo] é true,
/// oferece "Cadastrar novo produto" pro caso do fornecedor mandar/vender
/// algo que ainda não existe no catálogo — abre `CadastroProdutoScreen` em
/// modo `retornarProdutoCriado`, que volta direto com o produto criado em
/// vez de desviar pra galeria de mídias.
class BuscaProdutoSheet extends StatefulWidget {
  final List<Produto> produtos;
  final bool permiteCadastrarNovo;

  const BuscaProdutoSheet({super.key, required this.produtos, this.permiteCadastrarNovo = true});

  @override
  State<BuscaProdutoSheet> createState() => _BuscaProdutoSheetState();
}

class _BuscaProdutoSheetState extends State<BuscaProdutoSheet> {
  final _controller = TextEditingController();

  Future<void> _cadastrarNovo() async {
    final termo = _controller.text.trim();
    final produto = await Navigator.push<Produto>(
      context,
      MaterialPageRoute(
        builder: (_) => CadastroProdutoScreen(
          retornarProdutoCriado: true,
          produtoInicial: termo.isEmpty
              ? null
              : Produto(
                  nome: termo,
                  preco: 0,
                  descricao: '',
                  categoria: '',
                  estoqueAtual: 0,
                  estoqueMinimo: 0,
                  imagemUrl: '',
                  codigoBarras: '',
                  custo: 0,
                ),
        ),
      ),
    );
    if (produto != null && mounted) Navigator.pop(context, produto);
  }

  @override
  Widget build(BuildContext context) {
    final termo = _controller.text.toLowerCase();
    final filtrados = termo.isEmpty
        ? widget.produtos.take(50).toList()
        : widget.produtos.where((p) => p.nome.toLowerCase().contains(termo)).take(50).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Buscar produto...', prefixIcon: Icon(Icons.search)),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (widget.permiteCadastrarNovo)
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('Cadastrar novo produto'),
                subtitle: const Text('Fornecedor vendeu algo que ainda não está no catálogo'),
                onTap: _cadastrarNovo,
              ),
            Expanded(
              child: ListView.builder(
                itemCount: filtrados.length,
                itemBuilder: (context, index) {
                  final produto = filtrados[index];
                  return ListTile(
                    title: Text(produto.nome),
                    subtitle: Text('R\$ ${ProdutoValidators.formatarMoeda(produto.custo)}'),
                    onTap: () => Navigator.pop(context, produto),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
