{{flutter_js}}
{{flutter_build_config}}
// Sem service worker (26/11): com ele o celular ficava preso na versão antiga até recarregar 2×
// (motoboy com a rota aberta nunca atualizava). O flutter_service_worker.js publicado agora só
// apaga o cache antigo de quem ainda tem (ver scripts/publicar_web.sh).
_flutter.loader.load();
