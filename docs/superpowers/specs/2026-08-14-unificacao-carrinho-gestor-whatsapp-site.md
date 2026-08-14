# Unificação do carrinho — Gestor (app) / WhatsApp / Site

## Contexto e motivação

Nascido de um problema real observado ao vivo (14/08): o agente de
WhatsApp travou tentando remover um item do carrinho de um cliente, e o
usuário (dono da loja) não tinha absolutamente nenhum jeito de ver ou
corrigir esse carrinho a partir do app Gestor — o app não lê nem escreve
na tabela `carrinho`/`carrinho_itens` do Supabase, que hoje é exclusiva
do site (`gestor-loja`) e do agente de WhatsApp.

Na mesma conversa, o usuário descreveu um objetivo mais amplo:
- Poder **assumir um atendimento automatizado a qualquer momento**, pelo
  app, sem precisar refazer o carrinho nem os dados do cliente.
- Poder **ver e atender vários clientes em paralelo** — hoje o app só
  suporta um carrinho por vez (venda manual sequencial).
- Poder **mandar pro cliente um link do site com o carrinho já montado**,
  pra ele mesmo continuar adicionando itens ou finalizar a compra.

Isso retoma uma pergunta deixada propositalmente em aberto em
`2026-08-12-whatsapp-automacao-plano.md` ("Ainda não decidido — fica pra
quando a Fase 2 estiver validada"): qual caminho de autenticação usar pra
fazer o WhatsApp operar sobre os mesmos dados/regras do site. A Fase 2
(busca de produto) e o piloto real já estão validados — é a hora de
decidir.

## Achado que muda o escopo (14/08): não precisa de migração de reconciliação

A hipótese inicial era que unificar exigiria resolver duplicação de
clientes (um cadastro via WhatsApp sem `auth_user_id`, outro via site
com `auth_user_id`, mesmo telefone). **Isso já está resolvido** —
confirmado lendo `entrar_ou_criar_cliente` direto no banco
(`pg_get_functiondef`): a RPC já procura, antes de criar um cliente novo,
uma linha existente com `auth_user_id is null and telefone = <telefone
da sessão>` e **vincula** essa linha em vez de duplicar. Ou seja: um
cliente que já existe via WhatsApp (sem auth) e depois loga no site pelo
número dele **automaticamente vira o mesmo `cliente_id`**, sem
intervenção nenhuma.

Isso simplifica bastante o caminho de autenticação: não é preciso criar
sessões de Supabase Auth via Admin API nem reconciliar nada por migração
— basta que o cliente complete o OTP normal do site (por SMS, ou pelo
workflow que já existe `Site - Enviar OTP Login via WhatsApp`) com o
MESMO número de telefone já usado no WhatsApp. A única coisa a validar
antes de implementar (Tarefa 0 do plano): **o formato do telefone
salvo em `clientes.telefone` pelo Router do WhatsApp bate exatamente com
o formato que `auth.jwt() ->> 'phone'` devolve depois do OTP** (E.164 sem
`+`, provavelmente) — se não bater, é só uma normalização, não uma
mudança de arquitetura.

## Decisão tomada

**Não** construir uma RPC "irmã" auth-agnóstica nem uma sessão sintética
via Admin API. Usar o caminho 2 do plano de 12/08 (sessão real de
Supabase Auth), que na prática já está pronto no nível de dados — só
falta:

1. **App Gestor (Flutter) — maior parte do trabalho**: dar ao app acesso
   de leitura/escrita ao MESMO carrinho (`carrinho`/`carrinho_itens`) que
   WhatsApp e site já usam, por `cliente_id`, substituindo o
   `CarrinhoProvider` global único (`lib/main.dart:55`, em memória, sem
   `cliente_id`) por um carrinho por cliente persistido no Supabase.
   Isso resolve as duas dores do app de uma vez: visibilidade de
   qualquer carrinho ativo (WhatsApp incluso) e atendimento paralelo de
   vários clientes (cada um é só uma linha `carrinho` diferente, não
   precisa de estado múltiplo em memória).
2. **RPCs novas pro app** (mesmo padrão SECURITY DEFINER + whitelist já
   usado em todo o projeto): equivalentes de `consultar_carrinho`/
   `alterar_carrinho_whatsapp` mas chamáveis pelo app autenticado como o
   USUÁRIO da empresa (não o cliente) — precisa validar que esse usuário
   pertence à `empresa_id` do cliente que está manipulando. Reaproveitar
   a resolução por nome (`p_produto_busca`, já construída e testada hoje
   para o WhatsApp) também no app, pelo mesmo motivo (evitar erro de
   UUID digitado errado não é problema de LLM aqui, mas a função já
   existe e resolve bem).
3. **WhatsApp — tool nova `gerar_link_carrinho`**: manda o cliente pro
   site (rota do carrinho) e dispara o OTP via WhatsApp (workflow já
   existe). Como o carrinho já é a mesma tabela, ao completar o login o
   cliente já vê exatamente o que tinha no WhatsApp — sem token de
   carrinho nem link mágico novo.
4. **Handoff humano sem "refazer nada"**: já garantido pelas correções de
   hoje (`conversas.estado='atendente'` + gate no Router) — uma vez que
   o app tenha acesso ao mesmo carrinho (item 1), abrir o cliente no app
   depois de uma transferência já mostra o carrinho exato que o bot tinha
   montado. Não precisa de nenhum mecanismo novo além do item 1.

## Fora de escopo deste plano (decidir depois, não bloqueia)

- Checkout por cartão via WhatsApp (tokenização) — like o plano de 12/08
  já apontava, decidir só depois de ver demanda real.
- Reconciliação de clientes que hoje têm 2 cadastros de fato divergentes
  (nomes diferentes, etc) — não é o caso comum (a RPC já evita duplicar
  daqui pra frente); se aparecer um caso real, tratar pontualmente.

## Plano de implementação (Fase 1)

Plano completo, tarefa a tarefa, em
`docs/superpowers/plans/2026-08-14-unificacao-carrinho-fase1.md`. Cobre:
validação de formato de telefone, extração de `_alterar_carrinho_core`
compartilhado (sem mudar comportamento do WhatsApp), RPCs novas
`consultar_carrinho_app`/`alterar_carrinho_app` pro app, aba "Carrinho"
em `ClienteDetalhesScreen`, e tool `gerar_link_carrinho` no agente.

A refatoração do `CarrinhoProvider`/`VendasScreen` pra permitir
atendimento paralelo de várias vendas manuais fica pra uma Fase 2
separada — descoberto durante a investigação que esse fluxo tem conceitos
(cupom, zona de entrega, agendamento) que a tabela `carrinho`
compartilhada ainda não modela, então unificar de uma vez só seria um
escopo bem maior e mais arriscado do que o necessário pra resolver a dor
imediata.

## Task 0 — resultado (14/08)

Confirmado real: todos os 4 clientes de origem WhatsApp tinham telefone
em formato divergente do E.164 sem `+` que `auth.jwt()->>'phone'` usa
(ex: `"(21) 99887-7477"` vs `"5521998877477"`). A normalização antiga do
Router só tratava o caso de vir explicitamente com `+55`. Corrigido pra
sempre extrair só dígitos e garantir prefixo `55`. Achado colateral
concreto (não hipotético): o telefone de teste do próprio usuário já
tinha gerado 2 cadastros divergentes (`Jacó`, via WhatsApp, formato
antigo; `Lucas`, via login no site, E.164 correto) — exatamente o
problema que a normalização evita daqui pra frente. Esse caso específico
NÃO foi mesclado automaticamente (decisão de merge de cliente é
manual/pontual, fora de escopo desta fase) — os outros 3 clientes de
teste malformados foram normalizados via backfill.

## Task 1 — resultado (14/08)

`_alterar_carrinho_core` extraído, `alterar_carrinho_whatsapp` virou
casca fina (resolve tipo_mensagem/proposta/idempotência, delega o resto).
Grants confirmados (`postgres`+`service_role` só). Reexecutados os 5
cenários de regressão: 0-match, INTENCAO→CONFIRMACAO (fluxo completo),
múltiplos-match, match-único — todos com saída idêntica ao comportamento
pré-refatoração. Nenhuma mudança de comportamento observável pro
WhatsApp em produção.

## Task 2 — resultado (14/08)

`consultar_carrinho_app`/`alterar_carrinho_app` criadas, grants
confirmados (`authenticated`+`service_role`, sem `anon`). Testado via
`set_config('request.jwt.claims', ...)` + `set local role authenticated`
dentro de uma transação com `rollback` no fim (nunca persiste nada):
caminho feliz (consulta e remoção por produto_busca) funcionou
corretamente pro usuário real da empresa; tentativa de acessar carrinho
de cliente de OUTRA empresa foi corretamente bloqueada com exceção
"Cliente não encontrado para essa empresa" — isolamento multi-tenant
confirmado antes de qualquer wiring no app.
