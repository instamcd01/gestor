// Bancada da tela Trajeto da rota com os dados reais da entrega de 26/11 (#7457 do iFood), sem login.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:gestor/screens/trajeto_rota_screen.dart';
import 'package:gestor/theme/app_theme.dart';

const _dados = r'''
{"rota":{"aceita_em":"2026-11-26T17:08:55+00:00","chegou_loja_em":"2026-11-26T17:29:13+00:00","saiu_em":"2026-11-26T17:34:21+00:00","finalizada_em":"2026-11-26T17:50:37+00:00","entregador":{"nome":"LUCAS"},
"rota_pedidos":[{"ordem":1,"chegou_cliente_em":"2026-11-26T17:48:45+00:00","pedido":{"numero_sequencial":7457,"status":"entregue","cliente":{"nome":"Cliente","latitude":-22.923801,"longitude":-43.564097}}}]},
"posicoes":[{"lat":-22.87567,"lon":-43.57131,"em":"2026-11-26T17:09:28+00:00"},{"lat":-22.87567,"lon":-43.57131,"em":"2026-11-26T17:10:19+00:00"},{"lat":-22.87563,"lon":-43.57126,"em":"2026-11-26T17:11:48+00:00"},{"lat":-22.87562,"lon":-43.57125,"em":"2026-11-26T17:14:19+00:00"},{"lat":-22.87564,"lon":-43.57128,"em":"2026-11-26T17:29:15+00:00"},{"lat":-22.87564,"lon":-43.57128,"em":"2026-11-26T17:34:42+00:00"},{"lat":-22.87565,"lon":-43.57128,"em":"2026-11-26T17:35:43+00:00"},{"lat":-22.92389,"lon":-43.56405,"em":"2026-11-26T17:49:12+00:00"},{"lat":-22.92392,"lon":-43.56409,"em":"2026-11-26T17:50:12+00:00"}],
"loja":{"latitude":-22.8757171,"longitude":-43.5714203}}
''';

void main() => runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(
          corPrimaria: const Color(0xFFE84C1C), corSecundaria: const Color(0xFFE84C1C), brightness: Brightness.light, corTopo: const Color(0xFF1E1E24)),
      home: TrajetoRotaScreen(rotaId: 'x', titulo: 'Rota · #7457', demo: jsonDecode(_dados) as Map<String, dynamic>),
    ));
