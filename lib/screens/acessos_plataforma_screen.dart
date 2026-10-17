import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Acessos da equipe da plataforma (INARI) aos dados desta loja.
///
/// Promessa dos termos de uso: a equipe só abre dados de uma loja quando
/// precisa (suporte, correção de problema, teste de segurança) e cada acesso
/// fica registrado com quem, quando e por quê. A loja só LÊ: o banco não
/// deixa ninguém do app gravar, alterar ou apagar um registro
/// (tabela `acessos_plataforma`, RLS por empresa).
class AcessosPlataformaScreen extends StatefulWidget {
  const AcessosPlataformaScreen({super.key});

  @override
  State<AcessosPlataformaScreen> createState() => _AcessosPlataformaScreenState();
}

class _AcessosPlataformaScreenState extends State<AcessosPlataformaScreen> {
  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _acessos = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      // a RLS já limita aos registros desta loja
      final linhas = await Supabase.instance.client
          .from('acessos_plataforma')
          .select('quem, motivo, o_que, origem, criado_em')
          .order('criado_em', ascending: false)
          .limit(200);
      if (!mounted) return;
      setState(() {
        _acessos = (linhas as List).cast<Map<String, dynamic>>();
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar os acessos. Tente de novo.';
        _carregando = false;
      });
    }
  }

  static const _origem = {
    'banco': 'direto no banco de dados',
    'painel': 'pelo painel da plataforma',
    'app': 'pelo app',
    'automacao': 'por uma automação',
  };

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    // só números: o app não inicializa as datas em português (ver planejamento_screen.dart)
    final dia = DateFormat('dd/MM/yyyy');
    final hora = DateFormat('HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Acessos da equipe INARI')),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'A equipe da INARI só abre os dados da sua loja quando precisa, por exemplo para dar suporte ou '
              'corrigir um problema. Cada acesso aparece aqui, com quem acessou, quando e por quê. '
              'Ninguém consegue apagar ou alterar esta lista.',
              style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (_carregando)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (_erro != null)
              Column(children: [
                Text(_erro!, style: TextStyle(color: tema.colorScheme.error)),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _carregar, child: const Text('Tentar de novo')),
              ])
            else if (_acessos.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Nenhum acesso da equipe aos dados da sua loja até agora.', style: tema.textTheme.bodyLarge),
                ),
              )
            else
              ..._acessos.map((a) {
                final quando = DateTime.tryParse(a['criado_em'] as String? ?? '')?.toLocal();
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: const Icon(Icons.shield_outlined),
                    title: Text(a['motivo'] as String? ?? ''),
                    subtitle: Text([
                      '${a['quem']} · ${quando != null ? '${dia.format(quando)} às ${hora.format(quando)}' : ''}',
                      if ((a['o_que'] as String?)?.isNotEmpty ?? false) a['o_que'] as String,
                      _origem[a['origem']] ?? '',
                    ].where((l) => l.isNotEmpty).join('\n')),
                    isThreeLine: true,
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
