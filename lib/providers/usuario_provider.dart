import 'package:flutter/material.dart';
import '../models/convite_empresa.dart';
import '../models/usuario.dart';
import '../repositories/usuario_repository.dart';

class UsuarioProvider with ChangeNotifier {
  final UsuarioRepository _repository = UsuarioRepository();

  List<Usuario> _usuarios = [];
  List<ConviteEmpresa> _convites = [];
  bool _carregando = false;
  String? _erro;
  String? _empresaId;

  List<Usuario> get usuarios => _usuarios;
  List<ConviteEmpresa> get convitesPendentes => _convites.where((c) => c.pendente).toList();
  bool get carregando => _carregando;
  String? get erro => _erro;

  void definirEmpresa(String empresaId) {
    _empresaId = empresaId;
  }

  Future<void> carregar() async {
    _carregando = true;
    _erro = null;
    notifyListeners();

    try {
      _usuarios = await _repository.listar();
      _convites = await _repository.listarConvites();
    } catch (e) {
      _erro = 'Erro ao carregar usuários: $e';
      debugPrint(_erro);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> atualizarPapel(String usuarioId, String papel) async {
    await _repository.atualizarPapel(usuarioId, papel);
    await carregar();
  }

  Future<void> atualizarAtivo(String usuarioId, bool ativo) async {
    await _repository.atualizarAtivo(usuarioId, ativo);
    await carregar();
  }

  Future<void> atualizarNome(String usuarioId, String nome) async {
    await _repository.atualizarNome(usuarioId, nome);
    await carregar();
  }

  Future<ConviteEmpresa> gerarConvite({required String criadoPor, required String papel}) async {
    if (_empresaId == null) {
      throw StateError('Nenhuma empresa definida no UsuarioProvider ainda.');
    }
    final convite = await _repository.gerarConvite(
      empresaId: _empresaId!,
      criadoPor: criadoPor,
      papel: papel,
    );
    await carregar();
    return convite;
  }

  Future<void> revogarConvite(String conviteId) async {
    await _repository.revogarConvite(conviteId);
    await carregar();
  }
}
