import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();

  factory DatabaseHelper() {
    return _instance;
  }

  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'app_database.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
    CREATE TABLE clientes (
      id TEXT PRIMARY KEY,
      nome TEXT NOT NULL,
      celular TEXT NOT NULL,
      email TEXT,
      endereco TEXT,
      cpf TEXT,
      pet TEXT
    )
  ''');
  

    await db.execute('''
      CREATE TABLE produtos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome TEXT NOT NULL,
        preco REAL NOT NULL,
        descricao TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE pedidos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        clienteId INTEGER NOT NULL,
        data TEXT NOT NULL,
        total REAL NOT NULL,
        status TEXT NOT NULL,
        FOREIGN KEY (clienteId) REFERENCES clientes (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE pedido_itens (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pedidoId INTEGER NOT NULL,
        produtoId INTEGER NOT NULL,
        quantidade INTEGER NOT NULL,
        subtotal REAL NOT NULL,
        FOREIGN KEY (pedidoId) REFERENCES pedidos (id),
        FOREIGN KEY (produtoId) REFERENCES produtos (id)
      )
    ''');
  }
}
