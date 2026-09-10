import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/campanha_ativacao.dart';
import '../providers/auth_provider.dart';
import '../repositories/campanha_ativacao_repository.dart';
import '../utils/planilha_utils.dart';
import '../utils/produto_validators.dart';
import '../utils/telefone_utils.dart';
import '../widgets/aviso_banner.dart';
import '../widgets/estado_erro_lista.dart';

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

  // Mensagem única, editada uma vez só — ao selecionar um contato na lista
  // ela é reescrita com o nome+perfil dele (opcional: o usuário pode apagar
  // o nome se estiver salvo errado). Pedido do usuário: mais fácil ajustar
  // o texto de uma vez do que editar campo por campo em 269 contatos.
  final _mensagemController = TextEditingController();
  String? _contatoSelecionadoId;
  bool _primeiraSelecaoFeita = false;
  bool _esconderEnviados = false;

  // Cópia mutável da lista resolvida pelo FutureBuilder — necessária pra que
  // marcar "já enviei" num contato atualize o contador/filtro na hora, sem
  // esperar um pull-to-refresh (o Future em si só resolve uma vez).
  List<ContatoCampanha>? _contatosCache;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _mensagemController.dispose();
    super.dispose();
  }

  void _carregar() {
    _futuroMetricas = CampanhaAtivacaoRepository().obterMetricas(widget.campanha.id);
    _futuroContatos = CampanhaAtivacaoRepository().listarContatos(widget.campanha.id);
    _contatosCache = null;
    _primeiraSelecaoFeita = false;
  }

  Future<void> _marcarEnviado(ContatoCampanha c, bool enviado) async {
    await CampanhaAtivacaoRepository().marcarEnviado(c.contatoId, enviado);
    if (!mounted || _contatosCache == null) return;
    setState(() {
      final idx = _contatosCache!.indexWhere((x) => x.contatoId == c.contatoId);
      if (idx != -1) {
        _contatosCache![idx] = c.copyWith(enviadoEm: enviado ? DateTime.now() : null, limparEnviadoEm: !enviado);
      }
    });
  }

  Future<void> _recarregar() async {
    setState(_carregar);
    await Future.wait([_futuroMetricas, _futuroContatos]);
  }

  /// Troca de contato: se ainda não tem nada digitado, usa a sugestão
  /// completa (com o tom certo pro perfil). Se já tem um texto (editado ou
  /// não), só troca o nome na saudação inicial e preserva o resto — pedido
  /// do usuário: editar o corpo da mensagem uma vez e não perder o ajuste
  /// ao navegar entre contatos, só o nome deve mudar sozinho.
  void _selecionarContato(ContatoCampanha c) {
    setState(() {
      _contatoSelecionadoId = c.contatoId;
      final nome = c.nomeCliente ?? c.nomeWhatsapp;
      final textoAtual = _mensagemController.text;
      if (textoAtual.trim().isEmpty) {
        _mensagemController.text = _mensagemPadrao(nome: nome, perfil: c.perfil);
        return;
      }
      final novaSaudacao = _saudacao(nome);
      if (_regexSaudacao.hasMatch(textoAtual)) {
        _mensagemController.text = textoAtual.replaceFirst(_regexSaudacao, novaSaudacao);
      }
      // Se não achar a saudação no início (usuário apagou/reescreveu), não
      // mexe em nada — respeita a edição de quem tirou a saudação de propósito.
    });
  }

  /// Abre a lista de contatos por trás de um card de métrica (ex: "Ativaram",
  /// "Carrinho abandonado") — mesmo padrão de bottom sheet já usado em
  /// `HistoricoReconciliacaoScreen._abrirLista`. Filtra `_contatosCache` em
  /// memória (já carregado pra montar a lista principal da tela, não busca
  /// de novo no servidor). Tocar num contato da lista seleciona ele no
  /// painel de mensagem e fecha o sheet — mesmo fluxo de tocar direto no
  /// card do contato na lista de baixo.
  void _abrirListaMetrica({
    required String titulo,
    required bool Function(ContatoCampanha) filtro,
    required String Function(ContatoCampanha) subtitulo,
  }) {
    final todos = _contatosCache;
    if (todos == null) return;
    final itens = todos.where(filtro).toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('$titulo (${itens.length})', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ),
            const Divider(height: 1),
            Expanded(
              child: itens.isEmpty
                  ? const Center(child: Text('Nenhum contato nessa categoria.'))
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: itens.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final c = itens[index];
                        return ListTile(
                          title: Text(c.nomeCliente ?? c.nomeWhatsapp ?? c.telefone),
                          subtitle: Text(subtitulo(c)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.pop(ctx);
                            _selecionarContato(c);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Descarta o texto atual e volta pra sugestão padrão do perfil do contato
  /// selecionado — pra quando o usuário quer "recomeçar" com o tom sugerido
  /// em vez de manter o texto customizado anterior.
  void _restaurarSugestaoPadrao(ContatoCampanha c) {
    setState(() {
      _mensagemController.text = _mensagemPadrao(nome: c.nomeCliente ?? c.nomeWhatsapp, perfil: c.perfil);
    });
  }

  Future<void> _abrirWhatsApp(String telefone) async {
    final texto = Uri.encodeComponent(_mensagemController.text);
    // `wa.me` passa por um resolvedor de link antes de abrir o WhatsApp de
    // verdade, e esse resolvedor tem um bug conhecido com emoji fora do
    // plano básico (🐾🐶🐱 — os que essa campanha usa) que chegam como "?"
    // do outro lado. `whatsapp://send` abre o app direto, sem esse passo
    // intermediário — tenta esse primeiro, cai pro `wa.me` só se o
    // WhatsApp não estiver instalado (esquema `whatsapp://` não resolve
    // nesse caso).
    final uriApp = Uri.parse('whatsapp://send?phone=$telefone&text=$texto');
    final uriWeb = Uri.parse('https://wa.me/$telefone?text=$texto');
    if (await canLaunchUrl(uriApp)) {
      await launchUrl(uriApp, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(uriWeb)) {
      // Sem isso, em alguns aparelhos o link abre numa webview dentro do
      // próprio Gestor em vez de abrir o WhatsApp de verdade.
      await launchUrl(uriWeb, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível abrir o WhatsApp.')));
    }
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

  Future<void> _arquivarCampanha() async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arquivar campanha'),
        content: Text(
          'Arquivar "${widget.campanha.nome}"? Ela sai da lista principal, mas os contatos e o histórico '
          'continuam salvos — dá pra desarquivar depois em "Campanhas arquivadas".',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Arquivar')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    try {
      await CampanhaAtivacaoRepository().arquivar(widget.campanha.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível arquivar: $e')));
      }
    }
  }

  Future<void> _desarquivarCampanha() async {
    try {
      await CampanhaAtivacaoRepository().desarquivar(widget.campanha.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível desarquivar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final arquivada = widget.campanha.arquivada;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.campanha.nome),
        actions: [
          if (arquivada)
            IconButton(
              icon: const Icon(Icons.unarchive_outlined),
              tooltip: 'Desarquivar campanha',
              onPressed: _desarquivarCampanha,
            )
          else
            IconButton(
              icon: const Icon(Icons.archive_outlined),
              tooltip: 'Arquivar campanha',
              onPressed: _arquivarCampanha,
            ),
        ],
      ),
      floatingActionButton: arquivada
          ? null
          : FloatingActionButton.extended(
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
              if (arquivada) ...[
                const AvisoBanner(
                  texto: 'Campanha arquivada — desarquive pra importar novos contatos.',
                  tipo: TipoAviso.alerta,
                ),
                const SizedBox(height: 16),
              ],
              FutureBuilder<MetricasCampanha>(
                future: _futuroMetricas,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return EstadoErroLista(
                      mensagem: 'Não foi possível carregar as métricas: ${snapshot.error}',
                      onTentarNovamente: _recarregar,
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return _PainelMetricas(m: snapshot.data!, onAbrirLista: _abrirListaMetrica);
                },
              ),
              const SizedBox(height: 24),
              Text('Contatos', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              FutureBuilder<List<ContatoCampanha>>(
                future: _futuroContatos,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return EstadoErroLista(
                      mensagem: 'Não foi possível carregar os contatos: ${snapshot.error}',
                      onTentarNovamente: _recarregar,
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  // _contatosCache é a cópia mutável de verdade — só é
                  // (re)inicializada a partir do Future na primeira resolução
                  // (ou depois de um _recarregar, que zera o cache).
                  _contatosCache ??= List.of(snapshot.data!);
                  final contatos = _contatosCache!;
                  if (contatos.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Nenhum contato importado ainda — use o botão "Importar contatos".'),
                    );
                  }
                  // Seleciona automaticamente o 1º contato ainda pendente (não
                  // o primeiro da lista, que pode já ter sido marcado como
                  // enviado numa sessão anterior) — só na primeira carga, sem
                  // sobrescrever se o usuário já escolheu outro contato.
                  if (!_primeiraSelecaoFeita) {
                    _primeiraSelecaoFeita = true;
                    final pendentes = contatos.where((c) => !c.enviado);
                    final primeiro = pendentes.isNotEmpty ? pendentes.first : contatos.first;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _selecionarContato(primeiro);
                    });
                  }
                  ContatoCampanha? selecionado;
                  for (final c in contatos) {
                    if (c.contatoId == _contatoSelecionadoId) {
                      selecionado = c;
                      break;
                    }
                  }
                  final enviados = contatos.where((c) => c.enviado).length;
                  final contatosExibidos =
                      _esconderEnviados ? contatos.where((c) => !c.enviado).toList() : contatos;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PainelMensagem(
                        contato: selecionado,
                        controller: _mensagemController,
                        onEnviar: selecionado == null ? null : () => _abrirWhatsApp(selecionado!.telefone),
                        onRestaurarPadrao:
                            selecionado == null ? null : () => _restaurarSugestaoPadrao(selecionado!),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('$enviados de ${contatos.length} enviados', style: Theme.of(context).textTheme.bodyMedium),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Esconder enviados', style: TextStyle(fontSize: 13)),
                              Switch(
                                value: _esconderEnviados,
                                onChanged: (v) => setState(() => _esconderEnviados = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (contatosExibidos.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text('Todos os contatos já foram marcados como enviados 🎉')),
                        )
                      else
                        ...contatosExibidos.map((c) => _CartaoContato(
                              key: ValueKey(c.contatoId),
                              c: c,
                              selecionado: c.contatoId == _contatoSelecionadoId,
                              onSelecionar: () => _selecionarContato(c),
                              onMarcarEnviado: (enviado) => _marcarEnviado(c, enviado),
                            )),
                    ],
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

/// Assinatura de `_CampanhaDetalheScreenState._abrirListaMetrica` — extraída
/// aqui só pra dar nome ao tipo do callback que `_PainelMetricas` recebe.
typedef AbrirListaMetrica = void Function({
  required String titulo,
  required bool Function(ContatoCampanha) filtro,
  required String Function(ContatoCampanha) subtitulo,
});

class _PainelMetricas extends StatelessWidget {
  final MetricasCampanha m;
  final AbrirListaMetrica onAbrirLista;
  const _PainelMetricas({required this.m, required this.onAbrirLista});

  String _pct(int parte, int total) => total == 0 ? '—' : '${(parte / total * 100).toStringAsFixed(0)}%';

  String _subtituloPedidos(ContatoCampanha c) =>
      '${c.qtdPedidos} pedido(s) · ${_formatarReais(c.valorGasto)}';

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _Metrica('Contatos', '${m.totalContatos}'),
        _Metrica(
          'Ativaram',
          '${m.ativados} (${_pct(m.ativados, m.totalContatos)})',
          onTap: () => onAbrirLista(
            titulo: 'Ativaram',
            filtro: (c) => c.ativou,
            subtitulo: (c) => c.telefone,
          ),
        ),
        _Metrica(
          'Fizeram pedido',
          '${m.comPedido} (${_pct(m.comPedido, m.ativados)})',
          onTap: () => onAbrirLista(
            titulo: 'Fizeram pedido',
            filtro: (c) => c.qtdPedidos > 0,
            subtitulo: _subtituloPedidos,
          ),
        ),
        _Metrica(
          'Recompraram',
          '${m.recompraram}',
          onTap: () => onAbrirLista(
            titulo: 'Recompraram',
            filtro: (c) => c.qtdPedidos > 1,
            subtitulo: _subtituloPedidos,
          ),
        ),
        _Metrica('Valor gerado', _formatarReais(m.valorTotal)),
        _Metrica('Ticket médio', _formatarReais(m.ticketMedio)),
        _Metrica(
          'Carrinho abandonado',
          '${m.carrinhoAbandonado}',
          onTap: () => onAbrirLista(
            titulo: 'Carrinho abandonado',
            filtro: (c) => c.temCarrinhoAbandonado,
            subtitulo: (c) => c.telefone,
          ),
        ),
        _Metrica(
          'Favoritou sem comprar',
          '${m.favoritosSemCompra}',
          onTap: () => onAbrirLista(
            titulo: 'Favoritou sem comprar',
            filtro: (c) => c.temFavoritoSemCompra,
            subtitulo: (c) => c.telefone,
          ),
        ),
        _Metrica('Pedidos site × WhatsApp', '${m.pedidosSite} × ${m.pedidosWhatsapp}'),
      ],
    );
  }
}

class _Metrica extends StatelessWidget {
  final String rotulo;
  final String valor;
  final VoidCallback? onTap;
  const _Metrica(this.rotulo, this.valor, {this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(rotulo, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ),
                    if (onTap != null)
                      Icon(Icons.chevron_right, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ],
                ),
                const SizedBox(height: 4),
                Text(valor, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tags de perfil (vip/regular/inativo) — mesmo vocabulário de
/// `clientes.segmento`/`calcular_segmento_cliente()` no banco, reaproveitado
/// aqui pra contatos ainda sem cadastro real. Cor e rótulo só têm efeito
/// visual, não afetam nenhuma lógica de negócio.
(String, Color) _rotuloECorPerfil(String? perfil) {
  switch (perfil) {
    case 'vip':
      return ('VIP', Colors.amber.shade800);
    case 'inativo':
      return ('Inativo', Colors.grey.shade600);
    case 'regular':
      return ('Regular', Colors.blue.shade700);
    default:
      return ('', Colors.transparent);
  }
}

/// Saudação inicial ("Oi, Fulano!"/"Oi!") — extraída à parte porque também
/// é usada isoladamente pra trocar só o nome ao navegar entre contatos sem
/// perder o resto do texto que o usuário já editou (ver _selecionarContato).
String _saudacao(String? nome) {
  final partesNome = (nome ?? '').trim().split(RegExp(r'\s+'));
  final primeiroNome = partesNome.isEmpty || partesNome.first.isEmpty ? '' : partesNome.first;
  return primeiroNome.isEmpty ? 'Oi!' : 'Oi, $primeiroNome!';
}

/// Casa exatamente o formato gerado por [_saudacao], sempre no início do
/// texto — "Oi!" ou "Oi, Nome!" (nome sem vírgula/exclamação/quebra de linha).
final _regexSaudacao = RegExp(r'^(Oi!|Oi, [^\n!]+!)');

/// Mensagem inicial sugerida quando o contato ainda não tem um rascunho
/// salvo — varia por perfil porque quem já comprou bastante recentemente
/// (vip/regular) e quem sumiu há mais de 90 dias (inativo) merecem tom
/// diferente (ver discussão da migração Kyte: "sentimos sua falta" só faz
/// sentido pra quem realmente sumiu).
String _mensagemPadrao({required String? nome, required String? perfil}) {
  final saudacao = _saudacao(nome);
  switch (perfil) {
    case 'vip':
      return '$saudacao Aqui é da Delivery Pet 🐾 Você é um dos nossos clientes mais fiéis, por isso quero te contar '
          'em primeira mão: agora dá pra pedir pelo nosso site novo, com Pix e acompanhamento em tempo real: '
          'deliverypetexpress.com.br';
    case 'inativo':
      return '$saudacao Aqui é da Delivery Pet 🐾 Faz um tempinho que a gente não se fala! Ficamos com site novo, '
          'bem mais prático — catálogo completo, Pix e acompanhamento do pedido: deliverypetexpress.com.br '
          'Dá uma olhada quando puder 🐶🐱';
    default:
      return '$saudacao Aqui é da Delivery Pet 🐾 Agora você pode fazer seu pedido pelo nosso site novo, com Pix e '
          'acompanhamento em tempo real: deliverypetexpress.com.br';
  }
}

/// Painel fixo com a mensagem única (pedido do usuário: mais fácil ajustar
/// o texto de uma vez do que campo por campo em cada um dos 269 contatos).
/// Ao selecionar um contato na lista abaixo, o texto é reescrito com o
/// nome+perfil dele — o nome é só um ponto de partida editável, não uma
/// trava (existe contato com nome salvo errado no cadastro original).
class _PainelMensagem extends StatelessWidget {
  final ContatoCampanha? contato;
  final TextEditingController controller;
  final VoidCallback? onEnviar;
  final VoidCallback? onRestaurarPadrao;
  const _PainelMensagem({
    required this.contato,
    required this.controller,
    required this.onEnviar,
    required this.onRestaurarPadrao,
  });

  @override
  Widget build(BuildContext context) {
    final c = contato;
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    c == null
                        ? 'Selecione um contato na lista abaixo'
                        : 'Enviando para ${c.nomeCliente ?? c.nomeWhatsapp ?? c.telefone}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (onRestaurarPadrao != null)
                  TextButton.icon(
                    onPressed: onRestaurarPadrao,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Usar sugestão padrão', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              maxLines: 4,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: 'Mensagem pra enviar',
                border: OutlineInputBorder(),
                isDense: true,
                fillColor: Colors.white,
                filled: true,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onEnviar,
                icon: const Icon(Icons.chat, size: 18),
                label: const Text('Enviar no WhatsApp'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartaoContato extends StatefulWidget {
  final ContatoCampanha c;
  final bool selecionado;
  final VoidCallback onSelecionar;
  final Future<void> Function(bool enviado) onMarcarEnviado;
  const _CartaoContato({
    super.key,
    required this.c,
    required this.selecionado,
    required this.onSelecionar,
    required this.onMarcarEnviado,
  });

  @override
  State<_CartaoContato> createState() => _CartaoContatoState();
}

class _CartaoContatoState extends State<_CartaoContato> {
  bool _atualizandoEnviado = false;

  Future<void> _alternarEnviado(bool? valor) async {
    final novoValor = valor ?? false;
    setState(() => _atualizandoEnviado = true);
    try {
      await widget.onMarcarEnviado(novoValor);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível atualizar: $e')));
      }
    } finally {
      if (mounted) setState(() => _atualizandoEnviado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final enviado = c.enviado;
    final status = !c.ativou
        ? ('Não ativou', Colors.grey)
        : c.qtdPedidos == 0
            ? ('Ativou, sem pedido', Colors.orange)
            : ('Ativou — ${c.qtdPedidos} pedido${c.qtdPedidos == 1 ? '' : 's'}', Colors.green);
    final (rotuloPerfil, corPerfil) = _rotuloECorPerfil(c.perfil);

    return Card(
      shape: widget.selecionado
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
            )
          : null,
      child: InkWell(
        onTap: widget.onSelecionar,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Text(
                          c.nomeCliente ?? c.nomeWhatsapp ?? c.telefone,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            decoration: enviado ? TextDecoration.lineThrough : null,
                            color: enviado ? Theme.of(context).colorScheme.onSurfaceVariant : null,
                          ),
                        ),
                        if (rotuloPerfil.isNotEmpty)
                          Chip(
                            label: Text(rotuloPerfil, style: const TextStyle(fontSize: 11, color: Colors.white)),
                            backgroundColor: corPerfil,
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatarTelefoneExibicao(c.telefone)}${c.origem != null ? ' — ${c.origem}' : ''}',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    if (c.valorReferencia != null && c.valorReferencia! > 0)
                      Text(
                        'Gastou ${_formatarReais(c.valorReferencia!)} no histórico',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(status.$1, style: TextStyle(color: status.$2, fontSize: 12, fontWeight: FontWeight.bold)),
                  if (c.qtdPedidos > 0) Text(_formatarReais(c.valorGasto), style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  if (_atualizandoEnviado)
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Enviei', style: TextStyle(fontSize: 12)),
                        Checkbox(value: enviado, onChanged: _alternarEnviado, visualDensity: VisualDensity.compact),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
