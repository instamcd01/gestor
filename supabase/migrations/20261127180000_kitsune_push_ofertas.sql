-- Kitsune (app do entregador): avisos no celular quando chega oferta de rota (27/11).
-- Vários aparelhos por entregador (iPhone pela Tela de Início + Android), como no Gestor.

create table if not exists public.entregador_dispositivos_push (
  token text primary key,
  entregador_id uuid not null references public.entregadores(id) on delete cascade,
  plataforma text not null default 'web' check (plataforma in ('android', 'web', 'ios')),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index if not exists entregador_dispositivos_push_entregador_idx
  on public.entregador_dispositivos_push (entregador_id);
alter table public.entregador_dispositivos_push enable row level security;
-- sem policies: só as funções security definer abaixo leem/gravam

-- Registra o aparelho do entregador logado (relogin em outro entregador troca o dono do token).
create or replace function public.registrar_dispositivo_push_entregador(p_token text, p_plataforma text default 'web')
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_entregador uuid;
begin
  if p_token is null or length(p_token) < 20 then return false; end if;
  select id into v_entregador from entregadores
   where auth_user_id = auth.uid() and deleted_at is null
   limit 1;
  if v_entregador is null then return false; end if;

  insert into entregador_dispositivos_push (token, entregador_id, plataforma)
  values (p_token, v_entregador, coalesce(nullif(p_plataforma, ''), 'web'))
  on conflict (token) do update
    set entregador_id = excluded.entregador_id,
        plataforma = excluded.plataforma,
        atualizado_em = now();
  return true;
end;
$$;
revoke all on function public.registrar_dispositivo_push_entregador(text, text) from public, anon;
grant execute on function public.registrar_dispositivo_push_entregador(text, text) to authenticated;

-- App Android antigo grava em entregadores.fcm_token: passa a gravar também na tabela nova.
create or replace function public.atualizar_fcm_token_entregador(p_token text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  update entregadores set fcm_token = p_token where auth_user_id = auth.uid();
  perform registrar_dispositivo_push_entregador(p_token, 'android');
end;
$$;

-- Todos os aparelhos de um entregador (tabela nova + legado).
create or replace function public.tokens_push_entregador(p_entregador uuid)
returns text[]
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(array_agg(distinct t), '{}')
  from (
    select token as t from entregador_dispositivos_push where entregador_id = p_entregador
    union
    select fcm_token from entregadores where id = p_entregador and fcm_token is not null
  ) x;
$$;
revoke all on function public.tokens_push_entregador(uuid) from public, anon, authenticated;

-- Push a cada oferta nova (o WhatsApp continua indo pelo n8n como antes).
create or replace function public.notificar_push_oferta_rota()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_tokens text[];
  v_valor text;
  v_n int;
begin
  if new.resposta is not null then return new; end if;
  v_tokens := tokens_push_entregador(new.entregador_id);
  if coalesce(array_length(v_tokens, 1), 0) = 0 then return new; end if;

  v_valor := 'R$ ' || replace(to_char(coalesce(new.valor_ofertado, 0), 'FM999990.00'), '.', ',');
  v_n := coalesce(new.n_pedidos, 1);

  perform net.http_post(
    url := 'https://n8n.lukz.com.br/webhook/notificacao-push',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := jsonb_build_object(
      'notificacao_id', new.id,
      'empresa_id', new.empresa_id,
      'tipo', 'oferta_rota',
      'titulo', 'Nova entrega: ' || v_valor,
      'mensagem', v_n || case when v_n = 1 then ' pedido' else ' pedidos' end
                  || ' · o 1º que aceitar leva. Toque pra ver.',
      'link', 'https://kitsune.inari.lukz.com.br/',
      'icone', 'https://kitsune.inari.lukz.com.br/icons/Icon-192.png',
      'tokens', to_jsonb(v_tokens)
    )
  );
  return new;
exception when others then
  -- aviso nunca pode impedir a oferta de ser gravada
  raise warning 'notificar_push_oferta_rota: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists trg_push_oferta_rota on public.rota_ofertas;
create trigger trg_push_oferta_rota
  after insert on public.rota_ofertas
  for each row execute function public.notificar_push_oferta_rota();

-- Rota montada pela loja: usa todos os aparelhos e abre o Kitsune (antes: 1 token, link do Gestor).
create or replace function public.notificar_nova_rota_entregador()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_tokens text[];
begin
  if new.entregador_id is null then return new; end if;
  v_tokens := tokens_push_entregador(new.entregador_id);
  if coalesce(array_length(v_tokens, 1), 0) = 0 then return new; end if;

  perform net.http_post(
    url := 'https://n8n.lukz.com.br/webhook/notificacao-push',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := jsonb_build_object(
      'notificacao_id', new.id,
      'empresa_id', new.empresa_id,
      'tipo', 'rota_atribuida',
      'titulo', 'Nova rota de entrega',
      'mensagem', 'Você tem uma nova rota pra hoje.',
      'link', 'https://kitsune.inari.lukz.com.br/',
      'icone', 'https://kitsune.inari.lukz.com.br/icons/Icon-192.png',
      'tokens', to_jsonb(v_tokens)
    )
  );
  return new;
end;
$$;
