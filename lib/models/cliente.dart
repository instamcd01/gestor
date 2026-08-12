import 'pet.dart';

class Cliente {
  final String? idCliente;
  final String nome;
  final String celular;
  final String email;
  final String endereco;
  final String numero;
  final String bairro;
  final String cidade;
  final String estado;
  final String cep;
  final String complemento;
  final String cpf;
  final String observacao;
  final double saldo;
  /// PetCash (cashback) disponível — gerido pelo site (gerar_petcash_pedido/consumir_petcash), só leitura aqui.
  final double saldoPetCash;
  final List<Pet> pets;

  // Estratégico
  final DateTime? dataCadastro;
  final DateTime? aniversario;
  final String? canalOrigem;

  // Vendas e comportamento
  final int? quantidadeCompras;
  final double? totalGasto;
  final int? numeroCompras;
  final DateTime? ultimaCompra;
  final double? ticketMedio;

  // Relacionamento
  final DateTime? proximaVisita;
  final String? motivoUltimaVisita;

  // Marketing
  final bool? aceitaMarketing;
  final DateTime? ultimoContato;
  final String? canalPreferido;

  // Análise
  final String? categoriaCliente;
  final double? fidelidadeScore;
  final List<String>? interesses;

  // Documentação
  final List<String>? documentos;
  final Map<String, dynamic>? observacoesExtras;

  // Distância e entrega
  final double? rangeDistancia; // km
  final int? estimativaEntrega; // minutos

  // Localização exata (selecionada no mapa) — desambigua endereço quando
  // o nome da rua se repete (ex: "Rua 7" em bairros/cidades diferentes).
  final double? latitude;
  final double? longitude;

  Cliente({
    this.idCliente,
    required this.nome,
    required this.celular,
    required this.email,
    required this.endereco,
    this.numero = '',
    this.bairro = '',
    this.cidade = '',
    this.estado = '',
    this.cep = '',
    required this.complemento,
    required this.cpf,
    required this.observacao,
    required this.saldo,
    this.saldoPetCash = 0.0,
    required this.pets,
    this.dataCadastro,
    this.aniversario,
    this.canalOrigem,
    this.quantidadeCompras,
    this.totalGasto,
    this.numeroCompras,
    this.ultimaCompra,
    this.ticketMedio,
    this.proximaVisita,
    this.motivoUltimaVisita,
    this.aceitaMarketing,
    this.ultimoContato,
    this.canalPreferido,
    this.categoriaCliente,
    this.fidelidadeScore,
    this.interesses,
    this.documentos,
    this.observacoesExtras,
    this.rangeDistancia,
    this.estimativaEntrega,
    this.latitude,
    this.longitude,
  });

  List<String> get especies => pets.map((p) => p.especie).toSet().toList();

  Cliente copyWith({double? saldo, double? rangeDistancia, int? estimativaEntrega}) {
    return Cliente(
      idCliente: idCliente,
      nome: nome,
      celular: celular,
      email: email,
      endereco: endereco,
      numero: numero,
      bairro: bairro,
      cidade: cidade,
      estado: estado,
      cep: cep,
      complemento: complemento,
      cpf: cpf,
      observacao: observacao,
      saldo: saldo ?? this.saldo,
      pets: pets,
      dataCadastro: dataCadastro,
      aniversario: aniversario,
      canalOrigem: canalOrigem,
      quantidadeCompras: quantidadeCompras,
      totalGasto: totalGasto,
      numeroCompras: numeroCompras,
      ultimaCompra: ultimaCompra,
      ticketMedio: ticketMedio,
      proximaVisita: proximaVisita,
      motivoUltimaVisita: motivoUltimaVisita,
      aceitaMarketing: aceitaMarketing,
      ultimoContato: ultimoContato,
      canalPreferido: canalPreferido,
      categoriaCliente: categoriaCliente,
      fidelidadeScore: fidelidadeScore,
      interesses: interesses,
      documentos: documentos,
      observacoesExtras: observacoesExtras,
      rangeDistancia: rangeDistancia ?? this.rangeDistancia,
      estimativaEntrega: estimativaEntrega ?? this.estimativaEntrega,
      latitude: latitude,
      longitude: longitude,
    );
  }

  /// Endereço completo pra exibição — rua+número, bairro, cidade-UF e
  /// CEP, pulando as partes vazias. Único lugar que monta esse texto, pra
  /// não ter tela mostrando só a rua enquanto outra mostra tudo.
  String get enderecoCompleto {
    final partes = <String>[];
    if (endereco.isNotEmpty) {
      partes.add(numero.isNotEmpty ? '$endereco, $numero' : endereco);
    }
    if (bairro.isNotEmpty) partes.add(bairro);

    final cidadeUf = [cidade, estado].where((s) => s.isNotEmpty).join(' - ');
    if (cidadeUf.isNotEmpty) partes.add(cidadeUf);

    if (cep.isNotEmpty) partes.add('CEP $cep');

    return partes.join(', ');
  }

  /// Monta o Cliente a partir de uma linha do Supabase.
  /// Espera `.select('*, pets(*)')`. Campos "extras" que não têm coluna
  /// própria no banco (aniversário, interesses, etc.) ficam guardados
  /// dentro da coluna `metadata` (jsonb).
  factory Cliente.fromSupabase(Map<String, dynamic> row) {
    final metadata = (row['metadata'] as Map<String, dynamic>?) ?? {};
    final petsRows = (row['pets'] as List?) ?? [];

    DateTime? parseData(dynamic v) => v != null ? DateTime.tryParse(v.toString()) : null;

    return Cliente(
      idCliente: row['id'] as String?,
      nome: row['nome']?.toString() ?? '',
      celular: row['telefone']?.toString() ?? '',
      email: row['email']?.toString() ?? '',
      endereco: row['endereco']?.toString() ?? '',
      numero: row['numero']?.toString() ?? '',
      bairro: row['bairro']?.toString() ?? '',
      cidade: row['cidade']?.toString() ?? '',
      estado: row['estado']?.toString() ?? '',
      cep: row['cep']?.toString() ?? '',
      complemento: row['complemento']?.toString() ?? '',
      cpf: row['cpf']?.toString() ?? '',
      observacao: metadata['observacao']?.toString() ?? '',
      saldo: (row['saldo'] as num?)?.toDouble() ?? 0.0,
      saldoPetCash: (row['saldo_petcash'] as num?)?.toDouble() ?? 0.0,
      pets: petsRows.map((p) => Pet.fromSupabase(p as Map<String, dynamic>)).toList(),
      dataCadastro: parseData(row['created_at']),
      // Antes ficava preso no metadata (JSON); agora usa a coluna real
      // `data_nascimento`, que já existe na tabela e é a mesma usada por
      // relatórios/campanhas de aniversário feitos direto no banco.
      aniversario: parseData(row['data_nascimento']),
      canalOrigem: row['canal_origem']?.toString(),
      quantidadeCompras: (row['total_pedidos'] as num?)?.toInt(),
      totalGasto: (row['total_gasto'] as num?)?.toDouble() ?? 0.0,
      numeroCompras: (row['total_pedidos'] as num?)?.toInt(),
      ultimaCompra: parseData(row['ultima_compra']),
      ticketMedio: (row['ticket_medio'] as num?)?.toDouble() ?? 0.0,
      proximaVisita: parseData(metadata['proximaVisita']),
      motivoUltimaVisita: metadata['motivoUltimaVisita']?.toString(),
      aceitaMarketing: row['aceita_marketing'] as bool?,
      ultimoContato: parseData(metadata['ultimoContato']),
      canalPreferido: metadata['canalPreferido']?.toString(),
      categoriaCliente: row['segmento']?.toString(),
      fidelidadeScore: (row['score_fidelidade'] as num?)?.toDouble() ?? 0.0,
      interesses: metadata['interesses'] != null
          ? List<String>.from(metadata['interesses'])
          : [],
      documentos: metadata['documentos'] != null
          ? List<String>.from(metadata['documentos'])
          : [],
      observacoesExtras: metadata['observacoesExtras'] != null
          ? Map<String, dynamic>.from(metadata['observacoesExtras'])
          : {},
      rangeDistancia: (metadata['rangeDistancia'] as num?)?.toDouble(),
      estimativaEntrega: (metadata['estimativaEntrega'] as num?)?.toInt(),
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
    );
  }

  /// Payload pra INSERT/UPDATE na tabela `clientes` (não inclui pets,
  /// que são tratados à parte pelo repositório).
  Map<String, dynamic> toSupabaseMap() {
    return {
      'nome': nome,
      'telefone': celular,
      'email': email,
      'endereco': endereco,
      'numero': numero,
      'bairro': bairro,
      'cidade': cidade,
      'estado': estado,
      'cep': cep,
      'complemento': complemento,
      'cpf': cpf,
      'latitude': latitude,
      'longitude': longitude,
      'saldo': saldo,
      'canal_origem': canalOrigem,
      'aceita_marketing': aceitaMarketing ?? true,
      'segmento': categoriaCliente,
      'data_nascimento': aniversario?.toIso8601String().split('T').first,
      'metadata': {
        'observacao': observacao,
        'proximaVisita': proximaVisita?.toIso8601String(),
        'motivoUltimaVisita': motivoUltimaVisita,
        'ultimoContato': ultimoContato?.toIso8601String(),
        'canalPreferido': canalPreferido,
        'interesses': interesses,
        'documentos': documentos,
        'observacoesExtras': observacoesExtras,
        'rangeDistancia': rangeDistancia,
        'estimativaEntrega': estimativaEntrega,
      },
    };
  }
}
