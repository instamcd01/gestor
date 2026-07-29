import 'dart:io';

import '../config/supabase_config.dart';

/// Faz upload de uma imagem de produto pro bucket `produtos` do Supabase
/// Storage e retorna a URL pública. Lança exceção em caso de erro (empresa
/// não identificada, falha de rede etc) — quem chama decide como comunicar
/// isso ao usuário. Compartilhado entre cadastro, edição e galeria de
/// imagens de produto pra não triplicar a mesma lógica.
Future<String> uploadImagemProduto(File imageFile) async {
  String? empresaId;
  final userId = supabase.auth.currentUser?.id;
  if (userId != null) {
    final usuario = await supabase
        .from('usuarios')
        .select('empresa_id')
        .eq('id', userId)
        .maybeSingle();
    empresaId = usuario?['empresa_id'] as String?;
  }

  if (empresaId == null) {
    throw Exception('Empresa não identificada para o upload.');
  }

  final fileName =
      '$empresaId/${DateTime.now().millisecondsSinceEpoch}_${imageFile.path.split('/').last}';

  await supabase.storage.from('produtos').upload(fileName, imageFile);

  return supabase.storage.from('produtos').getPublicUrl(fileName);
}
