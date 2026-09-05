# App do Entregador — Fase 1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir o app "Entregador" (Flutter, novo projeto separado do Gestor) ponta a ponta: login próprio do entregador, ver rotas do dia, iniciar rota, navegar/marcar entregue/não entregue por parada, finalizar rota — sem rastreio GPS ao vivo (Fase 2/3, fora deste escopo). Baseado no spec aprovado `docs/superpowers/specs/2026-09-04-app-entregador-fase1-design.md`.

**Architecture:** Novo app Flutter (`entregador-app`, sibling de `gestor`) na mesma stack (Supabase + Provider), reaproveitando RPCs/lógica já existentes no banco e duplicando pequenos trechos de código do Gestor (ex: `distancia_service.dart`) em vez de extrair um pacote compartilhado. Identidade do entregador vive em `entregadores.auth_user_id`, sem linha em `usuarios` — por isso quase todo RLS/RPC que hoje usa `get_empresa_id()` (que só enxerga `usuarios`) precisa de política/checagem adicional específica pra entregador.

**Tech Stack:** Flutter 3.x, Supabase (`supabase_flutter`), Provider, `url_launcher`, `firebase_core`/`firebase_messaging` (push), Google Maps Distance Matrix/Directions API (via HTTP, mesma chave do Gestor).

## Global Constraints

- Projeto Supabase único pros dois apps: `dwswpwxnzjgoohucngbb` (mesma URL/anon key do Gestor, `lib/config/supabase_config.dart`).
- Nenhuma linha em `usuarios` é criada pro entregador — decisão de design já fechada no spec (linha 26-32). Toda leitura/escrita nova precisa funcionar SEM `get_empresa_id()`/`get_papel()` retornando valor (eles fazem `select ... from usuarios where id = auth.uid()`, que dá NULL pra um entregador).
- `confirmar_pagamento_entrega_loja_fisica` **não é uma RPC** (o spec original supôs que fosse) — é uma trigger BEFORE UPDATE em `pedidos` que roda sozinha quando `status` vira `'entregue'` e `canal_venda = 'loja_fisica'`. O app do entregador não chama nada especial pra isso, só atualiza `pedidos.status`.
- Novo pacote Android do app do entregador: `br.com.deliverypet.entregador`. Projeto Firebase reaproveitado: `deliverypet-6d0e7` (mesmo do Gestor), com um novo app Android registrado nele.
- Pasta do projeto novo: `C:\Users\lucas\StudioProjects\entregador-app` (sibling de `gestor`, mesmo padrão de `gestor-loja`/`gestor-conteudo-social`).
- `url_launcher: ^6.1.9` pra deep link do Google Maps (mesma versão já usada no Gestor).
- Toda migration é aplicada com `mcp__claude_ai_Supabase__apply_migration` no projeto `dwswpwxnzjgoohucngbb` — não existe SQL versionado no repo (confirmado: `find . -iname "*.sql"` não retorna nada), então cada task de backend já inclui o SQL completo a aplicar.

---

## Parte 1 — Backend (Supabase)

### Task 1: Colunas novas em `entregadores` + tabela `convites_entregador`

**Contexto:** `entregadores` precisa de `auth_user_id` (link com o login) e `fcm_token` (push). Convite de vínculo é uma tabela nova, separada de `convites_empresa` (que é escopada por `papel` genérico de staff, não por um entregador específico).

**Arquivos:** nenhum arquivo de repo — migration aplicada direto via MCP.

- [ ] **Step 1: Aplicar a migration**

```sql
alter table entregadores
  add column auth_user_id uuid unique,
  add column fcm_token text;

create table convites_entregador (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id),
  entregador_id uuid not null references entregadores(id),
  codigo varchar not null unique,
  criado_por uuid references usuarios(id),
  usado_em timestamptz,
  expira_em timestamptz not null default (now() + interval '7 days'),
  created_at timestamptz not null default now()
);

alter table convites_entregador enable row level security;

create policy convites_entregador_insert on convites_entregador
  for insert to authenticated
  with check (empresa_id = get_empresa_id() and get_papel() in ('dono', 'gerente'));

create policy convites_entregador_select on convites_entregador
  for select to authenticated
  using (empresa_id = get_empresa_id() and get_papel() in ('dono', 'gerente'));

create policy convites_entregador_update on convites_entregador
  for update to authenticated
  using (empresa_id = get_empresa_id() and get_papel() in ('dono', 'gerente'))
  with check (empresa_id = get_empresa_id() and get_papel() in ('dono', 'gerente'));
```

Use `mcp__claude_ai_Supabase__apply_migration` com `project_id: dwswpwxnzjgoohucngbb` e `name: add_entregador_auth_e_convites`.

- [ ] **Step 2: Verificar**

```sql
select column_name from information_schema.columns where table_name = 'entregadores' and column_name in ('auth_user_id', 'fcm_token');
select policyname from pg_policies where tablename = 'convites_entregador';
```

Esperado: 2 colunas + 3 policies retornadas.

- [ ] **Step 3: Commit**

Sem arquivo pra commitar (mudança só no banco) — anotar no changelog/PR a migration aplicada (nome `add_entregador_auth_e_convites`).

---

### Task 2: RLS de acesso do entregador em `rotas_entrega`, `rota_pedidos`, `pedidos`, `clientes`, `itens_pedido`

**Contexto:** essas 5 tabelas hoje só têm policy pra staff (via `get_empresa_id()`) ou pro cliente final (via `clientes.auth_user_id`). Sem policy nova, um entregador autenticado não enxerga nada — RLS nega tudo por padrão.

> **⚠️ Correção pós-execução (05/09, achada testando ao vivo):** o SQL abaixo, como escrito originalmente, causa recursão infinita (`42P17`) em duas tabelas — `clientes_entregador_select` faz `EXISTS` contra `pedidos`, que já tem `pedidos_cliente_le_proprio` referenciando `clientes` de volta; e `pedidos_entregador_select`/`update` fazem `EXISTS` contra `rota_pedidos`, que já tem `rota_pedidos_isolamento` referenciando `pedidos` de volta. Isso quebrou `clientes` E `pedidos` INTEIRAS pra todo mundo (não só pro entregador) até serem corrigidas pelas migrations `fix_recursao_rls_clientes_entregador` e `fix_recursao_rls_pedidos_entregador` (funções `entregador_pode_ver_cliente`/`entregador_pode_ver_pedido`, SECURITY DEFINER). **Se for reaplicar este SQL do zero em outro ambiente, já aplique a versão corrigida** (ver essas duas migrations, ou [[gestor_app_entregador_fase1]]), não o texto abaixo como está.

**Também faltou** uma policy de self-select em `entregadores` (`entregador_self_select`, ver migration `add_entregadores_self_select`) — sem ela, nem o próprio entregador conseguia reler o vínculo depois de `vincular_entregador_conta`, e as outras policies desta task (que fazem subquery em `entregadores`) ficavam silenciosamente sem efeito.

- [ ] **Step 1: Aplicar a migration**

```sql
-- rotas_entrega: entregador vê e atualiza (status, km_estimado etc.) só as próprias rotas.
create policy rotas_entrega_entregador_select on rotas_entrega
  for select to authenticated
  using (exists (
    select 1 from entregadores e
    where e.id = rotas_entrega.entregador_id and e.auth_user_id = auth.uid()
  ));

create policy rotas_entrega_entregador_update on rotas_entrega
  for update to authenticated
  using (exists (
    select 1 from entregadores e
    where e.id = rotas_entrega.entregador_id and e.auth_user_id = auth.uid()
  ))
  with check (exists (
    select 1 from entregadores e
    where e.id = rotas_entrega.entregador_id and e.auth_user_id = auth.uid()
  ));

-- rota_pedidos: só leitura (lista de paradas da rota) — reordenar é só do Gestor.
create policy rota_pedidos_entregador_select on rota_pedidos
  for select to authenticated
  using (exists (
    select 1 from rotas_entrega r
    join entregadores e on e.id = r.entregador_id
    where r.id = rota_pedidos.rota_id and e.auth_user_id = auth.uid()
  ));

-- pedidos: leitura + atualização de status/metadata, só pedidos que estão numa rota do entregador.
create policy pedidos_entregador_select on pedidos
  for select to authenticated
  using (exists (
    select 1 from rota_pedidos rp
    join rotas_entrega r on r.id = rp.rota_id
    join entregadores e on e.id = r.entregador_id
    where rp.pedido_id = pedidos.id and e.auth_user_id = auth.uid()
  ));

create policy pedidos_entregador_update on pedidos
  for update to authenticated
  using (exists (
    select 1 from rota_pedidos rp
    join rotas_entrega r on r.id = rp.rota_id
    join entregadores e on e.id = r.entregador_id
    where rp.pedido_id = pedidos.id and e.auth_user_id = auth.uid()
  ))
  with check (exists (
    select 1 from rota_pedidos rp
    join rotas_entrega r on r.id = rp.rota_id
    join entregadores e on e.id = r.entregador_id
    where rp.pedido_id = pedidos.id and e.auth_user_id = auth.uid()
  ));

-- clientes: só leitura, só clientes com pedido numa rota do entregador (nome/endereço/telefone da parada).
create policy clientes_entregador_select on clientes
  for select to authenticated
  using (exists (
    select 1 from pedidos p
    join rota_pedidos rp on rp.pedido_id = p.id
    join rotas_entrega r on r.id = rp.rota_id
    join entregadores e on e.id = r.entregador_id
    where p.cliente_id = clientes.id and e.auth_user_id = auth.uid()
  ));

-- itens_pedido: só leitura, pra mostrar os itens de cada parada.
create policy itens_pedido_entregador_select on itens_pedido
  for select to authenticated
  using (exists (
    select 1 from rota_pedidos rp
    join rotas_entrega r on r.id = rp.rota_id
    join entregadores e on e.id = r.entregador_id
    where rp.pedido_id = itens_pedido.pedido_id and e.auth_user_id = auth.uid()
  ));
```

Use `mcp__claude_ai_Supabase__apply_migration` com `name: add_rls_acesso_entregador`.

- [ ] **Step 2: Verificar**

```sql
select tablename, policyname from pg_policies
where policyname like '%entregador%'
order by tablename;
```

Esperado: 7 policies novas (2 em `rotas_entrega`, 1 em `rota_pedidos`, 2 em `pedidos`, 1 em `clientes`, 1 em `itens_pedido`), além das 3 de `convites_entregador` do Task 1.

- [ ] **Step 3: Commit**

Anotar no changelog a migration `add_rls_acesso_entregador`.

---

### Task 3: RPCs `vincular_entregador_conta` e `atualizar_fcm_token_entregador`

**Contexto:** `vincular_entregador_conta` troca um código de convite pelo vínculo `entregadores.auth_user_id = auth.uid()` (mesmo padrão de `entrar_empresa_com_convite`, adaptado). `atualizar_fcm_token_entregador` evita abrir uma policy genérica de UPDATE em `entregadores` pro próprio entregador (que deixaria ele editar `custo_modo`/`nome` também) — só esse campo, via RPC controlada.

- [ ] **Step 1: Aplicar a migration**

```sql
create or replace function public.vincular_entregador_conta(p_codigo varchar)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_convite record;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado';
  end if;

  if exists (select 1 from usuarios where id = auth.uid()) then
    raise exception 'Esta conta já é uma conta de funcionário da loja — use um login diferente pro app do entregador';
  end if;

  if exists (select 1 from entregadores where auth_user_id = auth.uid()) then
    raise exception 'Esta conta já está vinculada a um entregador';
  end if;

  select * into v_convite
  from convites_entregador
  where codigo = upper(trim(p_codigo))
    and usado_em is null
    and expira_em > now()
  for update;

  if v_convite.id is null then
    raise exception 'Código de convite inválido ou expirado';
  end if;

  update entregadores
  set auth_user_id = auth.uid()
  where id = v_convite.entregador_id and auth_user_id is null;

  if not found then
    raise exception 'Este entregador já está vinculado a outra conta';
  end if;

  update convites_entregador
  set usado_em = now()
  where id = v_convite.id;

  return v_convite.entregador_id;
end;
$$;

create or replace function public.atualizar_fcm_token_entregador(p_token text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  update entregadores set fcm_token = p_token where auth_user_id = auth.uid();
end;
$$;
```

Use `mcp__claude_ai_Supabase__apply_migration` com `name: add_rpc_vinculo_e_token_entregador`.

- [ ] **Step 2: Verificar**

```sql
select proname from pg_proc where proname in ('vincular_entregador_conta', 'atualizar_fcm_token_entregador');
```

Esperado: as 2 funções.

- [ ] **Step 3: Teste funcional (com um entregador de teste)**

No SQL editor (como staff, pra preparar o cenário):

```sql
-- ache um entregador ativo qualquer da sua empresa de teste
select id, nome, auth_user_id from entregadores where ativo = true limit 5;
```

Gere um convite via `UsuarioRepository`-like insert manual (ou espere o Task 5, que constrói a tela) — não bloqueia os próximos tasks de backend, só documente que esse fluxo será testado ponta a ponta depois que a tela de convite (Task 5) e a tela de vínculo no app novo (Task 8) existirem.

- [ ] **Step 4: Commit**

Anotar no changelog a migration `add_rpc_vinculo_e_token_entregador`.

---

### Task 4: `finalizar_rota_entrega` aceitar chamada do entregador + push de rota nova

**Contexto:** `finalizar_rota_entrega` (RPC já existente, ver definição abaixo) valida dono da rota com `v_rota.empresa_id is distinct from get_empresa_id()` — pra um entregador (sem linha em `usuarios`), `get_empresa_id()` é NULL, então a função sempre explode com "Rota não pertence à empresa". Precisa de uma segunda condição de posse via `entregadores.auth_user_id`. Também adiciona o trigger de push "rota nova atribuída" (item da spec, linha 56) — como notificação 1:1 (só o entregador daquela rota), não reaproveita o trigger genérico `notificar_push_notificacao` (que faz fan-out pra todos os `usuarios` da empresa) pra não arriscar mexer numa função compartilhada e sensível.

- [ ] **Step 1: Aplicar a migration**

```sql
create or replace function public.finalizar_rota_entrega(p_rota_id uuid, p_km_total numeric default null::numeric)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_rota record;
  v_entregador record;
  v_pedido record;
  v_total_pedidos_rota integer;
  v_total_pedidos_dia integer;
  v_custo_total numeric := 0;
  v_custo_por_pedido numeric;
  v_dias_no_mes integer;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado';
  end if;

  select * into v_rota from rotas_entrega where id = p_rota_id;
  if not found then
    raise exception 'Rota não encontrada';
  end if;

  if v_rota.empresa_id is distinct from get_empresa_id()
     and not exists (
       select 1 from entregadores e
       where e.id = v_rota.entregador_id and e.auth_user_id = auth.uid()
     ) then
    raise exception 'Rota não pertence à empresa do usuário autenticado';
  end if;

  select * into v_entregador from entregadores where id = v_rota.entregador_id;
  if not found or v_entregador.custo_modo is null then
    raise exception 'Entregador sem modo de custo configurado';
  end if;

  select count(*) into v_total_pedidos_rota from rota_pedidos where rota_id = p_rota_id;
  if v_total_pedidos_rota = 0 then
    raise exception 'Rota sem pedidos';
  end if;

  if v_entregador.custo_modo = 'fixo' then
    update pedidos p set custo_entrega_valor = v_entregador.custo_por_entrega
      from rota_pedidos rp where rp.pedido_id = p.id and rp.rota_id = p_rota_id;
    update rota_pedidos set custo_alocado = v_entregador.custo_por_entrega where rota_id = p_rota_id;

  elsif v_entregador.custo_modo = 'km' then
    for v_pedido in
      select p.id, (c.metadata->>'rangeDistancia')::numeric as distancia
      from rota_pedidos rp
      join pedidos p on p.id = rp.pedido_id
      join clientes c on c.id = p.cliente_id
      where rp.rota_id = p_rota_id
    loop
      update pedidos set custo_entrega_valor = coalesce(v_pedido.distancia,0) * v_entregador.custo_por_km where id = v_pedido.id;
      update rota_pedidos set custo_alocado = coalesce(v_pedido.distancia,0) * v_entregador.custo_por_km
        where rota_id = p_rota_id and pedido_id = v_pedido.id;
    end loop;

  elsif v_entregador.custo_modo = 'rota' then
    v_custo_total := coalesce(v_entregador.custo_por_km,0) * coalesce(p_km_total,0)
                    + coalesce(v_entregador.custo_por_parada_rota,0) * v_total_pedidos_rota;
    v_custo_por_pedido := v_custo_total / v_total_pedidos_rota;
    update pedidos p set custo_entrega_valor = v_custo_por_pedido
      from rota_pedidos rp where rp.pedido_id = p.id and rp.rota_id = p_rota_id;
    update rota_pedidos set custo_alocado = v_custo_por_pedido where rota_id = p_rota_id;

  elsif v_entregador.custo_modo in ('salario_mensal','salario_diaria') then
    select count(distinct rp.pedido_id) into v_total_pedidos_dia
    from rota_pedidos rp
    join rotas_entrega r on r.id = rp.rota_id
    where r.entregador_id = v_entregador.id and r.data_rota = v_rota.data_rota;

    if v_entregador.custo_modo = 'salario_diaria' then
      v_custo_por_pedido := coalesce(v_entregador.custo_salario_diaria,0) / greatest(v_total_pedidos_dia,1);
    else
      v_dias_no_mes := extract(day from (date_trunc('month', v_rota.data_rota) + interval '1 month - 1 day'))::integer;
      v_custo_por_pedido := (coalesce(v_entregador.custo_salario_mensal,0) / v_dias_no_mes) / greatest(v_total_pedidos_dia,1);
    end if;

    update pedidos p set custo_entrega_valor = v_custo_por_pedido
      from rota_pedidos rp
      join rotas_entrega r on r.id = rp.rota_id
      where rp.pedido_id = p.id and r.entregador_id = v_entregador.id and r.data_rota = v_rota.data_rota;
    update rota_pedidos rp set custo_alocado = v_custo_por_pedido
      from rotas_entrega r
      where rp.rota_id = r.id and r.entregador_id = v_entregador.id and r.data_rota = v_rota.data_rota;
  end if;

  update rotas_entrega set status = 'concluida', km_total = p_km_total, finalizada_em = now() where id = p_rota_id;
end;
$function$;

create or replace function public.notificar_nova_rota_entregador()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_token text;
begin
  select fcm_token into v_token from entregadores where id = new.entregador_id;

  if v_token is null then
    return new;
  end if;

  perform net.http_post(
    url := 'https://n8n.lukz.com.br/webhook/notificacao-push',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := jsonb_build_object(
      'notificacao_id', new.id,
      'empresa_id', new.empresa_id,
      'tipo', 'rota_atribuida',
      'titulo', 'Nova rota de entrega',
      'mensagem', 'Você tem uma nova rota pra hoje.',
      'tokens', to_jsonb(array[v_token])
    )
  );

  return new;
end;
$$;

create trigger trg_notificar_nova_rota_entregador
  after insert on rotas_entrega
  for each row execute function notificar_nova_rota_entregador();
```

Use `mcp__claude_ai_Supabase__apply_migration` com `name: finalizar_rota_aceita_entregador_e_push_nova_rota`.

- [ ] **Step 2: Verificar**

```sql
select pg_get_functiondef(oid) from pg_proc where proname = 'finalizar_rota_entrega';
select trigger_name from information_schema.triggers where event_object_table = 'rotas_entrega';
```

Esperado: a definição nova (com o `not exists (select 1 from entregadores ...)`) e o trigger `trg_notificar_nova_rota_entregador` listado.

- [ ] **Step 3: Commit**

Anotar no changelog a migration `finalizar_rota_aceita_entregador_e_push_nova_rota`.

---

## Parte 2 — Gestor (staff): gerar convite + tela de rotas vira leitura

### Task 5: Modelo/repositório de convite + botão "Gerar convite" em `entregadores_screen.dart`

**Files:**
- Create: `lib/models/convite_entregador.dart`
- Create: `lib/repositories/convite_entregador_repository.dart`
- Modify: `lib/screens/entregadores_screen.dart`

**Interfaces:**
- Produces: `ConviteEntregador.fromSupabase(Map)`, `ConviteEntregadorRepository.gerar({required String empresaId, required String entregadorId, required String criadoPor})` → `Future<ConviteEntregador>`.

- [ ] **Step 1: Criar o modelo**

`lib/models/convite_entregador.dart`:

```dart
class ConviteEntregador {
  final String id;
  final String codigo;
  final DateTime expiraEm;
  final DateTime? usadoEm;

  ConviteEntregador({
    required this.id,
    required this.codigo,
    required this.expiraEm,
    this.usadoEm,
  });

  factory ConviteEntregador.fromSupabase(Map<String, dynamic> row) {
    return ConviteEntregador(
      id: row['id'] as String,
      codigo: row['codigo'] as String,
      expiraEm: DateTime.parse(row['expira_em'].toString()),
      usadoEm: row['usado_em'] != null ? DateTime.tryParse(row['usado_em'].toString()) : null,
    );
  }
}
```

- [ ] **Step 2: Criar o repositório**

`lib/repositories/convite_entregador_repository.dart`:

```dart
import 'dart:math';

import '../config/supabase_config.dart';
import '../models/convite_entregador.dart';

/// Convite pra um entregador vincular a própria conta no app "Entregador"
/// (Fase 1 do app do entregador — ver docs/superpowers/specs/2026-09-04-app-entregador-fase1-design.md).
/// Mesmo padrão de `UsuarioRepository.gerarConvite`, mas escopado a um
/// `entregador_id` específico em vez de um `papel` genérico de staff.
class ConviteEntregadorRepository {
  static const _caracteresCodigo = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  Future<ConviteEntregador> gerar({
    required String empresaId,
    required String entregadorId,
    required String criadoPor,
  }) async {
    for (var tentativa = 0; tentativa < 5; tentativa++) {
      final codigo = _gerarCodigo();
      try {
        final row = await supabase
            .from('convites_entregador')
            .insert({
              'empresa_id': empresaId,
              'entregador_id': entregadorId,
              'codigo': codigo,
              'criado_por': criadoPor,
            })
            .select()
            .single();
        return ConviteEntregador.fromSupabase(row);
      } catch (e) {
        if (tentativa == 4) rethrow;
      }
    }
    throw StateError('Não foi possível gerar um código de convite único.');
  }

  String _gerarCodigo() {
    final random = Random.secure();
    return List.generate(8, (_) => _caracteresCodigo[random.nextInt(_caracteresCodigo.length)]).join();
  }
}
```

- [ ] **Step 3: Adicionar o botão "Gerar convite" na tela de entregadores**

Em `lib/screens/entregadores_screen.dart`, adicionar imports:

```dart
import '../providers/auth_provider.dart';
import '../repositories/convite_entregador_repository.dart';
```

Adicionar um método na `_EntregadoresScreenState`:

```dart
Future<void> _gerarConvite(Entregador entregador) async {
  if (entregador.id == null) return;
  final auth = context.read<AuthProvider>();
  final empresaId = auth.empresaId;
  final usuarioId = auth.usuarioAtual?.id;
  if (empresaId == null || usuarioId == null) return;

  try {
    final convite = await ConviteEntregadorRepository().gerar(
      empresaId: empresaId,
      entregadorId: entregador.id!,
      criadoPor: usuarioId,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Código de convite'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Passe esse código pra ${entregador.nome} digitar no app Entregador '
              '(válido até ${convite.expiraEm.day.toString().padLeft(2, '0')}/'
              '${convite.expiraEm.month.toString().padLeft(2, '0')}):',
            ),
            const SizedBox(height: 12),
            SelectableText(
              convite.codigo,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
        ],
      ),
    );
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao gerar convite: $e')));
    }
  }
}
```

No `trailing` do `ListTile` (dentro do `ListView.builder`), adicionar um terceiro `IconButton` antes do de editar:

```dart
IconButton(
  icon: const Icon(Icons.qr_code_2_outlined),
  tooltip: 'Gerar convite pro app Entregador',
  onPressed: () => _gerarConvite(entregador),
),
```

- [ ] **Step 4: Verificação manual**

Rodar o Gestor (`flutter run`), abrir Configurações > Entregadores, tocar no ícone de convite de um entregador ativo, confirmar que o diálogo mostra um código de 8 caracteres. Checar no Supabase (`select * from convites_entregador order by created_at desc limit 1`) que a linha foi criada com `empresa_id`/`entregador_id` certos.

- [ ] **Step 5: Commit**

```bash
git add lib/models/convite_entregador.dart lib/repositories/convite_entregador_repository.dart lib/screens/entregadores_screen.dart
git commit -m "$(cat <<'EOF'
Adiciona geração de convite pra entregador vincular conta no app novo

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EayLGjLR2qR9nEwtHazeiX
EOF
)"
```

---

### Task 6: `rotas_entrega_screen.dart` — status vira leitura + botão de override

**Contexto:** spec linha 60: "Iniciar rota"/"Finalizar rota" continuam existindo no Gestor só como **override manual de emergência** (ex: celular do entregador sem bateria) — o controle principal passa a ser do app novo. Não muda nenhuma lógica de banco (as mesmas RPCs/updates continuam existindo pro staff), só o texto/aviso na UI, pra não confundir quem usa o Gestor achando que ainda é o fluxo principal.

**Files:**
- Modify: `lib/screens/rotas_entrega_screen.dart:575-588` (bloco dos botões "Adicionar pedidos"/"Iniciar rota"/"Finalizar rota")

- [ ] **Step 1: Trocar os rótulos dos botões por versão "override"**

Substituir o trecho:

```dart
                              if (rota.planejada) ...[
                                TextButton(
                                  onPressed: () => _adicionarPedidos(rota),
                                  child: const Text('Adicionar pedidos'),
                                ),
                                ElevatedButton(
                                  onPressed: () => _iniciarRota(rota),
                                  child: const Text('Iniciar rota'),
                                ),
                              ] else if (rota.emAndamento)
                                ElevatedButton(
                                  onPressed: () => _finalizarRota(rota),
                                  child: const Text('Finalizar rota'),
                                ),
```

por:

```dart
                              if (rota.planejada) ...[
                                TextButton(
                                  onPressed: () => _adicionarPedidos(rota),
                                  child: const Text('Adicionar pedidos'),
                                ),
                                // Fluxo principal agora é o app Entregador
                                // (ver docs/superpowers/specs/2026-09-04-app-entregador-fase1-design.md)
                                // — isso aqui só existe pra destravar uma
                                // emergência (ex: celular do entregador sem
                                // bateria), por isso o rótulo avisa.
                                OutlinedButton(
                                  onPressed: () => _iniciarRota(rota),
                                  child: const Text('Iniciar rota (emergência)'),
                                ),
                              ] else if (rota.emAndamento)
                                OutlinedButton(
                                  onPressed: () => _finalizarRota(rota),
                                  child: const Text('Finalizar rota (emergência)'),
                                ),
```

- [ ] **Step 2: Verificação manual**

Rodar o Gestor, abrir Rotas de Entrega, confirmar que uma rota planejada mostra "Iniciar rota (emergência)" com estilo outlined (não mais preenchido) — visualmente secundário comparado ao antes.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/rotas_entrega_screen.dart
git commit -m "$(cat <<'EOF'
Marca Iniciar/Finalizar rota no Gestor como override de emergência

Controle principal do ciclo de rota passa a ser o app Entregador
(Fase 1) — os botões no Gestor continuam funcionando (mesma lógica),
só o rótulo/estilo deixam claro que é uma exceção, não o fluxo normal.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EayLGjLR2qR9nEwtHazeiX
EOF
)"
```

---

## Parte 3 — Novo app `entregador-app`

### Task 7: Scaffold do projeto

**Files:**
- Create: projeto Flutter em `C:\Users\lucas\StudioProjects\entregador-app`
- Create: `entregador-app/lib/config/supabase_config.dart`
- Create: `entregador-app/lib/main.dart` (placeholder mínimo, expandido no Task 8)

- [ ] **Step 1: Criar o projeto**

```bash
cd "C:\Users\lucas\StudioProjects"
flutter create --org br.com.deliverypet --project-name entregador entregador-app
```

- [ ] **Step 2: Ajustar `pubspec.yaml`**

Em `entregador-app/pubspec.yaml`, dentro de `dependencies:` (mantendo o que o `flutter create` já colocou: `flutter`, `cupertino_icons`):

```yaml
  provider: ^6.0.0
  supabase_flutter: ^2.8.0
  url_launcher: ^6.1.9
  http: ^1.6.0
  firebase_core: ^3.8.0
  firebase_messaging: ^15.1.0
  intl: ^0.19.0
```

- [ ] **Step 3: Instalar dependências**

```bash
cd "C:\Users\lucas\StudioProjects\entregador-app"
flutter pub get
```

- [ ] **Step 4: Criar `supabase_config.dart`**

`entregador-app/lib/config/supabase_config.dart` (idêntico ao do Gestor — mesmo projeto Supabase):

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mesmo backend do app Gestor (staff) — projeto Supabase único, RLS
/// separa o que cada tipo de usuário enxerga.
class SupabaseConfig {
  static const String url = 'https://dwswpwxnzjgoohucngbb.supabase.co';
  static const String anonKey =
      'sb_publishable_7ktXRTRJeD8cc5k1RDyEDg_1_HNzAdc';

  static Future<void> inicializar() async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
  }
}

final supabase = Supabase.instance.client;
```

- [ ] **Step 5: `main.dart` placeholder**

`entregador-app/lib/main.dart`:

```dart
import 'package:flutter/material.dart';

import 'config/supabase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.inicializar();
  runApp(const EntregadorApp());
}

class EntregadorApp extends StatelessWidget {
  const EntregadorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Entregador',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF2DA6E2), useMaterial3: true),
      home: const Scaffold(body: Center(child: Text('Entregador — em construção'))),
    );
  }
}
```

- [ ] **Step 6: Verificação**

```bash
cd "C:\Users\lucas\StudioProjects\entregador-app"
flutter analyze
flutter run -d <device_id>
```

Esperado: `flutter analyze` sem erros; app abre mostrando "Entregador — em construção".

- [ ] **Step 7: Commit**

```bash
cd "C:\Users\lucas\StudioProjects\entregador-app"
git init
git add -A
git commit -m "$(cat <<'EOF'
Scaffold inicial do app Entregador (Fase 1)

Projeto Flutter novo e separado do Gestor, mesma stack (Supabase +
Provider) — ver docs/superpowers/specs/2026-09-04-app-entregador-fase1-design.md
no repo gestor pro design completo.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EayLGjLR2qR9nEwtHazeiX
EOF
)"
```

---

### Task 8: Autenticação — login, vínculo por convite, e auth gate

**Files:**
- Create: `entregador-app/lib/providers/entregador_auth_provider.dart`
- Create: `entregador-app/lib/screens/login_screen.dart`
- Create: `entregador-app/lib/screens/vincular_conta_screen.dart`
- Create: `entregador-app/lib/screens/auth_gate.dart`
- Modify: `entregador-app/lib/main.dart`

**Interfaces:**
- Produces: `EntregadorAuthProvider` com `estaLogado`, `carregando`, `entregadorId`, `entregadorNome`, `precisaVincular` (getters), `entrar(email, senha)`, `cadastrar(email, senha)`, `vincular(codigo)`, `sair()`.

- [ ] **Step 1: Criar o provider de auth**

`entregador-app/lib/providers/entregador_auth_provider.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Autenticação do app Entregador — igual ao AuthProvider do Gestor na
/// mecânica (Supabase Auth + tabela própria pra saber se já tem vínculo),
/// mas aponta pra `entregadores.auth_user_id` em vez de `usuarios.empresa_id`
/// (decisão de design: NÃO cria linha em `usuarios` pra entregador — ver
/// docs/superpowers/specs/2026-09-04-app-entregador-fase1-design.md linha 26-32).
class EntregadorAuthProvider with ChangeNotifier {
  String? _entregadorId;
  String? _entregadorNome;
  bool _carregando = true;
  String? _erro;

  User? get usuarioAtual => supabase.auth.currentUser;
  bool get estaLogado => usuarioAtual != null;
  String? get entregadorId => _entregadorId;
  String? get entregadorNome => _entregadorNome;
  bool get carregando => _carregando;
  String? get erro => _erro;

  /// true quando logado mas ainda não digitou o código de convite.
  bool get precisaVincular => estaLogado && _entregadorId == null && !_carregando;

  EntregadorAuthProvider() {
    supabase.auth.onAuthStateChange.listen((_) => _verificarVinculo());
    _verificarVinculo();
  }

  Future<void> _verificarVinculo() async {
    _carregando = true;
    notifyListeners();

    if (!estaLogado) {
      _entregadorId = null;
      _entregadorNome = null;
      _carregando = false;
      notifyListeners();
      return;
    }

    try {
      final data = await supabase
          .from('entregadores')
          .select('id, nome')
          .eq('auth_user_id', usuarioAtual!.id)
          .maybeSingle();

      _entregadorId = data?['id'] as String?;
      _entregadorNome = data?['nome'] as String?;
    } catch (e) {
      debugPrint('Erro ao verificar vínculo entregador: $e');
      _entregadorId = null;
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<bool> entrar(String email, String senha) async {
    _erro = null;
    try {
      await supabase.auth.signInWithPassword(email: email, password: senha);
      return true;
    } on AuthException catch (e) {
      _erro = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> cadastrar(String email, String senha) async {
    _erro = null;
    try {
      await supabase.auth.signUp(email: email, password: senha);
      return true;
    } on AuthException catch (e) {
      _erro = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> vincular(String codigo) async {
    _erro = null;
    try {
      await supabase.rpc('vincular_entregador_conta', params: {'p_codigo': codigo});
      await _verificarVinculo();
      return true;
    } on PostgrestException catch (e) {
      _erro = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<void> sair() async {
    await supabase.auth.signOut();
  }
}
```

- [ ] **Step 2: Tela de login**

`entregador-app/lib/screens/login_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/entregador_auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  bool _modoCadastro = false;
  bool _carregando = false;

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _carregando = true);
    final auth = context.read<EntregadorAuthProvider>();

    final sucesso = _modoCadastro
        ? await auth.cadastrar(_emailController.text.trim(), _senhaController.text)
        : await auth.entrar(_emailController.text.trim(), _senhaController.text);

    setState(() => _carregando = false);

    if (!sucesso && mounted && auth.erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(auth.erro!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _modoCadastro ? 'Criar conta' : 'Entregador',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'E-mail'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe seu e-mail' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _senhaController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Senha'),
                    validator: (v) => (v == null || v.isEmpty) ? 'Informe sua senha' : null,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _carregando ? null : _enviar,
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                    child: _carregando
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_modoCadastro ? 'Criar conta' : 'Entrar'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => setState(() => _modoCadastro = !_modoCadastro),
                    child: Text(_modoCadastro ? 'Já tenho conta — entrar' : 'Primeira vez — criar conta'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Tela de vínculo por código**

`entregador-app/lib/screens/vincular_conta_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/entregador_auth_provider.dart';

/// Depois do login/cadastro, entra aqui — sem o código de convite gerado
/// pela loja (Configurações > Entregadores > ícone de convite, no Gestor),
/// a conta fica sem acesso a nenhuma rota.
class VincularContaScreen extends StatefulWidget {
  const VincularContaScreen({super.key});

  @override
  State<VincularContaScreen> createState() => _VincularContaScreenState();
}

class _VincularContaScreenState extends State<VincularContaScreen> {
  final _codigoController = TextEditingController();
  bool _carregando = false;

  @override
  void dispose() {
    _codigoController.dispose();
    super.dispose();
  }

  Future<void> _vincular() async {
    final codigo = _codigoController.text.trim();
    if (codigo.isEmpty) return;

    setState(() => _carregando = true);
    final auth = context.read<EntregadorAuthProvider>();
    final sucesso = await auth.vincular(codigo);
    setState(() => _carregando = false);

    if (!sucesso && mounted && auth.erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(auth.erro!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vincular conta'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<EntregadorAuthProvider>().sair(),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Peça pra loja te passar o código de convite gerado pra você.'),
              const SizedBox(height: 20),
              TextField(
                controller: _codigoController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Código de convite'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _carregando ? null : _vincular,
                child: _carregando
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Vincular'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Auth gate**

`entregador-app/lib/screens/auth_gate.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/entregador_auth_provider.dart';
import 'login_screen.dart';
import 'vincular_conta_screen.dart';
import 'minhas_rotas_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<EntregadorAuthProvider>();

    if (auth.carregando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!auth.estaLogado) {
      return const LoginScreen();
    }
    if (auth.precisaVincular) {
      return const VincularContaScreen();
    }
    return const MinhasRotasScreen();
  }
}
```

(`MinhasRotasScreen` é criada no Task 11 — esse import fica "vermelho" até lá; normal num plano de múltiplos tasks, o Step 6 deste task já avisa disso.)

- [ ] **Step 5: Atualizar `main.dart`**

`entregador-app/lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/supabase_config.dart';
import 'providers/entregador_auth_provider.dart';
import 'screens/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.inicializar();
  runApp(const EntregadorApp());
}

class EntregadorApp extends StatelessWidget {
  const EntregadorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => EntregadorAuthProvider()),
      ],
      child: MaterialApp(
        title: 'Entregador',
        theme: ThemeData(colorSchemeSeed: const Color(0xFF2DA6E2), useMaterial3: true),
        home: const AuthGate(),
      ),
    );
  }
}
```

- [ ] **Step 6: Verificação**

Não rodar `flutter analyze`/`flutter run` ainda neste task — `minhas_rotas_screen.dart` só existe a partir do Task 11, então o projeto não compila até lá. Confirmar isso é esperado; a verificação de compilação completa acontece no Step 6 do Task 11.

- [ ] **Step 7: Commit**

```bash
cd "C:\Users\lucas\StudioProjects\entregador-app"
git add lib/providers/entregador_auth_provider.dart lib/screens/login_screen.dart lib/screens/vincular_conta_screen.dart lib/screens/auth_gate.dart lib/main.dart
git commit -m "$(cat <<'EOF'
Adiciona login e vínculo de conta por código de convite

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EayLGjLR2qR9nEwtHazeiX
EOF
)"
```

---

### Task 9: Modelos + repositório de rotas/paradas (com dados de cliente/itens)

**Files:**
- Create: `entregador-app/lib/models/parada.dart`
- Create: `entregador-app/lib/models/rota_entrega.dart`
- Create: `entregador-app/lib/repositories/rota_entrega_repository.dart`

**Interfaces:**
- Produces: `RotaEntrega` (id, dataRota, status, kmEstimado, kmVoltaEstimado, polylineEstimada, planejada/emAndamento/concluida getters — igual ao do Gestor), `Parada` (pedidoId, ordem, clienteNome, endereco, telefone, latitude, longitude, itensResumo, formaPagamento, statusPagamento, canalVenda, status, custoAlocado), `RotaEntregaRepository.minhasRotasDeHoje()`, `.paradasDaRota(rotaId)`, `.iniciar(rotaId)`, `.atualizarKmEstimado(...)`, `.marcarEntregue(pedidoId)`, `.marcarNaoEntregue(pedidoId, motivo)`, `.finalizar(rotaId, {kmTotal})`.

- [ ] **Step 1: Modelo `RotaEntrega`**

`entregador-app/lib/models/rota_entrega.dart` (idêntico ao `StatusRota`/`RotaEntrega` do Gestor, sem os campos de `entregadorNome`/`entregadorCustoModo` que aqui não fazem sentido — é sempre "a minha rota"):

```dart
class StatusRota {
  static const planejada = 'planejada';
  static const emAndamento = 'em_andamento';
  static const concluida = 'concluida';
}

class RotaEntrega {
  final String id;
  final DateTime dataRota;
  final String status;
  final double? kmTotal;
  final double? kmEstimado;
  final double? kmVoltaEstimado;
  final String? polylineEstimada;
  final DateTime? finalizadaEm;

  RotaEntrega({
    required this.id,
    required this.dataRota,
    required this.status,
    this.kmTotal,
    this.kmEstimado,
    this.kmVoltaEstimado,
    this.polylineEstimada,
    this.finalizadaEm,
  });

  bool get planejada => status == StatusRota.planejada;
  bool get emAndamento => status == StatusRota.emAndamento;
  bool get concluida => status == StatusRota.concluida;

  factory RotaEntrega.fromSupabase(Map<String, dynamic> row) {
    return RotaEntrega(
      id: row['id'] as String,
      dataRota: DateTime.parse(row['data_rota'].toString()),
      status: row['status']?.toString() ?? StatusRota.planejada,
      kmTotal: (row['km_total'] as num?)?.toDouble(),
      kmEstimado: (row['km_estimado'] as num?)?.toDouble(),
      kmVoltaEstimado: (row['km_volta_estimado'] as num?)?.toDouble(),
      polylineEstimada: row['polyline_estimada']?.toString(),
      finalizadaEm: row['finalizada_em'] != null ? DateTime.tryParse(row['finalizada_em'].toString()) : null,
    );
  }
}
```

- [ ] **Step 2: Modelo `Parada`**

`entregador-app/lib/models/parada.dart`:

```dart
class StatusParada {
  static const pendente = 'pendente';
  static const preparando = 'preparando';
  static const saiuParaEntrega = 'saiu_para_entrega';
  static const entregue = 'entregue';
  static const naoEntregue = 'nao_entregue';
  static const cancelado = 'cancelado';
}

/// Uma parada da rota = um pedido, já com os dados de exibição resolvidos
/// (cliente + itens) via join no `RotaEntregaRepository.paradasDaRota` —
/// diferente do Gestor, esse app não tem um provider de histórico de vendas
/// já carregado com tudo, então busca só o necessário direto.
class Parada {
  final String pedidoId;
  final int ordem;
  final String status;
  final String clienteNome;
  final String? clienteTelefone;
  final String enderecoCompleto;
  final double? latitude;
  final double? longitude;
  final List<String> itensResumo;
  final String? tipoPagamento;
  final String? statusPagamento;
  final String canalVenda;
  final double valorTotal;
  final double? custoAlocado;

  Parada({
    required this.pedidoId,
    required this.ordem,
    required this.status,
    required this.clienteNome,
    this.clienteTelefone,
    required this.enderecoCompleto,
    this.latitude,
    this.longitude,
    required this.itensResumo,
    this.tipoPagamento,
    this.statusPagamento,
    required this.canalVenda,
    required this.valorTotal,
    this.custoAlocado,
  });

  bool get pagamentoPendente => statusPagamento == 'pendente';

  String get destinoParaMapa =>
      (latitude != null && longitude != null) ? '$latitude,$longitude' : enderecoCompleto;
}
```

- [ ] **Step 3: Repositório**

`entregador-app/lib/repositories/rota_entrega_repository.dart`:

```dart
import '../config/supabase_config.dart';
import '../models/parada.dart';
import '../models/rota_entrega.dart';

/// Acesso a dados de rotas/paradas pro app Entregador. RLS (`rotas_entrega_
/// entregador_select`, `rota_pedidos_entregador_select`, `pedidos_entregador_
/// select`, `clientes_entregador_select`, `itens_pedido_entregador_select` —
/// ver migration `add_rls_acesso_entregador`) já restringe tudo à(s) rota(s)
/// do entregador logado, então as queries aqui não precisam filtrar por
/// entregador_id explicitamente.
class RotaEntregaRepository {
  Future<List<RotaEntrega>> minhasRotasDeHoje() async {
    final hoje = DateTime.now().toIso8601String().split('T').first;
    final rows = await supabase
        .from('rotas_entrega')
        .select()
        .eq('data_rota', hoje)
        .order('created_at', ascending: true);
    return (rows as List).map((r) => RotaEntrega.fromSupabase(r as Map<String, dynamic>)).toList();
  }

  Future<List<Parada>> paradasDaRota(String rotaId) async {
    final rows = await supabase
        .from('rota_pedidos')
        .select('''
          ordem, custo_alocado,
          pedido:pedidos(
            id, status, tipo_pagamento, status_pagamento, canal_venda, valor_total,
            cliente:clientes(nome, telefone, endereco, numero, bairro, cidade, estado, cep, latitude, longitude),
            itens:itens_pedido(quantidade, produto:produtos(nome))
          )
        ''')
        .eq('rota_id', rotaId)
        .order('ordem', ascending: true);

    return (rows as List).map((r) {
      final row = r as Map<String, dynamic>;
      final pedido = row['pedido'] as Map<String, dynamic>;
      final cliente = pedido['cliente'] as Map<String, dynamic>?;
      final itens = (pedido['itens'] as List?) ?? [];

      final partesEndereco = <String>[];
      if (cliente != null) {
        final endereco = cliente['endereco']?.toString() ?? '';
        final numero = cliente['numero']?.toString() ?? '';
        if (endereco.isNotEmpty) partesEndereco.add(numero.isNotEmpty ? '$endereco, $numero' : endereco);
        final bairro = cliente['bairro']?.toString() ?? '';
        if (bairro.isNotEmpty) partesEndereco.add(bairro);
        final cidade = cliente['cidade']?.toString() ?? '';
        final estado = cliente['estado']?.toString() ?? '';
        if (cidade.isNotEmpty) partesEndereco.add(estado.isNotEmpty ? '$cidade - $estado' : cidade);
      }

      return Parada(
        pedidoId: pedido['id'] as String,
        ordem: (row['ordem'] as num?)?.toInt() ?? 0,
        status: pedido['status']?.toString() ?? StatusParada.pendente,
        clienteNome: cliente?['nome']?.toString() ?? '?',
        clienteTelefone: cliente?['telefone']?.toString(),
        enderecoCompleto: partesEndereco.join(', '),
        latitude: (cliente?['latitude'] as num?)?.toDouble(),
        longitude: (cliente?['longitude'] as num?)?.toDouble(),
        itensResumo: itens.map((i) {
          final item = i as Map<String, dynamic>;
          final produto = item['produto'] as Map<String, dynamic>?;
          final qtd = (item['quantidade'] as num?)?.toInt() ?? 0;
          return '${qtd}x ${produto?['nome'] ?? '?'}';
        }).toList(),
        tipoPagamento: pedido['tipo_pagamento']?.toString(),
        statusPagamento: pedido['status_pagamento']?.toString(),
        canalVenda: pedido['canal_venda']?.toString() ?? '',
        valorTotal: (pedido['valor_total'] as num?)?.toDouble() ?? 0,
        custoAlocado: (row['custo_alocado'] as num?)?.toDouble(),
      );
    }).toList();
  }

  Future<void> iniciar(String rotaId) async {
    await supabase.from('rotas_entrega').update({'status': StatusRota.emAndamento}).eq('id', rotaId);
  }

  Future<void> atualizarKmEstimado(
    String rotaId, {
    required double kmEstimado,
    double? kmVoltaEstimado,
    String? polylineEstimada,
  }) async {
    await supabase.from('rotas_entrega').update({
      'km_estimado': kmEstimado,
      'km_volta_estimado': kmVoltaEstimado,
      'polyline_estimada': polylineEstimada,
    }).eq('id', rotaId);
  }

  /// Trigger `confirmar_pagamento_entrega_loja_fisica` cuida sozinha de virar
  /// `status_pagamento` pra 'pago' quando `canal_venda = 'loja_fisica'` — não
  /// existe RPC pra chamar aqui, só o update de status mesmo.
  Future<void> marcarEntregue(String pedidoId) async {
    await supabase.from('pedidos').update({'status': StatusParada.entregue}).eq('id', pedidoId);
  }

  Future<void> marcarNaoEntregue(String pedidoId, String motivo) async {
    final atual = await supabase.from('pedidos').select('metadata').eq('id', pedidoId).single();
    final metadata = Map<String, dynamic>.from(atual['metadata'] as Map? ?? {});
    metadata['motivo_nao_entrega'] = motivo;

    await supabase
        .from('pedidos')
        .update({'status': StatusParada.naoEntregue, 'metadata': metadata}).eq('id', pedidoId);
  }

  Future<void> finalizar(String rotaId, {double? kmTotal}) async {
    await supabase.rpc('finalizar_rota_entrega', params: {'p_rota_id': rotaId, 'p_km_total': kmTotal});
  }
}
```

- [ ] **Step 2: Verificação manual (com dados reais)**

No SQL editor, como o entregador de teste já vinculado (ou simulando via `set local role`), confirmar que:

```sql
-- como staff: monte uma rota planejada com 1 pedido pro entregador de teste
select id from rotas_entrega where entregador_id = '<id_do_entregador_de_teste>' order by created_at desc limit 1;
```

E depois, já dentro do app (Task 11/12), confirmar visualmente que `paradasDaRota` traz nome/endereço/itens certos.

- [ ] **Step 3: Commit**

```bash
cd "C:\Users\lucas\StudioProjects\entregador-app"
git add lib/models/rota_entrega.dart lib/models/parada.dart lib/repositories/rota_entrega_repository.dart
git commit -m "$(cat <<'EOF'
Adiciona modelos e repositório de rotas/paradas

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EayLGjLR2qR9nEwtHazeiX
EOF
)"
```

---

### Task 10: `DistanciaService` duplicado + helper de navegação externa

**Contexto:** decisão já confirmada no spec (linha 40): duplicar `distancia_service.dart` em vez de extrair pacote compartilhado. Cópia idêntica ao arquivo do Gestor, exceto o stub condicional de web (esse app não roda em web — Fase 1 é só Android — então a versão aqui pode ser só a implementação mobile, sem o `if (dart.library.html)`).

**Files:**
- Create: `entregador-app/lib/services/distancia_service.dart`
- Create: `entregador-app/lib/services/navegacao_service.dart`

- [ ] **Step 1: Copiar `DistanciaService`**

Copiar o conteúdo de `C:\Users\lucas\StudioProjects\gestor\lib\services\distancia_service.dart` pra `entregador-app/lib/services/distancia_service.dart`, com 2 ajustes:
1. Remover o import `'web/distancia_maps_stub.dart' if (dart.library.html) 'web/distancia_maps_web.dart' as maps_web;` e todos os blocos `if (kIsWeb) { return maps_web...; }` dentro de cada método (esse app não roda em navegador).
2. Trocar o import `'../config/supabase_config.dart'` (mesmo caminho relativo, já existe no projeto novo — Task 7).

Resultado (versão sem o galho web, só os métodos usados por este app — `buscarEnderecoEmpresa` não é necessário aqui já que a rota já vem montada pelo Gestor, mas mantenha ele também por paridade/futuro reuso):

```dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/supabase_config.dart';

class RotaCalculada {
  final double distanciaKm;
  final int duracaoMin;

  RotaCalculada({required this.distanciaKm, required this.duracaoMin});
}

class RotaOtimizadaCalculada {
  final List<int>? ordemOtimizada;
  final double distanciaCobravelKm;
  final double distanciaVoltaKm;
  final int duracaoTotalMin;
  final String? polylineCodificada;

  RotaOtimizadaCalculada({
    this.ordemOtimizada,
    required this.distanciaCobravelKm,
    required this.distanciaVoltaKm,
    required this.duracaoTotalMin,
    this.polylineCodificada,
  });

  double get distanciaTotalComVoltaKm => distanciaCobravelKm + distanciaVoltaKm;
}

/// Cálculo de distância/rota real (Google Distance Matrix/Directions API) —
/// cópia de `gestor/lib/services/distancia_service.dart` (decisão confirmada
/// no spec: duplicar em vez de extrair pacote compartilhado, ver
/// docs/superpowers/specs/2026-09-04-app-entregador-fase1-design.md linha 40).
/// Sem o galho de Web do original — este app só roda Android na Fase 1.
class DistanciaService {
  DistanciaService._();

  static const _apiKey = 'AIzaSyDKmbywF7XdgUI3LWJ0-c83-tSaEl5EqPU';

  static Future<String?> buscarEnderecoEmpresa(String empresaId) async {
    try {
      final data = await supabase
          .from('empresas')
          .select('endereco, cidade, estado, cep')
          .eq('id', empresaId)
          .single();

      return _montarEndereco(
        endereco: data['endereco']?.toString() ?? '',
        cidade: data['cidade']?.toString() ?? '',
        estado: data['estado']?.toString() ?? '',
        cep: data['cep']?.toString() ?? '',
      );
    } catch (e) {
      debugPrint('Erro ao buscar endereço da empresa: $e');
      return null;
    }
  }

  static String? _montarEndereco({
    required String endereco,
    String numero = '',
    String bairro = '',
    required String cidade,
    required String estado,
    required String cep,
  }) {
    final partes = <String>[];
    if (endereco.isNotEmpty) {
      partes.add(numero.isNotEmpty ? '$endereco, $numero' : endereco);
    }
    if (bairro.isNotEmpty) partes.add(bairro);
    if (cidade.isNotEmpty) partes.add(estado.isNotEmpty ? '$cidade - $estado' : cidade);
    if (cep.isNotEmpty) partes.add(cep);

    return partes.isEmpty ? null : partes.join(', ');
  }

  static Future<RotaOtimizadaCalculada?> calcularRotaOtimizada({
    required String origem,
    required List<String> destinos,
  }) async {
    if (origem.trim().isEmpty || destinos.length < 2 || destinos.length > 8) return null;

    final matriz = await _buscarMatrizDistancias([origem, ...destinos]);
    if (matriz == null) return null;

    final ordem = _melhorOrdemPorDistancia(matriz, destinos.length);
    if (ordem == null) return null;

    final destinosNaOrdem = ordem.map((i) => destinos[i]).toList();
    final rotaFixa = await calcularRotaOrdemFixa(origem: origem, destinosNaOrdem: destinosNaOrdem);
    if (rotaFixa == null) return null;

    return RotaOtimizadaCalculada(
      ordemOtimizada: ordem,
      distanciaCobravelKm: rotaFixa.distanciaCobravelKm,
      distanciaVoltaKm: rotaFixa.distanciaVoltaKm,
      duracaoTotalMin: rotaFixa.duracaoTotalMin,
      polylineCodificada: rotaFixa.polylineCodificada,
    );
  }

  static Future<RotaOtimizadaCalculada?> calcularRotaOrdemFixa({
    required String origem,
    required List<String> destinosNaOrdem,
  }) async {
    if (origem.trim().isEmpty || destinosNaOrdem.isEmpty) return null;

    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
        'origin': origem,
        'destination': origem,
        if (destinosNaOrdem.length > 1) 'waypoints': destinosNaOrdem.join('|'),
        'mode': 'driving',
        'units': 'metric',
        'key': _apiKey,
      });

      final resposta = await http.get(uri).timeout(const Duration(seconds: 15));
      final json = jsonDecode(resposta.body) as Map<String, dynamic>;

      if (json['status'] != 'OK') return null;

      final rotas = json['routes'] as List;
      if (rotas.isEmpty) return null;
      final rota = rotas.first as Map<String, dynamic>;

      final legs = rota['legs'] as List;
      if (legs.isEmpty) return null;

      var duracaoTotalS = 0;
      var distanciaCobravelM = 0.0;
      for (var i = 0; i < legs.length - 1; i++) {
        final leg = legs[i] as Map<String, dynamic>;
        distanciaCobravelM += (leg['distance']['value'] as num).toDouble();
        duracaoTotalS += (leg['duration']['value'] as num).toInt();
      }
      final ultimaLeg = legs.last as Map<String, dynamic>;
      final distanciaVoltaM = (ultimaLeg['distance']['value'] as num).toDouble();
      duracaoTotalS += (ultimaLeg['duration']['value'] as num).toInt();

      final polyline = (rota['overview_polyline'] as Map<String, dynamic>?)?['points'] as String?;

      return RotaOtimizadaCalculada(
        distanciaCobravelKm: distanciaCobravelM / 1000,
        distanciaVoltaKm: distanciaVoltaM / 1000,
        duracaoTotalMin: (duracaoTotalS / 60).round(),
        polylineCodificada: polyline,
      );
    } catch (e) {
      debugPrint('Erro ao calcular rota de ordem fixa: $e');
      return null;
    }
  }

  static Future<List<List<double>>?> _buscarMatrizDistancias(List<String> pontos) async {
    try {
      final pontosStr = pontos.join('|');
      final uri = Uri.https('maps.googleapis.com', '/maps/api/distancematrix/json', {
        'origins': pontosStr,
        'destinations': pontosStr,
        'mode': 'driving',
        'units': 'metric',
        'key': _apiKey,
      });

      final resposta = await http.get(uri).timeout(const Duration(seconds: 15));
      final json = jsonDecode(resposta.body) as Map<String, dynamic>;

      if (json['status'] != 'OK') return null;

      final linhas = json['rows'] as List;
      final matriz = <List<double>>[];
      for (final linhaRaw in linhas) {
        final elementos = (linhaRaw as Map<String, dynamic>)['elements'] as List;
        final linha = <double>[];
        for (final elRaw in elementos) {
          final el = elRaw as Map<String, dynamic>;
          if (el['status'] != 'OK') return null;
          linha.add((el['distance']['value'] as num).toDouble() / 1000);
        }
        matriz.add(linha);
      }
      return matriz;
    } catch (e) {
      debugPrint('Erro ao buscar matriz de distâncias: $e');
      return null;
    }
  }

  static List<int>? _melhorOrdemPorDistancia(List<List<double>> matriz, int n) {
    List<int>? melhorOrdem;
    var melhorDistancia = double.infinity;

    void tentar(List<int> ordem) {
      var distancia = matriz[0][ordem.first + 1];
      for (var i = 0; i < ordem.length - 1; i++) {
        distancia += matriz[ordem[i] + 1][ordem[i + 1] + 1];
      }
      distancia += matriz[ordem.last + 1][0];
      if (distancia < melhorDistancia) {
        melhorDistancia = distancia;
        melhorOrdem = List.of(ordem);
      }
    }

    void permutar(List<int> restantes, List<int> atual) {
      if (restantes.isEmpty) {
        tentar(atual);
        return;
      }
      for (var i = 0; i < restantes.length; i++) {
        final proximo = restantes[i];
        final novoRestante = [...restantes.sublist(0, i), ...restantes.sublist(i + 1)];
        permutar(novoRestante, [...atual, proximo]);
      }
    }

    permutar(List.generate(n, (i) => i), []);
    return melhorOrdem;
  }
}
```

- [ ] **Step 2: Helper de navegação externa**

`entregador-app/lib/services/navegacao_service.dart`:

```dart
import 'package:url_launcher/url_launcher.dart';

/// Deep link externo pro Google Maps (spec linha 49) — sem navegação
/// turn-by-turn embutida no app, só abre o app de mapas do celular já
/// apontado pro destino.
class NavegacaoService {
  NavegacaoService._();

  static Future<bool> abrirNoGoogleMaps(String destino) async {
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': destino,
      'travelmode': 'driving',
    });
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
```

- [ ] **Step 3: Verificação**

```bash
cd "C:\Users\lucas\StudioProjects\entregador-app"
flutter analyze
```

Esperado: sem erros (ainda dá warning de import não usado em `auth_gate.dart` até o Task 11 — ok, não é regressão deste task).

- [ ] **Step 4: Commit**

```bash
cd "C:\Users\lucas\StudioProjects\entregador-app"
git add lib/services/distancia_service.dart lib/services/navegacao_service.dart
git commit -m "$(cat <<'EOF'
Adiciona cálculo de rota (duplicado do Gestor) e deep link de navegação

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EayLGjLR2qR9nEwtHazeiX
EOF
)"
```

---

### Task 11: Tela "Minhas rotas de hoje"

**Files:**
- Create: `entregador-app/lib/screens/minhas_rotas_screen.dart`

**Interfaces:**
- Consumes: `RotaEntregaRepository.minhasRotasDeHoje()`, `EntregadorAuthProvider.entregadorNome`/`sair()`.
- Produces: navega pra `RotaDetalheScreen` (Task 12) passando um `RotaEntrega`.

- [ ] **Step 1: Criar a tela**

`entregador-app/lib/screens/minhas_rotas_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/rota_entrega.dart';
import '../providers/entregador_auth_provider.dart';
import '../repositories/rota_entrega_repository.dart';
import 'rota_detalhe_screen.dart';

class MinhasRotasScreen extends StatefulWidget {
  const MinhasRotasScreen({super.key});

  @override
  State<MinhasRotasScreen> createState() => _MinhasRotasScreenState();
}

class _MinhasRotasScreenState extends State<MinhasRotasScreen> {
  final _repository = RotaEntregaRepository();
  List<RotaEntrega> _rotas = [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final rotas = await _repository.minhasRotasDeHoje();
      if (!mounted) return;
      setState(() => _rotas = rotas);
    } catch (e) {
      if (mounted) setState(() => _erro = 'Erro ao carregar rotas: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  String _rotuloStatus(String status) {
    switch (status) {
      case StatusRota.planejada:
        return 'Aguardando início';
      case StatusRota.emAndamento:
        return 'Em andamento';
      case StatusRota.concluida:
        return 'Concluída';
      default:
        return status;
    }
  }

  Color _corStatus(String status) {
    switch (status) {
      case StatusRota.planejada:
        return Colors.orange;
      case StatusRota.emAndamento:
        return Colors.blue;
      case StatusRota.concluida:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final nome = context.watch<EntregadorAuthProvider>().entregadorNome ?? '';
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar: AppBar(
        title: Text('Olá, $nome'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<EntregadorAuthProvider>().sair(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
                ? Center(child: Text(_erro!))
                : _rotas.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 120),
                          Center(child: Text('Nenhuma rota pra hoje ainda.')),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _rotas.length,
                        itemBuilder: (context, index) {
                          final rota = _rotas[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              title: Text(dateFormat.format(rota.dataRota)),
                              subtitle: Text(_rotuloStatus(rota.status)),
                              leading: CircleAvatar(
                                backgroundColor: _corStatus(rota.status).withValues(alpha: 0.15),
                                child: Icon(Icons.route, color: _corStatus(rota.status)),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => RotaDetalheScreen(rota: rota)),
                                );
                                if (mounted) _carregar();
                              },
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verificação**

```bash
cd "C:\Users\lucas\StudioProjects\entregador-app"
flutter analyze
```

Ainda vai reclamar de `rota_detalhe_screen.dart` não existir — normal, é criado no próximo task. Depois do Task 12, `flutter analyze` deve ficar limpo e o app compilar.

- [ ] **Step 3: Commit**

```bash
cd "C:\Users\lucas\StudioProjects\entregador-app"
git add lib/screens/minhas_rotas_screen.dart
git commit -m "$(cat <<'EOF'
Adiciona tela "Minhas rotas de hoje"

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EayLGjLR2qR9nEwtHazeiX
EOF
)"
```

---

### Task 12: Tela de detalhe da rota — iniciar, paradas, finalizar

**Files:**
- Create: `entregador-app/lib/screens/rota_detalhe_screen.dart`

**Interfaces:**
- Consumes: `RotaEntregaRepository` (Task 9), `DistanciaService` (Task 10), `NavegacaoService` (Task 10).

Esse é o coração do app — junta tudo: listar paradas, iniciar rota (com otimização), navegar, marcar entregue (com aviso de pagamento pendente), marcar não entregue (com motivo), finalizar rota.

- [ ] **Step 1: Criar a tela**

`entregador-app/lib/screens/rota_detalhe_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../models/parada.dart';
import '../models/rota_entrega.dart';
import '../repositories/rota_entrega_repository.dart';
import '../services/distancia_service.dart';
import '../services/navegacao_service.dart';

class RotaDetalheScreen extends StatefulWidget {
  final RotaEntrega rota;

  const RotaDetalheScreen({super.key, required this.rota});

  @override
  State<RotaDetalheScreen> createState() => _RotaDetalheScreenState();
}

class _RotaDetalheScreenState extends State<RotaDetalheScreen> {
  final _repository = RotaEntregaRepository();
  late RotaEntrega _rota;
  List<Parada> _paradas = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _rota = widget.rota;
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final paradas = await _repository.paradasDaRota(_rota.id);
      if (mounted) setState(() => _paradas = paradas);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar paradas: $e')));
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _iniciarRota() async {
    if (_paradas.isEmpty) return;

    final mostrarLoading = _paradas.length >= 2;
    if (mostrarLoading) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('Calculando a melhor rota...')),
            ],
          ),
        ),
      );
    }

    try {
      if (_paradas.length >= 2) {
        final destinos = _paradas.map((p) => p.destinoParaMapa).toList();
        // Loja como origem: usa o endereço da primeira parada como fallback
        // de referência geográfica só pra matriz de distância convergir —
        // o cálculo cobrável já ignora a perna de origem->1ª parada em
        // ambos os apps (ver DistanciaService.calcularRotaOrdemFixa).
        final resultado = await DistanciaService.calcularRotaOtimizada(
          origem: destinos.first,
          destinos: destinos,
        );
        if (resultado != null && resultado.ordemOtimizada != null) {
          _paradas = resultado.ordemOtimizada!.map((i) => _paradas[i]).toList();
          await _repository.atualizarKmEstimado(
            _rota.id,
            kmEstimado: resultado.distanciaCobravelKm,
            kmVoltaEstimado: resultado.distanciaVoltaKm,
            polylineEstimada: resultado.polylineCodificada,
          );
        }
      }

      if (mostrarLoading && mounted) Navigator.of(context, rootNavigator: true).pop();

      await _repository.iniciar(_rota.id);
      if (!mounted) return;
      setState(() => _rota = RotaEntrega(
            id: _rota.id,
            dataRota: _rota.dataRota,
            status: StatusRota.emAndamento,
            kmTotal: _rota.kmTotal,
            kmEstimado: _rota.kmEstimado,
            kmVoltaEstimado: _rota.kmVoltaEstimado,
            polylineEstimada: _rota.polylineEstimada,
          ));
      await _carregar();
    } catch (e) {
      if (mostrarLoading && mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao iniciar rota: $e')));
      }
    }
  }

  Future<void> _marcarEntregue(Parada parada) async {
    if (parada.pagamentoPendente) {
      final confirmou = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirmar pagamento'),
          content: Text(
            'Esse pedido está com pagamento pendente (${parada.tipoPagamento ?? 'forma não informada'}, '
            'R\$ ${parada.valorTotal.toStringAsFixed(2)}). Confirma que recebeu o pagamento na entrega?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Recebi — confirmar')),
          ],
        ),
      );
      if (confirmou != true) return;
    }

    try {
      await _repository.marcarEntregue(parada.pedidoId);
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao marcar entregue: $e')));
      }
    }
  }

  Future<void> _marcarNaoEntregue(Parada parada) async {
    const motivos = {
      'ausente': 'Cliente ausente',
      'endereco_nao_encontrado': 'Endereço não encontrado',
      'recusou': 'Cliente recusou',
    };

    final motivoEscolhido = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in motivos.entries)
              ListTile(title: Text(entry.value), onTap: () => Navigator.pop(ctx, entry.key)),
            ListTile(
              title: const Text('Outro motivo'),
              onTap: () => Navigator.pop(ctx, 'outro'),
            ),
          ],
        ),
      ),
    );
    if (motivoEscolhido == null) return;

    var motivoFinal = motivos[motivoEscolhido] ?? '';
    if (motivoEscolhido == 'outro') {
      final controller = TextEditingController();
      final texto = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Motivo'),
          content: TextField(controller: controller, decoration: const InputDecoration(hintText: 'Descreva o motivo')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Confirmar')),
          ],
        ),
      );
      if (texto == null || texto.isEmpty) return;
      motivoFinal = texto;
    }

    try {
      await _repository.marcarNaoEntregue(parada.pedidoId, motivoFinal);
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao marcar não entregue: $e')));
      }
    }
  }

  Future<void> _finalizarRota() async {
    final controller = TextEditingController(
      text: _rota.kmEstimado?.toStringAsFixed(1).replaceAll('.', ','),
    );
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar rota'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Km total rodado (opcional)', suffixText: 'km'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Finalizar')),
        ],
      ),
    );
    if (confirmou != true) return;

    final kmTotal = double.tryParse(controller.text.trim().replaceAll(',', '.'));

    try {
      await _repository.finalizar(_rota.id, kmTotal: kmTotal);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao finalizar: $e')));
      }
    }
  }

  bool get _todasResolvidas => _paradas.every((p) =>
      p.status == StatusParada.entregue || p.status == StatusParada.naoEntregue);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rota')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _paradas.length,
                    itemBuilder: (context, index) => _CardParada(
                      posicao: index + 1,
                      parada: _paradas[index],
                      podeAgir: _rota.emAndamento,
                      onNavegar: () => NavegacaoService.abrirNoGoogleMaps(_paradas[index].destinoParaMapa),
                      onEntregue: () => _marcarEntregue(_paradas[index]),
                      onNaoEntregue: () => _marcarNaoEntregue(_paradas[index]),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _rota.planejada
                        ? ElevatedButton(
                            onPressed: _paradas.isEmpty ? null : _iniciarRota,
                            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                            child: const Text('Iniciar rota'),
                          )
                        : _rota.emAndamento
                            ? ElevatedButton(
                                onPressed: _todasResolvidas ? _finalizarRota : null,
                                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                                child: Text(_todasResolvidas
                                    ? 'Finalizar rota'
                                    : 'Resolva todas as paradas pra finalizar'),
                              )
                            : const Text('Rota concluída', textAlign: TextAlign.center),
                  ),
                ),
              ],
            ),
    );
  }
}

class _CardParada extends StatelessWidget {
  final int posicao;
  final Parada parada;
  final bool podeAgir;
  final VoidCallback onNavegar;
  final VoidCallback onEntregue;
  final VoidCallback onNaoEntregue;

  const _CardParada({
    required this.posicao,
    required this.parada,
    required this.podeAgir,
    required this.onNavegar,
    required this.onEntregue,
    required this.onNaoEntregue,
  });

  Color _corStatus(String status) {
    switch (status) {
      case StatusParada.entregue:
        return Colors.green;
      case StatusParada.naoEntregue:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolvida = parada.status == StatusParada.entregue || parada.status == StatusParada.naoEntregue;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 14, child: Text('$posicao')),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(parada.clienteNome, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (resolvida)
                  Icon(
                    parada.status == StatusParada.entregue ? Icons.check_circle : Icons.cancel,
                    color: _corStatus(parada.status),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(parada.enderecoCompleto),
            if (parada.itensResumo.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(parada.itensResumo.join(', '), style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 6),
            Text(
              parada.pagamentoPendente
                  ? 'Cobrar na entrega: R\$ ${parada.valorTotal.toStringAsFixed(2)} (${parada.tipoPagamento ?? '?'})'
                  : 'Pago',
              style: TextStyle(
                color: parada.pagamentoPendente ? Colors.orange : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (podeAgir && !resolvida) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onNavegar,
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text('Navegar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onNaoEntregue,
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Não entregue'),
                  ),
                  ElevatedButton.icon(
                    onPressed: onEntregue,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Entregue'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verificação — compilação completa**

```bash
cd "C:\Users\lucas\StudioProjects\entregador-app"
flutter analyze
```

Esperado: 0 erros (a partir daqui `auth_gate.dart` → `minhas_rotas_screen.dart` → `rota_detalhe_screen.dart` fecham o ciclo de imports).

- [ ] **Step 3: Verificação manual — fluxo completo com dados reais**

Pré-requisito: já ter rodado Task 5 (gerar convite no Gestor) e Task 8 (vincular no app) com um entregador de teste que tenha 1+ pedido roteado (montar uma rota planejada no Gestor com 1-2 pedidos reais/de teste antes).

1. `flutter run -d <device_id>` no `entregador-app`.
2. Login/vínculo já feito → deve cair direto em "Minhas rotas de hoje" mostrando a rota planejada.
3. Abrir a rota → ver a(s) parada(s) com nome/endereço/itens corretos.
4. "Iniciar rota" → confirmar no Supabase que `rotas_entrega.status = 'em_andamento'`.
5. "Navegar" numa parada → confirma que abre o Google Maps externo com o destino certo.
6. "Entregue" num pedido com `status_pagamento = 'pendente'` → aparece o diálogo de confirmação; confirmar → checar no banco que `pedidos.status = 'entregue'` E `status_pagamento = 'pago'` (via trigger, só se `canal_venda = 'loja_fisica'`).
7. "Não entregue" noutro pedido → escolher motivo → checar `pedidos.status = 'nao_entregue'` e `metadata->>'motivo_nao_entrega'` preenchido.
8. Com as duas paradas resolvidas, "Finalizar rota" fica habilitado → tocar → checar `rotas_entrega.status = 'concluida'` e `pedidos.custo_entrega_valor` preenchido conforme o `custo_modo` do entregador de teste.

- [ ] **Step 4: Commit**

```bash
cd "C:\Users\lucas\StudioProjects\entregador-app"
git add lib/screens/rota_detalhe_screen.dart
git commit -m "$(cat <<'EOF'
Adiciona tela de detalhe da rota: iniciar, paradas, finalizar

Fecha o ciclo principal da Fase 1 do app Entregador — iniciar rota
(com otimização), navegar por deep link externo, marcar entregue
(com confirmação de pagamento pendente) ou não entregue (com motivo),
finalizar rota.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EayLGjLR2qR9nEwtHazeiX
EOF
)"
```

---

### Task 13: Push notifications no app novo

**Files:**
- Create: `entregador-app/lib/services/push_notification_service.dart`
- Modify: `entregador-app/lib/screens/minhas_rotas_screen.dart` (chamar a inicialização)

**Contexto:** depende do Task 14 (registro do app no Firebase + `google-services.json`/`firebase_options.dart`) pra funcionar de ponta a ponta — mas o código Dart pode ser escrito antes, só não vai compilar/rodar o push de verdade até o Task 14 existir. Ordem escolhida (código antes da config nativa) segue o padrão dos outros tasks deste plano (Dart primeiro, depois passo de infra manual).

- [ ] **Step 1: Criar o serviço**

`entregador-app/lib/services/push_notification_service.dart`:

```dart
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config/supabase_config.dart';
import '../firebase_options.dart';

/// Push (FCM) pro app Entregador — mesmo padrão do Gestor
/// (`gestor/lib/services/push_notification_service.dart`), mas salva o
/// token via RPC `atualizar_fcm_token_entregador` em vez de escrever direto
/// em `entregadores.fcm_token` (que não tem policy de UPDATE aberta pro
/// próprio entregador — de propósito, ver Task 3 do plano).
class PushNotificationService {
  static bool _inicializado = false;

  static Future<void> inicializar() async {
    if (_inicializado || kIsWeb || !Platform.isAndroid) return;

    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      _inicializado = true;

      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      await _salvarToken();
      FirebaseMessaging.instance.onTokenRefresh.listen((_) => _salvarToken());
    } catch (e) {
      debugPrint('Erro ao inicializar notificações push: $e');
    }
  }

  static Future<void> _salvarToken() async {
    if (supabase.auth.currentUser == null) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await supabase.rpc('atualizar_fcm_token_entregador', params: {'p_token': token});
    } catch (e) {
      debugPrint('Erro ao salvar token de notificação: $e');
    }
  }
}
```

- [ ] **Step 2: Chamar a inicialização quando a tela de rotas abrir**

Em `entregador-app/lib/screens/minhas_rotas_screen.dart`, adicionar o import:

```dart
import '../services/push_notification_service.dart';
```

E no `initState`:

```dart
@override
void initState() {
  super.initState();
  _carregar();
  PushNotificationService.inicializar();
}
```

- [ ] **Step 3: Verificação**

Só compila de fato depois do Task 14 (precisa de `firebase_options.dart` existir com dados reais). Deixar anotado: `flutter analyze` vai falhar em "target of URI doesn't exist: '../firebase_options.dart'" até lá — esperado.

- [ ] **Step 4: Commit**

```bash
cd "C:\Users\lucas\StudioProjects\entregador-app"
git add lib/services/push_notification_service.dart lib/screens/minhas_rotas_screen.dart
git commit -m "$(cat <<'EOF'
Adiciona serviço de push notification (FCM)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EayLGjLR2qR9nEwtHazeiX
EOF
)"
```

---

### Task 14: Registrar app no Firebase + build Android

**Contexto:** esse task tem passos manuais (console do Firebase) que exigem login interativo — não dá pra automatizar via CLI sem sessão aberta do usuário. Documentado aqui como checklist preciso, não como "TBD": são as mesmas etapas já seguidas quando o Gestor foi ligado ao Firebase (ver `gestor/lib/firebase_options.dart`, escrito à mão a partir do `google-services.json`).

**Files:**
- Create: `entregador-app/android/app/google-services.json` (baixado do console, não escrito à mão)
- Create: `entregador-app/lib/firebase_options.dart`
- Modify: `entregador-app/android/app/build.gradle` (applicationId + plugin do Google Services)

- [ ] **Step 1: Ajustar `applicationId`**

Em `entregador-app/android/app/build.gradle`, confirmar/ajustar (o `flutter create --org br.com.deliverypet --project-name entregador` do Task 7 já deve ter gerado isso certo, mas confirme):

```gradle
defaultConfig {
    applicationId "br.com.deliverypet.entregador"
    ...
}
```

- [ ] **Step 2: Registrar o app no Firebase Console**

No projeto Firebase existente `deliverypet-6d0e7` (console.firebase.google.com):
1. Configurações do projeto > Adicionar app > Android.
2. Nome do pacote Android: `br.com.deliverypet.entregador`.
3. Baixar o `google-services.json` gerado e colocar em `entregador-app/android/app/google-services.json`.

- [ ] **Step 3: Aplicar o plugin do Google Services**

Em `entregador-app/android/build.gradle` (nível raiz), adicionar no `dependencies` do bloco `buildscript`:

```gradle
classpath 'com.google.gms:google-services:4.4.2'
```

Em `entregador-app/android/app/build.gradle`, no topo (junto dos outros `apply plugin`):

```gradle
apply plugin: 'com.google.gms.google-services'
```

- [ ] **Step 4: Escrever `firebase_options.dart` a partir do `google-services.json` baixado**

`entregador-app/lib/firebase_options.dart` (mesmo padrão do Gestor — extrair `api_key`/`mobilesdk_app_id`/`project_number`/`project_id`/`storage_bucket` do JSON baixado no Step 2):

```dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Escrito à mão a partir de `android/app/google-services.json` (app Android
/// novo registrado no projeto Firebase `deliverypet-6d0e7`, reaproveitado do
/// Gestor). Só Android tem config nesta fase — ver
/// `push_notification_service.dart`, que já checa a plataforma.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('DefaultFirebaseOptions não tem configuração pra Web.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions só tem configuração pro Android (plataforma atual: $defaultTargetPlatform).',
        );
    }
  }

  // TODO(preencher após Step 2): valores vêm do google-services.json baixado
  // no console Firebase pro app br.com.deliverypet.entregador.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'PREENCHER_API_KEY',
    appId: 'PREENCHER_APP_ID',
    messagingSenderId: '380570421425',
    projectId: 'deliverypet-6d0e7',
    storageBucket: 'deliverypet-6d0e7.firebasestorage.app',
  );
}
```

Nota: os valores `apiKey`/`appId` só existem depois que o Step 2 (console Firebase) for feito por quem tem acesso à conta — é a única exceção neste plano a "sem placeholder", porque o valor literalmente não existe até um humano gerar no console. Preencher assim que o `google-services.json` real chegar.

- [ ] **Step 5: Build de teste**

```bash
cd "C:\Users\lucas\StudioProjects\entregador-app"
flutter build apk --debug
```

Esperado: build passa. Instalar num Android físico (`flutter install`) e repetir o checklist do Task 12 Step 3, agora conferindo que uma nova rota criada no Gestor pro entregador de teste dispara notificação push no celular (via `trg_notificar_nova_rota_entregador`, Task 4).

- [ ] **Step 6: Distribuição — Firebase App Distribution**

Reaproveitar o mesmo mecanismo já configurado pro Gestor (spec linha 22): no Firebase Console, App Distribution > selecionar o novo app Android > subir o APK de teste > adicionar os testadores (mesmo grupo usado hoje pro Gestor, se já existir um).

- [ ] **Step 7: Commit**

```bash
cd "C:\Users\lucas\StudioProjects\entregador-app"
git add android/app/google-services.json android/app/build.gradle android/build.gradle lib/firebase_options.dart
git commit -m "$(cat <<'EOF'
Registra app no Firebase (push) e finaliza build Android

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01EayLGjLR2qR9nEwtHazeiX
EOF
)"
```

---

## Self-Review

**Cobertura do spec:**
- Login próprio do entregador, sem linha em `usuarios` → Tasks 1, 3, 8.
- Ver rota(s) do dia → Task 11.
- Iniciar rota (com otimização) → Task 12 (`_iniciarRota`).
- Ver paradas em ordem, navegar (deep link) → Tasks 9, 10, 12.
- Marcar entregue (com confirmação de pagamento) / não entregue (com motivo) → Task 12.
- Finalizar rota → Tasks 4, 12.
- Push quando rota nova é montada → Tasks 4, 13, 14.
- Convite gerado a partir de "Entregadores" no Gestor → Task 5.
- Gestor: botões viram override manual → Task 6.
- RLS pros dados do entregador → Task 2.
- Reaproveitar `finalizar_rota_entrega`/`calcularRotaOtimizada`/`calcularRotaOrdemFixa` → Tasks 4, 10 (com a correção de que `finalizar_rota_entrega` precisou de ajuste, não ficou "sem mudança" como o spec supôs).
- Fora de escopo (GPS ao vivo, mapa ao vivo, rastreio cliente, foto de comprovante) → nenhum task cobre, de propósito.

**Correções feitas em relação ao spec original** (achadas só ao inspecionar o schema real via MCP do Supabase, não estavam visíveis no spec):
1. `confirmar_pagamento_entrega_loja_fisica` é trigger, não RPC — não existe chamada de RPC pra isso em nenhum task.
2. `finalizar_rota_entrega` PRECISOU de alteração (Task 4) — sem ela, a RPC rejeitaria toda chamada feita pelo entregador (`get_empresa_id()` retorna NULL pra quem não tem linha em `usuarios`).
3. RLS extra também precisou cobrir `clientes` e `itens_pedido` (não só as 3 tabelas citadas no spec) — sem isso a tela de parada não teria como mostrar nome/endereço/itens do pedido.
4. Token de push do entregador vai por RPC dedicada (`atualizar_fcm_token_entregador`), não por uma policy de UPDATE aberta em `entregadores` — mais restrito do que uma leitura literal do spec sugeriria.
5. Notificação de "rota nova" é um trigger dedicado (`trg_notificar_nova_rota_entregador`), não uma extensão do trigger genérico `notificar_push_notificacao` — evita mexer numa função compartilhada e sensível só pra um caso 1:1.

**Placeholder scan:** único ponto com valor pendente de verdade é `firebase_options.dart` (Task 14, Step 4) — não é um "TBD" evitável, é um valor que só existe depois de uma ação manual num console de terceiros (mesma situação documentada no `firebase_options.dart` atual do Gestor).
