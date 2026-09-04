# App do Entregador — Fase 1 (design aprovado)

## Contexto

O app "Gestor" (Flutter, staff) tem hoje um módulo de rotas de entrega (rotas_entrega, rota_pedidos) recém-lançado e validado: otimização de rota por distância real, reordenação manual, mapa com marcadores. Hoje quem controla o ciclo inteiro (montar rota, iniciar, avançar status de cada pedido, finalizar) é o funcionário da loja, dentro do app Gestor. "Entregadores" hoje são só registros de dados (nome, telefone, modo de custo) sem login/identidade própria — não existe nenhuma forma de um entregador acessar o sistema.

O usuário pediu explicitamente pra desenhar isso com a mesma lógica do app de entregador do iFood: rota pré-atribuída pela loja, mas o controle de iniciar/finalizar e cada parada passa a ser do próprio entregador, pelo celular dele.

Dado o tamanho do pedido completo (app do entregador + rastreio ao vivo pra loja + rastreio ao vivo pro cliente no site/WhatsApp), foi decidido dividir em 3 fases/specs sequenciais, cada uma testável isoladamente:
- **Fase 1 (este documento):** app do entregador funcionando ponta a ponta, SEM rastreio ao vivo.
- **Fase 2 (futura):** rastreio GPS ao vivo do entregador + mapa ao vivo pra loja acompanhar.
- **Fase 3 (futura):** rastreio ao vivo exposto pro cliente (site/WhatsApp), incluindo mensagem automática de "saiu para entrega" (que hoje não existe).

## Escopo da Fase 1

Dentro: login próprio do entregador, ver rota(s) do dia, iniciar rota, ver paradas em ordem, navegar (deep link pro Google Maps externo), marcar parada como entregue (com confirmação de pagamento quando pendente) ou não entregue (com motivo), finalizar rota, push notification quando uma rota nova é montada pra ele.

Fora (documentado, não construído agora): rastreio GPS contínuo, mapa ao vivo, rastreio pro cliente, foto de comprovante de entrega (avaliar como fast-follow se fizer falta na prática).

## Arquitetura

Projeto Flutter novo e separado do Gestor (staff) — não é uma view dentro do app atual. Mesma stack (Supabase + Provider), distribuído via Firebase App Distribution reaproveitando o mecanismo já configurado pro Gestor (novo app Android registrado no mesmo projeto Firebase `deliverypet-6d0e7`, ou projeto novo — decidir na implementação). App enxuto: só as telas que o entregador precisa, sem acesso a dados financeiros/de outros módulos do negócio.

## Identidade / login do entregador

Decisão de design (confirmada com o usuário): **não** misturar com a tabela `usuarios`/sistema de papéis de staff (dono/gerente/vendedor), que carrega permissões e visibilidade financeira. Em vez disso:

- Adicionar coluna `auth_user_id` (nullable, único) na tabela `entregadores` já existente.
- Convite gerado a partir da tela "Entregadores" do Gestor (já existe hoje, `entregadores_screen.dart`): dono/gerente escolhe um entregador cadastrado e gera um código (mesmo padrão de `convites_empresa`/`gerarConvite`, adaptado).
- Novo RPC (a criar), algo como `vincular_entregador_conta(p_codigo)`: valida o código, seta `entregadores.auth_user_id = auth.uid()` no registro correspondente. **Não** cria linha em `usuarios`.
- RLS novo em `rotas_entrega`/`rota_pedidos`/`pedidos` (pro contexto do entregador logado): acesso restrito a `entregador_id` cujo `entregadores.auth_user_id = auth.uid()`.
- Edge case aceito: se um entregador tentar logar por engano no app Gestor (staff) com essa conta, cai na tela de onboarding (criar empresa nova) porque não existe linha em `usuarios` — não é um buraco de segurança, só uma UX estranha nesse cenário raro.

## Modelo de dados — mudanças necessárias

- `entregadores`: `+ auth_user_id uuid unique null`, `+ fcm_token text null` (push é direto na própria entregadores, já que não tem `usuarios`).
- Novo RPC `vincular_entregador_conta(p_codigo)`.
- Novo(s) status de pedido: `nao_entregue` (adicionar à convenção livre de `pedidos.status`), motivo gravado em `pedidos.metadata.motivo_nao_entrega` (mesmo padrão já usado pra parcelamento/juros — reaproveita `pedido_status_historico` que já grava toda mudança de status via trigger existente).
- Reaproveitar RPC existente `confirmar_pagamento_entrega_loja_fisica` pra confirmação de pagamento na entrega (inspecionar assinatura exata na implementação, já que não está versionada no repo — vive só no Supabase).
- Reaproveitar `finalizar_rota_entrega` (sem mudança) e a lógica de otimização (`calcularRotaOtimizada`/`calcularRotaOrdemFixa`) hoje em `lib/services/distancia_service.dart` no Gestor — **duplicar** esse arquivo no app novo (decisão confirmada: extrair como pacote compartilhado seria over-engineering pra 2 apps só nesse estágio).
- Novo policy de convite — reaproveitar padrão de `convites_empresa`/`gerarConvite` mas escopado a um `entregador_id` específico em vez de um `papel` genérico.

## Fluxo principal (inspirado no iFood)

1. Login → tela "Minhas rotas de hoje" (pode haver mais de uma rota no dia).
2. Abre uma rota → lista de paradas numeradas (endereço, cliente, itens, forma de pagamento) — mesmo padrão visual de `rotas_entrega_screen.dart`/`rota_mapa_screen.dart` do Gestor.
3. Botão "Iniciar rota" — dispara o mesmo cálculo de otimização (`calcularRotaOtimizada`) hoje feito pela loja, agora chamado pelo entregador; seta `rotas_entrega.status = em_andamento`.
4. Por parada:
   - "Navegar" → deep link externo pro Google Maps (`url_launcher`, URL tipo `https://www.google.com/maps/dir/?api=1&destination=lat,lng&travelmode=driving`), sem navegação turn-by-turn embutida (não existe hoje no app, não é pra construir do zero agora).
   - "Entregue" → se pagamento pendente, pede confirmação (reaproveita `confirmar_pagamento_entrega_loja_fisica`); avança `pedidos.status` pra `entregue`.
   - "Não entregue" → menu de motivo (ausente / endereço não encontrado / recusou / outro com texto livre) → `pedidos.status = nao_entregue` + motivo em `metadata`.
5. Depois da última parada, "Finalizar rota" → RPC `finalizar_rota_entrega` (igual hoje).

## Notificações

Reaproveitar a infra de push já existente (trigger no banco + n8n `notificacao-push` + FCM), estendendo o alvo pra também considerar `entregadores.fcm_token` (hoje só olha `usuarios.fcm_token`). Evento: rota nova atribuída a um entregador.

## O que muda no Gestor (staff)

Tela de Rotas de Entrega continua existindo pra montar a rota (escolher pedidos + entregador). Os botões "Iniciar rota"/"Finalizar rota" viram leitura do status + um botão de override manual pra emergência (ex: celular do entregador sem bateria) — controle principal passa pro app novo.

## Fora de escopo (explícito)

Rastreio GPS ao vivo, mapa ao vivo pra loja, rastreio pro cliente (site/WhatsApp), mensagem automática de "saiu para entrega" pro cliente, foto de comprovante de entrega. Tudo isso fica documentado como Fase 2/3, a detalhar depois que a Fase 1 estiver validada com entregadores reais.

## Próximos passos

1. Usuário revisa este spec.
2. Invocar a skill `writing-plans` pra transformar isso num plano de implementação detalhado (arquivos a criar/mudar, ordem, RLS/migrations, etc.) antes de começar a codar.
