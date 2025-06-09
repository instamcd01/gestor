import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/produto.dart';

class ProdutoDBHelper {
  static final ProdutoDBHelper _instance = ProdutoDBHelper._internal();

  factory ProdutoDBHelper() => _instance;

  ProdutoDBHelper._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final path = join(await getDatabasesPath(), 'produtos.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE produtos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nome TEXT,
            preco REAL,
            precoPromocional REAL,
            descricao TEXT,
            categoria TEXT,
            estoqueAtual INTEGER,
            estoqueMinimo INTEGER,
            imagemUrl TEXT,
            codigoBarras TEXT UNIQUE,
            custo REAL,
            destacar INTEGER,
            exibirNoCatalogo INTEGER,
            precoIfood REAL,
            validade TEXT,
            markup TEXT,
            lucro TEXT,
            empresa TEXT,
            precoConcorrencia TEXT
          )
        ''');
      },
    );
  }

  Future<int> inserirProduto(Produto produto) async {
    final db = await database;
    return await db.insert('produtos', produto.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Produto>> buscarTodosProdutos() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('produtos');
    return List.generate(maps.length, (i) => Produto.fromMap(maps[i]));
  }

  Future<int> atualizarProduto(Produto produto) async {
    final db = await database;
    return await db.update(
      'produtos',
      produto.toMap(),
      where: 'id = ?',
      whereArgs: [produto.id],
    );
  }

  Future<int> deletarProduto(int id) async {
    final db = await database;
    return await db.delete(
      'produtos',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
