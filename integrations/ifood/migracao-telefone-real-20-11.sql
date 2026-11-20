-- Aplicada em produção 20/11/2026 (migration "clientes_telefone_real_sobre_mascarado").
-- Pedido do Lucas: o WhatsApp que o cliente do iFood informa no chat (ifood-chat
-- grava em clientes.whatsapp_informado) vira o telefone do cadastro, e o número
-- mascarado do marketplace (0800 do iFood, x99- da 99) nunca sobrescreve um
-- telefone real. Antes, o n8n "iFood - Webhook de Eventos" regravava o 0800 a
-- cada pedido, e a resposta do cliente no WhatsApp criava um cadastro gêmeo
-- "Cliente WhatsApp" (whatsapp_cliente_da_loja não achava o número).
create or replace function public._telefone_eh_placeholder(p text)
returns boolean language sql immutable as $$
  select p is null or btrim(p) = ''
      or btrim(p) ~ '^0800'
      or p like 'x99-%'
      or p like 'kyte-sem-numero%'
      or length(regexp_replace(p, '\D', '', 'g')) < 10
$$;

create or replace function public.clientes_telefone_real()
returns trigger language plpgsql set search_path = public as $$
begin
  if NEW.whatsapp_informado is not null
     and length(regexp_replace(NEW.whatsapp_informado, '\D', '', 'g')) >= 12
     and public._telefone_eh_placeholder(NEW.telefone) then
    NEW.telefone := regexp_replace(NEW.whatsapp_informado, '\D', '', 'g');
  elsif TG_OP = 'UPDATE'
     and public._telefone_eh_placeholder(NEW.telefone)
     and not public._telefone_eh_placeholder(OLD.telefone) then
    NEW.telefone := OLD.telefone;
  end if;
  return NEW;
end $$;

-- nome começa com "trg_clientes_t..." pra rodar DEPOIS do trg_clientes_99food_telefone_compartilhado
drop trigger if exists trg_clientes_telefone_real on public.clientes;
create trigger trg_clientes_telefone_real
  before insert or update of telefone, whatsapp_informado on public.clientes
  for each row execute function public.clientes_telefone_real();

-- Dados (rodado uma vez em 20/11): 4 gêmeos "Cliente WhatsApp" juntados ao
-- cadastro do iFood (conversas + mensagens movidas, gêmeo com deleted_at) —
-- pares em eventos_sistema tipo 'clientes_juntados_ifood_whatsapp'; depois
-- update clientes set whatsapp_informado = whatsapp_informado where whatsapp_informado is not null;
