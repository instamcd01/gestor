import 'package:flutter/material.dart';
import '../models/banner_home.dart';
import '../repositories/banner_home_repository.dart';

class BannerHomeProvider with ChangeNotifier {
  final BannerHomeRepository _repository = BannerHomeRepository();

  List<BannerHome> _banners = [];
  bool _carregando = false;
  String? _erro;
  String? _empresaId;

  List<BannerHome> get banners => _banners;
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
      _banners = await _repository.listar();
    } catch (e) {
      _erro = 'Erro ao carregar banners: $e';
      debugPrint(_erro);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> adicionar(BannerHome banner) async {
    if (_empresaId == null) {
      throw StateError('Nenhuma empresa definida no BannerHomeProvider ainda.');
    }
    final novo = await _repository.criar(banner, empresaId: _empresaId!);
    _banners.add(novo);
    notifyListeners();
  }

  Future<void> atualizar(BannerHome banner) async {
    await _repository.atualizar(banner);
    final index = _banners.indexWhere((b) => b.id == banner.id);
    if (index != -1) _banners[index] = banner;
    notifyListeners();
  }

  Future<void> excluir(String bannerId) async {
    await _repository.excluir(bannerId);
    _banners.removeWhere((b) => b.id == bannerId);
    notifyListeners();
  }

  Future<void> reordenar(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final movido = _banners.removeAt(oldIndex);
    _banners.insert(newIndex, movido);
    notifyListeners();
    await _repository.reordenar(_banners);
  }
}
