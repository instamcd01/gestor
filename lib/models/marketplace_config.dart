class MarketplaceConfig {
  final String? id;
  final String marketplaceId;
  final bool ativo;
  final String idLojaPlataforma;
  final String apiKey;
  final String apiSecret;
  final String observacoes;

  MarketplaceConfig({
    this.id,
    required this.marketplaceId,
    this.ativo = false,
    this.idLojaPlataforma = '',
    this.apiKey = '',
    this.apiSecret = '',
    this.observacoes = '',
  });

  factory MarketplaceConfig.fromSupabase(Map<String, dynamic> row) {
    return MarketplaceConfig(
      id: row['id'] as String?,
      marketplaceId: row['marketplace_id'] as String,
      ativo: row['ativo'] as bool? ?? false,
      idLojaPlataforma: row['id_loja_plataforma']?.toString() ?? '',
      apiKey: row['api_key']?.toString() ?? '',
      apiSecret: row['api_secret']?.toString() ?? '',
      observacoes: row['observacoes']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'marketplace_id': marketplaceId,
      'ativo': ativo,
      'id_loja_plataforma': idLojaPlataforma,
      'api_key': apiKey,
      'api_secret': apiSecret,
      'observacoes': observacoes,
    };
  }
}
