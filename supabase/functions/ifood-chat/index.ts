// iFood — robô de mensagens no chat do pedido (Separador / mercado-pet).
//
// O chat do Separador é Sendbird: o Separador pede ao iFood uma chave de
// chat (bff v1/chat/{merchantId}/token), cria a conversa do pedido
// (POST bff v1/chat/{orderId} {customerId}) e manda pelo SDK do Sendbird
// (userId = merchantId). O acesso ao bff é o login do Separador (Keycloak
// partners, client "app-separador", refresh token "Offline" de 48 h que se
// renova a cada uso) — guardado em ifood_chat_conexoes, só o servidor lê.
//
// Ações (POST JSON):
//   conectar  {codigo, refresh_token}  — vem da página /conectar-ifood do site
//   processar                          — cron (header x-cron-secret): renova o
//                                        acesso e manda a fila ifood_chat_envios
//
// Nunca mandar site, cupom ou número da loja no chat (contrato do iFood).
import { createClient } from "jsr:@supabase/supabase-js@2";
import SendbirdChat from "npm:@sendbird/chat@4.22.17";
import { GroupChannelModule } from "npm:@sendbird/chat@4.22.17/groupChannel";

const IFOOD_ID = "d4811153-e210-47b0-b910-ee0440914f60";
const KEYCLOAK = "https://partners-auth.ifood.com.br/realms/partners/protocol/openid-connect/token";
const CLIENT_ID = "app-separador";
const BFF = "https://separador.ifood.com.br/bff/";
const SENDBIRD_APP = "EF74AA6B-497E-4F58-ADF3-75E76BAE9D37";
const ORIGENS = ["https://deliverypetexpress.com.br", "https://www.deliverypetexpress.com.br", "http://localhost:3000"];

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

function cors(req: Request) {
  const o = req.headers.get("Origin") ?? "";
  return {
    "Access-Control-Allow-Origin": ORIGENS.includes(o) ? o : ORIGENS[0],
    "Access-Control-Allow-Headers": "content-type, x-cron-secret",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

type Conexao = {
  empresa_id: string; merchant_id: string; refresh_token: string; refresh_expira_em: string | null;
  access_token: string | null; access_expira_em: string | null;
  chat_token: string | null; chat_expira_em: string | null;
  enviar_mensagens: boolean; pedido_teste: string | null; renovado_em: string | null;
};

const expDoJwt = (t: string): string | null => {
  try {
    const p = JSON.parse(atob(t.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
    return p.exp ? new Date(p.exp * 1000).toISOString() : null;
  } catch { return null; }
};

class Desconectado extends Error {}

async function renovar(refresh: string) {
  const r = await fetch(KEYCLOAK, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", client_id: CLIENT_ID, refresh_token: refresh }),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || !j.access_token) {
    const msg = `${r.status} ${j.error ?? ""} ${j.error_description ?? ""}`.trim();
    if (r.status === 400 || r.status === 401) throw new Desconectado(msg);
    throw new Error(msg);
  }
  return {
    access_token: j.access_token as string,
    access_expira_em: new Date(Date.now() + (j.expires_in ?? 3600) * 1000).toISOString(),
    refresh_token: (j.refresh_token ?? refresh) as string,
    refresh_expira_em: expDoJwt(j.refresh_token ?? refresh),
  };
}

async function bff(c: Conexao, caminho: string, init: RequestInit = {}) {
  const r = await fetch(BFF + caminho, {
    ...init,
    headers: { Authorization: `Bearer ${c.access_token}`, "content-type": "application/json", ...(init.headers ?? {}) },
  });
  const texto = await r.text();
  let j: any = null;
  try { j = JSON.parse(texto); } catch { /* */ }
  if (!r.ok) throw new Error(`bff ${caminho.split("/").slice(0, 3).join("/")} ${r.status} ${texto.slice(0, 200)}`);
  return j;
}

// Garante acesso válido; renova se faltar < 30 min ou se a última renovação
// tem mais de 6 h (mantém a sessão "offline" de 48 h viva).
async function garantirAcesso(c: Conexao): Promise<Conexao> {
  const falta = c.access_expira_em ? new Date(c.access_expira_em).getTime() - Date.now() : -1;
  const velho = !c.renovado_em || Date.now() - new Date(c.renovado_em).getTime() > 6 * 3600e3;
  if (c.access_token && falta > 30 * 60e3 && !velho) return c;
  const n = await renovar(c.refresh_token);
  const novo = { ...c, ...n, renovado_em: new Date().toISOString() };
  await admin.from("ifood_chat_conexoes").update({
    access_token: n.access_token, access_expira_em: n.access_expira_em,
    refresh_token: n.refresh_token, refresh_expira_em: n.refresh_expira_em,
    renovado_em: novo.renovado_em, ultimo_erro: null, aviso_desconectado_em: null,
  }).eq("empresa_id", c.empresa_id);
  return novo;
}

async function garantirChatToken(c: Conexao): Promise<Conexao> {
  const falta = c.chat_expira_em ? new Date(c.chat_expira_em).getTime() - Date.now() : -1;
  if (c.chat_token && falta > 3600e3) return c;
  const j = await bff(c, `v1/chat/${c.merchant_id}/token`);
  const token = j?.data?.token;
  if (!token) throw new Error("chave do chat não veio");
  const exp = j?.data?.expiresAt ? new Date(j.data.expiresAt).toISOString() : null;
  await admin.from("ifood_chat_conexoes").update({ chat_token: token, chat_expira_em: exp }).eq("empresa_id", c.empresa_id);
  return { ...c, chat_token: token, chat_expira_em: exp };
}

function primeiroNome(nome: string | null | undefined) {
  const n = (nome ?? "").trim().split(/\s+/)[0] ?? "";
  if (!n || /^cliente$/i.test(n)) return "";
  return n.charAt(0).toUpperCase() + n.slice(1).toLowerCase();
}

function montarTexto(tipo: string, nome: string, retirada: boolean, pagarNaEntrega: boolean) {
  const ola = nome ? `Olá, ${nome}!` : "Olá!";
  if (tipo === "recebido") {
    return [
      `🛎️ ${ola} 👋`,
      "Recebemos o seu pedido e ele já está sendo separado com carinho! 🐾😁",
      retirada
        ? "Pode deixar um contato, para te avisarmos quando estiver pronto, por favor?"
        : "Pode deixar um contato, para facilitar a entrega, por favor?",
      retirada ? "" : "⚠️ Você será avisado assim que o seu pedido sair para entrega. 🛵",
      "💢 Mensagem enviada automaticamente. 💢",
    ].filter(Boolean).join("\n\n");
  }
  return [
    "Ebaa! 🤩 Seu pedido acabou de sair para entrega 😊🙌",
    "Nosso entregador já está a caminho e logo chegará até você 🛵💨",
    "Pode deixar um contato para facilitar a entrega, caso precise? Obrigado!",
    pagarNaEntrega
      ? "⚠️ Por favor, como o pagamento será na entrega, deixe o cartão ou o dinheiro em mãos. Isso ajuda o entregador a agilizar a sua entrega e as próximas. 😊"
      : "",
  ].filter(Boolean).join("\n\n");
}

async function enviarNoChat(c: Conexao, orderId: string, customerId: string, texto: string) {
  const sb = SendbirdChat.init({
    appId: SENDBIRD_APP,
    modules: [new GroupChannelModule()],
    localCacheEnabled: false,
    appStateToggleEnabled: false,
  }) as any;
  await sb.connect(c.merchant_id, c.chat_token);
  try {
    const url = `sendbird_gc_cm_${orderId}_${c.merchant_id}`;
    let canal;
    try {
      canal = await sb.groupChannel.getChannel(url);
    } catch {
      await bff(c, `v1/chat/${orderId}`, { method: "POST", body: JSON.stringify({ customerId }) });
      canal = await sb.groupChannel.getChannel(url);
    }
    const msg: any = await new Promise((ok, falha) => {
      canal.sendUserMessage({ message: texto }).onSucceeded(ok).onFailed(falha);
    });
    return msg?.messageId ?? null;
  } finally {
    try { await sb.disconnect(); } catch { /* */ }
  }
}

async function processar() {
  const { data: conexoes } = await admin.from("ifood_chat_conexoes").select("*");
  const resultado: any[] = [];
  for (const c0 of (conexoes ?? []) as Conexao[]) {
    let c = c0;
    try {
      c = await garantirAcesso(c);
    } catch (e) {
      const desconectou = e instanceof Desconectado;
      await admin.from("ifood_chat_conexoes").update({
        ultimo_erro: `${desconectou ? "DESCONECTADO: " : ""}${(e as Error).message}`.slice(0, 500),
        ultimo_erro_em: new Date().toISOString(),
      }).eq("empresa_id", c.empresa_id);
      resultado.push({ empresa: c.empresa_id, erro: (e as Error).message });
      continue;
    }

    const { data: fila } = await admin.from("ifood_chat_envios")
      .select("id, order_id, tipo, tentativas, created_at")
      .eq("empresa_id", c.empresa_id).eq("status", "pendente")
      .lt("created_at", new Date(Date.now() - 15e3).toISOString())
      .order("created_at").limit(10);

    for (const item of fila ?? []) {
      const marcar = (campos: Record<string, unknown>) =>
        admin.from("ifood_chat_envios").update(campos).eq("id", item.id);

      const teste = c.pedido_teste && c.pedido_teste === item.order_id;
      if (!c.enviar_mensagens && !teste) {
        await marcar({ status: "ignorado", motivo: "robô desligado" });
        continue;
      }
      // Muito tempo na fila = perdeu o momento; não manda atrasado.
      if (Date.now() - new Date(item.created_at).getTime() > 45 * 60e3) {
        await marcar({ status: "ignorado", motivo: "passou do momento" });
        continue;
      }

      const { data: mp } = await admin.from("marketplace_pedidos")
        .select("id, pedido_id, pedidos!inner(id, cliente_id, status, status_pagamento, tipo_entrega_marketplace, clientes(nome, id_externo_ifood))")
        .eq("marketplace_id", IFOOD_ID).eq("marketplace_order_id", item.order_id).maybeSingle();
      const ped: any = (mp as any)?.pedidos;
      if (!ped) {
        // pedido ainda não entrou no Gestor — tenta de novo no próximo minuto (até 10 min)
        if (Date.now() - new Date(item.created_at).getTime() > 10 * 60e3) {
          await marcar({ status: "ignorado", motivo: "pedido não entrou no Gestor" });
        }
        continue;
      }
      const cli = ped.clientes;
      const retirada = ped.tipo_entrega_marketplace === "TAKEOUT";
      if (item.tipo === "saiu" && retirada) {
        await marcar({ status: "ignorado", motivo: "retirada", marketplace_pedido_id: mp!.id, cliente_id: ped.cliente_id });
        continue;
      }
      if (["cancelado"].includes(ped.status)) {
        await marcar({ status: "ignorado", motivo: "pedido cancelado", marketplace_pedido_id: mp!.id });
        continue;
      }
      if (!cli?.id_externo_ifood) {
        await marcar({ status: "erro", motivo: "cliente sem código do iFood", marketplace_pedido_id: mp!.id });
        continue;
      }
      const texto = montarTexto(item.tipo, primeiroNome(cli.nome), retirada, ped.status_pagamento !== "pago");
      try {
        c = await garantirChatToken(c);
        await enviarNoChat(c, item.order_id, cli.id_externo_ifood, texto);
        await marcar({
          status: "enviado", enviado_em: new Date().toISOString(), texto, motivo: null,
          marketplace_pedido_id: mp!.id, cliente_id: ped.cliente_id, tentativas: item.tentativas + 1,
        });
        resultado.push({ order: item.order_id, tipo: item.tipo, ok: true });
      } catch (e) {
        const t = item.tentativas + 1;
        await marcar({
          status: t >= 3 ? "erro" : "pendente", tentativas: t, motivo: String((e as Error).message ?? e).slice(0, 500),
          marketplace_pedido_id: mp!.id, cliente_id: ped.cliente_id,
        });
        // chave do chat pode ter vencido antes da hora
        await admin.from("ifood_chat_conexoes").update({ chat_token: null }).eq("empresa_id", c.empresa_id);
        c = { ...c, chat_token: null };
        resultado.push({ order: item.order_id, tipo: item.tipo, erro: (e as Error).message });
      }
    }
  }
  return resultado;
}

async function conectar(body: any) {
  const codigo = String(body?.codigo ?? "").trim();
  const refresh = String(body?.refresh_token ?? "").trim();
  if (!codigo || !refresh) return { status: 400, body: { erro: "faltou o código ou o acesso" } };

  const { data: cod } = await admin.from("ifood_chat_codigos").select("*").eq("codigo", codigo).maybeSingle();
  if (!cod || cod.usado_em || new Date(cod.expira_em).getTime() < Date.now()) {
    return { status: 400, body: { erro: "código vencido ou já usado — peça um novo" } };
  }
  const { data: cfg } = await admin.from("empresa_marketplace_config")
    .select("id_loja_plataforma").eq("empresa_id", cod.empresa_id).eq("marketplace_id", IFOOD_ID).maybeSingle();
  if (!cfg?.id_loja_plataforma) return { status: 400, body: { erro: "iFood não configurado nesta loja" } };

  let n;
  try { n = await renovar(refresh); } catch (e) {
    return { status: 400, body: { erro: "o iFood não aceitou o acesso: " + (e as Error).message } };
  }
  const base: Conexao = {
    empresa_id: cod.empresa_id, merchant_id: cfg.id_loja_plataforma, ...n,
    chat_token: null, chat_expira_em: null, enviar_mensagens: false, pedido_teste: null,
    renovado_em: new Date().toISOString(),
  };
  // Confere que esse login enxerga o chat desta loja
  let c: Conexao;
  try {
    c = await garantirChatTokenSemSalvar(base);
  } catch (e) {
    return { status: 400, body: { erro: "esse login não abre o chat desta loja: " + (e as Error).message } };
  }
  const { error } = await admin.from("ifood_chat_conexoes").upsert({
    empresa_id: c.empresa_id, merchant_id: c.merchant_id,
    refresh_token: c.refresh_token, refresh_expira_em: c.refresh_expira_em,
    access_token: c.access_token, access_expira_em: c.access_expira_em,
    chat_token: c.chat_token, chat_expira_em: c.chat_expira_em,
    conectado_em: new Date().toISOString(), renovado_em: c.renovado_em,
    ultimo_erro: null, ultimo_erro_em: null, aviso_desconectado_em: null,
  }, { onConflict: "empresa_id" });
  if (error) return { status: 500, body: { erro: error.message } };
  await admin.from("ifood_chat_codigos").update({ usado_em: new Date().toISOString() }).eq("codigo", codigo);
  return { status: 200, body: { ok: true } };
}

async function garantirChatTokenSemSalvar(c: Conexao): Promise<Conexao> {
  const j = await bff(c, `v1/chat/${c.merchant_id}/token`);
  const token = j?.data?.token;
  if (!token) throw new Error("chave do chat não veio");
  return { ...c, chat_token: token, chat_expira_em: j?.data?.expiresAt ? new Date(j.data.expiresAt).toISOString() : null };
}

Deno.serve(async (req) => {
  const h = cors(req);
  if (req.method === "OPTIONS") return new Response("ok", { headers: h });
  const resp = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...h, "Content-Type": "application/json" } });

  const body = await req.json().catch(() => ({}));
  const acao = String(body?.acao ?? "");

  if (acao === "conectar") {
    const r = await conectar(body);
    return resp(r.body, r.status);
  }

  if (acao === "processar") {
    const { data: seg } = await admin.from("ifood_chat_parametros").select("valor").eq("chave", "cron_secret").maybeSingle();
    if (!seg?.valor || req.headers.get("x-cron-secret") !== seg.valor) return resp({ erro: "não autorizado" }, 401);
    try {
      return resp({ ok: true, resultado: await processar() });
    } catch (e) {
      return resp({ erro: (e as Error).message }, 500);
    }
  }

  return resp({ erro: "ação desconhecida" }, 400);
});
