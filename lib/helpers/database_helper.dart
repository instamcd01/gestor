// import 'package:sqflite/sqflite.dart';
// import 'package:path/path.dart';
// import '../models/produto.dart';
//
// class DatabaseHelper {
//   static final DatabaseHelper _instance = DatabaseHelper._internal();
//   factory DatabaseHelper() => _instance;
//
//   static Database? _database;
//
//   DatabaseHelper._internal();
//
//   Future<Database> get database async {
//     if (_database != null) return _database!;
//     _database = await _initDatabase();
//     return _database!;
//   }
//
//   Future<Database> _initDatabase() async {
//     final path = join(await getDatabasesPath(), 'produtos.db');
//     return await openDatabase(
//       path,
//       version: 1,
//       onCreate: (db, version) async {
//         await db.execute('''
//           CREATE TABLE produtos (
//             id TEXT PRIMARY KEY,
//             nome TEXT,
//             preco REAL,
//             imagemUrl TEXT,
//             categoria TEXT,
//             estoqueAtual INTEGER
//           )
//         ''');
//       },
//     );
//   }
//
//   Future<void> inserirProduto(Produto produto) async {
//     final db = await database;
//     await db.insert('produtos', produto.toJson(),
//         conflictAlgorithm: ConflictAlgorithm.replace);
//   }
//
//   Future<List<Produto>> listarProdutos() async {
//     final db = await database;
//     final List<Map<String, dynamic>> maps = await db.query('produtos');
//
//     return List.generate(maps.length, (i) {
//       return Produto.fromJson(maps[i]);
//     });
//   }
//
//   Future<void> deletarProduto(String id) async {
//     final db = await database;
//     await db.delete('produtos', where: 'id = ?', whereArgs: [id]);
//   }
//
//   Future<void> atualizarProduto(Produto produto) async {
//     final db = await database;
//     await db.update('produtos', produto.toJson(),
//         where: 'id = ?', whereArgs: [produto.id]);
//   }
// }
//////////////////////////////////////

//////////////////////////// ultimo utilizado abaixo
// import 'package:sqflite/sqflite.dart';
// import 'package:path/path.dart';
// import '../models/produto.dart';
//
// class DatabaseHelper {
//   static final DatabaseHelper _instance = DatabaseHelper._internal();
//   static DatabaseHelper get instance => _instance;
//
//   static const String _tableName = 'produtos';
//   static Database? _database;
//
//   DatabaseHelper._internal();
//
//   // Inicializa o banco de dados
//   Future<Database> getDatabase() async {
//     if (_database != null) return _database!;
//
//     final dbPath = await getDatabasesPath();
//     final path = join(dbPath, 'produtos.db');
//
//     _database = await openDatabase(
//       path,
//       version: 1,
//       onCreate: (db, version) {
//         return db.execute(
//           '''CREATE TABLE $_tableName(
//             id TEXT PRIMARY KEY,
//             nome TEXT,
//             preco REAL,
//             precoPromocional REAL,
//             imagemUrl TEXT,
//             categoria TEXT,
//             estoqueAtual INTEGER,
//             estoqueMinimo INTEGER,
//             codigoBarras TEXT,
//             custo REAL,
//             destacar INTEGER,
//             exibirNoCatalogo INTEGER,
//             precoIfood REAL,
//             markup TEXT,
//             lucro TEXT,
//             precoConcorrencia TEXT,
//             validade TEXT,
//             empresa TEXT
//           )''',
//         );
//       },
//     );
//     return _database!;
//   }
//
//   // Inserir um produto
//   Future<void> inserirProduto(Produto produto) async {
//     final db = await getDatabase();
//     await db.insert(
//       _tableName,
//       produto.toMap(),
//       conflictAlgorithm: ConflictAlgorithm.replace,
//     );
//   }
//
//   // Buscar todos os produtos
//   Future<List<Produto>> buscarProdutos() async {
//     final db = await getDatabase();
//     final List<Map<String, dynamic>> produtosData = await db.query(_tableName);
//
//     return produtosData.map((produto) => Produto.fromMap(produto)).toList();
//   }
//
//   // Atualizar um produto
//   Future<void> atualizarProduto(Produto produto) async {
//     final db = await getDatabase();
//     await db.update(
//       _tableName,
//       produto.toMap(),
//       where: 'id = ?',
//       whereArgs: [produto.id],
//     );
//   }
//
//   // Remover um produto
//   Future<void> removerProduto(String id) async {
//     final db = await getDatabase();
//     await db.delete(
//       _tableName,
//       where: 'id = ?',
//       whereArgs: [id],
//     );
//   }
// }
