import 'package:flutter_test/flutter_test.dart';
import 'package:gestor/models/cliente.dart';
import 'package:gestor/models/venda.dart';

Venda _venda({String canal = 'loja', String? tipo, double taxa = 0, String entrega = ''}) => Venda(
      idVenda: '1',
      numeroSequencial: 1,
      cliente: Cliente(
        idCliente: 'c1',
        nome: 'Teste',
        celular: '21999990000',
        email: '',
        endereco: '',
        complemento: '',
        cpf: '',
        observacao: '',
        saldo: 0,
        pets: const [],
      ),
      dataVenda: DateTime.now(),
      subtotal: 100,
      desconto: 0,
      saldoUsado: 0,
      valorEntrega: taxa,
      entregaSelecionada: entrega,
      valorTotal: 100,
      valorPago: 100,
      troco: 0,
      metodoPagamento: 'Pix',
      totalItens: 1,
      itens: const [],
      custoTotal: 0,
      lucroTotal: 0,
      status: StatusPedido.pronto,
      canalVenda: canal,
      tipoEntregaMarketplace: tipo,
    );

void main() {
  test('iFood DELIVERY com taxa zero continua sendo entrega (pedido do Wesley, 14/11)', () {
    final v = _venda(canal: 'ifood', tipo: 'DELIVERY', taxa: 0);
    expect(v.temEntrega, isTrue);
    expect(v.retirada, isFalse);
    expect(v.proximoStatus, StatusPedido.saiuParaEntrega);
  });

  test('99Food DELIVERY com frete grátis é entrega', () {
    final v = _venda(canal: '99food', tipo: 'DELIVERY', taxa: 0);
    expect(v.temEntrega, isTrue);
    expect(v.proximoStatus, StatusPedido.saiuParaEntrega);
  });

  test('iFood TAKEOUT é retirada mesmo com taxa', () {
    final v = _venda(canal: 'ifood', tipo: 'TAKEOUT', taxa: 5);
    expect(v.temEntrega, isFalse);
    expect(v.retirada, isTrue);
    expect(v.proximoStatus, StatusPedido.entregue);
  });

  test('venda da loja segue a regra antiga', () {
    expect(_venda(entrega: 'Retirada na Loja').temEntrega, isFalse);
    expect(_venda(entrega: '0-2km').temEntrega, isTrue);
    expect(_venda(taxa: 8).temEntrega, isTrue);
  });
}
