import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; // Para escolher a imagem
import 'package:provider/provider.dart';
import '../providers/produto_provider.dart'; // Assumindo que o Provider do produto está configurado
import '../models/produto.dart'; // Modelo de Produto

class CadastroProdutoScreen extends StatefulWidget {
  @override
  _CadastroProdutoScreenState createState() => _CadastroProdutoScreenState();
}

class _CadastroProdutoScreenState extends State<CadastroProdutoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _precoVendaController = TextEditingController();
  final _precoPromocionalController = TextEditingController();
  final _categoriaController = TextEditingController();
  final _descricaoController = TextEditingController();
  final _codigoBarrasController = TextEditingController();
  final _custoController = TextEditingController();
  final _estoqueController = TextEditingController();
  final _estoqueMinimoController = TextEditingController();
  bool _destacarProduto = false;
  bool _exibirNoCatalogo = true;
  XFile? _imagemProduto;

  // Função para selecionar imagem
  Future<void> _selecionarImagem() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    setState(() {
      _imagemProduto = pickedFile;
    });
  }

  void _adicionarProduto() {
    if (_formKey.currentState!.validate()) {
      final novoProduto = Produto(
        id: DateTime.now().toString(),
        nome: _nomeController.text,
        preco: double.parse(_precoVendaController.text),
        precoPromocional: double.parse(_precoPromocionalController.text),
        categoria: _categoriaController.text,
        descricao: _descricaoController.text,
        codigoBarras: _codigoBarrasController.text,
        custo: double.parse(_custoController.text),
        imagemUrl: _imagemProduto?.path ?? '', // Caminho da imagem
        estoqueAtual: int.parse(_estoqueController.text),
        estoqueMinimo: int.parse(_estoqueMinimoController.text),
        destacar: _destacarProduto,
        exibirNoCatalogo: _exibirNoCatalogo,
      );

      // Adicionar o produto ao Provider
      Provider.of<ProdutoProvider>(context, listen: false).adicionarProduto(novoProduto);

      // Navegar de volta após adicionar o produto
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Cadastrar Produto'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Seção para adicionar imagem do produto
                GestureDetector(
                  onTap: _selecionarImagem,
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: _imagemProduto == null
                        ? null
                        : FileImage(File(_imagemProduto!.path)),
                    child: _imagemProduto == null
                        ? Icon(Icons.add_a_photo, size: 50)
                        : null,
                  ),
                ),
                SizedBox(height: 16),

                // Campo para o nome do produto
                TextFormField(
                  controller: _nomeController,
                  decoration: InputDecoration(labelText: 'Nome do Produto'),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, insira o nome do produto';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                // Campo para preço de venda
                TextFormField(
                  controller: _precoVendaController,
                  decoration: InputDecoration(labelText: 'Preço de Venda'),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, insira o preço de venda';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                // Campo para preço promocional
                TextFormField(
                  controller: _precoPromocionalController,
                  decoration: InputDecoration(labelText: 'Preço Promocional'),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, insira o preço promocional';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                // Campo para categoria
                TextFormField(
                  controller: _categoriaController,
                  decoration: InputDecoration(labelText: 'Categoria'),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, insira a categoria';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                // Campo para descrição
                TextFormField(
                  controller: _descricaoController,
                  decoration: InputDecoration(labelText: 'Descrição'),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, insira a descrição';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                // Campo para código de barras
                TextFormField(
                  controller: _codigoBarrasController,
                  decoration: InputDecoration(labelText: 'Código de Barras'),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, insira o código de barras';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                // Campo para custo
                TextFormField(
                  controller: _custoController,
                  decoration: InputDecoration(labelText: 'Custo'),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, insira o custo';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),

                // Opção para destacar produto
                SwitchListTile(
                  title: Text('Destacar Produto'),
                  value: _destacarProduto,
                  onChanged: (value) {
                    setState(() {
                      _destacarProduto = value;
                    });
                  },
                ),

                // Opção para exibir no catálogo
                SwitchListTile(
                  title: Text('Exibir no Catálogo'),
                  value: _exibirNoCatalogo,
                  onChanged: (value) {
                    setState(() {
                      _exibirNoCatalogo = value;
                    });
                  },
                ),
                SizedBox(height: 16),

                // Seção de Estoque
                Text('Gestão de Estoque', style: Theme.of(context).textTheme.headline6),
                SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _estoqueController,
                        decoration: InputDecoration(labelText: 'Estoque Atual'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.settings),
                      onPressed: () {
                        // Ação para gerenciar o estoque
                        print('Gerenciando estoque...');
                      },
                    ),
                  ],
                ),
                SizedBox(height: 8),

                // Campo de Estoque Mínimo
                TextFormField(
                  controller: _estoqueMinimoController,
                  decoration: InputDecoration(labelText: 'Estoque Mínimo'),
                  keyboardType: TextInputType.number,
                ),
                SizedBox(height: 16),

                // Botão para adicionar produto
                ElevatedButton(
                  onPressed: _adicionarProduto,
                  child: Text('Adicionar Produto'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
