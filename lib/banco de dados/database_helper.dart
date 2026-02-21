// import 'package:sqflite/sqflite.dart';
// import 'package:path/path.dart';
//
// class DatabaseHelper {
//   static final DatabaseHelper _instance = DatabaseHelper._internal();
//   static DatabaseHelper get instance => _instance;
//   factory DatabaseHelper() {
//     return _instance;
//   }
//
//   DatabaseHelper._internal();
//
//   static Database? _database;
//
//   Future<Database> get database async {
//     if (_database != null) return _database!;
//     _database = await _initDatabase();
//     return _database!;
//   }
//
//   Future<Database> _initDatabase() async {
//     final dbPath = await getDatabasesPath();
//     final path = join(dbPath, 'app_database.db');
//
//     return await openDatabase(
//       path,
//       version: 1,
//       onCreate: _onCreate,
//     );
//   }
//
//   Future<void> _onCreate(Database db, int version) async {
//     await db.execute('''
//     CREATE TABLE clientes (
//       id TEXT PRIMARY KEY,
//       nome TEXT NOT NULL,
//       celular TEXT NOT NULL,
//       email TEXT,
//       endereco TEXT,
//       cpf TEXT,
//       pet TEXT
//     )
//   ''');
//
//
//     await db.execute('''
//       CREATE TABLE produtos (
//         id INTEGER PRIMARY KEY AUTOINCREMENT,
//         nome TEXT NOT NULL,
//         preco REAL NOT NULL,
//         descricao TEXT
//       )
//     ''');
//
//     await db.execute('''
//       CREATE TABLE pedidos (
//         id INTEGER PRIMARY KEY AUTOINCREMENT,
//         clienteId INTEGER NOT NULL,
//         data TEXT NOT NULL,
//         total REAL NOT NULL,
//         status TEXT NOT NULL,
//         FOREIGN KEY (clienteId) REFERENCES clientes (id)
//       )
//     ''');
//
//     await db.execute('''
//       CREATE TABLE pedido_itens (
//         id INTEGER PRIMARY KEY AUTOINCREMENT,
//         pedidoId INTEGER NOT NULL,
//         produtoId INTEGER NOT NULL,
//         quantidade INTEGER NOT NULL,
//         subtotal REAL NOT NULL,
//         FOREIGN KEY (pedidoId) REFERENCES pedidos (id),
//         FOREIGN KEY (produtoId) REFERENCES produtos (id)
//       )
//     ''');
//   }
// }
///////////////////////////////////
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
//   // Métodos não são mais estáticos!
//   Future<void> inserirProduto(Produto produto) async {
//     final db = await getDatabase();
//     await db.insert(
//       _tableName,
//       produto.toMap(),
//       conflictAlgorithm: ConflictAlgorithm.replace,
//     );
//   }
//
//   Future<List<Produto>> buscarProdutos() async {
//     final db = await getDatabase();
//     final List<Map<String, dynamic>> produtosData = await db.query(_tableName);
//
//     return produtosData.map((produto) => Produto.fromMap(produto)).toList();
//   }
//
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
//   Future<void> removerProduto(String id) async {
//     final db = await getDatabase();
//     await db.delete(
//       _tableName,
//       where: 'id = ?',
//       whereArgs: [id],
//     );
//   }
// }
