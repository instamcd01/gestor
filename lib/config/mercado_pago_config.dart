/// Client ID da aplicação Mercado Pago DA PLATAFORMA (uma só, não muda por
/// loja) — aplicação "Delivery Pet MP" no painel do Mercado Pago
/// (developers.mercadopago.com/panel/app/8162106481494061). client_id não
/// é segredo (vai exposto na própria URL de autorização); o client_secret
/// fica só no servidor do site (env var), nunca aqui no app.
const String kMercadoPagoClientId = '8162106481494061';

/// URL base do site (gestor-loja) — usada pra montar o redirect_uri do OAuth
/// (`$kSiteBaseUrl/mp/callback`) e pra chamar as rotas de API dele que só o
/// site sabe fazer (ex: estornar pagamento, que precisa do access_token do
/// Mercado Pago, guardado só lá). Precisa bater exatamente com a URL de
/// redirecionamento cadastrada na aplicação do Mercado Pago.
const String kSiteBaseUrl = 'https://deliverypetexpress.com.br';
