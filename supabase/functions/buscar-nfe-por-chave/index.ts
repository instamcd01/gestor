// Busca o XML de uma NF-e pela chave de acesso de 44 dígitos — resolve o
// caso de fornecedor que só manda a DANFE impressa/PDF, sem XML anexo
// (achado real: MixPet manda só PDF). Client (Flutter) nunca fala com a
// Sefaz direto: só manda a chave de acesso pra essa edge function, que
// repassa pro workflow n8n "NFe - Buscar por Chave (Sefaz DistribuicaoDFe)"
// e devolve o XML pronto, que cai no mesmo importador que já existe
// (NfeXmlParser/_processarXml em importar_nota_fiscal_screen.dart).
//
// Histórico: antes chamava a API paga da Meu Danfe (meudanfe.com.br)
// direto daqui. Trocado (2026-09-15) por consulta própria ao webservice
// oficial NFeDistribuicaoDFe da Sefaz (certificado digital A1 da empresa),
// orquestrada pelo n8n — decisão de abandonar a Meu Danfe por
// inconsistência de confiabilidade encontrada em uso real. O n8n cuida do
// SOAP + certificado + descompactação do docZip (gzip+base64); essa função
// só repassa a chave e devolve `{ok, xml}` no mesmo contrato de antes, pra
// não precisar mudar nada do lado do app.

const N8N_WEBHOOK_URL = "https://n8n.lukz.com.br/webhook/nfe-buscar-por-chave-sefaz";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { chave } = await req.json();
    const chaveLimpa = String(chave ?? "").replace(/\D/g, "");
    if (chaveLimpa.length !== 44) {
      return jsonResponse({ ok: false, erro: "chave_invalida", mensagem: "Chave de acesso precisa ter 44 dígitos." }, 400);
    }

    const resposta = await fetch(N8N_WEBHOOK_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ chave: chaveLimpa }),
    });

    if (!resposta.ok) {
      throw new Error(`Workflow n8n retornou ${resposta.status} ao buscar a NF-e.`);
    }

    const dados = await resposta.json();
    if (dados.ok !== true) {
      const status = dados.erro === "nao_encontrada" ? 404 : 502;
      return jsonResponse(dados, status);
    }

    return jsonResponse({ ok: true, xml: dados.xml });
  } catch (e) {
    return jsonResponse({ ok: false, erro: "erro_interno", mensagem: String(e instanceof Error ? e.message : e) }, 500);
  }
});
