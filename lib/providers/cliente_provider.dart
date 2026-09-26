import 'package:flutter/material.dart';
import '../config/supabase_config.dart';
import '../models/cliente.dart';
import '../repositories/cliente_repository.dart';
import '../utils/busca_utils.dart';

class ClientProvider with ChangeNotifier {
  final ClienteRepository _repository = ClienteRepository();

  List<Cliente> _clientes = [];
  String _termoPesquisa = '';
  Cliente? _clienteSelecionado;
  String? _empresaId;
  bool _carregando = false;
  String? _erro;

  /// Lista COMPLETA e sempre atual — é a que qualquer tela deve usar pra
  /// achar "a versão mais recente do cliente X". Antes esse getter devolvia
  /// uma cópia filtrada congelada (`pesquisarClientes('')` fazia
  /// `List.from(_clientes)`) que nunca recebia cliente novo/editado/
  /// promovido — a tela de venda achava o cliente antigo e parecia que a
  /// edição "não salvava" (achado real 26/09, bug recorrente).
  List<Cliente> get clientes => _clientes;

  /// Só pra exibição na tela de Clientes — calculado na hora a partir de
  /// `_clientes`, nunca guardado, então nunca fica desatualizado.
  List<Cliente> get clientesFiltrados {
    if (_termoPesquisa.isEmpty) return _clientes;
    return _clientes.where((cliente) {
      // Todos os campos buscáveis viram um único texto — assim uma busca com
      // várias palavras pode bater em campos diferentes (ex: "joao 999"
      // encontrando pelo nome + parte do celular), não só um campo por vez.
      final textoCompleto = [
        cliente.nome,
        cliente.celular,
        cliente.email,
        cliente.enderecoCompleto,
        cliente.complemento,
        cliente.cpf,
        cliente.especies.join(' '),
        cliente.observacao,
      ].join(' ');
      return contemTodasPalavras(textoCompleto, _termoPesquisa);
    }).toList();
  }
  Cliente? get clienteSelecionado => _clienteSelecionado;
  bool get carregando => _carregando;
  String? get erro => _erro;

  /// Chamado uma vez pelo AuthGate assim que sabemos a empresa do usuário
  /// logado — necessário pra criar novos clientes (empresa_id é obrigatório).
  void definirEmpresa(String empresaId) {
    _empresaId = empresaId;
  }

  Future<Cliente> addCliente(Cliente cliente) async {
    if (_empresaId == null) {
      throw StateError('Nenhuma empresa definida no ClientProvider ainda.');
    }
    try {
      final novoCliente = await _repository.criar(cliente, empresaId: _empresaId!);
      _clientes.add(novoCliente);
      notifyListeners();
      return novoCliente;
    } catch (e) {
      debugPrint('Erro ao adicionar cliente: $e');
      rethrow;
    }
  }

  Future<void> carregarClientes() async {
    _carregando = true;
    _erro = null;
    notifyListeners();

    try {
      _clientes = await _repository.listar();
    } catch (e) {
      _erro = 'Erro ao carregar clientes: $e';
      debugPrint(_erro);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  /// Mantido pelo nome antigo por compatibilidade com telas existentes.
  Future<void> carregarClientesDoFirestore() async {
    await carregarClientes();
  }

  Future<void> atualizarCliente(Cliente clienteAtualizado) async {
    if (clienteAtualizado.idCliente == null) {
      debugPrint('Erro: cliente sem id para atualização.');
      return;
    }
    try {
      await _repository.atualizar(clienteAtualizado);
      // Relê do banco em vez de confiar no objeto montado pela tela — ele
      // não carrega campos que a tela não edita (authUserId, pessoaId,
      // telefoneKyte, totais) e a cópia local ficava diferente do banco.
      final salvo = await _repository.buscarPorId(clienteAtualizado.idCliente!) ?? clienteAtualizado;
      substituirLocal(salvo);
    } catch (e) {
      debugPrint('Erro ao atualizar cliente: $e');
      rethrow;
    }
  }

  Future<void> removerClienteDoFirestore(Cliente cliente) async {
    if (cliente.idCliente == null) return;
    try {
      await _repository.excluir(cliente.idCliente!);
      _clientes.removeWhere((c) => c.idCliente == cliente.idCliente);
      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao remover cliente: $e');
      rethrow;
    }
  }

  Cliente? buscarClientePorNome(String nome) {
    try {
      return _clientes.firstWhere(
        (cliente) => cliente.nome.toLowerCase() == nome.toLowerCase(),
      );
    } catch (e) {
      return null;
    }
  }

  void pesquisarClientes(String texto) {
    _termoPesquisa = texto;
    notifyListeners();
  }

  /// Desfaz o vínculo de login do cliente — ver `ClienteRepository.
  /// redefinirAcesso` pra por que isso é necessário depois de trocar o
  /// telefone de um cliente que já tinha logado antes. Recarrega a lista
  /// inteira (em vez de só patchar localmente, como `atualizarSaldoLocal`
  /// faz) porque `authUserId` não está no `copyWith` — não vale a pena
  /// adicionar só pra essa ação rara.
  Future<void> redefinirAcesso(String clienteId, {String? novoTelefone}) async {
    await _repository.redefinirAcesso(clienteId, novoTelefone: novoTelefone);
    await carregarClientes();
    final index = _clientes.indexWhere((c) => c.idCliente == clienteId);
    if (index != -1) {
      _clienteSelecionado = _clientes[index];
    }
    notifyListeners();
  }

  /// Coloca/atualiza um cliente já salvo na lista em memória (sem ida ao
  /// servidor) — usado depois de editar/promover, pra lista nunca ficar
  /// atrás do banco.
  void substituirLocal(Cliente cliente) {
    final index = _clientes.indexWhere((c) => c.idCliente == cliente.idCliente);
    // Mesmo critério de `ClienteRepository.listar()`: histórico Kyte não
    // promovido não entra na lista normal.
    if (cliente.canalOrigem == 'kyte_historico') {
      if (index != -1) _clientes.removeAt(index);
    } else if (index != -1) {
      _clientes[index] = cliente;
    } else {
      _clientes.add(cliente);
    }
    if (_clienteSelecionado?.idCliente == cliente.idCliente) {
      _clienteSelecionado = cliente;
    }
    notifyListeners();
  }

  void setClienteSelecionado(Cliente cliente) {
    _clienteSelecionado = cliente;
    notifyListeners();
  }

  /// Atualiza só a cópia em memória do saldo — usado depois de uma
  /// movimentação feita via SaldoRepository, que já escreveu no banco
  /// (evita reenviar o cliente inteiro de novo pro servidor).
  void atualizarSaldoLocal(String clienteId, double novoSaldo) {
    final index = _clientes.indexWhere((c) => c.idCliente == clienteId);
    if (index != -1) {
      _clientes[index] = _clientes[index].copyWith(saldo: novoSaldo);
      notifyListeners();
    }
  }
}

const canalKyteHistorico = 'kyte_historico';

/// Canais de origem do cliente (WhatsApp, Instagram, iFood, etc.), agora
/// vindos do Supabase (tabela `canais_origem`, editável por empresa).
Future<List<String>> carregarCanaisOrigem() async {
  try {
    final data = await supabase.from('canais_origem').select('nome').order('nome', ascending: true);
    final canais = (data as List)
        .map((row) => row['nome'] as String)
        // Marcador interno de cadastro consultivo, não um canal de verdade —
        // escolher isso no formulário devolvia um cliente já promovido pro
        // Histórico Kyte (entrou na tabela por engano em 11/09, via "Outro
        // canal"). Só a RPC promover_cliente_kyte_historico mexe nisso.
        .where((c) => c != canalKyteHistorico)
        .toList();
    return canais.isNotEmpty ? canais : ['WhatsApp', 'Instagram', 'Ifood', 'Outro canal'];
  } catch (e) {
    debugPrint('Erro ao carregar canais: $e');
    return ['WhatsApp', 'Instagram', 'Ifood', 'Outro canal'];
  }
}

Future<void> adicionarCanalOrigem(String canal, String empresaId) async {
  if (canal == canalKyteHistorico) return;
  try {
    await supabase.from('canais_origem').upsert(
      {'nome': canal, 'empresa_id': empresaId},
      onConflict: 'empresa_id,nome',
    );
  } catch (e) {
    debugPrint('Erro ao salvar canal: $e');
  }
}
