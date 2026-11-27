-- Kitsune: botão "Testar aviso" — push de teste só pros aparelhos do próprio motoboy logado.
create or replace function public.testar_push_entregador()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_ent entregadores;
  v_tokens text[];
begin
  select * into v_ent from entregadores where auth_user_id = auth.uid() and deleted_at is null limit 1;
  if v_ent.id is null then return 0; end if;
  v_tokens := tokens_push_entregador(v_ent.id);
  if coalesce(array_length(v_tokens, 1), 0) = 0 then return 0; end if;

  perform net.http_post(
    url := 'https://n8n.lukz.com.br/webhook/notificacao-push',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := jsonb_build_object(
      'notificacao_id', gen_random_uuid(),
      'empresa_id', v_ent.empresa_id,
      'tipo', 'teste_kitsune',
      'titulo', 'Teste do Kitsune ✅',
      'mensagem', 'Os avisos de oferta estão chegando neste celular.',
      'link', 'https://kitsune.inari.lukz.com.br/',
      'icone', 'https://kitsune.inari.lukz.com.br/icons/Icon-192.png',
      'tokens', to_jsonb(v_tokens)
    )
  );
  return array_length(v_tokens, 1);
end;
$$;
revoke all on function public.testar_push_entregador() from public, anon;
grant execute on function public.testar_push_entregador() to authenticated;
