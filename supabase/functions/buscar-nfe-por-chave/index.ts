// Busca o XML de uma NF-e/CT-e pela chave de acesso de 44 dígitos, usando a
// API do Meu Danfe (meudanfe.com.br) — resolve o caso de fornecedor que só
// manda a DANFE impressa/PDF, sem XML anexo (achado real: MixPet). A Api-Key
// do Meu Danfe fica só aqui (Supabase Vault), nunca no app Flutter — client
// nunca vê a chave de API, só manda a chave de acesso da nota e recebe o XML
// de volta pronto pra cair no mesmo importador que já existe
// (NfeXmlParser/_processarXml em importar_nota_fiscal_screen.dart).
//
// Fluxo da API do Meu Danfe (documentação em meudanfe.com.br/documentacao.php):
//   1. PUT /fd/add/{chave} — pede pra buscar/adicionar a nota na área do
//      cliente. Resposta tem `status`: WAITING/SEARCHING (ainda buscando,
//      precisa tentar de novo) | OK (achou) | NOT_FOUND | ERROR.
//   2. GET /fd/get/xml/{chave} — só depois do status OK, baixa o XML de
//      verdade (campo `data` da resposta).
// Custo: R$0,03 por chave nova (grátis se já buscada antes, fica salva na
// área do cliente do Meu Danfe).

import { createClient } from "jsr:@supabase/supabase-js@2";

const MEUDANFE_BASE = "https://api.meudanfe.com.br/v2";
const MAX_TENTATIVAS = 8;
const ESPERA_ENTRE_TENTATIVAS_MS = 2000;

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

async function obterApiKeyMeuDanfe(): Promise<string> {
  // O schema `vault` não é exposto pela API REST (PostgREST só expõe
  // schemas configurados, nunca `vault`) — por isso a leitura passa por uma
  // função `public.obter_segredo` (SECURITY DEFINER, só service_role pode
  // chamar) em vez de consultar `vault.decrypted_secrets` direto.
  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data, error } = await supabaseAdmin.rpc("obter_segredo", { nome: "meudanfe_api_key" });

  if (error || !data) {
    throw new Error("Api-Key do Meu Danfe não configurada (vault: meudanfe_api_key).");
  }
  return data as string;
}

async function adicionarNota(chave: string, apiKey: string) {
  const resposta = await fetch(`${MEUDANFE_BASE}/fd/add/${chave}`, {
    method: "PUT",
    headers: { "Api-Key": apiKey },
  });
  if (!resposta.ok) {
    throw new Error(`Meu Danfe retornou ${resposta.status} ao adicionar a chave.`);
  }
  return (await resposta.json()) as { status: string; statusMessage: string };
}

async function baixarXml(chave: string, apiKey: string) {
  const resposta = await fetch(`${MEUDANFE_BASE}/fd/get/xml/${chave}`, {
    method: "GET",
    headers: { "Api-Key": apiKey },
  });
  if (!resposta.ok) {
    throw new Error(`Meu Danfe retornou ${resposta.status} ao baixar o XML.`);
  }
  return (await resposta.json()) as { name: string; type: string; format: string; data: string };
}

function aguardar(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
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

    const apiKey = await obterApiKeyMeuDanfe();

    let statusFinal: string | null = null;
    let statusMessage = "";
    for (let tentativa = 0; tentativa < MAX_TENTATIVAS; tentativa++) {
      const resultado = await adicionarNota(chaveLimpa, apiKey);
      statusFinal = resultado.status;
      statusMessage = resultado.statusMessage;
      if (statusFinal !== "WAITING" && statusFinal !== "SEARCHING") break;
      await aguardar(ESPERA_ENTRE_TENTATIVAS_MS);
    }

    if (statusFinal === "NOT_FOUND") {
      return jsonResponse({
        ok: false,
        erro: "nao_encontrada",
        mensagem: "NF-e não encontrada na Receita pra essa chave de acesso. Confira se digitou/escaneou certo.",
      }, 404);
    }
    if (statusFinal !== "OK") {
      return jsonResponse({
        ok: false,
        erro: "falha_busca",
        mensagem: statusMessage || "Não foi possível confirmar a busca a tempo — tente de novo em alguns segundos.",
      }, 502);
    }

    const xml = await baixarXml(chaveLimpa, apiKey);
    return jsonResponse({ ok: true, xml: xml.data, tipo: xml.type });
  } catch (e) {
    return jsonResponse({ ok: false, erro: "erro_interno", mensagem: String(e instanceof Error ? e.message : e) }, 500);
  }
});
