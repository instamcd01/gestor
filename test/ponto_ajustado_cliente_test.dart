import 'package:flutter_test/flutter_test.dart';
import 'package:gestor/models/cliente.dart';
import 'package:gestor/models/venda.dart';
import 'package:gestor/utils/mensagem_entregador.dart';

Cliente _cliente({bool ajustado = false, double? lat = -22.86, double? lng = -43.54}) => Cliente(
      idCliente: 'c1',
      nome: 'Fulana',
      celular: '5521999999999',
      email: '',
      endereco: 'Estrada do Mendanha',
      numero: '2',
      bairro: 'Campo Grande',
      complemento: '',
      cpf: '',
      observacao: '',
      saldo: 0,
      pets: const [],
      latitude: lat,
      longitude: lng,
      pontoAjustadoCliente: ajustado,
    );

Venda _venda(Cliente cliente) => Venda(
      cliente: cliente,
      dataVenda: DateTime(2026, 9, 26, 15),
      subtotal: 50,
      desconto: 0,
      saldoUsado: 0,
      valorEntrega: 4.9,
      entregaSelecionada: 'Entrega',
      valorTotal: 54.9,
      valorPago: 54.9,
      troco: 0,
      metodoPagamento: 'Pix',
      totalItens: 1,
      itens: const [],
      custoTotal: 30,
      lucroTotal: 20,
    );

void main() {
  test('ponto_ajustado_cliente vai e volta do banco', () {
    final mapa = _cliente(ajustado: true).toSupabaseMap();
    expect(mapa['ponto_ajustado_cliente'], isTrue);
    final lido = Cliente.fromSupabase({...mapa, 'id': 'c1', 'pets': []});
    expect(lido.pontoAjustadoCliente, isTrue);
    expect(Cliente.fromSupabase({...mapa, 'id': 'c1', 'pets': [], 'ponto_ajustado_cliente': null}).pontoAjustadoCliente,
        isFalse);
    expect(lido.copyWith(saldo: 10).pontoAjustadoCliente, isTrue, reason: 'copyWith não pode perder o selo');
  });

  test('mensagem do entregador avisa quando o cliente marcou o ponto no mapa', () {
    final msg = mensagemEntregador(_venda(_cliente(ajustado: true)));
    expect(msg, contains('Ponto marcado pelo cliente no mapa'));
    expect(msg, contains('query=-22.86,-43.54'));
  });

  test('sem ajuste do cliente (ou sem coordenada) não mostra o aviso', () {
    expect(mensagemEntregador(_venda(_cliente())), isNot(contains('Ponto marcado pelo cliente')));
    expect(mensagemEntregador(_venda(_cliente(ajustado: true, lat: null, lng: null))),
        isNot(contains('Ponto marcado pelo cliente')));
  });
}
