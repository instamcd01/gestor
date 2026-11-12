-- 12/11: auditoria do financeiro dos pedidos de marketplace (APLICADA 12/11 como financeiro_marketplace_correcoes_12_11).
-- 1) Taxa de serviço que o iFood cobra do cliente (additionalFees, ex. R$0,99) entra no valor_total mas fica com o iFood
--    (confirmado no extrato real de outubro: diferença de -0,99 por pedido). Sai da receita/lucro/repasse.
-- 2) Entrega feita pela plataforma (entregador_tipo <> MERCHANT, ex. 99FOOD): frete é da plataforma e a loja não tem custo de entrega.
-- 3) 99Food: comissão real do pedido (price_raw.commission_price, centavos) quando vier > 0; senão taxa cadastrada em marketplace_taxas.
-- 4) Cancelamento parcial da 99 passa a reduzir também o valor bruto do repasse.

create or replace function public.calcular_lucro_pedido()
returns trigger language plpgsql set search_path to 'public' as $function$
declare
  v_custo_itens numeric := 0;
  v_total_taxas_marketplace numeric := 0;
  v_reembolso_promocional numeric := 0;
  v_custos_operacionais numeric := 0;
  v_taxa_mp numeric := 0;
  v_lucro numeric := 0;
  v_receita numeric := 0;
  v_entregador text;
  v_taxa_serv numeric := 0;
  v_taxa_cliente numeric := 0;
  v_frete_plat numeric := 0;
begin
  select coalesce(sum(quantidade * custo_unitario),0) into v_custo_itens from itens_pedido where pedido_id = new.id;
  new.custo_total := v_custo_itens;

  if new.marketplace_id is not null then
    select coalesce(taxa_comissao,0) + coalesce(taxa_gateway,0) + coalesce(outras_taxas,0),
           coalesce(incentivo_promocional_ifood,0) + coalesce(incentivo_promocional_external,0),
           entregador_tipo, coalesce(taxa_servico_cliente,0)
      into v_total_taxas_marketplace, v_reembolso_promocional, v_entregador, v_taxa_serv
      from marketplace_pedidos where pedido_id = new.id;

    v_taxa_cliente := least(coalesce(v_taxa_serv,0), greatest(0, coalesce(new.valor_total,0)
                       - (coalesce(new.valor_produtos,0) + coalesce(new.valor_entrega,0) - coalesce(new.desconto,0))));

    if v_entregador is not null and v_entregador <> 'MERCHANT' then
      new.custo_entrega_valor := 0;
      v_frete_plat := coalesce(new.valor_entrega,0);
    end if;
  end if;

  v_custos_operacionais := coalesce(new.custo_embalagem_valor,0) + coalesce(new.taxa_maquininha_valor,0) + coalesce(new.custo_entrega_valor,0);
  v_taxa_mp := coalesce((new.metadata->>'mercadoPagoTaxa')::numeric, 0);

  v_lucro := new.valor_total - v_taxa_cliente - v_frete_plat - v_custo_itens - v_total_taxas_marketplace
             - v_custos_operacionais - v_taxa_mp + coalesce(v_reembolso_promocional,0);
  new.lucro_bruto := v_lucro;

  v_receita := new.valor_total - v_taxa_cliente - v_frete_plat + coalesce(v_reembolso_promocional,0);
  if v_receita > 0 then
    new.margem_percentual := greatest(-9999.99, least(9999.99, round((v_lucro / v_receita) * 100, 2)));
  end if;

  if new.marketplace_id is not null then
    update marketplace_pedidos set lucro_real_canal = v_lucro, margem_real_canal = new.margem_percentual
     where pedido_id = new.id;
  end if;
  return new;
end;
$function$;

create or replace function public.calcular_comissao_marketplace()
returns trigger language plpgsql set search_path to 'public' as $function$
declare
  v_ped record;
  v_offline boolean;
  v_taxa record;
  v_tem_taxa boolean;
  v_valor_itens numeric;
  v_base_comissao numeric;
  v_promo numeric;
  v_comissao_real numeric;
  v_taxa_cliente numeric := 0;
  v_frete_plat numeric := 0;
begin
  select empresa_id, coalesce((metadata->>'pagamentoNaEntrega')::boolean, false) offline,
         valor_total, valor_produtos, valor_entrega, desconto
    into v_ped from pedidos where id = new.pedido_id;
  v_offline := coalesce(v_ped.offline, false);

  select percentual_comissao, taxa_fixa, taxa_gateway into v_taxa
    from marketplace_taxas
   where marketplace_id = new.marketplace_id and empresa_id = v_ped.empresa_id
     and vigencia_inicio <= current_date and (vigencia_fim is null or vigencia_fim >= current_date)
   order by vigencia_inicio desc limit 1;
  v_tem_taxa := found;

  begin
    v_comissao_real := nullif((new.metadata->'price_raw'->>'commission_price')::numeric, 0) / 100;
  exception when others then v_comissao_real := null;
  end;

  if (v_tem_taxa or v_comissao_real is not null) and not coalesce(new.metadata ? 'repasseReal', false) then
    v_base_comissao := coalesce(new.valor_bruto_marketplace, 0);

    if new.marketplace_id = 'd4811153-e210-47b0-b910-ee0440914f60' then
      select coalesce(sum(quantidade * preco_unitario), 0) into v_valor_itens from itens_pedido where pedido_id = new.pedido_id;
      if v_valor_itens > 0 then
        v_base_comissao := v_valor_itens + coalesce(new.taxa_entrega_paga, 0);
      end if;
    end if;

    v_taxa_cliente := least(coalesce(new.taxa_servico_cliente,0), greatest(0, coalesce(v_ped.valor_total,0)
                       - (coalesce(v_ped.valor_produtos,0) + coalesce(v_ped.valor_entrega,0) - coalesce(v_ped.desconto,0))));
    if new.entregador_tipo is not null and new.entregador_tipo <> 'MERCHANT' then
      v_frete_plat := coalesce(v_ped.valor_entrega,0);
    end if;

    v_promo := coalesce(new.incentivo_promocional_ifood, 0) + coalesce(new.incentivo_promocional_external, 0);
    new.taxa_comissao := coalesce(v_comissao_real,
                           v_base_comissao * coalesce(v_taxa.percentual_comissao,0) / 100 + coalesce(v_taxa.taxa_fixa,0));
    new.taxa_gateway := case when v_offline then 0 else v_base_comissao * coalesce(v_taxa.taxa_gateway,0) / 100 end;
    new.outras_taxas := coalesce(new.outras_taxas, 0);
    new.valor_liquido_recebido := case when v_offline then 0
                                       else coalesce(new.valor_bruto_marketplace,0) - v_taxa_cliente - v_frete_plat end
                                  - new.taxa_comissao - new.taxa_gateway - new.outras_taxas + v_promo;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_calcular_comissao_marketplace on public.marketplace_pedidos;
create trigger trg_calcular_comissao_marketplace
  before insert or update of valor_bruto_marketplace, metadata, entregador_tipo, incentivo_promocional_ifood,
                             incentivo_promocional_external, taxa_entrega_paga
  on public.marketplace_pedidos for each row execute function calcular_comissao_marketplace();


-- 5) iFood: quem bancou cada desconto (MERCHANT → incentivo_promocional_loja) e frete cobrado x pago pelo cliente.
--    Antes só IFOOD/EXTERNAL eram lidos: desconto da loja ficava sem dono, taxa_entrega_paga nula → comissão sem a
--    entrega paga, tela mostrava "Entrega cobrada do cliente" mesmo com frete grátis (pedido da Érica, 1457).
create or replace function public.marketplace_incentivo_da_metadata()
returns trigger language plpgsql set search_path to 'public' as $function$
declare v_ifood numeric; v_ext numeric; v_loja numeric; v_plat numeric; v_frete_benef numeric := 0; v_entrega numeric;
begin
  if NEW.marketplace_id = 'd4811153-e210-47b0-b910-ee0440914f60' then
    if jsonb_typeof(NEW.metadata->'beneficios') = 'array' then
      select coalesce(sum((s->>'value')::numeric) filter (where s->>'name' = 'IFOOD'), 0),
             coalesce(sum((s->>'value')::numeric) filter (where s->>'name' in ('EXTERNAL','CHAIN')), 0),
             coalesce(sum((s->>'value')::numeric) filter (where s->>'name' = 'MERCHANT'), 0)
        into v_ifood, v_ext, v_loja
        from jsonb_array_elements(NEW.metadata->'beneficios') b,
             jsonb_array_elements(coalesce(b->'sponsorshipValues','[]'::jsonb)) s;
      select coalesce(sum((b->>'value')::numeric) filter (where b->>'target' = 'DELIVERY_FEE'), 0)
        into v_frete_benef from jsonb_array_elements(NEW.metadata->'beneficios') b;
      if NEW.incentivo_promocional_ifood is null and v_ifood > 0 then NEW.incentivo_promocional_ifood := v_ifood; end if;
      if NEW.incentivo_promocional_external is null and v_ext > 0 then NEW.incentivo_promocional_external := v_ext; end if;
      if NEW.incentivo_promocional_loja is null and v_loja > 0 then NEW.incentivo_promocional_loja := v_loja; end if;
    end if;
    if NEW.taxa_entrega_marketplace is null then
      select valor_entrega into v_entrega from pedidos where id = NEW.pedido_id;
      if v_entrega is not null then
        NEW.taxa_entrega_marketplace := v_entrega;
        NEW.taxa_entrega_paga := coalesce(NEW.taxa_entrega_paga, greatest(0, v_entrega - v_frete_benef));
      end if;
    end if;
    return NEW;
  end if;

  if NEW.incentivo_promocional_ifood is null and NEW.incentivo_promocional_external is null and NEW.metadata is not null then
    if jsonb_typeof(NEW.metadata->'promocoes') = 'array' and jsonb_array_length(NEW.metadata->'promocoes') > 0 then
      select coalesce(sum(greatest(coalesce((p->>'promo_discount')::numeric,0) - coalesce((p->>'shop_subside_price')::numeric,0), 0))
                        filter (where not ((p->>'promo_type') = '12' and NEW.entregador_tipo = '99FOOD')), 0) / 100,
             coalesce(sum(coalesce((p->>'shop_subside_price')::numeric,0)), 0) / 100
        into v_plat, v_loja
        from jsonb_array_elements(NEW.metadata->'promocoes') p;
      if v_plat > 0 then NEW.incentivo_promocional_ifood := v_plat; end if;
      if v_loja > 0 and NEW.incentivo_promocional_loja is null then NEW.incentivo_promocional_loja := v_loja; end if;
    elsif (NEW.metadata->>'desconto_pago_99') is not null and (NEW.metadata->>'desconto_pago_99')::numeric > 0 then
      NEW.incentivo_promocional_ifood := (NEW.metadata->>'desconto_pago_99')::numeric;
    end if;
  end if;
  return NEW;
end;
$function$;

-- 6) Ordem: o incentivo tem que ser lido ANTES da comissão/repasse (triggers rodam em ordem alfabética;
--    antes "trg_calcular_comissao" rodava antes de "trg_marketplace_incentivo" e o repasse ficava sem o reembolso).
drop trigger if exists trg_marketplace_incentivo_da_metadata on public.marketplace_pedidos;
drop trigger if exists trg_a2_marketplace_incentivo_da_metadata on public.marketplace_pedidos;
create trigger trg_a2_marketplace_incentivo_da_metadata
  before insert or update of metadata on public.marketplace_pedidos
  for each row execute function marketplace_incentivo_da_metadata();

-- 7) Recalcular pedidos de marketplace desde 13/10 que ainda não foram repassados.
update marketplace_pedidos m set metadata = m.metadata
  from pedidos p
 where p.id = m.pedido_id and p.created_at >= '2026-10-13' and m.data_repassado is null and p.deleted_at is null;

-- trg_metricas_marketplace soma +1 pedido a cada UPDATE (contaria tudo de novo) → desliga só durante o recálculo
alter table public.pedidos disable trigger trg_metricas_marketplace;
alter table public.pedidos disable trigger trg_frequencia_cliente;
update pedidos p set updated_at = now()
  from marketplace_pedidos m
 where m.pedido_id = p.id and p.created_at >= '2026-10-13' and m.data_repassado is null and p.deleted_at is null
   and p.status in ('entregue','concluido') and p.status_pagamento = 'pago';
alter table public.pedidos enable trigger trg_metricas_marketplace;
alter table public.pedidos enable trigger trg_frequencia_cliente;
