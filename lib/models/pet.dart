// models/pet.dart
class Pet {
  final String id;
  final String nome;
  final String especie;
  final String raca;
  final DateTime nascimento;
  final double peso;
  final bool vacinado;
  final bool castrado;
  final String observacoes;
  final String imagemUrl;

  Pet({
    required this.id,
    required this.nome,
    required this.especie,
    required this.raca,
    required this.nascimento,
    required this.peso,
    required this.vacinado,
    required this.castrado,
    required this.observacoes,
    required this.imagemUrl,
  });

  factory Pet.fromMap(Map<String, dynamic> map) {
    return Pet(
      id: map['id'],
      nome: map['nome'],
      especie: map['especie'],
      raca: map['raca'],
      nascimento: DateTime.parse(map['nascimento']),
      peso: map['peso'].toDouble(),
      vacinado: map['vacinado'],
      castrado: map['castrado'],
      observacoes: map['observacoes'],
      imagemUrl: map['imagemUrl'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'especie': especie,
      'raca': raca,
      'nascimento': nascimento.toIso8601String(),
      'peso': peso,
      'vacinado': vacinado,
      'castrado': castrado,
      'observacoes': observacoes,
      'imagemUrl': imagemUrl,
    };
  }
}

// class Pet {
//   final String nome;
//   final String especie;
//   final String raca;
//   final String idade;
//   final String cor;
//   final String porte;
//   final String vacinas;
//
//   // Estratégico
//   final DateTime? dataNascimento;
//   final bool castrado;
//   final String observacoes;
//
//   Pet({
//     required this.nome,
//     required this.especie,
//     required this.raca,
//     required this.idade,
//     required this.cor,
//     required this.porte,
//     required this.vacinas,
//     this.dataNascimento,
//     this.castrado = false,
//     this.observacoes = '',
//   });
//
//   Map<String, dynamic> toMap() {
//     return {
//       'nome': nome,
//       'especie': especie,
//       'raca': raca,
//       'idade': idade,
//       'cor': cor,
//       'porte': porte,
//       'vacinas': vacinas,
//       'dataNascimento': dataNascimento?.toIso8601String(),
//       'castrado': castrado,
//       'observacoes': observacoes,
//     };
//   }
//
//   factory Pet.fromMap(Map<String, dynamic> map) {
//     return Pet(
//       nome: map['nome'] ?? '',
//       especie: map['especie'] ?? '',
//       raca: map['raca'] ?? '',
//       idade: map['idade'] ?? '',
//       cor: map['cor'] ?? '',
//       porte: map['porte'] ?? '',
//       vacinas: map['vacinas'] ?? '',
//       dataNascimento: map['dataNascimento'] != null
//           ? DateTime.tryParse(map['dataNascimento'])
//           : null,
//       castrado: map['castrado'] ?? false,
//       observacoes: map['observacoes'] ?? '',
//     );
//   }
// }
