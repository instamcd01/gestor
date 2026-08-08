import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/marca_ativo.dart';

/// Kit de marca da empresa: galeria de ativos (mascote/logo/nome-imagem) +
/// upload pro bucket `logos` do Storage, e a configuração de qual ativo
/// aparece em cada posição do app/site.
class MarcaRepository {
  Future<List<MarcaAtivo>> listarAtivos() async {
    final data = await supabase.from('marca_ativos').select().order('tipo').order('ordem');
    return (data as List).map((row) => MarcaAtivo.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  Future<List<MarcaPosicao>> listarPosicoes() async {
    final data = await supabase.from('marca_posicoes').select();
    return (data as List).map((row) => MarcaPosicao.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  /// Envia uma imagem nova pro tipo indicado. Tipos "únicos" (tudo exceto
  /// mascote) substituem o ativo anterior; mascote sempre insere uma linha
  /// nova (galeria).
  ///
  /// Não usa `.upsert(onConflict: ...)` pros tipos únicos de propósito: o
  /// índice único que os protege é PARCIAL (`where tipo <> 'mascote'`,
  /// pra não restringir a galeria de mascote), e o Postgres só casa
  /// `ON CONFLICT` com um índice parcial se a cláusula tiver o MESMO
  /// predicado WHERE — o que o `upsert()` do supabase_flutter não permite
  /// especificar. Sem isso dava "no unique or exclusion constraint
  /// matching the ON CONFLICT specification" em todo envio. Select do id
  /// existente + update/insert manual contorna a limitação.
  Future<MarcaAtivo> enviar({
    required Uint8List bytes,
    required String empresaId,
    required String tipo,
    String? rotulo,
    int ordem = 0,
  }) async {
    final url = await _upload(bytes: bytes, empresaId: empresaId);

    if (tipo == 'mascote') {
      final row = await supabase
          .from('marca_ativos')
          .insert({'empresa_id': empresaId, 'tipo': tipo, 'rotulo': rotulo, 'url': url, 'ordem': ordem})
          .select()
          .single();
      return MarcaAtivo.fromSupabase(row);
    }

    final existente = await supabase
        .from('marca_ativos')
        .select('id')
        .eq('empresa_id', empresaId)
        .eq('tipo', tipo)
        .maybeSingle();

    final Map<String, dynamic> row;
    if (existente != null) {
      row = await supabase
          .from('marca_ativos')
          .update({'rotulo': rotulo, 'url': url, 'ordem': ordem})
          .eq('id', existente['id'])
          .select()
          .single();
    } else {
      row = await supabase
          .from('marca_ativos')
          .insert({'empresa_id': empresaId, 'tipo': tipo, 'rotulo': rotulo, 'url': url, 'ordem': ordem})
          .select()
          .single();
    }
    return MarcaAtivo.fromSupabase(row);
  }

  Future<void> excluirAtivo(String ativoId) async {
    await supabase.from('marca_ativos').delete().eq('id', ativoId);
  }

  Future<void> atualizarRotulo(String ativoId, String rotulo) async {
    await supabase.from('marca_ativos').update({'rotulo': rotulo}).eq('id', ativoId);
  }

  /// Define o que aparece numa posição — `modo='texto'` ignora `ativoId`
  /// (mostra o nome da empresa); `modo='imagem'` exige um `ativoId`.
  Future<void> definirPosicao({
    required String empresaId,
    required String posicao,
    required String modo,
    String? ativoId,
  }) async {
    await supabase.from('marca_posicoes').upsert(
      {
        'empresa_id': empresaId,
        'posicao': posicao,
        'modo': modo,
        'ativo_id': modo == 'imagem' ? ativoId : null,
      },
      onConflict: 'empresa_id,posicao',
    );
  }

  Future<String> _upload({required Uint8List bytes, required String empresaId}) async {
    final bytesProcessados = _redimensionar(bytes);
    final path = '$empresaId/${DateTime.now().millisecondsSinceEpoch}.png';
    await supabase.storage.from('logos').uploadBinary(
          path,
          bytesProcessados,
          fileOptions: const FileOptions(contentType: 'image/png', upsert: true),
        );
    return supabase.storage.from('logos').getPublicUrl(path);
  }

  // Sempre reencoda como PNG (não JPEG, sem canal alfa) — logo/mascote
  // costumam ter fundo transparente, forçar JPEG destruiria isso com um
  // fundo sólido.
  Uint8List _redimensionar(Uint8List bytesOriginais) {
    final decodificada = img.decodeImage(bytesOriginais);
    if (decodificada == null) return bytesOriginais;
    const larguraMaxima = 1000;
    final redimensionada =
        decodificada.width > larguraMaxima ? img.copyResize(decodificada, width: larguraMaxima) : decodificada;
    return img.encodePng(redimensionada);
  }
}
