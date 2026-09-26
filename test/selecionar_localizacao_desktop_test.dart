import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor/screens/selecionar_localizacao_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as g;

void main() {
  testWidgets('desktop: abre mapa OSM, clique marca o ponto e Confirmar devolve a posição', (tester) async {
    g.LatLng? resultado;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              resultado = await Navigator.push<g.LatLng>(
                context,
                MaterialPageRoute(
                  builder: (_) => const SelecionarLocalizacaoScreen(posicaoInicial: g.LatLng(-22.9, -43.55)),
                ),
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.byType(FlutterMap), findsOneWidget, reason: 'no desktop tem que usar flutter_map');
    expect(find.byType(g.GoogleMap), findsNothing);

    // Clica fora do centro do mapa → o ponto muda.
    final centro = tester.getCenter(find.byType(FlutterMap));
    await tester.tapAt(centro + const Offset(60, 40));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('Confirmar localização'));
    await tester.pumpAndSettle();

    expect(resultado, isNotNull);
    expect(resultado!.latitude, isNot(-22.9));
    expect(resultado!.latitude, closeTo(-22.9, 0.01));
    expect(resultado!.longitude, closeTo(-43.55, 0.01));
  }, skip: !Platform.isWindows);

  testWidgets('desktop: voltar depois de marcar pergunta antes de descartar', (tester) async {
    g.LatLng? resultado = const g.LatLng(0, 0);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            resultado = await Navigator.push<g.LatLng>(
              context,
              MaterialPageRoute(
                builder: (_) => const SelecionarLocalizacaoScreen(posicaoInicial: g.LatLng(-22.9, -43.55)),
              ),
            );
          },
          child: const Text('abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(FlutterMap)) + const Offset(50, 0));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Usar essa localização?'), findsOneWidget);
    await tester.tap(find.text('Usar localização'));
    await tester.pumpAndSettle();
    expect(resultado, isNotNull);
    expect(resultado!.longitude, isNot(-43.55));
  }, skip: !Platform.isWindows);
}
