class Venda {
  final String id;
  final String clienteId;
  final List<Map<String, dynamic>> produtos;
  final DateTime data;
  final double total;

  Venda({
    required this.id,
    required this.clienteId,
    required this.produtos,
    required this.data,
    required this.total,
  });
}
