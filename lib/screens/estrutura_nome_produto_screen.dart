import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';
import '../repositories/valor_estruturado_repository.dart';
import '../widgets/campos_estruturados_variante.dart';

/// Definição de um dos 7 campos opcionais que podem entrar no nome
/// (`categoria_campos_estruturados.campo`, restrito pelo CHECK do banco),
/// na mesma ordem em que a função `compor_nome_produto` os monta — assim o
/// preview do diálogo casa com a ordem real do nome gerado.
class _CampoEstrutura {
  final String campo;
  final String exemplo;
  const _CampoEstrutura(this.campo, this.exemplo);
}

const _camposEstrutura = [
  _CampoEstrutura('dose', '250mg'),
  _CampoEstrutura('composicao', 'Princípio Ativo'),
  _CampoEstrutura('apresentacao', '10 Comprimidos'),
  _CampoEstrutura('especie', 'Cães e Gatos'),
  _CampoEstrutura('fase', 'Adultos'),
  _CampoEstrutura('porte', 'Pequeno'),
  _CampoEstrutura('sabor', 'Frango'),
];

/// Tela pra montar/cadastrar, categoria por categoria, quais dos 7 campos
/// estruturados opcionais entram no "Nome do Produto" gerado automaticamente
/// (`compor_nome_produto`) — e ver de relance o que já está configurado em
/// cada categoria. Sem nenhuma linha em `categoria_campos_estruturados` pra
/// uma categoria, o padrão (já em vigor hoje, ver `campos_estruturados_variante.dart`)
/// é mostrar todos os 7 campos no formulário de cadastro/edição.
///
/// "Tipo de produto" e "Nome comercial" não entram aqui: sempre aparecem
/// quando preenchidos, não fazem parte do CHECK dessa tabela.
class EstruturaNomeProdutoScreen extends StatefulWidget {
  const EstruturaNomeProdutoScreen({super.key});

  @override
  State<EstruturaNomeProdutoScreen> createState() => _EstruturaNomeProdutoScreenState();
}

class _EstruturaNomeProdutoScreenState extends State<EstruturaNomeProdutoScreen> {
  bool _carregando = true;
  List<Map<String, dynamic>> _categorias = [];
  Map<String, Set<String>> _estrutura = {};

  @override
  void initState() {
    super.initState();
    _carregarTudo();
  }

  Future<void> _carregarTudo() async {
    setState(() => _carregando = true);
    try {
      final categorias = await supabase.from('categorias').select('id, nome').order('ordem');
      final estrutura = await carregarCamposEstruturadosPorCategoria();
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
    // Categoria sem configuração ainda: hoje já mostra todos os campos
    // (fallback do formulário) — refletir isso marcando tudo, em vez de
    // abrir com as caixas vazias e dar a impressão errada de "nada aparece".
    final selecionados = {
      for (final c in _camposEstrutura) c.campo: atual == null || atual.contains(c.campo),
    };

    final salvou = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DialogoEstruturaCategoria(
        categoriaNome: categoriaNome,
        selecionadosIniciais: selecionados,
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
                    'Escolha quais campos entram no "Nome do Produto" gerado automaticamente '
                    'em cada categoria. "Tipo de produto" e "Nome comercial" sempre aparecem '
                    'quando preenchidos. Categoria sem configuração usa todos os campos.',
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
                            final configurados = _estrutura[categoriaNome];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(categoriaNome),
                                subtitle: configurados == null
                                    ? const Text('Padrão — todos os campos')
                                    : Text(
                                        configurados.isEmpty
                                            ? 'Nenhum campo opcional'
                                            : _camposEstrutura
                                                .where((c) => configurados.contains(c.campo))
                                                .map((c) => rotulosCamposEstruturados[c.campo])
                                                .join(', '),
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
  final Map<String, bool> selecionadosIniciais;
  final bool eraPersonalizado;

  const _DialogoEstruturaCategoria({
    required this.categoriaNome,
    required this.selecionadosIniciais,
    required this.eraPersonalizado,
  });

  @override
  State<_DialogoEstruturaCategoria> createState() => _DialogoEstruturaCategoriaState();
}

class _DialogoEstruturaCategoriaState extends State<_DialogoEstruturaCategoria> {
  late Map<String, bool> _selecionados;
  String? _preview;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _selecionados = Map.of(widget.selecionadosIniciais);
    _atualizarPreview();
  }

  Future<void> _atualizarPreview() async {
    try {
      final resultado = await supabase.rpc('compor_nome_produto', params: {
        'p_categoria': widget.categoriaNome,
        'p_nome_comercial': 'Nome Comercial',
        'p_tipo_produto': null,
        'p_dose': _selecionados['dose']! ? _exemploDe('dose') : null,
        'p_composicao': _selecionados['composicao']! ? _exemploDe('composicao') : null,
        'p_apresentacao': _selecionados['apresentacao']! ? _exemploDe('apresentacao') : null,
        'p_especie': _selecionados['especie']! ? _exemploDe('especie') : null,
        'p_fase': _selecionados['fase']! ? _exemploDe('fase') : null,
        'p_porte': _selecionados['porte']! ? _exemploDe('porte') : null,
        'p_sabor': _selecionados['sabor']! ? _exemploDe('sabor') : null,
        'p_peso': null,
        'p_volume': null,
        'p_fabricante': 'Fabricante',
      });
      if (!mounted) return;
      setState(() => _preview = resultado as String?);
    } catch (e) {
      debugPrint('Erro ao pré-visualizar estrutura de nome: $e');
    }
  }

  String _exemploDe(String campo) => _camposEstrutura.firstWhere((c) => c.campo == campo).exemplo;

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    try {
      final empresaId = context.read<AuthProvider>().empresaId;
      if (empresaId == null) return;

      final atuais = widget.selecionadosIniciais.entries.where((e) => e.value).map((e) => e.key).toSet();
      final novos = _selecionados.entries.where((e) => e.value).map((e) => e.key).toSet();
      final paraRemover = atuais.difference(novos);
      final paraAdicionar = novos.difference(atuais);

      // Categoria nunca personalizada antes (fallback "todos") mas o usuário
      // deixou tudo marcado: nada muda de fato, não precisa gravar linha
      // nenhuma — só grava quando o conjunto final é diferente do fallback.
      if (!widget.eraPersonalizado && paraRemover.isEmpty && novos.length == _camposEstrutura.length) {
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
      if (paraAdicionar.isNotEmpty) {
        await supabase.from('categoria_campos_estruturados').insert([
          for (final campo in paraAdicionar)
            {'empresa_id': empresaId, 'categoria': widget.categoriaNome, 'campo': campo},
        ]);
      }
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
        width: 400,
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
                'Prévia com valores de exemplo. Peso/volume aparecem sozinhos quando o '
                'produto tiver, não fazem parte desta configuração.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              for (final c in _camposEstrutura)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(rotulosCamposEstruturados[c.campo] ?? c.campo),
                  value: _selecionados[c.campo],
                  onChanged: (v) {
                    setState(() => _selecionados[c.campo] = v ?? false);
                    _atualizarPreview();
                  },
                ),
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
