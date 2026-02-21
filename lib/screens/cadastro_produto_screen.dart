import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestor/screens/produto_categorias_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:firebase_storage/firebase_storage.dart'
    as firebase_storage; // Alias para evitar conflito

import '../models/produto.dart';
import '../providers/produto_provider.dart';

class CadastroProdutoScreen extends StatefulWidget {
  @override
  _CadastroProdutoScreenState createState() => _CadastroProdutoScreenState();
}

class _CadastroProdutoScreenState extends State<CadastroProdutoScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers para os campos do formulário
  final _nomeController = TextEditingController();
  final _precoVendaController = TextEditingController();
  final _precoPromocionalController = TextEditingController();
  final _categoriaController = TextEditingController();
  final _descricaoController = TextEditingController();
  final _codigoBarrasController = TextEditingController();
  final _custoController = TextEditingController();
  final _estoqueController = TextEditingController();
  final _estoqueMinimoController = TextEditingController();
  final _precoIfoodController = TextEditingController();
  final _markupController = TextEditingController();
  final _lucroController = TextEditingController();
  final _validadeController = TextEditingController();
  final _empresaController = TextEditingController();
  final _precoConcorrenciaController = TextEditingController();

  bool _destacarProduto = false;
  bool _exibirNoCatalogo = true;
  XFile? _imagemProdutoFile; // Arquivo da imagem selecionada
  bool _isLoading = false;

  String? _categoriaSelecionada; // armazenar categoria escolhida
  List<String> _categorias = []; // lista de categorias do Firestore

  @override
  void initState() {
    super.initState();
    // _carregarCategorias();
  }

  // Future<void> _carregarCategorias() async {
  //   try {
  //     final snapshot =
  //         await FirebaseFirestore.instance.collection('categorias').get();
  //     setState(() {
  //       _categorias =
  //           snapshot.docs.map((doc) => doc['nome'].toString()).toList();
  //     });
  //   } catch (e) {
  //     print("Erro ao carregar categorias: $e");
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(content: Text("Erro ao carregar categorias.")),
  //     );
  //   }
  // }

  @override
  void dispose() {
    _nomeController.dispose();
    _precoVendaController.dispose();
    _precoPromocionalController.dispose();
    _categoriaController.dispose();
    _descricaoController.dispose();
    _codigoBarrasController.dispose();
    _custoController.dispose();
    _estoqueController.dispose();
    _estoqueMinimoController.dispose();
    _precoIfoodController.dispose();
    _markupController.dispose();
    _lucroController.dispose();
    _validadeController.dispose();
    _empresaController.dispose();
    _precoConcorrenciaController.dispose();
    super.dispose();
  }

  Future<void> _selecionarImagem() async {
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _imagemProdutoFile = pickedFile;
        });
      }
    } catch (e) {
      print("Erro ao selecionar imagem: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao selecionar imagem: $e')),
        );
      }
    }
  }

  Future<String?> _uploadImagemProduto(File imageFile) async {
    if (!mounted) return null;
    try {
      // Criar uma referência única para o arquivo no Firebase Storage
      String fileName =
          'produtos/${DateTime.now().millisecondsSinceEpoch}_${imageFile.path.split('/').last}';
      firebase_storage.Reference ref =
          firebase_storage.FirebaseStorage.instance.ref().child(fileName);

      // Fazer upload do arquivo
      firebase_storage.UploadTask uploadTask = ref.putFile(imageFile);

      // Aguardar a conclusão do upload
      firebase_storage.TaskSnapshot taskSnapshot = await uploadTask;

      // Obter a URL de download
      String downloadURL = await taskSnapshot.ref.getDownloadURL();
      return downloadURL;
    } on firebase_storage.FirebaseException catch (e) {
      print("Erro no upload da imagem para o Firebase Storage: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro no upload da imagem: ${e.message}')),
        );
      }
      return null;
    } catch (e) {
      print("Erro desconhecido no upload da imagem: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro desconhecido no upload da imagem.')),
        );
      }
      return null;
    }
  }

  Future<void> _adicionarProduto() async {
    if (!_formKey.currentState!.validate()) {
      return; // Se o formulário não for válido, não continue
    }

    setState(() {
      _isLoading = true;
    });

    String? imagemUrlParaSalvar; // URL da imagem após o upload

    if (_imagemProdutoFile != null) {
      imagemUrlParaSalvar =
          await _uploadImagemProduto(File(_imagemProdutoFile!.path));
      if (imagemUrlParaSalvar == null && mounted) {
        // Se o upload falhar e o widget ainda estiver montado, pare o processo
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Falha ao fazer upload da imagem. Tente novamente.')),
        );
        return;
      }
    }

    final novoProduto = Produto(
      // id será gerado pelo Firestore
      nome: _nomeController.text,
      preco: double.tryParse(_precoVendaController.text) ?? 0.0,
      precoPromocional:
          double.tryParse(_precoPromocionalController.text) ?? 0.0,
      categoria: _categoriaController.text,
      descricao: _descricaoController.text,
      codigoBarras: _codigoBarrasController.text,
      custo: double.tryParse(_custoController.text) ?? 0.0,
      imagemUrl: imagemUrlParaSalvar ?? '',
      // Usa a URL do Storage ou string vazia
      estoqueAtual: int.tryParse(_estoqueController.text) ?? 0,
      estoqueMinimo: int.tryParse(_estoqueMinimoController.text) ?? 0,
      destacar: _destacarProduto,
      exibirNoCatalogo: _exibirNoCatalogo,
      precoIfood: double.tryParse(_precoIfoodController.text) ?? 0.0,
      markup: _markupController.text,
      lucro: _lucroController.text,
      precoConcorrencia:
          double.tryParse(_precoConcorrenciaController.text) ?? 0.0,
      validade: _validadeController.text,
      empresa: _empresaController.text,
    );

    try {
      if (mounted) {
        // Verifica antes de usar o context
        await Provider.of<ProdutoProvider>(context, listen: false)
            .adicionarProduto(novoProduto);

        if (mounted) {
          // Verifica novamente antes de interagir com a UI
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Produto adicionado com sucesso!')),
          );
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      print("Erro ao adicionar produto no Firestore: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao adicionar produto: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Cadastrar Novo Produto'),
        elevation: 0, // Opcional: remove a sombra do AppBar
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              // Para o botão ocupar a largura
              children: <Widget>[
                Center(
                  child: GestureDetector(
                    onTap: _selecionarImagem,
                    child: CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.grey[300],
                      backgroundImage: _imagemProdutoFile == null
                          ? null
                          : FileImage(File(_imagemProdutoFile!.path)),
                      child: _imagemProdutoFile == null
                          ? Icon(Icons.add_a_photo,
                              size: 60, color: Colors.grey[700])
                          : null,
                    ),
                  ),
                ),
                SizedBox(height: 24.0), // Espaçamento após a imagem

                // Campo Nome do Produto
                TextFormField(
                  controller: _nomeController,
                  decoration: InputDecoration(
                    labelText: 'Nome do Produto',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, insira o nome do produto';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16.0),

                // Campo Preço de Venda
                TextFormField(
                  controller: _precoVendaController,
                  decoration: InputDecoration(
                    labelText: 'Preço de Venda (R\$)',
                    border: OutlineInputBorder(),
                    prefixText: 'R\$ ',
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, insira o preço de venda';
                    }
                    if (double.tryParse(value.replaceAll(',', '.')) == null) {
                      return 'Por favor, insira um número válido';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16.0),

                // Campo Preço Promocional
                TextFormField(
                  controller: _precoPromocionalController,
                  decoration: InputDecoration(
                    labelText: 'Preço Promocional (R\$) (Opcional)',
                    border: OutlineInputBorder(),
                    prefixText: 'R\$ ',
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value != null &&
                        value.isNotEmpty &&
                        double.tryParse(value.replaceAll(',', '.')) == null) {
                      return 'Por favor, insira um número válido ou deixe em branco';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16.0),

                // Dropdown de Categoria com botão para ir para a tela de categorias
                Row(
                  children: [
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('produtos').snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return Center(child: CircularProgressIndicator());
                          }
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                            return Text("Nenhuma categoria encontrada");
                          }

                          List<String> categorias = snapshot.data!.docs
                              .map((doc) => doc['categoria'] as String? ?? '')
                              .where((categoria) => categoria.isNotEmpty)
                              .toSet()
                              .toList()
                            ..sort();

                          return DropdownButtonFormField<String>(
                            decoration: InputDecoration(
                              labelText: 'Categoria',
                              border: OutlineInputBorder(),
                            ),
                            value: _categoriaController.text.isNotEmpty
                                ? _categoriaController.text
                                : null,
                            items: categorias.map((categoria) {
                              return DropdownMenuItem(
                                value: categoria,
                                child: Text(categoria),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _categoriaController.text = value!;
                              });
                            },
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Por favor, selecione uma categoria';
                              }
                              return null;
                            },
                          );
                        },
                      ),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        // Navega para a tela de categorias
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => CategoriaScreen()),
                        );
                        // Rebuild para atualizar o dropdown com possíveis novas categorias
                        setState(() {});
                      },
                      child: Text("+"),
                    ),
                  ],
                ),
                SizedBox(height: 16.0),


                // Campo Descrição
                TextFormField(
                  controller: _descricaoController,
                  decoration: InputDecoration(
                    labelText: 'Descrição',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, insira a descrição';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16.0),

                // Campo Código de Barras
                TextFormField(
                  controller: _codigoBarrasController,
                  decoration: InputDecoration(
                    labelText: 'Código de Barras (Opcional)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                SizedBox(height: 16.0),

                // Campo Custo
                TextFormField(
                  controller: _custoController,
                  decoration: InputDecoration(
                    labelText: 'Custo (R\$)',
                    border: OutlineInputBorder(),
                    prefixText: 'R\$ ',
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, insira o custo do produto';
                    }
                    if (double.tryParse(value.replaceAll(',', '.')) == null) {
                      return 'Por favor, insira um número válido';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16.0),

                // Campo Estoque Atual
                TextFormField(
                  controller: _estoqueController,
                  decoration: InputDecoration(
                    labelText: 'Estoque Atual',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, insira o estoque atual';
                    }
                    if (int.tryParse(value) == null) {
                      return 'Por favor, insira um número inteiro válido';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16.0),

                // Campo Estoque Mínimo
                TextFormField(
                  controller: _estoqueMinimoController,
                  decoration: InputDecoration(
                    labelText: 'Estoque Mínimo',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, insira o estoque mínimo';
                    }
                    if (int.tryParse(value) == null) {
                      return 'Por favor, insira um número inteiro válido';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16.0),

                // Campo Preço Ifood
                TextFormField(
                  controller: _precoIfoodController,
                  decoration: InputDecoration(
                    labelText: 'Preço Ifood (R\$) (Opcional)',
                    border: OutlineInputBorder(),
                    prefixText: 'R\$ ',
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value != null &&
                        value.isNotEmpty &&
                        double.tryParse(value.replaceAll(',', '.')) == null) {
                      return 'Por favor, insira um número válido ou deixe em branco';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16.0),

                // Campo Markup
                TextFormField(
                  controller: _markupController,
                  decoration: InputDecoration(
                    labelText: 'Markup (Opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 16.0),

                // Campo Lucro
                TextFormField(
                  controller: _lucroController,
                  decoration: InputDecoration(
                    labelText: 'Lucro (Opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 16.0),

                // Campo Validade
                TextFormField(
                  controller: _validadeController,
                  decoration: InputDecoration(
                    labelText: 'Validade (Ex: DD/MM/AAAA) (Opcional)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.datetime,
                ),
                SizedBox(height: 16.0),

                // Campo Empresa
                TextFormField(
                  controller: _empresaController,
                  decoration: InputDecoration(
                    labelText: 'Empresa/Fornecedor (Opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 16.0),

                // Campo Preço Concorrência
                TextFormField(
                  controller: _precoConcorrenciaController,
                  decoration: InputDecoration(
                    labelText: 'Preço Concorrência (R\$) (Opcional)',
                    border: OutlineInputBorder(),
                    prefixText: 'R\$ ',
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value != null &&
                        value.isNotEmpty &&
                        double.tryParse(value.replaceAll(',', '.')) == null) {
                      return 'Por favor, insira um número válido ou deixe em branco';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 24.0), // Espaçamento antes dos Switches

                // Switch Destacar Produto
                SwitchListTile(
                  title: Text('Destacar Produto'),
                  value: _destacarProduto,
                  onChanged: (bool value) {
                    setState(() {
                      _destacarProduto = value;
                    });
                  },
                  activeColor: Theme.of(context).primaryColor,
                ),

                // Switch Exibir no Catálogo
                SwitchListTile(
                  title: Text('Exibir no Catálogo'),
                  value: _exibirNoCatalogo,
                  onChanged: (bool value) {
                    setState(() {
                      _exibirNoCatalogo = value;
                    });
                  },
                  activeColor: Theme.of(context).primaryColor,
                ),
                SizedBox(height: 32.0), // Espaçamento antes do botão

                // Botão Adicionar Produto
                _isLoading
                    ? Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _adicionarProduto,
                        child: Text('Adicionar Produto'),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 16.0),
                          textStyle: TextStyle(fontSize: 16.0),
                        ),
                      ),
                SizedBox(height: 16.0), // Espaçamento no final do formulário
              ],
            ),
          ),
        ),
      ),
    );
  }
}
