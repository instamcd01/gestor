class DeliveryInfo {
  final String endereco;
  final String distancia;
  final String tempo;
  final double valorEntrega;
  final bool freteGratis;

  DeliveryInfo({
    required this.endereco,
    required this.distancia,
    required this.tempo,
    required this.valorEntrega,
    required this.freteGratis,
  });
}

//
// class DeliveryInfo {
//   final String enderecoEntrega;
//   final double distanciaKm;
//   final int tempoEstimadoMin;
//   final double valorEntrega;
//
//   // Estratégicos
//   final String tipoEntrega; // Ex: "Loja", "Delivery Pet", "Motoboy"
//   final String statusEntrega; // Ex: "Pendente", "Saiu para entrega", "Entregue"
//   final DateTime? dataPrevisaoEntrega;
//   final String observacoes;
//
//   DeliveryInfo({
//     required this.enderecoEntrega,
//     required this.distanciaKm,
//     required this.tempoEstimadoMin,
//     required this.valorEntrega,
//     this.tipoEntrega = 'Loja',
//     this.statusEntrega = 'Pendente',
//     this.dataPrevisaoEntrega,
//     this.observacoes = '',
//   });
//
//   Map<String, dynamic> toMap() {
//     return {
//       'enderecoEntrega': enderecoEntrega,
//       'distanciaKm': distanciaKm,
//       'tempoEstimadoMin': tempoEstimadoMin,
//       'valorEntrega': valorEntrega,
//       'tipoEntrega': tipoEntrega,
//       'statusEntrega': statusEntrega,
//       'dataPrevisaoEntrega': dataPrevisaoEntrega?.toIso8601String(),
//       'observacoes': observacoes,
//     };
//   }
//
//   factory DeliveryInfo.fromMap(Map<String, dynamic> map) {
//     return DeliveryInfo(
//       enderecoEntrega: map['enderecoEntrega'] ?? '',
//       distanciaKm: (map['distanciaKm'] ?? 0).toDouble(),
//       tempoEstimadoMin: map['tempoEstimadoMin'] ?? 0,
//       valorEntrega: (map['valorEntrega'] ?? 0).toDouble(),
//       tipoEntrega: map['tipoEntrega'] ?? 'Loja',
//       statusEntrega: map['statusEntrega'] ?? 'Pendente',
//       dataPrevisaoEntrega: map['dataPrevisaoEntrega'] != null
//           ? DateTime.tryParse(map['dataPrevisaoEntrega'])
//           : null,
//       observacoes: map['observacoes'] ?? '',
//     );
//   }
// }
