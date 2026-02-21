// import 'package:flutter/material.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
//
// class CategoriaScreen extends StatefulWidget {
//   @override
//   _CategoriaScreenState createState() => _CategoriaScreenState();
// }
//
// class _CategoriaScreenState extends State<CategoriaScreen> {
//   final FirebaseFirestore _firestore = FirebaseFirestore.instance;
//   final TextEditingController _categoriaController = TextEditingController();
//   final TextEditingController _novaCategoriaController = TextEditingController();
//
//   List<Map<String, dynamic>> _categorias = []; // {id, nome, ordem}
//
//   @override
//   void initState() {
//     super.initState();
//     _carregarCategorias();
//   }
//
//   Future<void> _carregarCategorias() async {
//     // Busca categorias do Firestore
//     final snapshotCategorias = await _firestore
//         .collection("categorias")
//         .orderBy("ordem")
//         .get();
//
//     List<Map<String, dynamic>> categoriasFirestore = snapshotCategorias.docs
//         .map((doc) => {
//       "id": doc.id,
//       "nome": doc["nome"],
//       "ordem": doc["ordem"],
//     })
//         .toList();
//
//     // Busca categorias existentes nos produtos
//     final snapshotProdutos = await _firestore.collection("produtos").get();
//     List<String> categoriasProdutos = snapshotProdutos.docs
//         .map((doc) => doc['categoria'] as String? ?? '')
//         .where((c) => c.isNotEmpty)
//         .toSet()
//         .toList();
//
//     // Combina listas, evita duplicadas
//     for (var catProd in categoriasProdutos) {
//       if (!categoriasFirestore.any((c) => c["nome"] == catProd)) {
//         categoriasFirestore.add({
//           "id": null,
//           "nome": catProd,
//           "ordem": categoriasFirestore.length,
//         });
//       }
//     }
//
//     setState(() {
//       _categorias = categoriasFirestore;
//     });
//   }
//
//   Future<void> _adicionarCategoria(String nome) async {
//     if (nome.isEmpty) return;
//
//     final novaCategoria = {
//       "nome": nome,
//       "ordem": _categorias.isNotEmpty
//           ? _categorias.map((c) => c["ordem"] as int).reduce((a, b) => a > b ? a : b) + 1
//           : 0,
//     };
//
//     await _firestore.collection("categorias").add(novaCategoria);
//     await _carregarCategorias();
//   }
//
//   Future<void> _editarCategoria(String? id, String novoNome) async {
//     if (novoNome.isEmpty) return;
//
//     if (id != null) {
//       // Categoria existente no Firestore: atualiza
//       await _firestore.collection("categorias").doc(id).update({"nome": novoNome});
//     } else {
//       // Categoria só existente nos produtos: cria novo documento
//       final novaCategoria = {
//         "nome": novoNome,
//         "ordem": _categorias.length,
//       };
//       await _firestore.collection("categorias").add(novaCategoria);
//     }
//
//     await _carregarCategorias();
//   }
//
//
//   Future<void> _reordenarCategorias(int oldIndex, int newIndex) async {
//     if (newIndex > oldIndex) newIndex--;
//
//     final movedItem = _categorias.removeAt(oldIndex);
//     _categorias.insert(newIndex, movedItem);
//
//     // Atualiza a ordem no Firestore apenas para categorias que possuem id
//     for (int i = 0; i < _categorias.length; i++) {
//       if (_categorias[i]["id"] != null) {
//         await _firestore
//             .collection("categorias")
//             .doc(_categorias[i]["id"])
//             .update({"ordem": i});
//       }
//     }
//
//     setState(() {});
//   }
//
//   void _editarCategoriaDialog(int index) {
//     final controllerEdicao = TextEditingController(text: _categorias[index]["nome"]);
//     showDialog(
//       context: context,
//       builder: (context) {
//         return AlertDialog(
//           title: Text("Editar Categoria"),
//           content: TextField(
//             controller: controllerEdicao,
//             decoration: InputDecoration(labelText: "Novo nome"),
//           ),
//           actions: [
//             TextButton(
//               child: Text("Cancelar"),
//               onPressed: () => Navigator.pop(context),
//             ),
//             ElevatedButton(
//               child: Text("Salvar"),
//               onPressed: () async {
//                 await _editarCategoria(_categorias[index]["id"], controllerEdicao.text);
//                 Navigator.pop(context);
//               },
//             ),
//           ],
//         );
//       },
//     );
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: Text("Categorias")),
//       body: Column(
//         children: [
//           // Campo de seleção de categoria
//           Padding(
//             padding: const EdgeInsets.all(16.0),
//             child: TextField(
//               controller: _categoriaController,
//               readOnly: true,
//               decoration: InputDecoration(
//                 labelText: "Categoria selecionada",
//                 suffixIcon: Icon(Icons.arrow_drop_down),
//                 border: OutlineInputBorder(),
//               ),
//             ),
//           ),
//
//           // Lista de categorias dinamica e reordenável
//           Expanded(
//             child: ReorderableListView(
//               onReorder: _reordenarCategorias,
//               padding: EdgeInsets.symmetric(horizontal: 16),
//               children: [
//                 for (int index = 0; index < _categorias.length; index++)
//                   ListTile(
//                     key: ValueKey(_categorias[index]["id"] ?? _categorias[index]["nome"]),
//                     title: Text(_categorias[index]["nome"]),
//                     trailing: Row(
//                       mainAxisSize: MainAxisSize.min,
//                       children: [
//                         if (_categorias[index]["id"] != null)
//                           IconButton(
//                             icon: Icon(Icons.edit, color: Colors.grey),
//                             onPressed: () => _editarCategoriaDialog(index),
//                           ),
//                         Icon(Icons.drag_handle, color: Colors.grey),
//                       ],
//                     ),
//                     onTap: () {
//                       setState(() {
//                         _categoriaController.text = _categorias[index]["nome"];
//                       });
//                     },
//                   ),
//               ],
//             ),
//           ),
//
//           // Campo para adicionar nova categoria
//           Padding(
//             padding: const EdgeInsets.all(16.0),
//             child: Row(
//               children: [
//                 Expanded(
//                   child: TextField(
//                     controller: _novaCategoriaController,
//                     decoration: InputDecoration(
//                       labelText: "Nova categoria",
//                       border: OutlineInputBorder(),
//                     ),
//                   ),
//                 ),
//                 SizedBox(width: 8),
//                 ElevatedButton(
//                   onPressed: () async {
//                     if (_novaCategoriaController.text.isNotEmpty) {
//                       await _adicionarCategoria(_novaCategoriaController.text);
//                       _novaCategoriaController.clear();
//                     }
//                   },
//                   child: Text("Adicionar"),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CategoriaScreen extends StatefulWidget {
  final String? categoriaSelecionada; // categoria já selecionada, se houver

  const CategoriaScreen({this.categoriaSelecionada, Key? key}) : super(key: key);

  @override
  _CategoriaScreenState createState() => _CategoriaScreenState();
}

class _CategoriaScreenState extends State<CategoriaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _categoriaController = TextEditingController();
  final TextEditingController _novaCategoriaController = TextEditingController();

  List<Map<String, dynamic>> _categorias = []; // {id, nome, ordem}

  @override
  void initState() {
    super.initState();
    if (widget.categoriaSelecionada != null) {
      _categoriaController.text = widget.categoriaSelecionada!;
    }
    _carregarCategorias();
  }

  Future<void> _carregarCategorias() async {
    try {
      // 1️⃣ Carrega categorias da coleção
      final snapshotCategorias = await _firestore
          .collection("categorias")
          .orderBy("ordem")
          .get();

      List<Map<String, dynamic>> categoriasFirestore = snapshotCategorias.docs
          .map((doc) => {
        "id": doc.id,
        "nome": doc["nome"],
        "ordem": doc["ordem"],
      })
          .toList();

      // 2️⃣ Busca categorias existentes nos produtos
      final snapshotProdutos = await _firestore.collection("produtos").get();
      List<String> categoriasProdutos = snapshotProdutos.docs
          .map((doc) => doc['categoria'] as String? ?? '')
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList();

      // 3️⃣ Adiciona categorias de produtos que ainda não estão na coleção
      for (var catProd in categoriasProdutos) {
        if (!categoriasFirestore
            .any((c) => c["nome"].toLowerCase() == catProd.toLowerCase())) {
          final docRef = await _firestore.collection("categorias").add({
            "nome": catProd,
            "ordem": categoriasFirestore.length,
          });
          categoriasFirestore.add({
            "id": docRef.id,
            "nome": catProd,
            "ordem": categoriasFirestore.length,
          });
        }
      }

      setState(() {
        _categorias = categoriasFirestore;
      });
    } catch (e) {
      print("Erro ao carregar categorias: $e");
    }
  }

  Future<void> _adicionarCategoria(String nome) async {
    if (nome.isEmpty) return;

    if (_categorias.any((c) => c["nome"].toLowerCase() == nome.toLowerCase())) return;

    final novaCategoria = {
      "nome": nome,
      "ordem": _categorias.isNotEmpty
          ? _categorias.map((c) => c["ordem"] as int).reduce((a, b) => a > b ? a : b) + 1
          : 0,
    };

    await _firestore.collection("categorias").add(novaCategoria);
    await _carregarCategorias();
  }

  Future<void> _editarCategoria(String? id, String novoNome) async {
    if (novoNome.isEmpty) return;

    // Evita duplicatas
    if (_categorias.any((c) =>
    c["nome"].toLowerCase() == novoNome.toLowerCase() &&
        c["id"] != id)) return;

    if (id != null) {
      final antigaCategoria =
      _categorias.firstWhere((c) => c["id"] == id)["nome"];
      await _firestore.collection("categorias").doc(id).update({"nome": novoNome});

      // Atualiza todos os produtos que usam essa categoria
      final snapshotProdutos = await _firestore
          .collection("produtos")
          .where("categoria", isEqualTo: antigaCategoria)
          .get();

      for (var doc in snapshotProdutos.docs) {
        await _firestore.collection("produtos").doc(doc.id).update({
          "categoria": novoNome,
        });
      }
    } else {
      // Cria nova categoria
      await _adicionarCategoria(novoNome);
    }

    await _carregarCategorias();
  }

  Future<void> _excluirCategoria(String? id) async {
    if (id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Excluir categoria"),
        content: Text("Deseja realmente excluir esta categoria? Os produtos que a utilizam ficarão como 'Sem categoria'."),
        actions: [
          TextButton(
            child: Text("Cancelar"),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            child: Text("Excluir"),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final antigaCategoria =
    _categorias.firstWhere((c) => c["id"] == id)["nome"];

    // Atualiza produtos que utilizam a categoria para "Sem categoria"
    final snapshotProdutos = await _firestore
        .collection("produtos")
        .where("categoria", isEqualTo: antigaCategoria)
        .get();

    for (var doc in snapshotProdutos.docs) {
      await _firestore.collection("produtos").doc(doc.id).update({
        "categoria": "Sem categoria",
      });
    }

    // Exclui a categoria
    await _firestore.collection("categorias").doc(id).delete();
    await _carregarCategorias();
  }

  Future<void> _reordenarCategorias(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final movedItem = _categorias.removeAt(oldIndex);
    _categorias.insert(newIndex, movedItem);

    for (int i = 0; i < _categorias.length; i++) {
      if (_categorias[i]["id"] != null) {
        await _firestore
            .collection("categorias")
            .doc(_categorias[i]["id"])
            .update({"ordem": i});
      }
    }
    setState(() {});
  }

  void _editarCategoriaDialog(int index) {
    final controllerEdicao = TextEditingController(text: _categorias[index]["nome"]);
    String? novaSelecionada;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text("Editar Categoria"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controllerEdicao,
                    decoration: InputDecoration(labelText: "Novo nome"),
                  ),
                  SizedBox(height: 16),
                  DropdownButton<String>(
                    value: novaSelecionada,
                    hint: Text("Selecionar outra categoria para mesclar"),
                    isExpanded: true,
                    items: _categorias
                        .where((c) => c["id"] != _categorias[index]["id"])
                        .map<DropdownMenuItem<String>>(
                          (c) => DropdownMenuItem<String>(
                        value: c["nome"] as String,
                        child: Text(c["nome"] as String),
                      ),
                    )
                        .toList(),
                    onChanged: (val) {
                      setStateDialog(() {
                        novaSelecionada = val;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  child: Text("Cancelar"),
                  onPressed: () => Navigator.pop(context),
                ),
                TextButton(
                  child: Text("Excluir", style: TextStyle(color: Colors.red)),
                  onPressed: () async {
                    bool confirmar = await showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text("Confirmação"),
                        content: Text("Deseja realmente excluir esta categoria? Produtos relacionados ficarão como 'Sem categoria'."),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("Cancelar")),
                          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Confirmar")),
                        ],
                      ),
                    );
                    if (confirmar) {
                      await _excluirCategoria(_categorias[index]["id"]);
                      Navigator.pop(context);
                    }
                  },
                ),
                ElevatedButton(
                  child: Text("Salvar"),
                  onPressed: () async {
                    String antigoNome = _categorias[index]["nome"];
                    if (novaSelecionada != null) {
                      // Mescla/atribui produtos para categoria existente
                      final snapshotProdutos = await _firestore
                          .collection("produtos")
                          .where("categoria", isEqualTo: antigoNome)
                          .get();
                      for (var doc in snapshotProdutos.docs) {
                        await _firestore.collection("produtos").doc(doc.id).update({
                          "categoria": novaSelecionada,
                        });
                      }
                      // Exclui a categoria antiga
                      await _firestore.collection("categorias").doc(_categorias[index]["id"]).delete();
                    } else {
                      // Apenas renomeia a categoria
                      await _editarCategoria(_categorias[index]["id"], controllerEdicao.text);
                    }
                    Navigator.pop(context);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }



  void _salvarEVoltar() {
    Navigator.pop(context, _categoriaController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Categorias"),
        actions: [
          TextButton(
            onPressed: _salvarEVoltar,
            child: Text("Salvar", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
      body: Column(
        children: [
          // Categoria selecionada no topo
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _categoriaController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: "Categoria selecionada",
                suffixIcon: Icon(Icons.arrow_drop_down),
                border: OutlineInputBorder(),
              ),
            ),
          ),

          // Lista reordenável
          Expanded(
            child: ReorderableListView(
              onReorder: _reordenarCategorias,
              padding: EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (int index = 0; index < _categorias.length; index++)
                  ListTile(
                    key: ValueKey(_categorias[index]["id"] ?? _categorias[index]["nome"]),
                    title: Text(_categorias[index]["nome"]),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_categorias[index]["id"] != null)
                          IconButton(
                            icon: Icon(Icons.edit, color: Colors.grey),
                            onPressed: () => _editarCategoriaDialog(index),
                          ),
                        Icon(Icons.drag_handle, color: Colors.grey),
                      ],
                    ),
                    onTap: () {
                      setState(() {
                        _categoriaController.text = _categorias[index]["nome"];
                      });
                    },
                  ),
              ],
            ),
          ),

          // Campo para adicionar nova categoria
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _novaCategoriaController,
                    decoration: InputDecoration(
                      labelText: "Nova categoria",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    if (_novaCategoriaController.text.isNotEmpty) {
                      await _adicionarCategoria(_novaCategoriaController.text);
                      _novaCategoriaController.clear();
                    }
                  },
                  child: Text("Adicionar"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
