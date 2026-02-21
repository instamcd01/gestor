// import 'dart:io'; // Para File, se for lidar com upload de imagem
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:flutter/material.dart';
// import 'package:image_picker/image_picker.dart'; // Se for lidar com upload de imagem
// import 'package:provider/provider.dart';
// import 'package:firebase_storage/firebase_storage.dart' as firebase_storage; // Se for lidar com upload de imagem
//
// import '../models/produto.dart';
// import '../providers/produto_provider.dart';
// import '../widgets/buscar_imagem_produto.dart';
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
//   final _formKey = GlobalKey<FormState>();
//   late TextEditingController _nomeController;
//   late TextEditingController _categoriaController;
//   late TextEditingController _precoController;
//   late TextEditingController _precoPromocionalController;
//   late TextEditingController _descricaoController;
//   late TextEditingController _codigoBarrasController;
//   late TextEditingController _custoController;
//   late TextEditingController _estoqueAtualController;
//   late TextEditingController _estoqueMinimoController;
//   late TextEditingController _precoIfoodController;
//   late TextEditingController _markupController;
//   late TextEditingController _lucroController;
//   late TextEditingController _validadeController;
//   late TextEditingController _empresaController;
//   late TextEditingController _precoConcorrenciaController;
//   // Não precisamos de _idController se o ID não for editável pelo usuário
//
//   bool _destacarProduto = false;
//   bool _exibirNoCatalogo = true;
//   XFile? _novaImagemFile; // Para armazenar a nova imagem selecionada
//   String? _imagemUrlAtual; // Para exibir a imagem atual e manter se não for alterada
//   String? _imagemAutomaticaUrl;
//
//   bool _isLoading = false;
//   List<String> _categoriasExistentes = [];
//   bool _categoriasCarregadas = false;
//
//   @override
//   void initState() {
//     super.initState();
//     _nomeController = TextEditingController(text: widget.produto.nome);
//     _categoriaController = TextEditingController(text: widget.produto.categoria);
//     _precoController = TextEditingController(text: widget.produto.preco.toString());
//     _precoPromocionalController = TextEditingController(text: widget.produto.precoPromocional?.toString() ?? '');
//     _descricaoController = TextEditingController(text: widget.produto.descricao);
//     _codigoBarrasController = TextEditingController(text: widget.produto.codigoBarras);
//     _custoController = TextEditingController(text: widget.produto.custo.toString());
//     _estoqueAtualController = TextEditingController(text: widget.produto.estoqueAtual.toString());
//     _estoqueMinimoController = TextEditingController(text: widget.produto.estoqueMinimo.toString());
//     _precoIfoodController = TextEditingController(text: widget.produto.precoIfood?.toString() ?? '');
//     _markupController = TextEditingController(text: widget.produto.markup ?? '');
//     _lucroController = TextEditingController(text: widget.produto.lucro ?? '');
//     _validadeController = TextEditingController(text: widget.produto.validade ?? '');
//     _empresaController = TextEditingController(text: widget.produto.empresa ?? '');
//     _precoConcorrenciaController = TextEditingController(text: widget.produto.precoConcorrencia?.toString() ?? '');
//
//     _destacarProduto = widget.produto.destacar;
//     _exibirNoCatalogo = widget.produto.exibirNoCatalogo;
//     _imagemUrlAtual = widget.produto.imagemUrl;
//     _imagemAutomaticaUrl = widget.produto.imagemAutomaticaUrl;
//     _carregarCategoriasDoFirestore();
//   }
//   Future<void> _carregarCategoriasDoFirestore() async {
//     final snapshot = await FirebaseFirestore.instance.collection('produtos').get();
//     final categorias = snapshot.docs.map((doc) => doc.data()['categoria'] as String? ?? '').toSet().toList();
//     categorias.removeWhere((c) => c.isEmpty);
//     setState(() {
//       _categoriasExistentes = categorias;
//       _categoriasCarregadas = true;
//     });
//   }
//
//   void _mostrarDialogNovaCategoria(BuildContext context) {
//     final novaCategoriaController = TextEditingController();
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: Text('Nova Categoria'),
//         content: TextField(
//           controller: novaCategoriaController,
//           decoration: InputDecoration(labelText: 'Nome da categoria'),
//         ),
//         actions: [
//           TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Cancelar')),
//           ElevatedButton(
//             onPressed: () {
//               final novaCategoria = novaCategoriaController.text.trim();
//               if (novaCategoria.isNotEmpty && !_categoriasExistentes.contains(novaCategoria)) {
//                 setState(() {
//                   _categoriasExistentes.add(novaCategoria);
//                   _categoriaController.text = novaCategoria;
//                 });
//               }
//               Navigator.of(context).pop();
//             },
//             child: Text('Adicionar'),
//           ),
//         ],
//       ),
//     );
//   }
//
//   void _mostrarDialogEditarCategorias(BuildContext context) {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: Text('Editar Categorias'),
//         content: SizedBox(
//           width: double.maxFinite,
//           child: ListView.builder(
//             shrinkWrap: true,
//             itemCount: _categoriasExistentes.length,
//             itemBuilder: (context, index) {
//               final cat = _categoriasExistentes[index];
//               return ListTile(
//                 title: Text(cat),
//                 trailing: IconButton(
//                   icon: Icon(Icons.delete, color: Colors.red),
//                   onPressed: () {
//                     setState(() {
//                       _categoriasExistentes.removeAt(index);
//                       if (_categoriaController.text == cat) {
//                         _categoriaController.clear();
//                       }
//                     });
//                     Navigator.of(context).pop();
//                   },
//                 ),
//               );
//             },
//           ),
//         ),
//         actions: [
//           TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Fechar')),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildCategoriaField() {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text('Categoria', style: TextStyle(fontWeight: FontWeight.bold)),
//         SizedBox(height: 8),
//         if (!_categoriasCarregadas)
//           LinearProgressIndicator()
//         else
//           Row(
//             children: [
//               Expanded(
//                 child: DropdownButtonFormField<String>(
//                   isExpanded: true,
//                   value: _categoriaController.text.isNotEmpty ? _categoriaController.text : null,
//                   items: _categoriasExistentes.map((categoria) {
//                     return DropdownMenuItem(
//                       value: categoria,
//                       child: Text(categoria),
//                     );
//                   }).toList(),
//                   onChanged: (value) {
//                     if (value != null) {
//                       _categoriaController.text = value;
//                     }
//                   },
//                   decoration: InputDecoration(
//                     border: OutlineInputBorder(),
//                     hintText: 'Selecione ou digite uma categoria',
//                   ),
//                 ),
//               ),
//               IconButton(
//                 icon: Icon(Icons.add),
//                 tooltip: 'Nova categoria',
//                 onPressed: () => _mostrarDialogNovaCategoria(context),
//               ),
//               IconButton(
//                 icon: Icon(Icons.edit),
//                 tooltip: 'Editar categorias',
//                 onPressed: () => _mostrarDialogEditarCategorias(context),
//               ),
//             ],
//           ),
//       ],
//     );
//   }
//
//   @override
//   void dispose() {
//     _nomeController.dispose();
//     _categoriaController.dispose();
//     _precoController.dispose();
//     _precoPromocionalController.dispose();
//     _descricaoController.dispose();
//     _codigoBarrasController.dispose();
//     _custoController.dispose();
//     _estoqueAtualController.dispose();
//     _estoqueMinimoController.dispose();
//     _precoIfoodController.dispose();
//     _markupController.dispose();
//     _lucroController.dispose();
//     _validadeController.dispose();
//     _empresaController.dispose();
//     _precoConcorrenciaController.dispose();
//     super.dispose();
//   }
//
//   Future<void> _selecionarNovaImagem() async {
//     final picker = ImagePicker();
//     try {
//       final pickedFile = await picker.pickImage(source: ImageSource.gallery);
//       if (pickedFile != null) {
//         setState(() {
//           _novaImagemFile = pickedFile;
//         });
//       }
//     } catch (e) {
//       print("Erro ao selecionar imagem: $e");
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Erro ao selecionar imagem: $e')),
//         );
//       }
//     }
//   }
//
//   Future<String?> _uploadNovaImagem(File imageFile) async {
//     if (!mounted) return null;
//     try {
//       String fileName = 'produtos/${DateTime.now().millisecondsSinceEpoch}_${imageFile.path.split('/').last}';
//       firebase_storage.Reference ref = firebase_storage.FirebaseStorage.instance.ref().child(fileName);
//       firebase_storage.UploadTask uploadTask = ref.putFile(imageFile);
//       firebase_storage.TaskSnapshot taskSnapshot = await uploadTask;
//       return await taskSnapshot.ref.getDownloadURL();
//     } catch (e) {
//       print("Erro no upload da nova imagem: $e");
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Erro no upload da nova imagem: ${e is firebase_storage.FirebaseException ? e.message : e}')),
//         );
//       }
//       return null;
//     }
//   }
//
//   Future<void> _buscarImagemAutomatica() async {
//     final codigo = _codigoBarrasController.text.trim();
//     if (codigo.isEmpty) {
//       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Informe o código de barras para buscar a imagem')));
//       return;
//     }
//
//     setState(() {
//       _isLoading = true;
//     });
//
//     try {
//       // Aqui você implementa a lógica real da busca, ex: chamar uma API
//       String urlEncontrada = 'https://via.placeholder.com/300.png?text=$codigo';
//
//       setState(() {
//         _imagemAutomaticaUrl = urlEncontrada;
//         if (_novaImagemFile == null) {
//           _imagemUrlAtual = _imagemAutomaticaUrl;
//         }
//       });
//
//       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imagem automática atribuída!')));
//     } catch (e) {
//       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao buscar imagem automática: $e')));
//     } finally {
//       setState(() {
//         _isLoading = false;
//       });
//     }
//   }
//
//   Future<void> _salvarEdicao() async {
//     if (!_formKey.currentState!.validate()) {
//       return;
//     }
//
//     if (mounted) {
//       setState(() {
//         _isLoading = true;
//       });
//     }
//
//     String? imagemUrlParaSalvar = _imagemUrlAtual; // Mantém a URL atual por padrão
//
//     // Se uma nova imagem foi selecionada, faz o upload
//     if (_novaImagemFile != null) {
//       String? novaUrl = await _uploadNovaImagem(File(_novaImagemFile!.path));
//       if (novaUrl != null) {
//         imagemUrlParaSalvar = novaUrl;
//         // TODO: Considerar deletar a imagem antiga do Firebase Storage se uma nova for carregada com sucesso
//         // Isso requer armazenar a URL antiga e usar FirebaseStorage.instance.refFromURL(oldImageUrl).delete();
//       } else {
//         // Falha no upload da nova imagem, não continuar ou avisar o usuário
//         if (mounted) {
//           setState(() {
//             _isLoading = false;
//           });
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(content: Text('Falha ao fazer upload da nova imagem. As alterações não foram salvas.')),
//           );
//         }
//         return;
//       }
//     }
//
//     final produtoAtualizado = Produto(
//       id: widget.produto.id, // O ID não muda
//       nome: _nomeController.text,
//       categoria: _categoriaController.text,
//       preco: double.tryParse(_precoController.text.replaceAll(',', '.')) ?? widget.produto.preco,
//       precoPromocional: double.tryParse(_precoPromocionalController.text.replaceAll(',', '.')) ?? widget.produto.precoPromocional,
//       descricao: _descricaoController.text,
//       codigoBarras: _codigoBarrasController.text,
//       custo: double.tryParse(_custoController.text.replaceAll(',', '.')) ?? widget.produto.custo,
//       estoqueAtual: int.tryParse(_estoqueAtualController.text) ?? widget.produto.estoqueAtual,
//       estoqueMinimo: int.tryParse(_estoqueMinimoController.text) ?? widget.produto.estoqueMinimo,
//       imagemUrl: imagemUrlParaSalvar ?? widget.produto.imagemUrl, // Usa a nova URL ou a antiga
//       imagemAutomaticaUrl: _imagemAutomaticaUrl,
//       destacar: _destacarProduto,
//       exibirNoCatalogo: _exibirNoCatalogo,
//       precoIfood: double.tryParse(_precoIfoodController.text.replaceAll(',', '.')) ?? widget.produto.precoIfood,
//       markup: _markupController.text.isNotEmpty ? _markupController.text : widget.produto.markup,
//       lucro: _lucroController.text.isNotEmpty ? _lucroController.text : widget.produto.lucro,
//       validade: _validadeController.text.isNotEmpty ? _validadeController.text : widget.produto.validade,
//       empresa: _empresaController.text.isNotEmpty ? _empresaController.text : widget.produto.empresa,
//       precoConcorrencia: double.tryParse(_precoConcorrenciaController.text.replaceAll(',', '.')) ?? widget.produto.precoConcorrencia,
//     );
//
//     try {
//       if (mounted) {
//         await Provider.of<ProdutoProvider>(context, listen: false)
//             .atualizarProduto(produtoAtualizado);
//
//         if (mounted) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(content: Text('Produto atualizado com sucesso!')),
//           );
//           Navigator.of(context).pop(); // Volta para a tela anterior
//         }
//       }
//     } catch (e) {
//       print("Erro ao atualizar produto no Firestore: $e");
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Erro ao atualizar produto: ${e.toString()}')),
//         );
//       }
//     } finally {
//       if (mounted) {
//         setState(() {
//           _isLoading = false;
//         });
//       }
//     }
//   }
//
//
//
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//         appBar: AppBar(
//           title: Text('Editar Produto'),
//           actions: [
//             if (_isLoading)
//               Padding(
//                 padding: const EdgeInsets.all(16.0),
//                 child: CircularProgressIndicator(color: Colors.white),
//               )
//             else
//               IconButton(
//                 icon: Icon(Icons.save),
//                 onPressed: _salvarEdicao,
//               ),
//           ],
//         ),
//         body: Padding(
//         padding: const EdgeInsets.all(16.0),
//     child: Form(
//     key: _formKey,
//     child: SingleChildScrollView(
//     child: Column(
//     crossAxisAlignment: CrossAxisAlignment.stretch,
//     children: <Widget>[
//     Center(
//     child: GestureDetector(
//       onTap: _selecionarNovaImagem,
//       child: Column(
//         children: [
//           CircleAvatar(
//             radius: 60,
//             backgroundColor: Colors.grey[300],
//             backgroundImage: _novaImagemFile != null
//                 ? FileImage(File(_novaImagemFile!.path))
//                 : (_imagemUrlAtual != null && _imagemUrlAtual!.isNotEmpty
//                 ? NetworkImage(_imagemUrlAtual!)
//                 : (_imagemAutomaticaUrl != null ? NetworkImage(_imagemAutomaticaUrl!) : null)) as ImageProvider?,
//             child: (_novaImagemFile == null && (_imagemUrlAtual == null || _imagemUrlAtual!.isEmpty))
//                 ? Icon(Icons.add_a_photo, size: 60, color: Colors.grey[700])
//                 : null,
//           ),
//           Padding(
//             padding: const EdgeInsets.only(top: 8.0),
//             child: Text(
//               _novaImagemFile != null
//                   ? 'Nova imagem selecionada'
//                   : (_imagemUrlAtual != null && _imagemUrlAtual!.isNotEmpty)
//                   ? 'Toque para alterar imagem'
//                   : 'Toque para alterar imagem',
//               style: TextStyle(color: _novaImagemFile != null ? Colors.blue : Colors.grey[700]),
//             ),
//           ),
//         ],
//       ),
//     ),
//     ),
//       SizedBox(height: 24.0),
//
//     TextFormField(
//     controller: _nomeController,
//     decoration: InputDecoration(labelText: 'Nome do Produto', border: OutlineInputBorder()),
//     validator: (value) {
//     if (value == null || value.isEmpty) return 'Campo obrigatório';
//     return null;
//     },
//     ),
//     SizedBox(height: 16.0),
//       _buildCategoriaField(),
//     // TextFormField(
//     // controller: _categoriaController,
//     // decoration: InputDecoration(labelText: 'Categoria', border: OutlineInputBorder()),
//     // validator: (value) {
//     // if (value == null || value.isEmpty) return 'Campo obrigatório';
//     // return null;
//     // },
//     // ),
//     SizedBox(height: 16.0),
//
//     TextFormField(
//     controller: _precoController,
//     decoration: InputDecoration(labelText: 'Preço (R\$)', border: OutlineInputBorder(), prefixText: 'R\$ '),
//     keyboardType: TextInputType.numberWithOptions(decimal: true),
//     validator: (value) {
//     if (value == null || value.isEmpty) return 'Campo obrigatório';
//     if (double.tryParse(value.replaceAll(',', '.')) == null) return 'Número inválido';
//     return null;
//     },
//     ),
//     SizedBox(height: 16.0),
//
//     TextFormField(
//     controller: _precoPromocionalController,
//     decoration: InputDecoration(labelText: 'Preço Promocional (R\$) (Opcional)', border: OutlineInputBorder(), prefixText: 'R\$ '),
//     keyboardType: TextInputType.numberWithOptions(decimal: true),
//     validator: (value) {
//     if (value != null && value.isNotEmpty && double.tryParse(value.replaceAll(',', '.')) == null) return 'Número inválido';
//     return null;
//     },
//     ),
//     SizedBox(height: 16.0),
//
//     TextFormField(
//     controller: _descricaoController,
//     decoration: InputDecoration(labelText: 'Descrição', border: OutlineInputBorder()),
//     maxLines: 3,
//     validator: (value) {
//     if (value == null || value.isEmpty) return 'Campo obrigatório';
//     return null;
//     },
//     ),
//     SizedBox(height: 16.0),
//
//     TextFormField(
//     controller: _codigoBarrasController,
//     decoration: InputDecoration(labelText: 'Código de Barras (Opcional)', border: OutlineInputBorder()),
//     keyboardType: TextInputType.text, // Pode ser alfanumérico
//     ),
//     SizedBox(height: 16.0),
//
//     TextFormField(
//     controller: _custoController,
//     decoration: InputDecoration(labelText: 'Custo (R\$)', border: OutlineInputBorder(), prefixText: 'R\$ '),
//     keyboardType: TextInputType.numberWithOptions(decimal: true),
//     validator: (value) {
//     if (value == null || value.isEmpty) return 'Campo obrigatório';
//     if (double.tryParse(value.replaceAll(',', '.')) == null) return 'Número inválido';
//     return null;
//     },
//     ),
//     SizedBox(height: 16.0),
//
//     TextFormField(
//     controller: _estoqueAtualController,
//     decoration: InputDecoration(labelText: 'Estoque Atual', border: OutlineInputBorder()),
//     keyboardType: TextInputType.number,
//     validator: (value) {
//     if (value == null || value.isEmpty) return 'Campo obrigatório';
//     if (int.tryParse(value) == null) return 'Número inteiro inválido';
//     return null;
//     },
//     ),
//       SizedBox(height: 16.0),
//
//       TextFormField(
//         controller: _estoqueMinimoController,
//         decoration: InputDecoration(labelText: 'Estoque Mínimo', border: OutlineInputBorder()),
//         keyboardType: TextInputType.number,
//         validator: (value) {
//           if (value == null || value.isEmpty) return 'Campo obrigatório';
//           if (int.tryParse(value) == null) return 'Número inteiro inválido';
//           return null;
//         },
//       ),
//       SizedBox(height: 16.0),
//
//       TextFormField(
//         controller: _precoIfoodController,
//         decoration: InputDecoration(labelText: 'Preço iFood (R\$) (Opcional)', border: OutlineInputBorder(), prefixText: 'R\$ '),
//         keyboardType: TextInputType.numberWithOptions(decimal: true),
//         validator: (value) {
//           if (value != null && value.isNotEmpty && double.tryParse(value.replaceAll(',', '.')) == null) return 'Número inválido';
//           return null;
//         },
//       ),
//       SizedBox(height: 16.0),
//
//       TextFormField(
//         controller: _markupController,
//         decoration: InputDecoration(labelText: 'Markup (%) (Opcional)', border: OutlineInputBorder(), suffixText: '%'),
//         keyboardType: TextInputType.text, // Pode ser número ou texto simples
//       ),
//       SizedBox(height: 16.0),
//
//       TextFormField(
//         controller: _lucroController,
//         decoration: InputDecoration(labelText: 'Lucro (%) (Opcional)', border: OutlineInputBorder(), suffixText: '%'),
//         keyboardType: TextInputType.text, // Pode ser número ou texto simples
//       ),
//       SizedBox(height: 16.0),
//
//       TextFormField(
//         controller: _validadeController,
//         decoration: InputDecoration(labelText: 'Validade (Opcional)', border: OutlineInputBorder(), hintText: 'DD/MM/AAAA ou texto'),
//         keyboardType: TextInputType.datetime,
//       ),
//       SizedBox(height: 16.0),
//
//       TextFormField(
//         controller: _empresaController,
//         decoration: InputDecoration(labelText: 'Empresa/Fornecedor (Opcional)', border: OutlineInputBorder()),
//       ),
//       SizedBox(height: 16.0),
//
//       TextFormField(
//         controller: _precoConcorrenciaController,
//         decoration: InputDecoration(labelText: 'Preço Concorrência (R\$) (Opcional)', border: OutlineInputBorder(), prefixText: 'R\$ '),
//         keyboardType: TextInputType.numberWithOptions(decimal: true),
//         validator: (value) {
//           if (value != null && value.isNotEmpty && double.tryParse(value.replaceAll(',', '.')) == null) return 'Número inválido';
//           return null;
//         },
//       ),
//       SizedBox(height: 24.0), // Espaçamento antes dos Switches
//
//       SwitchListTile(
//         title: Text('Destacar Produto'),
//         value: _destacarProduto,
//         onChanged: (bool value) {
//           setState(() {
//             _destacarProduto = value;
//           });
//         },
//         activeColor: Theme.of(context).primaryColor,
//       ),
//
//       SwitchListTile(
//         title: Text('Exibir no Catálogo'),
//         value: _exibirNoCatalogo,
//         onChanged: (bool value) {
//           setState(() {
//             _exibirNoCatalogo = value;
//           });
//         },
//         activeColor: Theme.of(context).primaryColor,
//       ),
//       SizedBox(height: 32.0), // Espaçamento antes do botão salvar (se não estiver na AppBar)
//
//       // O botão de salvar já está na AppBar, então não é necessário aqui
//       // a menos que você queira um botão adicional no corpo do formulário.
//     ],
//     ),
//     ),
//     ),
//         ),
//     );
//   }
// }

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestor/screens/produto_categorias_screen.dart';
import 'package:image_picker/image_picker.dart';
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
  final _formKey = GlobalKey<FormState>();

  // Controladores para os campos do formulário
  late TextEditingController _nomeController;
  late TextEditingController _categoriaController;
  late TextEditingController _precoController;
  late TextEditingController _precoPromocionalController;
  late TextEditingController _descricaoController;
  late TextEditingController _codigoBarrasController;
  late TextEditingController _custoController;
  late TextEditingController _estoqueAtualController;
  late TextEditingController _estoqueMinimoController;
  late TextEditingController _precoIfoodController;
  late TextEditingController _markupController;
  late TextEditingController _lucroController;
  late TextEditingController _validadeController;
  late TextEditingController _empresaController;
  late TextEditingController _precoConcorrenciaController;

  bool _destacarProduto = false;
  bool _exibirNoCatalogo = true;

  XFile? _novaImagemFile; // Para imagem escolhida do dispositivo
  String? _imagemUrlAtual; // URL atual do produto
  String? _imagemAutomaticaUrl; // URL automática pelo código de barras

  bool _isLoading = false;
  List<String> _categoriasExistentes = [];
  bool _categoriasCarregadas = false;

  @override
  void initState() {
    super.initState();

    // Preenche os controladores com os dados atuais do produto
    _nomeController = TextEditingController(text: widget.produto.nome);
    _categoriaController =
        TextEditingController(text: widget.produto.categoria);
    _precoController =
        TextEditingController(text: widget.produto.preco.toString());
    _precoPromocionalController = TextEditingController(
        text: widget.produto.precoPromocional?.toString() ?? '');
    _descricaoController =
        TextEditingController(text: widget.produto.descricao);
    _codigoBarrasController =
        TextEditingController(text: widget.produto.codigoBarras);
    _custoController =
        TextEditingController(text: widget.produto.custo.toString());
    _estoqueAtualController =
        TextEditingController(text: widget.produto.estoqueAtual.toString());
    _estoqueMinimoController =
        TextEditingController(text: widget.produto.estoqueMinimo.toString());
    _precoIfoodController = TextEditingController(
        text: widget.produto.precoIfood?.toString() ?? '');
    _markupController =
        TextEditingController(text: widget.produto.markup ?? '');
    _lucroController = TextEditingController(text: widget.produto.lucro ?? '');
    _validadeController =
        TextEditingController(text: widget.produto.validade ?? '');
    _empresaController =
        TextEditingController(text: widget.produto.empresa ?? '');
    _precoConcorrenciaController = TextEditingController(
        text: widget.produto.precoConcorrencia?.toString() ?? '');

    _destacarProduto = widget.produto.destacar;
    _exibirNoCatalogo = widget.produto.exibirNoCatalogo;

    _imagemUrlAtual = widget.produto.imagemUrl;
    _imagemAutomaticaUrl = widget.produto.imagemAutomaticaUrl;

    _carregarCategoriasDoFirestore();
  }

  Future<void> _carregarCategoriasDoFirestore() async {
    final snapshot =
        await FirebaseFirestore.instance.collection('produtos').get();
    final categorias = snapshot.docs
        .map((doc) => doc.data()['categoria'] as String? ?? '')
        .toSet()
        .toList();
    categorias.removeWhere((c) => c.isEmpty);
    setState(() {
      _categoriasExistentes = categorias;
      _categoriasCarregadas = true;
    });
  }

  // Seleciona nova imagem da galeria
  Future<void> _selecionarNovaImagem() async {
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _novaImagemFile = pickedFile;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao selecionar imagem: $e')),
      );
    }
  }

  // **ALTERAÇÃO**: Gera a URL para acessar a imagem no seu servidor (não faz upload)
  Future<String?> _gerarUrlImagemServidor(XFile file) async {
    String nomeArquivo = file.path.split('/').last;
    return 'http://imagens.lukz.com.br/produtos/$nomeArquivo'; // <-- Alteração
  }

  // Busca imagem automaticamente usando código de barras
  Future<void> _buscarImagemAutomatica() async {
    final codigo = _codigoBarrasController.text.trim();
    if (codigo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Informe o código de barras para buscar a imagem')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // **ALTERAÇÃO**: Busca no servidor pelo código de barras
      String urlEncontrada = 'http://imagens.lukz.com.br/produtos/$codigo.png';
      setState(() {
        _imagemAutomaticaUrl = urlEncontrada;
        if (_novaImagemFile == null) {
          _imagemUrlAtual = _imagemAutomaticaUrl;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imagem automática atribuída!')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Salva alterações no Firestore
  Future<void> _salvarEdicao() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    String? imagemUrlParaSalvar = _imagemUrlAtual;

    if (_novaImagemFile != null) {
      // **ALTERAÇÃO**: Gera URL em vez de fazer upload no Firebase
      String? novaUrl = await _gerarUrlImagemServidor(_novaImagemFile!);
      if (novaUrl != null) {
        imagemUrlParaSalvar = novaUrl;
      } else {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Falha ao gerar URL da nova imagem.')));
        return;
      }
    }

    final produtoAtualizado = Produto(
      id: widget.produto.id,
      nome: _nomeController.text,
      categoria: _categoriaController.text,
      preco: double.tryParse(_precoController.text.replaceAll(',', '.')) ??
          widget.produto.preco,
      precoPromocional: double.tryParse(
              _precoPromocionalController.text.replaceAll(',', '.')) ??
          widget.produto.precoPromocional,
      descricao: _descricaoController.text,
      codigoBarras: _codigoBarrasController.text,
      custo: double.tryParse(_custoController.text.replaceAll(',', '.')) ??
          widget.produto.custo,
      estoqueAtual: int.tryParse(_estoqueAtualController.text) ??
          widget.produto.estoqueAtual,
      estoqueMinimo: int.tryParse(_estoqueMinimoController.text) ??
          widget.produto.estoqueMinimo,
      imagemUrl: imagemUrlParaSalvar ?? widget.produto.imagemUrl,
      imagemAutomaticaUrl: _imagemAutomaticaUrl,
      destacar: _destacarProduto,
      exibirNoCatalogo: _exibirNoCatalogo,
      precoIfood:
          double.tryParse(_precoIfoodController.text.replaceAll(',', '.')) ??
              widget.produto.precoIfood,
      markup: _markupController.text.isNotEmpty
          ? _markupController.text
          : widget.produto.markup,
      lucro: _lucroController.text.isNotEmpty
          ? _lucroController.text
          : widget.produto.lucro,
      validade: _validadeController.text.isNotEmpty
          ? _validadeController.text
          : widget.produto.validade,
      empresa: _empresaController.text.isNotEmpty
          ? _empresaController.text
          : widget.produto.empresa,
      precoConcorrencia: double.tryParse(
              _precoConcorrenciaController.text.replaceAll(',', '.')) ??
          widget.produto.precoConcorrencia,
    );

    try {
      await Provider.of<ProdutoProvider>(context, listen: false)
          .atualizarProduto(produtoAtualizado);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Produto atualizado com sucesso!')));
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao atualizar produto: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Campo de categorias com autocomplete
  Widget _buildCategoriaField() {
    return Autocomplete<String>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text == '') {
          return const Iterable<String>.empty();
        }
        return _categoriasExistentes.where((String option) {
          return option
              .toLowerCase()
              .contains(textEditingValue.text.toLowerCase());
        });
      },
      onSelected: (String selection) {
        _categoriaController.text = selection;
      },
      fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(labelText: 'Categoria'),
          validator: (value) =>
              value == null || value.isEmpty ? 'Informe a categoria' : null,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Editar Produto'),
        actions: [
          _isLoading
              ? Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : IconButton(icon: Icon(Icons.save), onPressed: _salvarEdicao),
        ],
      ),
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Exibe a imagem atual ou a nova selecionada
                CircleAvatar(
                  radius: 50,
                  backgroundImage: _novaImagemFile != null
                      ? FileImage(File(_novaImagemFile!.path))
                      : (_imagemUrlAtual != null
                              ? NetworkImage(_imagemUrlAtual!)
                              : AssetImage('assets/placeholder.png'))
                          as ImageProvider,
                ),
                TextButton.icon(
                  icon: Icon(Icons.photo),
                  label: Text('Selecionar nova imagem'),
                  onPressed: _selecionarNovaImagem,
                ),
                TextButton.icon(
                  icon: Icon(Icons.search),
                  label: Text('Buscar imagem automática'),
                  onPressed: _buscarImagemAutomatica,
                ),
                SizedBox(height: 16.0),
                TextFormField(
                  controller: _nomeController,
                  decoration: InputDecoration(labelText: 'Nome'),
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Informe o nome' : null,
                ),
                SizedBox(height: 16.0),
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
                TextFormField(
                  controller: _precoController,
                  decoration: InputDecoration(labelText: 'Preço'),
                  keyboardType: TextInputType.number,
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Informe o preço' : null,
                ),
                SizedBox(height: 16.0),
                TextFormField(
                  controller: _codigoBarrasController,
                  decoration: InputDecoration(
                      labelText: 'Código de Barras (Opcional)',
                      border: OutlineInputBorder()),
                  keyboardType: TextInputType.text, // Pode ser alfanumérico
                ),
                SizedBox(height: 16.0),

                TextFormField(
                  controller: _custoController,
                  decoration: InputDecoration(
                      labelText: 'Custo (R\$)',
                      border: OutlineInputBorder(),
                      prefixText: 'R\$ '),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value == null || value.isEmpty)
                      return 'Campo obrigatório';
                    if (double.tryParse(value.replaceAll(',', '.')) == null)
                      return 'Número inválido';
                    return null;
                  },
                ),
                SizedBox(height: 16.0),

                TextFormField(
                  controller: _estoqueAtualController,
                  decoration: InputDecoration(
                      labelText: 'Estoque Atual', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty)
                      return 'Campo obrigatório';
                    if (int.tryParse(value) == null)
                      return 'Número inteiro inválido';
                    return null;
                  },
                ),
                SizedBox(height: 16.0),

                TextFormField(
                  controller: _estoqueMinimoController,
                  decoration: InputDecoration(
                      labelText: 'Estoque Mínimo',
                      border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty)
                      return 'Campo obrigatório';
                    if (int.tryParse(value) == null)
                      return 'Número inteiro inválido';
                    return null;
                  },
                ),
                SizedBox(height: 16.0),

                TextFormField(
                  controller: _precoIfoodController,
                  decoration: InputDecoration(
                      labelText: 'Preço iFood (R\$) (Opcional)',
                      border: OutlineInputBorder(),
                      prefixText: 'R\$ '),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value != null &&
                        value.isNotEmpty &&
                        double.tryParse(value.replaceAll(',', '.')) == null)
                      return 'Número inválido';
                    return null;
                  },
                ),
                SizedBox(height: 16.0),

                TextFormField(
                  controller: _markupController,
                  decoration: InputDecoration(
                      labelText: 'Markup (%) (Opcional)',
                      border: OutlineInputBorder(),
                      suffixText: '%'),
                  keyboardType:
                      TextInputType.text, // Pode ser número ou texto simples
                ),
                SizedBox(height: 16.0),

                TextFormField(
                  controller: _lucroController,
                  decoration: InputDecoration(
                      labelText: 'Lucro (%) (Opcional)',
                      border: OutlineInputBorder(),
                      suffixText: '%'),
                  keyboardType:
                      TextInputType.text, // Pode ser número ou texto simples
                ),
                SizedBox(height: 16.0),

                TextFormField(
                  controller: _validadeController,
                  decoration: InputDecoration(
                      labelText: 'Validade (Opcional)',
                      border: OutlineInputBorder(),
                      hintText: 'DD/MM/AAAA ou texto'),
                  keyboardType: TextInputType.datetime,
                ),
                SizedBox(height: 16.0),

                TextFormField(
                  controller: _empresaController,
                  decoration: InputDecoration(
                      labelText: 'Empresa/Fornecedor (Opcional)',
                      border: OutlineInputBorder()),
                ),
                SizedBox(height: 16.0),

                TextFormField(
                  controller: _precoConcorrenciaController,
                  decoration: InputDecoration(
                      labelText: 'Preço Concorrência (R\$) (Opcional)',
                      border: OutlineInputBorder(),
                      prefixText: 'R\$ '),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value != null &&
                        value.isNotEmpty &&
                        double.tryParse(value.replaceAll(',', '.')) == null)
                      return 'Número inválido';
                    return null;
                  },
                ),
                SizedBox(height: 24.0),
                // Espaçamento antes dos Switches

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
                SizedBox(height: 32.0),
                // Espaçamento antes do botão salvar (se não estiver na AppBar)

                // O botão de salvar já está na AppBar, então não é necessário aqui
                // a menos que você queira um botão adicional no corpo do formulário.
              ],
            ),
          )),
    );
  }
}
