import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Faixa horizontal (abas, categorias) que rola com a roda do mouse e mostra
/// a barrinha de rolagem — no PC não dá pra arrastar com o dedo, e sem isso
/// o que passava da largura ficava inalcançável (abas de Pedidos, categorias
/// do Vender numa janela de 1200 px).
class FaixaRolavel extends StatefulWidget {
  final Widget child;

  /// Espaço embaixo pra barrinha não cobrir o conteúdo.
  final double espacoBarra;

  const FaixaRolavel({super.key, required this.child, this.espacoBarra = 8});

  @override
  State<FaixaRolavel> createState() => _FaixaRolavelState();
}

class _FaixaRolavelState extends State<FaixaRolavel> {
  final _rolagem = ScrollController();

  @override
  void dispose() {
    _rolagem.dispose();
    super.dispose();
  }

  void _roda(PointerSignalEvent sinal) {
    if (sinal is! PointerScrollEvent || !_rolagem.hasClients) return;
    final pos = _rolagem.position;
    if (pos.maxScrollExtent <= 0) return;
    final delta = sinal.scrollDelta.dy != 0 ? sinal.scrollDelta.dy : sinal.scrollDelta.dx;
    // Resolver: só esta faixa rola (não a lista de trás junto).
    GestureBinding.instance.pointerSignalResolver.register(sinal, (_) {
      _rolagem.jumpTo((pos.pixels + delta).clamp(0, pos.maxScrollExtent).toDouble());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _roda,
      child: Scrollbar(
        controller: _rolagem,
        thumbVisibility: true,
        child: Padding(
          padding: EdgeInsets.only(bottom: widget.espacoBarra),
          child: SingleChildScrollView(
            controller: _rolagem,
            scrollDirection: Axis.horizontal,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
