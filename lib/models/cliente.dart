class Cliente {
  final String idCliente;
  late final String nome;
  late final String celular;
  late final String email;
  late final String endereco;
  late final String complemento;
  late final String cpf;
  final List<String> pet;
  late final String observacao;
  final double saldo;

  Cliente({
    required this.idCliente,
    required this.nome,
    required this.celular,
    required this.email,
    required this.endereco,
    required this.complemento,
    required this.cpf,
    required this.pet,
    required this.observacao,
    required this.saldo,
  });

  // Convertendo Cliente para Map (para salvar no banco de dados)
  Map<String, dynamic> toMap() {
    return {
      'id': idCliente,
      'nome': nome,
      'celular': celular,
      'email': email,
      'endereco': endereco,
      'complemento': complemento,
      'cpf': cpf,
      'pet': pet,
      'observaçao': observacao,
      'saldo': saldo, // Incluindo o saldo no Map
    };
  }

  // Convertendo Map para Cliente (para buscar do banco de dados)
  static Cliente fromMap(Map<String, dynamic> map) {
    return Cliente(
      idCliente: map['id'],
      nome: map['nome'],
      celular: map['celular'],
      email: map['email'],
      endereco: map['endereco'],
      complemento: map['complemento'],
      cpf: map['cpf'],
      pet: map['pet'],
      observacao: map['observacao'],
      saldo: map['saldo'] ?? 0.0, // Atribuindo 0.0 caso o saldo não esteja presente no Map
    );
  }
}
