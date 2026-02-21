import 'package:gestor/models/pet.dart';

class Cliente {
  final String idCliente;
  final String nome;
  final String celular;
  final String email;
  final String endereco;
  final String complemento;
  final String cpf;
  final String observacao;
  final double saldo;
  final List<Pet> pets;

  // Estratégico
  final DateTime? dataCadastro;
  final DateTime? aniversario;
  final String? canalOrigem;

  // Vendas e comportamento
  final int? quantidadeCompras;
  final double? totalGasto;
  final int? numeroCompras;
  final DateTime? ultimaCompra;
  final double? ticketMedio;

  // Relacionamento
  final DateTime? proximaVisita;
  final String? motivoUltimaVisita;

  // Marketing
  final bool? aceitaMarketing;
  final DateTime? ultimoContato;
  final String? canalPreferido;

  // Análise
  final String? categoriaCliente;
  final double? fidelidadeScore;
  final List<String>? interesses;

  // Documentação
  final List<String>? documentos;
  final Map<String, dynamic>? observacoesExtras;

  // Distância e entrega
  final double? rangeDistancia; // km
  final int? estimativaEntrega; // minutos

  Cliente({
    required this.idCliente,
    required this.nome,
    required this.celular,
    required this.email,
    required this.endereco,
    required this.complemento,
    required this.cpf,
    required this.observacao,
    required this.saldo,
    required this.pets,
    this.dataCadastro,
    this.aniversario,
    this.canalOrigem,
    this.quantidadeCompras,
    this.totalGasto,
    this.numeroCompras,
    this.ultimaCompra,
    this.ticketMedio,
    this.proximaVisita,
    this.motivoUltimaVisita,
    this.aceitaMarketing,
    this.ultimoContato,
    this.canalPreferido,
    this.categoriaCliente,
    this.fidelidadeScore,
    this.interesses,
    this.documentos,
    this.observacoesExtras,
    this.rangeDistancia,
    this.estimativaEntrega,
  });

  List<String> get especies => pets.map((p) => p.especie).toSet().toList();

  Map<String, dynamic> toMap() {
    return {
      'idCliente': idCliente,
      'nome': nome,
      'celular': celular,
      'email': email,
      'endereco': endereco,
      'complemento': complemento,
      'cpf': cpf,
      'observacao': observacao,
      'saldo': saldo,
      'pets': pets.map((p) => p.toMap()).toList(),
      'dataCadastro': dataCadastro?.toIso8601String(),
      'aniversario': aniversario?.toIso8601String(),
      'canalOrigem': canalOrigem,
      'quantidadeCompras': quantidadeCompras,
      'totalGasto': totalGasto,
      'numeroCompras': numeroCompras,
      'ultimaCompra': ultimaCompra?.toIso8601String(),
      'ticketMedio': ticketMedio,
      'proximaVisita': proximaVisita?.toIso8601String(),
      'motivoUltimaVisita': motivoUltimaVisita,
      'aceitaMarketing': aceitaMarketing,
      'ultimoContato': ultimoContato?.toIso8601String(),
      'canalPreferido': canalPreferido,
      'categoriaCliente': categoriaCliente,
      'fidelidadeScore': fidelidadeScore,
      'interesses': interesses,
      'documentos': documentos,
      'observacoesExtras': observacoesExtras,
      'rangeDistancia': rangeDistancia,
      'estimativaEntrega': estimativaEntrega,
    };
  }

  factory Cliente.fromMap(Map<String, dynamic> map) {
    return Cliente(
      idCliente: map['idCliente'] ?? '',
      nome: map['nome'] ?? '',
      celular: map['celular'] ?? '',
      email: map['email'] ?? '',
      endereco: map['endereco'] ?? '',
      complemento: map['complemento'] ?? '',
      cpf: map['cpf'] ?? '',
      observacao: map['observacao'] ?? '',
      saldo: (map['saldo'] ?? 0.0).toDouble(),
      pets: (map['pets'] as List?)?.map((p) => Pet.fromMap(p)).toList() ?? [],
      dataCadastro: map['dataCadastro'] != null ? DateTime.tryParse(map['dataCadastro']) : null,
      aniversario: map['aniversario'] != null ? DateTime.tryParse(map['aniversario']) : null,
      canalOrigem: map['canalOrigem'],
      quantidadeCompras: map['quantidadeCompras'],
      totalGasto: (map['totalGasto'] ?? 0).toDouble(),
      numeroCompras: map['numeroCompras'],
      ultimaCompra: map['ultimaCompra'] != null ? DateTime.tryParse(map['ultimaCompra']) : null,
      ticketMedio: (map['ticketMedio'] ?? 0).toDouble(),
      proximaVisita: map['proximaVisita'] != null ? DateTime.tryParse(map['proximaVisita']) : null,
      motivoUltimaVisita: map['motivoUltimaVisita'],
      aceitaMarketing: map['aceitaMarketing'],
      ultimoContato: map['ultimoContato'] != null ? DateTime.tryParse(map['ultimoContato']) : null,
      canalPreferido: map['canalPreferido'],
      categoriaCliente: map['categoriaCliente'],
      fidelidadeScore: (map['fidelidadeScore'] ?? 0).toDouble(),
      interesses: map['interesses'] != null ? List<String>.from(map['interesses']) : [],
      documentos: map['documentos'] != null ? List<String>.from(map['documentos']) : [],
      observacoesExtras: map['observacoesExtras'] != null ? Map<String, dynamic>.from(map['observacoesExtras']) : {},
      rangeDistancia: map['rangeDistancia'] != null ? (map['rangeDistancia'] as num).toDouble() : null,
      estimativaEntrega: map['estimativaEntrega'] != null ? (map['estimativaEntrega'] as num).toInt() : null,
    );
  }
}


