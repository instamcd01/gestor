// iFood — Portal do Parceiro: guarda e renova a sessão do Portal e serve a
// fila do robô de navegador (pedido mínimo, pré-configuração do feriado).
//
// Sessão: Keycloak partners, client "partner-portal". O refresh dura ~5 h
// sem uso, então o cron renova a cada 2 h (ifood_portal_disparar_manter).
// Só o servidor lê ifood_portal_conexoes.
//
// Ações (POST JSON):
//   conectar        {codigo, refresh_token}   — página /ifood/conectar do site (favorito no Portal)
//   manter                                   — cron (x-cron-secret)
//   robo_tarefas                             — robô (x-robo-secret): pega as tarefas vencidas
//   robo_sessao     {empresa_id}             — robô: sessão renovada pra colocar no navegador
//   robo_devolver   {empresa_id, refresh_token, access_token?, id_token?} — robô: sessão depois do uso
//   robo_resultado  {id, ok, resultado?, erro?}
import { createClient } from "jsr:@supabase/supabase-js@2";

const IFOOD_ID = "d4811153-e210-47b0-b910-ee0440914f60";
const KEYCLOAK = "https://partners-auth.ifood.com.br/realms/partners/protocol/openid-connect/token";
const CLIENT_ID = "partner-portal";
const ORIGENS = ["https://deliverypetexpress.com.br", "https://www.deliverypetexpress.com.br", "http://localhost:3000"];

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

function cors(req: Request) {
  const o = req.headers.get("Origin") ?? "";
  return {
    "Access-Control-Allow-Origin": ORIGENS.includes(o) ? o : ORIGENS[0],
    "Access-Control-Allow-Headers": "content-type, x-cron-secret, x-robo-secret",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

const expDoJwt = (t: string | undefined | null): string | null => {
  if (!t) return null;
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
    id_token: (j.id_token ?? null) as string | null,
    session_state: (j.session_state ?? null) as string | null,
    scope: (j.scope ?? "openid profile email merchants profile_permissions") as string,
  };
}

async function parametro(chave: string) {
  const { data } = await admin.from("ifood_portal_parametros").select("valor").eq("chave", chave).maybeSingle();
  return data?.valor ?? null;
}

async function avisar(empresa_id: string, titulo: string, mensagem: string) {
  await admin.from("notificacoes").insert({ empresa_id, tipo: "data_especial", titulo, mensagem, entidade_tipo: "ifood_portal" });
}

async function renovarESalvar(c: any) {
  try {
    const n = await renovar(c.refresh_token);
    await admin.from("ifood_portal_conexoes").update({
      access_token: n.access_token, access_expira_em: n.access_expira_em,
      refresh_token: n.refresh_token, refresh_expira_em: n.refresh_expira_em,
      id_token: n.id_token ?? c.id_token, renovado_em: new Date().toISOString(),
      ultimo_erro: null, ultimo_erro_em: null, aviso_desconectado_em: null,
    }).eq("empresa_id", c.empresa_id);
    return { ...c, ...n, id_token: n.id_token ?? c.id_token };
  } catch (e) {
    const msg = (e as Error).message;
    await admin.from("ifood_portal_conexoes").update({ ultimo_erro: msg, ultimo_erro_em: new Date().toISOString() })
      .eq("empresa_id", c.empresa_id);
    if (e instanceof Desconectado && !c.aviso_desconectado_em) {
      await admin.from("ifood_portal_conexoes").update({ aviso_desconectado_em: new Date().toISOString() }).eq("empresa_id", c.empresa_id);
      await avisar(c.empresa_id, "Robô do Portal iFood desconectado ⚠️",
        "A sessão do Portal do Parceiro caiu. Abra o Portal e clique no favorito \"Conectar robô\" pra religar.");
    }
    throw e;
  }
}

async function conectar(body: any) {
  const codigo = String(body?.codigo ?? "").trim().toUpperCase();
  const refresh = String(body?.refresh_token ?? "").trim();
  if (!codigo || !refresh) return { status: 400, body: { erro: "faltou o código ou o acesso" } };
  const { data: cod } = await admin.from("ifood_portal_codigos").select("*").eq("codigo", codigo).maybeSingle();
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
  const { error } = await admin.from("ifood_portal_conexoes").upsert({
    empresa_id: cod.empresa_id, merchant_id: cfg.id_loja_plataforma,
    refresh_token: n.refresh_token, refresh_expira_em: n.refresh_expira_em,
    access_token: n.access_token, access_expira_em: n.access_expira_em, id_token: n.id_token,
    conectado_em: new Date().toISOString(), renovado_em: new Date().toISOString(),
    ultimo_erro: null, ultimo_erro_em: null, aviso_desconectado_em: null,
  }, { onConflict: "empresa_id" });
  if (error) return { status: 500, body: { erro: error.message } };
  await admin.from("ifood_portal_codigos").update({ usado_em: new Date().toISOString() }).eq("codigo", codigo);
  await admin.rpc("ifood_portal_agendar");
  return { status: 200, body: { ok: true } };
}

async function manter() {
  const { data } = await admin.from("ifood_portal_conexoes").select("*");
  const r: any[] = [];
  for (const c of data ?? []) {
    try { await renovarESalvar(c); r.push({ empresa_id: c.empresa_id, ok: true }); }
    catch (e) { r.push({ empresa_id: c.empresa_id, erro: (e as Error).message }); }
  }
  return r;
}

async function roboTarefas() {
  const agora = new Date().toISOString();
  const { data } = await admin.from("ifood_portal_tarefas").select("*")
    .eq("status", "pendente").lte("executar_em", agora).order("executar_em").limit(5);
  const pegas: any[] = [];
  for (const t of data ?? []) {
    const { data: up } = await admin.from("ifood_portal_tarefas")
      .update({ status: "executando", iniciado_em: agora, tentativas: t.tentativas + 1 })
      .eq("id", t.id).eq("status", "pendente").select().maybeSingle();
    if (up) pegas.push(up);
  }
  // tarefa travada em "executando" há mais de 15 min volta pra fila
  await admin.from("ifood_portal_tarefas").update({ status: "pendente" })
    .eq("status", "executando").lt("iniciado_em", new Date(Date.now() - 15 * 60e3).toISOString());
  return pegas;
}

async function roboSessao(body: any) {
  const { data: c } = await admin.from("ifood_portal_conexoes").select("*").eq("empresa_id", body?.empresa_id).maybeSingle();
  if (!c) return { status: 404, body: { erro: "loja sem conexão com o Portal" } };
  const n = await renovarESalvar(c);
  const perfil = (() => {
    try { return JSON.parse(atob(String(n.id_token).split(".")[1].replace(/-/g, "+").replace(/_/g, "/"))); } catch { return {}; }
  })();
  return {
    status: 200,
    body: {
      merchant_id: c.merchant_id,
      oidc_user: {
        id_token: n.id_token, session_state: (n as any).session_state ?? null, access_token: n.access_token,
        refresh_token: n.refresh_token, token_type: "Bearer", scope: (n as any).scope,
        profile: perfil, expires_at: Math.floor(new Date(n.access_expira_em).getTime() / 1000),
      },
    },
  };
}

async function roboDevolver(body: any) {
  const refresh = String(body?.refresh_token ?? "");
  if (!body?.empresa_id || !refresh) return { status: 400, body: { erro: "faltou empresa ou acesso" } };
  await admin.from("ifood_portal_conexoes").update({
    refresh_token: refresh, refresh_expira_em: expDoJwt(refresh),
    ...(body.access_token ? { access_token: body.access_token, access_expira_em: expDoJwt(body.access_token) } : {}),
    ...(body.id_token ? { id_token: body.id_token } : {}),
    renovado_em: new Date().toISOString(),
  }).eq("empresa_id", body.empresa_id);
  return { status: 200, body: { ok: true } };
}

async function roboResultado(body: any) {
  const { data: t } = await admin.from("ifood_portal_tarefas").select("*").eq("id", body?.id).maybeSingle();
  if (!t) return { status: 404, body: { erro: "tarefa não existe" } };
  if (body.ok) {
    await admin.from("ifood_portal_tarefas").update({
      status: "ok", resultado: body.resultado ?? null, erro: null, concluido_em: new Date().toISOString(),
    }).eq("id", t.id);
    return { status: 200, body: { ok: true } };
  }
  const erro = String(body.erro ?? "erro sem detalhe").slice(0, 1000);
  if (t.tentativas < 3) {
    await admin.from("ifood_portal_tarefas").update({
      status: "pendente", erro, resultado: body.resultado ?? null,
      executar_em: new Date(Date.now() + 5 * 60e3).toISOString(),
    }).eq("id", t.id);
  } else {
    await admin.from("ifood_portal_tarefas").update({
      status: "erro", erro, resultado: body.resultado ?? null, concluido_em: new Date().toISOString(),
    }).eq("id", t.id);
    const oque = t.acao === "pedido_minimo" ? `mudar o pedido mínimo pra R$ ${t.parametros?.valor}`
      : t.acao === "promocao" ? `${t.parametros?.modo === "sair" ? "sair da" : "voltar pra"} promoção "${t.parametros?.nome}"`
      : `ligar a pré-configuração ${t.parametros?.nome}`;
    await avisar(t.empresa_id, "Robô do Portal iFood não conseguiu ⚠️",
      `Não consegui ${oque} (${t.motivo ?? ""}). Faça à mão no Portal do Parceiro. Detalhe: ${erro.slice(0, 160)}`);
  }
  return { status: 200, body: { ok: true, nova_tentativa: t.tentativas < 3 } };
}

Deno.serve(async (req) => {
  const h = cors(req);
  if (req.method === "OPTIONS") return new Response("ok", { headers: h });
  const json = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers: { ...h, "content-type": "application/json" } });
  try {
    const body = await req.json().catch(() => ({}));
    const acao = body?.acao;
    if (acao === "conectar") {
      const r = await conectar(body);
      return json(r.status, r.body);
    }
    if (acao === "manter") {
      if (req.headers.get("x-cron-secret") !== await parametro("cron_secret")) return json(401, { erro: "sem permissão" });
      return json(200, { ok: true, resultado: await manter() });
    }
    if (String(acao ?? "").startsWith("robo_")) {
      const seg = req.headers.get("x-robo-secret");
      if (!seg || seg !== await parametro("robo_secret")) return json(401, { erro: "sem permissão" });
      if (acao === "robo_tarefas") return json(200, { tarefas: await roboTarefas() });
      if (acao === "robo_sessao") { const r = await roboSessao(body); return json(r.status, r.body); }
      if (acao === "robo_devolver") { const r = await roboDevolver(body); return json(r.status, r.body); }
      if (acao === "robo_resultado") { const r = await roboResultado(body); return json(r.status, r.body); }
    }
    return json(400, { erro: "ação desconhecida" });
  } catch (e) {
    return json(500, { erro: (e as Error).message });
  }
});
