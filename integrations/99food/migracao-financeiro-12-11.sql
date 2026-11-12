-- 12/11: auditoria do financeiro dos pedidos de marketplace (aguardando aplicar).
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
  before insert or update of valor_bruto_marketplace, metadata, entregador_tipo, incentivo_promocional_ifood
  on public.marketplace_pedidos for each row execute function calcular_comissao_marketplace();

-- Cancelamento parcial da 99: além do que já fazia, reduz o valor bruto do repasse.
-- (corpo igual ao atual + o update de marketplace_pedidos antes do insert em eventos_sistema)
--   update marketplace_pedidos set valor_bruto_marketplace = greatest(0, coalesce(valor_bruto_marketplace,0) - v_valor)
--    where id = NEW.marketplace_pedido_id and data_repassado is null;
