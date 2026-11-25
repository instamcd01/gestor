#!/usr/bin/env bash
# Publica o Gestor (INARI) web em gestor.deliverypetexpress.com.br.
#
# Compila aqui (a VPS tem só 2 núcleos — build Flutter lá pesa) e envia só os
# arquivos prontos pro ramo `web-deploy`, que o serviço gestor-web do
# Easypanel usa (Dockerfile com nginx, sem compilar nada). Depois do push,
# o Easypanel implanta sozinho (implantação automática ligada em 25/11).
#
# Uso: bash scripts/publicar_web.sh
set -euo pipefail

raiz="$(cd "$(dirname "$0")/.." && pwd)"
cd "$raiz"

# --no-tree-shake-icons: flutter_icons_null_safety cria IconData não-constante.
flutter build web --release --no-tree-shake-icons

origem_commit="$(git rev-parse --short HEAD)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cp -r build/web "$tmp/web"

cat > "$tmp/Dockerfile" <<'EOF'
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY web /usr/share/nginx/html
EOF

cat > "$tmp/nginx.conf" <<'EOF'
server {
  listen 80;
  root /usr/share/nginx/html;

  gzip on;
  gzip_types text/plain text/css application/javascript application/json application/wasm image/svg+xml;
  gzip_min_length 1024;

  # Arquivos do Flutter web não têm hash no nome (main.dart.js, etc.):
  # sempre revalida, senão o navegador fica com a versão velha depois de publicar.
  add_header Cache-Control "no-cache";

  location / {
    try_files $uri $uri/ /index.html;
  }
}
EOF

cd "$tmp"
git init -q
git checkout -q -b web-deploy
git add -A
git -c user.name="$(git -C "$raiz" config user.name)" -c user.email="$(git -C "$raiz" config user.email)" \
  commit -q -m "Gestor web a partir de ${origem_commit}"
git push -f -q "$(git -C "$raiz" remote get-url origin)" web-deploy
echo "Publicado no ramo web-deploy (origem ${origem_commit})."

# 25/11: "Implantação automática" ligada no serviço gestor-web do Easypanel: o push acima já
# coloca no ar sozinho (~1 min). Confere se o arquivo novo chegou no site.
for _ in $(seq 1 12); do
  if curl -fsS -m 15 "https://gestor.deliverypetexpress.com.br/main.dart.js?v=$RANDOM" | cmp -s - build/web/main.dart.js; then
    echo "No ar: gestor.deliverypetexpress.com.br já entrega esta versão."
    exit 0
  fi
  sleep 10
done
echo "AVISO: em 2 min o site ainda não mostrou a versão nova. Confira o gestor-web no Easypanel (Implantações)."
