import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';
import '../widgets/form_section.dart';

/// Dados cadastrais da empresa (Configurações > Dados da Loja). Preenche
/// informações que os marketplaces (iFood, 99Food, Rappi, ...) exigem no
/// cadastro do parceiro: CNPJ, razão social, endereço, contato.
class DadosLojaScreen extends StatefulWidget {
  const DadosLojaScreen({super.key});

  @override
  State<DadosLojaScreen> createState() => _DadosLojaScreenState();
}

class _DadosLojaScreenState extends State<DadosLojaScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nomeController = TextEditingController();
  final _razaoSocialController = TextEditingController();
  final _cnpjController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _enderecoController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _estadoController = TextEditingController();
  final _cepController = TextEditingController();
  final _taxaEntregaController = TextEditingController();

  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregarDados();
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
          .select(
              'nome, razao_social, cnpj, telefone, email, endereco, cidade, estado, cep, taxa_entrega_padrao')
          .eq('id', empresaId)
          .single();

      _nomeController.text = data['nome']?.toString() ?? '';
      _razaoSocialController.text = data['razao_social']?.toString() ?? '';
      _cnpjController.text = data['cnpj']?.toString() ?? '';
      _telefoneController.text = data['telefone']?.toString() ?? '';
      _emailController.text = data['email']?.toString() ?? '';
      _enderecoController.text = data['endereco']?.toString() ?? '';
      _cidadeController.text = data['cidade']?.toString() ?? '';
      _estadoController.text = data['estado']?.toString() ?? '';
      _cepController.text = data['cep']?.toString() ?? '';
      _taxaEntregaController.text =
          (data['taxa_entrega_padrao'] as num?)?.toString() ?? '';
    } catch (e) {
      debugPrint('Erro ao carregar dados da loja: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar dados da loja: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;

    setState(() => _salvando = true);
    try {
      await supabase.from('empresas').update({
        'nome': _nomeController.text.trim(),
        'razao_social': _razaoSocialController.text.trim(),
        'cnpj': _cnpjController.text.trim(),
        'telefone': _telefoneController.text.trim(),
        'email': _emailController.text.trim(),
        'endereco': _enderecoController.text.trim(),
        'cidade': _cidadeController.text.trim(),
        'estado': _estadoController.text.trim(),
        'cep': _cepController.text.trim(),
        'taxa_entrega_padrao':
            double.tryParse(_taxaEntregaController.text.replaceAll(',', '.')),
      }).eq('id', empresaId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dados da loja atualizados com sucesso!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar dados da loja: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _razaoSocialController.dispose();
    _cnpjController.dispose();
    _telefoneController.dispose();
    _emailController.dispose();
    _enderecoController.dispose();
    _cidadeController.dispose();
    _estadoController.dispose();
    _cepController.dispose();
    _taxaEntregaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dados da Loja'),
        actions: [
          _salvando
              ? Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Theme.of(context).colorScheme.primary, strokeWidth: 2),
                  ),
                )
              : IconButton(icon: const Icon(Icons.save), onPressed: _salvar),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Esses dados são usados no cadastro de parceiro em marketplaces '
                      '(iFood, 99Food, Rappi, etc.) e em notas/recibos emitidos pelo app.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 20),
                    FormSection(
                      titulo: 'Identificação',
                      children: [
                        TextFormField(
                          controller: _nomeController,
                          decoration: const InputDecoration(labelText: 'Nome da loja (fantasia)'),
                          validator: (v) => v == null || v.isEmpty ? 'Informe o nome da loja' : null,
                        ),
                        TextFormField(
                          controller: _razaoSocialController,
                          decoration: const InputDecoration(labelText: 'Razão social'),
                        ),
                        TextFormField(
                          controller: _cnpjController,
                          decoration: const InputDecoration(labelText: 'CNPJ', hintText: '00.000.000/0000-00'),
                          keyboardType: TextInputType.number,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FormSection(
                      titulo: 'Contato e endereço',
                      children: [
                        TextFormField(
                          controller: _telefoneController,
                          decoration: const InputDecoration(labelText: 'Telefone'),
                          keyboardType: TextInputType.phone,
                        ),
                        TextFormField(
                          controller: _emailController,
                          decoration: const InputDecoration(labelText: 'E-mail'),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        TextFormField(
                          controller: _enderecoController,
                          decoration: const InputDecoration(labelText: 'Endereço'),
                        ),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _cidadeController,
                                decoration: const InputDecoration(labelText: 'Cidade'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                controller: _estadoController,
                                decoration: const InputDecoration(labelText: 'UF'),
                                maxLength: 2,
                                textCapitalization: TextCapitalization.characters,
                              ),
                            ),
                          ],
                        ),
                        TextFormField(
                          controller: _cepController,
                          decoration: const InputDecoration(labelText: 'CEP'),
                          keyboardType: TextInputType.number,
                        ),
                        TextFormField(
                          controller: _taxaEntregaController,
                          decoration: const InputDecoration(
                            labelText: 'Taxa de entrega padrão (R\$)',
                            prefixText: 'R\$ ',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: (value) {
                            if (value != null &&
                                value.isNotEmpty &&
                                double.tryParse(value.replaceAll(',', '.')) == null) {
                              return 'Número inválido';
                            }
                            return null;
                          },
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
              ),
            ),
    );
  }
}
