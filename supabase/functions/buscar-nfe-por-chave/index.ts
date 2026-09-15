// Busca o XML de uma NF-e pela chave de acesso de 44 dígitos — resolve o
// caso de fornecedor que só manda a DANFE impressa/PDF, sem XML anexo
// (achado real: MixPet manda só PDF). Client (Flutter) nunca fala com a
// Sefaz nem com o certificado direto — só manda a chave pra essa função,
// que repassa (sem certificado nenhum nessa etapa, é um POST simples)
// pro serviço `nfe-sefaz-service` (Node.js, hospedado no Easypanel, mesma
// VPS do n8n/gestor-loja), que é quem de fato fala mTLS com a Sefaz.
//
// Histórico: essa função já tentou 3 formas diferentes de falar com a
// Sefaz direto — API paga da Meu Danfe (abandonada por inconsistência de
// confiabilidade), node HTTP Request do n8n (bug documentado do próprio
// n8n, chegou a vazar o certificado no log de erro) e `Deno.createHttpClient`
// direto aqui na edge function (Deno usa `rustls`, que tem incompatibilidade
// conhecida e SEM correção contra o servidor IIS antigo da Sefaz —
// "Connection reset by peer" sempre, ver rustls/rustls#1999). Node usa
// OpenSSL nativo pro `https`, mesma família que funcionou no teste manual
// com `openssl s_client` — por isso o mTLS de verdade agora mora num
// serviço Node separado, e essa função virou só um proxy fino.
//
// Certificado/chave continuam só no Supabase Vault, mas agora só o
// `nfe-sefaz-service` os lê — essa função só lê o token compartilhado
// (`nfe_sefaz_service_token`) usado pra autenticar a chamada entre os dois.

import { createClient } from "jsr:@supabase/supabase-js@2";

const NFE_SERVICE_URL = "https://deliverypet-nfe-sefaz-service.pdwq3u.easypanel.host/buscar-nfe-por-chave";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Defesa contra qualquer erro que por algum motivo acabe incluindo
// material sensível no texto (mesma lição aprendida com o bug do n8n —
// nunca repassar mensagem de erro crua sem checar).
function sanitizarErro(texto: unknown): string {
  const s = String(texto ?? "");
  if (/-----BEGIN [A-Z ]+-----/.test(s)) {
    return "Erro de conexão (detalhe omitido por segurança).";
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

    const serviceToken = await obterSegredo("nfe_sefaz_service_token");

    const resposta = await fetch(NFE_SERVICE_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Service-Token": serviceToken,
      },
      body: JSON.stringify({ chave: chaveLimpa }),
    });

    const dados = await resposta.json();
    return jsonResponse(dados, resposta.status);
  } catch (e) {
    return jsonResponse({ ok: false, erro: "erro_interno", mensagem: sanitizarErro(e instanceof Error ? e.message : e) }, 500);
  }
});
