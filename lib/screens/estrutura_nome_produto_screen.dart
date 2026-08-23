import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';
import '../repositories/valor_estruturado_repository.dart';

/// Exemplo mostrado no preview de cada campo, na mesma formatação que
/// `compor_nome_produto` aplica (parênteses, "Para ", "de Porte ", "Sabor ").
const Map<String, String> _exemplosCampo = {
  'tipo_produto': 'Tipo de Produto',
  'nome_comercial': 'Nome Comercial',
  'dose': '250mg',
  'composicao': 'Princípio Ativo',
  'apresentacao': '10 Comprimidos',
  'especie': 'Cães e Gatos',
  'fase': 'Adultos',
  'porte': 'Pequeno',
  'sabor': 'Frango',
};

/// Único campo que nunca pode ser removido da estrutura — sem nome
/// comercial o produto fica sem identidade no nome gerado. Pode ser
/// reordenado, só não desativado. Fabricante/Peso/Volume, ao contrário,
/// são tão configuráveis (posição e presença) quanto os outros — inclusive
/// dá pra tirar o fabricante do nome de uma categoria específica, se fizer
/// sentido pra ela.
const _campoFixo = 'nome_comercial';

/// Tela pra montar/cadastrar, categoria por categoria, quais campos entram
/// no "Nome do Produto" gerado automaticamente (`compor_nome_produto`) e EM
/// QUE ORDEM — e ver de relance o que já está configurado em cada
/// categoria. Sem nenhuma linha em `categoria_campos_estruturados` pra uma
/// categoria, o padrão é mostrar todos os campos na ordem histórica
/// (`ordemPadraoCamposEstruturados`), igual já acontecia antes de essa tabela existir.
///
/// Os campos de entrada de Peso/Volume/Fabricante continuam na seção
/// "Logística e fornecedor" do cadastro/edição de produto (servem também
/// pra frete e organização de imagens, não só pro nome) — só a posição
/// deles dentro do nome gerado é decidida aqui.
class EstruturaNomeProdutoScreen extends StatefulWidget {
  const EstruturaNomeProdutoScreen({super.key});

  @override
  State<EstruturaNomeProdutoScreen> createState() => _EstruturaNomeProdutoScreenState();
}

class _EstruturaNomeProdutoScreenState extends State<EstruturaNomeProdutoScreen> {
  bool _carregando = true;
  List<Map<String, dynamic>> _categorias = [];
  Map<String, List<String>> _estrutura = {};

  @override
  void initState() {
    super.initState();
    _carregarTudo();
  }

  Future<void> _carregarTudo() async {
    setState(() => _carregando = true);
    try {
      final categorias = await supabase.from('categorias').select('id, nome').order('ordem');
      final linhas = await supabase
          .from('categoria_campos_estruturados')
          .select('categoria, campo, ordem')
          .order('ordem');
      final estrutura = <String, List<String>>{};
      for (final linha in (linhas as List)) {
        (estrutura[linha['categoria'] as String] ??= []).add(linha['campo'] as String);
      }
      if (!mounted) return;
      setState(() {
        _categorias = List<Map<String, dynamic>>.from(categorias);
        _estrutura = estrutura;
        _carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar estrutura de nome: $e');
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _abrirEdicao(String categoriaNome) async {
    final atual = _estrutura[categoriaNome];
    final salvou = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DialogoEstruturaCategoria(
        categoriaNome: categoriaNome,
        ordemInicial: atual ?? List.of(ordemPadraoCamposEstruturados),
        eraPersonalizado: atual != null,
      ),
    );
    if (salvou == true) await _carregarTudo();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Estrutura do Nome dos Produtos')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Escolha quais campos entram no "Nome do Produto" gerado automaticamente em '
                    'cada categoria, e em que ordem — inclusive Fabricante, Peso e Volume. '
                    'Nome comercial não pode ser removido. Categoria sem configuração usa a '
                    'ordem padrão com todos os campos.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                Expanded(
                  child: _categorias.isEmpty
                      ? const Center(child: Text('Cadastre uma categoria primeiro.'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _categorias.length,
                          itemBuilder: (context, index) {
                            final categoriaNome = _categorias[index]['nome'] as String;
                            final ordem = _estrutura[categoriaNome];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(categoriaNome),
                                subtitle: Text(
                                  (ordem ?? ordemPadraoCamposEstruturados)
                                      .map((c) => rotulosCamposEstruturados[c] ?? c)
                                      .join('  →  '),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _abrirEdicao(categoriaNome),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _DialogoEstruturaCategoria extends StatefulWidget {
  final String categoriaNome;
  final List<String> ordemInicial;
  final bool eraPersonalizado;

  const _DialogoEstruturaCategoria({
    required this.categoriaNome,
    required this.ordemInicial,
    required this.eraPersonalizado,
  });

  @override
  State<_DialogoEstruturaCategoria> createState() => _DialogoEstruturaCategoriaState();
}

class _DialogoEstruturaCategoriaState extends State<_DialogoEstruturaCategoria> {
  late List<String> _ativos;
  String? _preview;
  bool _salvando = false;

  List<String> get _disponiveis => [
        for (final c in ordemPadraoCamposEstruturados)
          if (!_ativos.contains(c)) c,
      ];

  @override
  void initState() {
    super.initState();
    _ativos = List.of(widget.ordemInicial);
    if (!_ativos.contains(_campoFixo)) _ativos.add(_campoFixo);
    _atualizarPreview();
  }

  Future<void> _atualizarPreview() async {
    try {
      final resultado = await supabase.rpc('compor_nome_produto', params: {
        'p_categoria': widget.categoriaNome,
        'p_nome_comercial': _exemplosCampo['nome_comercial'],
        'p_tipo_produto': _exemplosCampo['tipo_produto'],
        'p_dose': _exemplosCampo['dose'],
        'p_composicao': _exemplosCampo['composicao'],
        'p_apresentacao': _exemplosCampo['apresentacao'],
        'p_especie': _exemplosCampo['especie'],
        'p_fase': _exemplosCampo['fase'],
        'p_porte': _exemplosCampo['porte'],
        'p_sabor': _exemplosCampo['sabor'],
        // Peso e volume são mutuamente exclusivos na formatação real (peso
        // tem prioridade) — manda só peso no preview quando os dois
        // estiverem ativos, pra não sugerir que os dois apareceriam juntos.
        'p_peso': _ativos.contains('peso') ? 10 : null,
        'p_volume': !_ativos.contains('peso') && _ativos.contains('volume') ? 500 : null,
        'p_fabricante': _ativos.contains('fabricante') ? 'Fabricante' : null,
        'p_ordem_campos': _ativos,
      });
      if (!mounted) return;
      setState(() => _preview = resultado as String?);
    } catch (e) {
      debugPrint('Erro ao pré-visualizar estrutura de nome: $e');
    }
  }

  void _adicionar(String campo) {
    setState(() => _ativos.add(campo));
    _atualizarPreview();
  }

  void _remover(String campo) {
    if (campo == _campoFixo) return;
    setState(() => _ativos.remove(campo));
    _atualizarPreview();
  }

  void _reordenar(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      final item = _ativos.removeAt(oldIndex);
      _ativos.insert(newIndex, item);
    });
    _atualizarPreview();
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    try {
      final empresaId = context.read<AuthProvider>().empresaId;
      if (empresaId == null) return;

      final atuais = widget.ordemInicial.toSet();
      final novos = _ativos.toSet();
      final paraRemover = atuais.difference(novos);

      // Categoria nunca personalizada antes (fallback = ordem padrão) mas o
      // resultado final é idêntico ao padrão: não precisa gravar nada.
      if (!widget.eraPersonalizado && paraRemover.isEmpty && _listEquals(_ativos, ordemPadraoCamposEstruturados)) {
        if (mounted) Navigator.pop(context, true);
        return;
      }

      if (paraRemover.isNotEmpty) {
        await supabase
            .from('categoria_campos_estruturados')
            .delete()
            .eq('categoria', widget.categoriaNome)
            .inFilter('campo', paraRemover.toList());
      }
      await supabase.from('categoria_campos_estruturados').upsert([
        for (var i = 0; i < _ativos.length; i++)
          {'empresa_id': empresaId, 'categoria': widget.categoriaNome, 'campo': _ativos[i], 'ordem': i},
      ], onConflict: 'empresa_id,categoria,campo');

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Erro ao salvar estrutura de nome: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _restaurarPadrao() async {
    setState(() => _salvando = true);
    try {
      await supabase.from('categoria_campos_estruturados').delete().eq('categoria', widget.categoriaNome);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Erro ao restaurar padrão da estrutura de nome: $e');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(widget.categoriaNome),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _preview?.isNotEmpty == true ? _preview! : '(preencha ao menos um campo)',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Prévia com valores de exemplo. Peso e volume nunca aparecem juntos — '
                'quando um produto tem os dois preenchidos, peso tem prioridade.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Text('Campos usados, na ordem do nome (arraste para reordenar)',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                onReorder: _reordenar,
                children: [
                  for (final campo in _ativos)
                    ListTile(
                      key: ValueKey(campo),
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: 4),
                      title: Text(rotulosCamposEstruturados[campo] ?? campo),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (campo != _campoFixo)
                            IconButton(
                              tooltip: 'Remover',
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => _remover(campo),
                            ),
                          const Icon(Icons.drag_handle),
                        ],
                      ),
                    ),
                ],
              ),
              if (_disponiveis.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Campos disponíveis', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final campo in _disponiveis)
                      ActionChip(
                        label: Text(rotulosCamposEstruturados[campo] ?? campo),
                        avatar: const Icon(Icons.add, size: 16),
                        onPressed: () => _adicionar(campo),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (widget.eraPersonalizado)
          TextButton(
            onPressed: _salvando ? null : _restaurarPadrao,
            child: const Text('Restaurar padrão'),
          ),
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _salvando ? null : _salvar, child: const Text('Salvar')),
      ],
    );
  }
}
