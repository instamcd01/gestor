// Busca o XML de uma NF-e pela chave de acesso de 44 dígitos — resolve o
// caso de fornecedor que só manda a DANFE impressa/PDF, sem XML anexo
// (achado real: MixPet manda só PDF). Consulta direto o webservice oficial
// `NFeDistribuicaoDFe` da Sefaz (Ambiente Nacional), autenticando com o
// certificado digital A1 da empresa via mTLS — client (Flutter) nunca fala
// com a Sefaz direto, só manda a chave pra essa função e recebe de volta
// `{ok, xml}`, que cai no mesmo importador que já existe
// (NfeXmlParser/_processarXml em importar_nota_fiscal_screen.dart).
//
// Histórico: usava a API paga da Meu Danfe (meudanfe.com.br), depois um
// workflow n8n fazendo essa mesma consulta — ambos abandonados: a Meu Danfe
// por inconsistência de confiabilidade encontrada em uso real, o n8n por um
// bug documentado do próprio projeto (node HTTP Request trava — "Converting
// circular structure to JSON" — ao usar certificado cliente e chegou a
// vazar o certificado/chave no próprio log de erro). Rodar aqui, em Deno
// (runtime da edge function, `Deno.createHttpClient` com suporte nativo a
// mTLS desde a v2), evita as duas armadilhas.
//
// Certificado/chave (PEM, sem senha) ficam só no Supabase Vault
// (`nfe_certificado_cert_pem`/`nfe_certificado_key_pem`), lidos via
// `obter_segredo` (mesma função SECURITY DEFINER já usada pra
// `meudanfe_api_key` antes) — nunca tocam o client nem aparecem em log.
//
// Endpoint/schema confirmados por teste real (15/09/2026, openssl s_client
// direto): `versao="1.01"` no `distDFeInt` (não a mais recente que existe
// pra outros serviços da NFe — esse webservice específico ainda valida
// contra 1.01, testado empiricamente após rejeição com versões mais novas).

import { createClient } from "jsr:@supabase/supabase-js@2";

const SEFAZ_URL = "https://www1.nfe.fazenda.gov.br/NFeDistribuicaoDFe/NFeDistribuicaoDFe.asmx";
const SOAP_ACTION = "http://www.portalfiscal.inf.br/nfe/wsdl/NFeDistribuicaoDFe/nfeDistDFeInteresse";

// Único empresa hoje (Delivery Pet) — se virar multi-tenant, buscar
// CNPJ/estado da tabela `empresas` em vez de hardcode.
const CNPJ = "52816710000198";
const C_UF_AUTOR = "33"; // RJ
const TP_AMB = "1"; // 1 = produção, 2 = homologação

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Defesa contra qualquer erro que por algum motivo acabe incluindo o
// certificado/chave no texto (mesma lição aprendida com o bug do n8n —
// nunca repassar mensagem de erro crua sem checar).
function sanitizarErro(texto: unknown): string {
  const s = String(texto ?? "");
  if (/-----BEGIN [A-Z ]+-----/.test(s)) {
    return "Erro de conexão com a Sefaz (detalhe omitido por segurança).";
  }
  return s.slice(0, 500);
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function obterSegredo(nome: string): Promise<string> {
  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data, error } = await supabaseAdmin.rpc("obter_segredo", { nome });
  if (error || !data) {
    throw new Error(`Segredo "${nome}" não configurado no Vault.`);
  }
  return data as string;
}

function montarSoap(chave: string): string {
  return `<?xml version="1.0" encoding="utf-8"?>
<soap12:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap12="http://www.w3.org/2003/05/soap-envelope">
  <soap12:Body>
    <nfeDistDFeInteresse xmlns="http://www.portalfiscal.inf.br/nfe/wsdl/NFeDistribuicaoDFe">
      <nfeDadosMsg>
        <distDFeInt xmlns="http://www.portalfiscal.inf.br/nfe" versao="1.01">
          <tpAmb>${TP_AMB}</tpAmb>
          <cUFAutor>${C_UF_AUTOR}</cUFAutor>
          <CNPJ>${CNPJ}</CNPJ>
          <consChNFe>
            <chNFe>${chave}</chNFe>
          </consChNFe>
        </distDFeInt>
      </nfeDadosMsg>
    </nfeDistDFeInteresse>
  </soap12:Body>
</soap12:Envelope>`;
}

function extrairTag(xml: string, tag: string): string | null {
  const m = xml.match(new RegExp(`<${tag}[^>]*>([^<]*)</${tag}>`, "i"));
  return m ? m[1] : null;
}

async function descompactarDocZip(base64: string): Promise<string> {
  const bin = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
  const ds = new DecompressionStream("gzip");
  const stream = new Blob([bin]).stream().pipeThrough(ds);
  const buffer = await new Response(stream).arrayBuffer();
  return new TextDecoder("utf-8").decode(buffer);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  let httpClient: Deno.HttpClient | null = null;
  try {
    const { chave } = await req.json();
    const chaveLimpa = String(chave ?? "").replace(/\D/g, "");
    if (chaveLimpa.length !== 44) {
      return jsonResponse({ ok: false, erro: "chave_invalida", mensagem: "Chave de acesso precisa ter 44 dígitos." }, 400);
    }

    const [cert, key] = await Promise.all([
      obterSegredo("nfe_certificado_cert_pem"),
      obterSegredo("nfe_certificado_key_pem"),
    ]);

    // O endpoint da Sefaz só aceita HTTP/1.1 (rejeita a tentativa padrão
    // do Deno de negociar HTTP/2) — testado empiricamente (15/09/2026).
    httpClient = Deno.createHttpClient({ cert, key, http1: true, http2: false });

    const resposta = await fetch(SEFAZ_URL, {
      method: "POST",
      client: httpClient,
      headers: {
        "Content-Type": `application/soap+xml; charset=utf-8; action="${SOAP_ACTION}"`,
      },
      body: montarSoap(chaveLimpa),
    });

    const corpo = await resposta.text();

    if (!resposta.ok) {
      throw new Error(`Sefaz retornou HTTP ${resposta.status}.`);
    }

    const cStat = extrairTag(corpo, "cStat");
    const xMotivo = extrairTag(corpo, "xMotivo");
    const docZipMatch = corpo.match(/<docZip[^>]*schema="([^"]*)"[^>]*>([^<]*)<\/docZip>/i);

    if (!docZipMatch) {
      const erro = cStat === "137" ? "nao_encontrada" : "falha_busca";
      const status = cStat === "137" ? 404 : 502;
      return jsonResponse({
        ok: false,
        erro,
        mensagem: xMotivo || "NF-e não encontrada na Sefaz pra essa chave de acesso, ou nenhum documento retornado.",
        cStat,
      }, status);
    }

    const xml = await descompactarDocZip(docZipMatch[2]);
    return jsonResponse({ ok: true, xml });
  } catch (e) {
    return jsonResponse({ ok: false, erro: "erro_interno", mensagem: sanitizarErro(e instanceof Error ? e.message : e) }, 500);
  } finally {
    httpClient?.close();
  }
});
