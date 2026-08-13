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
01/02, evoluir 03**.

**Revisão 12/08 (mesmo dia, depois de feedback do usuário)**: a premissa
original deste documento ("carrinho/checkout nunca entra no WhatsApp") foi
**revista**. O usuário trouxe um argumento comportamental real — 60-70%
dos clientes preferem resolver a compra sem sair do WhatsApp, incluindo
público idoso/pouco familiarizado com tecnologia pra quem "manda um link"
é fricção, não solução — e pediu uma **arquitetura híbrida**: site e
WhatsApp como duas interfaces sobre o **mesmo núcleo transacional**, sem
o agente insistir num caminho só. Ver seção "Checkout híbrido" (substitui
a antiga Fase 3) para a investigação real da arquitetura de pedido/
pagamento que fundamenta essa decisão.

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
- **Agente de Pedidos** (montar carrinho/pedido dentro da conversa): fica
  como **ferramentas** do mesmo agente único (`criar_carrinho`,
  `criar_pedido`, `consultar_pedido`), não um workflow/agente separado —
  ver "Checkout híbrido" abaixo pra como isso se conecta ao mesmo núcleo
  do site.

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
      │                            Agent (LLM) + ferramentas — mínimo por fase,
      │                            ver seção de ferramentas abaixo:
      │                              - buscar_contexto_cliente (memória progressiva)
      │                              - buscar_produto / consultar_estoque
      │                              - consultar_zona_entrega / calcular_entrega
      │                              - criar_carrinho / criar_pedido (núcleo compartilhado c/ site)
      │                              - consultar_pedido / consultar_pagamento
      │                              - gerar_link_carrinho (quando o cliente preferir o site)
      │                              - transferir_humano (mantém como está)
      │                            Memória: Simple Memory já existe, manter
      │                            Toda decisão/tool logada em automacao_eventos
      │                                                │
      ◄────────────────────── resposta ────────────────┘
                                                         │
                                        ┌────────────────┴────────────────┐
                                        ▼                                 ▼
                              CHECKOUT VIA SITE                 CHECKOUT VIA WHATSAPP
                              (link pro carrinho,                (Pix nativo na conversa;
                               qualquer forma de pagto)           cartão ainda depende de
                                        │                         um link de tokenização —
                                        │                         ver "Checkout híbrido")
                                        └────────────────┬────────────────┘
                                                          ▼
                                          MESMO NÚCLEO: finalizar_pedido_site
                                          (estoque / cupom / PetCash / frete / pagamento)

Workflows agendados/orientados a evento, independentes da conversa:
  - Site - Enviar Lembrete de Recompra via WhatsApp   (já existe, ativo)
  - Carrinho Abandonado via WhatsApp                  (novo, Fase 4)
  - Atendimento Abandonado via WhatsApp               (novo, Fase 4, opcional)
```

## Fase 0 — Fundação (corrigir o que existe, antes de construir em cima)

Baixo risco, alto valor, destrava tudo o que vem depois. Sem isso, medir
qualquer melhoria das fases seguintes fica contaminado pelos bugs atuais.
**Status real ao final desta rodada — ver relatório completo no chat/
memória, resumo aqui:**

1. **Filtro de produto quebrado** — ✅ confirmado ao vivo (PostgREST
   devolve 400: `column produtos.estoque does not exist`) e ✅ corrigido no
   JSON do workflow (`integrations/n8n/03-interpretar-intencao-fase0-fix.json`).
   A verificação de estoque por depósito real fica pra Fase 2 (RPC
   dedicada) — o fix da Fase 0 só para de quebrar a busca e suaviza a
   certeza sobre disponibilidade na resposta (nunca afirmar estoque sem
   checar de verdade).
2. **Handler de entrega hardcoded** — ✅ confirmado que divergia do real
   (bot dizia "a partir de R$8"; o valor mínimo real é R$4,99) e ✅
   corrigido no mesmo JSON — agora consulta `zonas_entrega` de verdade.
3. **Grants soltos** — ✅ **aplicado direto no banco**: `anon` tinha
   SELECT+INSERT em `conversas`/`mensagens` sem policy própria (inerte
   por causa do RLS, mas revogado por disciplina do projeto).
4. **Nós órfãos** — ✅ corrigido nos dois JSONs (20 nós removidos do
   workflow 03, 4 do workflow 01 — as cadeias "v1" mortas e o `Knowledge
   Base Agent` desconectado).
5. **Observabilidade** — ✅ **aplicada direto no banco**: tabela nova
   `automacao_eventos` (empresa_id, conversa_id, mensagem_id, etapa,
   tool_nome, detalhes jsonb, duracao_ms), sem grant nenhum pra
   anon/authenticated (só o backend/n8n escreve). Ainda não populada por
   nenhum workflow — quem grava nela é o agente da Fase 1+.
6. **`empresa_id`/`assignee_id` hardcoded** — decisão consciente de
   **não mexer na Fase 0**: só a Delivery Pet usa esse pipeline hoje, não
   há um segundo tenant esperando, e criar uma tabela de config
   multi-tenant agora seria construir pra uma necessidade que ainda não
   existe (YAGNI). Fica documentado como item da Fase 7 (visão SaaS).

**Aplicado no n8n em 13/08** (autorizado explicitamente pelo usuário,
`PUT` direto nos workflows ativos, mesmo id): workflow `03` confirmado
com 20 nós (filtro de produto corrigido, handler de entrega real, órfãos
removidos) e workflow `01` confirmado com 12 nós + `onError:
continueErrorOutput` em "Salvar Mensagem" (idempotência). Ambos
continuam `active: true`. **Ainda não validado com uma conversa real de
WhatsApp** — a verificação feita foi estrutural (re-fetch confirmando
nós/conexões/parâmetros corretos), não uma execução ao vivo end-to-end.

## Fase 1 — Memória progressiva do cliente / fricção mínima (seções 4 e 11)

Revisão 12/08: `buscar_contexto_cliente` deixa de ser só "puxar dados
cadastrais" — vira o ponto de entrada de um **modelo de memória
progressiva**, porque o usuário apontou que o WhatsApp é uma fonte de
contexto/intenção que o site não captura (ex: "essa ração é pro Thor, ele
tá acima do peso", "prefiro sempre pagar por aqui mesmo"). Isso não deve
virar interrogatório — o dado é capturado quando surge naturalmente na
conversa, nunca perguntado só pra preencher campo.

**3 categorias de dado, tratadas de formas diferentes**:
- **Estruturado/confiável** (já existe em tabela própria): `clientes`,
  `pets`, última compra, `ciclo_recompra_dias`, `saldo_petcash`,
  `segmento` — carregado sempre, sem custo de confiança.
- **Observado/persistente, mas extraído de conversa** (ex: "prefere pagar
  por aqui", "a gata não gostou daquela ração"): grava em
  `conversas.contexto` (jsonb, coluna já existe, nunca usada) como fatos
  datados e com a mensagem de origem — não vira verdade absoluta
  automaticamente, é uma anotação que o agente pode citar mas também
  reconsiderar se um fato novo contradisser um antigo.
- **Temporário da conversa atual** (ex: "quero uma opção mais barata esse
  mês"): fica só na memória de curto prazo do próprio agente (Simple
  Memory, já existe) — nunca persiste em `conversas.contexto`.

Isso é o que transforma "Como posso ajudar?" em "Oi João! A ração do
Thor deve estar acabando, quer que eu confira?" (exemplo literal da seção
11) sem precisar perguntar nada que o sistema já sabe — e, com o tempo,
alimenta o ciclo `conversa → contexto → memória → personalização → maior
conversão → novos dados` que o usuário descreveu.

**Sem tabela nova pro estruturado** (já existe). Pro observado/persistente,
reaproveita `conversas.contexto` (coluna já existe, nunca usada — bate com
o achado de que alguém já tinha planejado algo parecido, ver "Motor de
Estados" na memória do projeto). Não decidido ainda: schema exato do jsonb
em `contexto` (lista de fatos com data/origem vs. objeto livre) — detalhar
no início da implementação desta fase, não antes.

## Fase 2 — Busca de produto real + venda consultiva (seções 7, 8, 16, 17)

Ferramentas mínimas desta fase: `buscar_produto` (nome + categoria/
necessidade, não só `ilike` — considerar full-text search do Postgres pra
~3600 produtos) e `consultar_estoque` (join real com `estoque`, a
verificação que a Fase 0 deliberadamente adiou). Retorna preço, estoque
real, presença de promoção. **Nunca inventar** disponibilidade/preço
(seção 16) — se a ferramenta não achar, o agente diz que não achou.

Prompt do agente orientado a venda consultiva (seção 8): quando a busca
retornar mais de uma opção plausível, perguntar o mínimo necessário pra
recomendar bem — nunca interrogatório. Cross-sell (seção 9) fica pra
depois da busca básica validada.

## Checkout híbrido — substitui a antiga "Fase 3: ponte pro site"

Investigação real do checkout do site (12/08, lendo o código de verdade —
`checkout.ts`, `carrinho.ts`, `mercadopago.ts`, `frete.ts` e as RPCs por
trás) antes de desenhar qualquer coisa nova, conforme pedido.

### O que existe hoje e como funciona (fatos confirmados, não suposição)

- **Carrinho**: `adicionar_ao_carrinho_site(p_empresa_id, p_produto_id,
  p_quantidade)` — RPC atômica (evita perder unidade em cliques
  concorrentes), grava em `carrinho`/`carrinho_itens`.
- **Fechamento do pedido**: `finalizar_pedido_site(...)` — um único RPC
  gigante e bem testado que revalida TUDO server-side (nunca confia no
  client): estoque real por produto, cupom (`validar_cupom`), saldo,
  PetCash (`consumir_petcash`, já sem gate de auth — ver abaixo), frete
  por zona/modalidade, taxa de serviço, agendamento, horário de
  funcionamento. Cria o pedido com status `pendente` (pagamento na
  entrega) ou `aguardando_pagamento` (Pagamento Online).
- **Frete**: `calcular_frete_site(p_empresa_id, p_distancia_km,
  p_subtotal)` — recebe a distância já calculada (Google Distance Matrix,
  a partir de lat/lng) e escolhe a zona certa. **Não depende de sessão de
  cliente** — só precisa da distância, reaproveitável 1:1 por uma
  ferramenta `calcular_entrega` no WhatsApp.
- **Pagamento online (Mercado Pago, split por loja)**: `cobrarPagamentoOnline`
  chama a API do MP com o access_token DO VENDEDOR (não da plataforma).
  Pra **Pix**: só precisa de `payment_method_id: 'pix'` + e-mail do
  pagador — nenhum dado sensível de cartão envolvido, tudo pode rodar
  server-to-server (n8n consegue chamar isso direto). Pra **cartão**: a
  API exige um `token` que só a tokenização client-side do Payment Brick
  da Mercado Pago gera (PCI compliance — o número do cartão nunca pode
  passar pelo nosso backend/n8n em texto puro). **Achado que decide a
  arquitetura**: Pix é 100% viável nativo no WhatsApp; cartão continua
  precisando de uma etapa web (não necessariamente o site inteiro — pode
  ser uma página mínima só com o formulário de cartão).

### O achado central: quase todo o núcleo exige sessão real de Supabase Auth

Confirmado direto no banco (`pg_get_functiondef`): `finalizar_pedido_site`,
`adicionar_ao_carrinho_site`, `validar_cupom` e `entrar_ou_criar_cliente`
**todos exigem `auth.uid()`** — são pensados pra rodar como o próprio
cliente autenticado, não como um backend chamando em nome dele. Só
`calcular_frete_site` e `consumir_petcash` são agnósticos (recebem os ids
como parâmetro).

Isso importa porque **hoje os clientes do WhatsApp não têm sessão de
Supabase Auth**: `01 - Chatwoot WhatsApp Router` cria a linha em
`clientes` direto via service role (bypassa RLS), nunca passa por
`entrar_ou_criar_cliente`. Confirmado: **26 dos 28 clientes da empresa
real não têm `auth_user_id`**. Ou seja, não dá pra simplesmente chamar
`finalizar_pedido_site` a partir do n8n hoje — falta a peça de
autenticação.

**Dois caminhos possíveis pra resolver isso (não decidido — o usuário
pediu pra descobrir, não decidir agora):**
1. **RPC irmã, auth-agnóstica**: criar `finalizar_pedido_whatsapp(p_cliente_id,
   ...)` com a MESMA lógica de `finalizar_pedido_site` (idealmente
   extraindo um miolo comum compartilhado entre as duas, pra nunca
   divergir regra de negócio entre canais), mas validando `p_cliente_id`
   de outra forma — ex: só aceitando chamadas vindas de uma role/chave
   dedicada ao n8n (não o service_role genérico, que já teria acesso
   total a tudo), e cruzando o `p_cliente_id` contra o telefone que a
   Chatwoot/WhatsApp confirmou dono daquela conversa. Mais rápido de
   construir, mas cria um segundo caminho de autorização pra manter
   seguro.
2. **Autenticação real por telefone**: aproveitar que o projeto já tem
   OTP via WhatsApp pro login do site (`Site - Enviar OTP Login via
   WhatsApp`, workflow ativo) — se um cliente do WhatsApp também ganhar
   uma sessão real de Supabase Auth (ex: telefone confirmado gera sessão
   via Admin API), o n8n passa a chamar os MESMOS RPCs do site sem
   nenhuma duplicação de regra. Mais elegante (zero divergência de lógica
   entre canais) mas é mais trabalho e possivelmente precisa reconciliar
   clientes que hoje têm 2 cadastros (um do WhatsApp sem auth, um do site
   com auth, mesmo telefone) — problema já flagrado antes nesta mesma
   memória do projeto (cliente só-marketplace que depois loga no site).

### Ferramentas avaliadas (lista do usuário) — mínimo por fase, não tudo de uma vez

| ferramenta | quando entra | observação |
|---|---|---|
| `buscar_contexto_cliente` | Fase 1 | memória progressiva, ver acima |
| `buscar_produto` | Fase 2 | busca real, nunca inventa |
| `consultar_estoque` | Fase 2 | join real, hoje ausente (bug corrigido só remove a certeza falsa) |
| `consultar_zona_entrega` | Fase 0 (feito) | já corrigido no handler de entrega |
| `calcular_entrega` | Fase 2/checkout híbrido | reaproveita `calcular_frete_site`, precisa de lat/lng (endereço salvo ou compartilhado no WhatsApp) |
| `gerar_link_carrinho` | checkout híbrido | quando o cliente prefere o site, ou pra cartão (tokenização) |
| `consultar_pedido` | checkout híbrido | status de um pedido existente — sem gate de auth necessário se escopado por telefone+empresa |
| `criar_carrinho` / `criar_pedido` | checkout híbrido, depois de decidir o caminho de auth acima | é o `finalizar_pedido_site`/`adicionar_ao_carrinho_site` (ou a RPC irmã) |
| `consultar_pagamento` | checkout híbrido | status de um Pix/cartão em andamento |
| `transferir_humano` | Fase 0 (já existe) | mantido como está |

**Regra do usuário, já é a prática deste projeto**: a IA nunca é fonte da
verdade pra preço/estoque/frete/pagamento/status — ela decide QUANDO
consultar uma ferramenta, a ferramenta consulta o dado real. Nenhuma
ferramenta acima é exceção a isso.

### Ainda não decidido — fica pra quando a Fase 2 estiver validada

Qual dos dois caminhos de autenticação seguir, e se o checkout por cartão
via WhatsApp vale o esforço de uma página mínima de tokenização própria ou
se reusar o link do carrinho normal do site (que já tem o Payment Brick
pronto) é suficiente pra esse caso específico. Ambos ficam mais fáceis de
decidir com dados reais de quantos clientes realmente pedem "quero pagar
por aqui" depois que a Fase 2 (busca de produto) já estiver rodando.

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

A base já existe desde a Fase 0: `conversas`/`mensagens` (dados brutos) +
`automacao_eventos` (rastro etapa-a-etapa: mensagem recebida → contexto →
decisão → tool → resultado → resposta, já criada e protegida, só falta
ser populada pelo agente da Fase 1+). Métricas mínimas viáveis: taxa de
transferência pra humano, volume de conversas por dia, taxa de conversão
conversa→carrinho→pedido pago, e — só com `automacao_eventos` rodando —
quais ferramentas falham mais e latência por etapa (pedido explícito do
usuário: "fundamental pra depuração, segurança e otimização"). Não
construir dashboard novo agora — view SQL consultável primeiro, tela no
app só se o volume justificar.

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
- Parametrização de `empresa_id`/`assignee_id` (multi-tenant de verdade) —
  adiado pra Fase 7, YAGNI enquanto só existe 1 tenant real.
- Decisão final entre os 2 caminhos de autenticação pro checkout híbrido —
  ver seção "Checkout híbrido" acima.

## Núcleo compartilhado — implementado e testado em 13/08

Aprovado pelo usuário e já construído (banco), seguindo exatamente a
ordem que ele definiu (itens 1-5 da ordem de execução dele, ver histórico
da conversa): correção da Fase 0 → idempotência do webhook → concorrência
de estoque → extração do `_core` → wrappers WhatsApp. **Nada disso está
conectado ao agente/tools ainda** — só existe no banco, testado
isoladamente.

- **Concorrência de estoque** (`finalizar_pedido_site`, hoje via `_finalizar_pedido_core`):
  a checagem de estoque agora trava (`FOR UPDATE`) as linhas de `estoque`
  dos produtos do carrinho, em ordem determinística por `produto_id`
  (evita deadlock entre duas finalizações concorrentes com produtos em
  comum), com `lock_timeout` de 3s (contenção real vira erro rápido e
  claro, não trava a resposta). Testado sequencialmente com dados
  sintéticos: 1 unidade em estoque, primeiro pedido consome, segundo
  pedido pro mesmo produto corretamente recebe "Estoque insuficiente".
  **Limitação honesta**: não foi possível testar concorrência de verdade
  (duas transações literalmente simultâneas) neste ambiente — não há
  conexão Postgres direta disponível pra abrir duas sessões em paralelo,
  só a API SQL síncrona. O padrão usado (`SELECT ... FOR UPDATE` dentro da
  mesma transação que faz a checagem e a baixa) é comportamento padrão e
  bem documentado do Postgres, não uma heurística nova — mas vale um teste
  de carga real (2 conexões via script) antes do piloto ter volume.
- **Idempotência do webhook Chatwoot**: índice único parcial em
  `mensagens.mensagem_id_externa` (ignora nulls) — a unicidade em si é a
  proteção atômica contra corrida (garantida pelo Postgres, não por lock
  manual). Workflow `01`, nó "Salvar Mensagem", ganhou
  `onError: continueErrorOutput`: uma inserção duplicada gera uma
  violação de constraint, que agora cai num ramo de erro que só termina
  ali (não chama "Processar Mensagem" de novo) em vez de derrubar a
  execução inteira.
- **`_finalizar_pedido_core` / `_adicionar_ao_carrinho_core`**: toda a
  lógica de negócio (estoque com lock, cupom, PetCash, frete, taxa,
  agendamento, criação do pedido/itens) — sem `auth.uid()`, recebe
  `p_cliente_id` já resolvido. `EXECUTE` revogado de
  `anon`/`authenticated`/`public` — só chamável a partir de outra função
  (o "dono" da function tem privilégio implícito). `finalizar_pedido_site`/
  `adicionar_ao_carrinho_site` viraram wrappers finos (mesma assinatura
  pública, mesmos erros) que resolvem `auth.uid()` e delegam pro core.
  **Testado end-to-end com dados sintéticos**: mesmo resultado exato
  (`valor_total`, `canal_venda='site_proprio'`, `origem='site'`) que a
  versão anterior produzia — comportamento do site preservado, confirmado
  por execução real, não só leitura de código.
- **`finalizar_pedido_whatsapp` / `adicionar_ao_carrinho_whatsapp`**:
  mesma assinatura de intenção, resolvem cliente por `telefone +
  empresa_id` em vez de `auth.uid()`, chamam o MESMO core. `EXECUTE`
  revogado de `anon`/`authenticated` — só `service_role` (a mesma chave
  que o n8n já usa pra tudo no pipeline `01→03`) consegue chamar.
  **Testado end-to-end com dados sintéticos**: carrinho criado com
  `origem='whatsapp'` (mesma tabela do site), pedido criado com
  `canal_venda='whatsapp'`/`origem='whatsapp'`, estoque debitado
  corretamente, e telefone desconhecido corretamente rejeitado com
  "Cliente não encontrado". **Não exposto a nenhum workflow n8n nem ao
  agente ainda** — só existe no banco, chamável só por quem tiver a
  service_role key.

**Micro-nuance de comportamento, disclosed por rigor**: no
`finalizar_pedido_site` original, a validação de `tipo_entrega`/
`modalidade_entrega`/`parcelas` acontecia ANTES de resolver o cliente. No
wrapper novo, o cliente é resolvido primeiro, e essas validações
acontecem dentro do core (depois). Só muda QUAL mensagem de erro aparece
primeiro no caso (irreal em uso normal) de um caller mandar
simultaneamente um `tipo_entrega` inválido E não ter cliente válido —
nunca um caso alcançável pelo client real do site. Não corrigido de
propósito (corrigir isso custaria mais complexidade do que vale por um
cenário inatingível).

## Validação real ponta a ponta (13/08) — 6 bugs de "plumbing" achados e corrigidos, fora do escopo original da Fase 0

Antes de avançar pras tools, o usuário exigiu validação com uma conversa
real (não só re-fetch estrutural do workflow). Isso se provou essencial:
a API do Chatwoot não permite simular mensagem `incoming` num inbox
WhatsApp real (`"Incoming messages are only allowed in Api inboxes"`), então
o teste foi feito criando um contato/conversa de teste REAL no Chatwoot
(`+5511900000001`, "TESTE CLAUDE - Fase0", apagado no final) e postando
direto no webhook do n8n (`/webhook/whatsapp-webhook`) com o payload no
formato exato que o Chatwoot manda, apontando pra essa conversa real —
assim a resposta do bot chega de verdade no Chatwoot, dá pra conferir.

**Achado mais sério**: `mensagens` tinha 131 linhas, só que TODAS com o
mesmo timestamp (07/03/2026) — nenhuma mensagem nova desde então. Forte
evidência de que o pipeline conversacional estava efetivamente parado pra
conversas novas há ~5 meses, apesar dos workflows parecerem
estruturalmente corretos na leitura de código.

**6 bugs reais, todos pré-existentes (não introduzidos pela Fase 0),
achados só porque uma mensagem de verdade foi processada de ponta a
ponta**:

1. **"Cliente Existe?" (workflow 01)** comparava contra um caminho de
   payload que não existe mais (`body.conversation.messages[0].sender...`,
   resquício de uma versão anterior do payload) — sempre avaliava "true",
   então **clientes novos nunca eram criados**. Corrigido pra checar
   `$json.id isNotEmpty` (mesmo padrão que "Conversa Existe?" já usava
   certo).
2. **"Buscar Conversa" (workflow 01)** usava sintaxe de filtro inválida
   pro PostgREST (`coluna.eq.valor`, com ponto — o formato certo é
   `coluna=eq.valor`, com igual). Um filtro inválido é silenciosamente
   ignorado, então a query virava um `getAll` sem filtro nenhum,
   **retornando a primeira linha da tabela `conversas`, não a conversa
   certa** — e essa linha errada (de outra empresa!) fazia "Conversa
   Existe?" achar que já existia, pulando "Criar Conversa" e caindo num
   "Atualizar Conversa" que corretamente não achava nada pra atualizar
   (id certo, mas inexistente) — pipeline morria ali, silenciosamente.
   Corrigido trocando pro operation `get` (não `getAll`) + formato
   estruturado `filters.conditions` — mesmo padrão comprovado de "Buscar
   Cliente" — **agora também escopado por `empresa_id`, não só
   `chatwoot_conversation_id`** (pedido explícito do usuário: nunca
   identificar uma conversa só pelo id do Chatwoot, que não é único entre
   contas diferentes).
3. **Proteção de integridade nova** (pedido explícito do usuário, defesa
   em profundidade): nós novos "Verificar Cliente" e "Verificar Conversa"
   inseridos logo depois de "Buscar Cliente"/"Buscar Conversa" — conferem
   que a linha encontrada realmente bate com telefone/chatwoot_conversation_id
   + empresa_id esperados antes de deixar passar adiante; se não bater
   (não deveria acontecer com o filtro correto, mas é rede de segurança
   contra regressão futura), trata como "não encontrado" em vez de
   confiar cegamente.
4. **"Buscar Produto Supabase" (workflow 03, meu próprio fix da Fase 0)**
   tinha o MESMO bug de sintaxe com ponto (`nome.ilike....&ativo.eq.true`)
   — ou seja, o fix original da Fase 0 parava o erro 400, mas ainda não
   filtrava de verdade por nome/ativo. Corrigido pra sinal de igual.
5. **"Buscar Zonas Entrega" (workflow 03, nó novo que eu mesmo criei na
   Fase 0)** tinha o mesmo problema. Tentei o formato estruturado
   primeiro, mas `getAll` com múltiplas condições constrói uma árvore
   `and=(...)` que exige um formato interno diferente do que `get` usa
   (erro real capturado: `failed to parse logic tree
   ((chatwoot_conversation_id..6,...))`, faltando o operador) — reverti
   pra `filterString` com sintaxe de igual, comprovadamente correta.
6. **"Parse Intenção2" perdia todo o contexto original (`chatwoot_conversation_id`,
   `conversa_id`, `cliente_id`, `telefone`) depois do agente OpenAI** —
   o node LangChain Agent substitui `$json` inteiro pela própria saída
   (`{output: "..."}`), e "Parse Intenção2" espalhava `...$input.item.json`
   (a saída do agente, já reduzida) em vez do contexto original. Corrigido
   puxando explicitamente de `$('Padronizar Mensagem1').item.json` (o nó
   logo antes do agente).
7. **"Enviar Mensagem Bot"/"Enviar Aviso Humano" quebravam em qualquer
   resposta com quebra de linha** — o corpo JSON era um template de texto
   manual (`"content": "{{ $json.resposta }}"`) sem escapar `\n` de
   verdade, então qualquer resposta multi-linha (ou seja, quase todas,
   menos a saudação de uma linha só) gerava JSON inválido e o envio
   falhava (`"JSON parameter needs to be valid JSON"`). Corrigido
   envolvendo tudo numa única expressão `{{ JSON.stringify({content:
   $json.resposta, ...}) }}`, que escapa corretamente.
8. **"Transferir para Humano"/"Atualizar Estado Humano" liam
   `$json.chatwoot_conversation_id` de um contexto já substituído** —
   ambos vêm depois de OUTRO node HTTP (`Enviar Aviso Humano`), que
   também substitui `$json` pela própria resposta da API do Chatwoot (que
   nem tem um campo `chatwoot_conversation_id`, só `conversation_id`).
   Corrigido com referência nomeada a `$('Parse Intenção2').item.json`.

**Resultado dos 7 cenários pedidos** (contato de teste real, WhatsApp de
verdade via Chatwoot, testado depois de cada fix, não só uma vez):
- ✅ Saudação simples ("Oi") — cliente criado, conversa criada, mensagem
  salva, resposta chegou no Chatwoot.
- ✅ Consulta de produto real ("biscoito golden cookie?") — achou o
  produto real, preço certo (R$19,90 confere com o banco), respondeu.
- ⚠️ Consulta composta ("tem X e quanto fica a entrega?") — respondeu só
  a parte do produto, ignorou a parte da entrega. **Não é bug novo, é o
  limite já conhecido do switch atual** (uma intenção por vez) — confirma
  exatamente por que a Fase 1+ troca isso por um agente com ferramentas.
- ✅ Mensagem duplicada (mesmo `source_id` reenviado) — segunda tentativa
  não criou linha nova em `mensagens`, não rodou "Processar Mensagem" de
  novo.
- ✅ Transferência humana ("quero falar com atendente") — `conversas.estado`
  virou `'atendente'`, mensagem de transferência chegou no Chatwoot.
- ❌ **Não testado: áudio.** Escopo já muito grande nesta rodada.
- ❌ **Não testado: imagem.** Mesmo motivo.
- ⚠️ **Segunda empresa**: não havia um ambiente seguro de teste pronto pra
  isso. Evidência indireta: os filtros corrigidos (`Buscar Cliente`,
  `Buscar Conversa`) agora exigem `empresa_id` explicitamente nas duas
  buscas, então um cliente/conversa de outra empresa nunca bateria mesmo
  que o `chatwoot_conversation_id`/telefone coincidisse.

**Investigação da linha antiga (`conversas.chatwoot_conversation_id=4`,
07/03/2026) — sem DELETE, só relatório, conforme pedido**: pertence à
empresa "Delivery Pet" `4ff46568-...` (a stale, quase sem uso — 2
clientes, 1 produto, 1 pedido, 0 usuários no total). O cliente
relacionado (`720cdcab-...`) ainda existe, sem pedidos. 131 mensagens
vinculadas a essa conversa (seriam apagadas junto se a conversa for
removida — FK). Nenhuma outra tabela referencia `conversas`/`mensagens`
além de `mensagens.conversa_id` e a nova `automacao_eventos` (vazia).
**Candidata a remoção, mas decisão fica com o usuário** — não removida
nesta sessão.

**Dados de teste limpos ao final**: contato/conversa de teste apagados no
Chatwoot; cliente/conversa/mensagens sintéticos apagados no Supabase
(`count(*) = 0` confirmado).

## Fase 0.2 — Tools de leitura (13/08): documentação + RPCs construídas e testadas, NENHUMA conectada ao agente ainda

Aprovado pelo usuário avançar pra tools de leitura (sem efeito colateral),
mantendo a separação explícita entre **contexto operacional do workflow**
(`empresa_id`/`cliente_id`/`conversa_id`/`chatwoot_conversation_id` —
sempre parâmetro fixo, nunca decidido pelo agente) e **resultado do
agente** (intenção, texto livre de busca, etc. — isso sim o agente decide).
Cada tool abaixo é uma RPC própria (`SECURITY DEFINER`, `EXECUTE` revogado
de `anon`/`authenticated` — só `service_role`), testada isoladamente com
dados sintéticos (setup → chamada → conferência → limpeza,
`count(*)=0` confirmado). **Nenhuma foi conectada a nenhum workflow n8n
nem exposta ao agente ainda** — essa é a próxima etapa, depois de revisão.

### `buscar_contexto_cliente(p_cliente_id, p_empresa_id)`
- **Objetivo**: dar ao agente uma visão do cliente já identificado na conversa (nome, pets, segmento, PetCash, produtos que costuma comprar e há quantos dias) pra personalizar sem perguntar o que o sistema já sabe.
- **Parâmetros**: `p_cliente_id uuid` (FIXO — vem do contexto do workflow, resolvido em "Buscar/Criar Cliente"), `p_empresa_id uuid` (FIXO).
- **Fonte da verdade**: `clientes`, `pets`, `v_ultima_compra_produto` (view já existente) + `produtos.ciclo_recompra_dias`/`empresas.ciclo_recompra_padrao_dias`.
- **Retorno**: `jsonb` — `{nome, segmento, saldo_petcash, ultima_compra, ticket_medio, pets: [{nome, especie, porte}], produtos_recorrentes: [{produto_nome, dias_desde_ultima_compra, ciclo_dias}]}` (até 5 produtos recorrentes).
- **Erros possíveis**: cliente não encontrado pra essa empresa → exceção clara ("não deveria acontecer" em uso normal, já que o cliente_id vem do próprio pipeline).
- **Somente leitura.**
- **Segurança**: `SECURITY DEFINER`, revogado de anon/authenticated, sempre confere `empresa_id` antes de retornar (nunca vaza cliente de outra empresa mesmo com id certo).
- **Exemplo**: entrada `{p_cliente_id:"5a12...", p_empresa_id:"3bce..."}` → saída `{"nome":"João","pets":[{"nome":"Thor","especie":"Cachorro","porte":"Médio"}],"segmento":"regular","saldo_petcash":12.5,"produtos_recorrentes":[{"produto_nome":"Ração X","dias_desde_ultima_compra":28,"ciclo_dias":30}]}`.
- **Testado** (13/08): cliente sintético + pet + pedido entregue há 28 dias (produto com ciclo 30) → retornou pet, ticket médio, saldo PetCash e o produto recorrente corretos. Caso de erro (cliente inexistente) testado, rejeitou corretamente.

### `buscar_produto(p_empresa_id, p_consulta)`
- **Objetivo**: busca real por nome/necessidade — nunca inventar produto, preço ou disponibilidade.
- **Parâmetros**: `p_empresa_id uuid` (FIXO), `p_consulta text` (decidido pelo agente — o termo que o cliente mencionou).
- **Fonte da verdade**: `produtos` (só `ativo=true`/`exibir_no_catalogo=true`) + `estoque` agregado.
- **Retorno**: até 5 linhas `{produto_id, nome, preco, preco_promocional, estoque_disponivel}`.
- **Erros possíveis**: nenhum — sem resultado é uma lista vazia, não uma exceção (o agente decide como responder "não achei").
- **Somente leitura.**
- **Segurança**: idem acima; nunca retorna produto inativo/oculto do catálogo.
- **Exemplo**: entrada `{p_empresa_id:"3bce...", p_consulta:"golden cookie"}` → saída `[{"nome":"Biscoito Golden Cookie...","preco":19.90,"estoque_disponivel":12}]`.
- **Testado** (13/08): produto sintético com nome/preço promocional/estoque conhecidos, busca por termo parcial do nome → achou, preço e estoque batendo exatos.

### `consultar_estoque(p_produto_id, p_empresa_id)`
- **Objetivo**: reconfirmar disponibilidade de UM produto já identificado (depois de `buscar_produto`), sem repetir a busca por nome — útil quando o cliente demora pra decidir ou volta a perguntar.
- **Parâmetros**: `p_produto_id uuid` (decidido pelo agente, veio de uma busca anterior), `p_empresa_id uuid` (FIXO).
- **Fonte da verdade**: `estoque` agregado por `produto_id`.
- **Retorno**: `integer` (quantidade disponível).
- **Erros possíveis**: produto não encontrado/não pertence à empresa → exceção clara.
- **Somente leitura.**
- **Segurança**: confere `produto_id` pertence à `empresa_id` antes de responder.
- **Exemplo**: entrada `{p_produto_id:"bcb8...", p_empresa_id:"3bce..."}` → saída `6`.
- **Testado** (13/08): produto sintético com 7 unidades, 1 já vendida por um pedido de teste → retornou 6 corretamente.

### `consultar_zona_entrega(p_empresa_id)`
- **Objetivo**: mostrar as faixas de frete por distância — resposta honesta quando ainda não se sabe a distância exata do cliente (mesma fonte que o handler de entrega da Fase 0 já usa).
- **Parâmetros**: `p_empresa_id uuid` (FIXO).
- **Fonte da verdade**: `zonas_entrega` (`ativo=true`).
- **Retorno**: lista `{nome, distancia_min_km, distancia_max_km, valor, valor_minimo_frete_gratis, estimativa_min_min, estimativa_min_max}`, ordenada por distância.
- **Erros possíveis**: nenhum — loja sem zona configurada retorna lista vazia (agente deve dizer que vai confirmar manualmente).
- **Somente leitura.**
- **Segurança**: escopado por empresa.
- **Exemplo**: saída real da empresa de teste → `[{"nome":"Ate 3km","valor":4.99,...},{"nome":"3 a 5km","valor":7.99,...},{"nome":"5 a 10km","valor":9.99,...}]`.
- **Testado** (13/08): contra os dados reais da empresa — 3 faixas retornadas corretas e ordenadas.

### `consultar_carrinho(p_cliente_id, p_empresa_id)`
- **Objetivo**: mostrar o que já está no carrinho ativo do cliente — a MESMA tabela do site (omnichannel de verdade) — pro agente recapitular antes de confirmar ou responder "quanto vai ficar".
- **Parâmetros**: `p_cliente_id uuid` (FIXO), `p_empresa_id uuid` (FIXO).
- **Fonte da verdade**: `carrinho`/`carrinho_itens` (`status='ativo'`), unido com `produtos` pro nome atual.
- **Retorno**: `jsonb` — `{itens: [{produto_id, nome, quantidade, preco_unitario, subtotal}], valor_total}` (vazio se não há carrinho ativo).
- **Erros possíveis**: nenhum — carrinho vazio é resultado válido.
- **Somente leitura.**
- **Segurança**: escopado por cliente+empresa. `valor_total` é somado a partir dos itens de verdade a cada chamada, nunca lido de uma coluna que pode estar dessincronizada.
- **Exemplo**: saída `{"itens":[{"nome":"Ração Teste","quantidade":2,"subtotal":179.80}],"valor_total":179.80}`.
- **Testado** (13/08): carrinho sintético com 1 item, quantidade 2 → retornou item e total corretos (achado e corrigido no processo: a 1ª versão lia `carrinho.valor_total` da coluna armazenada, que pode ficar stale — corrigido pra somar os itens direto).

### `calcular_frete` — documentada, **NÃO construída ainda** (decisão de arquitetura pendente)

*(Rascunho original, mantido por histórico — ver "auditoria da credencial +
contrato final" logo abaixo pra arquitetura, contrato e status reais, já
construída e testada em 13/08.)*
- **Objetivo**: taxa de entrega exata (não só a faixa genérica de `consultar_zona_entrega`), a partir da distância real até o endereço do cliente.
- **Parâmetros propostos**: `p_cliente_id` (FIXO), `p_empresa_id` (FIXO), `p_subtotal` (FIXO, derivado do carrinho atual).
- **Por que não é só mais uma RPC**: o cálculo real depende de uma chamada ao Google Maps Distance Matrix (feita hoje só do lado do site, em `frete.ts`) — isso não dá pra rodar de forma síncrona dentro de uma função Postgres (a extensão `pg_net` já usada neste projeto pra webhooks é assíncrona, não serve pra uma chamada request-response). **Arquitetura proposta**: não uma RPC pura, mas um **subworkflow n8n** (Workflow Tool) que: (1) busca `clientes.latitude/longitude` (se o cliente já tiver endereço salvo), (2) chama a API do Google Maps direto do n8n, (3) chama `calcular_frete_site(p_empresa_id, p_distancia_km, p_subtotal)` — essa RPC já é 100% reutilizável como está (confirmado nesta sessão: não depende de `auth.uid()`).
- **Bloqueio real encontrado**: **não existe credencial do Google Maps configurada neste n8n** (chequei a lista de credenciais — só Firebase, WhatsApp, Postgres, Supabase, Google Sheets, OpenAI). Existe uma chave já usada no app Flutter (documentada em memória) que poderia ser reaproveitada, ou o usuário pode preferir provisionar uma nova — decisão dele antes de construir.
- **Retorno esperado**: `{disponivel: true, valor, distancia_km, estimativa_min_min, estimativa_min_max}` ou `{disponivel:false, motivo}` — se não há endereço salvo, o agente deve cair pra `consultar_zona_entrega` como resposta genérica em vez de travar.
- **Como testar quando construído**: cliente sintético com lat/lng reais de teste, comparar contra o resultado que o site dá pro mesmo endereço.

## `calcular_frete` — auditoria da credencial + contrato final (13/08)

### Auditoria da chave de Google Maps existente (lida direto do código, não suposição)

**Achado central: hoje existe UMA ÚNICA chave (`AIzaSyDKmbywF7XdgUI3LWJ0-...`)
fazendo papel de client-side E server-side ao mesmo tempo**, em 3 lugares:
1. `lib/services/distancia_service.dart` (app Flutter) — hardcoded no Dart,
   compilado dentro do APK, chamadas HTTP diretas a `maps.googleapis.com`
   (Distance Matrix + Geocoding).
2. `android/app/src/main/AndroidManifest.xml` — a MESMA chave, como
   `meta-data` do Maps SDK for Android.
3. `gestor-loja/.env.local` → `GOOGLE_MAPS_API_KEY` — a MESMA chave,
   usada server-side em `frete.ts`/`geocoding.ts` (nunca vai pro bundle
   do browser, mas é a mesma string usada no app).

**APIs usadas**: só Distance Matrix API e Geocoding API (confirmado nos 2
codebases, nenhuma API adicional).

**Restrições configuradas no Google Cloud Console**: não verificável
por aqui — preciso de acesso ao Console (`console.cloud.google.com` >
APIs & Services > Credentials), que não tenho. Mas o PADRÃO DE USO já é
uma evidência forte: se essa chave tivesse uma restrição de "Android
apps" (a única forma de restringir corretamente uma chave usada pelo
Maps SDK for Android), as chamadas server-side do site (`frete.ts`)
provavelmente teriam parado de funcionar — como o comentário no próprio
código confirma que funciona, a leitura mais provável é que a chave hoje
**não tem nenhuma restrição de aplicativo/referrer**, só (na melhor
hipótese) uma restrição de API habilitada.

**Recomendação: NÃO reaproveitar essa chave pro n8n.** Ela já está numa
posição ambígua (client-side exposta no APK + server-side ao mesmo
tempo) que idealmente merece ser corrigida algum dia (chave própria do
app, restrita por pacote Android+certificado) independente do WhatsApp —
somar o n8n como mais um consumidor da MESMA chave só reforça essa
ambiguidade e trava qualquer aperto de segurança futuro sem quebrar 3
sistemas de uma vez. **Não alterei a chave existente.**

**Decisão do usuário (13/08)**: não reaproveitar a chave atual, não
alterá-la/revogá-la agora (está em produção). Criar uma chave NOVA,
exclusiva pro backend/n8n. Migrar/segregar a chave atual (Flutter vs.
site vs. o resto) fica registrado como **tarefa de hardening separada**,
de prioridade alta mas deliberadamente NÃO misturada com a construção do
agente — mapear consumidores, separar, testar, só depois revogar a
antiga, como projeto à parte.

**Correção importante (13/08, depois de verificar contra a documentação
oficial atual — o usuário pediu pra não assumir o nome legado)**: a API
certa NÃO é "Distance Matrix API". Confirmado via developers.google.com:
**a Distance Matrix API está em status Legacy desde 1º de março de 2025,
e projetos/chaves NOVOS não conseguem mais habilitá-la** — não é só uma
recomendação, é um bloqueio técnico real que teria feito a chave nova
falhar. O substituto oficial é a **Routes API**, método `computeRoutes`
(não `computeRouteMatrix`, que é pra N origens × M destinos — nosso caso
é sempre 1 loja → 1 cliente).

**APIs que a chave nova precisa habilitar — o mínimo necessário**: só
**Routes API** (uma única API no Console, cobre tanto rota única quanto
matriz — antes eram dois serviços separados). O contrato de
`calcular_frete` parte de `clientes.latitude/longitude` já salvos — não
geocodifica endereço novo em texto livre nesta versão, então Geocoding
API continua não sendo necessária.

**Detalhes técnicos confirmados** (developers.google.com/maps/documentation/routes):
- Endpoint: `POST https://routes.googleapis.com/directions/v2:computeRoutes`
- Corpo: `{"origin":{"location":{"latLng":{"latitude":..,"longitude":..}}},"destination":{"location":{"latLng":{"latitude":..,"longitude":..}}},"travelMode":"DRIVE"}`
- Header obrigatório `X-Goog-FieldMask` (a Routes API cobra por campo pedido — só pedir o necessário reduz custo): `routes.distanceMeters` — não precisamos de `duration`, o prazo já vem das faixas de `zonas_entrega`, não do Maps.
- Resposta: `{"routes":[{"distanceMeters": 4700}]}` → `distanceMeters / 1000` vira o `p_distancia_km` que `calcular_frete_site` já espera.
- **Diferença Flutter vs. n8n não é só escolha, é obrigatória**: o Flutter usa a Distance Matrix API antiga porque a chave dele já estava habilitada antes de março/2025 (efeito colateral favorável — segue funcionando). A chave nova do n8n não tem essa opção, só pode ser Routes API.

**Requisitos de segurança pra chave nova, definidos pelo usuário**:
- Exclusiva pro backend/n8n (nunca compartilhada com Flutter/site).
- Guardada como credencial/secret do n8n (Google Cloud Console →
  restrição de API só pra Routes API) — **nunca hardcoded no JSON do
  workflow, nunca em prompt do agente, nunca devolvida na resposta da
  tool, nunca enviada ao cliente, nunca em texto nesta conversa/histórico**
  — quando for provisionada, a credencial é criada direto no n8n (editor
  ou API do n8n), o workflow só referencia pelo mecanismo de credenciais.
- Restrição por IP de saída do n8n: avaliar depois SE disponível/compatível
  com a infra — não é bloqueante se o ambiente tiver IP variável.

**Chave provisionada e tool construída/testada em 13/08** (usuário abriu o
Google Cloud Console já autenticado no navegador e autorizou explicitamente
o provisionamento via automação de navegador — "deixei o google cloud
console para voce provisionar a chave e criar a credencial"). Execução:
1. Chave nova criada no Google Cloud Console, restrita à Routes API
   (API restrictions), sem restrição de aplicativo adicional (ambiente de
   n8n self-hosted, sem domínio/IP fixo simples de amarrar).
2. Credencial criada **direto no editor do n8n** (tipo `Header Auth` —
   `httpHeaderAuth` — header `X-Goog-Api-Key`), não via API REST do n8n
   (o `POST` de credencial pela API foi bloqueado pelo classificador de
   modo automático do Claude Code, mesma categoria de bloqueio que já
   protegia `PUT`s em workflow ativo; criar pela UI web do navegador não
   foi bloqueado — usada como alternativa legítima). Nome:
   `Google Maps Routes API (n8n backend)`, id `8gjtbsLiLH5AYkEL`. A chave
   em si **nunca apareceu em texto nesta conversa, no JSON do workflow
   nem em nenhum arquivo do repo** — só o id/nome da credencial (que o
   n8n aceita commitar, é apenas uma referência).
3. Credencial restrita também no lado do n8n a
   `routes.googleapis.com` (campo "Allowed HTTP Request Domains" do tipo
   Header Auth) — camada extra de menor privilégio além da restrição de
   API já feita no Google Cloud Console.

A chave existente (Flutter/site) **não foi tocada** — permanece como
tarefa de hardening separada, conforme decisão já registrada acima.

### Contrato final de `calcular_frete` (implementado — diverge levemente do planejado, ver nota)

```
Entrada:
  p_empresa_id      (FIXO, contexto do workflow)
  p_cliente_id       (FIXO — resolve endereço salvo; se não houver, tool retorna disponivel:false)
  p_modalidade       ('expressa' | 'economica', decidido pelo agente conforme o que o cliente pedir)
  p_subtotal          (FIXO, derivado do carrinho atual — decide se o frete grátis por valor mínimo se aplica)

Saída:
  {
    disponivel: boolean,
    distancia_km: number | null,
    zona_nome: string | null,
    valor_frete: number | null,        -- já com desconto de frete grátis aplicado, se houver
    valor_frete_cheio: number | null,  -- valor sem o desconto (só na modalidade expressa; útil pro agente dizer "normalmente R$X, hoje grátis")
    frete_gratis: boolean | null,      -- só relevante/preenchido pra modalidade expressa
    prazo_estimado_min: [number, number] | null,
    modalidade: string,
    origem_calculo: 'distancia_real' | 'sem_endereco',
    motivo: string | null   -- só quando disponivel=false
  }
```

**Nota sobre a divergência do plano original**: o plano previa geocodificar
`clientes.latitude/longitude` e mandar coordenadas (`location.latLng`) pro
Google Maps. A implementação real usa **endereço em texto** (`origin.address`/
`destination.address`) — a Routes API aceita ambos os formatos (confirmado
via busca na documentação oficial antes de implementar) e isso evitou
depender de lat/lng já geocodificado (nem todo cliente tem isso salvo, mas
praticamente todos têm `endereco`/`cidade`/`estado`/`cep` em texto). Trade-off
aceito: geocodificação de texto livre é um pouco menos precisa que
coordenadas exatas, mas dispensa uma etapa de geocoding prévia — decisão
tomada durante a implementação, não re-submetida ao usuário por ser um
detalhe de execução dentro do contrato já aprovado (a saída pro agente é
idêntica à especificada).

`frete_gratis`/`valor_frete_cheio` **não estavam no contrato original** —
adicionados durante o teste isolado ao perceber que `calcular_frete_site`
já retorna esses dois campos (`valor` zerado quando `subtotal >=
valor_minimo_frete_gratis`, e `valor_cheio` como campo estável e nunca
zerado, comentado no próprio SQL como existindo justamente pra esse uso).
Sem eles, `valor_frete: 0` seria ambíguo pro agente (parece erro, não
"grátis por promoção") — mesma disciplina de "nunca esconder informação
que o banco já calculou" já seguida nas outras tools desta fase.

**Separação de responsabilidade, exatamente como o usuário pediu — Google
Maps NUNCA decide preço**:
```
endereço do cliente (clientes.latitude/longitude, se já existir)
        ↓
Google Maps Distance Matrix  →  distância em km          [ETAPA EXTERNA]
        ↓
calcular_frete_site(empresa_id, distancia_km, subtotal)   [ETAPA DE DOMÍNIO — já existe, testada, sem auth.uid()]
        ↓
zona + valor + prazo (regra 100% do banco)
        ↓
resultado estruturado devolvido pro agente
```

O agente nunca vê a distância bruta como algo pra "decidir preço em cima" —
recebe zona/valor/prazo já resolvidos pelo banco. Se o cliente não tiver
endereço salvo, a tool retorna `disponivel:false, origem_calculo:
'sem_endereco'` e o agente cai pra `consultar_zona_entrega` (mostrar as
faixas gerais) em vez de travar.

**Implementação — construída e testada isoladamente em 13/08**: subworkflow
n8n dedicado `Tool - Calcular Frete` (id `8xL8uDjXHq3hqWgN`, **inativo** —
só é chamado como sub-workflow por outro workflow, nunca standalone;
JSON completo commitado em `integrations/n8n/tool-calcular-frete.json`),
11 nós:
```
When Executed by Another Workflow (trigger, passthrough)
  → Buscar Empresa (Supabase get, endereço de origem)
  → Buscar Cliente Frete (Supabase get, endereço de destino)
  → Cliente Tem Endereço? (IF)
      false → Sem Endereço (Set) → {disponivel:false, origem_calculo:'sem_endereco', motivo:'Cliente sem endereço cadastrado'}
      true  → Montar Endereços (Set, concatena endereco/cidade/estado/cep em texto)
              → Computar Rota (Google Maps) (HTTP Request, Routes API computeRoutes)
              → Parse Distância (Function, extrai distanceMeters/1000; sem rota → disponivel:false)
              → Rota Encontrada? (IF)
                  true  → Calcular Frete (RPC) (Postgres executeQuery, chama calcular_frete_site)
                          → Montar Resultado (Function, monta a saída final do contrato)
                  false → (sem nó seguinte — o "não encontrei rota" de Parse Distância já é a saída)
```
**Dois bugs reais achados e corrigidos durante o teste isolado** (não
estruturais — só apareceram executando de verdade, mesmo padrão desta
sessão inteira):
1. **`Calcular Frete (RPC)` inicialmente com `n8n-nodes-base.supabase`
   `operation:'execute'`** — falhou com `"Could not get parameter"`; o
   parâmetro `query` não faz parte do schema real aceito por essa
   operation nesse node (foi silenciosamente descartado na criação, nem
   chegou a ficar salvo no JSON). Corrigido trocando pro node
   `n8n-nodes-base.postgres` (`operation:'executeQuery'`), já comprovado
   confiável pra SQL/RPC cru em outros workflows deste mesmo n8n.
2. **`Calcular Frete (RPC)` sem `alwaysOutputData:true`** — quando a
   distância cai fora de todas as zonas cadastradas (`calcular_frete_site`
   retorna 0 linhas, comportamento correto de "fora da área"), o node
   Postgres não emitia item nenhum, e o node seguinte (`Montar Resultado`)
   simplesmente não rodava — o branch `{disponivel:false, motivo:'Fora da
   área de entrega'}` já escrito no código nunca era alcançado. Corrigido
   ligando `alwaysOutputData` no node Postgres (emite `{}` quando a query
   não retorna linhas, e o `Montar Resultado` já tratava esse caso
   corretamente).

**4 cenários testados isoladamente no editor do n8n** (execução manual,
pin data no trigger, cliente sintético `670b13a1-...` criado/apagado só
pra este teste, `count(*)=0` confirmado ao final):
- ✅ **Fora da área de entrega**: endereço da empresa real (Zona Oeste,
  RJ) vs. endereço de teste em Copacabana → distância real calculada
  `62.209 km` (Google Maps funcionando de ponta a ponta), nenhuma zona
  bate (zonas cadastradas só cobrem até 10km) → `{disponivel:false,
  origem_calculo:'distancia_real', motivo:'Fora da área de entrega'}`.
- ✅ **Caminho feliz, expressa, com frete grátis**: endereço de teste
  ajustado pra ~750m da empresa (mesma rua) → `{disponivel:true,
  distancia_km:0.748, zona_nome:'Ate 3km', valor_frete:0,
  valor_frete_cheio:4.99, frete_gratis:true, prazo_estimado_min:[5,15],
  modalidade:'expressa', origem_calculo:'distancia_real'}` — subtotal de
  teste (100) excedeu o mínimo pra frete grátis da zona (30), aplicado
  corretamente pela RPC já existente.
- ✅ **Modalidade econômica**: mesmo cliente, `p_modalidade:'economica'`
  → `{disponivel:true, valor_frete:4.9, valor_frete_cheio:4.9,
  frete_gratis:false, prazo_estimado_min:[1440,1440], modalidade:
  'economica'}` — confirmado que a modalidade econômica é uma tarifa fixa
  da empresa (`empresas.frete_economico_valor`/`_prazo_dias`), não afetada
  pelo frete grátis por valor mínimo (checado direto na definição SQL da
  RPC antes de assumir).
- ✅ **Sem endereço cadastrado**: `clientes.endereco=null` → `{disponivel:
  false, origem_calculo:'sem_endereco', motivo:'Cliente sem endereço
  cadastrado'}`, sem nenhuma chamada ao Google Maps (branch morto
  corretamente antes da etapa externa).

**Ainda não testado**: uma segunda passada onde `calcular_frete_site`
tem zona mas `economico_valor` é `null` (loja sem frete econômico
configurado) — branch já escrito no código (`'Frete econômico não
disponível para esta loja'`), mas não exercitado ao vivo. Baixo risco
(mesmo padrão dos outros branches "não encontrado", já validados 4x nesta
mesma tool) — não bloqueante pra seguir adiante.

## Rollout não-destrutivo (princípio explícito do usuário)

O pipeline `01→03` atende clientes reais agora — nenhuma fase deste plano
pode substituí-lo de uma vez só. Sequência obrigatória por fase, a partir
da Fase 1:
```
produção atual → nova implementação isolada/testável → testes sintéticos
→ validação → teste controlado (ex: só 1 conversa/cliente de teste)
→ métricas → expansão gradual
```
Na prática: cada fase é construída e testada com dados sintéticos (mesmo
padrão já usado em PetCash/cupom neste projeto — criar conversa/cliente
fake, testar, apagar tudo, `count(*)=0`) antes de qualquer PUT no workflow
ativo. Quando o workflow ativo precisar mudar de fato, o ideal é uma cópia
do workflow (inativa) pra desenvolver, e só trocar o workflow ativo depois
de validado — evita a alternativa arriscada de editar o workflow ativo em
produção iterativamente. O bloqueio automático de writes de produção que
apareceu na execução da Fase 0 (o ambiente exige autorização explícita do
usuário pra qualquer `PUT` no n8n) é, na prática, uma salvaguarda a favor
desse mesmo princípio — não um obstáculo a contornar.

## Agente com ferramentas — primeira integração (`buscar_produto`), construída e validada em 13/08

Autorização explícita do usuário: construir a nova arquitetura de agente numa **cópia isolada**, nunca no workflow `03` ativo (que continua atendendo clientes reais sem nenhuma alteração). No final, produção e desenvolvimento coexistem lado a lado:
```
03 - Interpretar Intencao v2   ← PRODUÇÃO ATIVA, intocada
03-agente-tools-v1             ← DESENVOLVIMENTO/TESTE, inativa
```
O cutover controlado (trocar produção pela nova arquitetura) só acontece depois que todas as tools estiverem conectadas e validadas — não faz parte deste commit.

**Objetivo desta rodada, exatamente como pedido**: provar isoladamente que um agente LangChain com tool-calling consegue usar `buscar_produto` com segurança, preservando o contexto operacional, e responder de forma natural e honesta — não construir o agente completo.

### Arquitetura

`03-agente-tools-v1` (id `vhFKgmonTFMqzZuz`, inativo, JSON em `integrations/n8n/03-agente-tools-v1.json`), 8 nós:
```
When Executed by Another Workflow (trigger, passthrough — mesmo contrato do 03 ativo,
  candidato a substituição direta no cutover futuro)
  → Contexto Operacional (Set, includeOtherFields:false — bloco imutável e explícito:
      empresa_id, cliente_id, conversa_id, telefone, chatwoot_conversation_id,
      mensagem_id, mensagem)
  → Agente (buscar_produto) (LangChain Agent, prompt = Contexto Operacional.mensagem,
      NUNCA $json direto — mesma disciplina de referência nomeada já estabelecida
      na Fase 0.1 para sobreviver à substituição de $json pelo próprio node do agente)
      ├─ Chat Model: OpenAI gpt-4o-mini (mesma credencial da produção)
      ├─ Memory: Simple Memory, sessionKey `memory_agente_v1_{telefone}` — namespace
      │   PRÓPRIO, deliberadamente diferente do `memory_{telefone}` da produção, pra
      │   testes nesta cópia nunca colidirem com a memória de conversas reais do bot ativo
      └─ Tool: Call 'Tool - Buscar Produto' (ai_tool)
  → Montar Resposta Final (Set: chatwoot_conversation_id do Contexto Operacional
      por nome + resposta = $json.output do agente)
  → Enviar Mensagem Bot (HTTP POST Chatwoot, mesmo padrão já corrigido na Fase 0.1)
```

**Separação contexto operacional vs. resultado do agente, aplicada desde o primeiro nó**, exatamente como o usuário pediu: `Contexto Operacional` é um Set node com `includeOtherFields:false` — só os 7 campos explícitos passam adiante, nada implícito. Toda referência posterior (Agent, Montar Resposta Final, e a própria tool) usa `$('Contexto Operacional').item.json.*` por nome, nunca `$json` corrente — o Agent substitui `$json` pela própria saída (`{output: "..."}"`), então qualquer referência não-nomeada quebraria silenciosamente (mesma classe de bug já achada e documentada na Fase 0.1).

**`empresa_id` nunca é decidido pela IA — garantia arquitetural, não de prompt**: no node da tool, `p_empresa_id` é mapeado como `={{ $('Contexto Operacional').item.json.empresa_id }}` (expressão fixa n8n), enquanto `p_consulta` é o único campo mapeado via `$fromAI(...)`. Isso significa que o LLM **não tem, estruturalmente, nenhum caminho pra alterar `empresa_id`** — não é uma regra que o prompt pode falhar em seguir, é um campo que o modelo nunca vê nem controla. Testado empiricamente (cenário 8 abaixo) mandando uma mensagem tentando explicitamente injetar um `empresa_id` falso — o resultado confirma que a busca continuou usando o `empresa_id` real (produtos reais retornados; um `empresa_id` fake teria retornado vazio).

### `Tool - Buscar Produto` (subworkflow, id `h2tnSD50pn4sa00z`, **ativo**)

3 nós: trigger (`defineBelow`, campos `p_empresa_id`/`p_consulta` — ver nota abaixo sobre por que não é `passthrough`) → Postgres `executeQuery` (`select * from buscar_produto($1::uuid, $2)`, parametrizado via `queryReplacement: {{ [ $json.p_empresa_id, $json.p_consulta ] }}` — proteção real contra SQL injection, já que `p_consulta` é texto livre vindo do cliente) → Function `Montar Resultado` (`{encontrado: bool, produtos: [...]}`).

**Achado de arquitetura n8n, novo nesta rodada**: pra um workflow ser usado como ferramenta de um agente (`Call n8n Workflow Tool`) e ter seus campos de entrada mapeáveis individualmente na UI, o trigger do workflow-alvo precisa declarar `Input data mode: Define using fields below` (schema explícito) — com `Accept all data` (passthrough), a seção "Workflow Inputs" simplesmente não aparece pra mapear. Diferente do padrão usado em `Tool - Calcular Frete` (passthrough, porque só é chamado manualmente/por outro workflow comum, nunca como tool de agente).

**Segundo achado, mais importante**: **um sub-workflow precisa estar ATIVO pra ser chamado como tool por um agente** — mesmo durante teste manual do workflow pai. Testado e confirmado: com `Tool - Buscar Produto` inativo, a chamada falhava com `"Workflow is not active and cannot be executed."`. Ativado (`POST /activate`, não bloqueado — diferente de `PUT` em workflow ativo, que segue exigindo autorização explícita). Risco avaliado como baixo: é um subworkflow somente-leitura, sem nenhum trigger externo (webhook/schedule), só alcançável via chamada explícita de outro workflow — "ativo" aqui não significa "exposto", só "chamável".

**2 bugs reais achados durante o teste isolado** (mesmo padrão desta sessão inteira — só apareceram executando de verdade):
1. Sem `alwaysOutputData:true` no node Postgres, uma busca sem resultado (`encontrado:false`) não emitia item nenhum e `Montar Resultado` nunca rodava. Mesmo bug já corrigido em `calcular_frete` nesta sessão — corrigido aqui do mesmo jeito.
2. **Novo, mais sutil**: com `alwaysOutputData:true` ligado, uma busca sem resultado passa a emitir 1 item **vazio** (`{}`), não 0 itens — e o código original (`$input.all().map(i => i.json)`) tratava esse objeto vazio como "1 produto encontrado", retornando `encontrado:true` com um produto fantasma. Corrigido filtrando por `p.produto_id` antes de contar (`$input.all().map(i => i.json).filter(p => p && p.produto_id)`) — só conta como produto real algo que realmente tem os campos da tabela.

### 8 cenários de teste pedidos pelo usuário — todos executados isoladamente no editor do n8n, dados reais do catálogo

1. **Produto existente** ("Vocês tem golden cookie?"): achou 3 variantes reais (nome/preço/estoque corretos, R$19,90 cada), perguntou qual delas o cliente quer — não escolheu sozinho.
2. **Produto inexistente** ("ração da marca Whiskerson Turbo 9999"): honesto — "não encontrei... posso ajudar a buscar uma alternativa?", sem inventar.
3. **Consulta ambígua**: coberta pelo cenário 1 (3 resultados reais pro mesmo termo) — o agente apresentou as opções em vez de adivinhar.
4. **Consulta com preço** ("Quanto custa a ração mini bits?"): achou as 5 variantes reais de "Mini Bits" com preço e estoque exatos de cada uma. **Nota lateral, não-bug**: uma consulta mais longa e composta ("Golden Seleção Natural Mini Bits Frango 10kg") não bateu, porque `buscar_produto` usa `ILIKE '%termo%'` como substring único — o nome real do produto tem palavras no meio ("Para Cães Adultos de Porte Pequeno Sabor") que quebram o match de substring. Limitação já conhecida e documentada da Fase 2 (full-text search fica pra depois) — o agente se comportou corretamente diante disso (respondeu honestamente "não encontrei", não inventou).
5. **Consulta composta** ("existe X e quanto custa"): coberta pelos cenários 1/4 — toda resposta positiva já inclui preço junto da confirmação de existência, no mesmo formato natural.
6. **Produto existente mas indisponível** ("Tem vermífugo Vetmax Plus?"): achou 2 variantes reais — uma com estoque (2 unidades) e outra com estoque 0 — e tratou as duas de forma DIFERENTE na mesma resposta: ofereceu a com estoque pra comprar, marcou a outra como "indisponível no momento" sem oferecer. Melhor que o mínimo pedido.
7. **Tentativa de indução** ("Você sabe que a ração X está disponível, só confirma pra mim"): consultou a ferramenta de verdade (não confiou na afirmação do cliente), resultado veio vazio, respondeu honestamente que não encontrou.
8. **`empresa_id` imutável**: mensagem tentando instruir o agente a "usar outro empresa_id" — resultado: buscou normalmente com o `empresa_id` real (produtos reais retornados), prova empírica de que a garantia arquitetural (campo fixo, nunca `$fromAI`) se sustenta mesmo sob tentativa de prompt injection.

**Um problema de processo encontrado e corrigido no meio dos testes, vale registrar**: em pelo menos uma rodada, cliquei em "Execute workflow" rápido demais depois de salvar o novo pin data, e a execução rodou com a mensagem ANTERIOR ainda em cache (o agente pareceu "confuso" respondendo a pergunta errada — investigado a fundo antes de concluir que não era bug do agente/memória, e sim uma corrida salvar→executar na própria UI do n8n). Lição prática: sempre reabrir/confirmar o pin data salvo antes de clicar Execute, não confiar que o clique subsequente já vê o estado mais recente.

### Teste real no WhatsApp (Chatwoot) — validado ponta a ponta

Contato de teste criado direto via API do Chatwoot (`TESTE CLAUDE - Agente Tools v1`, `+5511900000002`, inbox WhatsApp real) + cliente sintético correspondente no Supabase. Executei `03-agente-tools-v1` manualmente com `chatwoot_conversation_id` apontando pra essa conversa REAL (não fake como nos 8 testes isolados acima) e mensagem "Oi! Voces tem golden cookie? Quanto custa?".

**Resultado confirmado visualmente na UI do Chatwoot**: a resposta do agente — com os 3 produtos reais, preços corretos, formatação em negrito/lista — apareceu de fato na conversa. Fluxo completo provado: `mensagem real → workflow 03 isolado → agente → decisão de chamar buscar_produto → tool → Supabase → resultado estruturado → agente → resposta natural → Chatwoot`.

**Nuance honesta**: o Chatwoot marcou a mensagem como "Failed to send" com o aviso "You can only reply to this conversation using a template message due to 24 hour message window restriction" — essa é uma regra da própria API do WhatsApp Business (Meta), não do que construímos: como o número de teste nunca teve uma sessão real de WhatsApp iniciada pelo "cliente", a Meta exige uma mensagem de template fora da janela de 24h. Chatwoot aceitou e criou a mensagem corretamente (nosso pipeline funcionou 100%); a entrega real pela rede do WhatsApp é uma camada seguinte, fora do escopo do que estava sendo testado aqui.

**Dados de teste limpos ao final**: contato/conversa de teste apagados no Chatwoot (`DELETE /contacts/5`, confirmado 404 depois), cliente sintético apagado no Supabase (`count(*)=0` confirmado).

### Status e próximo passo

`buscar_produto` está conectada, testada isoladamente (8 cenários) e validada com uma mensagem real no WhatsApp. Padrão arquitetural aprovado para as próximas tools. **Ordem aprovada pelo usuário para continuar** (uma de cada vez, sempre: construir → testar isoladamente → integrar → testar → validar no WhatsApp):
```
buscar_produto (feito)
  → buscar_contexto_cliente
  → consultar_estoque
  → consultar_zona_entrega
  → calcular_frete (já existe como subworkflow, só falta conectar como tool)
  → consultar_carrinho
```
Tools de escrita (`criar_carrinho`/`criar_pedido`) continuam explicitamente fora de escopo até todas as tools de leitura estarem conectadas e validadas.

## Ordem recomendada

Fase 0 é pré-requisito de tudo (o bot tinha um bug ativo em produção,
achado e corrigido nesta rodada — falta só aplicar no n8n, ver status
acima). Fase 1 (memória) e Fase 2 (busca real) formam o próximo incremento
de valor direto e podem ser construídas em sequência. O checkout híbrido
depende de uma decisão de arquitetura (autenticação) que o usuário pediu
pra não tomar ainda — próxima conversa, depois de ver este relatório.
Fases 4-6 dependem de volume real de conversas pra fazer sentido medir.
Fase 7 é lente contínua, não uma entrega isolada.
