# Identidade de Cliente Cross-Canal (Vínculo por Pessoa) — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permitir que um mesmo cliente real tenha cadastros isolados em cada canal (site, WhatsApp, iFood, 99Food, loja física) que podem ser vinculados sob uma "pessoa" canônica — sem nunca mesclar/mover dados automaticamente a partir de um identificador não-provado (CPF/CNPJ digitado), e sem quebrar o casamento por telefone/email já provado (SMS OTP / confirmação de email) do qual depende o carrinho compartilhado WhatsApp↔site.

**Architecture:** Cada linha de `clientes` continua sendo a identidade isolada de um canal. Um campo novo, `pessoa_id` (auto-referência nullable em `clientes`), aponta pra qual cadastro é o canônico da mesma pessoa — vazio por padrão (cada cadastro é dono de si mesmo). Vínculo por telefone/email continua automático (já provado por SMS/confirmação, sustenta o carrinho compartilhado). Vínculo por CPF/CNPJ (não-provado, só texto digitado) NUNCA mescla automático — só grava uma sugestão pendente numa fila que só o staff (dono/gerente) vê e aprova no app Gestor. O cliente nunca sabe que essa fila existe; o site continua mostrando só os próprios pedidos/saldo dele, sempre, antes ou depois de qualquer vínculo — o vínculo só afeta a visão agregada do STAFF (segmento, total gasto, histórico consolidado na ficha do cliente do app).

**Tech Stack:** Postgres/PL-pgSQL via Supabase MCP (`mcp__claude_ai_Supabase__apply_migration`/`execute_sql`, projeto `dwswpwxnzjgoohucngbb`), Flutter/Dart (app Gestor, `supabase_flutter`).

## Global Constraints

- Projeto Supabase: `dwswpwxnzjgoohucngbb` (Delivery Pet). Todas as mudanças de schema/RPC são aplicadas via `mcp__claude_ai_Supabase__apply_migration` (nome + SQL) — **não existem arquivos `.sql` locais neste projeto**, é a convenção já estabelecida em toda a sessão anterior.
- Toda função nova sensível é `SECURITY DEFINER` com `SET search_path TO 'public'`, seguindo o padrão de `completar_cadastro_cliente`/`entrar_ou_criar_cliente` já existentes.
- Toda tabela/função nova tem grants explícitos revogados de `anon` por padrão — esse projeto já foi pego de surpresa várias vezes por grants automáticos do Supabase vazando pra `anon`/`authenticated` em objetos novos (ver `[[feedback_whitelist_explicita_obrigatoria_subworkflows]]`). **Achado ao vivo durante a execução deste plano (Task 6)**: `REVOKE ALL ... FROM public` NÃO revoga um `EXECUTE` que o Supabase concede DIRETO pra `anon` por `ALTER DEFAULT PRIVILEGES` — as 5 funções deste plano vazaram `anon_pode=true` até uma migration de correção (`corrige_grants_anon_funcoes_vinculo_cliente`) revogar explicitamente `FROM anon` em cada uma. **Toda função nova precisa de `REVOKE EXECUTE ... FROM anon` explícito, nunca só `FROM public`** — atualizar esse hábito daqui pra frente no projeto inteiro, não só neste plano.
- Telefone/email continuam vinculando automático (não mexer em `entrar_ou_criar_cliente` neste plano) — só o caminho de CPF/CNPJ dentro de `completar_cadastro_cliente` muda.
- Flutter: seguir o padrão já usado em `authUserId` no model `Cliente` (campo só-leitura, nunca em `toSupabaseMap()`) e em `AppDestino.papeisPermitidos` (`['dono', 'gerente']`) pra qualquer tela nova sensível.
- Verificação de cada task backend: rodar uma query SQL direta provando o comportamento (mesmo padrão usado a sessão inteira: criar dado de teste, chamar a função, checar o resultado, apagar o dado de teste). Verificação de cada task Flutter: `flutter analyze` limpo + leitura do diff, mesmo padrão já usado nesta sessão (sem framework de teste automatizado configurado neste projeto).

---

## Task 1: Coluna `pessoa_id` + resolução canônica

**Files:** Migration via `apply_migration` (nome: `identidade_cliente_pessoa_id_fundacao`), projeto `dwswpwxnzjgoohucngbb`.

**Interfaces:**
- Produces: coluna `clientes.pessoa_id uuid null`; função `public.pessoa_canonica_id(p_cliente_id uuid) returns uuid`; função `public.listar_grupo_pessoa(p_cliente_id uuid) returns table(id uuid)`.

- [x] **Step 1: Aplicar a migration**

```sql
ALTER TABLE public.clientes ADD COLUMN pessoa_id uuid REFERENCES public.clientes(id);

CREATE INDEX idx_clientes_pessoa_id ON public.clientes(pessoa_id) WHERE pessoa_id IS NOT NULL;

-- Garante que pessoa_id sempre aponta direto pro cadastro raiz (que não
-- tem pessoa_id próprio) — evita cadeias A->B->C que complicariam
-- qualquer resolução; e garante que o vínculo nunca cruza empresa.
CREATE OR REPLACE FUNCTION public.validar_pessoa_id()
RETURNS trigger
LANGUAGE plpgsql
AS $$
declare
  v_alvo_pessoa_id uuid;
  v_alvo_empresa_id uuid;
begin
  if NEW.pessoa_id is null then
    return NEW;
  end if;

  if NEW.pessoa_id = NEW.id then
    raise exception 'pessoa_id não pode apontar pra si mesmo';
  end if;

  select pessoa_id, empresa_id into v_alvo_pessoa_id, v_alvo_empresa_id
  from public.clientes where id = NEW.pessoa_id;

  if v_alvo_empresa_id is null then
    raise exception 'pessoa_id aponta pra um cliente inexistente';
  end if;

  if v_alvo_empresa_id <> NEW.empresa_id then
    raise exception 'pessoa_id precisa ser da mesma empresa';
  end if;

  if v_alvo_pessoa_id is not null then
    raise exception 'pessoa_id precisa apontar pro cadastro raiz (que não tem pessoa_id próprio)';
  end if;

  return NEW;
end;
$$;

CREATE TRIGGER trg_validar_pessoa_id
BEFORE INSERT OR UPDATE OF pessoa_id ON public.clientes
FOR EACH ROW EXECUTE FUNCTION public.validar_pessoa_id();

-- "Pessoa" canônica de um cadastro: ele mesmo, se não estiver vinculado;
-- senão, o cadastro raiz que ele aponta.
CREATE OR REPLACE FUNCTION public.pessoa_canonica_id(p_cliente_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  select coalesce(pessoa_id, id) from public.clientes where id = p_cliente_id;
$$;

-- Todos os cadastros (de qualquer canal) que pertencem à mesma pessoa que
-- p_cliente_id — inclui ele mesmo. Usado pelo app pra listar pedidos/
-- métricas consolidadas na ficha do cliente.
CREATE OR REPLACE FUNCTION public.listar_grupo_pessoa(p_cliente_id uuid)
RETURNS TABLE(id uuid)
LANGUAGE sql
STABLE
AS $$
  select c.id from public.clientes c
  where c.id = public.pessoa_canonica_id(p_cliente_id)
     or c.pessoa_id = public.pessoa_canonica_id(p_cliente_id);
$$;

REVOKE ALL ON FUNCTION public.pessoa_canonica_id(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.pessoa_canonica_id(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.listar_grupo_pessoa(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.listar_grupo_pessoa(uuid) TO authenticated;
```

- [x] **Step 2: Verificar direto no banco** — `resolucao_ok=true`, `tamanho_grupo=2`, insert em cadeia falhou com a mensagem certa, dados de teste apagados.

Rodar via `execute_sql` (mesma empresa `3bce0e24-2868-49f3-a9dd-eed921ffc8e4` usada a sessão inteira):

```sql
-- cria 2 clientes de teste, vincula um ao outro, confere resolução
insert into clientes (empresa_id, telefone, nome, canal_origem)
values ('3bce0e24-2868-49f3-a9dd-eed921ffc8e4', '21900000001', 'Teste Raiz', 'whatsapp')
returning id;
-- anote o id retornado como :raiz_id

insert into clientes (empresa_id, telefone, nome, canal_origem, pessoa_id)
values ('3bce0e24-2868-49f3-a9dd-eed921ffc8e4', '21900000002', 'Teste Vinculado', 'site_proprio', '<raiz_id>')
returning id;
-- anote como :vinculado_id

select pessoa_canonica_id('<vinculado_id>') = '<raiz_id>' as resolucao_ok; -- espera true
select count(*) from listar_grupo_pessoa('<raiz_id>'); -- espera 2

-- confere a trava de cadeia (deve falhar)
insert into clientes (empresa_id, telefone, nome, canal_origem, pessoa_id)
values ('3bce0e24-2868-49f3-a9dd-eed921ffc8e4', '21900000003', 'Teste Cadeia', 'ifood', '<vinculado_id>');
-- espera erro 'pessoa_id precisa apontar pro cadastro raiz...'

delete from clientes where id in ('<raiz_id>', '<vinculado_id>');
```

Confirmar: `resolucao_ok = true`, contagem do grupo = 2, insert em cadeia falha com a mensagem certa, limpeza feita (não deixar os clientes de teste no banco).

---

## Task 2: Tabela `vinculos_cliente_pendentes`

**Files:** Migration via `apply_migration` (nome: `tabela_vinculos_cliente_pendentes`).

**Interfaces:**
- Consumes: `clientes`, `empresas`, `usuarios` (já existentes).
- Produces: tabela `public.vinculos_cliente_pendentes` (colunas: `id, empresa_id, cliente_novo_id, cliente_encontrado_id, criterio, status, revisado_por, revisado_em, created_at`).

- [x] **Step 1: Aplicar a migration**

```sql
CREATE TABLE public.vinculos_cliente_pendentes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id uuid NOT NULL REFERENCES public.empresas(id) ON DELETE CASCADE,
  cliente_novo_id uuid NOT NULL REFERENCES public.clientes(id) ON DELETE CASCADE,
  cliente_encontrado_id uuid NOT NULL REFERENCES public.clientes(id) ON DELETE CASCADE,
  criterio text NOT NULL CHECK (criterio IN ('cpf', 'cnpj')),
  status text NOT NULL DEFAULT 'pendente' CHECK (status IN ('pendente', 'aprovado', 'rejeitado')),
  revisado_por uuid REFERENCES public.usuarios(id),
  revisado_em timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_vinculos_pendente_unico
  ON public.vinculos_cliente_pendentes (cliente_novo_id, cliente_encontrado_id)
  WHERE status = 'pendente';

ALTER TABLE public.vinculos_cliente_pendentes ENABLE ROW LEVEL SECURITY;

CREATE POLICY vinculos_cliente_pendentes_isolamento
  ON public.vinculos_cliente_pendentes
  FOR SELECT
  USING (empresa_id = public.get_empresa_id());

REVOKE ALL ON public.vinculos_cliente_pendentes FROM anon;
REVOKE ALL ON public.vinculos_cliente_pendentes FROM authenticated;
GRANT SELECT ON public.vinculos_cliente_pendentes TO authenticated;
```

- [x] **Step 2: Verificar direto no banco** — `anon_pode=false, auth_pode=true, auth_insere=false`, exatamente como esperado.

```sql
select has_table_privilege('anon', 'public.vinculos_cliente_pendentes', 'SELECT') as anon_pode; -- espera false
select has_table_privilege('authenticated', 'public.vinculos_cliente_pendentes', 'SELECT') as auth_pode; -- espera true
select has_table_privilege('authenticated', 'public.vinculos_cliente_pendentes', 'INSERT') as auth_insere; -- espera false
```

Confirmar os 3 resultados exatamente como comentado (nenhum grant vazando).

---

## Task 3: RPC `detectar_vinculo_por_documento`

**Files:** Migration via `apply_migration` (nome: `rpc_detectar_vinculo_por_documento`).

**Interfaces:**
- Consumes: `normalizar_documento(text)` (já existe, criada na sessão anterior).
- Produces: `public.detectar_vinculo_por_documento(p_cliente_id uuid) returns void`.

- [x] **Step 1: Aplicar a migration**

```sql
CREATE OR REPLACE FUNCTION public.detectar_vinculo_por_documento(p_cliente_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare
  v_empresa_id uuid;
  v_tipo_pessoa text;
  v_cpf text;
  v_cnpj text;
  v_encontrado_id uuid;
begin
  select empresa_id, tipo_pessoa, cpf, cnpj
  into v_empresa_id, v_tipo_pessoa, v_cpf, v_cnpj
  from clientes where id = p_cliente_id;

  if v_empresa_id is null then
    return;
  end if;

  if v_tipo_pessoa = 'fisica' and v_cpf is not null and v_cpf <> '' then
    select id into v_encontrado_id
    from clientes
    where empresa_id = v_empresa_id
      and id <> p_cliente_id
      and pessoa_id is null
      and auth_user_id is null
      and normalizar_documento(cpf) = normalizar_documento(v_cpf)
    limit 1;

    if v_encontrado_id is not null then
      insert into vinculos_cliente_pendentes (empresa_id, cliente_novo_id, cliente_encontrado_id, criterio)
      values (v_empresa_id, p_cliente_id, v_encontrado_id, 'cpf')
      on conflict do nothing;
    end if;
  end if;

  if v_tipo_pessoa = 'juridica' and v_cnpj is not null and v_cnpj <> '' then
    select id into v_encontrado_id
    from clientes
    where empresa_id = v_empresa_id
      and id <> p_cliente_id
      and pessoa_id is null
      and auth_user_id is null
      and normalizar_documento(cnpj) = normalizar_documento(v_cnpj)
    limit 1;

    if v_encontrado_id is not null then
      insert into vinculos_cliente_pendentes (empresa_id, cliente_novo_id, cliente_encontrado_id, criterio)
      values (v_empresa_id, p_cliente_id, v_encontrado_id, 'cnpj')
      on conflict do nothing;
    end if;
  end if;
end;
$$;

REVOKE ALL ON FUNCTION public.detectar_vinculo_por_documento(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.detectar_vinculo_por_documento(uuid) TO authenticated;
```

- [x] **Step 2: Verificar direto no banco** — detectou o vínculo (CPF mascarado de um lado, sem máscara do outro), não duplicou na 2ª chamada, dados de teste apagados.

```sql
-- cliente antigo (ex: WhatsApp) com CPF real, sem login
insert into clientes (empresa_id, telefone, nome, canal_origem, tipo_pessoa, cpf)
values ('3bce0e24-2868-49f3-a9dd-eed921ffc8e4', '21900000010', 'Antigo Teste', 'whatsapp', 'fisica', '11144477735')
returning id; -- :antigo_id (CPF válido de teste, dígito verificador ok)

-- cliente novo (site) com o MESMO cpf, formatado diferente (com máscara)
insert into clientes (empresa_id, telefone, nome, canal_origem, tipo_pessoa, cpf)
values ('3bce0e24-2868-49f3-a9dd-eed921ffc8e4', '21900000011', 'Novo Teste', 'site_proprio', 'fisica', '111.444.777-35')
returning id; -- :novo_id

select detectar_vinculo_por_documento('<novo_id>');

select cliente_novo_id, cliente_encontrado_id, criterio, status
from vinculos_cliente_pendentes
where cliente_novo_id = '<novo_id>';
-- espera 1 linha: cliente_encontrado_id = :antigo_id, criterio = 'cpf', status = 'pendente'

-- roda de novo, confirma que não duplica (on conflict do nothing)
select detectar_vinculo_por_documento('<novo_id>');
select count(*) from vinculos_cliente_pendentes where cliente_novo_id = '<novo_id>'; -- espera 1

delete from vinculos_cliente_pendentes where cliente_novo_id = '<novo_id>';
delete from clientes where id in ('<antigo_id>', '<novo_id>');
```

---

## Task 4: Reverter auto-merge de CPF/CNPJ em `completar_cadastro_cliente`

**Files:** Migration via `apply_migration` (nome: `completar_cadastro_cliente_sem_automerge_documento`).

**Interfaces:**
- Consumes: `normalizar_telefone_br(text)` (já existe), `detectar_vinculo_por_documento(uuid)` (Task 3), `validar_cpf`/`validar_cnpj` (já existem).
- Produces: `public.completar_cadastro_cliente(...)` reescrita (mesma assinatura pública, nenhum call site do site/app muda).

- [x] **Step 1: Aplicar a migration**

```sql
CREATE OR REPLACE FUNCTION public.completar_cadastro_cliente(p_empresa_id uuid, p_nome text, p_tipo_pessoa text, p_cpf text DEFAULT NULL::text, p_cnpj text DEFAULT NULL::text, p_razao_social text DEFAULT NULL::text, p_genero text DEFAULT NULL::text, p_data_nascimento date DEFAULT NULL::date, p_telefone text DEFAULT NULL::text, p_aceitou_termos boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cliente_id uuid;
  v_cpf_digitos text;
  v_cnpj_digitos text;
  v_telefone_jwt text;
  v_email_jwt text;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado';
  end if;

  if p_tipo_pessoa not in ('fisica', 'juridica') then
    raise exception 'Tipo de pessoa inválido';
  end if;

  if p_nome is null or trim(p_nome) = '' then
    raise exception 'Nome é obrigatório';
  end if;

  if not p_aceitou_termos then
    raise exception 'É necessário aceitar os termos de uso';
  end if;

  if p_tipo_pessoa = 'fisica' then
    v_cpf_digitos := regexp_replace(coalesce(p_cpf, ''), '[^0-9]', '', 'g');
    if not validar_cpf(v_cpf_digitos) then
      raise exception 'CPF inválido';
    end if;
  else
    v_cnpj_digitos := regexp_replace(coalesce(p_cnpj, ''), '[^0-9]', '', 'g');
    if not validar_cnpj(v_cnpj_digitos) then
      raise exception 'CNPJ inválido';
    end if;
    if p_razao_social is null or trim(p_razao_social) = '' then
      raise exception 'Razão social é obrigatória para pessoa jurídica';
    end if;
  end if;

  select id into v_cliente_id from clientes where empresa_id = p_empresa_id and auth_user_id = auth.uid();

  if v_cliente_id is null then
    v_telefone_jwt := auth.jwt() ->> 'phone';
    v_email_jwt := auth.jwt() ->> 'email';
    if (v_telefone_jwt is null or v_telefone_jwt = '') and (v_email_jwt is null or v_email_jwt = '') then
      raise exception 'Sessão sem telefone ou email verificado';
    end if;

    -- Sem casamento por CPF/CNPJ aqui — é texto digitado, sem prova de
    -- posse nenhuma (diferente de telefone/email, provados por SMS/link
    -- de confirmação). Cadastro novo sempre nasce isolado; a detecção de
    -- possível mesma pessoa vira sugestão pendente pro staff revisar no
    -- app (ver detectar_vinculo_por_documento), nunca mescla sozinha.
    insert into clientes (
      empresa_id, telefone, email, nome, tipo_pessoa, cpf, cnpj, razao_social,
      genero, data_nascimento, auth_user_id, canal_origem, termos_aceitos_em
    ) values (
      p_empresa_id,
      coalesce(nullif(normalizar_telefone_br(v_telefone_jwt), ''), nullif(p_telefone, ''), ''),
      nullif(v_email_jwt, ''),
      trim(p_nome),
      p_tipo_pessoa,
      case when p_tipo_pessoa = 'fisica' then v_cpf_digitos else null end,
      case when p_tipo_pessoa = 'juridica' then v_cnpj_digitos else null end,
      case when p_tipo_pessoa = 'juridica' then trim(p_razao_social) else null end,
      nullif(trim(coalesce(p_genero, '')), ''),
      p_data_nascimento,
      auth.uid(),
      'site_proprio',
      now()
    )
    returning id into v_cliente_id;

    perform detectar_vinculo_por_documento(v_cliente_id);

    return v_cliente_id;
  end if;

  update clientes set
    nome = trim(p_nome),
    tipo_pessoa = p_tipo_pessoa,
    cpf = case when p_tipo_pessoa = 'fisica' then v_cpf_digitos else null end,
    cnpj = case when p_tipo_pessoa = 'juridica' then v_cnpj_digitos else null end,
    razao_social = case when p_tipo_pessoa = 'juridica' then trim(p_razao_social) else null end,
    genero = nullif(trim(coalesce(p_genero, '')), ''),
    data_nascimento = p_data_nascimento,
    telefone = case when (telefone is null or telefone = '') and p_telefone is not null and trim(p_telefone) <> ''
                    then p_telefone else telefone end,
    termos_aceitos_em = now()
  where id = v_cliente_id;

  return v_cliente_id;
end;
$function$;
```

- [x] **Step 2: Verificar direto no banco** — `sem_automerge_cpf=true`, `chama_deteccao=true`.

Repetir o teste do Task 3 (cliente antigo com CPF real) mas chamando `completar_cadastro_cliente` через um usuário de teste autenticado não é viável direto por SQL puro (depende de `auth.uid()`/`auth.jwt()` de uma sessão real) — em vez disso, confirmar por leitura que a função não tem mais nenhuma referência a `normalizar_documento` no corpo:

```sql
select pg_get_functiondef(oid) not ilike '%normalizar_documento%' as sem_automerge_cpf
from pg_proc where proname = 'completar_cadastro_cliente' and pronamespace = 'public'::regnamespace;
-- espera true

select pg_get_functiondef(oid) ilike '%detectar_vinculo_por_documento%' as chama_deteccao
from pg_proc where proname = 'completar_cadastro_cliente' and pronamespace = 'public'::regnamespace;
-- espera true
```

O teste ponta-a-ponta de verdade (login real no site com CPF de outra conta, confirmar que aparece em `vinculos_cliente_pendentes` em vez de mesclar) fica pra validação manual do usuário depois do deploy, junto com a Task 6.

---

## Task 5: Métricas agregadas por pessoa (`recalcular_metricas_grupo_pessoa`)

**Files:** Migration via `apply_migration` (nome: `metricas_cliente_agregadas_por_pessoa`).

**Interfaces:**
- Consumes: `pessoa_canonica_id(uuid)` (Task 1), `calcular_segmento_cliente(integer, numeric, timestamptz)` (já existe).
- Produces: `public.recalcular_metricas_grupo_pessoa(p_cliente_id uuid) returns void`; reescreve o trigger `atualizar_cliente_metricas()` (mesma assinatura de trigger, mesmo disparo em `pedidos`).

- [x] **Step 1: Aplicar a migration**

```sql
-- Soma pedidos entregues de TODOS os cadastros vinculados à mesma pessoa
-- (não só do cadastro que recebeu o pedido) e grava o total em CADA linha
-- do grupo — assim a ficha do cliente no app mostra o mesmo total
-- consolidado não importa por qual cadastro (canal) o staff entrar.
CREATE OR REPLACE FUNCTION public.recalcular_metricas_grupo_pessoa(p_cliente_id uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
declare
  v_pessoa_id uuid;
  v_total_gasto numeric;
  v_total_pedidos integer;
  v_ticket_medio numeric;
  v_ultima_compra timestamptz;
begin
  v_pessoa_id := pessoa_canonica_id(p_cliente_id);

  select coalesce(sum(p.valor_total), 0), count(*), coalesce(avg(p.valor_total), 0), max(p.created_at)
  into v_total_gasto, v_total_pedidos, v_ticket_medio, v_ultima_compra
  from pedidos p
  where p.status = 'entregue'
    and p.cliente_id in (
      select id from clientes where id = v_pessoa_id or pessoa_id = v_pessoa_id
    );

  update clientes
  set total_gasto = v_total_gasto,
      total_pedidos = v_total_pedidos,
      ticket_medio = v_ticket_medio,
      ultima_compra = v_ultima_compra,
      segmento = calcular_segmento_cliente(v_total_pedidos, v_total_gasto, v_ultima_compra),
      updated_at = now()
  where id = v_pessoa_id or pessoa_id = v_pessoa_id;
end;
$$;

CREATE OR REPLACE FUNCTION public.atualizar_cliente_metricas()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.status = 'entregue' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM NEW.status) THEN
    PERFORM recalcular_metricas_grupo_pessoa(NEW.cliente_id);
  END IF;
  RETURN NEW;
END;
$$;
```

- [x] **Step 2: Verificar direto no banco** — as duas linhas do grupo mostraram `total_pedidos=2, total_gasto=150.00` consolidado.

```sql
-- 2 clientes vinculados, cada um com 1 pedido entregue
insert into clientes (empresa_id, telefone, nome, canal_origem)
values ('3bce0e24-2868-49f3-a9dd-eed921ffc8e4', '21900000020', 'Grupo Raiz', 'whatsapp')
returning id; -- :raiz_id

insert into clientes (empresa_id, telefone, nome, canal_origem, pessoa_id)
values ('3bce0e24-2868-49f3-a9dd-eed921ffc8e4', '21900000021', 'Grupo Vinculado', 'site_proprio', '<raiz_id>')
returning id; -- :vinc_id

insert into pedidos (empresa_id, cliente_id, status, valor_total, canal_venda, origem)
values ('3bce0e24-2868-49f3-a9dd-eed921ffc8e4', '<raiz_id>', 'entregue', 100.00, 'whatsapp', 'whatsapp');

insert into pedidos (empresa_id, cliente_id, status, valor_total, canal_venda, origem)
values ('3bce0e24-2868-49f3-a9dd-eed921ffc8e4', '<vinc_id>', 'entregue', 50.00, 'site_proprio', 'site');

select id, total_pedidos, total_gasto from clientes where id in ('<raiz_id>', '<vinc_id>');
-- espera as DUAS linhas com total_pedidos = 2, total_gasto = 150.00

delete from pedidos where cliente_id in ('<raiz_id>', '<vinc_id>');
delete from clientes where id in ('<raiz_id>', '<vinc_id>');
```

Confirmar que ambas as linhas mostram o total consolidado (150,00 / 2 pedidos), não só a própria.

---

## Task 6: RPCs `vincular_clientes` e `rejeitar_vinculo`

**Files:** Migration via `apply_migration` (nome: `rpc_vincular_rejeitar_cliente`).

**Interfaces:**
- Consumes: `recalcular_metricas_grupo_pessoa(uuid)` (Task 5), tabela `vinculos_cliente_pendentes` (Task 2), `usuarios`.
- Produces: `public.vincular_clientes(p_vinculo_id uuid) returns void`; `public.rejeitar_vinculo(p_vinculo_id uuid) returns void`.

- [x] **Step 1: Aplicar a migration**

```sql
CREATE OR REPLACE FUNCTION public.vincular_clientes(p_vinculo_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare
  v_empresa_id uuid;
  v_novo_id uuid;
  v_encontrado_id uuid;
  v_status text;
  v_usuario_empresa_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado';
  end if;

  select empresa_id into v_usuario_empresa_id from usuarios where id = auth.uid();
  if v_usuario_empresa_id is null then
    raise exception 'Só staff pode vincular clientes';
  end if;

  select empresa_id, cliente_novo_id, cliente_encontrado_id, status
  into v_empresa_id, v_novo_id, v_encontrado_id, v_status
  from vinculos_cliente_pendentes where id = p_vinculo_id;

  if v_empresa_id is null then
    raise exception 'Sugestão de vínculo não encontrada';
  end if;

  if v_empresa_id <> v_usuario_empresa_id then
    raise exception 'Sugestão de vínculo não pertence à sua empresa';
  end if;

  if v_status <> 'pendente' then
    raise exception 'Essa sugestão já foi revisada';
  end if;

  update clientes set pessoa_id = v_encontrado_id where id = v_novo_id;

  update vinculos_cliente_pendentes
  set status = 'aprovado', revisado_por = auth.uid(), revisado_em = now()
  where id = p_vinculo_id;

  perform recalcular_metricas_grupo_pessoa(v_encontrado_id);
end;
$$;

CREATE OR REPLACE FUNCTION public.rejeitar_vinculo(p_vinculo_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
declare
  v_empresa_id uuid;
  v_status text;
  v_usuario_empresa_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado';
  end if;

  select empresa_id into v_usuario_empresa_id from usuarios where id = auth.uid();
  if v_usuario_empresa_id is null then
    raise exception 'Só staff pode revisar vínculos';
  end if;

  select empresa_id, status into v_empresa_id, v_status
  from vinculos_cliente_pendentes where id = p_vinculo_id;

  if v_empresa_id is null then
    raise exception 'Sugestão de vínculo não encontrada';
  end if;

  if v_empresa_id <> v_usuario_empresa_id then
    raise exception 'Sugestão de vínculo não pertence à sua empresa';
  end if;

  if v_status <> 'pendente' then
    raise exception 'Essa sugestão já foi revisada';
  end if;

  update vinculos_cliente_pendentes
  set status = 'rejeitado', revisado_por = auth.uid(), revisado_em = now()
  where id = p_vinculo_id;
end;
$$;

REVOKE ALL ON FUNCTION public.vincular_clientes(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.vincular_clientes(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.rejeitar_vinculo(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.rejeitar_vinculo(uuid) TO authenticated;
```

- [x] **Step 2: Verificar direto no banco** — `prosecdef=true` nas 2. **1ª checagem achou `anon_pode_vincular=true`** (na verdade em TODAS as 5 funções deste plano, Tasks 1/3/6) — corrigido com `REVOKE EXECUTE ... FROM anon` explícito em cada uma (migration `corrige_grants_anon_funcoes_vinculo_cliente`), reverificado limpo: `anon=false, authenticated=true` nas 5. Ver nota em Global Constraints.

```sql
select proname, prosecdef from pg_proc
where proname in ('vincular_clientes', 'rejeitar_vinculo') and pronamespace = 'public'::regnamespace;
-- espera as 2 linhas com prosecdef = true (SECURITY DEFINER)

select has_function_privilege('authenticated', 'public.vincular_clientes(uuid)', 'EXECUTE') as auth_pode_vincular;
select has_function_privilege('anon', 'public.vincular_clientes(uuid)', 'EXECUTE') as anon_pode_vincular;
-- espera true / false
```

Teste funcional completo (chamando como um usuário `usuarios` real, checando que `pessoa_id`/status/métricas mudam certo) fica pra teste manual do usuário direto no app, depois da Task 10 — mais fácil de validar pela UI do que simulando `auth.uid()` staff por SQL puro.

---

## Task 7: Campo `pessoaId` no model `Cliente`

**Files:**
- Modify: `lib/models/cliente.dart`

**Interfaces:**
- Produces: `Cliente.pessoaId` (`String?`, populado a partir de `row['pessoa_id']`, nunca em `toSupabaseMap()` — mesmo padrão de `authUserId`).

- [x] **Step 1: Adicionar o campo, seguindo exatamente o padrão de `authUserId`**

Em `lib/models/cliente.dart`, logo abaixo do bloco de `authUserId` (linha ~75), adicionar:

```dart
  /// Vínculo com o cadastro canônico da mesma pessoa em outro canal (ver
  /// [[gestor_app_context]], plano "Identidade de Cliente Cross-Canal") —
  /// null significa "não vinculado, é sua própria pessoa". Só leitura
  /// aqui, nunca vai em `toSupabaseMap()` — o vínculo só é criado pelas
  /// RPCs `vincular_clientes`/`detectar_vinculo_por_documento`, nunca
  /// pelo formulário genérico de editar cliente.
  final String? pessoaId;
```

No construtor (logo após `this.authUserId,`):

```dart
    this.pessoaId,
```

No `copyWith` (logo após `authUserId: authUserId,`):

```dart
      pessoaId: pessoaId,
```

Em `Cliente.fromSupabase` (logo após `authUserId: row['auth_user_id'] as String?,`):

```dart
      pessoaId: row['pessoa_id'] as String?,
```

**Não adicionar em `toSupabaseMap()`** — deixar de fora, igual `authUserId`.

- [x] **Step 2: Verificar** — `flutter analyze lib/models/cliente.dart`: "No issues found!"

```bash
cd "C:/Users/lucas/StudioProjects/gestor" && flutter analyze lib/models/cliente.dart
```

Esperar: nenhum erro novo (o mesmo aviso pré-existente de `intl`, se aparecer em outro arquivo, não conta aqui).

- [x] **Step 3: Commit** — `5eda42e`

```bash
git add lib/models/cliente.dart
git commit -m "Adiciona campo pessoaId ao model Cliente (base pro vínculo cross-canal)"
```

---

## Task 8: Histórico de compras consolidado por pessoa

**Files:**
- Modify: `lib/repositories/venda_repository.dart:45-56` (método `listarPorCliente`)
- Modify: `lib/screens/cliente_detalhes_screen.dart:557-561` (`_ComprasClienteTabState._carregar`)

**Interfaces:**
- Consumes: RPC `listar_grupo_pessoa(uuid)` (Task 1).
- Produces: `VendaRepository.listarPorCliente` passa a devolver pedidos de TODOS os cadastros vinculados, não só do `clienteId` recebido (mesma assinatura pública — nenhum outro call site precisa mudar).

- [x] **Step 1: Reescrever `listarPorCliente` pra resolver o grupo primeiro**

Em `lib/repositories/venda_repository.dart`, substituir:

```dart
  Future<List<Venda>> listarPorCliente(String clienteId) async {
    final data = await supabase
        .from('pedidos')
        .select(_selectComItensECliente)
        .eq('cliente_id', clienteId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);

    return (data as List)
        .map((row) => _vendaFromRow(row as Map<String, dynamic>))
        .toList();
  }
```

por:

```dart
  /// Pedidos do cliente E de qualquer outro cadastro (outro canal) já
  /// vinculado a ele como a mesma pessoa (ver `listar_grupo_pessoa`,
  /// plano "Identidade de Cliente Cross-Canal") — sem vínculo nenhum,
  /// `listar_grupo_pessoa` devolve só o próprio id, comportamento
  /// idêntico ao de antes.
  Future<List<Venda>> listarPorCliente(String clienteId) async {
    final grupo = await supabase.rpc('listar_grupo_pessoa', params: {'p_cliente_id': clienteId});
    final ids = (grupo as List).map((r) => r['id'] as String).toList();

    final data = await supabase
        .from('pedidos')
        .select(_selectComItensECliente)
        .inFilter('cliente_id', ids)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);

    return (data as List)
        .map((row) => _vendaFromRow(row as Map<String, dynamic>))
        .toList();
  }
```

- [x] **Step 2: Verificar** — só o aviso pré-existente do `intl`, nada novo.

```bash
cd "C:/Users/lucas/StudioProjects/gestor" && flutter analyze lib/repositories/venda_repository.dart lib/screens/cliente_detalhes_screen.dart
```

Esperar: limpo.

- [x] **Step 3: Verificar comportamento direto no banco (mesmo dado de teste do Task 5)** — `listar_grupo_pessoa` devolveu as 2 linhas esperadas.

```sql
insert into clientes (empresa_id, telefone, nome, canal_origem)
values ('3bce0e24-2868-49f3-a9dd-eed921ffc8e4', '21900000030', 'Consolidado Raiz', 'whatsapp')
returning id; -- :raiz_id

insert into clientes (empresa_id, telefone, nome, canal_origem, pessoa_id)
values ('3bce0e24-2868-49f3-a9dd-eed921ffc8e4', '21900000031', 'Consolidado Vinculado', 'site_proprio', '<raiz_id>')
returning id; -- :vinc_id

select id from listar_grupo_pessoa('<raiz_id>');
-- espera 2 linhas: :raiz_id e :vinc_id

delete from clientes where id in ('<raiz_id>', '<vinc_id>');
```

- [x] **Step 4: Commit** — `579ba7d`

```bash
git add lib/repositories/venda_repository.dart
git commit -m "Aba Compras do cliente passa a consolidar pedidos de cadastros vinculados"
```

---

## Task 9: Model e repositório de sugestões de vínculo

**Files:**
- Create: `lib/models/vinculo_cliente.dart`
- Create: `lib/repositories/vinculo_cliente_repository.dart`

**Interfaces:**
- Produces: `VinculoCliente` (campos: `id`, `criterio`, `criadoEm`, `nomeNovo`, `telefoneNovo`, `canalNovo`, `nomeEncontrado`, `telefoneEncontrado`, `canalEncontrado`, `totalPedidosEncontrado`, `saldoEncontrado`, `saldoPetCashEncontrado`); `VinculoClienteRepository.listarPendentes()`, `.aprovar(String id)`, `.rejeitar(String id)`.

- [x] **Step 1: Criar o model**

`lib/models/vinculo_cliente.dart`:

```dart
/// Sugestão de vínculo entre 2 cadastros de `clientes` que bateram por
/// CPF/CNPJ (documento digitado, sem prova de posse — por isso nunca
/// mescla sozinho, sempre passa por aqui) — ver
/// `detectar_vinculo_por_documento` e plano "Identidade de Cliente
/// Cross-Canal". Só staff (dono/gerente) vê esta tela; o cliente nunca
/// sabe que essa fila existe.
class VinculoCliente {
  final String id;
  final String criterio; // 'cpf' | 'cnpj'
  final DateTime criadoEm;

  final String clienteNovoId;
  final String nomeNovo;
  final String telefoneNovo;
  final String? canalNovo;

  final String clienteEncontradoId;
  final String nomeEncontrado;
  final String telefoneEncontrado;
  final String? canalEncontrado;
  final int totalPedidosEncontrado;
  final double saldoEncontrado;
  final double saldoPetCashEncontrado;

  VinculoCliente({
    required this.id,
    required this.criterio,
    required this.criadoEm,
    required this.clienteNovoId,
    required this.nomeNovo,
    required this.telefoneNovo,
    this.canalNovo,
    required this.clienteEncontradoId,
    required this.nomeEncontrado,
    required this.telefoneEncontrado,
    this.canalEncontrado,
    required this.totalPedidosEncontrado,
    required this.saldoEncontrado,
    required this.saldoPetCashEncontrado,
  });

  factory VinculoCliente.fromSupabase(Map<String, dynamic> row) {
    final novo = row['cliente_novo'] as Map<String, dynamic>;
    final encontrado = row['cliente_encontrado'] as Map<String, dynamic>;

    return VinculoCliente(
      id: row['id'] as String,
      criterio: row['criterio'] as String,
      criadoEm: DateTime.parse(row['created_at'] as String),
      clienteNovoId: novo['id'] as String,
      nomeNovo: novo['nome']?.toString() ?? '',
      telefoneNovo: novo['telefone']?.toString() ?? '',
      canalNovo: novo['canal_origem']?.toString(),
      clienteEncontradoId: encontrado['id'] as String,
      nomeEncontrado: encontrado['nome']?.toString() ?? '',
      telefoneEncontrado: encontrado['telefone']?.toString() ?? '',
      canalEncontrado: encontrado['canal_origem']?.toString(),
      totalPedidosEncontrado: (encontrado['total_pedidos'] as num?)?.toInt() ?? 0,
      saldoEncontrado: (encontrado['saldo'] as num?)?.toDouble() ?? 0.0,
      saldoPetCashEncontrado: (encontrado['saldo_petcash'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
```

- [x] **Step 2: Criar o repositório**

`lib/repositories/vinculo_cliente_repository.dart`:

```dart
import '../config/supabase_config.dart';
import '../models/vinculo_cliente.dart';

/// Acesso à fila de sugestões de vínculo entre cadastros — ver
/// `VinculoCliente` pro contexto completo.
class VinculoClienteRepository {
  Future<List<VinculoCliente>> listarPendentes() async {
    final data = await supabase
        .from('vinculos_cliente_pendentes')
        .select('''
          id, criterio, created_at,
          cliente_novo:clientes!vinculos_cliente_pendentes_cliente_novo_id_fkey(id, nome, telefone, canal_origem),
          cliente_encontrado:clientes!vinculos_cliente_pendentes_cliente_encontrado_id_fkey(id, nome, telefone, canal_origem, total_pedidos, saldo, saldo_petcash)
        ''')
        .eq('status', 'pendente')
        .order('created_at');

    return (data as List)
        .map((row) => VinculoCliente.fromSupabase(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> aprovar(String vinculoId) async {
    await supabase.rpc('vincular_clientes', params: {'p_vinculo_id': vinculoId});
  }

  Future<void> rejeitar(String vinculoId) async {
    await supabase.rpc('rejeitar_vinculo', params: {'p_vinculo_id': vinculoId});
  }
}
```

- [x] **Step 3: Verificar** — "No issues found!"

```bash
cd "C:/Users/lucas/StudioProjects/gestor" && flutter analyze lib/models/vinculo_cliente.dart lib/repositories/vinculo_cliente_repository.dart
```

Esperar: limpo.

- [x] **Step 4: Commit** — `31b5583`

```bash
git add lib/models/vinculo_cliente.dart lib/repositories/vinculo_cliente_repository.dart
git commit -m "Adiciona model e repositório de sugestões de vínculo de cliente"
```

---

## Task 10: Tela de revisão de vínculos (staff)

**Files:**
- Create: `lib/screens/vinculos_clientes_screen.dart`
- Modify: `lib/utils/app_destinos.dart`

**Interfaces:**
- Consumes: `VinculoClienteRepository` (Task 9).
- Produces: `VinculosClientesScreen` (StatefulWidget), registrada em `appDestinos` com `papeisPermitidos: ['dono', 'gerente']`.

- [x] **Step 1: Criar a tela**

`lib/screens/vinculos_clientes_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/vinculo_cliente.dart';
import '../repositories/vinculo_cliente_repository.dart';

/// Fila de possíveis mesmas-pessoas detectadas por CPF/CNPJ entre canais
/// diferentes (site/WhatsApp/iFood/99Food/loja física) — staff confirma
/// ou rejeita, nunca acontece automático (ver `VinculoCliente`).
class VinculosClientesScreen extends StatefulWidget {
  const VinculosClientesScreen({super.key});

  @override
  State<VinculosClientesScreen> createState() => _VinculosClientesScreenState();
}

class _VinculosClientesScreenState extends State<VinculosClientesScreen> {
  final _repository = VinculoClienteRepository();
  late Future<List<VinculoCliente>> _futureVinculos;
  final Set<String> _emProcessamento = {};

  @override
  void initState() {
    super.initState();
    _futureVinculos = _repository.listarPendentes();
  }

  Future<void> _recarregar() async {
    setState(() => _futureVinculos = _repository.listarPendentes());
    await _futureVinculos;
  }

  Future<void> _confirmarEAgir(VinculoCliente vinculo, {required bool aprovar}) async {
    final valorEmRisco = vinculo.saldoEncontrado > 0 || vinculo.saldoPetCashEncontrado > 0;
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(aprovar ? 'Vincular cadastros?' : 'Rejeitar sugestão?'),
        content: Text(
          aprovar
              ? '"${vinculo.nomeNovo}" (novo, ${vinculo.canalNovo ?? "?"}) será vinculado a '
                  '"${vinculo.nomeEncontrado}" (${vinculo.canalEncontrado ?? "?"}, '
                  '${vinculo.totalPedidosEncontrado} pedido(s)'
                  '${valorEmRisco ? ", saldo ${currencyFormat.format(vinculo.saldoEncontrado)} + PetCash ${currencyFormat.format(vinculo.saldoPetCashEncontrado)}" : ""}).\n\n'
                  'O histórico consolidado passa a aparecer na ficha de ambos.'
              : 'A sugestão será descartada — os 2 cadastros continuam separados.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(aprovar ? 'Vincular' : 'Rejeitar')),
        ],
      ),
    );

    if (confirmou != true) return;

    setState(() => _emProcessamento.add(vinculo.id));
    try {
      if (aprovar) {
        await _repository.aprovar(vinculo.id);
      } else {
        await _repository.rejeitar(vinculo.id);
      }
      await _recarregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) setState(() => _emProcessamento.remove(vinculo.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Scaffold(
      appBar: AppBar(title: const Text('Vínculos de Clientes')),
      body: FutureBuilder<List<VinculoCliente>>(
        future: _futureVinculos,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro ao carregar vínculos: ${snapshot.error}'));
          }

          final vinculos = snapshot.data ?? [];
          if (vinculos.isEmpty) {
            return RefreshIndicator(
              onRefresh: _recarregar,
              child: ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('Nenhum vínculo pendente de revisão.')),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _recarregar,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: vinculos.length,
              itemBuilder: (context, index) {
                final vinculo = vinculos[index];
                final processando = _emProcessamento.contains(vinculo.id);
                final valorEmRisco = vinculo.saldoEncontrado > 0 || vinculo.saldoPetCashEncontrado > 0;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bateu por ${vinculo.criterio.toUpperCase()} • ${dateFormat.format(vinculo.criadoEm)}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(height: 8),
                        Text('Novo: ${vinculo.nomeNovo} (${vinculo.canalNovo ?? "?"}) — ${vinculo.telefoneNovo}'),
                        Text(
                          'Encontrado: ${vinculo.nomeEncontrado} (${vinculo.canalEncontrado ?? "?"}) — '
                          '${vinculo.telefoneEncontrado} — ${vinculo.totalPedidosEncontrado} pedido(s)',
                        ),
                        if (valorEmRisco)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Saldo: ${currencyFormat.format(vinculo.saldoEncontrado)} • '
                              'PetCash: ${currencyFormat.format(vinculo.saldoPetCashEncontrado)}',
                              style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.bold),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: processando ? null : () => _confirmarEAgir(vinculo, aprovar: false),
                              child: const Text('Rejeitar'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: processando ? null : () => _confirmarEAgir(vinculo, aprovar: true),
                              child: processando
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Text('Vincular'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
```

- [x] **Step 2: Registrar no menu, só pra dono/gerente**

Em `lib/utils/app_destinos.dart`, adicionar o import:

```dart
import '../screens/vinculos_clientes_screen.dart';
```

E adicionar no fim da lista `appDestinos` (após o item `'Campanhas de Ativação'`, mesmo bloco de itens dono/gerente):

```dart
  AppDestino(
    titulo: 'Vínculos de Clientes',
    icone: Icons.link,
    builder: (_) => const VinculosClientesScreen(),
    papeisPermitidos: ['dono', 'gerente'],
  ),
```

- [x] **Step 3: Verificar** — só o aviso pré-existente do `intl`.

```bash
cd "C:/Users/lucas/StudioProjects/gestor" && flutter analyze lib/screens/vinculos_clientes_screen.dart lib/utils/app_destinos.dart
```

Esperar: limpo.

- [x] **Step 4: Commit** — `42fdc76`

```bash
git add lib/screens/vinculos_clientes_screen.dart lib/utils/app_destinos.dart
git commit -m "Adiciona tela de revisão de vínculos de cliente (dono/gerente)"
```

---

## Task 11: Indicador de vínculo na ficha do cliente

**Files:**
- Modify: `lib/screens/cliente_detalhes_screen.dart` (`_buildDadosTab`)

**Interfaces:**
- Consumes: `Cliente.pessoaId` (Task 7).

- [x] **Step 1: Adicionar um aviso simples quando o cliente é um cadastro vinculado**

Em `cliente_detalhes_screen.dart`, dentro de `_buildDadosTab`, logo abaixo do `CircleAvatar` central (após o `Center(child: CircleAvatar(...))`), adicionar:

```dart
        if (cliente.pessoaId != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: Chip(
                avatar: const Icon(Icons.link, size: 16),
                label: const Text('Vinculado a outro cadastro — histórico consolidado'),
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              ),
            ),
          ),
```

- [x] **Step 2: Verificar** — só o aviso pré-existente do `intl`.

```bash
cd "C:/Users/lucas/StudioProjects/gestor" && flutter analyze lib/screens/cliente_detalhes_screen.dart
```

Esperar: limpo.

- [x] **Step 3: Commit** — `faa861a`

```bash
git add lib/screens/cliente_detalhes_screen.dart
git commit -m "Mostra indicador de vínculo na ficha do cliente"
```

---

## Fora do escopo deste plano (decisão consciente, não esquecimento)

- **Desvincular** (`pessoa_id` → null de volta) — não construído; se um vínculo for aprovado por engano, hoje precisa de um `UPDATE clientes SET pessoa_id = null WHERE id = ...` manual. Adicionar um `desvincular_clientes(uuid)` é natural de acrescentar depois, mesmo padrão do `rejeitar_vinculo`.
- **Carteira (saldo/PetCash) compartilhada entre cadastros vinculados** — decisão consciente: o cliente continua vendo/gastando só o saldo do PRÓPRIO cadastro no site, nunca o do cadastro vinculado, mesmo depois do vínculo aprovado. Só a visão do STAFF (segmento/total gasto/histórico) fica consolidada. Evita reabrir o mesmo risco de exposição de saldo que motivou todo este plano.
- **Migração retroativa de duplicados já existentes no banco** (ex: os ~12 clientes com telefone malformado mencionados em `[[gestor_app_context]]`) — a detecção só roda em cadastros NOVOS do site daqui pra frente. Rodar `detectar_vinculo_por_documento` retroativamente pra todo `clientes` já existente é factível (é só um loop), mas fica pra quando o usuário pedir.
- **Guarda de telefone/email reciclado** (discutida na sessão, risco pré-existente e menor) — telefone/email continuam vinculando automático sem trava adicional neste plano.

---

## Self-Review

**Cobertura do que foi discutido**: senha mínima e cadastro fantasma já estavam resolvidos antes deste plano (sessão anterior); este plano cobre especificamente a arquitetura de vínculo por pessoa (Tasks 1-6 backend, 7-11 app) — CPF/CNPJ nunca mais mescla sozinho (Task 4), telefone/email continuam automáticos (nenhuma mudança em `entrar_ou_criar_cliente`), staff revisa (Tasks 6, 10), site do cliente não muda em nada (nenhuma task toca `gestor-loja`).

**Placeholders**: nenhum "implementar depois"/"adicionar validação" solto — todo SQL e código Dart está completo, copiável direto.

**Consistência de tipos/nomes**: `pessoa_canonica_id`/`listar_grupo_pessoa` (Task 1) usados identicamente em `recalcular_metricas_grupo_pessoa` (Task 5) e no repositório Dart (Task 8); `VinculoCliente`/`VinculoClienteRepository` (Task 9) usados identicamente na tela (Task 10); `pessoaId` (Task 7) usado identicamente em `cliente_detalhes_screen.dart` (Task 11).
