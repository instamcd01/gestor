import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../models/notificacao.dart';
import '../providers/notificacao_provider.dart';
import '../providers/produto_provider.dart';
import '../repositories/conteudo_guia_repository.dart';
import '../repositories/notificacao_repository.dart';
import '../screens/avaliacoes_disputas_screen.dart';
import '../screens/campanhas_ativacao_screen.dart';
import '../screens/cliente_screen.dart';
import '../screens/conversas_whatsapp_screen.dart';
import '../screens/despesas_screen.dart';
import '../screens/dicas_site_screen.dart';
import '../screens/editar_produto_screen.dart';
import '../screens/fila_pedidos_screen.dart';
import '../screens/importar_nota_fiscal_screen.dart';
import '../screens/produtos_screen.dart';

/// Navigator do MaterialApp — o toque no push/aviso do desktop chega fora de
/// qualquer tela, então precisa navegar sem um BuildContext próprio.
final navigatorKey = GlobalKey<NavigatorState>();

/// Pra onde a notificação leva quando tocada — por `tipo`, não por
/// `entidadeTipo`, porque o mesmo entidadeTipo ('pedido') serve tanto pra
/// pedido parado quanto pra avaliação/disputa, que têm telas diferentes.
Widget? _telaRelacionada(String tipo) {
  switch (tipo) {
    case TipoNotificacao.estoqueBaixo:
    case TipoNotificacao.estoqueZerado:
    case TipoNotificacao.syncFalhou:
    case TipoNotificacao.custoAlterado:
      return ProdutosScreen();
    case TipoNotificacao.pedidoParado:
    case TipoNotificacao.pedidoHoraSaidaEntrega:
    case TipoNotificacao.pedidoAtrasadoEntrega:
      return const FilaPedidosScreen();
    case TipoNotificacao.despesaVencendo:
    case TipoNotificacao.despesaVencida:
      return const DespesasScreen();
    case TipoNotificacao.avaliacaoRecebida:
    case TipoNotificacao.disputaRecebida:
    case TipoNotificacao.disputaPrazoVencendo:
      return const AvaliacoesDisputasScreen();
    case TipoNotificacao.carrinhoAbandonado:
      return const CampanhasAtivacaoScreen();
    case TipoNotificacao.clienteAtivoNoSite:
      return ClientesScreen();
    case TipoNotificacao.nfePendente:
      return const ImportarNotaFiscalScreen();
    case TipoNotificacao.erroSistema:
      // Sem tela própria — a mensagem já vem com a rota do site onde o
      // erro aconteceu; investigar é olhar o código, não navegar no app.
      return null;
    default:
      return null;
  }
}

/// Abre a tela da notificação — a mesma regra pra lista de notificações,
/// push (Android/navegador) e aviso do desktop.
Future<void> abrirNotificacao({required String tipo, String? entidadeId}) async {
  final navegador = navigatorKey.currentState;
  final contexto = navigatorKey.currentContext;
  if (navegador == null || contexto == null) return;

  // Falha de sincronização é sobre UM produto específico — leva direto pra
  // edição dele (onde "Disponibilidade em Marketplaces" mostra o motivo
  // completo, sem cortar) em vez de largar o usuário na lista inteira pra
  // caçar qual produto falhou. Cai pro fallback genérico se o produto não
  // estiver carregado localmente por algum motivo.
  if (tipo == TipoNotificacao.syncFalhou && entidadeId != null) {
    final produto = contexto.read<ProdutoProvider>().getProdutoPorId(entidadeId);
    if (produto != null) {
      navegador.push(MaterialPageRoute(builder: (_) => EditarProdutoScreen(produto: produto)));
      return;
    }
  }

  // Dica nova do site: direto na tela de revisão/aprovação daquela dica.
  if (tipo == TipoNotificacao.guiaRascunho && entidadeId != null) {
    final guia = await ConteudoGuiaRepository().buscar(entidadeId).catchError((_) => null);
    if (guia != null) {
      navegador.push(MaterialPageRoute(builder: (_) => DicaDetalheScreen(guia: guia)));
      return;
    }
  }

  // Atendente virtual chamou o dono: abre a conversa (resumo do pedido + rascunho).
  if (tipo == TipoNotificacao.whatsappAtendimento) {
    navegador.push(MaterialPageRoute(
      builder: (_) => entidadeId != null ? ConversaWhatsappScreen(conversaId: entidadeId) : const ConversasWhatsappScreen(),
    ));
    return;
  }

  final tela = _telaRelacionada(tipo);
  if (tela != null) navegador.push(MaterialPageRoute(builder: (_) => tela));
}

/// Toque no push: só o id vem na mensagem — busca tipo/entidade, marca como
/// lida e abre a tela.
Future<void> abrirNotificacaoPorId(String id, NotificacaoProvider provider) async {
  try {
    final linha = await supabase.from('notificacoes').select('tipo, entidade_id').eq('id', id).maybeSingle();
    if (linha == null) return;
    await NotificacaoRepository().marcarComoLida(id);
    provider.carregar();
    await abrirNotificacao(tipo: linha['tipo'] as String, entidadeId: linha['entidade_id'] as String?);
  } catch (e) {
    debugPrint('Erro ao abrir notificação tocada: $e');
  }
}
