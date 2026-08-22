import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/auth_provider.dart';
import '../providers/cliente_provider.dart';
import '../models/cliente.dart';
import '../repositories/cliente_repository.dart';
import '../utils/cliente_validators.dart';
import '../utils/planilha_utils.dart';
import '../utils/telefone_utils.dart';

/// Aliases de cabeçalho reconhecidos pra planilha de clientes — mesmo
/// espírito de [_aliasesProdutos] em importar_produtos_planilha.dart.
const _aliasesClientes = {
  'nome': ['nome', 'nome*', 'cliente'],
  'celular': ['celular', 'telefone', 'whatsapp', 'contato', 'fone'],
  'email': ['email', 'e-mail'],
  'cpf': ['cpf'],
  'endereco': ['endereço', 'endereco', 'rua'],
  'numero': ['número', 'numero', 'nº', 'n°'],
  'bairro': ['bairro'],
  'cidade': ['cidade'],
  'estado': ['estado', 'uf'],
  'cep': ['cep'],
  'complemento': ['complemento'],
  'aniversario': ['aniversário', 'aniversario', 'data de nascimento', 'nascimento'],
  'canal_origem': ['canal de origem', 'canal origem', 'origem'],
  'observacao': ['observação', 'observacao', 'obs'],
  'aceita_marketing': ['aceita marketing', 'marketing'],
  'saldo': ['saldo'],
};

/// Uma linha já interpretada da planilha, antes de virar [Cliente] de
/// verdade — guarda também o número da linha original (pra mensagens de
/// erro) e se ela vai virar cliente novo ou atualização de um existente.
class _LinhaImportada {
  final int numeroLinha;
  final Cliente cliente;
  final bool atualizacao;
  _LinhaImportada({required this.numeroLinha, required this.cliente, required this.atualizacao});
}


class ImportarClientesScreen extends StatefulWidget {
  const ImportarClientesScreen({super.key});

  @override
  State<ImportarClientesScreen> createState() => _ImportarClientesScreenState();
}

class _ImportarClientesScreenState extends State<ImportarClientesScreen> {
  bool _processando = false;

  Future<void> _iniciarImportacao() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (result == null || !mounted) return;

    setState(() => _processando = true);
    try {
      // `bytes` (não `path`) — no Web não existe caminho de arquivo real,
      // `withData: true` acima garante que o file_picker sempre traga os
      // bytes prontos, em qualquer plataforma.
      final bytesArquivo = result.files.single.bytes;
      if (bytesArquivo == null) throw StateError('Não foi possível ler o arquivo selecionado.');
      final bytesCorrigidos = corrigirNumFmtsInvalidos(bytesArquivo);
      final excel = Excel.decodeBytes(bytesCorrigidos);

      final clienteProvider = Provider.of<ClientProvider>(context, listen: false);
      await clienteProvider.carregarClientes();
      // Chave de correlação é o telefone normalizado — é a mesma que o
      // banco já usa (constraint UNIQUE(empresa_id, telefone)), diferente
      // de produtos onde o código de barras não é confiável como único.
      final existentesPorTelefone = <String, Cliente>{
        for (final c in clienteProvider.clientes)
          if (c.celular.isNotEmpty) normalizarTelefoneBr(c.celular): c,
      };

      // Primeira aba com "nome" e "celular" reconhecidos — diferente de
      // produtos, não há um padrão conhecido de múltiplas abas derivadas
      // pra planilha de clientes, então não precisa da mesma heurística.
      Sheet? abaClientes;
      MapaColunasPlanilha? mapaEncontrado;
      for (final entry in excel.tables.entries) {
        if (entry.value.rows.isEmpty) continue;
        final mapa = MapaColunasPlanilha.deCabecalho(entry.value.rows.first, _aliasesClientes);
        if (mapa.indicePorCampo['nome'] != null && mapa.indicePorCampo['celular'] != null) {
          abaClientes = entry.value;
          mapaEncontrado = mapa;
          break;
        }
      }

      final linhas = <_LinhaImportada>[];
      final linhasSemNome = <int>[];
      final linhasSemCelular = <int>[];
      final linhasCelularInvalido = <int>[];
      final linhasCelularDuplicado = <int>[];
      final telefonesNestaImportacao = <String>{};

      if (abaClientes != null && mapaEncontrado != null) {
        final mapa = mapaEncontrado;
        final rows = abaClientes.rows;

        for (var i = 1; i < rows.length; i++) {
          final row = rows[i];
          final numeroLinha = i + 1;

          final nome = mapa.celula(row, 'nome');
          if (nome == null) {
            linhasSemNome.add(numeroLinha);
            continue;
          }

          final celularTexto = mapa.celula(row, 'celular');
          if (celularTexto == null) {
            linhasSemCelular.add(numeroLinha);
            continue;
          }

          final celular = normalizarTelefoneBr(celularTexto);
          if (celular.length < 10 || celular.length > 11) {
            linhasCelularInvalido.add(numeroLinha);
            continue;
          }

          if (!existentesPorTelefone.containsKey(celular) && !telefonesNestaImportacao.add(celular)) {
            // Duas linhas desta mesma planilha com o mesmo celular e
            // nenhuma delas correspondendo a um cliente já cadastrado —
            // a segunda seria rejeitada pela constraint única do banco no
            // meio da importação. Mantém só a primeira ocorrência.
            linhasCelularDuplicado.add(numeroLinha);
            continue;
          }

          final existente = existentesPorTelefone[celular];

          // Todo campo abaixo preserva o valor já cadastrado quando a
          // célula da planilha está vazia — só sobrescreve quando a
          // planilha realmente traz um valor novo. "Segmento" (categoria
          // do cliente) nunca vem da planilha: é calculado pelo banco a
          // partir do comportamento de compra, não é algo pra importar.
          // "Saldo" só é aceito pra clientes novos — pra um já existente,
          // usar o valor da planilha geraria um "ajuste manual" de saldo
          // via trigger toda vez que a planilha reimportada estivesse
          // desatualizada (mesma classe de bug já corrigida na imagem dos
          // produtos: nunca deixar um snapshot antigo sobrescrever um
          // valor vivo/gerenciado pelo sistema).
          final cliente = Cliente(
            idCliente: existente?.idCliente,
            nome: nome,
            celular: celular,
            email: mapa.celula(row, 'email') ?? existente?.email ?? '',
            endereco: mapa.celula(row, 'endereco') ?? existente?.endereco ?? '',
            numero: mapa.celula(row, 'numero') ?? existente?.numero ?? '',
            bairro: mapa.celula(row, 'bairro') ?? existente?.bairro ?? '',
            cidade: mapa.celula(row, 'cidade') ?? existente?.cidade ?? '',
            estado: mapa.celula(row, 'estado') ?? existente?.estado ?? '',
            cep: mapa.celula(row, 'cep') ?? existente?.cep ?? '',
            complemento: mapa.celula(row, 'complemento') ?? existente?.complemento ?? '',
            cpf: mapa.celula(row, 'cpf') ?? existente?.cpf ?? '',
            observacao: mapa.celula(row, 'observacao') ?? existente?.observacao ?? '',
            saldo: existente?.saldo ?? (parseMoedaPlanilha(mapa.celula(row, 'saldo')) ?? 0.0),
            // Pets não fazem parte desta importação (planilha não carrega
            // esse dado) — preserva os que já existem em vez de apagá-los.
            // ClienteRepository.atualizar() sempre substitui a lista de
            // pets do cliente; se mandássemos vazia, apagaria os pets de
            // todo cliente já cadastrado a cada reimportação.
            pets: existente?.pets ?? [],
            aniversario: ClienteValidators.parseData(mapa.celula(row, 'aniversario')) ?? existente?.aniversario,
            canalOrigem: mapa.celula(row, 'canal_origem') ?? existente?.canalOrigem,
            aceitaMarketing: mapa.celula(row, 'aceita_marketing') != null
                ? parseBooleanoPlanilha(mapa.celula(row, 'aceita_marketing'), padrao: false)
                : existente?.aceitaMarketing,
            categoriaCliente: existente?.categoriaCliente,
            latitude: existente?.latitude,
            longitude: existente?.longitude,
            // Mesmo bug de "reconstruir sem listar tudo" que já foi achado
            // e corrigido em editar_cliente_screen.dart nesta sessão — mas
            // essa tela de importação nunca tinha sido tocada por aquele
            // fix. tipoPessoa/cnpj/razaoSocial têm valor padrão no
            // construtor ('fisica'/''/'') — sem isso, todo cliente PJ
            // reimportado pela planilha voltava a virar PF, apagando
            // CNPJ/razão social. aceitaLembreteWhatsapp também tem default
            // false — sem preservar, reimportar apagava o opt-in de
            // lembrete de recompra que o cliente já tinha dado.
            tipoPessoa: existente?.tipoPessoa ?? 'fisica',
            cnpj: existente?.cnpj ?? '',
            razaoSocial: existente?.razaoSocial ?? '',
            aceitaLembreteWhatsapp: existente?.aceitaLembreteWhatsapp ?? false,
            proximaVisita: existente?.proximaVisita,
            motivoUltimaVisita: existente?.motivoUltimaVisita,
            ultimoContato: existente?.ultimoContato,
            canalPreferido: existente?.canalPreferido,
            interesses: existente?.interesses,
            documentos: existente?.documentos,
            observacoesExtras: existente?.observacoesExtras,
            rangeDistancia: existente?.rangeDistancia,
            estimativaEntrega: existente?.estimativaEntrega,
            quantidadeCompras: existente?.quantidadeCompras,
            totalGasto: existente?.totalGasto,
            numeroCompras: existente?.numeroCompras,
            ultimaCompra: existente?.ultimaCompra,
            ticketMedio: existente?.ticketMedio,
            intervaloMedioRecompraDias: existente?.intervaloMedioRecompraDias,
          );

          linhas.add(_LinhaImportada(numeroLinha: numeroLinha, cliente: cliente, atualizacao: existente != null));
        }
      }

      if (!mounted) return;
      setState(() => _processando = false);

      if (linhas.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum cliente reconhecido nessa planilha.')),
        );
        return;
      }

      await _confirmarEExecutar(
        linhas,
        linhasSemNome,
        linhasSemCelular,
        linhasCelularInvalido,
        linhasCelularDuplicado,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _processando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao ler a planilha: $e')));
      }
    }
  }

  Future<void> _confirmarEExecutar(
    List<_LinhaImportada> linhas,
    List<int> linhasSemNome,
    List<int> linhasSemCelular,
    List<int> linhasCelularInvalido,
    List<int> linhasCelularDuplicado,
  ) async {
    final novos = linhas.where((l) => !l.atualizacao).length;
    final atualizacoes = linhas.where((l) => l.atualizacao).length;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar importação'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$novos cliente${novos == 1 ? '' : 's'} novo${novos == 1 ? '' : 's'}'),
            if (atualizacoes > 0)
              Text('$atualizacoes atualização${atualizacoes == 1 ? '' : 'ões'} (mesmo celular já cadastrado)'),
            if (linhasSemNome.isNotEmpty)
              Text('${linhasSemNome.length} linha(s) ignorada(s) por falta de nome',
                  style: const TextStyle(color: Colors.orange)),
            if (linhasSemCelular.isNotEmpty)
              Text('${linhasSemCelular.length} linha(s) ignorada(s) por falta de celular',
                  style: const TextStyle(color: Colors.orange)),
            if (linhasCelularInvalido.isNotEmpty)
              Text('${linhasCelularInvalido.length} linha(s) com celular inválido (precisa de DDD + número)',
                  style: const TextStyle(color: Colors.orange)),
            if (linhasCelularDuplicado.isNotEmpty)
              Text('${linhasCelularDuplicado.length} linha(s) ignorada(s) por celular repetido na própria planilha',
                  style: const TextStyle(color: Colors.orange)),
            const SizedBox(height: 12),
            Text('Exemplo (primeira linha): ${linhas.first.cliente.nome} — ${linhas.first.cliente.celular}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Importar')),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _processando = true);
    try {
      final clienteProvider = Provider.of<ClientProvider>(context, listen: false);
      final empresaId = context.read<AuthProvider>().empresaId;
      if (empresaId == null) throw StateError('Empresa não identificada.');

      var criados = 0;
      var atualizados = 0;
      // Volume de clientes é ordens de grandeza menor que o de produtos —
      // chamadas sequenciais (sem lote) são simples e rápidas o bastante.
      for (final l in linhas) {
        if (l.atualizacao) {
          await ClienteRepository().atualizar(l.cliente);
          atualizados++;
        } else {
          await ClienteRepository().criar(l.cliente, empresaId: empresaId);
          criados++;
        }
      }

      await clienteProvider.carregarClientes();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$criados clientes importados, $atualizados atualizados.'),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao importar: $e')));
      }
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  /// Gera uma planilha com os clientes atuais — serve tanto pra virar um
  /// backup/planilha mestre atualizada quanto, numa conta nova sem
  /// clientes ainda, como modelo em branco já com os cabeçalhos certos
  /// (não precisa de um gerador de modelo genérico separado).
  Future<void> _exportarClientesAtual() async {
    setState(() => _processando = true);
    try {
      final clienteProvider = Provider.of<ClientProvider>(context, listen: false);
      await clienteProvider.carregarClientes();
      final clientes = List<Cliente>.from(clienteProvider.clientes)..sort((a, b) => a.nome.compareTo(b.nome));

      final excel = Excel.createExcel();
      final Sheet sheet = excel['Clientes'];

      sheet.appendRow([
        TextCellValue('Nome'),
        TextCellValue('Celular'),
        TextCellValue('Email'),
        TextCellValue('CPF'),
        TextCellValue('Endereço'),
        TextCellValue('Número'),
        TextCellValue('Bairro'),
        TextCellValue('Cidade'),
        TextCellValue('Estado'),
        TextCellValue('CEP'),
        TextCellValue('Complemento'),
        TextCellValue('Aniversário'),
        TextCellValue('Canal de Origem'),
        TextCellValue('Observação'),
        TextCellValue('Aceita Marketing'),
        TextCellValue('Saldo'),
      ]);

      for (final c in clientes) {
        sheet.appendRow([
          TextCellValue(c.nome),
          TextCellValue(c.celular),
          TextCellValue(c.email),
          TextCellValue(c.cpf),
          TextCellValue(c.endereco),
          TextCellValue(c.numero),
          TextCellValue(c.bairro),
          TextCellValue(c.cidade),
          TextCellValue(c.estado),
          TextCellValue(c.cep),
          TextCellValue(c.complemento),
          TextCellValue(ClienteValidators.formatarData(c.aniversario)),
          TextCellValue(c.canalOrigem ?? ''),
          TextCellValue(c.observacao),
          TextCellValue((c.aceitaMarketing ?? false) ? 'Sim' : 'Não'),
          DoubleCellValue(c.saldo),
        ]);
      }

      final bytes = excel.encode() ?? [];

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(bytes),
              name: 'clientes_atuais.xlsx',
              mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ),
          ],
          text: 'Planilha com os ${clientes.length} clientes cadastrados.',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao exportar planilha: $e')));
      }
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Importar Clientes')),
      body: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Reconhece as colunas pelo nome do cabeçalho — não precisa reordenar nada. '
                    'Clientes já cadastrados são identificados pelo celular e atualizados; '
                    'pets não fazem parte desta importação, continuam sendo os mesmos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _processando ? null : _iniciarImportacao,
                    child: const Text('Importar Clientes da Planilha'),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: _processando ? null : _exportarClientesAtual,
                    child: const Text('Exportar Clientes Atuais'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Gera uma planilha com os clientes já cadastrados — serve de modelo pra '
                    'preencher (mesmos cabeçalhos) ou como backup.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          if (_processando) Container(color: Colors.black26, child: const Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }
}
