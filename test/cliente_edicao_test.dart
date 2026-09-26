import 'package:flutter_test/flutter_test.dart';
import 'package:gestor/models/cliente.dart';
import 'package:gestor/providers/cliente_provider.dart';
import 'package:gestor/repositories/cliente_repository.dart';
import 'package:gestor/utils/cliente_validators.dart';

Cliente _cliente({
  String id = 'c1',
  String nome = 'Fulana',
  String celular = '(21) 97446-4293',
  String? canal,
  String? telefoneKyte,
}) =>
    Cliente(
      idCliente: id,
      nome: nome,
      celular: celular,
      email: '',
      endereco: 'Rua A',
      complemento: '',
      cpf: '',
      observacao: '',
      saldo: 10,
      pets: const [],
      canalOrigem: canal,
      telefoneKyte: telefoneKyte,
    );

void main() {
  group('celularParaEdicao', () {
    test('formato 55 aparece mascarado (não é cortado pela máscara)', () {
      expect(ClienteValidators.celularParaEdicao('5521974464293'), '(21) 97446-4293');
      expect(ClienteValidators.celularParaEdicao('21974464293'), '(21) 97446-4293');
      expect(ClienteValidators.celularParaEdicao('(21) 97446-4293'), '(21) 97446-4293');
      expect(ClienteValidators.celularParaEdicao('2134567890'), '(21) 3456-7890');
    });
    test('placeholder Kyte não é tocado', () {
      expect(ClienteValidators.celularParaEdicao('kyte-sem-numero-7'), 'kyte-sem-numero-7');
    });
  });

  group('celularParaSalvar', () {
    test('número igual mantém o valor gravado EXATO (formato 55 do WhatsApp)', () {
      expect(
        ClienteValidators.celularParaSalvar(original: '5521974464293', digitado: '(21) 97446-4293'),
        '5521974464293',
      );
    });
    test('número igual mantém máscara quando o original era mascarado', () {
      expect(
        ClienteValidators.celularParaSalvar(original: '(21) 97446-4293', digitado: '(21) 97446-4293'),
        '(21) 97446-4293',
      );
    });
    test('número trocado num cadastro formato 55 continua no formato 55', () {
      expect(
        ClienteValidators.celularParaSalvar(original: '5521974464293', digitado: '(21) 98888-7777'),
        '5521988887777',
      );
    });
    test('número trocado num cadastro manual mantém o digitado', () {
      expect(
        ClienteValidators.celularParaSalvar(original: '(21) 97446-4293', digitado: '(21) 98888-7777'),
        '(21) 98888-7777',
      );
    });
  });

  group('ClienteRepository.payloadAtualizacao', () {
    test('cliente normal: manda telefone e canal, nunca saldo', () {
      final p = ClienteRepository.payloadAtualizacao(_cliente(celular: '5521974464293', canal: 'site_proprio'));
      expect(p['telefone'], '5521974464293');
      expect(p['canal_origem'], 'site_proprio');
      expect(p.containsKey('saldo'), isFalse);
      expect(p.containsKey('telefone_kyte'), isFalse);
    });
    test('Kyte não promovido: não mexe em telefone (placeholder) nem canal', () {
      final p = ClienteRepository.payloadAtualizacao(
        _cliente(celular: 'kyte-sem-numero-3', canal: canalKyteHistorico, telefoneKyte: '21974464293'),
      );
      expect(p.containsKey('telefone'), isFalse);
      expect(p.containsKey('canal_origem'), isFalse);
      expect(p['endereco'], 'Rua A'); // o resto do cadastro continua editável
    });
    test('Kyte não promovido com número digitado: ainda não grava em telefone', () {
      final p = ClienteRepository.payloadAtualizacao(
        _cliente(celular: '(21) 97446-4293', canal: canalKyteHistorico),
      );
      expect(p.containsKey('telefone'), isFalse);
      expect(p.containsKey('canal_origem'), isFalse);
    });
    test('objeto desatualizado com placeholder não sobrescreve telefone promovido', () {
      final p = ClienteRepository.payloadAtualizacao(_cliente(celular: 'kyte-sem-numero-3', canal: ''));
      expect(p.containsKey('telefone'), isFalse);
    });
  });

  group('ClientProvider', () {
    test('lista não congela depois de buscar e limpar a busca (bug 26/09)', () {
      final provider = ClientProvider()
        ..definirClientesParaTeste([_cliente(id: 'a', nome: 'Ana'), _cliente(id: 'b', nome: 'Bia')]);
      provider.pesquisarClientes('ana');
      expect(provider.clientesFiltrados.map((c) => c.idCliente), ['a']);
      expect(provider.clientes.length, 2, reason: '`clientes` é sempre a lista completa');
      provider.pesquisarClientes('');

      provider.substituirLocal(_cliente(id: 'c', nome: 'Mariana'));
      expect(provider.clientes.any((c) => c.idCliente == 'c'), isTrue);
      expect(provider.clientesFiltrados.any((c) => c.idCliente == 'c'), isTrue);

      provider.substituirLocal(_cliente(id: 'a', nome: 'Ana', celular: '5521999998888'));
      expect(provider.clientes.firstWhere((c) => c.idCliente == 'a').celular, '5521999998888');
    });

    test('busca ativa continua funcionando e reflete edições', () {
      final provider = ClientProvider()..definirClientesParaTeste([_cliente(id: 'a', nome: 'Ana')]);
      provider.pesquisarClientes('ana');
      provider.substituirLocal(_cliente(id: 'a', nome: 'Ana Paula'));
      expect(provider.clientesFiltrados.single.nome, 'Ana Paula');
      provider.pesquisarClientes('zzz');
      expect(provider.clientesFiltrados, isEmpty);
    });

    test('cadastro Kyte não promovido sai da lista normal', () {
      final provider = ClientProvider()..definirClientesParaTeste([_cliente(id: 'k', nome: 'Kyte')]);
      provider.substituirLocal(_cliente(id: 'k', nome: 'Kyte', canal: canalKyteHistorico));
      expect(provider.clientes, isEmpty);
    });
  });
}
