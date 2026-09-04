import 'package:flutter/material.dart';
import '../models/pedido_compra.dart';
import '../models/sugestao_planejamento.dart';
import '../repositories/sugestao_planejamento_repository.dart';

/// Carrega as 4 fontes de sugestão da aba Sugestões do Planejamento em
/// paralelo, cada uma com seu próprio estado de erro — uma RPC falhando
/// não deve esconder as outras 3 (por isso não é um `Future.wait` simples
/// que propaga a primeira exceção pra tudo).
class SugestaoPlanejamentoProvider with ChangeNotifier {
  final SugestaoPlanejamentoRepository _repository = SugestaoPlanejamentoRepository();

  String? _empresaId;
  bool _carregando = false;

  List<SugestaoCompra> _sugestoesCompra = [];
  String? _erroCompra;

  List<SugestaoRecompra> _sugestoesRecompra = [];
  String? _erroRecompra;

  List<SugestaoContatoParado> _contatosParados = [];
  String? _erroContatosParados;

  List<PostConteudoPendente> _conteudoPendente = [];
  String? _erroConteudoPendente;

  bool get carregando => _carregando;
  List<SugestaoCompra> get sugestoesCompra => _sugestoesCompra;
  String? get erroCompra => _erroCompra;
  List<SugestaoRecompra> get sugestoesRecompra => _sugestoesRecompra;
  String? get erroRecompra => _erroRecompra;
  List<SugestaoContatoParado> get contatosParados => _contatosParados;
  String? get erroContatosParados => _erroContatosParados;
  List<PostConteudoPendente> get conteudoPendente => _conteudoPendente;
  String? get erroConteudoPendente => _erroConteudoPendente;

  void definirEmpresa(String empresaId) {
    _empresaId = empresaId;
  }

  Future<void> carregar() async {
    if (_empresaId == null) return;
    _carregando = true;
    notifyListeners();

    try {
      _sugestoesCompra = await _repository.buscarSugestoesCompra(empresaId: _empresaId!);
      _erroCompra = null;
    } catch (e) {
      _erroCompra = 'Erro ao buscar sugestões de compra: $e';
      debugPrint(_erroCompra);
    }

    try {
      _sugestoesRecompra = await _repository.buscarSugestoesRecompra(empresaId: _empresaId!);
      _erroRecompra = null;
    } catch (e) {
      _erroRecompra = 'Erro ao buscar sugestões de recompra: $e';
      debugPrint(_erroRecompra);
    }

    try {
      _contatosParados = await _repository.buscarContatosParados(empresaId: _empresaId!);
      _erroContatosParados = null;
    } catch (e) {
      _erroContatosParados = 'Erro ao buscar contatos de campanha parados: $e';
      debugPrint(_erroContatosParados);
    }

    try {
      _conteudoPendente = await _repository.buscarConteudoPendente(empresaId: _empresaId!);
      _erroConteudoPendente = null;
    } catch (e) {
      _erroConteudoPendente = 'Erro ao buscar conteúdo social pendente: $e';
      debugPrint(_erroConteudoPendente);
    }

    _carregando = false;
    notifyListeners();
  }

  /// Marca o lembrete como enviado (evita repetir a mesma sugestão amanhã,
  /// respeitando o cooldown de `clientes_devido_recompra`) e recarrega.
  Future<void> marcarRecompraLembrada(String clienteId) async {
    await _repository.marcarLembreteRecompraEnviado(clienteId);
    await carregar();
  }
}
