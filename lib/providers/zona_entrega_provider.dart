import 'package:flutter/material.dart';

import '../models/zona_entrega.dart';
import '../repositories/zona_entrega_repository.dart';

class ZonaEntregaProvider with ChangeNotifier {
  ZonaEntregaProvider({String tabela = 'zonas_entrega'}) : _repository = ZonaEntregaRepository(tabela: tabela);

  final ZonaEntregaRepository _repository;

  List<ZonaEntrega> _zonas = [];
  bool _carregando = false;
  String? _erro;
  String? _empresaId;
  DateTime? _carregadoEm;

  List<ZonaEntrega> get zonas => _zonas;
  bool get carregando => _carregando;
  String? get erro => _erro;

  /// Chamado uma vez pelo AuthGate assim que sabemos a empresa do usuário
  /// logado — necessário pra criar novas zonas (empresa_id é obrigatório).
  void definirEmpresa(String empresaId) {
    _empresaId = empresaId;
  }

  Future<void> carregarZonas() async {
    _carregando = true;
    _erro = null;
    notifyListeners();

    try {
      _zonas = await _repository.listar();
      _carregadoEm = DateTime.now();
    } catch (e) {
      _erro = 'Erro ao carregar zonas de entrega: $e';
      debugPrint(_erro);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  /// Recarrega se as faixas tiverem mais de [maxIdade]. O app carrega as
  /// zonas no login, mas domingo/feriado mudam frete, frete grátis e prazo
  /// no meio do dia (ajustes_temporarios) — sem isso o PDV mostrava os
  /// valores de quando o app abriu (achado real 20/11).
  Future<void> garantirAtualizadas({Duration maxIdade = const Duration(minutes: 5)}) async {
    if (_carregando) return;
    if (_carregadoEm != null && DateTime.now().difference(_carregadoEm!) < maxIdade) return;
    await carregarZonas();
  }

  Future<void> criarZona(ZonaEntrega zona) async {
    if (_empresaId == null) {
      throw StateError('Nenhuma empresa definida no ZonaEntregaProvider ainda.');
    }
    final criada = await _repository.criar(zona, empresaId: _empresaId!);
    _zonas.add(criada);
    _zonas.sort((a, b) => a.distanciaMinKm.compareTo(b.distanciaMinKm));
    notifyListeners();
  }

  Future<void> atualizarZona(ZonaEntrega zona) async {
    await _repository.atualizar(zona);
    final index = _zonas.indexWhere((z) => z.id == zona.id);
    if (index != -1) _zonas[index] = zona;
    _zonas.sort((a, b) => a.distanciaMinKm.compareTo(b.distanciaMinKm));
    notifyListeners();
  }

  Future<void> excluirZona(String id) async {
    await _repository.excluir(id);
    _zonas.removeWhere((z) => z.id == id);
    notifyListeners();
  }

  /// Encontra a zona que cobre uma distância — usada no checkout pra
  /// decidir o valor do frete a partir do km calculado até o cliente.
  ZonaEntrega? zonaParaDistancia(double km) {
    for (final zona in _zonas) {
      if (zona.ativo && zona.cobreDistancia(km)) return zona;
    }
    return null;
  }
}
