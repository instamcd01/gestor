class Cliente {
  final String id;
  final String nome;
  final String celular;
  final String email;
  final String endereco;
  final String cpf;
  final String pet;
  final double saldo;

  Cliente({
    required this.id,
    required this.nome,
    required this.celular,
    required this.email,
    required this.endereco,
    required this.cpf,
    required this.pet,
    required this.saldo,
  });

  // Convertendo Cliente para Map (para salvar no banco de dados)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'celular': celular,
      'email': email,
      'endereco': endereco,
      'cpf': cpf,
      'pet': pet,
      'saldo': saldo, // Incluindo o saldo no Map
    };
  }

  // Convertendo Map para Cliente (para buscar do banco de dados)
  static Cliente fromMap(Map<String, dynamic> map) {
    return Cliente(
      id: map['id'],
      nome: map['nome'],
      celular: map['celular'],
      email: map['email'],
      endereco: map['endereco'],
      cpf: map['cpf'],
      pet: map['pet'],
      saldo: map['saldo'] ?? 0.0, // Atribuindo 0.0 caso o saldo não esteja presente no Map
    );
  }
}
