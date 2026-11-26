// Faixa "Nova versão · Atualizar" (26/11). Sem o service worker do Flutter o navegador já baixa a
// versão nova ao recarregar, mas quem fica com a tela aberta (motoboy na rota, loja no painel)
// continuaria na antiga. A cada 3 min compara /versao.txt (gravado no publicar_web.sh) com a
// versão compilada (--dart-define=APP_VERSAO). Fora da web não faz nada.
export 'nova_versao/nova_versao_nativo.dart' if (dart.library.js_interop) 'nova_versao/nova_versao_web.dart';
