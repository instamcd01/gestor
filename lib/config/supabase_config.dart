import 'package:supabase_flutter/supabase_flutter.dart';

/// Configuração central de acesso ao Supabase.
///
/// A chave publishable/anon é segura para ficar no app (é feita pra isso),
/// mas quem realmente protege os dados é o RLS configurado no banco —
/// nunca use a service_role key aqui no client.
class SupabaseConfig {
  static const String url = 'https://dwswpwxnzjgoohucngbb.supabase.co';
  static const String anonKey =
      'sb_publishable_7ktXRTRJeD8cc5k1RDyEDg_1_HNzAdc';

  static Future<void> inicializar() async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
  }
}

/// Atalho pra acessar o client Supabase de qualquer lugar do app.
final supabase = Supabase.instance.client;
