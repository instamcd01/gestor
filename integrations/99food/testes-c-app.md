# 99Food — testes com o app do cliente (C-App), antes da call

Conta de teste: passada pela equipe da 99 (não guardar número/senha aqui).

## Preparar o celular
1. App da 99 atualizado (≥ 6.57.8), login com a conta de teste.
2. Fake GPS em Goiânia (a loja de teste fica em Av. T-2, 1922, Setor Bueno, Goiânia).
3. Endereço de entrega (ao lado da foto) perto da loja: Av. T-2, 1922, Setor Bueno, Goiânia - GO.
4. Buscar a loja pelo nome inteiro: **Delivery Pet**. A loja precisa estar aberta.

⚠️ A loja de teste está ligada à Delivery Pet real: cada pedido baixa estoque de verdade. Usar itens baratos e
cancelar sempre pelo Gestor (devolve o estoque). Ao final, eu limpo os pedidos de teste.

## Cenários (o Claude acompanha cada um no banco)
| # | Entrega | Pagamento | O que fazer | O que conferir no Gestor |
|---|---|---|---|---|
| 1 | da loja | online | 2 itens + observação | entra "pago"; itens, valores, frete, endereço, observação, nº do pedido |
| 2 | da loja | dinheiro | 1 item, pedir troco | entra "pendente"; troco |
| 3 | da 99 | online | 1 item | entra "pago"; pronto → a 99 chama o entregador |
| 4 | qualquer | online | cliente cancela ANTES de a loja confirmar | pedido cancelado no Gestor, estoque devolvido |
| 5 | qualquer | online | cliente pede cancelamento DEPOIS de confirmado | aviso de pedido de cancelamento chega; aceitar/recusar |
| 6 | qualquer | online | depois de entregue, cliente pede reembolso | aviso de reembolso chega; aceitar/recusar |
| 7 | qualquer | online | usar cupom ou item com oferta, se aparecer | desconto separado entre 99 e loja |
| 8 | qualquer | qualquer | loja cancela no Gestor escolhendo "Item em falta" | a 99 recebe o motivo 1010 |

Trocar entre "entrega da loja" e "entrega da 99": merchant.99app.com › Lojas › Configurações › Configurações de
entrega. Mexer na configuração derruba o token da loja; o banco renova sozinho em até 5 min.

## Resultado (12/11)
- Online: OK (2 pedidos; R$ 0,99 de taxa de serviço fica com a 99, fora do total da loja).
- Dinheiro: o app não oferece; validado pelo portal (entrega 99 → "pago").
- Desconto: OK. Preço promocional do Gestor vai como oferta da loja; cupom da 99 fica em incentivo_promocional_ifood
  (repasse da plataforma) sem o cupom de frete quando a entrega é da 99.
- Observação: o app não tem o campo; validada pelos pedidos do portal.
- Cancelamento pelo cliente (antes, depois de confirmado e depois de pronto): a 99 cancela direto (901); Gestor
  cancela e devolve estoque. O fluxo "cliente pede, loja aprova" não acontece no sandbox.
- Bugs achados e corrigidos: telefone compartilhado da 99 derrubava o 2º cliente (trigger clientes_99food_telefone_compartilhado);
  token derrubado perdia confirmação/cancelamento (food99_garantir_acoes); repasse somava cupom de frete; desconto do pedido somava frete.
- Pendente (melhoria): gravar quem cancelou (901 cliente / 961 99 / 971-981 entregador) consultando o pedido na 99.
