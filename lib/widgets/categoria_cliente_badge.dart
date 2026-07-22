import 'package:flutter/material.dart';

/// Selo colorido com a categoria do cliente (`segmento`), calculada
/// automaticamente no banco a partir do histórico de compras — novo,
/// regular, vip ou inativo. Não é editável pelo usuário.
class CategoriaClienteBadge extends StatelessWidget {
  final String? categoria;

  const CategoriaClienteBadge({super.key, required this.categoria});

  static const _config = {
    'novo': (label: 'Novo', cor: Colors.blueGrey),
    'regular': (label: 'Regular', cor: Colors.blue),
    'vip': (label: 'VIP', cor: Colors.amber),
    'inativo': (label: 'Inativo', cor: Colors.redAccent),
  };

  @override
  Widget build(BuildContext context) {
    final chave = (categoria ?? '').toLowerCase();
    final info = _config[chave];
    if (info == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: info.cor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: info.cor.withValues(alpha: 0.5)),
      ),
      child: Text(
        info.label,
        style: TextStyle(
          color: info.cor.computeLuminance() > 0.6 ? Colors.black87 : info.cor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
