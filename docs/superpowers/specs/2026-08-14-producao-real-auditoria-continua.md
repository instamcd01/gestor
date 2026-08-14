# Produção real + auditoria contínua do agente WhatsApp — arquitetura

## Contexto e decisão do usuário (14/08)

Depois de aprovar toda a camada de leitura + carrinho + `criar_pedido` + multimodal
(ver `gestor_whatsapp_automacao_conversacional` na memória), o usuário mudou a
estratégia de rollout: em vez de uma whitelist pequena de clientes, quer que o
agente novo (`03-agente-tools-v1`) passe a atender **clientes reais em produção
de verdade**, nas capacidades já validadas, tratando este período como um
**laboratório de produção controlado** — não um piloto artificial.

Duas condições explícitas:
1. **Isso não é "colocar no ar e observar manualmente"** — precisa de uma camada
   de auditoria assíncrona, automática, que reconstrua e avalie cada atendimento,
   agrupe padrões, e gere um relatório periódico.
2. **Não bloquear o aprendizado esperando a auditoria ficar perfeita** — subir o
   atendimento real primeiro, com o mínimo de observabilidade necessário pra
   reconstruir um atendimento depois, e construir a auditoria em cima disso, de
   forma incremental.

**Capacidades autorizadas para produção real agora**: texto, áudio, imagem,
interpretação de pedidos, busca de produtos, histórico do cliente,
disponibilidade, zona de entrega, cálculo de frete, montagem/alteração de
carrinho, revisão, transferência para humano.

**Fora do escopo desta virada** (não mencionado na lista acima, portanto
continua bloqueado): `criar_pedido` e qualquer pagamento. Só entra em produção
depois que a especificação de pagamento (seção própria abaixo) estiver
implementada e testada com o mesmo rigor de toda tool anterior, e o usuário
aprovar explicitamente — ele foi explícito: "não altere checkout/pagamento além
do que já foi definido sem me consultar".

## Estado real do sistema, confirmado por consulta direta ao banco (14/08, não suposição)

Antes de desenhar qualquer coisa nova, consultei o schema e os dados reais
(projeto Supabase `dwswpwxnzjgoohucngbb`) para saber exatamente o que já existe:

- **`conversas` tem 1 única linha** — o registro órfão da empresa "Delivery Pet"
  legado (`chatwoot_conversation_id=4`, já documentado como candidato a
  limpeza histórica, não apagado por decisão do usuário). Ou seja: **nenhuma
  conversa real da empresa atual passou pelo pipeline ainda** — confirma o que
  a memória já registrava (atendimento hoje é 100% manual).
- **`mensagens` tem 132 linhas, 100% `direcao='incoming', tipo='text'`.** Duas
  implicações diretas:
  1. **Nenhuma resposta do bot é persistida hoje.** O node "Enviar Mensagem
     Bot" em `03-agente-tools-v1.json` (linha 218) manda a resposta pro
     Chatwoot (`message_type: "outgoing"`) mas nunca grava em `mensagens`. Uma
     reconstrução de atendimento hoje só teria metade da conversa.
  2. Nenhum áudio/imagem real de cliente passou pelo sistema fora dos testes
     sintéticos desta sessão (todos limpos ao final, `count=0` confirmado).
- **`automacao_eventos` está com ZERO linhas.** A tabela existe e foi testada
  exaustivamente com dados sintéticos (sempre limpos depois), mas hoje só é
  escrita pelas 3 tools de ESCRITA (`alterar_carrinho`, `revisar_carrinho`,
  `criar_pedido`) para fins de idempotência — **nenhuma das 6 tools de LEITURA
  registra evento nenhum**. Não dá pra saber hoje, de fora, se `buscar_produto`
  foi chamado numa conversa real, com que parâmetro, ou o que retornou.
- **Não existe nenhum conceito de "atendimento" (sessão) no schema.** `conversas`
  é uma linha por telefone+empresa, viva indefinidamente — não há fronteira
  entre "esse cliente mandou uma mensagem em março" e "esse cliente mandou uma
  mensagem hoje" a não ser inspecionar timestamps manualmente.
- **`mensagens` ainda tem `authenticated` com grant de INSERT** (achado
  incidental durante esta investigação) — inerte hoje porque RLS
  (`mensagens_isolamento`, `cmd=ALL`) restringe a linhas cuja `conversa_id`
  pertence à própria empresa do usuário autenticado, mas é grant desnecessário
  pro caso de uso real (só o pipeline via `service_role` deveria escrever aqui).
  Fica registrado como item de higiene pra Fase 1, não é vazamento ativo.
- **Nenhuma tabela de auditoria, score, padrão ou relatório existe** — é
  greenfield completo, confirmado por `list_tables`.
- `pedidos.score_satisfacao` (numeric) já existe na tabela de pedidos, sem
  nenhum uso hoje — não é o lugar certo pra guardar o score do atendimento
  (o atendimento pode nem virar pedido), mas fica registrado como um sinal de
  que a intenção de medir satisfação já existia antes desta sessão.

## Arquitetura proposta — visão geral

```
Cliente (WhatsApp)
      │
      ▼
Chatwoot ──webhook──▶ 01 Router ──▶ 02 Processar ──▶ 03 Agente (tools)
      ▲                                                    │
      │                                                    ▼
      └──────────────── resposta ◀── Enviar Mensagem Bot ──┘
                                            │
                                            ▼
                              [NOVO] Salvar Mensagem Bot (outgoing)
                                            │
                                            ▼
                                   mensagens.atendimento_id
                                            │
                    (toda tool, leitura ou escrita) automacao_eventos
                                            │
                              ┌─────────────┴─────────────┐
                              ▼                            ▼
                 [NOVO] Fechar Atendimentos       [NOVO] Auditor de
                 Inativos (cron, fecha sessão)     Atendimento (cron,
                              │                     assíncrono, só leitura
                              ▼                     de produção)
                        atendimentos                        │
                     (encerrado_em, motivo)                 ▼
                                                  auditorias_atendimento
                                                              │
                                       ┌──────────────────────┴───────────────────┐
                                       ▼                                          ▼
                         [NOVO] Agrupador de Padrões               [NOVO] Relatório Diário
                            (semanal, LLM, agrupa                    (diário, agrega auditorias
                             problemas_detectados)                    + padrões + alertas)
                                       │                                          │
                                       ▼                                          ▼
                              padroes_atendimento                      relatorios_atendimento
                                                                     (canal de entrega: EM ABERTO)
```

O auditor, o agrupador de padrões e o relatório **nunca escrevem em
`conversas`/`carrinho`/`pedidos`/prompts/workflows** — só leem produção e
escrevem nas tabelas novas de análise. Qualquer mudança real (prompt, RPC,
workflow) continua sendo decisão e execução manual, revisada por você, exatamente
como todo o resto deste projeto até aqui.

## Fase 1 — Observabilidade mínima + spec de pagamento (bloqueia o cutover)

Objetivo: garantir que, a partir do momento em que o agente atender um cliente
real, dá pra **reconstruir integralmente** esse atendimento depois (as duas
direções da conversa, toda tool chamada, o resultado de cada uma, e onde ele
começa/termina).

### 1a. Logar mensagens de saída do bot

**Arquivo**: `integrations/n8n/03-agente-tools-v1.json`.

Novo node `Salvar Mensagem Bot` (Postgres `executeQuery`, mesmo padrão do
`Preprocessar Mensagem Multimodal`), logo depois de `Enviar Mensagem Bot`,
`onError:continueRegularOutput` (falha de log nunca deve impedir a resposta
já enviada ao cliente — a resposta já saiu, isso é só rastro):

```sql
INSERT INTO mensagens (conversa_id, cliente_id, direcao, tipo, conteudo, atendimento_id)
VALUES ($1, $2, 'outgoing', 'text', $3, $4)
```

Parâmetros: `conversa_id`/`cliente_id`/`atendimento_id` de `Contexto Operacional`
(fixos, nunca `$fromAI`), `$3` = `$json.resposta` (o texto que já foi mandado
pro Chatwoot, não uma paráfrase).

### 1b. Logar toda chamada de tool (leitura + escrita)

**Arquivos**: os 9 subworkflows `tool-*.json` — cada `Function` node "Montar
Resultado" ganha um passo irmão (Postgres `executeQuery`, mesmo padrão de
idempotência já usado em `alterar_carrinho`/`revisar_carrinho`/`criar_pedido`,
`onError:continueRegularOutput`) que insere em `automacao_eventos`:

```sql
INSERT INTO automacao_eventos (empresa_id, conversa_id, mensagem_id, etapa, tool_nome, detalhes, duracao_ms)
VALUES ($1, $2, $3, 'tool_call', $4, $5, $6)
```

`detalhes` = `{"input": {...parametros recebidos...}, "output": {...o mesmo
jsonb que já vai pro agente...}}` — nunca mais do que o que já trafega pro
LLM (a tabela não tem grant público, mas ainda assim não há motivo pra
duplicar ali um dado que a própria tool já decidiu não expor). `duracao_ms`
calculado via `$now` no início/fim do subworkflow (n8n já expõe
`$execution.resumeUrl`/tempo de execução, ou basta 2 nós `Set` com timestamp).

As 3 tools de escrita já gravam em `automacao_eventos` com `etapa` própria
(`criado`, etc, usada pra idempotência) — este passo novo é **adicional**
(`etapa='tool_call'`), não substitui a gravação de idempotência existente.

### 1c. Conceito de "atendimento" (sessão)

Nova tabela:

```sql
CREATE TABLE atendimentos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL,
  conversa_id uuid NOT NULL REFERENCES conversas(id),
  cliente_id uuid REFERENCES clientes(id),
  iniciado_em timestamptz NOT NULL DEFAULT now(),
  encerrado_em timestamptz,
  motivo_encerramento text, -- preenchido pelo job de fechamento OU pelo auditor
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON atendimentos (conversa_id, encerrado_em);
ALTER TABLE atendimentos ENABLE ROW LEVEL SECURITY;
-- sem policy pra anon/authenticated ainda (só service_role via RPC abaixo),
-- mesma disciplina de automacao_eventos
```

`mensagens` ganha `atendimento_id uuid REFERENCES atendimentos(id)` (nullable,
aditivo, não quebra as 132 linhas existentes).

Nova RPC, chamada pelo node `Contexto Operacional` do agente (ou por um node
logo antes dele) em toda mensagem nova, ANTES de salvar a mensagem:

```sql
CREATE OR REPLACE FUNCTION resolver_atendimento_atual(
  p_conversa_id uuid, p_cliente_id uuid, p_empresa_id uuid,
  p_gap_minutos int DEFAULT 30
) RETURNS uuid ...
-- procura atendimentos.encerrado_em IS NULL para esta conversa_id
-- com iniciado_em (ou última mensagem) dentro de p_gap_minutos: reusa
-- senão: cria uma linha nova e devolve o id novo
```

`SECURITY DEFINER`, grant só pra `service_role` (mesmo padrão de todas as RPCs
deste projeto), `EXECUTE` revogado de `anon`/`authenticated` explicitamente no
mesmo `CREATE`.

Fechamento (job agendado, novo workflow n8n `Fechar Atendimentos Inativos`,
Schedule Trigger a cada 15 min):

```sql
UPDATE atendimentos
SET encerrado_em = now(), motivo_encerramento = 'timeout_sem_atividade'
WHERE encerrado_em IS NULL
  AND id NOT IN (SELECT atendimento_id FROM mensagens WHERE created_at > now() - interval '30 minutes')
```

O `motivo_encerramento` gravado aqui é só um heurístico técnico
("inatividade") — a classificação de verdade (resolvido pelo agente,
transferido, abandonado, pedido criado) é responsabilidade do **auditor**
(Fase 2), que tem o contexto completo pra julgar isso, não este job.

### 1d. Especificação definitiva de pagamento

Substitui a spec anterior (3 valores em português, sem Pix) registrada em
`gestor_whatsapp_automacao_conversacional`. Códigos canônicos:

| Código | Uso |
|---|---|
| `PIX` | novo — não existia antes na tool de `criar_pedido` |
| `CARTAO_CREDITO` | renomeado de `'Cartão de Crédito'` |
| `CARTAO_DEBITO` | renomeado de `'Cartão de Débito'` |
| `DINHEIRO` | renomeado de `'Dinheiro'` |

**Regra de desambiguação** (comportamental, no prompt da tool — não é uma
decisão de risco financeiro por si só, é interpretação de linguagem, então
fica na camada de LLM; o gate determinístico continua sendo a whitelist da
RPC, que já rejeita qualquer valor fora dos 4 códigos):
- Cliente diz só "cartão" → agente pergunta literalmente "Claro 😊 Crédito ou
  débito?" antes de prosseguir.
- Cliente já disse "crédito" ou "débito" explicitamente → não pergunta de novo.
- Nunca dizer "na entrega" na conversa (já não há cobrança online implementada,
  então a frase não muda o comportamento, só a redação da resposta).

**Onde muda**:
- RPC `criar_pedido_whatsapp` (só existe no Supabase): `CREATE OR REPLACE`
  trocando a lista de validação de `('Dinheiro','Cartão de Crédito','Cartão de
  Débito')` para `('PIX','CARTAO_CREDITO','CARTAO_DEBITO','DINHEIRO')`.
  Confirmar antes se alguma linha de teste teria ficado em `pedidos` com o
  valor antigo (não deveria, dado que os testes sempre limparam os dados
  sintéticos) — se houver, é dado de teste, não migração de dado real.
- `integrations/n8n/tool-criar-pedido.json`, parâmetro `p_tipo_pagamento`
  (linha 660 do agente + o node correspondente na tool): descrição do
  `$fromAI` reescrita pros 4 códigos + regra de desambiguação embutida na
  própria descrição do parâmetro (não só no system prompt — lição já registrada
  nesta sessão: reforço em prosa no system prompt sozinho é frágil, o texto
  que acompanha o parâmetro da tool pesa mais na decisão do modelo).
- `integrations/n8n/03-agente-tools-v1.json`, system prompt: seção de
  pagamento reescrita com os 4 códigos e a regra de desambiguação.

**Esta parte fica bloqueada para implementação até você revisar e aprovar esta
seção especificamente** — é a única mudança de pagamento autorizada; nenhuma
outra (cartão online, gateway, cobrança automática) entra nesta fase.

### Critério de "Fase 1 pronta"

Mesmo rigor de toda fase anterior: testar cada peça isolada (RPC via SQL
direto, subworkflow isolado no editor), depois em conjunto no agente isolado,
depois validar com uma conversa real via Chatwoot — confirmando que, ao final,
dá pra reconstruir 100% de um atendimento de teste (mensagens dos dois lados +
toda tool chamada + atendimento com início/fim) só consultando o banco.

## Fase 1.5 — Cutover de produção (capacidades já validadas, sem pagamento)

Depois da Fase 1 validada: conectar `03-agente-tools-v1` como o workflow que
realmente responde no pipeline `01 Router → 02 Processar → 03`, no lugar do
antigo `03 - Interpretar Intencao v2` (que nunca atendeu cliente real de
verdade — ver correção já registrada na memória). `criar_pedido` continua
com sua tool desconectada (ou o gate de confirmação nunca chega a autorizar,
a decidir na hora — mais seguro simplesmente não conectar a tool ainda,
mesmo padrão já usado durante toda a Fase 0.2/leitura) até você aprovar a
especificação de pagamento em produção.

**Ponto a validar antes do cutover, não decidido ainda**: como o Chatwoot
roteia conversas — hoje, sem bot, um atendente humano provavelmente recebe
todas as conversas na fila padrão do inbox. Ligar o webhook `01` significa
que TODA mensagem nova passa a ser respondida pelo agente automaticamente.
Precisa confirmar com você se é isso mesmo que quer (mensagem chega → agente
responde direto, sem um humano na frente) ou se ainda quer um approval humano
por conversa nos primeiros dias — isso é diferente de "whitelist de clientes"
(que você já descartou), é sobre o modo de operação do primeiro dia.

## Atualização 14/08 (mesma sessão) — reversão da estratégia de pagamento + arquitetura final de `automacao_eventos`

Depois da Fase 1 (banco) implementada e testada, e da Fase 1.5 prestes a começar sem `criar_pedido`, o usuário reverteu essa decisão: quer **liberar o ciclo completo de compra pra clientes reais agora** (leitura+carrinho+`criar_pedido`+as 4 formas de pagamento), não faseado. Todas as proteções já construídas (evidência textual determinística, revalidação de estoque/frete no momento, idempotência, concorrência, identidade nunca controlada pelo LLM) continuam exatamente como estão — a liberação é sobre ROTEAMENTO/disponibilidade da tool, nunca sobre enfraquecer validação. Detalhe completo em `gestor_whatsapp_piloto_pagamento_decisao` na memória.

**Achado real durante essa revisão**: lendo `_finalizar_pedido_core`, confirmei que nenhum dos 4 códigos de pagamento do WhatsApp (incluindo PIX) gera cobrança automática — `status_pagamento` sempre nasce `'pendente'`, e só `tipo_pagamento='Pagamento Online'` (fluxo exclusivo do site, Mercado Pago Payment Brick) muda esse comportamento. Ou seja: hoje, "Pix" no WhatsApp é o cliente informando a intenção de pagamento, não uma cobrança real gerada — a confirmação de pagamento continua manual, igual pedido de loja física. O estágio "resultado do pagamento" do funil que o usuário quer medir **não existe como sinal automatizável ainda** — fica registrado como gap real, não implementado silenciosamente como se existisse.

### Arquitetura final de `automacao_eventos` (substituindo o rascunho da Fase 1b acima)

Pedida explicitamente pelo usuário antes de instrumentar qualquer tool, com uma lista de requisitos específicos — respondendo um a um:

**1. Dois tipos de evento, nunca misturados na mesma linha:**
- **`etapa='tool_call'`** — traço de baixo nível, UMA linha por chamada de tool (leitura OU escrita), sempre que a tool executa. É o rastro bruto: "o que foi chamado, com que parâmetro, com que resultado". Nunca usado pra autorizar nada, só observabilidade.
- **Marcos de negócio** (`etapa` com valor próprio, já existe parcialmente hoje) — `intencao_registrada` (proposta pendente de `alterar_carrinho`), `carrinho_alterado`, `revisao_confirmado`, `criado` (pedido), `erro` (pedido), mais 2 novos: `transferencia_humano`, `atendimento_encerrado`. Continuam com a MESMA constraint de idempotência já existente (`automacao_eventos_mensagem_tool_etapa_uniq`), porque são as linhas que decisões financeiras/críticas dependem. `tool_call` NUNCA entra nessa constraint — não precisa, não autoriza nada, duplicar uma leitura só significa "foi chamado duas vezes", que é a verdade, não um bug.

**2. Campos por evento** (schema final, aditivo ao que já existe):
```sql
ALTER TABLE automacao_eventos ADD COLUMN atendimento_id uuid REFERENCES atendimentos(id);
ALTER TABLE automacao_eventos ADD COLUMN sucesso boolean;
CREATE INDEX idx_automacao_eventos_atendimento ON automacao_eventos (atendimento_id);
CREATE INDEX idx_automacao_eventos_mensagem ON automacao_eventos (mensagem_id);
```
`detalhes` (jsonb, já existe) pra `tool_call`: `{"input": {...só os parametros AI-controlled, nunca empresa_id/cliente_id/conversa_id que já são colunas}, "output": {...exatamente o mesmo jsonb que a tool já devolve pro agente, nunca o retorno bruto pré-whitelist da RPC}}`. Pra marcos de negócio: mantém o formato já usado hoje (ex.: `{autorizado, pedido_id, status}` pra `criado`).

**3. Relação atendimento_id / conversa_id / mensagem_id / tool**: toda linha carrega os 3 IDs. Hoje só as tools de ESCRITA recebem `conversa_id`/`mensagem_id` como parâmetro — as 6 de leitura não. Pra logar de forma útil, as 6 tools de leitura ganham `p_conversa_id`/`p_mensagem_id`/`p_atendimento_id` como **parâmetros fixos novos** (nunca `$fromAI`, vindos de `Contexto Operacional`/`Resolver Atendimento` — mesma garantia arquitetural já usada em toda tool existente), só pra permitir o log; a lógica de negócio de cada RPC de leitura não muda em nada.

**4. Relacionar resposta do agente às tools usadas**: `mensagens` ganha `mensagem_id_origem uuid` (nullable, só preenchido em linhas `outgoing`) apontando pro `id` da mensagem `incoming` que originou aquele turno do agente. Como toda linha de `tool_call` daquele turno também carrega o mesmo `mensagem_id` (o da mensagem incoming), a correlação fica direta: `mensagens.mensagem_id_origem = automacao_eventos.mensagem_id` — nenhuma tabela nova, 1 coluna aditiva.

**5. Erros e retries**: `sucesso=false` + `detalhes.erro` (mensagem, nunca stack trace bruto) quando uma tool falha tecnicamente (timeout, erro de rede, exceção). Retry (do n8n ou o próprio agente rechamando) simplesmente gera outra linha `tool_call` — não precisa de tratamento especial, a sequência de linhas já conta a história ("tentou, falhou, tentou de novo, funcionou").

**6/7. Idempotência e duplicação**: só os marcos de negócio (a constraint já existente) precisam de garantia de não-duplicação, porque são a base de decisões financeiras — isso já está testado e não muda. `tool_call` é telemetria pura, apêndice, nunca fonte de verdade pra nenhuma decisão — duplicar não corrompe nada.

**8/9. O que nunca é registrado / precisa sanitização**: a regra é simples porque já existe — o `detalhes.output` de um `tool_call` é SEMPRE o mesmo jsonb que já passou pela whitelist de cada tool (o Function "Montar Resultado" já filtra 🟡/🔴 antes de chegar no LLM, ver auditoria de Data Exposure já feita). Logar depois desse ponto, nunca antes, significa que o log nunca pode vazar mais do que o próprio agente já vê. Nenhuma credencial passa por nenhuma tool hoje (confirmado na auditoria de 13/08), então não há esse risco aqui. `detalhes.input` inclui só os parâmetros que o LLM efetivamente controla (`p_consulta`, `p_quantidade_desejada`, `p_operacao`, `p_produto_id`, `p_tipo_pagamento`, etc.) — nunca repete identidade (`empresa_id`/`cliente_id`/`conversa_id`), que já são colunas próprias.

**10. Como o auditor usa isso**: pra reconstruir um atendimento, a query é `mensagens` (todas as linhas do `atendimento_id`, ordenadas por `created_at`) `LEFT JOIN automacao_eventos` (mesmo `atendimento_id`, ordenadas) — dá pra intercalar mensagem→tool_call(s)→mensagem seguinte na ordem real. Os marcos de negócio (`etapa != 'tool_call'`) dão o funil sem precisar re-derivar de tool_call: presença de `carrinho_alterado` = chegou em carrinho; `revisao_confirmado` = chegou em confirmação; `criado` (tool_nome='criar_pedido') = virou pedido, com `detalhes.tipo_pagamento`(a adicionar no resultado hoje devolvido) pra saber a forma escolhida.

### Implementação (ordem revisada da instrumentação, task tracker já reflete isso)

1. Migration: `atendimento_id`, `sucesso` em `automacao_eventos`; `mensagem_id_origem` em `mensagens`; adicionar `tipo_pagamento` ao jsonb de retorno de `criado` em `criar_pedido_whatsapp` (hoje só devolve `pedido_id`/`status`).
2. Adicionar `p_conversa_id`/`p_mensagem_id`/`p_atendimento_id` fixos nas 6 tools de leitura (subworkflow + node de chamada no agente).
3. Instrumentar as 9 tools: node `Logar Tool Call` (Postgres INSERT, `onError:continueRegularOutput`) + node `Restaurar Saída` (repassa o output original de "Montar Resultado", já que o node Postgres substitui `$json`) depois de cada "Montar Resultado".
4. Workflow `Fechar Atendimentos Inativos` (cron).
5. Testar reconstrução completa de um atendimento sintético via SQL puro antes de considerar pronto.

## Fase 2 — Auditoria assíncrona por atendimento

Nova tabela:

```sql
CREATE TABLE auditorias_atendimento (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  atendimento_id uuid NOT NULL REFERENCES atendimentos(id),
  empresa_id uuid NOT NULL,
  gerado_em timestamptz NOT NULL DEFAULT now(),
  modelo_usado text NOT NULL,
  qualidade_geral numeric,      -- 0-100
  precisao numeric,
  seguranca numeric,
  naturalidade numeric,
  friccao numeric,              -- quanto menor, melhor -- ver definição abaixo
  resolucao text,               -- 'resolvido_agente' | 'transferido_humano' | 'abandonado' | 'pedido_criado' | 'sem_solucao'
  uso_tools numeric,            -- tools certas, na hora certa
  necessidade_humano boolean,
  necessidade_humano_evitavel boolean, -- transferiu mas o agente poderia ter resolvido?
  conversao boolean,
  problemas_detectados jsonb NOT NULL DEFAULT '[]', -- [{categoria, tipo, gravidade, descricao, evidencia}]
  recomendacao text,
  metadata jsonb DEFAULT '{}',
  UNIQUE (atendimento_id)
);
```

**Categorias fixas** (campo `categoria` dentro de cada item de
`problemas_detectados`, vocabulário fechado pedido por você): `precisao`,
`seguranca`, `ux_friccao`, `comportamento_conversa`, `uso_ferramentas`,
`conversao`, `recuperacao_falhas`, `intervencao_humana`.

**`tipo`** é um slug curto e livre (ex: `busca_produto_linguagem_natural`,
`pergunta_redundante`, `numero_estoque_vazado`) — não é um enum fechado,
porque a variedade real só vai aparecer com uso; é o campo que a Fase 3 usa
pra agrupar.

**Definição de `friccao`** (evita subjetividade): calculada a partir de sinais
objetivos que o próprio auditor já tem em mãos — nº de mensagens do cliente
no atendimento, nº de vezes que o agente pediu esclarecimento, nº de tools que
retornaram "não encontrado", se houve repetição de informação já fornecida
(auditor compara mensagens do cliente entre si). O auditor calcula o número a
partir desses sinais concretos citados em `evidencias`, nunca "no chute".

**Trigger**: novo subworkflow `Auditor - Avaliar Atendimento`, Schedule Trigger
(ex.: a cada 15-20 min), processa em lote todo `atendimentos` com
`encerrado_em IS NOT NULL` e sem linha correspondente em
`auditorias_atendimento`. Para cada um:
1. Reconstrói a transcrição completa (`mensagens` ordenadas por
   `created_at`, incluindo `direcao`/`tipo`/`transcricao`/`interpretacao`
   quando existir).
2. Busca todos os `automacao_eventos` da mesma `conversa_id`/janela de tempo
   do atendimento (todas as tools chamadas + resultado).
3. Busca o estado final relevante (existe `pedido_id` vinculado? o
   `conversas.estado` terminou como `atendente`?).
4. Chama um LLM (Auditor) com um prompt estruturado pedindo o JSON exato do
   schema acima, **citando evidência textual** para cada `problema_detectado`
   (nunca uma alegação sem trecho da conversa por trás) — mesmo princípio já
   usado nesta sessão pra `mensagem_e_confirmacao_afirmativa`: decisão de
   risco não pode ser "confiar que o LLM generalizou direito", aqui a
   mitigação é exigir evidência textual auditável por você depois.
5. Insere em `auditorias_atendimento`.

**Sem efeito colateral em produção**: este subworkflow não tem nenhuma
credencial de escrita em `conversas`/`carrinho`/`pedidos`, só leitura +
INSERT nas tabelas novas de análise — a separação Agente/Auditor/Relatório/Você
que você pediu na seção 9 fica garantida arquiteturalmente (grant), não só
por convenção.

## Fase 3 — Agrupamento de padrões

Nova tabela:

```sql
CREATE TABLE padroes_atendimento (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL,
  periodo_inicio timestamptz NOT NULL,
  periodo_fim timestamptz NOT NULL,
  categoria text NOT NULL,
  tipo_problema text NOT NULL,
  ocorrencias int NOT NULL,
  total_atendimentos_periodo int NOT NULL,
  pct_atendimentos numeric NOT NULL,
  gravidade_media numeric,
  exemplos jsonb NOT NULL DEFAULT '[]', -- atendimento_id + trecho de evidência, poucos exemplos reais
  recomendacao text,
  gerado_em timestamptz NOT NULL DEFAULT now()
);
```

Novo subworkflow `Agrupador - Padroes Atendimento` (Schedule Trigger semanal,
ajustável): lê todo `problemas_detectados` das auditorias do período, agrupa
com um segundo LLM (não é um `GROUP BY` simples — o exemplo que você deu, do
"sachê de frango"/"nomes comerciais", exige julgamento semântico pra perceber
que 3 `tipo`s de superfície diferentes são o mesmo problema raiz de busca) e
grava `padroes_atendimento`. Cadência semanal em vez de diária no começo,
porque volume baixo de atendimentos reais no início tornaria um agrupamento
diário estatisticamente pouco útil — ajustável conforme o volume real crescer
(decisão sua, não bloqueante).

## Fase 4 — Relatório periódico

Novo subworkflow `Relatorio - Diario Atendimento`, Schedule Trigger diário,
agrega o período: contagem de atendimentos / resolvidos / transferidos /
abandonados / pedidos, top problemas (de `padroes_atendimento` mais recente +
contagem direta de `problemas_detectados` do dia, já que padrões só rodam
semanalmente), top oportunidades (recomendações agregadas por frequência),
alertas (qualquer `auditorias_atendimento` com `seguranca` abaixo de um
limiar, ou `problemas_detectados` com `gravidade` alta na categoria
`seguranca`/`precisao`, ou salto abrupto de `necessidade_humano`/abandono
comparado à média móvel).

**Em aberto, preciso da sua decisão**: onde esse relatório deve aparecer —
mensagem de WhatsApp pra você, e-mail, uma tabela (`relatorios_atendimento`)
que fica disponível pra você consultar quando quiser, ou outro canal? Não
implemento a entrega até isso estar definido (a geração/agregação em si não
depende dessa resposta).

## Fase 5 — Feedback humano no ciclo (parcialmente em aberto)

Quando `conversas.estado` vira `atendente` (handoff), o auditor da Fase 2 já
classifica `resolucao='transferido_humano'`. O que falta pra fechar o ciclo
completo que você pediu (por que o humano assumiu, o que ele corrigiu, se o
agente poderia ter resolvido) é **capturar as mensagens que o atendente humano
manda depois do handoff** — hoje só a resposta do BOT é logada (Fase 1a
resolve isso só pro bot). Precisa validar se o webhook do Chatwoot já dispara
pro n8n em mensagens enviadas por um atendente humano (mesmo endpoint
`message_created`, ou um evento diferente) — não confirmei isso ainda, fica
como investigação da Fase 5, não bloqueante pras fases anteriores. Se
confirmado, o mesmo padrão de `Salvar Mensagem Bot` (1a) se aplica a mensagens
humanas (`direcao='outgoing'`, sem `tool_nome`), e o Auditor ganha um segundo
prompt específico pra esse caso: "o que o atendente fez que o agente não
tinha feito, e isso era algo que o agente poderia ter feito sozinho?".

## Fase 6 — Habilitar `criar_pedido`/pagamento em produção real

Só depois de: Fase 1d (spec de pagamento) implementada e testada com todo o
rigor já padrão neste projeto (SQL isolado → subworkflow isolado → agente →
WhatsApp real) **e** aprovação explícita sua — não é liberado automaticamente
junto com o resto do cutover.

## Perguntas em aberto (bloqueiam só a fase específica, não o resto)

1. **Modelo do Auditor (Fase 2)**: usar o mesmo `gpt-4o-mini` do agente
   (mais barato, já em uso) ou um modelo mais forte já que não é tempo real e
   a qualidade do julgamento importa mais que velocidade/custo aqui?
2. **Canal de entrega do relatório (Fase 4)**: WhatsApp pra você, e-mail, ou
   uma tabela/consulta sob demanda?
3. **Modo de operação no primeiro dia do cutover (Fase 1.5)**: agente responde
   direto assim que ligar o webhook, ou você quer um humano de prontidão
   revisando as primeiras conversas antes delas saírem, nos primeiros dias?
4. **Cadência do agrupador de padrões (Fase 3)**: proposta é semanal pra
   começar (volume baixo no início) — confirma, ou prefere diário desde já
   mesmo com poucos dados?

## Ordem de implementação proposta (SUPERADA — ver "Fase 2 revisada" abaixo)

Fase 1 (observabilidade + pagamento, sem depender de nenhuma pergunta em
aberto) → Fase 1.5 (cutover, depende da pergunta 3) → Fase 2 (auditoria,
depende da pergunta 1) → Fase 3 (padrões, depende da pergunta 4) → Fase 4
(relatório, depende da pergunta 2) → Fase 5 (feedback humano, depende de
investigação do webhook Chatwoot) → Fase 6 (pagamento em produção, depende de
aprovação explícita separada).

Cada fase segue o mesmo processo já validado nesta sessão: construir → testar

---

# Fase 2 revisada — investigação e desenho (14/08, sessão seguinte)

Fase 1 e 1.5 completas (cutover feito, testado com pedido real via
Chatwoot, ver `docs/superpowers/specs/2026-08-14-mapa-dependencias-cutover-whatsapp.md`).
Usuário pediu um pedido de Fase 2 bem mais detalhado que o rascunho acima —
5 dimensões de classificação, exigência de o auditor **propor** melhoria
agrupada por causa raiz (não só listar problema), e análise do histórico
real do Chatwoot como baseline. Investigação feita antes de desenhar
qualquer schema novo, como já é padrão neste projeto.

## Achado crítico — não existe histórico real pra analisar

Consultei a API do Chatwoot diretamente (`GET /accounts/1/conversations?status=all`):
**a conta inteira tem 4 conversas, nenhuma de cliente real**:
- Conversa 3 e 4: de 07/03/2026, mesma leva de dado de setup/teste inicial
  já documentada (131 mensagens todas do mesmo timestamp).
- Conversa 14: "Beatriz Teste Multimodal", contato sintético meu da sessão
  de testes multimodais de 13-14/08.
- Conversa 15: contato sintético desta própria sessão (Fase 1.5).

Só existe 1 inbox no Chatwoot (`Delivery Pet API Oficial`, o número de
teste). **Não há segundo canal/número com histórico real escondido em
algum lugar que eu tenha encontrado.** Isso confirma de novo o que a
memória já registrava: o atendimento real de clientes hoje acontece por
fora deste sistema inteiramente (pessoalmente, telefone, ou WhatsApp
pessoal sem integração) — nunca passou pelo Chatwoot.

**Consequência pro pedido do usuário (item 8)**: não dá pra construir o
"baseline de como os clientes realmente conversam" a partir de dado que
não existe neste sistema. Duas opções, nenhuma implementada ainda:
1. **Esperar o tráfego real do cutover acumular** — já está rodando desde
   a Fase 1.5, mas hoje só no número de TESTE (não recebe cliente real
   ainda) — então o volume real ainda é zero.
2. **Se existir histórico real em outro lugar** (WhatsApp Business App
   pessoal, export de conversas, outro CRM) que o usuário tenha e queira
   usar como baseline, isso seria uma importação pontual — precisa saber
   se esse dado existe e em que formato antes de desenhar como importar.

Volume real hoje pra treinar/validar o auditor: 64 linhas em
`automacao_eventos`, todas de teste sintético meu (Fase 1/1.5), zero
atendimento de cliente real.

## Schema revisado de `auditorias_atendimento` — 5 dimensões

O rascunho anterior (seção "Fase 2" acima) tinha um schema genérico demais
pro que o usuário pediu agora — ele quer poder filtrar/agregar por
dimensão diretamente, não só vasculhar um jsonb. Campos fixos por
dimensão (mais fácil de indexar/agregar em SQL puro que tudo dentro de
`problemas_detectados`), evidência sempre obrigatória:

```sql
CREATE TABLE auditorias_atendimento (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  atendimento_id uuid NOT NULL REFERENCES atendimentos(id) UNIQUE,
  empresa_id uuid NOT NULL,
  gerado_em timestamptz NOT NULL DEFAULT now(),
  modelo_usado text NOT NULL,

  -- Dimensão 1: ATENDIMENTO (resultado objetivo, cruzado com dado real,
  -- nunca só opinião do auditor -- pedido_id/transferencia vêm de
  -- automacao_eventos/conversas, não de interpretação livre)
  resultado text NOT NULL CHECK (resultado IN (
    'resolvido_agente','transferido_humano','abandonado','pedido_criado','sem_solucao'
  )),
  pedido_id uuid REFERENCES pedidos(id),

  -- Dimensão 2: QUALIDADE
  qualidade_score numeric CHECK (qualidade_score BETWEEN 0 AND 100),
  teve_alucinacao boolean NOT NULL DEFAULT false,
  teve_informacao_incorreta boolean NOT NULL DEFAULT false,
  resposta_incompleta boolean NOT NULL DEFAULT false,
  resposta_confusa boolean NOT NULL DEFAULT false,

  -- Dimensão 3: EXPERIÊNCIA / fricção (métrica de primeira classe, pedida
  -- explicitamente) -- friccao_score derivado de sinais objetivos que o
  -- PRÓPRIO auditor calcula a partir da transcrição, nunca "no chute"
  friccao_score numeric CHECK (friccao_score BETWEEN 0 AND 100),
  qtd_perguntas_desnecessarias int NOT NULL DEFAULT 0,
  qtd_reformulacoes_cliente int NOT NULL DEFAULT 0,
  cliente_repetiu_informacao boolean NOT NULL DEFAULT false,
  sentimento_cliente text CHECK (sentimento_cliente IN ('satisfeito','neutro','frustrado','indeterminado')),

  -- Dimensão 4: OPERACIONAL (uso de tools -- cruzado com automacao_eventos
  -- de verdade, o auditor recebe a lista real de tool_call daquele
  -- atendimento, não infere sozinho quais tools existem)
  tools_usadas_incorretamente jsonb NOT NULL DEFAULT '[]', -- [{tool, motivo}]
  tools_faltantes jsonb NOT NULL DEFAULT '[]', -- [{tool_esperada, motivo}]
  tools_desnecessarias jsonb NOT NULL DEFAULT '[]',
  teve_erro_tecnico boolean NOT NULL DEFAULT false,

  -- Dimensão 5: COMERCIAL
  teve_intencao_compra boolean NOT NULL DEFAULT false,
  chegou_no_carrinho boolean NOT NULL DEFAULT false,
  venda_perdida boolean NOT NULL DEFAULT false,
  venda_perdida_motivo text,

  -- Transversal: toda ocorrência pontual, com evidência textual
  -- obrigatória (nunca uma alegação sem trecho real por trás)
  problemas_detectados jsonb NOT NULL DEFAULT '[]',
  -- [{categoria: precisao|seguranca|ux_friccao|comportamento|uso_ferramentas|comercial,
  --   tipo: slug curto (livre, é o que a Fase 3 agrupa por similaridade semântica),
  --   gravidade: baixa|media|alta,
  --   descricao: texto,
  --   evidencia: trecho literal da conversa}]

  resumo text NOT NULL, -- 2-3 frases, pro relatório não precisar reprocessar a conversa toda
  recomendacao text,
  metadata jsonb NOT NULL DEFAULT '{}'
);
CREATE INDEX ON auditorias_atendimento (empresa_id, gerado_em);
CREATE INDEX ON auditorias_atendimento (resultado);
REVOKE ALL ON auditorias_atendimento FROM PUBLIC, anon, authenticated;
```

**Input do auditor pra cada atendimento** (montado por SQL antes de chamar
o LLM, nunca o LLM "lembrando" sozinho): transcrição completa
(`mensagens` ordenadas por `atendimento_id`) + toda `automacao_eventos`
do mesmo período (tool_call + eventos de negócio) + resultado objetivo
(existe `pedido_id`? `conversas.estado` terminou `atendente`?). O LLM
preenche os campos SUBJETIVOS (qualidade, fricção, sentimento,
problemas) em cima desse contexto real — nunca decide sozinho se existe
pedido ou transferência, isso vem de dado, não de interpretação.

## `padroes_atendimento` — agrupamento por causa raiz, com recomendação concreta

O pedido do usuário é explícito: não quer "atendimento X teve problema",
quer "39% das buscas com 'sachê' falharam, causa X, sugestão Y". Isso
exige uma segunda passada de LLM (não dá pra fazer só com `GROUP BY` em
`tipo`, porque a mesma causa raiz aparece com `tipo`s de superfície
diferentes — já vimos isso na prática com "sachê de frango").

```sql
CREATE TABLE padroes_atendimento (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL,
  periodo_inicio timestamptz NOT NULL,
  periodo_fim timestamptz NOT NULL,
  categoria text NOT NULL,
  titulo text NOT NULL, -- "Busca não encontra produtos por nome comercial/apelido"
  ocorrencias int NOT NULL,
  total_atendimentos_periodo int NOT NULL,
  pct_atendimentos numeric NOT NULL,
  gravidade_media text,
  causa_provavel text NOT NULL,
  solucao_sugerida text NOT NULL,
  prioridade text NOT NULL CHECK (prioridade IN ('baixa','media','alta')),
  exemplos jsonb NOT NULL DEFAULT '[]', -- [{atendimento_id, chatwoot_conversation_id, evidencia}]
  gerado_em timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON padroes_atendimento FROM PUBLIC, anon, authenticated;
```

Subworkflow `Agrupador - Padroes Atendimento`: lê todo `problemas_detectados`
do período, manda pro LLM pedindo pra AGRUPAR semanticamente (não por
`tipo` exato) e, pra cada grupo com >= N ocorrências, preencher
`causa_provavel`/`solucao_sugerida`/`prioridade` — exatamente o formato
do exemplo que o usuário deu.

## Relatório — estrutura exata pedida

`relatorios_atendimento` (tabela) + subworkflow gerador, lendo
`auditorias_atendimento` + `padroes_atendimento` do período:
- **Resumo executivo**: contagem de atendimentos/resolvidos/transferidos/
  abandonados/pedidos, taxa de conversão.
- **Top problemas**: de `padroes_atendimento`, ordenado por
  `prioridade`+`ocorrencias` — problema/quantidade/impacto/exemplos/causa/
  solução/prioridade, exatamente os campos que o usuário pediu.
- **Top oportunidades**: mesma fonte, filtrado por categoria comercial.
- **Alertas**: qualquer `auditorias_atendimento` com `teve_alucinacao` ou
  `venda_perdida` ou `qualidade_score` abaixo de um limiar.
- **Link pro Chatwoot**: `https://chatwoot.lukz.com.br/app/accounts/1/conversations/{chatwoot_conversation_id}`
  — direto a partir de `conversas.chatwoot_conversation_id`, já existe.

## Perguntas em aberto ANTES de implementar (nenhuma bloqueia a próxima, só a fase específica)

As 4 perguntas antigas (modelo do auditor, canal do relatório, cadência do
agrupador) continuam sem resposta — refeitas aqui porque a pergunta 3
antiga (modo de operação no cutover) já foi resolvida (agente responde
direto, sem humano de prontidão, decisão implícita de manter o cutover
como estava depois de testado).

1. **Modelo do Auditor**: `gpt-4o-mini` (mesmo do agente, mais barato) ou
   um modelo mais forte, já que aqui não é tempo real e a qualidade do
   julgamento pesa mais?
2. **Canal do relatório**: WhatsApp, e-mail, ou tabela consultável?
3. **Cadência do agrupador de padrões**: semanal (proposto antes) ou outra?
4. **NOVA — histórico como baseline**: dado que não existe no Chatwoot,
   você tem esse histórico em algum outro lugar (WhatsApp Business App,
   export, outro sistema) que valha a pena importar pontualmente? Ou
   seguimos só com tráfego novo a partir de agora?
5. **NOVA — volume mínimo pra começar**: como hoje o número ainda é de
   teste (não recebe cliente real), a Fase 2 só vai ter dado de verdade
   pra analisar quando esse número passar a atender cliente de fato —
   isso já está decidido/planejado, ou ainda está em aberto?

Nenhuma implementação feita ainda desta revisão — só investigação e
desenho, como pedido explicitamente.

---

# Auditor — investigação do fluxo real + arquitetura proposta (14/08, sessão seguinte)

Schema da Fase 2 (`auditorias_atendimento`, `padroes_atendimento`, 4 views)
já implementado e testado (seção acima). Achado urgente corrigido no
caminho: agente novo não tinha nenhuma tool de transferência pra humano —
construída (`transferir_humano_whatsapp` + `WhatsApp - Tool - Transferir
Humano`), testada ao vivo, `conversas.estado` e reatribuição real no
Chatwoot confirmados.

Usuário pediu investigação completa do fluxo real ANTES do workflow do
Auditor, pra não duplicar lógica nem inventar métrica sem fonte. Como eu
mesmo construí e testei toda a Fase 1/1.5 nesta sessão, a investigação
abaixo é conhecimento direto (testado ao vivo), não suposição — só
confirmei via SQL os pontos que não tinha 100% de certeza.

## Mapa consolidado — de onde vem cada dado que o Auditor vai usar

| Dado | Fonte real | Confiabilidade |
|---|---|---|
| Sessão do atendimento (início/fim/motivo de fechamento técnico) | `atendimentos` (`iniciado_em`/`encerrado_em`/`motivo_encerramento`) | 🟢 alta — criado por `resolver_atendimento_atual`, fechado por `WhatsApp - Fechar Atendimentos Inativos` |
| Mensagens (cliente e agente, nas duas direções) | `mensagens` filtrado por `atendimento_id` | 🟢 alta — incoming e outgoing ambos gravados (Bug 6 corrigido); `mensagem_id_origem` correlaciona resposta→pergunta |
| Toda chamada de tool (input/output real) | `automacao_eventos` `etapa='tool_call'` | 🟢 alta — as 10 tools (9 + transferir_humano) logam aqui |
| Eventos de negócio (carrinho alterado, revisão confirmada, pedido criado, transferência) | `automacao_eventos` outras `etapa`s, com `motivo` estruturado em `detalhes->'output'` | 🟢 alta |
| Pedido criado (id, valor, forma de pagamento) | `automacao_eventos` (`tool_nome='criar_pedido', etapa='criado'`) **e** tabela `pedidos` (fonte definitiva) | 🟢 alta — cruzar as duas, `pedidos` é quem manda se divergir |
| Transferência humana | `automacao_eventos` (`tool_nome='transferir_humano'`) **e** `conversas.estado='atendente'` | 🟢 alta |
| Erro técnico de tool | `automacao_eventos.sucesso=false` | 🟢 alta |
| Duração de CADA chamada de tool (não do atendimento inteiro) | `automacao_eventos.duracao_ms` | 🔴 **não disponível** — coluna existe mas nunca foi populada na instrumentação da Fase 1 (achado agora, não presumido). Dá pra aproximar pela diferença entre `created_at` de eventos consecutivos, mas não é uma métrica precisa — o Auditor não deve reportar isso como número exato. |
| Duração do atendimento inteiro | `atendimentos.encerrado_em - iniciado_em` | 🟢 alta |
| Produto encontrado/não encontrado | `automacao_eventos` (`buscar_produto`, `output.encontrado`) | 🟢 alta |
| Problema de estoque | `automacao_eventos` (`alterar_carrinho`/`criar_pedido`, `motivo` em `sem_estoque`/`estoque_insuficiente_ajustado`/`estoque_insuficiente`) | 🟢 alta |
| Problema de frete | `automacao_eventos` (`revisar_carrinho`/`criar_pedido`, `motivo='frete_indisponivel'`) | 🟢 alta |
| Fricção/frustração/repetição | Não existe como dado — só a TRANSCRIÇÃO bruta | 🟡 interpretativo — é exatamente o trabalho do Auditor, nunca um fato pré-computado |
| Abandono | Não existe flag — só inferível (atendimento fechado por timeout, sem pedido, sem transferência, último evento foi resposta do agente sem retorno do cliente) | 🟡 interpretativo, com sinais objetivos de apoio |
| Score de satisfação do cliente | `pedidos.score_satisfacao` existe na tabela mas **nunca é preenchido por nada** (achado, não presumido — coluna morta desde antes desta sessão) | 🔴 não disponível, não inventar |

**Confirmado por consulta real**: hoje existem 65 linhas em `automacao_eventos`
(todas de teste meu), zero atendimento de cliente real — o Auditor será
implementado e testado com esse dado sintético (que reflete cenários reais
de uso: busca de produto, carrinho, revisão, confirmação, pagamento nos 4
métodos, transferência humana) até o tráfego real começar.

## Isolamento por canal (reconfirma o que a auditoria de impacto já mostrou)

Nada do Auditor toca em tabela/RPC do site ou do gestor/app — `auditorias_atendimento`/`padroes_atendimento` são novas, isoladas, mesmo padrão de grant (`service_role`-only) já usado em toda tabela WhatsApp desta sessão. O Auditor só LÊ dados que já existem (`mensagens`, `automacao_eventos`, `atendimentos`, `conversas`, `pedidos`) — nunca escreve nas tabelas operacionais, só nas duas novas de análise. Isso satisfaz a exigência do usuário ("Auditor é somente análise; não altera pedidos/carrinhos/pagamentos") por design, não por convenção.

## Arquitetura proposta do Auditor

```
WhatsApp - Fechar Atendimentos Inativos (já existe, roda a cada 15min)
      │ fecha atendimentos inativos
      ▼
WhatsApp - Auditor de Atendimento (NOVO, Schedule Trigger, ex.: a cada 20min)
      │
      ▼
1. Buscar atendimentos pendentes de auditoria
   SELECT a.id FROM atendimentos a
   WHERE a.encerrado_em IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM auditorias_atendimento au WHERE au.atendimento_id = a.id)
   ORDER BY a.encerrado_em LIMIT 5   -- lote pequeno por execução, controla custo/tempo
      │
      ▼ (Split in Batches / loop, 1 atendimento por vez)
2. Montar Contexto Objetivo — RPC NOVA `montar_contexto_auditoria(p_atendimento_id)`
   SQL puro, monta o jsonb ANTES do LLM entrar em cena:
   {
     atendimento: {id, iniciado_em, encerrado_em, duracao_minutos, motivo_encerramento},
     cliente: {nome, historico_resumido},  -- sem dado financeiro (saldo/ticket_medio já
       proibidos desde a auditoria de Data Exposure de 13/08)
     mensagens: [{direcao, tipo, conteudo, transcricao, created_at}, ...],  -- ordenado
     eventos: [{tool_nome, etapa, sucesso, motivo, resumo_input, resumo_output, created_at}, ...],
     fatos_pre_computados: {
       teve_transferencia_humano: bool,
       pedido: {id, valor_total, tipo_pagamento, status} | null,   -- de `pedidos`, não do texto
       teve_erro_tecnico: bool,
       qtd_mensagens_cliente: int,
       qtd_mensagens_agente: int,
       qtd_tool_calls: int,
       tools_chamadas: [nomes distintos],
       teve_problema_estoque: bool,
       teve_problema_frete: bool,
       teve_busca_sem_resultado: bool
     }
   }
      │
      ▼
3. Chamar o Auditor (LLM mais forte, ex. gpt-4o — a confirmar modelo exato
   disponível na credencial) com o contexto acima + prompt estruturado
   (ver próxima seção) → JSON estruturado batendo com as colunas de
   `auditorias_atendimento`
      │
      ▼
4. Gravar em `auditorias_atendimento` (INSERT direto, sem passar o resultado
   de volta pra nenhum sistema operacional)
      │
      ▼
5. Próximo atendimento do lote (loop) → fim
```

**Assíncrono por design**: dispara só depois que `Fechar Atendimentos
Inativos` já fechou o atendimento — nunca no caminho da resposta ao
cliente, sem qualquer impacto de latência no atendimento real.

## Prompt do Auditor — a cadeia FATO → INTERPRETAÇÃO → PROBLEMA → CAUSA → SOLUÇÃO

Estrutura do prompt (rascunho, ainda não escrito em produção):

1. **Contrato de entrada**: "Você recebe `fatos_pre_computados`, já calculados
   pelo sistema a partir do banco de dados — nunca contradiga esses valores,
   mesmo que o texto da conversa pareça sugerir outra coisa. Se o agente
   disse algo que os fatos não confirmam, ISSO EM SI é um problema
   (`teve_alucinacao`/`teve_informacao_incorreta`), não um motivo pra você
   acreditar no texto."
2. **As 5 dimensões**, uma seção do prompt por dimensão, com a lista de
   sinais que o usuário deu (excesso de perguntas, repetição, resposta
   robótica, falta de empatia, burocracia desnecessária, etc. pra
   Experiência; tool errada/faltante/desnecessária pra Operacional; etc.)
3. **Regra de bom senso, literal do usuário**: "Nem toda transferência pra
   humano é problema. Nem toda conversa longa é ruim. Nem toda venda não
   concluída é culpa do agente. Nem toda pergunta do cliente precisa virar
   automação. Julgue pelo contexto e evidência, nunca conte eventos
   mecanicamente."
4. **Para cada item em `problemas_detectados`**: exigir os 5 campos em
   cadeia — fato (cita a mensagem/evento exato), interpretação, categoria,
   causa provável, solução sugerida (com o `tipo_solucao` categorizado:
   prompt/regra determinística/tool/banco/workflow n8n/UX/catálogo-busca/
   treinamento/integração/processo operacional/transferência humana/outro),
   gravidade (baixa/média/alta/crítica).
5. **Saída JSON estrita** batendo 1:1 com as colunas já criadas em
   `auditorias_atendimento` (resultado, scores, booleans das 5 dimensões,
   `fatos_observados`, `problemas_detectados`, `resumo`, `recomendacao`).

## `padroes_atendimento` — segunda passada, agrupamento

Continua como desenhado na seção anterior — subworkflow separado (cadência
a decidir, proposta semanal), lê `problemas_detectados` de todas as
auditorias do período, agrupa semanticamente (não por string exata),
preenche `causa_provavel`/`solucao_sugerida`/`prioridade`. Sem mudança na
proposta anterior, só reforçando que o exemplo do usuário ("14 de 37
atendimentos com dificuldade de busca por linguagem natural") é
exatamente o formato esperado.

## Plano de teste antes de considerar pronto

Dado real disponível hoje: a conversa de teste desta sessão (Fase 1.5) tem
~14 mensagens reais cobrindo busca de produto, carrinho, revisão,
confirmação, 4 formas de pagamento testadas, 2 pedidos criados, e 1
transferência humana — cenário rico o suficiente pra validar o Auditor
antes de qualquer tráfego real. Como eu sei exatamente o que aconteceu de
verdade nessa conversa (participei dela), dá pra validar se os `fatos_observados`
do Auditor batem com a realidade — teste de precisão real, não só "rodou
sem erro".

## Perguntas antes de implementar

1. **Modelo exato**: `gpt-4o` (mais forte, mesma credencial OpenAI já em
   uso) — confirma esse modelo especificamente, ou prefere outro?
2. **Cadência do Auditor**: proposta a cada 20min (perto do ciclo de 15min
   do fechamento de atendimentos) — confirma, ou prefere outro intervalo?
3. **Tamanho do lote por execução**: proposta 5 atendimentos por rodada
   (controla custo/tempo por execução) — confirma?

Nenhuma implementação feita ainda desta seção — só investigação e
arquitetura, como pedido explicitamente.
isolado → testar composto → validar com dado real → documentar → commit.

## Redesenho do buscar_produto (Fase 1.6) — implementado e validado 14/08

Motivação: achado real ao ler uma conversa ao vivo — "areia de gato" só
retornava sempre os mesmos 5 produtos (LIMIT 5 ORDER BY nome, puramente
alfabético), escondendo 20 de 25 produtos reais / 7 de 9 marcas reais pra
sempre. Root cause confirmado antes de qualquer implementação.

### Distinção fabricante vs. marca (documentar pra nunca mais confundir)

`fabricante` = marca real reconhecível pelo cliente (PremieRpet, Mars
Petcare, Quatree...). `produtos.marca` = fornecedor/distribuidor interno,
NUNCA usado pra filtro ou exibição ao cliente. O site já faz essa
distinção corretamente em `gestor-loja/src/lib/catalogo.ts:272-278`. O
WhatsApp agora replica o mesmo padrão — `buscar_produto_v2` filtra e
retorna sempre `fabricante` (exposto como campo `marca` na resposta pro
agente, por compatibilidade de nome com o que o cliente entende).

### buscar_produto_v2 (RPC, Supabase)

Princípio: LLM interpreta intenção, banco decide o que existe. Filtros de
categoria/fabricante/espécie/preço são tratados como restrições da
intenção do cliente — nunca fatos inventados. Prioridade dura:
correspondência com intenção > disponibilidade > relevância/destaque >
diversidade de marca.

- 3 níveis de fallback: (1) todos os termos batem + todos os filtros
  opcionais, (2) todos os termos batem + só espécie (categoria/
  fabricante/preço são soltos), (3) qualquer termo bate + só espécie.
  Espécie NUNCA é solta em nenhum nível — é fato de confiança do cliente,
  não preferência soft.
- Diversidade por marca via `ROW_NUMBER() OVER (PARTITION BY fabricante
  ORDER BY disponivel DESC, destaque DESC, nome ASC)`, resultado final
  ordenado por disponibilidade > destaque > posição-por-marca > nome —
  isso dá variedade real sem diluir uma busca por marca específica.
- Limite fixo de 6 resultados. `ha_mais_opcoes: true` quando há mais.
- `todas_marcas_encontradas` só é computado quando `p_interesse_marcas`
  vem true (o agente só marca isso quando o cliente pede explicitamente
  "tem de outra marca?") — evita ruído no prompt na maioria das buscas.
- `disponivel` é sempre por produto individual, nunca um valor único pra
  lista inteira — mantém a mesma separação encontrado≠disponível já
  corrigida no Auditor (ver seção anterior).
- 2 bugs achados e corrigidos durante a simulação SQL obrigatória (antes
  de tocar em n8n): `LIMIT` depois de `jsonb_agg` não limitava nada (só
  limitava linhas, já 1 pelo agregado) — corrigido movendo `ORDER BY
  ... LIMIT` pra uma CTE antes do agregado. E o fallback do nível 2
  originalmente soltava espécie junto com os outros filtros, permitindo
  ração de cachorro aparecer numa busca filtrada por gato — corrigido
  tornando espécie não-solta em nenhum nível.
- Grants: só `service_role`, confirmado sem vazamento pra anon/
  authenticated.
- 12 cenários validados via SQL puro antes de qualquer wiring em n8n
  (existência vs. disponibilidade, múltiplas marcas, busca ampla com
  corte em 6, zero resultado, produto zerado com alternativa, filtro de
  marca+espécie combinado, filtro de preço).

### informar_area_atendimento (RPC nova, Supabase)

Complementa `consultar_zona_entrega` (que precisa do endereço já
cadastrado do cliente) com uma versão sem endereço, pra perguntas
genéricas tipo "vocês atendem minha região?" antes do cliente ter
endereço cadastrado. Retorna só `{cidade, zonas: [{nome, prazo_estimado_min:
[min,max]}]}` — nunca distância exata, preço ou regra interna de cálculo.
As zonas reais são faixas de distância ("Ate 3km", "3 a 5km", "5 a
10km"), não bairros nomeados — o system prompt instrui o agente a
descrever isso em texto natural (ex: "entrega entre 5 e 35 minutos
dependendo da distância"), nunca ler o nome técnico da zona como se fosse
um lugar.

### Implementação em n8n

- `WhatsApp - Tool - Buscar Produto` (h2tnSD50pn4sa00z): trigger com 6
  novos inputs opcionais, node "Normalizar Filtros" (empty/undefined→null,
  parse numérico seguro, boolean seguro) antes da chamada RPC, RPC
  trocada pra `buscar_produto_v2(..., 6)`, "Montar Resultado" reescrito
  pra desempacotar o jsonb único e só incluir `todas_marcas_encontradas`
  quando não-nulo.
- `WhatsApp - Tool - Informar Área de Atendimento` (wSL0LYn8oyLmDSjJ):
  subworkflow novo, mesmo padrão dos outros (trigger→RPC→Montar
  Resultado→Preparar Log→Logar Tool Call→Restaurar Saída).
- Agente principal (`WhatsApp - 02 Agente`, vhFKgmonTFMqzZuz): node de
  chamada do buscar_produto ganhou os 6 novos parâmetros `$fromAI`, cada
  um com instrução explícita de só preencher com evidência clara na
  conversa, nunca inventar. Novo node de chamada pra
  informar_area_atendimento. System prompt atualizado: filtros opcionais
  documentados como regra dura, disponibilidade por item da lista (nunca
  generalizada), quando usar cada tool nova, e como descrever as zonas de
  distância em linguagem natural.
- Teste isolado de ambos os subworkflows feito via workflow temporário
  descartável (Schedule Trigger 1min → Execute Workflow com casos reais
  → inspeção via `/api/v1/executions?includeData=true`), cobrindo filtro
  combinado marca+espécie, `interesse_marcas: true` (boolean sobrevive ao
  transporte n8n→Postgres), filtro de preço (numeric sobrevive), e
  informar_area_atendimento puro — depois deletado. Nenhum bug de
  plumbing encontrado desta vez (diferente das vezes anteriores nesta
  sessão).

Próximo passo: validar com conversa real via WhatsApp (o usuário já testa
no próprio número pessoal) antes de considerar a fase encerrada.

## Bugs reais achados em conversa ao vivo e corrigidos (14/08, mesma sessão)

Usuário testando no próprio número pediu a auditoria da conversa mais
recente. Atendimento ainda estava aberto (Auditor formal só processa
atendimentos encerrados), então li a transcrição + `automacao_eventos`
diretamente. Achei 2 bugs reais de produção, não relacionados ao
redesenho do buscar_produto:

### 1. Alucinação de produto_id ao remover item do carrinho por referência vaga

Cliente tinha 2 sachês no carrinho (herdados de um atendimento anterior —
carrinho é do cliente, não da conversa) e pediu "remover os sachês"
repetidamente. Depois de remover o primeiro corretamente, o agente
tentou remover o segundo **4 vezes**, cada vez inventando um
`produto_id` diferente que não existia em lugar nenhum (nem catálogo nem
carrinho) — a RPC rejeitou todas as 4 corretamente (`produto_nao_encontrado`,
nenhuma corrupção de dado), mas a experiência foi péssima. Causa raiz: o
system prompt já proibia reescrever produto_id de memória, mas só cobria
o fluxo de ADICIONAR (via buscar_produto); não havia regra equivalente
pra REMOVER/ALTERAR um item já existente no carrinho, cuja fonte de
verdade correta é `consultar_carrinho`, nunca `buscar_produto` (o
catálogo pode não bater 1:1 com o item real do carrinho).

**Fix**: nova regra explícita no system prompt — antes de remover/alterar
um item referenciado de forma vaga, chamar `consultar_carrinho` na mesma
resposta pra pegar o produto_id real; se a referência bater com mais de
um item, perguntar qual em vez de escolher sozinho.

### 2. Bot continuava respondendo depois de transferir pra humano

`conversas.estado='atendente'` estava sendo setado corretamente pela
RPC, mas o Router (workflow 01) nunca checava esse campo antes de
invocar o agente — toda mensagem nova do cliente, mesmo depois da
transferência, continuava caindo no bot normalmente. Descoberta
colateral: **não existia nenhum mecanismo pra reverter `estado` de volta
pro bot** — uma vez transferido, o cliente ficaria preso nesse estado
para sempre.

**Fix em duas partes**:
- Router: novo node "Anexar Estado da Conversa" + IF "Bot Está Ativo?"
  antes de "Processar Mensagem" — mensagem do cliente continua sendo
  salva (histórico/Chatwoot), mas o agente só é chamado se
  `estado_conversa !== 'atendente'`. Estado default de conversa nova é
  literalmente a string `'processar mensagem'` (não null) — descoberto
  lendo o node "Criar Conversa".
- `WhatsApp - Fechar Atendimentos Inativos`: novo node "Liberar Bot Após
  Transferência" — ao fechar um atendimento (30min sem atividade), reseta
  `conversas.estado` de volta pra `'processar mensagem'` se estava
  `'atendente'`. Fechamento do atendimento = fim natural do episódio
  atendido pelo humano; a próxima sessão do cliente começa com o bot de
  novo. Escolhido por ser consistente com o modelo de sessão (atendimento)
  já usado em todo o resto do projeto, sem exigir ação manual.

### 3. Notificação push ao dono quando cliente pede humano (pedido novo do usuário)

Usuário perguntou como saberia que um cliente pediu atendimento humano —
hoje só existe a atribuição da conversa no Chatwoot (`assignee_id`), sem
alerta ativo. Reaproveitada a infraestrutura de push já existente do app
(`usuarios.fcm_token` + webhook `notificacao-push` → FCM, mesma usada
pra outras notificações do app):

- `transferir_humano_whatsapp` passou a retornar também `fcm_tokens`
  (array de tokens de todos os usuários da empresa) e `cliente_nome`.
- Subworkflow `WhatsApp - Tool - Transferir Humano` ganhou um IF "É
  Transferência Nova?" + node HTTP que dispara o push **só na primeira
  vez** (`ja_estava_transferido === false`) — evita spam a cada nova
  mensagem do cliente já transferido.
- Testado ao vivo: push de teste disparado com sucesso pro token real do
  usuário; 1 dos 2 tokens da empresa veio `NotRegistered` (app
  desinstalado/token velho de outro usuário) — não bloqueia, mas vale
  limpar tokens mortos no futuro.

Estado da conversa de teste do usuário (`7e897edb-...`) foi resetado
manualmente pra `'processar mensagem'` depois do fix, já que ela ficou
presa em `'atendente'` de antes da correção existir.

## Fix estrutural do bug de alucinação (reincidiu, corrigido de raiz — 14/08)

O fix de prompt do item anterior NÃO foi suficiente: o mesmo bug
reproduziu na conversa seguinte, e desta vez com uma evidência mais
grave — o agente inventou um UUID errado pra remover a areia mesmo
tendo acabado de ver o ID real (`a7422f57-...`) no retorno de
`consultar_carrinho` 20 segundos antes, na mesma conversa. 3 tentativas,
3 UUIDs diferentes, nenhum correto. Isso confirma que o problema é uma
limitação conhecida de LLM (reproduzir uma string longa/aleatória de
memória com fidelidade), não falta de instrução — regra de prompt
sozinha não é confiável pra esse tipo de erro.

**Fix estrutural** (`alterar_carrinho_whatsapp`, novo parâmetro opcional
`p_produto_busca text`): pra `remover`/`alterar_quantidade` de um item já
no carrinho, o agente não informa mais produto_id — informa
`produto_busca` com as palavras do cliente (ex: "sachê", "areia"), e o
banco resolve o produto certo fazendo `ILIKE` contra os itens do
carrinho ATIVO do próprio cliente (nunca contra o catálogo geral):
- 0 correspondências → `produto_nao_encontrado_no_carrinho`.
- 1 correspondência → resolve automaticamente, segue o fluxo normal.
- 2+ correspondências → `multiplos_itens_correspondem` +
  `itens_correspondentes` (nomes reais) — agente pergunta qual, nunca
  escolhe sozinho.

`produto_id` continua existindo e obrigatório só pra `adicionar` (fluxo
via `buscar_produto`, que nunca mostrou esse problema — o ID ali é usado
na mesma resposta em que acabou de ser buscado, não precisa sobreviver
vários turnos de conversa).

Testado via SQL puro (3 cenários: 0/1/2+ matches) antes de qualquer
wiring, depois implementado no subworkflow `WhatsApp - Tool - Alterar
Carrinho` (novo input, query RPC atualizada, `Montar Resultado` passou a
incluir `itens_correspondentes` só quando existe — whitelist explícita)
e no agente (`produto_id` e `produto_busca` viram dois `$fromAI`
separados com instrução clara de qual usar em qual caso). Overload
antigo da RPC (sem o parâmetro novo) removido depois da migração —
única chamadora era esse subworkflow, já atualizado.

## Bug crítico achado em conversa real: filtro de espécie nunca batia pra "cachorro" (14/08, mesma sessão)

Usuário reportou que o agente parou de conseguir buscar ração pra
cachorro. Causa raiz: `buscar_produto_v2` (implementado mais cedo hoje)
recebe `p_especie` em linguagem natural do agente ("cachorro", "gato"),
mas o banco guarda `produtos.especie` em outro vocabulário ("Cães",
"Gatos", "Cães e Gatos", etc). O filtro usava `LIKE` literal sem
normalização — "cachorro" nunca é substring de "caes", então TODA busca
com espécie cachorro inferida retornava zero resultados desde o deploy
de hoje. Só não foi pego nos testes de validação porque o único teste
com espécie usado foi "gato", que por coincidência É substring de
"gatos" (`unaccent(lower("Gatos"))='gatos'`), mascarando o problema.

**Fix**: normalização de sinônimos antes do filtro — `cachorro`/`cão`/
`canino` → `caes`; `gato`/`gata`/`felino` → `gatos`; qualquer outro valor
passa direto (unaccent+lower). Aplicado nos 4 pontos onde `p_especie`
era usado (tier 1, tier 2, tier 3, marcas). Reconfirma o princípio "banco
decide": a normalização fica no backend, não depende do agente acertar o
token exato.

Testado com os 3 casos reais que falharam na conversa (`ração` +
categoria "Racao" + espécie "cachorro"; "Golden cão adulto" + fabricante
Golden + espécie "cachorro") — agora retornam produtos reais
corretamente. Reconfirmado sem regressão o caso "gato" que já funcionava.

## Alucinação séria: agente afirmou ter adicionado item sem chamar nenhuma ferramenta (14/08)

Achado ao vivo, mais grave que os anteriores de hoje: cliente pediu pra
adicionar um tapete específico ("Pode ser o 1"), e o agente respondeu
"Adicionei o Tapete Higiênico Petix ao seu carrinho!" com um resumo
completo de carrinho (3 itens, R$192,70) — **sem nenhuma chamada real a
buscar_produto ou alterar_carrinho nesse turno** (confirmado via
`automacao_eventos`: zero eventos entre o pedido e a resposta). Carrinho
real no banco continuou com só 2 itens, R$103,80. O modelo pegou o
PADRÃO textual de uma resposta de sucesso anterior na mesma conversa
(a adição real da ração Quatree, alguns turnos antes) e reproduziu o
formato com um produto diferente, sem executar nada.

Isso é uma classe de falha diferente e mais séria que a alucinação de
UUID corrigida hoje mais cedo — ali o modelo pelo menos TENTAVA chamar a
ferramenta (com um ID errado); aqui ele simplesmente não chamou nada e
inventou o resultado inteiro. Reforço aplicado no system prompt (regra
mais enfática da seção "REGRA FUNDAMENTAL", topo da lista): nunca afirmar
adição/remoção/alteração de carrinho sem o retorno real de
alterar_carrinho NESTA MESMA resposta, nunca copiar o formato de uma
resposta de sucesso anterior sem resultado novo por trás.

**Ressalva explícita**: diferente dos bugs de hoje corrigidos
estruturalmente (banco decide, não LLM), este é fundamentalmente sobre o
modelo mentir no TEXTO gerado sem executar a ferramenta — não há como
o n8n "forçar" isso de fora de forma totalmente confiável só com prompt.
O reforço de prompt é mitigação, não solução definitiva. Vale considerar,
se reincidir, um modelo mais forte pro agente principal (hoje
`gpt-4o-mini`) ou uma auditoria mais agressiva desse padrão específico
(comparar toda resposta que menciona "adicionei"/"removi" contra
automacao_eventos do mesmo turno).

## Ajuste de UX no carrinho de convidado com item local (14/08)

Usuário testou o cenário de carrinho de convidado NÃO vazio (item
adicionado antes pelo navegador): o merge com o carrinho real já
funcionava certo (confirmado pelo usuário — "isso é um bom sinal"), mas
o botão "Finalizar pedido" não deixava claro que fazer login ali também
traria itens de outros canais (ex: WhatsApp) — podia parecer confuso ver
produtos novos aparecerem depois do login sem explicação. Texto de apoio
atualizado pra avisar isso explicitamente antes do clique, sem mudar
nenhum comportamento funcional (só clareza). Commit `ed8aa40` em
`gestor-loja`, pushado.
