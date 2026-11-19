# Entregador por oferta no WhatsApp — desenho (19/11/2026)

Status: **regras aprovadas pelo Lucas em 19/11**; implementação ainda não começou.
Base: app do entregador (Kitsune, `entregador-app`) + tabelas `entregadores`, `rotas_entrega`, `rota_pedidos`.

## Objetivo
Motoboys freelancers (moto própria, trabalham em apps, não ficam presos na loja) recebem
automaticamente no WhatsApp a oferta de entrega. O primeiro que aceita fica com a rota; tudo
que cair até ele **sair da loja** entra na rota dele e o valor sobe. Ninguém aceitou ou ele não
chegou a tempo → aviso pro Lucas, que entrega.

## Regras de negócio (aprovadas)
1. **Gatilho:** pedido com entrega própria (site, loja/WhatsApp, iFood DELIVERY, 99Food) entra
   na fila → se não houver rota aberta, cria rota em estado `ofertada` e dispara a oferta.
2. **Aceite:** oferta vai pra todos os entregadores freelancers ativos ao mesmo tempo. O 1º
   "Aceito" leva (trava atômica no banco: `update ... where status='ofertada' returning`). Os
   demais recebem "essa rota já foi".
3. **Rota cresce:** enquanto a rota estiver `ofertada` ou `aceita` (ele a caminho / na loja),
   todo pedido novo de entrega entra nela. Sem limite de pedidos — ele decide o que cabe.
   Botão opcional **"Rota cheia"**: pedidos seguintes abrem rota nova.
4. **Fecha** quando ele marca **"Saí"**. Pedido depois disso → rota nova.
5. **Prazo de saída** = o mais apertado entre os pedidos da rota:
   `fim da promessa do pedido − tempo de rota da loja até aquela parada − 5 min de tolerância`.
   Promessa: `previsao_entrega_fim` (zona) ou `entrega_prevista_fim` (iFood). Tempo de rota:
   Google Distance Matrix (mesma base de `cliente.estimativaEntrega` / "Sair até").
   Se um pedido novo encurta o prazo, ele é avisado ("sair até 14h22, antes era 14h30").
6. **Sem entregador:** ninguém aceitou até `prazo de saída − tempo médio de chegada` ou o
   aceitante não chegou/saiu até o prazo → notificação pro Lucas (push + WhatsApp) e a rota
   volta pra loja (Lucas entrega). Aceitante que estourou o prazo perde a rota.
7. **Valor (fase de teste):** `R$ 4 de saída + R$ 1,00 por km de IDA + R$ 2 por parada extra`.
   Km = rota de entrega otimizada loja → paradas, **sem volta**. Ajustar depois de 2 semanas
   pela taxa de aceite (tempo até aceitar, % de ofertas sem aceite).
   **O entregador só vê o valor final da rota** — nunca a fórmula, base, km ou valor por parada.
   A fórmula fica só no Gestor (Configurações, só dono).
8. **Pedido que não paga a própria entrega:** se `lucro antes da entrega < custo marginal que o
   pedido acrescenta`, não oferta sozinho — avisa o Lucas pra decidir (entregar ele mesmo ou
   esperar juntar).

## Pagamento na entrega
- **Pago antes (site/MP, iFood, 99):** "JÁ PAGO — NÃO COBRAR" (regra atual de `mensagem_entregador.dart`).
- **Cartão na entrega:** motoboy cobra no **celular dele** via Mercado Pago **Colaboradores +
  Tap to Pay (iPhone) / Point Tap (Android NFC)** — cai na conta da loja, ele não vê saldo.
  Só aproximação; sem aproximação → Pix/link. **Testar com 1 motoboy antes.**
  Opcional: mandar link de pagamento/Pix ao cliente antes da saída (testar aceitação).
- **Dinheiro:** fica com o motoboy e é abatido do acerto (rota R$ 30, recebeu R$ 80 → ele
  repassa R$ 50). Motoboy novo só leva pedido em dinheiro depois de algumas rotas sem problema.

## Código de entrega (marketplace)
- iFood: já existe `confirmarComCodigo` → `pedidos.codigo_confirmacao_*` → n8n
  (`integrations/n8n/ifood-codigo-confirmacao.json`) valida na API. No link da rota, campo
  "código do cliente" por parada, mesmo caminho. Parada só fica "entregue" com código aceito.
- 99Food: **conferir na documentação da 99** se há código e endpoint equivalentes.

## Mensagens (WhatsApp Cloud API)
Mensagem iniciada pela loja precisa de **modelo aprovado pela Meta** (categoria utilidade),
com botões de resposta rápida.
- Oferta: `🛵 Entrega Delivery Pet · {n} entrega(s) · {bairros} · R$ {valor} · chegar na loja até {hh:mm}` [Aceito] [Não dá]
- Aceito: `Rota é sua! Chegue até {hh:mm}. O valor aumenta a cada pedido que entrar até você sair.` + link
- Já foi: `Essa rota já foi pega. Te aviso na próxima!`
- Pedido entrou: `+1 na sua rota · agora {n} entregas · R$ {valor}` (+ `⚠️ sair até {hh:mm}` se mudou)
- Lucas: `Rota sem entregador · {n} pedidos · sair até {hh:mm}`

## Link da rota (motoboy)
Página web leve com token de uso único por rota (sem instalar app); quem já usa o Kitsune vê no
app. Mostra: paradas na ordem, navegar, o que cobrar, campo de código, entregue/não entregue,
botões "Rota cheia" e "Saí". Ao finalizar, grava o valor da rota em `rotas_entrega` e o
`custo_alocado` por pedido em `rota_pedidos` (atualiza `pedidos.custo_entrega_valor` → lucro real).

## Acerto com o motoboy
Extrato por entregador: rotas, valor, dinheiro recebido, saldo a pagar. Pagamento por Pix
(dia/semana). Freelancer: sem horário, sem exclusividade, pode recusar à vontade.

## Dados de base (30 dias até 19/11)
~10 pedidos com entrega/dia; 41% caem sozinhos (sem outro em 20 min). Lucro médio antes da
entrega: iFood R$ 30,75 · site R$ 28,31 · loja R$ 34,72 (25% mais fracos ~R$ 16–20).
Distância mediana de ida: iFood 4,3 km · site 3,0 km · loja 1,3 km. Custo antigo real
(R$ 5 + moto ida/volta) numa entrega de 4,3 km ≈ R$ 8,50–9.

## A conferir antes de implementar
- Conversar com 1–2 motoboys sobre o valor (sem mostrar a fórmula).
- Teste real do Tap to Pay como colaborador.
- Código de entrega da 99Food.
- Modelos de mensagem aprovados pela Meta.
