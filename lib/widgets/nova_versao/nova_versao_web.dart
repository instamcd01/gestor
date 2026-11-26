import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

const _versao = String.fromEnvironment('APP_VERSAO');

class AvisoNovaVersao extends StatefulWidget {
  const AvisoNovaVersao({super.key, required this.child});
  final Widget child;

  @override
  State<AvisoNovaVersao> createState() => _AvisoNovaVersaoState();
}

class _AvisoNovaVersaoState extends State<AvisoNovaVersao> {
  Timer? _timer;
  bool _nova = false;

  @override
  void initState() {
    super.initState();
    if (_versao.isEmpty) return; // build local, sem versão
    _timer = Timer.periodic(const Duration(minutes: 3), (_) => _conferir());
    Future.delayed(const Duration(seconds: 20), _conferir);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _conferir() async {
    if (_nova) return;
    try {
      final r = await web.window.fetch('versao.txt?t=${DateTime.now().millisecondsSinceEpoch}'.toJS).toDart;
      if (!r.ok) return;
      final publicada = (await r.text().toDart).toDart.trim();
      if (publicada.isNotEmpty && publicada != _versao && mounted) setState(() => _nova = true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        widget.child,
        if (_nova)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(14),
                color: const Color(0xFF1E1E24),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(children: [
                    const Expanded(
                      child: Text('Tem uma versão nova do app.',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                    FilledButton(onPressed: () => web.window.location.reload(), child: const Text('Atualizar')),
                  ]),
                ),
              ),
            ),
          ),
      ]);
}
