import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/cliente.dart';
import '../models/item_carrinho_cliente.dart';
import '../models/movimentacao_saldo.dart';
import '../models/venda.dart';
import '../providers/auth_provider.dart';
import '../providers/cliente_provider.dart';
import '../repositories/carrinho_cliente_repository.dart';
import '../repositories/cliente_repository.dart';
import '../repositories/saldo_repository.dart';
import '../repositories/venda_repository.dart';
import '../repositories/vinculo_cliente_repository.dart';
import '../utils/canal_venda_utils.dart';
import '../utils/cliente_validators.dart';
import '../utils/formatadores_input.dart';
import '../utils/telefone_utils.dart';
import '../widgets/categoria_cliente_badge.dart';
import '../widgets/form_section.dart';
import 'editar_cliente_screen.dart';
import 'venda_detalhes_screen.dart';

/// Abre o WhatsApp no telefone real do cliente (ver [Cliente.telefoneContato]).
/// Usado pela ficha e pelo atalho W da tabela de Clientes no PC.
Future<void> abrirWhatsAppDoCliente(Cliente cliente) async {
  final telefone = cliente.telefoneContato;
  if (normalizarTelefoneBr(telefone).isEmpty) return;
  final uri = Uri.parse(linkWhatsApp(telefone));
  if (await canLaunchUrl(uri)) {
    // Sem isso, em alguns aparelhos o link abre numa webview dentro do
    // próprio Gestor em vez de abrir o WhatsApp de verdade.
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class ClienteDetalhesScreen extends StatefulWidget {
  final Cliente cliente;

  /// true = painel ao lado da tabela de Clientes no PC: cabeçalho, números e
  /// abas, sem barra de título. Quem usa precisa dar uma `key` por cliente
  /// (as abas carregam os dados uma vez só, ao abrir).
  final bool embutida;

  /// Só no modo embutida: botão "Nova venda" (null esconde o botão).
  final VoidCallback? onNovaVenda;

  /// Só no modo embutida: o cadastro foi alterado, promovido ou excluído. A
  /// tela de fora recarrega a lista dela — no modo embutida não há rota pra
  /// fechar (`Navigator.pop` fecharia a tela de quem está em volta).
  final VoidCallback? onAlterado;

  const ClienteDetalhesScreen({
    super.key,
    required this.cliente,
    this.embutida = false,
    this.onNovaVenda,
    this.onAlterado,
  });

  @override
  State<ClienteDetalhesScreen> createState() => _ClienteDetalhesScreenState();
}

class _ClienteDetalhesScreenState extends State<ClienteDetalhesScreen> {
  bool _excluindo = false;
  bool _promovendoKyte = false;

  // Só no modo embutida (cabeçalho e título da aba Carrinho).
  Timer? _esperaPainel;
  int? _qtdCarrinho;
  bool _recebePush = false;

  @override
  void initState() {
    super.initState();
    final id = widget.cliente.idCliente;
    if (widget.embutida && id != null) {
      // Espera um instante: segurando ↑ ↓ na tabela, os clientes que só
      // passaram pela seleção não vão ao banco.
      _esperaPainel = Timer(const Duration(milliseconds: 300), () => _carregarResumoPainel(id));
    }
  }

  @override
  void dispose() {
    _esperaPainel?.cancel();
    super.dispose();
  }

  /// Só enfeite do painel (contagem e "recebe aviso"): se falhar, a ficha
  /// continua inteira e a aba Carrinho mostra o próprio erro.
  Future<void> _carregarResumoPainel(String id) async {
    try {
      final carrinho = await CarrinhoClienteRepository().consultar(id);
      if (mounted) setState(() => _qtdCarrinho = carrinho.itens.length);
    } catch (e) {
      debugPrint('Erro ao contar o carrinho do cliente: $e');
    }
    try {
      final recebe = await ClienteRepository().recebePush(id);
      if (mounted) setState(() => _recebePush = recebe);
    } catch (e) {
      debugPrint('Erro ao consultar aviso no celular do cliente: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Observa o provider pra refletir mudanças feitas em outro lugar do app
    // (ex: uma venda alterando saldo/total gasto) sem precisar reabrir a tela.
    final clientProvider = context.watch<ClientProvider>();
    final cliente = widget.cliente.idCliente != null
        ? clientProvider.clientes.firstWhere(
            (c) => c.idCliente == widget.cliente.idCliente,
            orElse: () => widget.cliente,
          )
        : widget.cliente;

    if (widget.embutida) return _buildEmbutida(context, cliente);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(cliente.nome),
          actions: [
            // Reforça na UI o que já é bloqueado no banco (trigger) —
            // vendedor não exclui cliente.
            if (context.watch<AuthProvider>().podeExcluir)
              IconButton(
                icon: _excluindo
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary),
                      )
                    : const Icon(Icons.delete),
                onPressed: _excluindo ? null : () => _confirmarDelecao(cliente),
              ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Dados'),
              Tab(text: 'Carrinho'),
              Tab(text: 'Compras'),
              Tab(text: 'Conta'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildDadosTab(context, cliente),
            _CarrinhoClienteTab(clienteId: cliente.idCliente ?? ''),
            _ComprasClienteTab(clienteId: cliente.idCliente),
            _ContaClienteTab(cliente: cliente),
          ],
        ),
      ),
    );
  }

  // ───────────────── modo embutida (painel do PC) ─────────────────

  Widget _buildEmbutida(BuildContext context, Cliente cliente) {
    final cores = Theme.of(context).colorScheme;
    final compras = cliente.quantidadeCompras ?? 0;

    return DefaultTabController(
      length: 4,
      child: Material(
        color: cores.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cabecalhoEmbutido(context, cliente),
            _acoesEmbutido(context, cliente),
            _numerosEmbutido(context, cliente),
            // Cores à mão: o tema da TabBar é feito pra ficar sobre a barra
            // colorida do topo e aqui o fundo é claro.
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: cores.primary,
              unselectedLabelColor: cores.onSurfaceVariant,
              indicatorColor: cores.primary,
              dividerColor: cores.outlineVariant,
              tabs: [
                const Tab(text: 'Dados'),
                Tab(text: _qtdCarrinho == null || _qtdCarrinho == 0 ? 'Carrinho' : 'Carrinho ($_qtdCarrinho)'),
                Tab(text: compras == 0 ? 'Compras' : 'Compras ($compras)'),
                const Tab(text: 'Conta'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _dadosEmbutido(context, cliente),
                  _CarrinhoClienteTab(
                    clienteId: cliente.idCliente ?? '',
                    onQuantidade: (n) {
                      if (mounted) setState(() => _qtdCarrinho = n);
                    },
                  ),
                  _ComprasClienteTab(clienteId: cliente.idCliente),
                  _ContaClienteTab(cliente: cliente),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cabecalhoEmbutido(BuildContext context, Cliente cliente) {
    final cores = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final origem = cliente.canalOrigem;
    final detalhes = [
      if (cliente.dataCadastro != null) 'Cliente desde ${DateFormat('MM/yyyy').format(cliente.dataCadastro!.toLocal())}',
      if (origem != null && origem.isNotEmpty) 'veio por: ${rotuloCanalVenda(origem)}',
      if (_recebePush) 'recebe aviso no celular',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: cores.primaryContainer,
            child: Text(
              cliente.nome.isNotEmpty ? cliente.nome[0].toUpperCase() : '?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: cores.onPrimaryContainer),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        cliente.nome,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CategoriaClienteBadge(categoria: cliente.categoriaCliente),
                  ],
                ),
                if (detalhes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(detalhes, style: TextStyle(fontSize: 12.5, color: cores.onSurfaceVariant)),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Mais ações',
            enabled: !_excluindo,
            onSelected: (acao) {
              switch (acao) {
                case 'editar':
                  _editarDados(cliente);
                case 'login':
                  _confirmarRedefinirAcesso(context, cliente);
                case 'excluir':
                  _confirmarDelecao(cliente);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'editar', child: Text('Editar dados')),
              if (cliente.authUserId != null)
                const PopupMenuItem(value: 'login', child: Text('Redefinir acesso ao login')),
              // Reforça na UI o que já é bloqueado no banco (trigger).
              if (auth.podeExcluir) const PopupMenuItem(value: 'excluir', child: Text('Excluir cliente')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _acoesEmbutido(BuildContext context, Cliente cliente) {
    final cores = Theme.of(context).colorScheme;
    final botao = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 34),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      textStyle: const TextStyle(fontSize: 13),
      visualDensity: VisualDensity.compact,
    );
    final temTelefone = normalizarTelefoneBr(cliente.telefoneContato).isNotEmpty;
    final temMapa = cliente.enderecoCompleto.isNotEmpty || cliente.latitude != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (temTelefone)
            OutlinedButton(
              style: botao.copyWith(foregroundColor: WidgetStatePropertyAll(cores.primary)),
              onPressed: () => abrirWhatsAppDoCliente(cliente),
              child: const Text('WhatsApp · W'),
            ),
          if (cliente.email.isNotEmpty)
            OutlinedButton(style: botao, onPressed: () => _enviarEmail(cliente.email), child: const Text('E-mail')),
          if (temMapa)
            OutlinedButton(
              style: botao,
              // Pino exato quando existe, igual à ficha do celular.
              onPressed: () => _abrirMapa(
                cliente.latitude != null && cliente.longitude != null
                    ? '${cliente.latitude},${cliente.longitude}'
                    : cliente.enderecoCompleto,
              ),
              child: const Text('Mapa'),
            ),
          if (widget.onNovaVenda != null)
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: widget.onNovaVenda,
              child: const Text('Nova venda · F2'),
            ),
        ],
      ),
    );
  }

  Widget _numerosEmbutido(BuildContext context, Cliente cliente) {
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final intervalo = cliente.intervaloMedioRecompraDias;
    final numeros = [
      ('Compras', '${cliente.quantidadeCompras ?? 0}'),
      ('Total gasto', moeda.format(cliente.totalGasto ?? 0)),
      ('Ticket médio', moeda.format(cliente.ticketMedio ?? 0)),
      ('Volta a cada', intervalo == null ? '—' : '${intervalo.toStringAsFixed(0)} dias'),
    ];
    final cores = Theme.of(context).colorScheme;
    Widget linha((String, String) n) => Row(
          children: [
            Flexible(
              child: Text(n.$1,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: cores.onSurfaceVariant)),
            ),
            const SizedBox(width: 6),
            Text(n.$2, maxLines: 1, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: LayoutBuilder(builder: (context, limites) {
        // Painel estreito (janela de ~1200 px): 4 cartões lado a lado cortariam
        // o valor em reais, e empilhados tirariam a altura das abas. Viram duas
        // linhas de texto, sem cartão.
        if (limites.maxWidth < 400) {
          return Column(
            children: [
              Row(children: [Expanded(child: linha(numeros[0])), const SizedBox(width: 12), Expanded(child: linha(numeros[1]))]),
              const SizedBox(height: 4),
              Row(children: [Expanded(child: linha(numeros[3])), const SizedBox(width: 12), Expanded(child: linha(numeros[2]))]),
            ],
          );
        }
        return Row(
          children: [
            for (final (i, n) in numeros.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: _cartaoNumero(context, n.$1, n.$2)),
            ],
          ],
        );
      }),
    );
  }

  Widget _cartaoNumero(BuildContext context, String rotulo, String valor) {
    final cores = Theme.of(context).colorScheme;
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        border: Border.all(color: cores.outlineVariant.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rotulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: cores.onSurfaceVariant)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(valor, maxLines: 1, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// Só mostra o que está preenchido (no celular aparece "Não informado").
  Widget _dadoEmbutido(BuildContext context, String rotulo, String? valor) {
    if (valor == null || valor.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(rotulo, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(valor, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _cartaoEmbutido(BuildContext context, String titulo, List<Widget> filhos) {
    final cores = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        border: Border.all(color: cores.outlineVariant.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              titulo.toUpperCase(),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: cores.onSurfaceVariant),
            ),
          ),
          ...filhos,
        ],
      ),
    );
  }

  Widget _dadosEmbutido(BuildContext context, Cliente cliente) {
    final cores = Theme.of(context).colorScheme;
    final data = DateFormat('dd/MM/yyyy');
    final telefone = cliente.telefoneContato;
    final entrega = [
      if (cliente.rangeDistancia != null) '${cliente.rangeDistancia!.toStringAsFixed(1).replaceAll('.', ',')} km',
      if (cliente.estimativaEntrega != null) '${cliente.estimativaEntrega} min',
    ].join(', ');
    final auth = context.watch<AuthProvider>();
    final ehKyte = cliente.canalOrigem == 'kyte_historico';
    final botao = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 34),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      textStyle: const TextStyle(fontSize: 13),
      visualDensity: VisualDensity.compact,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      children: [
        if (ehKyte || cliente.pessoaId != null || cliente.appUltimoUsoEm != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (ehKyte)
                  Chip(
                    avatar: const Icon(Icons.history, size: 16),
                    label: const Text('Histórico Kyte — cadastro sem login'),
                    backgroundColor: cores.tertiaryContainer,
                    visualDensity: VisualDensity.compact,
                  ),
                if (cliente.pessoaId != null)
                  Chip(
                    avatar: const Icon(Icons.link, size: 16),
                    label: const Text('Vinculado a outro cadastro'),
                    backgroundColor: cores.primaryContainer,
                    visualDensity: VisualDensity.compact,
                  ),
                if (cliente.appUltimoUsoEm != null)
                  Chip(
                    avatar: const Icon(Icons.phone_iphone, size: 16),
                    label: Text(
                      'Tem o app${cliente.appPlataforma == 'iphone' ? ' (iPhone)' : cliente.appPlataforma == 'android' ? ' (Android)' : ''}'
                      ' · último acesso ${DateFormat('dd/MM').format(cliente.appUltimoUsoEm!.toLocal())}',
                    ),
                    backgroundColor: cores.secondaryContainer,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        // Mesma regra da ficha do celular: só enquanto não houver vínculo.
        if (ehKyte && cliente.pessoaId == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                style: botao,
                onPressed: _promovendoKyte ? null : () => _promoverHistoricoKyte(cliente),
                icon: _promovendoKyte
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('Usar este cadastro'),
              ),
            ),
          ),
        _dadoEmbutido(context, 'Celular', telefone.isEmpty ? null : ClienteValidators.celularParaEdicao(telefone)),
        _dadoEmbutido(context, 'E-mail', cliente.email),
        if (cliente.tipoPessoa == 'juridica') ...[
          _dadoEmbutido(context, 'CNPJ', cliente.cnpj),
          _dadoEmbutido(context, 'Razão social', cliente.razaoSocial),
        ] else
          _dadoEmbutido(context, 'CPF', cliente.cpf),
        _dadoEmbutido(context, 'Endereço', cliente.enderecoExibicao),
        if (cliente.pontoAjustadoCliente)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Chip(
              avatar: const Icon(Icons.push_pin, size: 16),
              label: const Text('Ponto marcado pelo cliente no mapa — siga o pino'),
              visualDensity: VisualDensity.compact,
            ),
          ),
        _dadoEmbutido(context, 'Entrega', entrega),
        _dadoEmbutido(context, 'Aniversário', cliente.aniversario == null ? null : data.format(cliente.aniversario!)),
        _dadoEmbutido(context, 'Observação', cliente.observacao),
        _dadoEmbutido(context, 'Marketing', cliente.aceitaMarketing == true ? 'Aceita' : 'Não aceita'),
        _dadoEmbutido(context, 'Lembrete', cliente.aceitaLembreteWhatsapp ? 'Aceita lembrete de recompra (WhatsApp)' : 'Não aceita lembrete de recompra'),
        _cartaoEmbutido(context, 'Pets (${cliente.pets.length})', [
          if (cliente.pets.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('Nenhum pet registrado.', style: TextStyle(fontSize: 13, color: cores.onSurfaceVariant)),
            ),
          for (final pet in cliente.pets)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [pet.nome, pet.especie, pet.raca, pet.porte].where((s) => s.isNotEmpty).join(' · '),
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (pet.alergias.isNotEmpty)
                    Text('Alergias: ${pet.alergias}', style: TextStyle(fontSize: 12, color: cores.error)),
                ],
              ),
            ),
        ]),
        if (cliente.idCliente != null && auth.podeExcluir)
          _CadastrosVinculadosSection(
            key: ValueKey('${cliente.idCliente}-${cliente.pessoaId}'),
            cliente: cliente,
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(style: botao, onPressed: () => _editarDados(cliente), child: const Text('Editar dados')),
            if (cliente.authUserId != null)
              OutlinedButton(
                style: botao,
                onPressed: () => _confirmarRedefinirAcesso(context, cliente),
                child: const Text('Redefinir acesso ao login'),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _editarDados(Cliente cliente) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditarClienteScreen(clienteSelecionado: cliente)),
    );
    // EditarClienteScreen já atualiza o ClientProvider; o cadastro do Kyte não
    // mora nele, então a lista de fora é que precisa recarregar.
    if (mounted) widget.onAlterado?.call();
  }

  // ───────────────── ficha de sempre (celular) ─────────────────

  Widget _buildDadosTab(BuildContext context, Cliente cliente) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Center(
          child: CircleAvatar(
            radius: 40,
            backgroundColor: colorScheme.primaryContainer,
            child: Text(
              cliente.nome.isNotEmpty ? cliente.nome[0].toUpperCase() : '?',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: colorScheme.onPrimaryContainer),
            ),
          ),
        ),
        if (cliente.canalOrigem == 'kyte_historico')
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: Chip(
                avatar: const Icon(Icons.history, size: 16),
                label: const Text('Histórico Kyte — cadastro sem login'),
                backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
              ),
            ),
          ),
        // Só oferece o atalho enquanto não tiver vínculo aprovado ainda —
        // depois de vinculado já existe um cadastro real pra usar direto.
        // "Promove" a própria linha (telefone_kyte -> telefone) em vez de
        // criar um cadastro novo: mantém o histórico de pedidos já
        // vinculado a esse id e evita duplicar ficha + gerar sugestão de
        // vínculo pra revisar depois (ver [[gestor_vinculo_cliente_cross_canal]]).
        if (cliente.canalOrigem == 'kyte_historico' && cliente.pessoaId == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: _promovendoKyte ? null : () => _promoverHistoricoKyte(cliente),
                icon: _promovendoKyte
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('Usar este cadastro'),
              ),
            ),
          ),
        if (cliente.pessoaId != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: Chip(
                avatar: const Icon(Icons.link, size: 16),
                label: const Text('Vinculado a outro cadastro — histórico consolidado'),
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              ),
            ),
          ),
        if (cliente.appUltimoUsoEm != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: Chip(
                avatar: const Icon(Icons.phone_iphone, size: 16),
                label: Text(
                  'Tem o app${cliente.appPlataforma == 'iphone' ? ' (iPhone)' : cliente.appPlataforma == 'android' ? ' (Android)' : ''}'
                  ' · último acesso ${DateFormat('dd/MM').format(cliente.appUltimoUsoEm!.toLocal())}',
                ),
                backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              ),
            ),
          ),
        if (cliente.idCliente != null && context.watch<AuthProvider>().podeExcluir)
          _CadastrosVinculadosSection(
            // Recria a seção quando o vínculo muda (provider recarregado),
            // senão ela ficava com o grupo antigo em memória.
            key: ValueKey('${cliente.idCliente}-${cliente.pessoaId}'),
            cliente: cliente,
          ),
        const SizedBox(height: 8),
        Center(child: CategoriaClienteBadge(categoria: cliente.categoriaCliente)),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (cliente.celular.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.message, color: Colors.green),
                tooltip: 'Abrir WhatsApp',
                onPressed: () => _abrirWhatsApp(cliente.telefoneKyte ?? cliente.celular),
              ),
            if (cliente.email.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.email, color: Colors.blue),
                tooltip: 'Enviar e-mail',
                onPressed: () => _enviarEmail(cliente.email),
              ),
            if (cliente.enderecoCompleto.isNotEmpty || cliente.latitude != null)
              IconButton(
                icon: const Icon(Icons.location_on, color: Colors.red),
                tooltip: 'Abrir no mapa',
                // Pino exato quando existe (principalmente se o cliente
                // ajustou no mapa) — o texto pode apontar pra outro ponto.
                onPressed: () => _abrirMapa(
                  cliente.latitude != null && cliente.longitude != null
                      ? '${cliente.latitude},${cliente.longitude}'
                      : cliente.enderecoCompleto,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        FormSection(
          titulo: 'Contato',
          children: [
            _buildClienteInfo('Celular/WhatsApp', cliente.celular),
            _buildClienteInfo('E-mail', cliente.email),
            if (cliente.tipoPessoa == 'juridica') ...[
              _buildClienteInfo('CNPJ', cliente.cnpj),
              _buildClienteInfo('Razão social', cliente.razaoSocial),
            ] else
              _buildClienteInfo('CPF', cliente.cpf),
            _buildClienteInfo('Endereço', cliente.enderecoCompleto),
            if (cliente.pontoAjustadoCliente)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Chip(
                  avatar: const Icon(Icons.push_pin, size: 18),
                  label: const Text('Ponto marcado pelo cliente no mapa — siga o pino'),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            _buildClienteInfo('Complemento', cliente.complemento),
            _buildClienteInfo('Distância',
                cliente.rangeDistancia != null ? '${cliente.rangeDistancia!.toStringAsFixed(2)} km' : 'Não informado'),
            _buildClienteInfo('Estimativa de entrega',
                cliente.estimativaEntrega != null ? '${cliente.estimativaEntrega} min' : 'Não informado'),
          ],
        ),
        const SizedBox(height: 16),

        FormSection(
          titulo: 'Preferências',
          children: [
            _buildClienteInfo('Observação', cliente.observacao),
            _buildClienteInfo('Canal de Origem', cliente.canalOrigem ?? 'Não informado'),
            _buildClienteInfo('Aniversário',
                cliente.aniversario != null ? dateFormat.format(cliente.aniversario!) : 'Não informado'),
            _buildClienteInfo('Aceita Marketing?', cliente.aceitaMarketing == true ? 'Sim' : 'Não'),
            _buildClienteInfo(
              'Aceita lembrete de recompra (WhatsApp)?',
              cliente.aceitaLembreteWhatsapp ? 'Sim' : 'Não',
            ),
          ],
        ),
        const SizedBox(height: 16),

        FormSection(
          titulo: 'Resumo de compras',
          children: [
            _buildClienteInfo('Cliente desde',
                cliente.dataCadastro != null ? dateFormat.format(cliente.dataCadastro!) : 'Não informado'),
            _buildClienteInfo('Compras Realizadas', cliente.quantidadeCompras?.toString() ?? '0'),
            _buildClienteInfo('Total Gasto', 'R\$ ${(cliente.totalGasto ?? 0).toStringAsFixed(2)}'),
            _buildClienteInfo('Ticket Médio', 'R\$ ${(cliente.ticketMedio ?? 0).toStringAsFixed(2)}'),
            if (cliente.intervaloMedioRecompraDias != null)
              _buildClienteInfo(
                'Intervalo Médio Entre Pedidos',
                '${cliente.intervaloMedioRecompraDias!.toStringAsFixed(0)} dias',
              ),
          ],
        ),
        const SizedBox(height: 16),

        FormSection(
          titulo: 'Pets',
          children: [
            if (cliente.pets.isEmpty)
              Text('Nenhum pet registrado.', style: TextStyle(color: colorScheme.onSurfaceVariant))
            else
              Column(children: cliente.pets.map((pet) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: pet.imagemUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: pet.imagemUrl,
                                fit: BoxFit.cover,
                                errorWidget: (context, url, error) => Container(
                                  color: colorScheme.surfaceContainerHighest,
                                  child: Icon(Icons.pets, color: colorScheme.onSurfaceVariant),
                                ),
                              )
                            : Container(
                                color: colorScheme.surfaceContainerHighest,
                                child: Icon(Icons.pets, color: colorScheme.onSurfaceVariant),
                              ),
                      ),
                    ),
                    title: Text(pet.nome),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${pet.especie} - ${pet.raca}${pet.porte.isNotEmpty ? ' • ${pet.porte}' : ''}'),
                        if (pet.alergias.isNotEmpty)
                          Text(
                            'Alergias: ${pet.alergias}',
                            style: TextStyle(color: Colors.red[700], fontSize: 12),
                          ),
                      ],
                    ),
                  )).toList()),
          ],
        ),
        const SizedBox(height: 24),

        ElevatedButton(
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EditarClienteScreen(clienteSelecionado: cliente),
              ),
            );
            // EditarClienteScreen já atualiza o ClientProvider antes de
            // voltar — o watch() no build cuida do resto.
          },
          style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
          child: const Text('Editar Dados'),
        ),

        // Só faz sentido pra cliente que já logou alguma vez (authUserId
        // != null) — editar o telefone sozinho não reconecta o login, ver
        // ClienteRepository.redefinirAcesso.
        if (cliente.authUserId != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _confirmarRedefinirAcesso(context, cliente),
            icon: const Icon(Icons.link_off),
            label: const Text('Redefinir acesso ao login'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmarRedefinirAcesso(BuildContext context, Cliente cliente) async {
    final formKey = GlobalKey<FormState>();
    // Pré-preenche já mascarado, a partir só dos dígitos (sem o DDI 55, se
    // houver) — o telefone salvo pode estar em formatos diferentes
    // dependendo de como o cliente entrou (site vs cadastro manual no
    // app), e o TelefoneInputFormatter só entende DDD+número puro.
    final digitosAtuais = normalizarTelefoneBr(cliente.celular);
    final telefoneController = TextEditingController(
      text: TelefoneInputFormatter()
          .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: digitosAtuais))
          .text,
    );

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Redefinir acesso ao login'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Use isso quando o cliente perdeu o telefone antigo e não '
                'consegue mais receber o código de verificação. Confirme o '
                'número atual dele abaixo — o histórico de pedidos, saldo '
                'e endereço continuam os mesmos, nada é apagado.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: telefoneController,
                decoration: const InputDecoration(labelText: 'Telefone atual'),
                keyboardType: TextInputType.phone,
                inputFormatters: [TelefoneInputFormatter()],
                validator: ClienteValidators.celular,
                autofocus: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Redefinir'),
          ),
        ],
      ),
    );

    if (confirmou != true || !context.mounted) {
      telefoneController.dispose();
      return;
    }
    final novoTelefone = telefoneController.text;
    telefoneController.dispose();

    try {
      await context.read<ClientProvider>().redefinirAcesso(cliente.idCliente!, novoTelefone: novoTelefone);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Acesso redefinido — o cliente já pode entrar com o telefone atual.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível redefinir: $e')),
      );
    }
  }

  Future<void> _promoverHistoricoKyte(Cliente cliente) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usar este cadastro'),
        content: Text(
          'O telefone ${cliente.telefoneKyte ?? ''} vira o telefone oficial desse cadastro e ele passa a '
          'aparecer na lista normal de clientes, pronto pra usar numa venda. O histórico de pedidos continua o mesmo.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    setState(() => _promovendoKyte = true);
    try {
      await ClienteRepository().promoverHistoricoKyte(cliente.idCliente!);
      if (!mounted) return;
      await context.read<ClientProvider>().carregarClientes();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cadastro liberado — já aparece na lista normal de clientes.')),
      );
      if (widget.embutida) {
        setState(() => _promovendoKyte = false);
        widget.onAlterado?.call();
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _promovendoKyte = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível usar esse cadastro: $e')),
      );
    }
  }

  Widget _buildClienteInfo(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value?.isNotEmpty == true ? value! : 'Não informado',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarDelecao(Cliente cliente) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text(
          cliente.saldo > 0
              ? 'Tem certeza de que deseja excluir este cliente? Ele ainda tem R\$ ${cliente.saldo.toStringAsFixed(2)} de saldo — esse valor deixará de ser rastreado.'
              : 'Tem certeza de que deseja excluir este cliente?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );

    if (confirmou != true || !mounted) return;

    final clientProvider = Provider.of<ClientProvider>(context, listen: false);
    setState(() => _excluindo = true);
    try {
      // Pega antes: no painel, a exclusão fecha este widget (a linha some).
      final aoAlterar = widget.onAlterado;
      final embutida = widget.embutida;
      await clientProvider.removerClienteDoFirestore(cliente);
      if (embutida) {
        aoAlterar?.call();
        if (mounted) setState(() => _excluindo = false);
        return;
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _excluindo = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível excluir o cliente: $e')),
      );
    }
  }

  Future<void> _abrirWhatsApp(String numero) async {
    if (normalizarTelefoneBr(numero).isEmpty) return;
    final uri = Uri.parse(linkWhatsApp(numero));
    if (await canLaunchUrl(uri)) {
      // Sem isso, em alguns aparelhos o link abre numa webview dentro do
      // próprio Gestor em vez de abrir o WhatsApp de verdade.
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _enviarEmail(String email) async {
    if (email.isEmpty) return;
    final uri = Uri(scheme: 'mailto', path: email);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _abrirMapa(String endereco) async {
    if (endereco.isEmpty) return;
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(endereco)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}

/// Aba "Carrinho": o carrinho ATIVO real desse cliente — o mesmo que o
/// agente de WhatsApp e o site usam (tabela `carrinho`/`carrinho_itens`
/// compartilhada). Permite ver e remover item na mão, útil quando o bot
/// trava numa operação ou quando o dono assume um atendimento.
class _CarrinhoClienteTab extends StatefulWidget {
  final String clienteId;

  /// Avisa quantos itens há no carrinho (título da aba no painel do PC).
  final ValueChanged<int>? onQuantidade;

  const _CarrinhoClienteTab({required this.clienteId, this.onQuantidade});

  @override
  State<_CarrinhoClienteTab> createState() => _CarrinhoClienteTabState();
}

class _CarrinhoClienteTabState extends State<_CarrinhoClienteTab> {
  final _repository = CarrinhoClienteRepository();
  late Future<CarrinhoCliente> _futureCarrinho;
  String? _removendoProdutoId;

  @override
  void initState() {
    super.initState();
    _futureCarrinho = _carregar();
  }

  Future<CarrinhoCliente> _carregar() {
    if (widget.clienteId.isEmpty) {
      return Future.value(CarrinhoCliente(itens: [], valorTotal: 0));
    }
    return _repository.consultar(widget.clienteId).then((carrinho) {
      widget.onQuantidade?.call(carrinho.itens.length);
      return carrinho;
    });
  }

  Future<void> _recarregar() async {
    setState(() {
      _futureCarrinho = _carregar();
    });
    await _futureCarrinho;
  }

  Future<void> _removerItem(ItemCarrinhoCliente item) async {
    setState(() => _removendoProdutoId = item.produtoId);
    try {
      final novoCarrinho = await _repository.removerItem(
        widget.clienteId,
        produtoId: item.produtoId,
      );
      widget.onQuantidade?.call(novoCarrinho.itens.length);
      setState(() {
        _futureCarrinho = Future.value(novoCarrinho);
        _removendoProdutoId = null;
      });
    } catch (e) {
      setState(() => _removendoProdutoId = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível remover: $e')),
        );
      }
    }
  }

  /// "Criado em dd/MM HH:mm" e, se a última alteração for depois da
  /// criação (cliente mexeu no carrinho mais de uma vez), acrescenta
  /// "última alteração dd/MM HH:mm" também.
  String _formatarTimestamps(CarrinhoCliente carrinho) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final criado = carrinho.criadoEm;
    if (criado == null) return '';
    // Vem do banco em UTC — sem .toLocal(), mostrava a hora adiantada em 3h
    // (bug real 10/09, mesmo padrão já usado em notificacoes_screen.dart).
    final criadoLocal = criado.toLocal();
    final texto = StringBuffer('Criado em ${dateFormat.format(criadoLocal)}');
    final atualizado = carrinho.atualizadoEm;
    if (atualizado != null && atualizado.difference(criado).inMinutes.abs() >= 1) {
      texto.write(' • última alteração ${dateFormat.format(atualizado.toLocal())}');
    }
    return texto.toString();
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return FutureBuilder<CarrinhoCliente>(
      future: _futureCarrinho,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro ao carregar carrinho: ${snapshot.error}'));
        }
        final carrinho = snapshot.data!;
        if (carrinho.vazio) {
          return RefreshIndicator(
            onRefresh: _recarregar,
            child: ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Center(child: Text('Nenhum item no carrinho no momento.')),
                ),
              ],
            ),
          );
        }
        final timestamps = _formatarTimestamps(carrinho);
        return RefreshIndicator(
          onRefresh: _recarregar,
          child: ListView.builder(
            itemCount: carrinho.itens.length + (timestamps.isEmpty ? 1 : 2),
            itemBuilder: (context, index) {
              if (timestamps.isNotEmpty) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      timestamps,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  );
                }
                index -= 1;
              }
              if (index == carrinho.itens.length) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Total: ${currencyFormat.format(carrinho.valorTotal)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                );
              }
              final item = carrinho.itens[index];
              return ListTile(
                title: Text(item.nome),
                subtitle: Text('${item.quantidade}x ${currencyFormat.format(item.precoUnitario)}'),
                trailing: _removendoProdutoId == item.produtoId
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removerItem(item),
                      ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Aba "Compras": histórico de pedidos desse cliente (mesma tabela usada
/// pelo histórico geral de vendas), reaproveitando a tela de detalhes de
/// venda já existente pro toque em cada item.
class _ComprasClienteTab extends StatefulWidget {
  final String? clienteId;

  const _ComprasClienteTab({required this.clienteId});

  @override
  State<_ComprasClienteTab> createState() => _ComprasClienteTabState();
}

class _ComprasClienteTabState extends State<_ComprasClienteTab> {
  final _repository = VendaRepository();
  late Future<List<Venda>> _futureVendas;

  // null = "Todos" — só filtra quando o cliente tem pedido de mais de uma
  // plataforma (senão o filtro não ajuda em nada, só ocupa espaço).
  String? _canalSelecionado;

  @override
  void initState() {
    super.initState();
    _futureVendas = _carregar();
  }

  Future<List<Venda>> _carregar() {
    final clienteId = widget.clienteId;
    if (clienteId == null) return Future.value([]);
    return _repository.listarPorCliente(clienteId);
  }

  Future<void> _recarregar() async {
    setState(() {
      _futureVendas = _carregar();
    });
    await _futureVendas;
  }

  /// "Comprar novamente": soma os itens desse pedido antigo ao carrinho
  /// ATIVO do cliente (preço de hoje) — mesma tabela compartilhada com
  /// WhatsApp/site. Não abre a venda aqui: o carrinho atualizado já aparece
  /// em "Carrinhos do dia" ou ao selecionar esse cliente numa nova venda
  /// (mesma mesclagem automática que já existe pra carrinho de WhatsApp/site).
  Future<void> _comprarNovamente(Venda venda) async {
    final pedidoId = venda.idVenda;
    if (pedidoId == null) return;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Comprar novamente'),
        content: const Text(
          'Isso soma os itens desse pedido ao carrinho atual do cliente, com o preço de hoje. Continuar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Repetir pedido')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    try {
      final resultado = await CarrinhoClienteRepository().repetirPedido(pedidoId);
      if (!mounted) return;
      final indisponiveis = resultado.indisponiveis;
      final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Pedido repetido no carrinho'),
          content: Text(
            '${resultado.qtdAdicionados} ite${resultado.qtdAdicionados == 1 ? 'm' : 'ns'} '
            'adicionado${resultado.qtdAdicionados == 1 ? '' : 's'} ao carrinho atual do cliente '
            '(total: ${currencyFormat.format(resultado.carrinho.valorTotal)}).'
            '${indisponiveis.isEmpty ? '' : '\n\nNão entraram (indisponíveis): ${indisponiveis.map((i) => i.produtoNome).join(', ')}.'}'
            '\n\nContinue em "Carrinhos do dia" ou selecionando esse cliente numa nova venda.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ok'))],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao repetir pedido: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return FutureBuilder<List<Venda>>(
      future: _futureVendas,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro ao carregar compras: ${snapshot.error}'));
        }

        final vendas = snapshot.data ?? [];
        if (vendas.isEmpty) {
          return RefreshIndicator(
            onRefresh: _recarregar,
            child: ListView(
              children: const [
                SizedBox(height: 120),
                Center(child: Text('Nenhuma compra registrada.')),
              ],
            ),
          );
        }

        // Só as plataformas que esse cliente específico já usou — não faz
        // sentido mostrar um chip "iFood" pra quem nunca pediu por lá.
        final canais = vendas.map((v) => v.canalVenda).toSet().toList()..sort();
        final vendasFiltradas = _canalSelecionado == null
            ? vendas
            : vendas.where((v) => v.canalVenda == _canalSelecionado).toList();

        return RefreshIndicator(
          onRefresh: _recarregar,
          child: Column(
            children: [
              if (canais.length > 1)
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('Todos (${vendas.length})'),
                          selected: _canalSelecionado == null,
                          onSelected: (_) => setState(() => _canalSelecionado = null),
                        ),
                      ),
                      for (final canal in canais)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            avatar: Icon(iconeCanalVenda(canal), size: 16),
                            label: Text(
                              '${rotuloCanalVenda(canal)} (${vendas.where((v) => v.canalVenda == canal).length})',
                            ),
                            selected: _canalSelecionado == canal,
                            onSelected: (_) => setState(() => _canalSelecionado = canal),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: vendasFiltradas.length,
                  itemBuilder: (context, index) {
                    final venda = vendasFiltradas[index];
                    final cancelada = venda.cancelada;

                    return Card(
                      child: ListTile(
                        leading: Icon(
                          cancelada ? Icons.block : iconeCanalVenda(venda.canalVenda),
                          color: cancelada ? Colors.grey : Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(
                          currencyFormat.format(venda.valorTotal),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            decoration: cancelada ? TextDecoration.lineThrough : null,
                            color: cancelada ? Colors.grey[600] : null,
                          ),
                        ),
                        subtitle: Text(
                          '${dateFormat.format(venda.dataVenda)} • ${venda.metodoPagamento} • '
                          '${rotuloCanalVenda(venda.canalVenda)}${cancelada ? ' • CANCELADA' : ''}',
                          style: cancelada ? TextStyle(color: Colors.grey[600]) : null,
                        ),
                        trailing: venda.idVenda == null
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.replay),
                                tooltip: 'Comprar novamente',
                                onPressed: () => _comprarNovamente(venda),
                              ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => VendaDetalhesScreen(venda: venda)),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Aba "Conta": saldo atual + extrato de movimentações (crédito/débito),
/// com ações pra lançar ajustes manuais (ex: devolução, cortesia).
class _ContaClienteTab extends StatefulWidget {
  final Cliente cliente;

  const _ContaClienteTab({required this.cliente});

  @override
  State<_ContaClienteTab> createState() => _ContaClienteTabState();
}

class _ContaClienteTabState extends State<_ContaClienteTab> {
  final _repository = SaldoRepository();
  late Future<List<MovimentacaoSaldo>> _futureMovimentacoes;

  @override
  void initState() {
    super.initState();
    _futureMovimentacoes = _carregar();
  }

  @override
  void didUpdateWidget(covariant _ContaClienteTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cliente.idCliente != widget.cliente.idCliente) {
      setState(() {
        _futureMovimentacoes = _carregar();
      });
    }
  }

  Future<List<MovimentacaoSaldo>> _carregar() {
    final clienteId = widget.cliente.idCliente;
    if (clienteId == null) return Future.value([]);
    return _repository.listarPorCliente(clienteId);
  }

  Future<void> _abrirDialogoMovimentacao(String tipo) async {
    final clienteId = widget.cliente.idCliente;
    if (clienteId == null) return;

    final valorController = TextEditingController();
    final motivoController = TextEditingController();

    final confirmou = await showDialog<bool>(
      context: context,
      // Sem autofocus + sem fechar tocando fora: com o teclado aberto (via
      // autofocus) e o diálogo fechando por barrier-dismiss no mesmo frame,
      // bate num bug conhecido do framework do Flutter (assert
      // `_dependents.isEmpty` ao desativar o Overlay/IME) — só os botões
      // fecham o diálogo agora.
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(tipo == 'credito' ? 'Adicionar Crédito' : 'Registrar Débito'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: valorController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor (R\$)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: motivoController,
              decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );

    if (confirmou != true || !mounted) return;

    final valor = double.tryParse(valorController.text.replaceAll(',', '.'));
    if (valor == null || valor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um valor válido.')),
      );
      return;
    }

    try {
      final novoSaldo = await _repository.registrarMovimentacao(
        clienteId: clienteId,
        tipo: tipo,
        valor: valor,
        motivo: motivoController.text.trim().isEmpty ? null : motivoController.text.trim(),
      );
      if (!mounted) return;
      Provider.of<ClientProvider>(context, listen: false).atualizarSaldoLocal(clienteId, novoSaldo);
      setState(() {
        _futureMovimentacoes = _carregar();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível registrar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Column(
      children: [
        Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text('Saldo Atual', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  currencyFormat.format(widget.cliente.saldo),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green),
                ),
                // Ajustar saldo é ação financeira — vendedor só enxerga o
                // saldo atual (precisa pra aplicar como pagamento numa
                // venda), não pode criar/remover crédito por conta própria.
                if (context.watch<AuthProvider>().podeVerFinancas) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // Sem Expanded, os dois botões (ícone + texto) somados
                      // ultrapassavam a largura da tela em telas estreitas —
                      // esse era o overflow reportado na aba Conta.
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _abrirDialogoMovimentacao('credito'),
                          icon: const Icon(Icons.add, color: Colors.green),
                          label: const Text('Adicionar Crédito'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _abrirDialogoMovimentacao('debito'),
                          icon: const Icon(Icons.remove, color: Colors.red),
                          label: const Text('Registrar Débito'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        // Só leitura aqui — PetCash é gerido pelo site (crédito automático
        // na entrega, consumo/expiração no checkout), sem botão de ajuste
        // manual como o saldo comum (diferente semântica: tem validade por
        // crédito, não é um saldo único fungível).
        if (widget.cliente.saldoPetCash > 0)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('🐾 PetCash Disponível', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    currencyFormat.format(widget.cliente.saldoPetCash),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: FutureBuilder<List<MovimentacaoSaldo>>(
            future: _futureMovimentacoes,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Erro ao carregar extrato: ${snapshot.error}'));
              }

              final movimentacoes = snapshot.data ?? [];
              if (movimentacoes.isEmpty) {
                return const Center(child: Text('Nenhuma movimentação registrada.'));
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: movimentacoes.length,
                itemBuilder: (context, index) {
                  final mov = movimentacoes[index];
                  return ListTile(
                    leading: Icon(
                      mov.isCredito ? Icons.arrow_upward : Icons.arrow_downward,
                      color: mov.isCredito ? Colors.green : Colors.red,
                    ),
                    title: Text(mov.motivo?.isNotEmpty == true ? mov.motivo! : (mov.isCredito ? 'Crédito' : 'Débito')),
                    subtitle: Text(dateFormat.format(mov.criadoEm)),
                    trailing: Text(
                      '${mov.isCredito ? '+' : '-'}${currencyFormat.format(mov.valor)}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: mov.isCredito ? Colors.green : Colors.red),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Cadastros da mesma pessoa em outros canais (site, WhatsApp, Kyte...) +
/// vincular/desvincular manualmente. Só dono/gerente (a RPC também barra).
/// O vínculo junta o histórico só na visão da loja: o cliente continua vendo
/// no site apenas os pedidos do cadastro em que faz login.
class _CadastrosVinculadosSection extends StatefulWidget {
  final Cliente cliente;

  const _CadastrosVinculadosSection({super.key, required this.cliente});

  @override
  State<_CadastrosVinculadosSection> createState() => _CadastrosVinculadosSectionState();
}

class _CadastrosVinculadosSectionState extends State<_CadastrosVinculadosSection> {
  final _repository = VinculoClienteRepository();
  late Future<List<Cliente>> _futureGrupo;
  bool _processando = false;

  @override
  void initState() {
    super.initState();
    _futureGrupo = _repository.listarGrupo(widget.cliente.idCliente!);
  }

  Future<void> _aposMudanca(String mensagem) async {
    final messenger = ScaffoldMessenger.of(context);
    await context.read<ClientProvider>().carregarClientes();
    if (!mounted) return;
    final future = _repository.listarGrupo(widget.cliente.idCliente!);
    setState(() {
      _futureGrupo = future;
      _processando = false;
    });
    messenger.showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Future<void> _vincular() async {
    final outro = await showDialog<Cliente>(
      context: context,
      builder: (_) => _EscolherCadastroDialog(excluirId: widget.cliente.idCliente!),
    );
    if (outro == null || !mounted) return;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vincular cadastros?'),
        content: Text(
          '"${widget.cliente.nome}" e "${outro.nome}" passam a ser tratados como a mesma pessoa: '
          'pedidos, total gasto e recompra contam juntos aqui no Gestor.\n\n'
          'O cadastro com login no site fica como principal. O cliente não vê diferença no site, '
          'e saldo/PetCash continuam separados.\n\n'
          'Dá pra desfazer depois em "Desvincular".',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Vincular')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    setState(() => _processando = true);
    try {
      await _repository.vincularManual(widget.cliente.idCliente!, outro.idCliente!);
      if (!mounted) return;
      await _aposMudanca('Cadastros vinculados.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _processando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível vincular: $e')));
    }
  }

  Future<void> _desvincular(Cliente vinculado, Cliente principal) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desvincular?'),
        content: Text(
          '"${vinculado.nome}" deixa de estar ligado a "${principal.nome}". '
          'Cada um volta a contar só os próprios pedidos.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Desvincular')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    setState(() => _processando = true);
    try {
      await _repository.desvincular(vinculado.idCliente!);
      if (!mounted) return;
      await _aposMudanca('Cadastros desvinculados.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _processando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível desvincular: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Cliente>>(
      future: _futureGrupo,
      builder: (context, snapshot) {
        final grupo = snapshot.data ?? [];
        final principal = grupo.where((c) => c.pessoaId == null).firstOrNull;
        final outros = grupo.where((c) => c.idCliente != widget.cliente.idCliente).toList();

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (outros.isNotEmpty && principal != null)
                FormSection(
                  titulo: 'Cadastros vinculados',
                  children: outros.map((c) {
                    final ehPrincipal = c.pessoaId == null;
                    // Desvincular sempre solta o lado que não é o principal.
                    final vinculado = ehPrincipal ? widget.cliente : c;
                    final detalhes = [
                      if (ehPrincipal) 'principal',
                      if (c.authUserId != null) 'tem login no site',
                      if (c.canalOrigem == canalKyteHistorico) 'histórico Kyte',
                      '${c.quantidadeCompras ?? 0} pedido(s) no grupo',
                    ].join(' · ');
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.link),
                      title: Text(c.nome),
                      subtitle: Text(detalhes),
                      trailing: TextButton(
                        onPressed: _processando ? null : () => _desvincular(vinculado, principal),
                        child: const Text('Desvincular'),
                      ),
                    );
                  }).toList(),
                ),
              Center(
                child: OutlinedButton.icon(
                  onPressed: _processando || snapshot.connectionState != ConnectionState.done ? null : _vincular,
                  icon: _processando
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add_link, size: 16),
                  label: const Text('Vincular a outro cadastro'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Busca por nome ou telefone em todos os cadastros, inclusive os do
/// Histórico Kyte (que ficam fora da lista normal de clientes).
class _EscolherCadastroDialog extends StatefulWidget {
  final String excluirId;

  const _EscolherCadastroDialog({required this.excluirId});

  @override
  State<_EscolherCadastroDialog> createState() => _EscolherCadastroDialogState();
}

class _EscolherCadastroDialogState extends State<_EscolherCadastroDialog> {
  String _busca = '';
  List<Cliente> _kyte = [];

  @override
  void initState() {
    super.initState();
    ClienteRepository().listarHistoricoKyte().then((lista) {
      if (mounted) {
        setState(() {
          _kyte = lista;
        });
      }
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final termo = _busca.trim().toLowerCase();
    final digitos = termo.replaceAll(RegExp(r'\D'), '');
    final todos = [...context.read<ClientProvider>().clientes, ..._kyte];
    final resultados = termo.length < 2
        ? <Cliente>[]
        : todos.where((c) {
            if (c.idCliente == widget.excluirId) return false;
            if (c.nome.toLowerCase().contains(termo)) return true;
            if (digitos.length < 4) return false;
            final tel = (c.telefoneKyte ?? c.celular).replaceAll(RegExp(r'\D'), '');
            return tel.contains(digitos);
          }).take(50).toList();

    return AlertDialog(
      title: const Text('Vincular a qual cadastro?'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Nome ou telefone',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() {
                _busca = v;
              }),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: termo.length < 2
                  ? const Center(child: Text('Digite pelo menos 2 letras.'))
                  : resultados.isEmpty
                      ? const Center(child: Text('Nenhum cadastro encontrado.'))
                      : ListView.builder(
                          itemCount: resultados.length,
                          itemBuilder: (context, i) {
                            final c = resultados[i];
                            final detalhes = [
                              c.telefoneKyte ?? c.celular,
                              if (c.authUserId != null) 'tem login no site',
                              if (c.canalOrigem == canalKyteHistorico) 'histórico Kyte',
                              if (c.pessoaId != null) 'já vinculado',
                            ].where((s) => s.isNotEmpty).join(' · ');
                            return ListTile(
                              title: Text(c.nome),
                              subtitle: Text(detalhes),
                              onTap: () => Navigator.pop(context, c),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      ],
    );
  }
}
