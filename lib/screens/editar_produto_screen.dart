// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import '../models/produto.dart';
// import '../providers/produto_provider.dart';
//
// class EditarProdutoScreen extends StatefulWidget {
//   final Produto produto;
//
//   EditarProdutoScreen({required this.produto});
//
//   @override
//   _EditarProdutoScreenState createState() => _EditarProdutoScreenState();
// }
//
// class _EditarProdutoScreenState extends State<EditarProdutoScreen> {
//   late TextEditingController _nomeController;
//   late TextEditingController _categoriaController;
//   late TextEditingController _precoController;
//   late TextEditingController _precoPromocionalController;
//   late TextEditingController _precoIfoodController;
//   late TextEditingController _custoController;
//   late TextEditingController _validadeController;
//   late TextEditingController _descricaoController;
//   late TextEditingController _codigoBarrasController;
//   late TextEditingController _imagemUrlController;
//   late TextEditingController _markupController;
//   late TextEditingController _lucroController;
//   late TextEditingController _empresaController;
//   late TextEditingController _precoConcorrenciaController;
//   late TextEditingController _estoqueAtualController;
//   late TextEditingController _estoqueMinimoController;
//   late TextEditingController _destacarController;
//   late TextEditingController _exibirNoCatalogoController;
//   late TextEditingController _idController;
//
//   @override
//   void initState() {
//     super.initState();
//     _nomeController = TextEditingController(text: widget.produto.nome);
//     _categoriaController = TextEditingController(text: widget.produto.categoria);
//     _precoController = TextEditingController(text: widget.produto.preco.toString());
//     _precoPromocionalController = TextEditingController(text: widget.produto.precoPromocional.toString());
//     _precoIfoodController = TextEditingController(text: widget.produto.precoIfood.toString());
//     _custoController = TextEditingController(text: widget.produto.custo.toString());
//     _validadeController = TextEditingController(text: widget.produto.validade);
//     _descricaoController = TextEditingController(text: widget.produto.descricao);
//     _codigoBarrasController = TextEditingController(text: widget.produto.codigoBarras);
//     _imagemUrlController = TextEditingController(text: widget.produto.imagemUrl);
//     _markupController = TextEditingController(text: widget.produto.markup.toString());
//     _lucroController = TextEditingController(text: widget.produto.lucro.toString());
//     _empresaController = TextEditingController(text: widget.produto.empresa);
//     _precoConcorrenciaController = TextEditingController(text: widget.produto.precoConcorrencia.toString());
//     _estoqueAtualController = TextEditingController(text: widget.produto.estoqueAtual.toString());
//     _estoqueMinimoController = TextEditingController(text: widget.produto.estoqueMinimo.toString());
//     _destacarController = TextEditingController(text: widget.produto.destacar.toString());
//     _exibirNoCatalogoController = TextEditingController(text: widget.produto.exibirNoCatalogo.toString());
//     _idController = TextEditingController(text: widget.produto.id.toString());
//   }
//
//   @override
//   void dispose() {
//     _nomeController.dispose();
//     _categoriaController.dispose();
//     _precoController.dispose();
//     _precoPromocionalController.dispose();
//     _precoIfoodController.dispose();
//     _custoController.dispose();
//     _validadeController.dispose();
//     _descricaoController.dispose();
//     _codigoBarrasController.dispose();
//     _imagemUrlController.dispose();
//     _markupController.dispose();
//     _lucroController.dispose();
//     _empresaController.dispose();
//     _precoConcorrenciaController.dispose();
//     _estoqueAtualController.dispose();
//     _estoqueMinimoController.dispose();
//     _destacarController.dispose();
//     _exibirNoCatalogoController.dispose();
//     _idController.dispose();
//     super.dispose();
//   }
//
//   void _salvarEdicao() {
//     // Salvar as alterações no produto
//     widget.produto.id = _idController.text;
//     widget.produto.nome = _nomeController.text;
//     widget.produto.categoria = _categoriaController.text;
//     widget.produto.preco = double.tryParse(_precoController.text) ?? 0.0;
//     widget.produto.precoPromocional = double.tryParse(_precoPromocionalController.text) ?? 0.0;
//     widget.produto.precoIfood = double.tryParse(_precoIfoodController.text) ?? 0.0;
//     widget.produto.custo = double.tryParse(_custoController.text) ?? 0.0;
//     widget.produto.validade = _validadeController.text;
//     widget.produto.descricao = _descricaoController.text;
//     widget.produto.codigoBarras = _codigoBarrasController.text;
//     widget.produto.imagemUrl = _imagemUrlController.text;
//     widget.produto.markup = double.tryParse(_markupController.text) ?? 0.0;
//     widget.produto.lucro = double.tryParse(_lucroController.text) ?? 0.0;
//     widget.produto.empresa = _empresaController.text;
//     widget.produto.precoConcorrencia = double.tryParse(_precoConcorrenciaController.text) ?? 0.0;
//     widget.produto.estoqueAtual = int.tryParse(_estoqueAtualController.text) ?? 0;
//     widget.produto.estoqueMinimo = int.tryParse(_estoqueMinimoController.text) ?? 0;
//     widget.produto.destacar = _destacarController.text.toLowerCase() == 'true';
//     widget.produto.exibirNoCatalogo = _exibirNoCatalogoController.text.toLowerCase() == 'true';
//
//
//     // Atualiza o produto no provider
//     final produtoProvider = Provider.of<ProdutoProvider>(context, listen: false);
//     produtoProvider.atualizarProduto(widget.produto); // Atualiza o produto no provider
//
//     // Após salvar, retornar para a tela anterior
//     Navigator.pop(context);
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Editar Produto'),
//         actions: [
//           IconButton(
//             icon: Icon(Icons.save),
//             onPressed: _salvarEdicao,
//           ),
//         ],
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: SingleChildScrollView(
//           child: Column(
//             children: [
//               TextField(
//                 controller: _idController,
//                 decoration: InputDecoration(labelText: 'Id'),
//               ),
//               TextField(
//                 controller: _nomeController,
//                 decoration: InputDecoration(labelText: 'Nome'),
//               ),
//               TextField(
//                 controller: _categoriaController,
//                 decoration: InputDecoration(labelText: 'Categoria'),
//               ),
//               TextField(
//                 controller: _precoController,
//                 decoration: InputDecoration(labelText: 'Preço'),
//                 keyboardType: TextInputType.number,
//               ),
//               TextField(
//                 controller: _precoPromocionalController,
//                 decoration: InputDecoration(labelText: 'Preço Promocional'),
//                 keyboardType: TextInputType.number,
//               ),
//               TextField(
//                 controller: _precoIfoodController,
//                 decoration: InputDecoration(labelText: 'Preço Ifood'),
//                 keyboardType: TextInputType.number,
//               ),
//               TextField(
//                 controller: _custoController,
//                 decoration: InputDecoration(labelText: 'Custo'),
//                 keyboardType: TextInputType.number,
//               ),
//               TextField(
//                 controller: _validadeController,
//                 decoration: InputDecoration(labelText: 'Validade'),
//               ),
//               TextField(
//                 controller: _descricaoController,
//                 decoration: InputDecoration(labelText: 'Descrição'),
//               ),
//               TextField(
//                 controller: _codigoBarrasController,
//                 decoration: InputDecoration(labelText: 'Código de Barras'),
//               ),
//               TextField(
//                 controller: _imagemUrlController,
//                 decoration: InputDecoration(labelText: 'Imagem URL'),
//               ),
//               TextField(
//                 controller: _markupController,
//                 decoration: InputDecoration(labelText: 'Markup'),
//               ),
//               TextField(
//                 controller: _lucroController,
//                 decoration: InputDecoration(labelText: 'Lucro'),
//               ),
//               TextField(
//                 controller: _empresaController,
//                 decoration: InputDecoration(labelText: 'Empresa'),
//               ),
//               TextField(
//                 controller: _precoConcorrenciaController,
//                 decoration: InputDecoration(labelText: 'Preço Concorrência'),
//                 keyboardType: TextInputType.number,
//               ),
//               TextField(
//                 controller: _estoqueAtualController,
//                 decoration: InputDecoration(labelText: 'Estoque Atual'),
//                 keyboardType: TextInputType.number,
//               ),
//               TextField(
//                 controller: _estoqueMinimoController,
//                 decoration: InputDecoration(labelText: 'Estoque Mínimo'),
//                 keyboardType: TextInputType.number,
//               ),
//               TextField(
//                 controller: _destacarController,
//                 decoration: InputDecoration(labelText: 'Destacar (true/false)'),
//               ),
//               TextField(
//                 controller: _exibirNoCatalogoController,
//                 decoration: InputDecoration(labelText: 'Exibir no Catálogo (true/false)'),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/produto.dart';
import '../providers/produto_provider.dart';

class EditarProdutoScreen extends StatefulWidget {
  final Produto produto;

  EditarProdutoScreen({required this.produto});

  @override
  _EditarProdutoScreenState createState() => _EditarProdutoScreenState();
}

class _EditarProdutoScreenState extends State<EditarProdutoScreen> {
  late TextEditingController _nomeController;
  late TextEditingController _categoriaController;
  late TextEditingController _precoController;
  late TextEditingController _descricaoController;
  late TextEditingController _estoqueAtualController;
  late TextEditingController _precoPromocionalController;
  late TextEditingController _estoqueMinimoController;
  late TextEditingController _imagemUrlController;
  late TextEditingController _codigoBarrasController;
  late TextEditingController _custoController;
  late TextEditingController _destacarController;
  late TextEditingController _empresaController;
  late TextEditingController _exibirNoCatalogoController;
  late TextEditingController _lucroController;
  late TextEditingController _markupController;
  late TextEditingController _precoConcorrenciaController;
  late TextEditingController _precoIfoodController;
  late TextEditingController _validadeController;

  @override
  void initState() {
    super.initState();
    _nomeController = TextEditingController(text: widget.produto.nome);
    _categoriaController = TextEditingController(text: widget.produto.categoria);
    _precoController = TextEditingController(text: widget.produto.preco.toString());
    _descricaoController = TextEditingController(text: widget.produto.descricao);
    _estoqueAtualController = TextEditingController(text: widget.produto.estoqueAtual.toString());
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _categoriaController.dispose();
    _precoController.dispose();
    _descricaoController.dispose();
    _estoqueAtualController.dispose();
    super.dispose();
  }

  Future<void> _salvarEdicao() async {
    final produtoAtualizado = Produto(
      id: widget.produto.id,
      nome: _nomeController.text,
      categoria: _categoriaController.text,
      preco: double.tryParse(_precoController.text) ?? 0.0,
      descricao: _descricaoController.text,
      estoqueAtual: int.tryParse(_estoqueAtualController.text) ?? 0,
        precoPromocional: double.tryParse( _precoPromocionalController.text) ?? 0.0,
        estoqueMinimo: int.tryParse( _estoqueMinimoController.text) ?? 0,
        imagemUrl: _imagemUrlController.text,
        codigoBarras: _codigoBarrasController.text,
        custo: double.tryParse( _custoController.text) ?? 0.0,
        destacar:  _destacarController.text.toLowerCase() == 'true',
      empresa: _empresaController.text,
      exibirNoCatalogo: _exibirNoCatalogoController.text.toLowerCase() == 'true',
    lucro: _lucroController.text,
      markup: _markupController.text,
      precoConcorrencia: _precoConcorrenciaController.text,
      precoIfood: double.tryParse( _precoIfoodController.text) ?? 0.0,
      validade: _validadeController.text,
    );

    final produtoProvider = Provider.of<ProdutoProvider>(context, listen: false);
    await produtoProvider.atualizarProduto(produtoAtualizado); // Atualiza no SQLite

    Navigator.pop(context); // Retorna para a tela anterior
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Editar Produto'),
        actions: [
          IconButton(
            icon: Icon(Icons.save),
            onPressed: _salvarEdicao,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _nomeController,
                decoration: InputDecoration(labelText: 'Nome'),
              ),
              TextField(
                controller: _categoriaController,
                decoration: InputDecoration(labelText: 'Categoria'),
              ),
              TextField(
                controller: _precoController,
                decoration: InputDecoration(labelText: 'Preço'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: _descricaoController,
                decoration: InputDecoration(labelText: 'Descrição'),
              ),
              TextField(
                controller: _estoqueAtualController,
                decoration: InputDecoration(labelText: 'Estoque Atual'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

