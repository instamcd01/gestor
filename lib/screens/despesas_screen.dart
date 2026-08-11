import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/despesa.dart';
import '../models/fornecedor.dart';
import '../providers/auth_provider.dart';
import '../providers/despesa_provider.dart';
import '../providers/fornecedor_provider.dart';
import '../utils/cliente_validators.dart';
import '../utils/formatadores_input.dart';
import '../widgets/estado_erro_lista.dart';
import '../widgets/form_section.dart';

const _metodosPagamentoDespesa = ['Dinheiro', 'Pix', 'Transferência', 'Boleto', 'Cartão'];

/// Tela de Despesas — atende tanto "Contas a Pagar" (abre já filtrada em
/// pendentes) quanto "Saídas" (abre mostrando tudo) do menu de Finanças,
/// já que são a mesma tabela só com um recorte diferente.
class DespesasScreen extends StatefulWidget {
  final bool apenasPendentes;
  /// Abre já numa aba específica ('Pendentes'/'Atrasadas'/'Pagas') — usado
  /// pela tela de métricas pra levar direto pro recorte que foi tocado,
  /// sem precisar escolher o chip de novo. Tem prioridade sobre
  /// `apenasPendentes` quando os dois são passados.
  final String? filtroInicial;

  const DespesasScreen({super.key, this.apenasPendentes = false, this.filtroInicial});

  @override
  State<DespesasScreen> createState() => _DespesasScreenState();
}

class _DespesasScreenState extends State<DespesasScreen> {
  late String _filtro;

  @override
  void initState() {
    super.initState();
    _filtro = widget.filtroInicial ?? (widget.apenasPendentes ? 'Pendentes' : 'Todas');
    Provider.of<DespesaProvider>(context, listen: false).carregar();
  }

  List<Despesa> _aplicarFiltro(List<Despesa> despesas) {
    switch (_filtro) {
      case 'Pendentes':
        return despesas.where((d) => d.status == StatusDespesa.pendente).toList();
      case 'Atrasadas':
        return despesas.where((d) => d.atrasada).toList();
      case 'Pagas':
        return despesas.where((d) => d.paga).toList();
      default:
        return despesas;
    }
  }

  Future<void> _abrirFormulario({Despesa? despesa}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _DespesaFormScreen(despesa: despesa)),
    );
  }

  Future<void> _marcarComoPaga(Despesa despesa) async {
    String metodoSelecionado = _metodosPagamentoDespesa.first;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text('Marcar como paga'),
          content: DropdownButtonFormField<String>(
            initialValue: metodoSelecionado,
            decoration: const InputDecoration(labelText: 'Forma de pagamento'),
            items: _metodosPagamentoDespesa
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: (v) => setModalState(() => metodoSelecionado = v!),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
          ],
        ),
      ),
    );

    if (confirmou != true || !mounted) return;

    try {
      await context.read<DespesaProvider>().marcarComoPaga(despesa.id!, metodoPagamento: metodoSelecionado);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível marcar como paga: $e')));
    }
  }

  Future<void> _cancelar(Despesa despesa) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar despesa'),
        content: Text('Cancelar "${despesa.descricao}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancelar despesa')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    try {
      await context.read<DespesaProvider>().cancelar(despesa.id!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível cancelar: $e')));
    }
  }

  Color _corStatus(Despesa d) {
    if (d.cancelada) return Colors.grey;
    if (d.paga) return Colors.green;
    if (d.atrasada) return Colors.red;
    return Colors.orange;
  }

  String _rotuloStatus(Despesa d) {
    if (d.cancelada) return 'Cancelada';
    if (d.paga) return 'Paga';
    if (d.atrasada) return 'Atrasada';
    return 'Pendente';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DespesaProvider>();
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final dateFormat = DateFormat('dd/MM/yyyy');
    final despesas = _aplicarFiltro(provider.despesas);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.apenasPendentes ? 'Contas a Pagar' : 'Saídas'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: () => _abrirFormulario()),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['Todas', 'Pendentes', 'Atrasadas', 'Pagas'].map((rotulo) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(rotulo),
                      selected: _filtro == rotulo,
                      onSelected: (_) => setState(() => _filtro = rotulo),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          if (provider.carregando)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (provider.erro != null)
            Expanded(
              child: EstadoErroLista(mensagem: provider.erro!, onTentarNovamente: provider.carregar),
            )
          else if (despesas.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(height: 16),
                    Text(
                      'Nenhuma despesa encontrada.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: provider.carregar,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: despesas.length,
                  itemBuilder: (context, index) {
                    final despesa = despesas[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Row(
                          children: [
                            Flexible(child: Text(despesa.descricao, overflow: TextOverflow.ellipsis)),
                            if (despesa.recorrente) ...[
                              const SizedBox(width: 6),
                              Tooltip(
                                message: 'Recorrente — gera a próxima ocorrência sozinha todo mês',
                                child: Icon(Icons.autorenew, size: 14, color: Theme.of(context).colorScheme.primary),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${despesa.categoria}${despesa.fornecedor != null ? ' • ${despesa.fornecedor!.nome}' : ''}'),
                            Text('Vencimento: ${dateFormat.format(despesa.dataVencimento)}'),
                            if (despesa.codigoBarrasBoleto != null && despesa.codigoBarrasBoleto!.isNotEmpty)
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Boleto: ${despesa.codigoBarrasBoleto}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () {
                                      Clipboard.setData(ClipboardData(text: despesa.codigoBarrasBoleto!));
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(content: Text('Código de barras copiado.')));
                                    },
                                    child: const Icon(Icons.copy_outlined, size: 14),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(currencyFormat.format(despesa.valor), style: const TextStyle(fontWeight: FontWeight.bold)),
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _corStatus(despesa).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(_rotuloStatus(despesa),
                                  style: TextStyle(color: _corStatus(despesa), fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        onTap: () => showModalBottomSheet(
                          context: context,
                          builder: (ctx) => SafeArea(
                            child: Wrap(
                              children: [
                                if (despesa.status == StatusDespesa.pendente) ...[
                                  ListTile(
                                    leading: const Icon(Icons.check_circle_outline, color: Colors.green),
                                    title: const Text('Marcar como paga'),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _marcarComoPaga(despesa);
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.edit_outlined),
                                    title: const Text('Editar'),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _abrirFormulario(despesa: despesa);
                                    },
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.cancel_outlined, color: Colors.red),
                                    title: const Text('Cancelar despesa'),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _cancelar(despesa);
                                    },
                                  ),
                                ] else
                                  ListTile(
                                    leading: const Icon(Icons.visibility_outlined),
                                    title: const Text('Ver detalhes'),
                                    subtitle: despesa.paga ? Text('Pago via ${despesa.metodoPagamento ?? '-'}') : null,
                                    onTap: () => Navigator.pop(ctx),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DespesaFormScreen extends StatefulWidget {
  final Despesa? despesa;

  const _DespesaFormScreen({this.despesa});

  @override
  State<_DespesaFormScreen> createState() => _DespesaFormScreenState();
}

class _DespesaFormScreenState extends State<_DespesaFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _descricaoController;
  late final TextEditingController _valorController;
  late final TextEditingController _vencimentoController;
  late final TextEditingController _observacoesController;
  late final TextEditingController _codigoBarrasBoletoController;
  late final TextEditingController _recorrenciaDiaController;
  late bool _recorrente;
  late String _categoria;
  // Guardado por id, não pela instância de `Despesa.fornecedor` (essa vem
  // de uma consulta separada da lista usada no dropdown) — senão o
  // DropdownButtonFormField quebra ("There should be exactly one item
  // with [DropdownButton]'s value") por não achar objeto igual por
  // referência entre as duas listas.
  String? _fornecedorIdSelecionado;
  bool _salvando = false;

  bool get _editando => widget.despesa != null;

  @override
  void initState() {
    super.initState();
    final d = widget.despesa;
    _descricaoController = TextEditingController(text: d?.descricao ?? '');
    _valorController = TextEditingController(text: d != null ? ClienteValidators.formatarMoeda(d.valor) : '');
    _vencimentoController = TextEditingController(
      text: d != null ? DateFormatUtilsLocal.formatar(d.dataVencimento) : '',
    );
    _observacoesController = TextEditingController(text: d?.observacoes ?? '');
    _codigoBarrasBoletoController = TextEditingController(text: d?.codigoBarrasBoleto ?? '');
    _recorrente = d?.recorrente ?? false;
    _recorrenciaDiaController = TextEditingController(
      text: (d?.recorrenciaDia ?? d?.dataVencimento.day)?.toString() ?? '',
    );
    _categoria = d?.categoria ?? categoriasDespesaSugeridas.first;
    _fornecedorIdSelecionado = d?.fornecedor?.id;

    Provider.of<FornecedorProvider>(context, listen: false).carregar();
  }

  @override
  void dispose() {
    _descricaoController.dispose();
    _valorController.dispose();
    _vencimentoController.dispose();
    _observacoesController.dispose();
    _codigoBarrasBoletoController.dispose();
    _recorrenciaDiaController.dispose();
    super.dispose();
  }

  /// Sempre busca de novo na lista atual do provider em vez de guardar a
  /// instância — garante a mesma referência usada nos `items` do dropdown
  /// (ver comentário em `_fornecedorIdSelecionado`).
  Fornecedor? _resolverFornecedor(List<Fornecedor> fornecedores) {
    if (_fornecedorIdSelecionado == null) return null;
    for (final f in fornecedores) {
      if (f.id == _fornecedorIdSelecionado) return f;
    }
    return null;
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    final vencimento = DateFormatUtilsLocal.parsear(_vencimentoController.text);
    if (vencimento == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data de vencimento inválida.')));
      return;
    }

    setState(() => _salvando = true);

    final despesa = Despesa(
      id: widget.despesa?.id,
      fornecedor: _resolverFornecedor(context.read<FornecedorProvider>().fornecedores),
      descricao: _descricaoController.text.trim(),
      categoria: _categoria,
      valor: ClienteValidators.parseNumero(_valorController.text) ?? 0.0,
      dataVencimento: vencimento,
      dataPagamento: widget.despesa?.dataPagamento,
      status: widget.despesa?.status ?? StatusDespesa.pendente,
      metodoPagamento: widget.despesa?.metodoPagamento,
      observacoes: _observacoesController.text.trim(),
      codigoBarrasBoleto: _codigoBarrasBoletoController.text.trim().isEmpty ? null : _codigoBarrasBoletoController.text.trim(),
      recorrente: _recorrente,
      recorrenciaDia: _recorrente ? int.tryParse(_recorrenciaDiaController.text.trim()) : null,
    );

    try {
      final provider = context.read<DespesaProvider>();
      if (_editando) {
        await provider.atualizar(despesa);
      } else {
        final criadoPor = context.read<AuthProvider>().usuarioAtual?.id;
        await provider.adicionar(despesa, criadoPor: criadoPor);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar despesa: $e')));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fornecedorProvider = context.watch<FornecedorProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar Despesa' : 'Nova Despesa')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormSection(
                titulo: 'Dados da despesa',
                children: [
                  TextFormField(
                    controller: _descricaoController,
                    decoration: const InputDecoration(labelText: 'Descrição'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe a descrição' : null,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _categoria,
                    decoration: const InputDecoration(labelText: 'Categoria'),
                    items: categoriasDespesaSugeridas.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (v) => setState(() => _categoria = v!),
                  ),
                  // `DropdownButton` puro (não `...FormField`) de propósito:
                  // o `value` é recalculado a cada build a partir da lista
                  // atual do provider, então sempre bate com a mesma
                  // referência de objeto usada em `items` — um FormField
                  // guarda o `initialValue` só na primeira vez e não
                  // reage quando a lista de fornecedores termina de
                  // carregar depois, o que causava a tela vermelha.
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'Fornecedor (Opcional)'),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<Fornecedor?>(
                        isExpanded: true,
                        value: _resolverFornecedor(fornecedorProvider.fornecedores),
                        items: [
                          const DropdownMenuItem<Fornecedor?>(value: null, child: Text('Nenhum')),
                          ...fornecedorProvider.fornecedores.map((f) => DropdownMenuItem(
                                value: f,
                                child: Text(f.nome, overflow: TextOverflow.ellipsis),
                              )),
                        ],
                        onChanged: (v) => setState(() => _fornecedorIdSelecionado = v?.id),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _valorController,
                          decoration: const InputDecoration(labelText: 'Valor (R\$)', prefixText: 'R\$ '),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [MoedaInputFormatter()],
                          validator: (v) =>
                              (ClienteValidators.parseNumero(v) ?? 0) <= 0 ? 'Informe um valor válido' : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _vencimentoController,
                          decoration: const InputDecoration(labelText: 'Vencimento', hintText: 'DD/MM/AAAA'),
                          keyboardType: TextInputType.datetime,
                          inputFormatters: [DataInputFormatter()],
                          validator: (v) => DateFormatUtilsLocal.parsear(v) == null ? 'Data inválida' : null,
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Despesa recorrente'),
                    subtitle: const Text('Repete todo mês sozinha (ex: mensalidade, assinatura)'),
                    value: _recorrente,
                    onChanged: (v) => setState(() {
                      _recorrente = v;
                      if (v && _recorrenciaDiaController.text.trim().isEmpty) {
                        final vencimento = DateFormatUtilsLocal.parsear(_vencimentoController.text);
                        _recorrenciaDiaController.text = (vencimento?.day ?? DateTime.now().day).toString();
                      }
                    }),
                  ),
                  if (_recorrente)
                    TextFormField(
                      controller: _recorrenciaDiaController,
                      decoration: const InputDecoration(
                        labelText: 'Dia do mês da próxima ocorrência',
                        helperText: 'De 1 a 28 — evita ambiguidade em meses mais curtos',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final dia = int.tryParse(v?.trim() ?? '');
                        if (dia == null || dia < 1 || dia > 28) return 'Informe um dia entre 1 e 28';
                        return null;
                      },
                    ),
                  TextFormField(
                    controller: _codigoBarrasBoletoController,
                    decoration: const InputDecoration(
                      labelText: 'Código de barras do boleto (Opcional)',
                      helperText: 'Linha digitável, pra facilitar identificar/pagar depois',
                    ),
                  ),
                  TextFormField(
                    controller: _observacoesController,
                    decoration: const InputDecoration(labelText: 'Observações (Opcional)'),
                    maxLines: 3,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _salvando ? null : _salvar,
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                child: _salvando
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary))
                    : const Text('Salvar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pequeno helper local pra formatar/parsear DD/MM/AAAA sem depender de
/// nenhum validator específico de cliente/produto.
class DateFormatUtilsLocal {
  static String formatar(DateTime data) =>
      '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';

  static DateTime? parsear(String? texto) {
    if (texto == null) return null;
    final partes = texto.trim().split('/');
    if (partes.length != 3) return null;
    final dia = int.tryParse(partes[0]);
    final mes = int.tryParse(partes[1]);
    final ano = int.tryParse(partes[2]);
    if (dia == null || mes == null || ano == null) return null;
    try {
      final data = DateTime(ano, mes, dia);
      if (data.day != dia || data.month != mes || data.year != ano) return null;
      return data;
    } catch (_) {
      return null;
    }
  }
}
