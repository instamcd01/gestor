# Automação conversacional via WhatsApp — plano de implementação

## Contexto

O usuário definiu um framework estratégico completo (42 seções) para guiar
toda decisão futura de automação de atendimento/vendas via WhatsApp deste
projeto — resumo em memória (`gestor_whatsapp_automacao_conversacional`),
não repetido aqui. Este documento é o plano de implementação derivado
desse framework, escrito depois de uma auditoria real (não suposição) do
n8n (`n8n.lukz.com.br`) e do schema Supabase (`dwswpwxnzjgoohucngbb`)
em 12/08/2026.

**Achado que define o ponto de partida**: já existe um pipeline de
atendimento por WhatsApp em produção — Chatwoot (self-hosted) recebe as
mensagens, dispara webhook pro n8n, que roda uma cadeia de 3 workflows
ativos (`01 - Chatwoot WhatsApp Router` → `02 - Processar Mensagem` → `03
- Interpretar Intencao v2`). O funil hoje só cobre Descoberta/Interesse
(saudação, consulta — quando não quebrada — e transferência humana). Os 3
workflows seguintes do pipeline original (`04 - Busca Produtos`, `05 -
Carrinho`, `06 - Checkout`) nunca foram construídos (stub vazio).
Decisão tomada (autorização do usuário: "se achar que dá pra usar como
base tudo bem, mas pode desenvolver do zero se achar melhor"): **reaproveitar
01/02, evoluir 03, não reconstruir carrinho/checkout dentro do
WhatsApp** — ver seção "Decisão de arquitetura" abaixo para o porquê.

## Objetivo (classificação segundo a seção 2 do framework)

Este projeto mira, nesta ordem de prioridade:
1. **Reduzir tempo de atendimento / custo operacional** — hoje perguntas
   simples de catálogo ainda podem cair no humano por causa do bug do
   filtro de estoque.
2. **Aumentar conversão** — cliente que pergunta preço/disponibilidade e
   não recebe resposta útil desiste. Ponte pro carrinho fecha esse gap.
3. **Aumentar recompra/retenção** — já parcialmente resolvido (lembrete de
   recompra por ciclo de produto, ver `gestor_loja_petcash_cashback.md`
   Fase 2); falta cobrir carrinho abandonado e atendimento abandonado.
4. **Reduzir erros / melhorar controle** — hoje o bot pode responder
   "não encontrei" pra um produto que existe (bug), o que corrói confiança
   no canal.
5. **Preparar pro SaaS** (seção 37/38) — `empresa_id`/`assignee_id`
   hardcoded no pipeline atual são o principal bloqueio pra isso; tratado
   na Fase 0.

## Decisão de arquitetura: um agente com ferramentas, não dez agentes

A seção 21 do framework é explícita: multiagente só quando há benefício
arquitetural real, nunca por complexidade. Avaliando os "agentes
especializados" sugeridos contra o que esse negócio realmente precisa
agora:

- **Agente de Atendimento + Vendas + Produtos + CRM**: cabem em **um único
  agente conversacional** (LLM com tool-calling, não o padrão atual de
  "classifica intenção → switch → texto fixo"). O ganho de trocar o
  switch por um agente com ferramentas: hoje o bot não consegue responder
  "tem ração X e quanto custa a entrega pro Leblon?" numa mensagem só,
  porque cada intenção é uma rota isolada. Um agente com ferramentas
  (`buscar_produto`, `consultar_zona_entrega`, `buscar_contexto_cliente`,
  `gerar_link_carrinho`, `transferir_humano`) encadeia o que for
  necessário na mesma resposta, e é exatamente o padrão de "aplicação
  invisível" da seção 5.
- **Agente de Logística**, **Agente de CRM**: não precisam ser workflows
  n8n separados — viram **ferramentas** (tools) do agente único acima,
  cada uma uma chamada Supabase/RPC real. Separar em subworkflows só
  adicionaria latência e superfície de erro sem ganho.
- **Agente de Retenção / Pós-venda**: esses SIM continuam sendo workflows
  n8n separados, porque o gatilho é diferente (tempo/evento, não uma
  conversa em andamento) — o lembrete de recompra já existe assim
  (`Site - Enviar Lembrete de Recompra via WhatsApp`, Schedule Trigger
  diário) e o novo "carrinho abandonado" (Fase 4) segue o mesmo molde.
- **Agente de Pedidos** (montar carrinho/checkout dentro da conversa): **não
  construído dentro do WhatsApp.** Ver justificativa abaixo.

### Por que não reconstruir carrinho/checkout no WhatsApp

O site (`gestor-loja`) já tem carrinho, cupom, PetCash, frete por zona e
pagamento (Pix/cartão via Mercado Pago) — tudo testado e em produção.
Reimplementar essa lógica de negócio inteira dentro de uma conversa de
texto é o cenário de maior risco do projeto inteiro (dinheiro real,
estoque real, várias regras de desconto que já têm bug histórico
documentado neste projeto quando duplicadas). A seção 19 do próprio
framework já aponta a saída: "quando o site for melhor pro cliente e pra
operação, o WhatsApp pode atuar como ponte inteligente". Por isso a Fase 3
constrói uma **ponte** (link de carrinho pré-preenchido), não um
checkout paralelo.

## Arquitetura alvo

```
WhatsApp Cloud API
      │
      ▼
   Chatwoot (self-hosted) ──── mensagem recebida ────┐
      │                                                │
      │ (reutiliza como está, com fix de grants)      ▼
      │                                    01 · Router
      │                                    upsert cliente/conversa/mensagem
      │                                    empresa_id vem de config, não hardcoded
      │                                                │
      │                                                ▼
      │                                    02 · Processar Mensagem
      │                                    (multimodal: texto/imagem/pdf/áudio — mantém como está)
      │                                                │
      │                                                ▼
      │                            03 · Agente Conversacional (reconstrução)
      │                            Agent (LLM) + ferramentas:
      │                              - buscar_contexto_cliente (nome, pets, última compra, ciclo)
      │                              - buscar_produto (Supabase real, sem bug de coluna)
      │                              - consultar_zona_entrega (tabela real)
      │                              - gerar_link_carrinho (Fase 3)
      │                              - transferir_humano (mantém como está)
      │                            Memória: Simple Memory já existe, manter
      │                                                │
      ◄────────────────────── resposta ────────────────┘

Workflows agendados/orientados a evento, independentes da conversa:
  - Site - Enviar Lembrete de Recompra via WhatsApp   (já existe, ativo)
  - Carrinho Abandonado via WhatsApp                  (novo, Fase 4)
  - Atendimento Abandonado via WhatsApp               (novo, Fase 4, opcional)
```

## Fase 0 — Fundação (corrigir o que existe, antes de construir em cima)

Baixo risco, alto valor, destrava tudo o que vem depois. Sem isso, medir
qualquer melhoria das fases seguintes fica contaminado pelos bugs atuais.

1. **Corrigir o filtro de produto** em "Buscar Produto Supabase" (nó do
   workflow 03): `estoque.gt.0` referencia coluna inexistente em
   `produtos` (estoque é tabela relacionada). Trocar por um embed
   filtrado do PostgREST (`estoque.quantidade_atual=gt.0` via select
   aninhado) ou por uma RPC dedicada (preferível — ver Fase 2, essa RPC já
   vai precisar existir com mais campos).
2. **Handler de entrega**: trocar o texto fixo por uma consulta real a
   `zonas_entrega` (a mesma tabela que `ZonaEntregaProvider`/config do
   site já usa) — nunca deixar o bot dizer algo que diverge do que o
   checkout realmente cobra.
3. **Revogar grants soltos**: `anon` tem SELECT+INSERT em `conversas` e
   `mensagens` sem policy própria (inerte hoje porque RLS nega por
   padrão, mas por disciplina do projeto — ver
   `feedback_regras_gerais_engenharia_projeto` — deve ser revogado como
   qualquer objeto novo).
4. **Limpar nós órfãos**: remover as 2 cadeias "v1" desconectadas no
   workflow 03 e o `Knowledge Base Agent` órfão no workflow 01 — sujeira
   que só atrapalha manutenção futura (seção 23 do framework).
5. **Parametrizar `empresa_id`/`assignee_id`**: hoje hardcoded
   (`3bce0e24-...` / `assignee_id: 1`). Resolver dinamicamente (via
   `empresa_marketplace_config`-like lookup, ou uma tabela nova
   `empresa_chatwoot_config` com `account_id`/`inbox_id`/`assignee_id`
   por empresa) — não bloqueia o uso atual (só a Delivery Pet usa isso
   hoje), mas é o que separa "script que funciona pra um cliente" de
   "produto" (seção 37/38).

## Fase 1 — Memória do cliente / fricção mínima (seção 4 e 11 do framework)

Ferramenta nova `buscar_contexto_cliente`, chamada no início de toda
conversa (não só quando o cliente pergunta), injetando no contexto do
agente: nome, pets (espécie/porte), produtos com `ciclo_recompra_dias`
próximo do vencimento pra aquele cliente (mesma view já existente,
`v_produtos_prontos_recompra`/`v_clientes_prontos_recompra`), última
compra, saldo PetCash, segmento (`clientes.segmento`, já calculado).
Isso é o que transforma "Como posso ajudar?" em "Oi João! A ração do
Thor deve estar acabando, quer que eu confira?" (exemplo literal da seção
11) sem precisar perguntar nada que o sistema já sabe.

**Sem tabela nova** — todos os dados já existem (`clientes`, `pets`,
`v_produtos_prontos_recompra`, `catalogo_*_publico`). É só uma ferramenta
nova no agente.

## Fase 2 — Busca de produto real + venda consultiva (seções 7, 8, 16, 17)

Ferramenta `buscar_produto(termo, filtros?)`: busca real (nome + talvez
busca por categoria/necessidade, não só `ilike` — considerar full-text
search do Postgres se o `ilike` simples não performar bem em ~3600
produtos), retorna preço, estoque real (via join com `estoque`), presença
de promoção. **Nunca inventar** disponibilidade/preço (seção 16) — se a
ferramenta não achar, o agente diz que não achou, não especula.

Prompt do agente orientado a venda consultiva (seção 8): quando a busca
retornar mais de uma opção plausível (ex: "ração" sozinho, sem espécie/
porte), perguntar o mínimo necessário pra recomendar bem — nunca
interrogatório. Cross-sell (seção 9) fica pra uma iteração depois de
validar que a busca básica funciona bem — não empacotar tudo de uma vez
(risco de a primeira versão nunca sair do papel por escopo demais).

## Fase 3 — Ponte pedido → carrinho do site (implementa a decisão de arquitetura acima)

Ferramenta `gerar_link_carrinho(produtos: [{produto_id, quantidade}])`:
1. Nova RPC `criar_carrinho_pendente_whatsapp(p_cliente_id, p_itens)` —
   gera um token de curta duração (ex: tabela `carrinhos_whatsapp_pendentes`
   com `token`, `cliente_id`, `itens jsonb`, `expira_em`, mesmo padrão de
   expiração já usado em PetCash/OTP).
2. Nova rota no site `gestor-loja`:
   `/loja/[slug]/carrinho/retomar/[token]` — carrega os itens do token pro
   carrinho do cliente (mesmo mecanismo de `localStorage`/sessão que o
   carrinho normal já usa) e redireciona pro carrinho normal.
3. Agente responde com o link direto (`https://.../carrinho/retomar/{token}`)
   — o cliente termina no fluxo de checkout já validado e testado, sem
   nenhuma lógica de pagamento nova no WhatsApp.

Isso fecha o funil (seção 26) até PEDIDO/PAGAMENTO sem duplicar nenhuma
regra de negócio já existente.

## Fase 4 — Recuperação de oportunidades (seção 13)

Já existe: lembrete de recompra por ciclo de produto (ativo).
Novo, mesmo padrão (Schedule Trigger + view Postgres + template WhatsApp
aprovado pelo Meta):
- **Carrinho abandonado**: cliente gerou um `carrinho_whatsapp_pendente`
  (Fase 3) e não finalizou em N horas → lembrete com o link ainda válido.
- **Atendimento abandonado** (opcional, avaliar depois): conversa em
  `conversas.estado != 'atendente'` sem resposta do cliente por X tempo
  após o bot ter perguntado algo — usar as colunas `contexto`/
  `ultimo_fluxo` que já existem em `conversas` (não usadas por nenhum
  workflow ativo hoje — provavelmente a intenção original de quem
  desenhou o schema) pra saber em que ponto a conversa parou.

Regra da seção 14 (nunca virar spam) aplica a ambos: cooldown, opt-in
(`aceita_lembrete_whatsapp`, já existe e já é coletado no site e no app),
nunca mais de 1 lembrete por oportunidade sem uma nova interação do
cliente.

## Fase 5 — Segmentação e personalização (seções 12, 29)

`clientes.segmento` (novo/regular/vip/inativo) já é calculado
automaticamente (`calcular_segmento_cliente`, já em produção). Usar isso
no prompt do agente pra ajustar tom (novo cliente → mais explicativo e
acolhedor; VIP → direto ao ponto; inativo → tom de reconquista) sem
precisar de nenhuma automação nova — só contexto adicional na ferramenta
`buscar_contexto_cliente` da Fase 1.

## Fase 6 — Métricas (seção 27)

Os dados já ficam salvos (`conversas`, `mensagens`) — falta consumir.
Métricas mínimas viáveis com o que já existe: taxa de transferência pra
humano (`conversas.estado='atendente'` / total), volume de conversas por
dia, e — depois da Fase 3 — taxa de conversão conversa→carrinho gerado→
pedido pago (via o token de `carrinhos_whatsapp_pendentes`). Não construir
dashboard novo agora — se necessário, uma tela simples no app
(`Configurações > WhatsApp` ou similar) ou uma view SQL consultável
depois que houver volume real pra medir.

## Fase 7 — Visão SaaS (seções 37, 38)

Depois que a Fase 0 parametrizar `empresa_id`, o pipeline inteiro já fica
genérico o suficiente pra, em tese, atender outro petshop cliente da
plataforma. O que continua sendo config-por-empresa (não código): texto
do system prompt (nome da loja, tom), zona de entrega, templates
aprovados no Meta (cada empresa precisa da própria conta WhatsApp
Business). Não é escopo agora — só a lente a manter enquanto as fases
acima são construídas, pra não hardcodar de novo o que acabou de ser
generalizado.

## O que fica de fora por enquanto (decisão consciente, não esquecimento)

- Cross-sell/upsell ativo (seção 9) — só depois da busca básica validada.
- A/B testing de copy (seção 28) — sem volume de conversas reais ainda
  pra um teste ter significância.
- Multiagente "de verdade" (workflows separados por especialidade) — só
  se o agente único com ferramentas mostrar limite real de escala/latência.
- Reescrever `04/05/06` como estavam nomeados originalmente — a Fase 3
  cobre a necessidade real (fechar o funil) sem precisar de 3 workflows
  extras fazendo o que o site já faz.

## Ordem recomendada

Fase 0 é pré-requisito de tudo (o bot está com um bug ativo em produção
agora). Fases 1-3 formam o incremento de valor mais direto (contexto +
busca real + fechar o funil) e podem ser construídas em sequência dentro
da mesma leva de trabalho. Fases 4-6 dependem de volume real de conversas
pra fazer sentido medir, então vêm depois. Fase 7 é lente contínua, não
uma entrega isolada.

**Este plano ainda não foi executado** — é o documento de referência
criado antes de começar a construir, conforme pedido do usuário. Próxima
ação: confirmar com o usuário se começa por Fase 0 (correção do que já
está ativo em produção) e segue direto pras Fases 1-3, ou se ele quer
revisar/ajustar alguma decisão deste plano antes.
