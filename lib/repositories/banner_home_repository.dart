import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/banner_home.dart';

/// Banners rotativos da home do site (`banners_home`) + upload das
/// mídias pro bucket `banners` do Storage — mesma convenção de path do
/// bucket `produtos` (`{empresaId}/...`), ver `upload_imagem_produto.dart`.
class BannerHomeRepository {
  Future<List<BannerHome>> listar() async {
    final data = await supabase.from('banners_home').select().order('ordem', ascending: true);
    return (data as List).map((row) => BannerHome.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  Future<BannerHome> criar(BannerHome banner, {required String empresaId}) async {
    final row = await supabase
        .from('banners_home')
        .insert({...banner.toSupabaseMap(), 'empresa_id': empresaId})
        .select()
        .single();
    return BannerHome.fromSupabase(row);
  }

  Future<void> atualizar(BannerHome banner) async {
    if (banner.id == null) {
      throw ArgumentError('Banner sem id não pode ser atualizado');
    }
    await supabase.from('banners_home').update(banner.toSupabaseMap()).eq('id', banner.id!);
  }

  Future<void> excluir(String bannerId) async {
    await supabase.from('banners_home').delete().eq('id', bannerId);
  }

  Future<void> reordenar(List<BannerHome> emOrdem) async {
    for (var i = 0; i < emOrdem.length; i++) {
      final id = emOrdem[i].id;
      if (id != null) {
        await supabase.from('banners_home').update({'ordem': i}).eq('id', id);
      }
    }
  }

  /// Upload de imagem — redimensiona/comprime igual ao padrão de foto de
  /// produto (`uploadImagemProduto`), banner não precisa de resolução maior
  /// que isso pra web.
  Future<String> uploadImagem({
    required Uint8List bytes,
    required String empresaId,
  }) async {
    final bytesProcessados = _comprimirImagem(bytes);
    final path = '$empresaId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await supabase.storage.from('banners').uploadBinary(
          path,
          bytesProcessados,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
    return supabase.storage.from('banners').getPublicUrl(path);
  }

  /// Upload de vídeo — sobe direto (sem processar, o Flutter não tem como
  /// recomprimir vídeo sem uma lib de encoding nova); nomes/extensão
  /// preservados só pra facilitar debug manual no Storage.
  Future<String> uploadVideo({
    required Uint8List bytes,
    required String empresaId,
    required String nomeArquivoOriginal,
  }) async {
    final extensao = nomeArquivoOriginal.contains('.') ? nomeArquivoOriginal.split('.').last : 'mp4';
    final path = '$empresaId/${DateTime.now().millisecondsSinceEpoch}.$extensao';
    await supabase.storage.from('banners').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: 'video/$extensao', upsert: true),
        );
    return supabase.storage.from('banners').getPublicUrl(path);
  }

  Uint8List _comprimirImagem(Uint8List bytesOriginais) {
    final decodificada = img.decodeImage(bytesOriginais);
    if (decodificada == null) return bytesOriginais;
    // 1920px cobre a largura recomendada (ver banners_loja_screen.dart) sem
    // subir arquivo maior que o necessário pro carrossel do site.
    const larguraMaxima = 1920;
    final redimensionada =
        decodificada.width > larguraMaxima ? img.copyResize(decodificada, width: larguraMaxima) : decodificada;
    return img.encodeJpg(redimensionada, quality: 88);
  }
}
