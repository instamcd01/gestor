/// Faixa de distância com preço de entrega (ex: "0 a 5km, R$ 10,00").
/// Configurada pela loja em Configurações > Opções de Entrega e usada no
/// checkout pra calcular o frete a partir da distância real até o cliente.
class ZonaEntrega {
  final String? id;
  final String nome;
  final double distanciaMinKm;
  final double distanciaMaxKm;
  final double valor;
  final double? valorMinimoFreteGratis;
  final bool ativo;
  final int ordem;

  // Faixa de tempo estimado (minutos) — dá margem pra juntar vários pedidos
  // numa mesma rota sem virar "atrasado" assim que o mínimo passa. Nula
  // quando a zona ainda não tem faixa configurada (não gera previsão).
  final int? estimativaMinMin;
  final int? estimativaMinMax;

  ZonaEntrega({
    this.id,
    required this.nome,
    required this.distanciaMinKm,
    required this.distanciaMaxKm,
    required this.valor,
    this.valorMinimoFreteGratis,
    this.ativo = true,
    this.ordem = 0,
    this.estimativaMinMin,
    this.estimativaMinMax,
  });

  factory ZonaEntrega.fromSupabase(Map<String, dynamic> row) {
    return ZonaEntrega(
      id: row['id'] as String?,
      nome: row['nome']?.toString() ?? '',
      distanciaMinKm: (row['distancia_min_km'] as num?)?.toDouble() ?? 0,
      distanciaMaxKm: (row['distancia_max_km'] as num?)?.toDouble() ?? 0,
      valor: (row['valor'] as num?)?.toDouble() ?? 0,
      valorMinimoFreteGratis: (row['valor_minimo_frete_gratis'] as num?)?.toDouble(),
      ativo: row['ativo'] as bool? ?? true,
      ordem: (row['ordem'] as num?)?.toInt() ?? 0,
      estimativaMinMin: (row['estimativa_min_min'] as num?)?.toInt(),
      estimativaMinMax: (row['estimativa_min_max'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'nome': nome,
      'distancia_min_km': distanciaMinKm,
      'distancia_max_km': distanciaMaxKm,
      'valor': valor,
      'valor_minimo_frete_gratis': valorMinimoFreteGratis,
      'ativo': ativo,
      'ordem': ordem,
      'estimativa_min_min': estimativaMinMin,
      'estimativa_min_max': estimativaMinMax,
    };
  }

  /// true se a faixa cobre essa distância (mínimo inclusivo, máximo exclusivo).
  bool cobreDistancia(double km) => km >= distanciaMinKm && km < distanciaMaxKm;

  /// true se essa faixa se sobrepõe com outra — usado na validação do
  /// formulário pra impedir duas zonas cobrindo a mesma distância (o que
  /// deixaria o preço do frete ambíguo).
  bool sobrepoe(ZonaEntrega outra) {
    return distanciaMinKm < outra.distanciaMaxKm && outra.distanciaMinKm < distanciaMaxKm;
  }
}
