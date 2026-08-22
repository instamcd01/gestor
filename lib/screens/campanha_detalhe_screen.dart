import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/campanha_ativacao.dart';
import '../providers/auth_provider.dart';
import '../repositories/campanha_ativacao_repository.dart';
import '../utils/planilha_utils.dart';
import '../utils/produto_validators.dart';
import '../utils/telefone_utils.dart';

String _formatarReais(double valor) => 'R\$ ${ProdutoValidators.formatarMoeda(valor)}';

/// Só pra exibição na lista — recebe o formato "com DDI" que o resto do
/// app usa internamente (ver normalizarTelefoneParaAuth) e devolve algo
/// legível tipo "+55 (21) 97150-9079".
String _formatarTelefoneExibicao(String digitos) {
  if (digitos.length < 12) return digitos;
  final ddi = digitos.substring(0, 2);
  final ddd = digitos.substring(2, 4);
  final resto = digitos.substring(4);
  if (resto.length == 9) return '+$ddi ($ddd) ${resto.substring(0, 5)}-${resto.substring(5)}';
  if (resto.length == 8) return '+$ddi ($ddd) ${resto.substring(0, 4)}-${resto.substring(4)}';
  return '+$ddi $ddd $resto';
}

const _aliasesContatos = {
  'telefone': ['telefone', 'celular', 'whatsapp', 'contato', 'fone', 'número', 'numero'],
  'nome': ['nome', 'nome no whatsapp', 'contato salvo como'],
  'origem': ['origem', 'plataforma', 'fonte'],
};

class CampanhaDetalheScreen extends StatefulWidget {
  final CampanhaAtivacao campanha;
  const CampanhaDetalheScreen({super.key, required this.campanha});

  @override
  State<CampanhaDetalheScreen> createState() => _CampanhaDetalheScreenState();
}

class _CampanhaDetalheScreenState extends State<CampanhaDetalheScreen> {
  bool _processando = false;
  late Future<MetricasCampanha> _futuroMetricas;
  late Future<List<ContatoCampanha>> _futuroContatos;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  void _carregar() {
    _futuroMetricas = CampanhaAtivacaoRepository().obterMetricas(widget.campanha.id);
    _futuroContatos = CampanhaAtivacaoRepository().listarContatos(widget.campanha.id);
  }

  Future<void> _recarregar() async {
    setState(_carregar);
    await Future.wait([_futuroMetricas, _futuroContatos]);
  }

  Future<void> _importarContatos() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (result == null || !mounted) return;

    setState(() => _processando = true);
    try {
      final bytesArquivo = result.files.single.bytes;
      if (bytesArquivo == null) throw StateError('Não foi possível ler o arquivo selecionado.');
      final excel = Excel.decodeBytes(corrigirNumFmtsInvalidos(bytesArquivo));

      Sheet? aba;
      MapaColunasPlanilha? mapa;
      for (final entry in excel.tables.entries) {
        if (entry.value.rows.isEmpty) continue;
        final m = MapaColunasPlanilha.deCabecalho(entry.value.rows.first, _aliasesContatos);
        if (m.indicePorCampo['telefone'] != null) {
          aba = entry.value;
          mapa = m;
          break;
        }
      }

      if (aba == null || mapa == null) {
        throw StateError('Não achei uma coluna de telefone reconhecível nessa planilha.');
      }

      final contatos = <({String telefone, String? nomeWhatsapp, String? origem})>[];
      final telefonesVistos = <String>{};
      var semTelefone = 0;
      var invalidos = 0;

      for (var i = 1; i < aba.rows.length; i++) {
        final row = aba.rows[i];
        final telefoneTexto = mapa.celula(row, 'telefone');
        if (telefoneTexto == null) {
          semTelefone++;
          continue;
        }
        final telefone = normalizarTelefoneParaAuth(telefoneTexto);
        if (telefone.length < 12 || telefone.length > 13) {
          invalidos++;
          continue;
        }
        if (!telefonesVistos.add(telefone)) continue; // duplicata na própria planilha, mantém a 1ª
        contatos.add((
          telefone: telefone,
          nomeWhatsapp: mapa.celula(row, 'nome'),
          origem: mapa.celula(row, 'origem'),
        ));
      }

      if (contatos.isEmpty) {
        throw StateError('Nenhum telefone válido reconhecido nessa planilha.');
      }

      if (!mounted) return;
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirmar importação de contatos'),
          content: Text(
            '${contatos.length} contato${contatos.length == 1 ? '' : 's'} pronto${contatos.length == 1 ? '' : 's'} pra entrar nessa campanha.'
            '${semTelefone > 0 ? '\n$semTelefone linha(s) ignorada(s) por falta de telefone.' : ''}'
            '${invalidos > 0 ? '\n$invalidos linha(s) com telefone inválido.' : ''}\n\n'
            'Isso só adiciona a lista de acompanhamento — não cria cadastro de cliente nenhum.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Importar')),
          ],
        ),
      );
      if (confirmado != true || !mounted) return;

      final empresaId = context.read<AuthProvider>().empresaId;
      if (empresaId == null) throw StateError('Empresa não identificada.');

      await CampanhaAtivacaoRepository().importarContatos(
        campanhaId: widget.campanha.id,
        empresaId: empresaId,
        contatos: contatos,
      );

      await _recarregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${contatos.length} contatos adicionados à campanha.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao importar: $e')));
      }
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.campanha.nome)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _processando ? null : _importarContatos,
        icon: const Icon(Icons.upload_file),
        label: const Text('Importar contatos'),
      ),
      body: RefreshIndicator(
        onRefresh: _recarregar,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FutureBuilder<MetricasCampanha>(
                future: _futuroMetricas,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return _PainelMetricas(m: snapshot.data!);
                },
              ),
              const SizedBox(height: 24),
              Text('Contatos', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              FutureBuilder<List<ContatoCampanha>>(
                future: _futuroContatos,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final contatos = snapshot.data!;
                  if (contatos.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Nenhum contato importado ainda — use o botão "Importar contatos".'),
                    );
                  }
                  return Column(
                    children: contatos.map((c) => _CartaoContato(c: c)).toList(),
                  );
                },
              ),
              const SizedBox(height: 80), // espaço pro FAB não cobrir o último item
            ],
          ),
        ),
      ),
    );
  }
}

class _PainelMetricas extends StatelessWidget {
  final MetricasCampanha m;
  const _PainelMetricas({required this.m});

  String _pct(int parte, int total) => total == 0 ? '—' : '${(parte / total * 100).toStringAsFixed(0)}%';

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _Metrica('Contatos', '${m.totalContatos}'),
        _Metrica('Ativaram', '${m.ativados} (${_pct(m.ativados, m.totalContatos)})'),
        _Metrica('Fizeram pedido', '${m.comPedido} (${_pct(m.comPedido, m.ativados)})'),
        _Metrica('Recompraram', '${m.recompraram}'),
        _Metrica('Valor gerado', _formatarReais(m.valorTotal)),
        _Metrica('Ticket médio', _formatarReais(m.ticketMedio)),
        _Metrica('Carrinho abandonado', '${m.carrinhoAbandonado}'),
        _Metrica('Favoritou sem comprar', '${m.favoritosSemCompra}'),
        _Metrica('Pedidos site × WhatsApp', '${m.pedidosSite} × ${m.pedidosWhatsapp}'),
      ],
    );
  }
}

class _Metrica extends StatelessWidget {
  final String rotulo;
  final String valor;
  const _Metrica(this.rotulo, this.valor);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rotulo, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(valor, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartaoContato extends StatelessWidget {
  final ContatoCampanha c;
  const _CartaoContato({required this.c});

  @override
  Widget build(BuildContext context) {
    final status = !c.ativou
        ? ('Não ativou', Colors.grey)
        : c.qtdPedidos == 0
            ? ('Ativou, sem pedido', Colors.orange)
            : ('Ativou — ${c.qtdPedidos} pedido${c.qtdPedidos == 1 ? '' : 's'}', Colors.green);

    return Card(
      child: ListTile(
        title: Text(c.nomeCliente ?? c.nomeWhatsapp ?? c.telefone),
        subtitle: Text('${_formatarTelefoneExibicao(c.telefone)}${c.origem != null ? ' — ${c.origem}' : ''}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(status.$1, style: TextStyle(color: status.$2, fontSize: 12, fontWeight: FontWeight.bold)),
            if (c.qtdPedidos > 0) Text(_formatarReais(c.valorGasto), style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
