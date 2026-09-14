import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/supabase_config.dart';
import '../models/pedido_compra.dart';
import '../models/produto.dart';
import '../models/produto_fornecedor.dart';
import '../providers/auth_provider.dart';
import '../providers/pedido_compra_provider.dart';
import '../providers/produto_provider.dart';
import '../repositories/pedido_compra_repository.dart';
import '../repositories/produto_fornecedor_repository.dart';
import '../utils/cotacao_pdf_parser.dart';
import '../utils/produto_validators.dart';
import '../utils/telefone_utils.dart';
import '../widgets/busca_produto_sheet.dart';
import 'cadastro_produto_screen.dart';

/// "R$ X,XX/un" sempre, e quando a quantidade é maior que 1 também mostra
/// o total (unitário × quantidade) — pedido explícito do usuário: nunca
/// esconder o valor por unidade, e somar o total quando for múltiplo.
String _formatarValorUnitarioETotal(double unitario, int quantidade) {
  final porUnidade = 'R\$ ${unitario.toStringAsFixed(2)}/un';
  if (quantidade <= 1) return porUnidade;
  final total = unitario * quantidade;
  return '$porUnidade (R\$ ${total.toStringAsFixed(2)} no total, ${quantidade}un)';
}

/// O que pedir pro fornecedor sobre um item específico, na mensagem de
/// ajuste (ver `_enviarMensagemAjuste`) — uma ação por item, nunca mais de
/// uma ao mesmo tempo (não faz sentido pedir mais quantidade E remover o
/// mesmo item).
enum AcaoMensagemFornecedor {
  nenhuma,
  reportarDivergencia,
  ajustarQuantidade,
  perguntarDescontoVolume,
  removerDoPedido,
}

extension on AcaoMensagemFornecedor {
  String get rotulo {
    switch (this) {
      case AcaoMensagemFornecedor.nenhuma:
        return 'Nenhuma ação';
      case AcaoMensagemFornecedor.reportarDivergencia:
        return 'Reportar divergência';
      case AcaoMensagemFornecedor.ajustarQuantidade:
        return 'Ajustar quantidade (pra mais ou pra menos)';
      case AcaoMensagemFornecedor.perguntarDescontoVolume:
        return 'Perguntar desconto por volume';
      case AcaoMensagemFornecedor.removerDoPedido:
        return 'Remover do pedido';
    }
  }
}

/// Item novo pra incluir na mensagem de ajuste, digitado livre — pra
/// produto que o fornecedor tem mas ainda nem existe no catálogo (não dá
/// pra vincular por id porque não existe id nenhum ainda).
class _ItemNovoMensagem {
  final TextEditingController nomeController = TextEditingController();
  final TextEditingController quantidadeController = TextEditingController();

  void dispose() {
    nomeController.dispose();
    quantidadeController.dispose();
  }
}

/// Item da cotação sem produto correspondente no catálogo (ver seção
/// "Produtos da cotação sem cadastro") — mesma mecânica de ação pra
/// mensagem que `_ItemConferencia` usa, só que sem `ItemPedidoCompra` por
/// trás (não tem produto_id nenhum ainda, por isso não é um item real do
/// pedido — só existe pra decidir cadastrar/ignorar/perguntar).
class _ItemNaoCadastrado {
  final ItemCotacaoExtraido lido;
  AcaoMensagemFornecedor acaoMensagem = AcaoMensagemFornecedor.nenhuma;
  final TextEditingController quantidadeDesejadaController = TextEditingController();

  _ItemNaoCadastrado(this.lido);

  void dispose() => quantidadeDesejadaController.dispose();
}

/// Seletor de ação reaproveitado tanto pelos itens do pedido
/// (`_LinhaConferencia`) quanto pelos produtos da cotação sem cadastro —
/// mesma interação nos dois lugares, pedido explícito do usuário.
class _SeletorAcaoMensagem extends StatelessWidget {
  final AcaoMensagemFornecedor valor;
  final ValueChanged<AcaoMensagemFornecedor> onChanged;
  final TextEditingController quantidadeDesejadaController;

  /// true pros "Produtos da cotação sem cadastro" (não têm campo
  /// "Confirmado" próprio — só existe [quantidadeDesejadaController] mesmo
  /// pra dizer quanto pedir). false pros itens do pedido real
  /// (`_LinhaConferencia`), que JÁ têm um campo "Confirmado" editável
  /// acima — usar esse mesmo campo em vez de duplicar em outro,
  /// exatamente o que causava "ajustei a quantidade mas não salvou nada":
  /// a quantidade negociada ficava só no campo da mensagem, nunca no
  /// campo que a Conferência realmente salva.
  final bool exibirCampoQuantidade;

  const _SeletorAcaoMensagem({
    required this.valor,
    required this.onChanged,
    required this.quantidadeDesejadaController,
    this.exibirCampoQuantidade = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<AcaoMensagemFornecedor>(
          initialValue: valor,
          isDense: true,
          decoration: const InputDecoration(labelText: 'Pedir ajuste ao fornecedor sobre este item', isDense: true),
          items: [
            for (final acao in AcaoMensagemFornecedor.values) DropdownMenuItem(value: acao, child: Text(acao.rotulo)),
          ],
          onChanged: (acao) => onChanged(acao ?? AcaoMensagemFornecedor.nenhuma),
        ),
        if (valor == AcaoMensagemFornecedor.ajustarQuantidade && !exibirCampoQuantidade)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Edite o campo "Confirmado" acima com a quantidade que você quer pedir — é ele que a mensagem usa e que fica salvo.',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        if (valor == AcaoMensagemFornecedor.ajustarQuantidade && exibirCampoQuantidade)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
              controller: quantidadeDesejadaController,
              decoration: const InputDecoration(labelText: 'Nova quantidade desejada', isDense: true),
              keyboardType: TextInputType.number,
            ),
          ),
      ],
    );
  }
}

/// Por que um item aparece destacado na conferência — determina em qual
/// seção da tela ele entra e a cor/explicação mostrada, pra nunca deixar
/// um card vermelho sem dizer o motivo.
enum CategoriaConferencia {
  /// Preço e/ou quantidade confirmados diferem do que foi pedido.
  divergente,

  /// Estava no pedido, mas o PDF lido automaticamente não trouxe esse item.
  faltanteNoPdf,

  /// Veio no PDF (ou foi registrado manualmente) sem ter sido pedido.
  naoEstavaNoPedido,

  /// Bateu certinho — pedido, PDF e confirmação concordam.
  semDivergencia,
}

class _ItemConferencia {
  final ItemPedidoCompra original;
  final TextEditingController confirmadoController;
  final TextEditingController custoController;
  String? produtoSubstitutoId;
  String? produtoSubstitutoNome;

  /// Marcado manualmente pelo usuário conferindo item por item — "já
  /// revisei este, tá tudo certo" — puramente pra ajudar a acompanhar o
  /// progresso numa lista grande, não afeta o que é salvo nem a mensagem
  /// pro fornecedor.
  bool revisadoOk = false;

  /// true depois de ler um PDF de cotação/pedido automaticamente (ver
  /// [parseCotacaoTargetSistemas]) quando este item não apareceu nele —
  /// só um aviso visual, não impede salvar (pode ser item que o
  /// fornecedor vai mandar depois, ou já foi conferido antes).
  bool foraDaCotacaoLida = false;

  /// O que incluir sobre este item na mensagem de ajuste pro fornecedor
  /// (ver `_enviarMensagemAjuste`) — escolhido pelo usuário, exceto
  /// `reportarDivergencia` que já vem pré-marcado quando a leitura
  /// automática do PDF encontra preço/quantidade diferente (usuário pode
  /// desmarcar se não quiser perguntar sobre aquele item específico).
  AcaoMensagemFornecedor acaoMensagem = AcaoMensagemFornecedor.nenhuma;
  final TextEditingController quantidadeDesejadaController = TextEditingController();

  _ItemConferencia(this.original)
      : confirmadoController = TextEditingController(
          text: (original.quantidadeConfirmada ?? original.quantidadePedida).toString(),
        ),
        custoController = TextEditingController(
          text: ProdutoValidators.formatarMoeda(original.custoConfirmado ?? original.custoUnitario),
        );

  int get quantidadeConfirmadaAtual => int.tryParse(confirmadoController.text) ?? original.quantidadePedida;
  double get custoConfirmadoAtual => ProdutoValidators.parseNumero(custoController.text) ?? original.custoUnitario;
  bool get quantidadeMudou => quantidadeConfirmadaAtual != original.quantidadePedida;
  bool get precoMudou => custoConfirmadoAtual != original.custoUnitario;

  bool get naoEstavaNoPedido => original.quantidadePedida == 0;

  bool get divergente => produtoSubstitutoId != null || quantidadeMudou || precoMudou;

  /// Uma única categoria por item, nessa prioridade — usada pra agrupar a
  /// lista em seções (ver `_ConferenciaEspelhoScreenState.build`).
  CategoriaConferencia get categoria {
    if (naoEstavaNoPedido) return CategoriaConferencia.naoEstavaNoPedido;
    if (foraDaCotacaoLida) return CategoriaConferencia.faltanteNoPdf;
    if (divergente) return CategoriaConferencia.divergente;
    return CategoriaConferencia.semDivergencia;
  }

  ItemPedidoCompra paraSalvar() {
    return original.copyWith(
      quantidadeConfirmada: quantidadeConfirmadaAtual,
      quantidadeConfirmadaDefinir: true,
      custoConfirmado: custoConfirmadoAtual,
      produtoSubstitutoId: produtoSubstitutoId,
      produtoSubstitutoNome: produtoSubstitutoNome,
      produtoSubstitutoDefinir: true,
    );
  }

  void dispose() {
    confirmadoController.dispose();
    custoController.dispose();
    quantidadeDesejadaController.dispose();
  }
}

/// 10 anos — bucket 'pedidos-compra' é privado, então o anexo só fica
/// acessível via signed URL; um documento de pedido precisa continuar
/// abrível "pra sempre" na prática, não só por alguns minutos/horas.
const _validadeAnexoSegundos = 315360000;

/// Conferência do espelho enviado pelo fornecedor: registra quantas fotos
/// forem necessárias (pedido grande costuma vir em mais de uma imagem) e a
/// quantidade que realmente foi confirmada por item — cobrindo não só
/// ruptura (veio menos) mas qualquer erro do fornecedor (veio mais, veio
/// produto errado, ou chegou algo que nem tinha sido pedido).
class ConferenciaEspelhoScreen extends StatefulWidget {
  final String pedidoId;

  const ConferenciaEspelhoScreen({super.key, required this.pedidoId});

  @override
  State<ConferenciaEspelhoScreen> createState() => _ConferenciaEspelhoScreenState();
}

class _ConferenciaEspelhoScreenState extends State<ConferenciaEspelhoScreen> {
  final _repository = PedidoCompraRepository();
  PedidoCompra? _pedido;
  List<_ItemConferencia> _itens = [];
  final List<AnexoEspelho> _anexos = [];
  final List<_ItemNaoCadastrado> _naoCadastrados = [];
  final List<_ItemNovoMensagem> _itensNovosMensagem = [];
  final Map<String, ProdutoFornecedor> _vinculosPorProdutoId = {};
  bool _carregando = true;
  bool _enviandoAnexo = false;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final item in _itens) {
      item.dispose();
    }
    for (final item in _itensNovosMensagem) {
      item.dispose();
    }
    for (final item in _naoCadastrados) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final pedido = await _repository.buscarPorId(widget.pedidoId);

      // Vínculo produto-fornecedor (com faixas de desconto) de cada item,
      // pra mostrar "peça mais Nun e economize R$X" igual já existe na
      // Sugestão de Compra — antes essa dica só aparecia lá, não aqui, que
      // é justamente onde a negociação com o fornecedor acontece de verdade.
      final produtoFornecedorRepo = ProdutoFornecedorRepository();
      final produtoIds = {for (final i in pedido.itens) i.produtoSubstitutoId ?? i.produtoId};
      final vinculos = <String, ProdutoFornecedor>{};
      for (final produtoId in produtoIds) {
        final lista = await produtoFornecedorRepo.listarPorProduto(produtoId);
        for (final v in lista) {
          if (v.fornecedorId == pedido.fornecedor.id) {
            vinculos[produtoId] = v;
            break;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _pedido = pedido;
        _itens = pedido.itens.map((i) => _ItemConferencia(i)).toList();
        _anexos
          ..clear()
          ..addAll(pedido.anexosEspelho);
        _vinculosPorProdutoId
          ..clear()
          ..addAll(vinculos);
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar pedido: $e')));
    }
  }

  Future<void> _adicionarFotos() async {
    List<XFile> arquivos;
    try {
      arquivos = await ImagePicker().pickMultiImage();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao selecionar fotos: $e')));
      return;
    }
    if (arquivos.isEmpty) return;

    setState(() => _enviandoAnexo = true);
    try {
      final empresaId = context.read<AuthProvider>().empresaId!;
      for (final arquivo in arquivos) {
        final bytes = await arquivo.readAsBytes();
        final nomeArquivo = arquivo.name;
        final path = '$empresaId/${widget.pedidoId}/${DateTime.now().millisecondsSinceEpoch}_$nomeArquivo';
        await supabase.storage.from('pedidos-compra').uploadBinary(path, bytes);
        // Bucket 'pedidos-compra' é PRIVADO — getPublicUrl gera um link que
        // nunca funciona pra ninguém (404 silencioso, achado real: o anexo
        // salvo nunca dava pra abrir de novo). Signed URL de longa duração
        // (10 anos) resolve pra um documento que precisa continuar
        // acessível indefinidamente, sem tornar o bucket inteiro público.
        final url = await supabase.storage.from('pedidos-compra').createSignedUrl(path, _validadeAnexoSegundos);
        if (!mounted) return;
        setState(() {
          _anexos.add(AnexoEspelho(url: url, tipo: 'imagem', nomeArquivo: nomeArquivo, criadoEm: DateTime.now()));
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao enviar foto: $e')));
    } finally {
      if (mounted) setState(() => _enviandoAnexo = false);
    }
  }

  Future<void> _adicionarPdf() async {
    final resultado = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    if (resultado == null || resultado.files.single.bytes == null || !mounted) return;

    setState(() => _enviandoAnexo = true);
    try {
      final empresaId = context.read<AuthProvider>().empresaId!;
      final arquivo = resultado.files.single;
      final path = '$empresaId/${widget.pedidoId}/${DateTime.now().millisecondsSinceEpoch}_${arquivo.name}';
      await supabase.storage.from('pedidos-compra').uploadBinary(
            path,
            arquivo.bytes!,
            fileOptions: const FileOptions(contentType: 'application/pdf'),
          );
      final url = await supabase.storage.from('pedidos-compra').createSignedUrl(path, _validadeAnexoSegundos);
      if (!mounted) return;
      setState(() {
        _anexos.add(AnexoEspelho(url: url, tipo: 'pdf', nomeArquivo: arquivo.name, criadoEm: DateTime.now()));
      });
      await _tentarConferirAutomaticamente(arquivo.bytes!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao enviar PDF: $e')));
    } finally {
      if (mounted) setState(() => _enviandoAnexo = false);
    }
  }

  void _removerAnexo(int index) {
    setState(() => _anexos.removeAt(index));
  }

  /// Lê o PDF recém-anexado e pré-preenche quantidade/custo confirmados com
  /// o que o fornecedor realmente cotou — antes disso, anexar o PDF só
  /// guardava o arquivo como referência e o usuário tinha que digitar tudo
  /// olhando pro PDF manualmente. Casamento é só por código de barras
  /// (nunca por nome — mesmo princípio de toda reconciliação por EAN já
  /// usada no projeto), então um produto com nome diferente no PDF mas EAN
  /// igual ainda é reconhecido certo. PDF em formato não reconhecido (não é
  /// do Target Sistemas) simplesmente não muda nada — segue manual, igual
  /// antes.
  /// Formato de PDF que o parser ainda não reconhece — avisa explicitamente
  /// em vez de falhar em silêncio, pra pedir pro usuário voltar aqui e
  /// mostrar o arquivo (o parser é ensinado formato por formato, ver
  /// [parseCotacaoTargetSistemas]).
  void _avisarFormatoNaoReconhecido() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: const Text(
        'Não reconheci o formato deste PDF pra ler automaticamente. Confirme os itens manualmente '
        'abaixo — e se puder, volte aqui e mostre esse arquivo pra ensinar esse formato novo.',
      ),
    ));
  }

  Future<void> _tentarConferirAutomaticamente(Uint8List bytes) async {
    List<ItemCotacaoExtraido> itensLidos;
    try {
      final texto = extrairTextoPdf(bytes);
      itensLidos = parseCotacaoTargetSistemas(texto);
    } catch (e) {
      debugPrint('Não deu pra ler o PDF automaticamente: $e');
      _avisarFormatoNaoReconhecido();
      return;
    }
    if (itensLidos.isEmpty) {
      _avisarFormatoNaoReconhecido();
      return;
    }
    if (!mounted) return;

    final produtosPorId = {for (final p in context.read<ProdutoProvider>().produtos) p.id: p};
    Produto? produtoPorEan(String ean) {
      for (final p in produtosPorId.values) {
        if (p.codigoBarras == ean) return p;
      }
      return null;
    }

    final eansRestantes = {for (final i in itensLidos) i.codigoBarras: i};
    var atualizados = 0;
    var adicionados = 0;

    setState(() {
      for (final item in _itens) {
        // Casa pelo EAN do produto REAL deste item — o substituto, se
        // houver (fornecedor mandou outro produto no lugar), senão o
        // produto originalmente pedido.
        final produtoId = item.produtoSubstitutoId ?? item.original.produtoId;
        final ean = produtosPorId[produtoId]?.codigoBarras;
        final lido = ean == null ? null : eansRestantes.remove(ean);
        if (lido == null) {
          item.foraDaCotacaoLida = true;
          continue;
        }
        item.foraDaCotacaoLida = false;
        item.confirmadoController.text = lido.quantidade.toString();
        item.custoController.text = ProdutoValidators.formatarMoeda(lido.custoUnitario);
        if (item.divergente) item.acaoMensagem = AcaoMensagemFornecedor.reportarDivergencia;
        atualizados++;
      }

      for (final item in _naoCadastrados) {
        item.dispose();
      }
      _naoCadastrados.clear();
      for (final lido in eansRestantes.values) {
        final produto = produtoPorEan(lido.codigoBarras);
        if (produto == null || produto.id == null) {
          // Fornecedor mandou esse item na cotação, mas não existe produto
          // com esse EAN no catálogo — antes disso ficava só contado num
          // número na notificação, sem dizer QUAL produto era. Agora entra
          // numa lista própria (ver seção "Produtos da cotação sem
          // cadastro" na tela) pra decidir se cadastra ou ignora.
          _naoCadastrados.add(_ItemNaoCadastrado(lido));
          continue;
        }
        final novoItem = _ItemConferencia(ItemPedidoCompra(
          produtoId: produto.id!,
          produtoNome: produto.nome,
          quantidadePedida: 0,
          quantidadeConfirmada: lido.quantidade,
          custoUnitario: produto.custo,
          custoConfirmado: lido.custoUnitario,
          origem: OrigemItemPedidoCompra.conferencia,
        ))
          ..confirmadoController.text = lido.quantidade.toString()
          ..custoController.text = ProdutoValidators.formatarMoeda(lido.custoUnitario);
        _itens.add(novoItem);
        adicionados++;
      }
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: Text(
        '${itensLidos.length} item(ns) lido(s) do PDF: $atualizados atualizado(s), $adicionados novo(s)'
        '${_naoCadastrados.isNotEmpty ? ', ${_naoCadastrados.length} sem cadastro no catálogo (veja a lista abaixo)' : ''}.',
      ),
    ));
  }

  /// Abre o cadastro de produto já com nome/EAN/custo vindos da cotação —
  /// pro caso de "Produtos da cotação sem cadastro" (o fornecedor vendeu
  /// algo que o catálogo ainda não conhece). Ao salvar, o produto criado já
  /// entra como item novo na conferência (mesmo tratamento de "veio sem
  /// ter sido pedido"), sem precisar sair e voltar pra achar ele de novo.
  Future<void> _cadastrarProdutoNaoCatalogado(_ItemNaoCadastrado item) async {
    final lido = item.lido;
    final produtoCriado = await Navigator.of(context).push<Produto>(MaterialPageRoute(
      builder: (_) => CadastroProdutoScreen(
        retornarProdutoCriado: true,
        produtoInicial: Produto(
          nome: lido.nome,
          codigoBarras: lido.codigoBarras,
          custo: lido.custoUnitario,
          preco: lido.custoUnitario,
          descricao: '',
          categoria: '',
          estoqueAtual: 0,
          estoqueMinimo: 0,
          imagemUrl: '',
        ),
      ),
    ));
    if (produtoCriado == null || produtoCriado.id == null || !mounted) return;

    setState(() {
      _naoCadastrados.remove(item);
      item.dispose();
      _itens.add(_ItemConferencia(ItemPedidoCompra(
        produtoId: produtoCriado.id!,
        produtoNome: produtoCriado.nome,
        quantidadePedida: 0,
        quantidadeConfirmada: lido.quantidade,
        custoUnitario: produtoCriado.custo,
        custoConfirmado: lido.custoUnitario,
        origem: OrigemItemPedidoCompra.conferencia,
      ))
        ..confirmadoController.text = lido.quantidade.toString()
        ..custoController.text = ProdutoValidators.formatarMoeda(lido.custoUnitario));
    });
  }

  /// Descarta um item da cotação sem cadastro — não cadastra, não entra na
  /// mensagem, só some da lista (ex: fornecedor cotou algo que não
  /// interessa comprar).
  void _ignorarNaoCadastrado(_ItemNaoCadastrado item) {
    setState(() {
      _naoCadastrados.remove(item);
      item.dispose();
    });
  }

  /// Monta a mensagem de WhatsApp com os ajustes marcados (ver
  /// `AcaoMensagemFornecedor`) e os itens novos digitados livres, e abre
  /// pro usuário revisar/enviar — nunca envia sozinho, só prepara o texto
  /// (mesmo padrão de `_abrirWhatsApp` em `pedido_compra_detalhe_screen.dart`).
  Future<void> _enviarMensagemAjuste() async {
    final pedido = _pedido;
    if (pedido == null) return;

    // Junta os itens do pedido e os "sem cadastro" — mesma ação, mesmo
    // seletor (`_SeletorAcaoMensagem`), só a frase muda conforme a origem
    // (pedido real tem quantidade/custo ORIGINAL pra comparar; item sem
    // cadastro só tem o que veio cotado, sem "original" próprio).
    final remover = <String>[];
    final ajustarQtd = <String>[];
    final desconto = <String>[];
    final divergencia = <String>[];

    for (final i in _itens) {
      switch (i.acaoMensagem) {
        case AcaoMensagemFornecedor.removerDoPedido:
          remover.add('• ${i.original.produtoNome}');
        case AcaoMensagemFornecedor.ajustarQuantidade:
          // Lê direto do campo "Confirmado" (edite-o pra digitar a
          // quantidade que quer pedir) — não um campo separado, senão a
          // quantidade negociada nunca chega a ser salva de verdade (bug
          // real: usuário ajustava um campo só da mensagem, o pedido
          // continuava com o valor antigo depois de "Salvar conferência").
          ajustarQtd.add('• ${i.original.produtoNome}: de ${i.original.quantidadePedida}un pra ${i.quantidadeConfirmadaAtual}un');
        case AcaoMensagemFornecedor.perguntarDescontoVolume:
          // Referência é a quantidade/custo CONFIRMADOS (o que a leitura do
          // PDF já indicou, ou o que foi digitado à mão), não o pedido
          // original — se o fornecedor já cotou 18un a R$2,27, é sobre
          // essa realidade que faz sentido perguntar "tem melhor levando
          // mais", não sobre a 1un que eu tinha pedido antes de cotar.
          desconto.add(
            '• ${i.original.produtoNome}: hoje ${_formatarValorUnitarioETotal(i.custoConfirmadoAtual, i.quantidadeConfirmadaAtual)}'
            ' — tem preço melhor levando mais?',
          );
        case AcaoMensagemFornecedor.reportarDivergencia:
          final partes = <String>[];
          if (i.quantidadeMudou) partes.add('${i.original.quantidadePedida}un → ${i.quantidadeConfirmadaAtual}un');
          if (i.precoMudou) {
            partes.add(
              '${_formatarValorUnitarioETotal(i.original.custoUnitario, i.original.quantidadePedida)} → '
              '${_formatarValorUnitarioETotal(i.custoConfirmadoAtual, i.quantidadeConfirmadaAtual)}',
            );
          }
          final detalhe = partes.isEmpty ? 'pode confirmar os dados desse item?' : '${partes.join(', ')}, pode confirmar?';
          divergencia.add('• ${i.original.produtoNome}: $detalhe');
        case AcaoMensagemFornecedor.nenhuma:
          break;
      }
    }

    for (final n in _naoCadastrados) {
      final lido = n.lido;
      switch (n.acaoMensagem) {
        case AcaoMensagemFornecedor.removerDoPedido:
          remover.add('• ${lido.nome} (não vou incluir esse item)');
        case AcaoMensagemFornecedor.ajustarQuantidade:
          final desejada = n.quantidadeDesejadaController.text.trim();
          ajustarQtd.add('• ${lido.nome}: de ${lido.quantidade}un cotados pra ${desejada.isEmpty ? '?' : desejada}un');
        case AcaoMensagemFornecedor.perguntarDescontoVolume:
          desconto.add(
            '• ${lido.nome}: hoje ${_formatarValorUnitarioETotal(lido.custoUnitario, lido.quantidade)}'
            ' — tem preço melhor levando mais?',
          );
        case AcaoMensagemFornecedor.reportarDivergencia:
          divergencia.add(
            '• ${lido.nome} — ${_formatarValorUnitarioETotal(lido.custoUnitario, lido.quantidade)} '
            '(EAN ${lido.codigoBarras}), ainda não tenho cadastrado — pode confirmar esse item?',
          );
        case AcaoMensagemFornecedor.nenhuma:
          break;
      }
    }

    final novos = _itensNovosMensagem.where((i) => i.nomeController.text.trim().isNotEmpty).toList();

    if (remover.isEmpty && ajustarQtd.isEmpty && desconto.isEmpty && divergencia.isEmpty && novos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Marque uma ação em pelo menos um item (ou adicione um item novo) antes de gerar a mensagem.'),
      ));
      return;
    }

    if (pedido.fornecedor.telefoneParaPedido.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este fornecedor não tem WhatsApp/telefone cadastrado')),
      );
      return;
    }

    final numero = pedido.numeroSequencial != null ? '#${pedido.numeroSequencial}' : '';
    final buffer = StringBuffer('Oi! Sobre o pedido $numero, preciso de alguns ajustes:\n');

    if (remover.isNotEmpty) {
      buffer.writeln('\n🗑️ Remover / não incluir:');
      remover.forEach(buffer.writeln);
    }
    if (ajustarQtd.isNotEmpty) {
      buffer.writeln('\n🔄 Ajustar quantidade:');
      ajustarQtd.forEach(buffer.writeln);
    }
    if (desconto.isNotEmpty) {
      buffer.writeln('\n💰 Consulta de preço por volume:');
      desconto.forEach(buffer.writeln);
    }
    if (divergencia.isNotEmpty) {
      buffer.writeln('\n⚠️ Confirmar / divergências:');
      divergencia.forEach(buffer.writeln);
    }
    if (novos.isNotEmpty) {
      buffer.writeln('\n➕ Também gostaria de incluir:');
      for (final i in novos) {
        final qtd = i.quantidadeController.text.trim();
        buffer.writeln('• ${i.nomeController.text.trim()}${qtd.isEmpty ? '' : ' — ${qtd}un'}');
      }
    }
    buffer.write('\nPode me ajudar com isso? Obrigado!');

    final texto = Uri.encodeComponent(buffer.toString());
    final url = Uri.parse('${linkWhatsApp(pedido.fornecedor.telefoneParaPedido)}?text=$texto');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível abrir o WhatsApp: $e')));
    }
  }

  void _adicionarItemNovoMensagem() {
    setState(() => _itensNovosMensagem.add(_ItemNovoMensagem()));
  }

  void _removerItemNovoMensagem(_ItemNovoMensagem item) {
    setState(() {
      _itensNovosMensagem.remove(item);
      item.dispose();
    });
  }

  /// Salva uma faixa de desconto nova pro vínculo produto-fornecedor deste
  /// item, pré-preenchida com o que acabou de ser confirmado (ex: fornecedor
  /// deu 18% a partir de 120un — você já ajustou Confirmado/Custo pra
  /// refletir isso, aqui só registra a condição pra próxima vez). Sem isso,
  /// a única forma de cadastrar uma faixa era saindo daqui e indo em Editar
  /// Produto > Fornecedores deste produto.
  Future<void> _registrarFaixaDesconto(_ItemConferencia item) async {
    final produtoId = item.produtoSubstitutoId ?? item.original.produtoId;
    final vinculo = _vinculosPorProdutoId[produtoId];
    if (vinculo == null || vinculo.id == null) return;

    final quantidadeController = TextEditingController(text: item.quantidadeConfirmadaAtual.toString());
    final custoController = TextEditingController(text: ProdutoValidators.formatarMoeda(item.custoConfirmadoAtual));

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar faixa de desconto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('A partir de quantas unidades esse custo passa a valer com este fornecedor?'),
            const SizedBox(height: 12),
            TextField(
              controller: quantidadeController,
              decoration: const InputDecoration(labelText: 'Quantidade mínima'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: custoController,
              decoration: const InputDecoration(labelText: 'Custo unitário (R\$)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Registrar')),
        ],
      ),
    );
    final quantidadeMinima = int.tryParse(quantidadeController.text);
    final custoUnitario = ProdutoValidators.parseNumero(custoController.text);
    quantidadeController.dispose();
    custoController.dispose();
    if (confirmou != true || quantidadeMinima == null || custoUnitario == null || !mounted) return;

    final vinculoAtualizado = ProdutoFornecedor(
      id: vinculo.id,
      produtoId: vinculo.produtoId,
      fornecedorId: vinculo.fornecedorId,
      fornecedorNome: vinculo.fornecedorNome,
      produtoNome: vinculo.produtoNome,
      produtoCodigoBarras: vinculo.produtoCodigoBarras,
      custoUnitario: vinculo.custoUnitario,
      codigoProdutoFornecedor: vinculo.codigoProdutoFornecedor,
      multiploCompra: vinculo.multiploCompra,
      principal: vinculo.principal,
      ativo: vinculo.ativo,
      faixasDesconto: [
        ...vinculo.faixasDesconto,
        FaixaDescontoProdutoFornecedor(quantidadeMinima: quantidadeMinima, custoUnitario: custoUnitario),
      ],
    );

    try {
      final salvo = await ProdutoFornecedorRepository().atualizar(vinculoAtualizado);
      if (!mounted) return;
      setState(() => _vinculosPorProdutoId[produtoId] = salvo);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Faixa de desconto registrada.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao registrar faixa: $e')));
    }
  }

  Future<void> _marcarSubstituto(_ItemConferencia item) async {
    final produtos = context.read<ProdutoProvider>().produtos.where((p) => p.ativo && p.id != null).toList()
      ..sort((a, b) => a.nome.compareTo(b.nome));

    final produto = await showModalBottomSheet<Produto>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BuscaProdutoSheet(produtos: produtos),
    );
    if (produto == null) return;
    setState(() {
      item.produtoSubstitutoId = produto.id;
      item.produtoSubstitutoNome = produto.nome;
    });
  }

  Future<void> _adicionarItemNaoPedido() async {
    final produtos = context.read<ProdutoProvider>().produtos.where((p) => p.ativo && p.id != null).toList()
      ..sort((a, b) => a.nome.compareTo(b.nome));

    final produto = await showModalBottomSheet<Produto>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BuscaProdutoSheet(produtos: produtos),
    );
    if (produto == null) return;

    setState(() {
      _itens.add(_ItemConferencia(ItemPedidoCompra(
        produtoId: produto.id!,
        produtoNome: produto.nome,
        quantidadePedida: 0,
        quantidadeConfirmada: 1,
        custoUnitario: produto.custo,
        origem: OrigemItemPedidoCompra.conferencia,
      ))
        ..confirmadoController.text = '1');
    });
  }

  Future<void> _salvarConferencia() async {
    final pedido = _pedido;
    if (pedido == null) return;

    setState(() => _salvando = true);
    try {
      final provider = context.read<PedidoCompraProvider>();
      final itensParaSalvar = _itens.map((i) => i.paraSalvar()).toList();
      await provider.substituirItens(pedido.id!, itensParaSalvar);
      await provider.confirmarConferencia(pedido.id!, anexos: _anexos);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar conferência: $e')));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  /// Cada seção é um accordion — pedido grande (muitos itens sem
  /// divergência, por exemplo) não obriga rolar a tela inteira pra ver as
  /// seções que realmente precisam de atenção.
  Widget _secao({
    required String titulo,
    required String explicacao,
    required Color cor,
    required List<_ItemConferencia> itens,
    bool expandidoPorPadrao = true,
  }) {
    if (itens.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: expandidoPorPadrao,
        leading: Container(width: 10, height: 10, decoration: BoxDecoration(color: cor, shape: BoxShape.circle)),
        title: Text('$titulo (${itens.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(explicacao, style: const TextStyle(fontSize: 12)),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          for (final item in itens)
            _LinhaConferencia(
              item: item,
              onMarcarSubstituto: () => _marcarSubstituto(item),
              vinculo: _vinculosPorProdutoId[item.produtoSubstitutoId ?? item.original.produtoId],
              onRegistrarFaixaDesconto: () => _registrarFaixaDesconto(item),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final porCategoria = <CategoriaConferencia, List<_ItemConferencia>>{};
    for (final item in _itens) {
      (porCategoria[item.categoria] ??= []).add(item);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Conferência do Espelho')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Anexos do espelho', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Envie quantas fotos ou PDFs forem necessários — um pedido grande costuma vir em mais de uma imagem.',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _anexos.length; i++) _ChipAnexo(anexo: _anexos[i], onRemover: () => _removerAnexo(i)),
                    ActionChip(
                      avatar: _enviandoAnexo
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add_photo_alternate_outlined, size: 18),
                      label: const Text('Fotos'),
                      onPressed: _enviandoAnexo ? null : _adicionarFotos,
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text('PDF'),
                      onPressed: _enviandoAnexo ? null : _adicionarPdf,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Itens pedidos', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Confirme o que o fornecedor realmente vai mandar — pode ser diferente do pedido (a mais, a menos, produto trocado, ou preço diferente do cotado).',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                _secao(
                  titulo: 'Preço ou quantidade diferente do pedido',
                  explicacao: 'O que foi confirmado (do PDF lido, ou digitado à mão) não bate com o que você pediu.',
                  cor: colorScheme.error,
                  itens: porCategoria[CategoriaConferencia.divergente] ?? [],
                ),
                _secao(
                  titulo: 'Não vieram no PDF lido',
                  explicacao: 'Estavam no pedido, mas o PDF anexado não trouxe esses itens — confirme manualmente ou remova se o fornecedor não vai mandar.',
                  cor: colorScheme.tertiary,
                  itens: porCategoria[CategoriaConferencia.faltanteNoPdf] ?? [],
                ),
                _secao(
                  titulo: 'Vieram sem ter sido pedidos',
                  explicacao: 'O PDF trouxe esses itens (ou foram registrados manualmente) mesmo sem estarem no pedido original.',
                  cor: colorScheme.secondary,
                  itens: porCategoria[CategoriaConferencia.naoEstavaNoPedido] ?? [],
                ),
                if (_naoCadastrados.isNotEmpty)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    clipBehavior: Clip.antiAlias,
                    child: ExpansionTile(
                      initiallyExpanded: true,
                      leading: Container(width: 10, height: 10, decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle)),
                      title: Text('Produtos da cotação sem cadastro (${_naoCadastrados.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text(
                        'O fornecedor cotou esses itens, mas nenhum produto no catálogo tem esse código de barras.',
                        style: TextStyle(fontSize: 12),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      children: [
                        for (final item in _naoCadastrados)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.lido.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text(
                                    'EAN: ${item.lido.codigoBarras} • ${item.lido.quantidade}un a R\$ ${item.lido.custoUnitario.toStringAsFixed(2)}',
                                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 6),
                                  _SeletorAcaoMensagem(
                                    valor: item.acaoMensagem,
                                    onChanged: (acao) => setState(() => item.acaoMensagem = acao),
                                    quantidadeDesejadaController: item.quantidadeDesejadaController,
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () => _ignorarNaoCadastrado(item),
                                        icon: const Icon(Icons.close, size: 18),
                                        label: const Text('Ignorar'),
                                      ),
                                      const SizedBox(width: 4),
                                      FilledButton.tonal(
                                        onPressed: () => _cadastrarProdutoNaoCatalogado(item),
                                        child: const Text('Cadastrar'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                _secao(
                  titulo: 'Sem divergência',
                  explicacao: 'Bateu certinho com o que foi pedido.',
                  cor: colorScheme.outline,
                  itens: porCategoria[CategoriaConferencia.semDivergencia] ?? [],
                  expandidoPorPadrao: false,
                ),
                TextButton.icon(
                  onPressed: _adicionarItemNaoPedido,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Registrar item que chegou sem ter sido pedido'),
                ),
                const SizedBox(height: 24),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    title: const Text('Pedir ajuste ao fornecedor', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text(
                      'Marque uma ação nos itens acima (ou adicione item novo) e gere a mensagem de WhatsApp.',
                      style: TextStyle(fontSize: 12),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    children: [
                      for (final novo in _itensNovosMensagem)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: novo.nomeController,
                                  decoration: const InputDecoration(labelText: 'Produto novo (nome)', isDense: true),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: novo.quantidadeController,
                                  decoration: const InputDecoration(labelText: 'Qtd.', isDense: true),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => _removerItemNovoMensagem(novo),
                              ),
                            ],
                          ),
                        ),
                      TextButton.icon(
                        onPressed: _adicionarItemNovoMensagem,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Adicionar item novo (não cadastrado ainda)'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _enviarMensagemAjuste,
                        icon: const Icon(Icons.chat_outlined),
                        label: const Text('Gerar mensagem de ajuste (WhatsApp)'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _salvando ? null : _salvarConferencia,
                  icon: _salvando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: Text(_salvando ? 'Salvando...' : 'Salvar conferência'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                ),
              ],
            ),
    );
  }
}

class _ChipAnexo extends StatelessWidget {
  final AnexoEspelho anexo;
  final VoidCallback onRemover;

  const _ChipAnexo({required this.anexo, required this.onRemover});

  Future<void> _abrir(BuildContext context) async {
    try {
      await launchUrl(Uri.parse(anexo.url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível abrir o anexo: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: Icon(anexo.tipo == 'pdf' ? Icons.picture_as_pdf_outlined : Icons.image_outlined, size: 18),
      label: Text(anexo.nomeArquivo, overflow: TextOverflow.ellipsis),
      onPressed: () => _abrir(context),
      onDeleted: onRemover,
    );
  }
}

class _LinhaConferencia extends StatefulWidget {
  final _ItemConferencia item;
  final VoidCallback onMarcarSubstituto;

  /// null quando o produto não tem vínculo com ESTE fornecedor (ou nunca
  /// foi vinculado) — sem faixas de desconto pra mostrar nem pra registrar.
  final ProdutoFornecedor? vinculo;
  final VoidCallback onRegistrarFaixaDesconto;

  const _LinhaConferencia({
    required this.item,
    required this.onMarcarSubstituto,
    required this.vinculo,
    required this.onRegistrarFaixaDesconto,
  });

  @override
  State<_LinhaConferencia> createState() => _LinhaConferenciaState();
}

class _LinhaConferenciaState extends State<_LinhaConferencia> {
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final colorScheme = Theme.of(context).colorScheme;

    // Marcado como "tudo certo" recolhe pro resumo de 1 linha — numa lista
    // grande, conferir item por item e ir marcando limpa a tela conforme
    // avança, em vez de ter que rolar por tudo de novo toda vez.
    if (item.revisadoOk) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: CheckboxListTile(
          value: true,
          onChanged: (_) => setState(() => item.revisadoOk = false),
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            item.original.produtoNome,
            style: TextStyle(decoration: TextDecoration.lineThrough, color: colorScheme.onSurfaceVariant),
          ),
          subtitle: Text('${item.quantidadeConfirmadaAtual}un a R\$ ${item.custoConfirmadoAtual.toStringAsFixed(2)}'),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(value: item.revisadoOk, onChanged: (v) => setState(() => item.revisadoOk = v ?? false)),
                Expanded(
                  child: Text(item.original.produtoNome, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            if (!item.naoEstavaNoPedido)
              Text(
                'Pedido: ${item.original.quantidadePedida}un a R\$ ${item.original.custoUnitario.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
            if (item.quantidadeMudou || item.precoMudou)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.quantidadeMudou) _linhaMudanca('Quantidade', item.original.quantidadePedida.toString(), item.quantidadeConfirmadaAtual.toString(), item.quantidadeConfirmadaAtual > item.original.quantidadePedida),
                    if (item.precoMudou) _linhaMudanca('Preço', 'R\$ ${item.original.custoUnitario.toStringAsFixed(2)}', 'R\$ ${item.custoConfirmadoAtual.toStringAsFixed(2)}', item.custoConfirmadoAtual > item.original.custoUnitario),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: item.confirmadoController,
                    decoration: const InputDecoration(labelText: 'Confirmado', isDense: true),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: item.custoController,
                    decoration: const InputDecoration(labelText: 'Custo (R\$)', isDense: true),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            if (widget.vinculo != null) _dicaFaixaDesconto(widget.vinculo!, item),
            const SizedBox(height: 6),
            item.produtoSubstitutoNome != null
                ? Chip(
                    label: Text('Veio: ${item.produtoSubstitutoNome}', overflow: TextOverflow.ellipsis),
                    onDeleted: () => setState(() {
                      item.produtoSubstitutoId = null;
                      item.produtoSubstitutoNome = null;
                    }),
                  )
                : Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: widget.onMarcarSubstituto,
                      child: const Text('Veio outro produto?'),
                    ),
                  ),
            const Divider(height: 16),
            _SeletorAcaoMensagem(
              valor: item.acaoMensagem,
              onChanged: (acao) => setState(() => item.acaoMensagem = acao),
              quantidadeDesejadaController: item.quantidadeDesejadaController,
              exibirCampoQuantidade: false,
            ),
          ],
        ),
      ),
    );
  }

  /// Mesma dica "peça mais Nun e economize R$X" já usada na Sugestão de
  /// Compra, agora também aqui — onde a negociação com o fornecedor
  /// realmente acontece. Botão "Registrar" fica sempre disponível (mesmo
  /// sem faixa melhor à frente), pra guardar uma condição nova que o
  /// fornecedor acabou de conceder na conversa.
  Widget _dicaFaixaDesconto(ProdutoFornecedor vinculo, _ItemConferencia item) {
    final proxima = vinculo.proximaFaixa(item.quantidadeConfirmadaAtual);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: proxima == null
                ? const SizedBox.shrink()
                : Text(
                    'Peça mais ${proxima.unidadesFaltando}un e economize R\$${proxima.economiaPorUnidade.toStringAsFixed(2)}/un',
                    style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w600),
                  ),
          ),
          TextButton(
            onPressed: widget.onRegistrarFaixaDesconto,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Registrar faixa de desconto', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _linhaMudanca(String rotulo, String de, String para, bool subiu) {
    // Preço/quantidade que sobe custa mais caro pro negócio (vermelho);
    // que desce é bom pro negócio (verde) — cores fixas de propósito, não
    // seguem o tema claro/escuro do error/tertiary porque aqui o sentido é
    // sempre "ruim"/"bom" em qualquer tema, não uma categoria neutra.
    final cor = subiu ? Colors.red.shade700 : Colors.green.shade700;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(subiu ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: cor),
          const SizedBox(width: 4),
          Text('$rotulo: $de → $para', style: TextStyle(fontSize: 12, color: cor, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

