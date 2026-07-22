import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';
import '../widgets/form_section.dart';

/// Configurações > Meu Recibo: o que aparece no PDF gerado na tela de
/// detalhes da venda (logo, CNPJ, mensagem de rodapé).
class MeuReciboScreen extends StatefulWidget {
  const MeuReciboScreen({super.key});

  @override
  State<MeuReciboScreen> createState() => _MeuReciboScreenState();
}

class _MeuReciboScreenState extends State<MeuReciboScreen> {
  final _mensagemController = TextEditingController();
  bool _mostrarLogo = true;
  bool _mostrarCnpj = true;
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  @override
  void dispose() {
    _mensagemController.dispose();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) {
      setState(() => _carregando = false);
      return;
    }

    try {
      final data = await supabase
          .from('empresas')
          .select('recibo_mensagem, recibo_mostrar_logo, recibo_mostrar_cnpj')
          .eq('id', empresaId)
          .single();

      _mensagemController.text = data['recibo_mensagem']?.toString() ?? '';
      _mostrarLogo = data['recibo_mostrar_logo'] as bool? ?? true;
      _mostrarCnpj = data['recibo_mostrar_cnpj'] as bool? ?? true;
    } catch (e) {
      debugPrint('Erro ao carregar configuração do recibo: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;

    setState(() => _salvando = true);
    try {
      await supabase.from('empresas').update({
        'recibo_mensagem': _mensagemController.text.trim(),
        'recibo_mostrar_logo': _mostrarLogo,
        'recibo_mostrar_cnpj': _mostrarCnpj,
      }).eq('id', empresaId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuração do recibo salva com sucesso!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meu Recibo'),
        actions: [
          _salvando
              ? Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary, strokeWidth: 2),
                  ),
                )
              : IconButton(icon: const Icon(Icons.save), onPressed: _carregando ? null : _salvar),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Controla o que aparece no recibo em PDF (gerado na tela de detalhes de cada venda).',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 16),
                FormSection(
                  titulo: 'Conteúdo do recibo',
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mostrar logo da loja'),
                      subtitle: const Text('Usa o logo configurado em Aparência e Marca'),
                      value: _mostrarLogo,
                      onChanged: (v) => setState(() => _mostrarLogo = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mostrar CNPJ e razão social'),
                      subtitle: const Text('Usa os dados cadastrados em Dados da Loja'),
                      value: _mostrarCnpj,
                      onChanged: (v) => setState(() => _mostrarCnpj = v),
                    ),
                    TextField(
                      controller: _mensagemController,
                      decoration: const InputDecoration(
                        labelText: 'Mensagem no rodapé (Opcional)',
                        hintText: 'Ex: Obrigado pela preferência! Volte sempre.',
                      ),
                      maxLines: 3,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _salvando ? null : _salvar,
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                  child: const Text('Salvar'),
                ),
              ],
            ),
    );
  }
}
