import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/interrupcao_marketplace.dart';
import '../models/marketplace.dart';
import '../models/marketplace_config.dart';
import '../models/reconciliacao_historico.dart';
import '../providers/auth_provider.dart';
import '../providers/produto_provider.dart';
import '../repositories/interrupcao_marketplace_repository.dart';
import '../repositories/marketplace_config_repository.dart';
import '../repositories/reconciliacao_historico_repository.dart';
import '../widgets/marketplace_config_card.dart';
import 'historico_reconciliacao_screen.dart';

/// Tela dedicada da integração com o iFood — pausa/retomar loja, indicador
/// e histórico de reconciliação (estoque/financeiro), exportação de
/// catálogo e credenciais. Reúne num só lugar o que antes ficava espalhado
/// entre "Integrar Plataformas" e "Exportar Relatórios".
class IntegracaoIfoodScreen extends StatefulWidget {
  final Marketplace marketplace;

  const IntegracaoIfoodScreen({super.key, required this.marketplace});

  @override
  State<IntegracaoIfoodScreen> createState() => _IntegracaoIfoodScreenState();
}

class _IntegracaoIfoodScreenState extends State<IntegracaoIfoodScreen> {
  final _configRepository = MarketplaceConfigRepository();
  final _interrupcaoRepository = InterrupcaoMarketplaceRepository();
  final _historicoRepository = ReconciliacaoHistoricoRepository();

  static const _urlWebhookReconciliacao = 'https://n8n.lukz.com.br/webhook/ifood-reconciliacao-relatorios';

  MarketplaceConfig? _config;
  InterrupcaoMarketplace? _interrupcaoAtiva;
  bool _carregando = true;
  bool _exportando = false;
  bool _enviandoEstoque = false;
  bool _enviandoFinanceiro = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final configs = await _configRepository.listar();
      final interrupcao = await _interrupcaoRepository.buscarAtiva();
      if (mounted) {
        setState(() {
          _config = configs.where((c) => c.marketplaceId == widget.marketplace.id).firstOrNull ??
              MarketplaceConfig(marketplaceId: widget.marketplace.id);
          _interrupcaoAtiva = interrupcao;
          _carregando = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar integração iFood: $e');
      if (mounted) setState(() => _carregando = false);
    }
  }

  Duration _ateOFimDoDia() {
    final agora = DateTime.now();
    final fimDoDia = DateTime(agora.year, agora.month, agora.day, 23, 59);
    return fimDoDia.difference(agora);
  }

  Future<void> _pausarLoja() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;

    final motivoController = TextEditingController();
    Duration duracaoEscolhida = const Duration(hours: 1);

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Pausar loja no iFood'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: motivoController,
                decoration: const InputDecoration(labelText: 'Motivo (ex: acabou o estoque)'),
              ),
              const SizedBox(height: 16),
              const Text('Por quanto tempo?', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ('30 min', const Duration(minutes: 30)),
                  ('1 hora', const Duration(hours: 1)),
                  ('2 horas', const Duration(hours: 2)),
                  ('Resto do dia', null),
                ].map((opcao) {
                  final (rotulo, duracao) = opcao;
                  final selecionado = duracao == duracaoEscolhida ||
                      (duracao == null && duracaoEscolhida == _ateOFimDoDia());
                  return ChoiceChip(
                    label: Text(rotulo),
                    selected: selecionado,
                    onSelected: (_) => setDialogState(() => duracaoEscolhida = duracao ?? _ateOFimDoDia()),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Pausar')),
          ],
        ),
      ),
    );
    if (confirmado != true) return;
    final motivo = motivoController.text.trim().isEmpty ? 'Pausa manual' : motivoController.text.trim();

    try {
      await _interrupcaoRepository.pausar(
        empresaId: empresaId,
        marketplaceId: widget.marketplace.id,
        motivo: motivo,
        fim: DateTime.now().add(duracaoEscolhida),
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Loja pausada.')));
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível pausar a loja.')));
      }
    }
  }

  Future<void> _retomarLoja() async {
    final interrupcao = _interrupcaoAtiva;
    if (interrupcao == null) return;
    try {
      await _interrupcaoRepository.cancelar(interrupcao.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Loja reaberta.')));
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível reabrir a loja.')));
      }
    }
  }

  Widget _cardPausaLoja() {
    final interrupcao = _interrupcaoAtiva;
    final dateFormat = DateFormat('dd/MM HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: interrupcao == null
            ? Row(
                children: [
                  Icon(Icons.storefront, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Loja aberta no iFood')),
                  OutlinedButton(onPressed: _pausarLoja, child: const Text('Pausar loja')),
                ],
              )
            : Row(
                children: [
                  const Icon(Icons.pause_circle_outline, color: Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Loja pausada: ${interrupcao.motivo}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('Até ${dateFormat.format(interrupcao.fim)}',
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        if (interrupcao.status == 'erro' && interrupcao.erro != null)
                          Text(interrupcao.erro!, style: const TextStyle(fontSize: 12, color: Colors.red)),
                      ],
                    ),
                  ),
                  TextButton(onPressed: _retomarLoja, child: const Text('Retomar agora')),
                ],
              ),
      ),
    );
  }

  Widget _cardReconciliacao() {
    final config = _config;
    if (config == null || !config.ativo) return const SizedBox.shrink();

    final checkpoint = config.ultimaReconciliacaoEstoqueEm;
    final hoje = DateTime.now();
    final hojeSemHora = DateTime(hoje.year, hoje.month, hoje.day);
    final diasSemReconciliar =
        checkpoint == null ? null : hojeSemHora.difference(DateTime(checkpoint.year, checkpoint.month, checkpoint.day)).inDays;

    late final IconData icone;
    late final Color cor;
    late final String titulo;
    String? subtitulo;

    if (diasSemReconciliar == null) {
      icone = Icons.help_outline;
      cor = Colors.orange;
      titulo = 'Estoque do iFood nunca foi reconciliado';
      subtitulo = 'Peça pro Claude Code rodar a reconciliação de relatórios.';
    } else if (diasSemReconciliar <= 0) {
      icone = Icons.check_circle_outline;
      cor = Colors.green;
      titulo = 'Estoque do iFood reconciliado hoje';
    } else if (diasSemReconciliar == 1) {
      icone = Icons.schedule;
      cor = Colors.blueGrey;
      titulo = 'Aguardando reconciliação de hoje';
      subtitulo = 'Última reconciliação: ${DateFormat('dd/MM').format(checkpoint!)}';
    } else {
      icone = Icons.warning_amber_rounded;
      cor = Colors.red;
      titulo = '$diasSemReconciliar dias sem reconciliar o estoque do iFood';
      subtitulo = 'Última reconciliação: ${DateFormat('dd/MM').format(checkpoint!)}';
    }

    // Financeiro sempre fica de 2 a 3 dias atrás do estoque de propósito —
    // o relatório "Vendas e Pedidos" do iFood só fecha os valores em D+2, ver
    // memória do projeto. Só chama atenção se passar bem além disso.
    final checkpointFinanceiro = config.ultimaReconciliacaoFinanceiraEm;
    final diasSemFinanceiro = checkpointFinanceiro == null
        ? null
        : hojeSemHora.difference(DateTime(checkpointFinanceiro.year, checkpointFinanceiro.month, checkpointFinanceiro.day)).inDays;
    final financeiroAtrasado = diasSemFinanceiro != null && diasSemFinanceiro > 4;
    final subtituloFinanceiro = checkpointFinanceiro == null
        ? 'Financeiro: aguardando primeira conciliação'
        : 'Financeiro conciliado até ${DateFormat('dd/MM').format(checkpointFinanceiro)}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(icone, color: cor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (subtitulo != null)
                        Text(subtitulo, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      Text(
                        subtituloFinanceiro,
                        style: TextStyle(
                          fontSize: 12,
                          color: financeiroAtrasado ? Colors.red : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: financeiroAtrasado ? FontWeight.w600 : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.history),
            title: const Text('Ver histórico de reconciliação'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => HistoricoReconciliacaoScreen(marketplaceId: widget.marketplace.id, nomeMarketplace: 'iFood'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportarESalvar(Excel workbook, String nomeArquivo, String textoCompartilhar) async {
    final bytes = workbook.encode();
    if (bytes == null) throw Exception('Falha ao gerar a planilha.');
    await Share.shareXFiles(
      [
        XFile.fromData(
          Uint8List.fromList(bytes),
          name: nomeArquivo,
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ],
      text: textoCompartilhar,
    );
  }

  /// Gera a planilha no formato exato que o Portal do Parceiro iFood pede em
  /// Catálogo > Integração via planilha (colunas/ordem conferidas baixando o
  /// arquivo modelo real do portal em 06/09/2026 — não são inventadas).
  /// Preço/estoque/ativo já vêm do estado atual do Gestor, incluindo a baixa
  /// automática feita pela reconciliação de pedidos do iFood — o usuário só
  /// precisa fazer o upload manual dessa planilha no portal depois.
  Future<void> _exportarCatalogo() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    setState(() => _exportando = true);
    try {
      final provider = context.read<ProdutoProvider>();
      await provider.carregarProdutos();
      if (!mounted) return;

      // codigo_barras "0" é usado como placeholder pra produto sem EAN real
      // (ex: taxas de entrega cadastradas como produto) — nunca representa
      // certo no iFood (é indexado por EAN, então todos colidiriam no "0").
      final produtos = provider.produtos.where((p) {
        final ean = p.codigoBarras.trim();
        return ean.isNotEmpty && ean != '0';
      }).toList()
        ..sort((a, b) => a.nome.compareTo(b.nome));

      final workbook = Excel.createExcel();
      final sheet = workbook['Catálogo iFood'];
      workbook.delete('Sheet1');

      sheet.appendRow([
        TextCellValue('Código de Barras'),
        TextCellValue('Nome'),
        TextCellValue('Preço'),
        TextCellValue('Qtd. Atual Estoque'),
        TextCellValue('Ativo'),
        TextCellValue('Preço em Promoção'),
        TextCellValue('Múltiplo Ean Original'),
        TextCellValue('Código Plu'),
        TextCellValue('Quantidade Múltiplo'),
        TextCellValue('Canal'),
      ]);

      var semPrecoValido = 0;
      var ativosNoIfood = 0;
      for (final produto in produtos) {
        // Portal ignora linha com preço vazio/zerado, então nem vale incluir.
        final preco = produto.precoIfood ?? produto.preco;
        if (preco <= 0) {
          semPrecoValido++;
          continue;
        }
        final ativoNoIfood = produto.ativo && produto.exibirNoCatalogo && produto.estoqueAtual > 0;
        if (ativoNoIfood) ativosNoIfood++;
        // iFood rejeita a linha inteira se o preço promocional for maior ou
        // igual ao preço normal — ignorar em vez de deixar a linha falhar.
        final precoPromocionalValido =
            produto.precoPromocional != null && produto.precoPromocional! < preco ? produto.precoPromocional : null;
        sheet.appendRow([
          TextCellValue(produto.codigoBarras.trim()),
          TextCellValue(produto.nome),
          DoubleCellValue(preco),
          IntCellValue(produto.estoqueAtual),
          IntCellValue(ativoNoIfood ? 1 : 0),
          precoPromocionalValido != null ? DoubleCellValue(precoPromocionalValido) : TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue(''),
          TextCellValue('iFood App'),
        ]);
      }

      final incluidos = produtos.length - semPrecoValido;
      final mensagem = 'Catálogo exportado pro iFood: $incluidos produto(s), $ativosNoIfood ativo(s)'
          '${semPrecoValido > 0 ? ', $semPrecoValido sem preço válido ignorado(s)' : ''}.';

      await _exportarESalvar(
        workbook,
        'catalogo_ifood_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx',
        mensagem,
      );

      if (empresaId != null) {
        await _historicoRepository.registrar(
          empresaId: empresaId,
          marketplaceId: widget.marketplace.id,
          tipo: TipoReconciliacaoHistorico.catalogoExportado,
          detalhes: {'produtos_exportados': incluidos, 'produtos_ativos': ativosNoIfood},
          mensagem: mensagem,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao exportar catálogo: $e')));
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  /// Envia um relatório JSON (NDJSON — uma linha = um pedido/item) baixado
  /// manualmente do Portal do Parceiro pro mesmo webhook n8n que eu (Claude
  /// Code) chamava via curl — o backend já sabe casar produto por EAN, baixar
  /// estoque ou fechar financeiro, atualizar checkpoint (protegido por
  /// LEAST(), nunca avança além do que o iFood já liberou) e devolver a
  /// planilha de catálogo atualizada, pronta pra subir de volta no portal.
  Future<void> _enviarRelatorio({required bool financeiro}) async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || !mounted) return;

    final bytesArquivo = result.files.single.bytes;
    if (bytesArquivo == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível ler o arquivo selecionado.')));
      }
      return;
    }

    setState(() {
      if (financeiro) {
        _enviandoFinanceiro = true;
      } else {
        _enviandoEstoque = true;
      }
    });

    try {
      final linhas = utf8.decode(bytesArquivo).split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      if (linhas.isEmpty) {
        throw Exception('Arquivo vazio ou formato inválido.');
      }
      final registros = linhas.map((l) => jsonDecode(l) as Map<String, dynamic>).toList();

      final primeiro = registros.first;
      final ehORelatorioCerto = financeiro
          ? primeiro.containsKey('id_pedido_ifood') &&
              (primeiro.containsKey('valor_do_pedido') || primeiro.containsKey('status_pedido'))
          : primeiro.containsKey('id_pedido_ifood') && primeiro.containsKey('sku');
      if (!ehORelatorioCerto) {
        throw Exception('Esse arquivo não parece ser o relatório certo — selecionou o relatório errado?');
      }

      // periodo_ate vem do próprio conteúdo do arquivo (maior data entre as
      // linhas), não é digitado — o arquivo já diz qual período é.
      String? maiorData;
      for (final registro in registros) {
        final dt = financeiro ? registro['dt']?.toString() : (registro['dt_pedido'] ?? registro['dt'])?.toString();
        if (dt != null && (maiorData == null || dt.compareTo(maiorData) > 0)) {
          maiorData = dt;
        }
      }
      if (maiorData == null) {
        throw Exception('Não achei nenhuma data válida nesse arquivo.');
      }

      final corpo = financeiro
          ? {'empresa_id': empresaId, 'pedidos_relatorio': registros, 'periodo_ate_financeiro': maiorData}
          : {'empresa_id': empresaId, 'itens_relatorio': registros, 'periodo_ate_estoque': maiorData};

      final resposta = await http.post(
        Uri.parse(_urlWebhookReconciliacao),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(corpo),
      );

      if (resposta.statusCode != 200) {
        throw Exception('O servidor recusou o envio (${resposta.statusCode}). Tente de novo em instantes.');
      }

      final contentType = resposta.headers['content-type'] ?? '';
      if (!contentType.contains('spreadsheetml')) {
        final texto = utf8.decode(resposta.bodyBytes);
        throw Exception(texto.isEmpty ? 'Resposta inesperada do servidor.' : texto);
      }

      final mensagem = financeiro ? 'Financeiro conciliado até $maiorData.' : 'Estoque reconciliado até $maiorData.';
      await Share.shareXFiles(
        [
          XFile.fromData(
            resposta.bodyBytes,
            name: 'catalogo_ifood_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx',
            mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
        text: '$mensagem Catálogo atualizado em anexo, pronto pra subir no Portal do Parceiro.',
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));

      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao enviar relatório: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          if (financeiro) {
            _enviandoFinanceiro = false;
          } else {
            _enviandoEstoque = false;
          }
        });
      }
    }
  }

  Widget _cardEnviarRelatorio() {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: Text('Enviar relatório do iFood', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined, color: Colors.deepOrange),
            title: const Text('Itens por pedido (estoque)'),
            subtitle: const Text('Baixa o estoque dos pedidos concluídos'),
            trailing: _enviandoEstoque
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: _enviandoEstoque ? null : () => _enviarRelatorio(financeiro: false),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined, color: Colors.deepOrange),
            title: const Text('Vendas e Pedidos (financeiro)'),
            subtitle: const Text('Fecha o valor financeiro dos pedidos já com estoque baixado'),
            trailing: _enviandoFinanceiro
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: _enviandoFinanceiro ? null : () => _enviarRelatorio(financeiro: true),
          ),
        ],
      ),
    );
  }

  Future<void> _salvarConfig(MarketplaceConfig config) async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    try {
      await _configRepository.salvar(config, empresaId: empresaId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Configuração salva.')));
      await _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Integração iFood')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _cardPausaLoja(),
                _cardReconciliacao(),
                _cardEnviarRelatorio(),
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.storefront_outlined, color: Colors.deepOrange),
                    title: const Text('Exportar Catálogo iFood'),
                    subtitle: const Text('Preço, estoque e status atuais, já no formato pra importar no Portal do Parceiro'),
                    trailing: _exportando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download),
                    onTap: _exportando ? null : _exportarCatalogo,
                  ),
                ),
                MarketplaceConfigCard(
                  marketplace: widget.marketplace,
                  config: _config ?? MarketplaceConfig(marketplaceId: widget.marketplace.id),
                  onSalvar: _salvarConfig,
                ),
              ],
            ),
    );
  }
}
