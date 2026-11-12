# 99Food — virada do sandbox pra loja real

Estado em 12/11/2026: a integração está pronta e testada no sandbox (app de teste `5764607796526450761`,
loja de teste com `app_shop_id` = id da empresa Delivery Pet `3bce0e24-2868-49f3-a9dd-eed921ffc8e4`).

## O que só a 99 destrava (ordem)
1. **Call de validação** com o time de integração (loja de teste aberta + catálogo ativo). Eles conferem:
   dinheiro e online, entrega da 99 e da loja, confirmar/cancelar/pronto/entregue, valores, cliente,
   endereço, nº do pedido e observação.
2. **Conta de teste do C-App**, pra testar pagamento online e cancelamento/reembolso pedidos pelo cliente.
3. **Loja de produção**: quem cria é o time **comercial** da 99 (contrato). A Delivery Pet tem cadastro, mas
   a loja não está ativa.

## Antes da call (conferido contra o roteiro da 99 em 12/11)
- [ ] Loja de teste ABERTA. Em 12/11 o setStatus deu errno 11040 "is shop self delivery pay mode set?": a loja está
      em entrega pela loja sem forma de pagamento. Acertar em merchant.99app.com › Lojas › Configurações ›
      Formas de pagamento (e Configurações de entrega), depois reabrir.
- [ ] Testar pedido com desconto (promotions / shop_subside_price / items_discount): nenhum teste teve desconto ainda.
- [ ] Pagamento online e cancelamento/reembolso pedido pelo cliente (C-App).
- [x] Cancelamento pela loja manda o motivo real (1010–1080), não mais sempre 1080 (app + robô de status, 12/11).
- [x] Dinheiro com entrega da 99 entra "pago" (a 99 repassa como online); com entrega da loja entra "pendente".
- [x] Catálogo ≥ 5 itens, estoque 1x/hora, token refresh→get, webhook responde errno 0.
- Opcional (não está na call): cancelamento parcial `/v3/order/operate/partialCancel` com `is_sold_out`
  (hoje a separação usa `adjustItem`); polling de pedidos (só se a 99 liberar; usamos webhook).

## Virada (depois da call aprovada e da loja criada pelo comercial)
1. **App de produção** no portal (Gerenciamento de aplicativo › Criar aplicativo):
   nome `DeliveryPet_P_GR_BR`, tipo "Ambiente de produção", webhook `https://n8n.lukz.com.br/webhook/99food-eventos`
   (é o mesmo robô; ele confere a assinatura com o segredo que está na configuração).
2. **Autorização da loja**: Gerenciamento da loja › Autorização de solicitação de lote › escolher o app de
   produção › copiar o link. O Lucas abre o link logado como gerente da loja real e clica em Autorizar.
3. **Vincular**: aba "Vincular estabelecimento" › Bind › `app_shop_id` = `3bce0e24-2868-49f3-a9dd-eed921ffc8e4`.
4. **Desvincular a loja de TESTE** do app de teste (Unbind). Senão os pedidos de teste continuam caindo na
   empresa real e baixando estoque.
5. **Trocar a credencial** no Gestor (Integrar Plataformas › 99Food): App ID e Secret do app de produção. Quem
   cola é o Lucas. Isso grava `empresa_marketplace_config.api_key/api_secret`; tudo no banco e nos robôs lê de lá.
   O `food99-manter-token` pega o token novo no minuto seguinte (conferir `food99_token.erro` nulo).
6. **Catálogo**: `select food99_carga_catalogo_iniciar('3bce0e24-2868-49f3-a9dd-eed921ffc8e4');`
   O cron `food99-carga-catalogo` manda um lote de 50 a cada ~70 s e para sozinho no fim
   (`food99_carga_catalogo.concluido_em`). Se a produção tiver o limite de 1 envio a cada 4 h, ele espera e
   tenta de novo (errno 10005) — perguntar antes à 99 se liberam a janela pra carga inicial.
   Em produção a 99 categoriza pelo **EAN** (item library): EAN certo importa mais que a categoria.
6b. **Aceitação só pela OpenAPI** (a 99 volta pra "B-App e OpenAPI" ao vincular; nesse modo a loja NÃO aparece pro
   cliente se não for aberta pelo app de lojista): `POST /v1/shop/shop/setconfirmmethod` com `order_confirm_method: 2`.
   E ligar pedidos de cancelamento/reembolso do cliente: `POST /v1/shop/apply/set` (receive_cancel_apply e
   receive_refund_apply = 1). Conferir em `/v1/shop/shop/detail`.
7. **Loja**: configurar no merchant.99app.com (Grocery, categoria, entrega pela loja, área/taxa, horário) e
   abrir pela tela de pausa do Gestor ou `setStatus`.
8. **Piloto**: 1º pedido real acompanhado ao vivo (chega, confirma sozinho, pronto, saiu, entregue,
   valores batem com o app da 99).

## Rede de segurança do token (12/11)
A 99 derruba o token da loja a qualquer momento (validade aleatória, mudança de config). Enquanto o banco
renova, os robôs mandavam confirmar/cancelar com token vazio (errno 10002) e a chamada se perdia — num pedido
real a 99 cancelaria sozinha em 5 min. Agora:
- `food99-manter-token` roda a cada **15 s** (era 1 min).
- `food99-garantir-acoes` (a cada 20 s, função `food99_garantir_acoes`): confirma de novo pedido que ficou
  `orderNew` por mais de 15 s (até 6 tentativas em 5 min) e reenvia ao robô de status qualquer
  cancelado/pronto/entregue que voltou com errno 10002/10100/10102. Resposta 10100/10102 força renovar o token.
  Histórico em `food99_reenvios`.

## Conferências rápidas
```sql
select * from food99_token;                         -- token válido e sem erro
select * from food99_carga_catalogo;                -- andamento da carga
select tipo_evento, count(*), max(created_at) from eventos_sistema
 where tipo_evento like '99food%' and created_at > now() - interval '1 day' group by 1;
```
`99food_assinatura_invalida` só com `uploadGroceryMenuTaskStatus` é conhecido e inofensivo (pergunta aberta
com a 99). Em aviso de pedido, o robô confere o pedido em `/v1/order/order/detail` antes de seguir.

## Limpeza depois da virada
Apagar `teste_99food_lote`, `teste_99food_etapa`, `teste_99food_driver`, `teste_99food_conferir_proximo` e a
tabela `teste_99food_log` (têm a credencial de teste fixa no código).
