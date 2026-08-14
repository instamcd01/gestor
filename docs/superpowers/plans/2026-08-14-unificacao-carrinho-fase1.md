# Unificação do Carrinho (Fase 1) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dar ao app Gestor (Flutter) acesso de leitura e edição ao carrinho real (`carrinho`/`carrinho_itens` no Supabase) de qualquer cliente da empresa — o mesmo carrinho que o agente de WhatsApp e o site já usam — e permitir que o agente de WhatsApp direcione o cliente pro site com o carrinho já populado.

**Architecture:** Extrai a lógica de alteração de carrinho de `alterar_carrinho_whatsapp` pra uma função interna compartilhada (`_alterar_carrinho_core`), sem mudar nenhum comportamento do WhatsApp. Duas RPCs novas (`consultar_carrinho_app`, `alterar_carrinho_app`), chamáveis pelo app autenticado como usuário da empresa (não como o cliente, diferente do site), validam que o usuário pertence à mesma empresa do cliente-alvo e então chamam o core. O app ganha uma aba nova em `ClienteDetalhesScreen` mostrando esse carrinho. O agente de WhatsApp ganha uma tool nova que orienta o cliente a continuar no site — sem link mágico nem token novo, porque o carrinho já é a mesma linha e o OTP do site já é entregue por WhatsApp (confirmado: workflow n8n `Site - Enviar OTP Login via WhatsApp` já está ativo como hook de envio de SMS do Supabase Auth).

**Tech Stack:** Supabase (Postgres/plpgsql, RPCs SECURITY DEFINER), Flutter (Provider, pattern de repository já usado no projeto), n8n (`@n8n/n8n-nodes-langchain.toolWorkflow`, Postgres node).

## Global Constraints

- Toda RPC nova com assinatura própria precisa de `REVOKE ALL ... FROM PUBLIC, anon, authenticated` seguido do `GRANT` explícito certo — bug recorrente confirmado várias vezes nesta sessão (overload novo herda grants públicos por padrão).
- Nunca passthrough direto de jsonb de RPC pra UI/agente — sempre whitelist explícita campo a campo (regra permanente do projeto, ver `feedback_whitelist_explicita_obrigatoria_subworkflows`).
- `carrinho`/`alterar_carrinho_whatsapp`/`consultar_carrinho` são usados em produção real (piloto ativo) — a extração do core (Tarefa 1) não pode mudar nenhum comportamento observável do fluxo de WhatsApp; testar isso é a parte mais crítica da Tarefa 1.
- Autorização multi-tenant explícita: toda RPC nova que a Tarefa 2 cria precisa verificar que `usuarios.empresa_id` (de quem chama, via `auth.uid()`) bate com `clientes.empresa_id` (do cliente alvo) — já houve vazamento multi-tenant real neste projeto por RPC `SECURITY DEFINER` sem esse check (`gestor_pedido_compra_fornecedor`).
- Escopo desta Fase 1: só visibilidade/edição do carrinho pelo app + tool de handoff pro site. A unificação do fluxo de VENDA MANUAL do app (hoje `CarrinhoProvider` global em memória, com cupom/zona de entrega/agendamento — mais rico que a tabela `carrinho` compartilhada) fica pra uma Fase 2 separada, não coberta aqui.

---

### Task 0: Validar formato de telefone entre WhatsApp e Supabase Auth

**Files:**
- Nenhum arquivo — é uma verificação de dado real via SQL, documentada no resultado.

**Interfaces:**
- Produz: confirmação (ou não) de que `clientes.telefone` (populado pelo Router do WhatsApp) tem o MESMO formato que `auth.jwt() ->> 'phone'` (populado pelo Supabase Auth depois do OTP) — isso é pré-requisito lógico pra Tarefa 5 funcionar (se os formatos não baterem, `entrar_ou_criar_cliente` nunca vai encontrar o cliente certo por telefone e vai criar um duplicado).

- [ ] **Step 1: Conferir o formato salvo pelo WhatsApp**

Rodar via Supabase (`execute_sql`, projeto `dwswpwxnzjgoohucngbb`):

```sql
select telefone, canal_origem from clientes
where empresa_id = '3bce0e24-2868-49f3-a9dd-eed921ffc8e4' and canal_origem is distinct from 'site_proprio'
limit 5;
```

Anotar o formato exato (ex: `5521999999999` sem `+`, ou `+5521999999999`, ou com formatação tipo `(21) 99999-9999`).

- [ ] **Step 2: Conferir o formato que o Supabase Auth usa**

Rodar:

```sql
select phone from auth.users limit 5;
```

(Se não houver nenhum usuário de Auth ainda com telefone confirmado, usar a documentação do Supabase Auth — formato E.164 sem `+`, ex: `5521999999999` — e validar contra o primeiro usuário real que logar depois da Tarefa 5.)

- [ ] **Step 3: Se os formatos não baterem, normalizar na origem**

Se `clientes.telefone` do WhatsApp tiver formato diferente (ex: com `+`, ou com espaços/parênteses), corrigir a normalização em `integrations/n8n/01-chatwoot-router.json`, no node `Normalizar Dados` (campo `telefone`), pra sempre salvar em E.164 sem `+` — o mesmo formato do Auth. Buscar o node atual:

```bash
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" https://n8n.lukz.com.br/api/v1/workflows/BMPxK87ZayiSmOjy | node -e "
let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
  const w = JSON.parse(d);
  console.log(JSON.stringify(w.nodes.find(n=>n.name==='Normalizar Dados').parameters, null, 2));
});
"
```

Se precisar mudar, ajustar a expressão do campo `telefone` pra remover `+`/espaços/parênteses/traços antes de salvar, testar com uma mensagem real de teste, e fazer o deploy via `PUT /api/v1/workflows/BMPxK87ZayiSmOjy` seguindo o mesmo processo já usado o dia inteiro nesta sessão (baixar workflow completo, editar só o node, `PUT` de volta).

- [ ] **Step 4: Documentar o resultado**

Anotar no arquivo `docs/superpowers/specs/2026-08-14-unificacao-carrinho-gestor-whatsapp-site.md`, numa nova seção "## Task 0 — resultado", se precisou de normalização ou não, e qual é o formato canônico confirmado.

---

### Task 1: Extrair `_alterar_carrinho_core` — sem mudar comportamento do WhatsApp

**Files:**
- Modify: RPC `alterar_carrinho_whatsapp` no Supabase (via `apply_migration`, projeto `dwswpwxnzjgoohucngbb`).
- Create: nova função interna `_alterar_carrinho_core` no mesmo projeto.

**Interfaces:**
- Produz: `_alterar_carrinho_core(p_cliente_id uuid, p_empresa_id uuid, p_operacao text, p_produto_id uuid, p_quantidade integer, p_produto_busca text) RETURNS jsonb` — mesmo shape de retorno que `alterar_carrinho_whatsapp` já devolve hoje (`autorizado`, `motivo`, `operacao`, `produto_id`, `produto_nome`, `quantidade_antes`, `quantidade_final`, mais `carrinho` embutido), SEM os campos/lógica de `tipo_mensagem`/`proposta_pendente`/idempotência por `mensagem_id` (esses ficam só em `alterar_carrinho_whatsapp`, que chama o core depois de resolver isso).
- Consome: nada de tarefas anteriores.

O `_alterar_carrinho_core` é literalmente o miolo que já existe dentro de `alterar_carrinho_whatsapp` — a parte que resolve `p_produto_busca` (já construída e testada hoje), busca o produto, mexe em `carrinho`/`carrinho_itens`, calcula estoque. `alterar_carrinho_whatsapp` continua existindo, mas vira uma casca fina: resolve `tipo_mensagem`/proposta/idempotência, e só then chama o core.

- [ ] **Step 1: Escrever a migration com o core extraído + o wrapper reescrito**

```sql
-- Núcleo puro: só mexe no carrinho. Nenhuma noção de conversa, tipo_mensagem,
-- proposta pendente ou idempotência por mensagem — isso é responsabilidade
-- de quem chama (alterar_carrinho_whatsapp hoje; alterar_carrinho_app na
-- Tarefa 2).
CREATE OR REPLACE FUNCTION public._alterar_carrinho_core(
  p_cliente_id uuid, p_empresa_id uuid, p_operacao text,
  p_produto_id uuid, p_quantidade integer, p_produto_busca text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_carrinho_id uuid;
  v_produto record;
  v_estoque int;
  v_quantidade_antes int;
  v_quantidade_final int;
  v_motivo text := null;
  v_resultado jsonb;
  v_candidatos jsonb;
  v_qtd_candidatos int;
begin
  if p_operacao not in ('adicionar', 'remover', 'alterar_quantidade') then
    raise exception 'Operação inválida: %', p_operacao;
  end if;
  if not exists (select 1 from clientes where id = p_cliente_id and empresa_id = p_empresa_id) then
    raise exception 'Cliente não encontrado para essa empresa';
  end if;

  if p_produto_id is null and p_produto_busca is not null and p_operacao in ('remover', 'alterar_quantidade') then
    select coalesce(jsonb_agg(jsonb_build_object('produto_id', ci.produto_id, 'nome', p.nome)), '[]'::jsonb),
           count(*)
      into v_candidatos, v_qtd_candidatos
    from carrinho_itens ci
    join carrinho c on c.id = ci.carrinho_id
    join produtos p on p.id = ci.produto_id
    where c.cliente_id = p_cliente_id and c.empresa_id = p_empresa_id and c.status = 'ativo'
      and unaccent(lower(p.nome)) like '%' || unaccent(lower(p_produto_busca)) || '%';

    if v_qtd_candidatos = 0 then
      return jsonb_build_object(
        'autorizado', false, 'motivo', 'produto_nao_encontrado_no_carrinho',
        'operacao', p_operacao, 'produto_id', null, 'produto_nome', null,
        'quantidade_antes', null, 'quantidade_final', null,
        'carrinho', (select public.consultar_carrinho(p_cliente_id, p_empresa_id))
      );
    elsif v_qtd_candidatos > 1 then
      return jsonb_build_object(
        'autorizado', false, 'motivo', 'multiplos_itens_correspondem',
        'operacao', p_operacao, 'produto_id', null, 'produto_nome', null,
        'quantidade_antes', null, 'quantidade_final', null, 'itens_correspondentes', v_candidatos,
        'carrinho', (select public.consultar_carrinho(p_cliente_id, p_empresa_id))
      );
    else
      p_produto_id := (v_candidatos->0->>'produto_id')::uuid;
    end if;
  end if;

  if p_produto_id is null then
    raise exception 'produto_id é obrigatório';
  end if;

  select p.id, p.nome, p.ativo, p.exibir_no_catalogo, p.preco, p.preco_promocional
    into v_produto
  from produtos p
  where p.id = p_produto_id and p.empresa_id = p_empresa_id;

  if not found then
    return jsonb_build_object(
      'autorizado', false, 'motivo', 'produto_nao_encontrado',
      'operacao', p_operacao, 'produto_id', p_produto_id, 'produto_nome', null,
      'quantidade_antes', null, 'quantidade_final', null,
      'carrinho', (select public.consultar_carrinho(p_cliente_id, p_empresa_id))
    );
  end if;

  if p_operacao in ('adicionar', 'alterar_quantidade') and not (v_produto.ativo and v_produto.exibir_no_catalogo) then
    return jsonb_build_object(
      'autorizado', false, 'motivo', 'produto_indisponivel',
      'operacao', p_operacao, 'produto_id', p_produto_id, 'produto_nome', v_produto.nome,
      'quantidade_antes', null, 'quantidade_final', null,
      'carrinho', (select public.consultar_carrinho(p_cliente_id, p_empresa_id))
    );
  end if;

  if p_operacao in ('adicionar', 'alterar_quantidade') and (p_quantidade is null or p_quantidade < 0) then
    return jsonb_build_object(
      'autorizado', false, 'motivo', 'quantidade_invalida',
      'operacao', p_operacao, 'produto_id', p_produto_id, 'produto_nome', v_produto.nome,
      'quantidade_antes', null, 'quantidade_final', null,
      'carrinho', (select public.consultar_carrinho(p_cliente_id, p_empresa_id))
    );
  end if;

  select id into v_carrinho_id from carrinho
  where cliente_id = p_cliente_id and empresa_id = p_empresa_id and status = 'ativo';

  if v_carrinho_id is null then
    if p_operacao = 'adicionar' or (p_operacao = 'alterar_quantidade' and p_quantidade > 0) then
      insert into carrinho (empresa_id, cliente_id, status, origem, valor_total)
      values (p_empresa_id, p_cliente_id, 'ativo', 'whatsapp', 0)
      returning id into v_carrinho_id;
    else
      return jsonb_build_object(
        'autorizado', true, 'motivo', 'carrinho_vazio',
        'operacao', p_operacao, 'produto_id', p_produto_id, 'produto_nome', v_produto.nome,
        'quantidade_antes', 0, 'quantidade_final', 0,
        'carrinho', (select public.consultar_carrinho(p_cliente_id, p_empresa_id))
      );
    end if;
  end if;

  select ci.quantidade into v_quantidade_antes
  from carrinho_itens ci where ci.carrinho_id = v_carrinho_id and ci.produto_id = p_produto_id;
  v_quantidade_antes := coalesce(v_quantidade_antes, 0);

  if p_operacao in ('adicionar', 'alterar_quantidade') then
    select coalesce(sum(quantidade_atual), 0) into v_estoque
    from (select quantidade_atual from estoque where produto_id = p_produto_id for update) sub;

    if p_operacao = 'adicionar' then
      v_quantidade_final := least(v_quantidade_antes + p_quantidade, greatest(v_estoque, 0));
    else
      if p_quantidade = 0 then
        delete from carrinho_itens where carrinho_id = v_carrinho_id and produto_id = p_produto_id;
        v_quantidade_final := 0;
      else
        v_quantidade_final := least(p_quantidade, greatest(v_estoque, 0));
      end if;
    end if;

    if v_quantidade_final > 0 then
      insert into carrinho_itens (carrinho_id, produto_id, quantidade, preco_unitario, subtotal)
      values (
        v_carrinho_id, p_produto_id, v_quantidade_final,
        coalesce(v_produto.preco_promocional, v_produto.preco),
        v_quantidade_final * coalesce(v_produto.preco_promocional, v_produto.preco)
      )
      on conflict (carrinho_id, produto_id) do update set
        quantidade = v_quantidade_final,
        preco_unitario = coalesce(v_produto.preco_promocional, v_produto.preco),
        subtotal = v_quantidade_final * coalesce(v_produto.preco_promocional, v_produto.preco);
    end if;

    v_motivo := case when v_estoque <= 0 then 'sem_estoque'
                     when v_quantidade_final < v_quantidade_antes + coalesce(p_quantidade, 0) and p_operacao = 'adicionar' then 'estoque_insuficiente_ajustado'
                     else null end;
  else
    delete from carrinho_itens where carrinho_id = v_carrinho_id and produto_id = p_produto_id;
    v_quantidade_final := 0;
  end if;

  update carrinho set valor_total = (
    select coalesce(sum(subtotal), 0) from carrinho_itens where carrinho_id = v_carrinho_id
  ), updated_at = now() where id = v_carrinho_id;

  v_resultado := jsonb_build_object(
    'autorizado', true, 'motivo', v_motivo,
    'operacao', p_operacao, 'produto_id', p_produto_id, 'produto_nome', v_produto.nome,
    'quantidade_antes', v_quantidade_antes, 'quantidade_final', v_quantidade_final
  );

  return v_resultado || jsonb_build_object('carrinho', (select public.consultar_carrinho(p_cliente_id, p_empresa_id)));
end;
$function$;

REVOKE ALL ON FUNCTION public._alterar_carrinho_core(uuid,uuid,text,uuid,integer,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._alterar_carrinho_core(uuid,uuid,text,uuid,integer,text) TO service_role;

-- Wrapper: só resolve tipo_mensagem/proposta_pendente/idempotência, delega
-- tudo de carrinho pro core.
CREATE OR REPLACE FUNCTION public.alterar_carrinho_whatsapp(
  p_cliente_id uuid, p_empresa_id uuid, p_conversa_id uuid, p_operacao text,
  p_produto_id uuid, p_quantidade integer, p_tipo_mensagem text, p_mensagem_id uuid,
  p_atendimento_id uuid DEFAULT NULL::uuid,
  p_produto_busca text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_proposta jsonb;
  v_ja_processado jsonb;
  v_resultado jsonb;
  v_produto_nome text;
begin
  if p_tipo_mensagem not in ('CONSULTA', 'INFORMACAO', 'INTENCAO', 'COMANDO', 'CONFIRMACAO') then
    raise exception 'tipo_mensagem inválido: %', p_tipo_mensagem;
  end if;
  if not exists (select 1 from clientes where id = p_cliente_id and empresa_id = p_empresa_id) then
    raise exception 'Cliente não encontrado para essa empresa';
  end if;

  select contexto->'proposta_pendente' into v_proposta
  from conversas where id = p_conversa_id;

  if p_tipo_mensagem = 'CONFIRMACAO' and v_proposta is not null
     and (v_proposta->>'criado_em')::timestamptz >= now() - interval '15 minutes' then
    if p_produto_id is null then
      p_produto_id := (v_proposta->>'produto_id')::uuid;
    end if;
    if p_quantidade is null then
      p_quantidade := (v_proposta->>'quantidade')::int;
    end if;
  end if;

  if p_produto_id is null and p_produto_busca is null then
    raise exception 'produto_id ou produto_busca é obrigatório';
  end if;

  if p_produto_id is not null then
    select detalhes into v_ja_processado
    from automacao_eventos
    where mensagem_id = p_mensagem_id
      and tool_nome = 'alterar_carrinho'
      and etapa = 'executado'
      and detalhes->>'produto_id' = p_produto_id::text
      and detalhes->>'operacao' = p_operacao
    order by created_at desc
    limit 1;

    if v_ja_processado is not null then
      return v_ja_processado || jsonb_build_object('idempotente', true, 'carrinho', (select public.consultar_carrinho(p_cliente_id, p_empresa_id)));
    end if;
  end if;

  select nome into v_produto_nome from produtos where id = p_produto_id;

  if p_tipo_mensagem = 'INTENCAO' then
    if p_produto_id is null then
      raise exception 'produto_id é obrigatório pra registrar uma proposta (INTENCAO)';
    end if;
    update conversas set contexto = coalesce(contexto, '{}'::jsonb) || jsonb_build_object(
      'proposta_pendente', jsonb_build_object(
        'operacao', p_operacao, 'produto_id', p_produto_id, 'quantidade', p_quantidade,
        'criado_em', now()
      )
    ) where id = p_conversa_id;

    v_resultado := jsonb_build_object(
      'autorizado', false, 'aguardando_confirmacao', true, 'motivo', 'aguardando_confirmacao',
      'operacao', p_operacao, 'produto_id', p_produto_id, 'produto_nome', v_produto_nome,
      'quantidade_antes', null, 'quantidade_final', p_quantidade
    );
    insert into automacao_eventos (empresa_id, conversa_id, mensagem_id, atendimento_id, etapa, tool_nome, detalhes, sucesso)
    values (p_empresa_id, p_conversa_id, p_mensagem_id, p_atendimento_id, 'executado', 'alterar_carrinho', v_resultado, false);
    return v_resultado || jsonb_build_object('carrinho', (select public.consultar_carrinho(p_cliente_id, p_empresa_id)));
  end if;

  if p_tipo_mensagem = 'CONFIRMACAO' then
    if v_proposta is null
       or (v_proposta->>'operacao') is distinct from p_operacao
       or (p_produto_id is not null and (v_proposta->>'produto_id') is distinct from p_produto_id::text)
       or (v_proposta->>'criado_em')::timestamptz < now() - interval '15 minutes'
    then
      v_resultado := jsonb_build_object(
        'autorizado', false, 'motivo', 'sem_proposta_pendente',
        'operacao', p_operacao, 'produto_id', p_produto_id, 'produto_nome', v_produto_nome,
        'quantidade_antes', null, 'quantidade_final', null
      );
      insert into automacao_eventos (empresa_id, conversa_id, mensagem_id, atendimento_id, etapa, tool_nome, detalhes, sucesso)
      values (p_empresa_id, p_conversa_id, p_mensagem_id, p_atendimento_id, 'executado', 'alterar_carrinho', v_resultado, false);
      return v_resultado || jsonb_build_object('carrinho', (select public.consultar_carrinho(p_cliente_id, p_empresa_id)));
    end if;
  elsif p_tipo_mensagem <> 'COMANDO' then
    v_resultado := jsonb_build_object(
      'autorizado', false, 'motivo', 'sem_comando_explicito',
      'operacao', p_operacao, 'produto_id', p_produto_id, 'produto_nome', v_produto_nome,
      'quantidade_antes', null, 'quantidade_final', null
    );
    insert into automacao_eventos (empresa_id, conversa_id, mensagem_id, atendimento_id, etapa, tool_nome, detalhes, sucesso)
    values (p_empresa_id, p_conversa_id, p_mensagem_id, p_atendimento_id, 'executado', 'alterar_carrinho', v_resultado, false);
    return v_resultado || jsonb_build_object('carrinho', (select public.consultar_carrinho(p_cliente_id, p_empresa_id)));
  end if;

  v_resultado := public._alterar_carrinho_core(p_cliente_id, p_empresa_id, p_operacao, p_produto_id, p_quantidade, p_produto_busca);

  update conversas set contexto = coalesce(contexto, '{}'::jsonb) - 'proposta_pendente' - 'revisao_pendente' where id = p_conversa_id;

  insert into automacao_eventos (empresa_id, conversa_id, mensagem_id, atendimento_id, etapa, tool_nome, detalhes, sucesso)
  values (p_empresa_id, p_conversa_id, p_mensagem_id, p_atendimento_id, 'executado', 'alterar_carrinho',
    v_resultado - 'carrinho' - 'itens_correspondentes', (v_resultado->>'autorizado')::boolean);

  return v_resultado;
end;
$function$;

REVOKE ALL ON FUNCTION public.alterar_carrinho_whatsapp(uuid,uuid,uuid,text,uuid,integer,text,uuid,uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.alterar_carrinho_whatsapp(uuid,uuid,uuid,text,uuid,integer,text,uuid,uuid,text) TO service_role;
```

Aplicar via `mcp__claude_ai_Supabase__apply_migration` (nome: `extrair_alterar_carrinho_core`), projeto `dwswpwxnzjgoohucngbb`.

- [ ] **Step 2: Reconfirmar os grants**

```sql
select grantee, privilege_type from information_schema.routine_privileges
where routine_name in ('_alterar_carrinho_core', 'alterar_carrinho_whatsapp');
```

Esperado: só `postgres` e `service_role` nas duas.

- [ ] **Step 3: Rodar de novo os 3 cenários já validados hoje pra `p_produto_busca`, provando que o comportamento não mudou**

Usar um cliente de teste (não o cliente real de produção). Repetir exatamente os 3 testes já feitos nesta sessão: busca sem match (`produto_nao_encontrado_no_carrinho`), busca com match múltiplo (`multiplos_itens_correspondem`), busca com match único (remove de verdade). Comparar a saída com a documentada em `docs/superpowers/specs/2026-08-14-producao-real-auditoria-continua.md` (seção "Fix estrutural do bug de alucinação") — tem que ser idêntica.

- [ ] **Step 4: Testar o fluxo INTENCAO → CONFIRMACAO continua funcionando**

```sql
-- usa cliente/conversa reais de teste
select alterar_carrinho_whatsapp(
  '<cliente_id_teste>', '3bce0e24-2868-49f3-a9dd-eed921ffc8e4', '<conversa_id_teste>',
  'adicionar', '<produto_id_real>', 2, 'INTENCAO', null, null
) as passo1_intencao;
-- esperado: autorizado=false, aguardando_confirmacao=true, carrinho inalterado

select alterar_carrinho_whatsapp(
  '<cliente_id_teste>', '3bce0e24-2868-49f3-a9dd-eed921ffc8e4', '<conversa_id_teste>',
  'adicionar', null, null, 'CONFIRMACAO', null, null
) as passo2_confirmacao;
-- esperado: autorizado=true, quantidade_final reflete os 2 itens adicionados
```

- [ ] **Step 5: Commit**

Sincronizar nada de arquivo local (é só Supabase) — mas registrar no spec doc (`2026-08-14-unificacao-carrinho-gestor-whatsapp-site.md`) que a Tarefa 1 foi concluída e validada, com os resultados dos testes acima colados.

---

### Task 2: RPCs novas pro app — `consultar_carrinho_app` e `alterar_carrinho_app`

**Files:**
- Create: RPCs `consultar_carrinho_app`, `alterar_carrinho_app` no Supabase.

**Interfaces:**
- Consome: `_alterar_carrinho_core` (Tarefa 1), `consultar_carrinho` (já existe).
- Produz: `consultar_carrinho_app(p_cliente_id uuid) RETURNS jsonb` — mesmo shape de `consultar_carrinho` (`itens`, `valor_total`). `alterar_carrinho_app(p_cliente_id uuid, p_operacao text, p_produto_id uuid DEFAULT NULL, p_quantidade integer DEFAULT NULL, p_produto_busca text DEFAULT NULL) RETURNS jsonb` — mesmo shape que o core devolve. As duas resolvem `empresa_id` sozinhas a partir de `auth.uid()`, o chamador (app) nunca informa `empresa_id` nem `p_tipo_mensagem` — a autorização aqui é "o usuário está autenticado como funcionário/dono dessa empresa", não uma classificação de mensagem de LLM.

- [ ] **Step 1: Escrever a migration**

```sql
CREATE OR REPLACE FUNCTION public.consultar_carrinho_app(p_cliente_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_empresa_usuario uuid;
  v_empresa_cliente uuid;
begin
  select empresa_id into v_empresa_usuario from usuarios where id = auth.uid();
  if v_empresa_usuario is null then
    raise exception 'Usuário não autenticado ou sem empresa associada';
  end if;

  select empresa_id into v_empresa_cliente from clientes where id = p_cliente_id;
  if v_empresa_cliente is null or v_empresa_cliente <> v_empresa_usuario then
    raise exception 'Cliente não encontrado para essa empresa';
  end if;

  return public.consultar_carrinho(p_cliente_id, v_empresa_usuario);
end;
$function$;

REVOKE ALL ON FUNCTION public.consultar_carrinho_app(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.consultar_carrinho_app(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.alterar_carrinho_app(
  p_cliente_id uuid, p_operacao text, p_produto_id uuid DEFAULT NULL::uuid,
  p_quantidade integer DEFAULT NULL::integer, p_produto_busca text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_empresa_usuario uuid;
  v_empresa_cliente uuid;
begin
  select empresa_id into v_empresa_usuario from usuarios where id = auth.uid();
  if v_empresa_usuario is null then
    raise exception 'Usuário não autenticado ou sem empresa associada';
  end if;

  select empresa_id into v_empresa_cliente from clientes where id = p_cliente_id;
  if v_empresa_cliente is null or v_empresa_cliente <> v_empresa_usuario then
    raise exception 'Cliente não encontrado para essa empresa';
  end if;

  return public._alterar_carrinho_core(p_cliente_id, v_empresa_usuario, p_operacao, p_produto_id, p_quantidade, p_produto_busca);
end;
$function$;

REVOKE ALL ON FUNCTION public.alterar_carrinho_app(uuid,text,uuid,integer,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.alterar_carrinho_app(uuid,text,uuid,integer,text) TO authenticated;
```

Aplicar via `apply_migration` (nome: `criar_rpcs_carrinho_app`).

- [ ] **Step 2: Testar autorização negativa — usuário de uma empresa não pode ver carrinho de cliente de outra**

Como há 2 empresas reais no banco (`3bce0e24-...` e `4ff46568-...`, confirmadas nesta sessão), testar que `consultar_carrinho_app`/`alterar_carrinho_app` levantam exceção quando `p_cliente_id` não pertence à empresa do usuário autenticado. Isso não dá pra testar via `execute_sql` puro (que roda como `postgres`, não como um `authenticated` real) — anotar como teste manual obrigatório na Tarefa 4 (quando o app já estiver chamando de verdade, testar logado como usuário da empresa A tentando abrir um `cliente_id` da empresa B — tem que dar erro).

- [ ] **Step 3: Testar o caminho feliz via SQL, simulando auth.uid() com `set role`**

```sql
-- pega um usuario real da empresa de teste
select id, empresa_id from usuarios where empresa_id = '3bce0e24-2868-49f3-a9dd-eed921ffc8e4' limit 1;

-- simula a sessão desse usuário pra essa transação só
begin;
select set_config('request.jwt.claims', json_build_object('sub', '<usuario_id_encontrado_acima>')::text, true);
set local role authenticated;
select consultar_carrinho_app('<cliente_id_teste>') as teste_consulta;
select alterar_carrinho_app('<cliente_id_teste>', 'remover', null, null, '<termo_de_busca>') as teste_alterar;
rollback;
```

(O `rollback` no fim garante que o teste não deixa nenhuma alteração real — importante porque esse cliente pode ser o mesmo usado nos testes ao vivo desta sessão.)

- [ ] **Step 4: Commit**

Registrar no spec doc que a Tarefa 2 foi concluída, com os resultados dos testes.

---

### Task 3: Repository Flutter `CarrinhoClienteRepository`

**Files:**
- Create: `lib/repositories/carrinho_cliente_repository.dart`
- Create: `lib/models/item_carrinho_cliente.dart`

**Interfaces:**
- Consome: RPCs `consultar_carrinho_app`/`alterar_carrinho_app` (Tarefa 2), padrão `supabase.rpc(...)` já usado em `lib/repositories/saldo_repository.dart:29-36`.
- Produz: `class CarrinhoClienteRepository { Future<CarrinhoCliente> consultar(String clienteId); Future<CarrinhoCliente> remover(String clienteId, {String? produtoId, String? produtoBusca}); Future<CarrinhoCliente> alterarQuantidade(String clienteId, {String? produtoId, String? produtoBusca, required int quantidade}); }` — usado pela Tarefa 4.

- [ ] **Step 1: Criar o model**

```dart
// lib/models/item_carrinho_cliente.dart
class ItemCarrinhoCliente {
  final String produtoId;
  final String nome;
  final int quantidade;
  final double precoUnitario;
  final double subtotal;

  ItemCarrinhoCliente({
    required this.produtoId,
    required this.nome,
    required this.quantidade,
    required this.precoUnitario,
    required this.subtotal,
  });

  factory ItemCarrinhoCliente.fromJson(Map<String, dynamic> json) {
    return ItemCarrinhoCliente(
      produtoId: json['produto_id'] as String,
      nome: json['nome'] as String,
      quantidade: json['quantidade'] as int,
      precoUnitario: (json['preco_unitario'] as num).toDouble(),
      subtotal: (json['subtotal'] as num).toDouble(),
    );
  }
}

class CarrinhoCliente {
  final List<ItemCarrinhoCliente> itens;
  final double valorTotal;
  final String? motivoUltimaOperacao;
  final List<ItemCarrinhoCliente>? itensCorrespondentes;

  CarrinhoCliente({
    required this.itens,
    required this.valorTotal,
    this.motivoUltimaOperacao,
    this.itensCorrespondentes,
  });

  bool get vazio => itens.isEmpty;

  factory CarrinhoCliente.fromJson(Map<String, dynamic> json) {
    final carrinhoJson = (json['carrinho'] ?? json) as Map<String, dynamic>;
    final itensJson = (carrinhoJson['itens'] as List?) ?? [];
    final correspondentesJson = json['itens_correspondentes'] as List?;
    return CarrinhoCliente(
      itens: itensJson
          .map((i) => ItemCarrinhoCliente.fromJson(i as Map<String, dynamic>))
          .toList(),
      valorTotal: (carrinhoJson['valor_total'] as num?)?.toDouble() ?? 0,
      motivoUltimaOperacao: json['motivo'] as String?,
      itensCorrespondentes: correspondentesJson
          ?.map((i) => ItemCarrinhoCliente.fromJson({
                'produto_id': i['produto_id'],
                'nome': i['nome'],
                'quantidade': 0,
                'preco_unitario': 0,
                'subtotal': 0,
              }))
          .toList(),
    );
  }
}
```

- [ ] **Step 2: Criar o repository**

```dart
// lib/repositories/carrinho_cliente_repository.dart
import '../config/supabase_config.dart';
import '../models/item_carrinho_cliente.dart';

/// Acesso ao MESMO carrinho que o agente de WhatsApp e o site usam
/// (tabela `carrinho`/`carrinho_itens`, por cliente). As RPCs
/// `consultar_carrinho_app`/`alterar_carrinho_app` resolvem a empresa
/// sozinhas a partir do usuário autenticado — nunca passe empresa_id
/// daqui.
class CarrinhoClienteRepository {
  Future<CarrinhoCliente> consultar(String clienteId) async {
    final data = await supabase.rpc('consultar_carrinho_app', params: {
      'p_cliente_id': clienteId,
    });
    return CarrinhoCliente.fromJson({'carrinho': data as Map<String, dynamic>});
  }

  Future<CarrinhoCliente> removerItem(
    String clienteId, {
    String? produtoId,
    String? produtoBusca,
  }) async {
    final data = await supabase.rpc('alterar_carrinho_app', params: {
      'p_cliente_id': clienteId,
      'p_operacao': 'remover',
      'p_produto_id': produtoId,
      'p_produto_busca': produtoBusca,
    });
    return CarrinhoCliente.fromJson(data as Map<String, dynamic>);
  }

  Future<CarrinhoCliente> alterarQuantidade(
    String clienteId, {
    String? produtoId,
    String? produtoBusca,
    required int quantidade,
  }) async {
    final data = await supabase.rpc('alterar_carrinho_app', params: {
      'p_cliente_id': clienteId,
      'p_operacao': 'alterar_quantidade',
      'p_produto_id': produtoId,
      'p_produto_busca': produtoBusca,
      'p_quantidade': quantidade,
    });
    return CarrinhoCliente.fromJson(data as Map<String, dynamic>);
  }
}
```

- [ ] **Step 3: Rodar `flutter analyze` pra confirmar que os 2 arquivos novos compilam sem erro**

```bash
cd C:\Users\lucas\StudioProjects\gestor
flutter analyze lib/repositories/carrinho_cliente_repository.dart lib/models/item_carrinho_cliente.dart
```

Esperado: `No issues found!`.

- [ ] **Step 4: Commit**

```bash
git add lib/repositories/carrinho_cliente_repository.dart lib/models/item_carrinho_cliente.dart
git commit -m "feat: repository do carrinho compartilhado pro app"
```

---

### Task 4: Aba "Carrinho" em `ClienteDetalhesScreen`

**Files:**
- Modify: `lib/screens/cliente_detalhes_screen.dart`

**Interfaces:**
- Consome: `CarrinhoClienteRepository` (Tarefa 3).

- [ ] **Step 1: Adicionar a 4ª aba**

Em `lib/screens/cliente_detalhes_screen.dart:42-76`, mudar `DefaultTabController(length: 3, ...)` pra `length: 4`, adicionar `Tab(text: 'Carrinho')` na `TabBar` (depois de "Dados", antes de "Compras" — é a informação mais acionável, junto do topo) e o widget correspondente na `TabBarView`:

```dart
return DefaultTabController(
  length: 4,
  child: Scaffold(
    appBar: AppBar(
      title: Text(cliente.nome),
      actions: [ /* ...mantém igual... */ ],
      bottom: const TabBar(
        tabs: [
          Tab(text: 'Dados'),
          Tab(text: 'Carrinho'),
          Tab(text: 'Compras'),
          Tab(text: 'Conta'),
        ],
      ),
    ),
    body: TabBarView(
      children: [
        _buildDadosTab(context, cliente),
        _CarrinhoClienteTab(clienteId: cliente.idCliente ?? ''),
        _ComprasClienteTab(clienteId: cliente.idCliente),
        _ContaClienteTab(cliente: cliente),
      ],
    ),
  ),
);
```

- [ ] **Step 2: Implementar o widget da aba**

Adicionar no fim do arquivo (mesmo padrão de `_ComprasClienteTab`, linhas 323+):

```dart
class _CarrinhoClienteTab extends StatefulWidget {
  final String clienteId;

  const _CarrinhoClienteTab({required this.clienteId});

  @override
  State<_CarrinhoClienteTab> createState() => _CarrinhoClienteTabState();
}

class _CarrinhoClienteTabState extends State<_CarrinhoClienteTab> {
  final _repository = CarrinhoClienteRepository();
  late Future<CarrinhoCliente> _futureCarrinho;
  String? _removendoProdutoId;

  @override
  void initState() {
    super.initState();
    _futureCarrinho = _carregar();
  }

  Future<CarrinhoCliente> _carregar() {
    if (widget.clienteId.isEmpty) {
      return Future.value(CarrinhoCliente(itens: [], valorTotal: 0));
    }
    return _repository.consultar(widget.clienteId);
  }

  Future<void> _recarregar() async {
    setState(() => _futureCarrinho = _carregar());
    await _futureCarrinho;
  }

  Future<void> _removerItem(ItemCarrinhoCliente item) async {
    setState(() => _removendoProdutoId = item.produtoId);
    try {
      final novoCarrinho = await _repository.removerItem(
        widget.clienteId,
        produtoId: item.produtoId,
      );
      setState(() {
        _futureCarrinho = Future.value(novoCarrinho);
        _removendoProdutoId = null;
      });
    } catch (e) {
      setState(() => _removendoProdutoId = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível remover: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return FutureBuilder<CarrinhoCliente>(
      future: _futureCarrinho,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro ao carregar carrinho: ${snapshot.error}'));
        }
        final carrinho = snapshot.data!;
        if (carrinho.vazio) {
          return RefreshIndicator(
            onRefresh: _recarregar,
            child: ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Center(child: Text('Nenhum item no carrinho no momento.')),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _recarregar,
          child: ListView.builder(
            itemCount: carrinho.itens.length + 1,
            itemBuilder: (context, index) {
              if (index == carrinho.itens.length) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Total: ${currencyFormat.format(carrinho.valorTotal)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                );
              }
              final item = carrinho.itens[index];
              return ListTile(
                title: Text(item.nome),
                subtitle: Text('${item.quantidade}x ${currencyFormat.format(item.precoUnitario)}'),
                trailing: _removendoProdutoId == item.produtoId
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removerItem(item),
                      ),
              );
            },
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 3: Adicionar os imports novos no topo do arquivo**

```dart
import '../models/item_carrinho_cliente.dart';
import '../repositories/carrinho_cliente_repository.dart';
```

- [ ] **Step 4: Rodar `flutter analyze` no arquivo inteiro**

```bash
flutter analyze lib/screens/cliente_detalhes_screen.dart
```

Esperado: `No issues found!`.

- [ ] **Step 5: Testar manualmente no emulador/dispositivo**

Abrir um cliente que tenha itens reais no carrinho (usar o cliente de teste desta sessão, que tem carrinho populado). Confirmar: (a) a aba "Carrinho" mostra os itens reais e o total certo, batendo com o que `consultar_carrinho_app` devolveu no teste SQL da Tarefa 2; (b) remover um item funciona e atualiza a lista; (c) abrir um cliente sem carrinho mostra a mensagem de vazio sem erro.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/cliente_detalhes_screen.dart
git commit -m "feat: aba de carrinho ativo na tela de detalhes do cliente"
```

---

### Task 5: Tool `gerar_link_carrinho` no agente de WhatsApp

**Files:**
- Create: subworkflow n8n `WhatsApp - Tool - Gerar Link Carrinho` (via API).
- Modify: `WhatsApp - 02 Agente` (`vhFKgmonTFMqzZuz`) — novo tool node + system prompt.
- Create local: `integrations/n8n/tool-gerar-link-carrinho.json` (sync depois do deploy).

**Interfaces:**
- Consome: nenhuma RPC nova — só monta uma mensagem/link. Depende do Task 0 (formato de telefone) estar confirmado.
- Produz: tool `gerar_link_carrinho` disponível pro agente, seguindo o mesmo padrão de todo tool existente (trigger → lógica → Preparar Log → Logar Tool Call → Restaurar Saída).

Essa tool NÃO precisa gerar nenhum token novo — o carrinho já é a mesma linha (`carrinho`/`carrinho_itens` por `cliente_id`), e o login por telefone no site já entrega o código via WhatsApp (workflow `Site - Enviar OTP Login via WhatsApp`, `vvSbhI6JWIqxUvhp`, já ativo). A tool só monta a URL do carrinho no site e confirma pro agente que pode orientar o cliente.

- [ ] **Step 1: Confirmar a URL real do site**

```bash
grep -r "NEXT_PUBLIC_SITE_URL\|gestor-loja" C:\Users\lucas\StudioProjects\gestor\gestor-loja\.env* 2>/dev/null
```

Se não achar, perguntar a URL de produção real do site ao usuário antes de continuar (não adivinhar).

- [ ] **Step 2: Criar o subworkflow**

Seguir exatamente o mesmo padrão de `integrations/n8n/tool-informar-area-atendimento.json` (o mais simples já construído hoje) — trigger com `p_empresa_id`/`p_conversa_id`/`p_mensagem_id`/`p_atendimento_id`, um node de lógica que monta `{ url: 'https://<site>/carrinho', instrucao: 'Peça pro cliente confirmar o número de telefone dele no site pra ver o carrinho já com os itens.' }`, depois `Preparar Log`/`Logar Tool Call`/`Restaurar Saída` idênticos aos outros. Usar o script `build-informar-area.js` (`C:\Users\lucas\AppData\Local\Temp\claude\...\scratchpad\`, já usado hoje) como base, adaptando o node de lógica.

- [ ] **Step 3: Testar isoladamente**

Mesmo processo já usado hoje pra `informar_area_atendimento` e `buscar_produto_v2`: criar workflow temporário com Schedule Trigger de 1 min chamando o subworkflow novo, conferir a execução via `/api/v1/executions?includeData=true`, depois deletar o workflow temporário.

- [ ] **Step 4: Adicionar a tool no agente**

Mesmo padrão do node `Call 'Tool - Informar Área de Atendimento'` já existente em `WhatsApp - 02 Agente` — novo `toolWorkflow` node, conectado via `ai_tool` ao node `Agente (buscar_produto)`, descrição explicando quando usar (ex: "cliente prefere continuar no site", "cliente quer pagar com cartão" — hoje sem suporte nativo no WhatsApp).

- [ ] **Step 5: Atualizar o system prompt**

Adicionar seção "QUANDO USAR gerar_link_carrinho": usar quando o cliente pedir explicitamente pra continuar no site, ou quando mencionar pagamento com cartão (ainda sem suporte direto no WhatsApp). Orientar o agente a avisar que o cliente vai precisar confirmar o número de telefone (o mesmo do WhatsApp) pra ver o carrinho já pronto.

- [ ] **Step 6: Deploy e teste real**

Deploy via `PUT /api/v1/workflows/vhFKgmonTFMqzZuz` (mesmo processo do dia inteiro). Testar via WhatsApp real: pedir pro agente o link, confirmar que a mensagem chega com a URL certa e a instrução de confirmar o telefone. Depois, testar o fluxo completo: abrir o link, fazer OTP no site com o mesmo número usado no WhatsApp, confirmar que o carrinho aparece populado — ESSE é o teste que valida a Tarefa 0 de verdade.

- [ ] **Step 7: Sync local e commit**

```bash
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" https://n8n.lukz.com.br/api/v1/workflows/vhFKgmonTFMqzZuz -o integrations/n8n/03-agente-tools-v1.json
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" https://n8n.lukz.com.br/api/v1/workflows/<id_do_subworkflow_novo> -o integrations/n8n/tool-gerar-link-carrinho.json
git add integrations/n8n/03-agente-tools-v1.json integrations/n8n/tool-gerar-link-carrinho.json
git commit -m "feat: tool gerar_link_carrinho — handoff pro site com carrinho já populado"
```

---

## Self-Review

**Cobertura da spec** (`2026-08-14-unificacao-carrinho-gestor-whatsapp-site.md`):
- Item 1 (validar formato de telefone) → Task 0.
- Item 2 (RPCs novas pro app, reaproveitando resolução por nome) → Tasks 1-2.
- Item 3 (visibilidade/edição no app) → Tasks 3-4.
- Item 4 (tool `gerar_link_carrinho`) → Task 5.
- Item "handoff humano sem refazer nada" → já resolvido pelas correções de hoje (gate no Router + `_alterar_carrinho_core` compartilhado); Task 4 é o que dá visibilidade real disso no app.
- Explicitamente FORA de escopo (declarado no spec e repetido aqui): refatoração do `CarrinhoProvider`/`VendasScreen` pra atendimento paralelo de vendas manuais — fica pra uma Fase 2 separada, dado que esse fluxo tem conceitos (cupom, zona de entrega, agendamento) que a tabela `carrinho` compartilhada ainda não modela.
