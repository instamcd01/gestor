-- APLICADA 13/11 — carga dos robôs da 99 (banco travou 12/11 21h45)
-- Causa: food99_garantir_acoes (a cada 20s) varria eventos_sistema inteira (66 MB, sem índice de data)
-- ~4.300 vezes/dia; food99_manter_tokens gravava food99_token a cada 15s mesmo sem mudança;
-- cron.job_run_details crescia sem limpeza (46 MB).

-- 1) índices pra varredura por data/tipo em eventos_sistema
create index if not exists eventos_sistema_created_at_idx on public.eventos_sistema (created_at);
create index if not exists eventos_sistema_tipo_created_idx on public.eventos_sistema (tipo_evento, created_at);

-- 2) manter_tokens: não regravar a linha do token a cada rodada
CREATE OR REPLACE FUNCTION public.food99_manter_tokens()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c record; t record; r record; v_req bigint; v_n int := 0;
  c_food99 constant uuid := 'e11ec855-6936-410d-a56a-635adebfe595';
begin
  for c in select empresa_id, api_key, api_secret, id_loja_plataforma
             from empresa_marketplace_config where marketplace_id = c_food99 and ativo loop
    insert into food99_token (empresa_id, app_shop_id) values (c.empresa_id, c.id_loja_plataforma)
      on conflict (empresa_id) do update set app_shop_id = excluded.app_shop_id
      where food99_token.app_shop_id is distinct from excluded.app_shop_id;
    select * into t from food99_token where empresa_id = c.empresa_id;

    if t.net_verif_id is not null then
      select * into r from net._http_response where id = t.net_verif_id;
      if r.id is not null then
        if (r.content::jsonb->>'errno') in ('10100','10102') then
          update food99_token set auth_token = null, expira_em = null, erro = 'token derrubado pela 99: ' || left(r.content, 200)
           where empresa_id = c.empresa_id;
        end if;
        update food99_token set net_verif_id = null, verificado_em = now() where empresa_id = c.empresa_id;
      elsif t.verificado_em < now() - interval '3 minutes' then
        update food99_token set net_verif_id = null where empresa_id = c.empresa_id;
      end if;
      select * into t from food99_token where empresa_id = c.empresa_id;
    end if;

    if t.net_request_id is not null then
      select * into r from net._http_response where id = t.net_request_id;
      if r.id is null then
        if t.acao_em > now() - interval '2 minutes' then continue; end if;
      elsif (r.content::jsonb->>'errno') = '0' then
        if t.acao_pendente = 'get' and (r.content::jsonb->'data'->>'auth_token') is not null then
          update food99_token set auth_token = r.content::jsonb->'data'->>'auth_token',
                 emitido_em = now(),
                 expira_em = to_timestamp((r.content::jsonb->'data'->>'token_expiration_time')::bigint),
                 verificado_em = now(),
                 erro = null where empresa_id = c.empresa_id;
        elsif t.acao_pendente = 'refresh' then
          update food99_token set refresh_ok_em = now(), erro = null where empresa_id = c.empresa_id;
        end if;
      else
        update food99_token set erro = coalesce(r.content, r.error_msg) where empresa_id = c.empresa_id;
      end if;
      update food99_token set net_request_id = null, acao_pendente = null where empresa_id = c.empresa_id;
      select * into t from food99_token where empresa_id = c.empresa_id;
    end if;

    if t.auth_token is null or t.expira_em is null
       or t.expira_em < now() + greatest(interval '6 minutes', (t.expira_em - coalesce(t.emitido_em, now())) / 3) then
      if t.refresh_ok_em > now() - interval '5 minutes' then
        v_req := net.http_get(url := 'https://openapi.99food.com/v1/auth/authtoken/get',
          params := jsonb_build_object('app_id', c.api_key, 'app_secret', c.api_secret, 'app_shop_id', c.id_loja_plataforma));
        update food99_token set acao_pendente = 'get', net_request_id = v_req, acao_em = now() where empresa_id = c.empresa_id;
      else
        v_req := net.http_get(url := 'https://openapi.99food.com/v1/auth/authtoken/refresh',
          params := jsonb_build_object('app_id', c.api_key, 'app_secret', c.api_secret, 'app_shop_id', c.id_loja_plataforma));
        update food99_token set acao_pendente = 'refresh', net_request_id = v_req, acao_em = now(), refresh_ok_em = null where empresa_id = c.empresa_id;
      end if;
      v_n := v_n + 1;
    elsif t.net_verif_id is null and coalesce(t.verificado_em, '-infinity') < now() - interval '5 minutes' then
      v_req := net.http_get(url := 'https://openapi.99food.com/v1/shop/shop/detail',
        params := jsonb_build_object('auth_token', t.auth_token));
      update food99_token set net_verif_id = v_req, verificado_em = now() where empresa_id = c.empresa_id;
    end if;
  end loop;
  return v_n;
end;
$function$;

-- 3) frequências: garantir 20s→30s (confirmação ainda cabe com folga no prazo de 5 min da 99),
--    token 15s→1 min (renova com ≥6 min de antecedência), cancelamento parcial 10s→30s
select cron.alter_job(41, schedule := '30 seconds');
select cron.alter_job(34, schedule := '* * * * *');
select cron.alter_job(42, schedule := '30 seconds');

-- 4) limpeza diária do histórico do cron (guarda 3 dias)
select cron.schedule('limpar-historico-cron', '20 3 * * *',
  $$delete from cron.job_run_details where end_time < now() - interval '3 days'$$);
