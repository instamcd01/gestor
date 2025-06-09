// import 'package:sqflite/sqflite.dart';
//
// import '../models/cliente.dart';
// import 'database_helper.dart';
//
//
// class ClienteDao {
//   final DatabaseHelper _dbHelper = DatabaseHelper();
//   late Database _db;
//
//   Future<int> inserirCliente(Cliente cliente) async {
//     final db = await _dbHelper.database;
//     return await db.insert(
//       'clientes',
//       cliente.toMap(),
//       conflictAlgorithm: ConflictAlgorithm.replace,
//     );
//   }
//   // Método para buscar todos os clientes
//   Future<List<Cliente>> buscarClientes() async {
//     final List<Map<String, dynamic>> maps = await _db.query('clientes');
//     return List.generate(maps.length, (i) {
//       return Cliente(
//         idCliente: maps[i]['id'],
//         nome: maps[i]['nome'],
//         celular: maps[i]['celular'],
//         email: maps[i]['email'],
//         endereco: maps[i]['endereco'],
//         complemento: maps[i]['complemento'],
//         cpf: maps[i]['cpf'],
//         pet: maps[i]['pet'],
//         observacao: maps[i]['observacao'],
//         saldo: maps[i]['saldo'],
//       );
//     });
//   }
//   Future<List<Cliente>> listarClientes() async {
//     final db = await _dbHelper.database;
//     final List<Map<String, dynamic>> maps = await db.query('clientes');
//     return List.generate(maps.length, (i) => Cliente.fromMap(maps[i]));
//   }
//
//   Future<int> atualizarCliente(Cliente cliente) async {
//     final db = await _dbHelper.database;
//     return await db.update(
//       'clientes',
//       cliente.toMap(),
//       where: 'id = ?',
//       whereArgs: [cliente.idCliente],
//     );
//   }
//
//   Future<int> deletarCliente(String id) async {
//     final db = await _dbHelper.database;
//     return await db.delete(
//       'clientes',
//       where: 'id = ?',
//       whereArgs: [id],
//     );
//   }
// }

import 'package:sqflite/sqflite.dart';
import '../models/cliente.dart';
import 'database_helper.dart';

class ClienteDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // Método para inserir um cliente
  Future<int> inserirCliente(Cliente cliente) async {
    final db = await _dbHelper.getDatabase();
    return await db.insert(
      'clientes',
      cliente.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Método para buscar todos os clientes
  Future<List<Cliente>> buscarClientes() async {
    final db = await _dbHelper.getDatabase();
    final List<Map<String, dynamic>> maps = await db.query('clientes');
    return List.generate(maps.length, (i) {
      return Cliente(
        idCliente: maps[i]['id'],
        nome: maps[i]['nome'],
        celular: maps[i]['celular'],
        email: maps[i]['email'],
        endereco: maps[i]['endereco'],
        complemento: maps[i]['complemento'],
        cpf: maps[i]['cpf'],
        pet: maps[i]['pet'],
        observacao: maps[i]['observacao'],
        saldo: maps[i]['saldo'],
      );
    });
  }

  // Método para listar clientes usando o fromMap
  Future<List<Cliente>> listarClientes() async {
    final db = await _dbHelper.getDatabase();
    final List<Map<String, dynamic>> maps = await db.query('clientes');
    return List.generate(maps.length, (i) => Cliente.fromMap(maps[i]));
  }

  // Método para atualizar um cliente
  Future<int> atualizarCliente(Cliente cliente) async {
    final db = await _dbHelper.getDatabase();
    return await db.update(
      'clientes',
      cliente.toMap(),
      where: 'id = ?',
      whereArgs: [cliente.idCliente],
    );
  }

  // Método para deletar um cliente
  Future<int> deletarCliente(String id) async {
    final db = await _dbHelper.getDatabase();
    return await db.delete(
      'clientes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
