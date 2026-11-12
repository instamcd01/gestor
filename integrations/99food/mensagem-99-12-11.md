Olá, tudo bem? Aqui é o Lucas, da Delivery Pet (integração 99Compras, app "Gestor Delivery Pet", app_id 5764607796526450761).

A integração está pronta no sandbox: catálogo com 667 itens ativos, estoque sincronizado, loja de teste aberta e pedidos testados nos dois modos de entrega (pela 99 e pela loja), com confirmar, pronto, saiu para entrega, entregue e cancelamento pela loja funcionando. Queremos fazer a call de validação o quanto antes. Hoje mesmo, se tiverem horário.

Pra fechar, preciso de 4 coisas:

1. Uma conta de teste do C-App, pra testarmos pagamento online e o cancelamento/reembolso pedido pelo cliente antes da call.
2. Loja de produção: a Delivery Pet tem cadastro de lojista, mas a loja não está ativa. Com quem do comercial eu falo pra ativar (contrato) e já deixar pronta pra vincular ao nosso app de produção?
3. Na carga inicial do catálogo em produção (~670 itens), o limite de 1 envio a cada 4 horas vale? Mandamos em lotes de 50, porque lote grande dava erro no sandbox. Conseguem liberar a janela como fizeram no teste?
4. O aviso uploadGroceryMenuTaskStatus chega com uma assinatura que não bate com MD5(corpo + app_secret). Os avisos de pedido batem. Esse aviso é assinado de outro jeito?

Também temos uma tarefa de catálogo travada desde 01/09 (taskID 5764663429895686998). Se puderem cancelar, agradeço.

Obrigado!
