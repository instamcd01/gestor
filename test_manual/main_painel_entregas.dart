// Bancada do Painel de Entregas (não vai pro app publicado): a tela real com dados de exemplo,
// sem login e sem rede (o mapa usa os azulejos do OpenStreetMap).
// flutter build web -t test_manual/main_painel_entregas.dart -o <pasta>
import 'package:flutter/material.dart';
import 'package:gestor/screens/painel_entregas_screen.dart';
import 'package:gestor/theme/app_theme.dart';

String _t(Duration d) => DateTime.now().toUtc().add(d).toIso8601String();

Map<String, dynamic> _ped(String id, int n, String nome, String bairro, String status, double lat, double lon, {Duration? prometido}) => {
      'id': id,
      'numero_sequencial': n,
      'status': status,
      'previsao_entrega_fim': prometido == null ? null : _t(prometido),
      'cliente': {'nome': nome, 'bairro': bairro, 'latitude': lat, 'longitude': lon},
    };

Map<String, dynamic> _rp(int ordem, Map<String, dynamic> p, {String? foto}) => {'ordem': ordem, 'foto_path': foto, 'pedido': p};

Map<String, dynamic> demo() => {
      'cfg': {'ativo': true, 'pausado_ate': null, 'chuva_valor': 3, 'chuva_ate': _t(const Duration(hours: 2))},
      'loja': {'latitude': -22.8757171, 'longitude': -43.5714203},
      'resumo': {'entregas': 11, 'aceitas': 5, 'ofertadas': 6, 'min_ate_aceite': 2, 'pago_motoboys': 84.3, 'frete_cobrado': 101.9},
      'rotas': [
        {
          'id': 'r1', 'status': 'em_andamento', 'valor_entregador': 15.8, 'bonus': 0, 'km_ida': 7.8, 'google_ok': true,
          'ofertada_em': _t(const Duration(minutes: -40)), 'saiu_em': _t(const Duration(minutes: -22)),
          'prazo_saida': _t(const Duration(minutes: -20)), 'chegou_loja_em': _t(const Duration(minutes: -25)),
          'pos_lat': -22.8930, 'pos_lon': -43.5880, 'pos_em': _t(const Duration(seconds: -40)),
          'entregador': {'nome': 'Carlos Souza', 'telefone': '21999990001'},
          'rota_pedidos': [
            _rp(1, _ped('p1', 11421, 'Ana', 'Inhoaíba', 'entregue', -22.8995, -43.5960), foto: 'x.jpg'),
            _rp(2, _ped('p2', 11425, 'Bruno', 'Cosmos', 'pronto', -22.9165, -43.6136, prometido: const Duration(minutes: -6))),
            _rp(3, _ped('p3', 11430, 'Márcia', 'Cosmos', 'pronto', -22.9230, -43.6180)),
          ],
        },
        {
          'id': 'r2', 'status': 'aceita', 'valor_entregador': 11.5, 'bonus': 0, 'km_ida': 5.1, 'google_ok': true,
          'ofertada_em': _t(const Duration(minutes: -12)), 'prazo_saida': _t(const Duration(minutes: 9)),
          'chegou_loja_em': _t(const Duration(minutes: -2)), 'gps_falha': 'bloqueado',
          'entregador': {'nome': 'Renan Lima'},
          'rota_pedidos': [
            _rp(1, _ped('p4', 11431, 'Paula', 'Rio da Prata', 'pronto', -22.8880, -43.5440)),
            _rp(2, _ped('p5', 11432, 'Jorge', 'Rio da Prata', 'pronto', -22.8925, -43.5390)),
          ],
        },
        {
          'id': 'r3', 'status': 'ofertada', 'valor_entregador': 13.5, 'bonus': 0, 'km_ida': 6.2, 'google_ok': true,
          'ofertada_em': _t(const Duration(minutes: -3)), 'prazo_saida': _t(const Duration(minutes: 26)),
          'rota_pedidos': [_rp(1, _ped('p6', 11434, 'Rita', 'Santíssimo', 'preparando', -22.8780, -43.5150))],
        },
        {
          'id': 'r4', 'status': 'ofertada', 'valor_entregador': 11.5, 'bonus': 0, 'km_ida': 4.3, 'google_ok': true,
          'ofertada_em': null, 'prazo_saida': _t(const Duration(minutes: 47)),
          'rota_pedidos': [_rp(1, _ped('p7', 11436, 'Juliana', 'Mendanha', 'pendente', -22.8580, -43.5500))],
        },
        {
          'id': 'r5', 'status': 'sem_entregador', 'valor_entregador': 12.0, 'bonus': 0, 'km_ida': 6.9, 'google_ok': true,
          'ofertada_em': _t(const Duration(minutes: -28)), 'prazo_saida': _t(const Duration(minutes: -5)),
          'rota_pedidos': [_rp(1, _ped('p8', 11427, 'Sérgio', 'Senador Vasconcelos', 'pronto', -22.8920, -43.5130))],
        },
      ],
      'concluidas': [
        {
          'id': 'c1', 'status': 'concluida', 'valor_entregador': 21.0, 'bonus': 0, 'km_ida': 16.7, 'saiu_em': _t(const Duration(hours: -3)),
          'finalizada_em': _t(const Duration(hours: -2)), 'entregador': {'nome': 'Carlos Souza'},
          'rota_pedidos': [_rp(1, _ped('c1p', 11402, 'Lia', 'Bangu', 'entregue', -22.8746, -43.4652), foto: 'y.jpg')],
        },
      ],
      'fora': [
        {'motivo': 'nao_paga_entrega', 'pedido': _ped('p9', 11433, 'Caio', 'Campo Grande', 'preparando', -22.90, -43.56)},
      ],
      'voltou': [
        {'foto_path': 'z.jpg', 'devolucao_confirmada_em': null, 'pedido': _ped('p10', 11418, 'Diego', 'Cosmos', 'nao_entregue', -22.91, -43.60)},
      ],
      'reclamou': [],
      'rotas_loja': [
        {
          'id': 'm1', 'status': 'em_andamento', 'entregador': {'nome': 'Lucas'},
          'rota_pedidos': [
            {'pedido': {'status': 'entregue', 'cliente': {'latitude': -22.8650, 'longitude': -43.5850}}},
            {'pedido': {'status': 'pronto', 'cliente': {'latitude': -22.8600, 'longitude': -43.5950}}},
          ],
        },
      ],
      'motoboys': [
        {'id': 'e1', 'nome': 'Carlos Souza', 'disponivel': true},
        {'id': 'e2', 'nome': 'Renan Lima', 'disponivel': true},
        {'id': 'e3', 'nome': 'Diego Alves', 'disponivel': false},
        {'id': 'e4', 'nome': 'Marcos Silva', 'disponivel': true, 'pos_lat': -22.8690, 'pos_lon': -43.5620, 'pos_em': _t(const Duration(minutes: -1))},
      ],
      'acerto': [
        {'n_pedidos': 4, 'valor_entregador': 27.3, 'dinheiro_recebido': 0, 'entregador': {'nome': 'Carlos Souza'}},
        {'n_pedidos': 3, 'valor_entregador': 21.0, 'dinheiro_recebido': 0, 'entregador': {'nome': 'Carlos Souza'}},
        {'n_pedidos': 3, 'valor_entregador': 25.0, 'dinheiro_recebido': 60, 'entregador': {'nome': 'Renan Lima'}},
      ],
    };

void main() {
  final cor = Uri.base.queryParameters['cor'];
  final primaria = cor == null ? const Color(0xFFE84C1C) : Color(int.parse('FF$cor', radix: 16));
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.build(
        corPrimaria: primaria, corSecundaria: primaria, brightness: Brightness.light, corTopo: const Color(0xFF1E1E24)),
    home: PainelEntregasScreen(demo: demo()),
  ));
}
