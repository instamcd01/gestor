// iFood — consultas e ações da loja que o Gestor faz direto e que precisam
// devolver resposta pra tela (módulos Merchant, Order/Picking e Item).
//
// Chamada: app com o JWT do usuário + {"acao", ...}. A loja é sempre a do
// usuário logado (get_empresa_id); clientId/clientSecret ficam no banco
// (empresa_marketplace_config) e nunca passam pelo app.
//
// Ações:
//   listar_lojas · detalhe_loja · status_loja
//   listar_pausas
//   consultar_horarios · salvar_horarios {turnos: [{dia, inicio, fim}]}
//   consultar_pedido {marketplace_pedido_id} (GET virtual-bag)
//   carga_completa                         (POST ingestion ?reset=true)
//
// Pausa criar/remover continua pelo caminho de sempre
// (marketplace_interrupcoes → gatilho → n8n "Marketplace - Loja").
import { createClient } from "jsr:@supabase/supabase-js@2";

const API = "https://merchant-api.ifood.com.br";
const IFOOD_ID = "d4811153-e210-47b0-b910-ee0440914f60";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const admin = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

const DIAS: Record<string, string> = {
  segunda: "MONDAY", terca: "TUESDAY", quarta: "WEDNESDAY", quinta: "THURSDAY",
  sexta: "FRIDAY", sabado: "SATURDAY", domingo: "SUNDAY",
};

type Config = { empresa_id: string; id_loja_plataforma: string; api_key: string; api_secret: string };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ erro: "não autorizado" }, 401);
  const usuario = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  const { data: empresaId } = await usuario.rpc("get_empresa_id");
  if (!empresaId) return json({ erro: "não autorizado" }, 401);

  const body = await req.json().catch(() => ({}));
  const acao = String(body?.acao ?? "");

  const { data: cfg } = await admin
    .from("empresa_marketplace_config")
    .select("empresa_id, id_loja_plataforma, api_key, api_secret")
    .eq("empresa_id", empresaId).eq("marketplace_id", IFOOD_ID).eq("ativo", true)
    .maybeSingle();
  if (!cfg?.api_key || !cfg?.id_loja_plataforma) return json({ erro: "iFood não conectado nesta loja" }, 400);
  const c = cfg as Config;
  const loja = c.id_loja_plataforma;

  try {
    let r: Resultado;
    switch (acao) {
      case "listar_lojas": r = await ifood(c, "GET", "/merchant/v1.0/merchants"); break;
      case "detalhe_loja": r = await ifood(c, "GET", `/merchant/v1.0/merchants/${body.merchant_id ?? loja}`); break;
      case "status_loja": r = await ifood(c, "GET", `/merchant/v1.0/merchants/${body.merchant_id ?? loja}/status`); break;
      case "listar_pausas": r = await ifood(c, "GET", `/merchant/v1.0/merchants/${loja}/interruptions`); break;
      case "consultar_horarios": r = await ifood(c, "GET", `/merchant/v1.0/merchants/${loja}/opening-hours`); break;
      case "salvar_horarios": {
        const shifts = montarShifts(body.turnos);
        if (typeof shifts === "string") return json({ erro: shifts }, 400);
        r = await ifood(c, "PUT", `/merchant/v1.0/merchants/${loja}/opening-hours`, { storeId: loja, shifts });
        break;
      }
      case "consultar_pedido": {
        const { data: mp } = await usuario
          .from("marketplace_pedidos").select("marketplace_order_id")
          .eq("id", body.marketplace_pedido_id).eq("marketplace_id", IFOOD_ID).maybeSingle();
        if (!mp?.marketplace_order_id) return json({ erro: "pedido do iFood não encontrado" }, 404);
        r = await ifood(c, "GET", `/order/v1.0/orders/${mp.marketplace_order_id}/virtual-bag`, undefined, body.marketplace_pedido_id);
        break;
      }
      case "carga_completa": {
        const { data: itens, error } = await admin.rpc("ifood_itens_carga_completa", {
          p_empresa_id: c.empresa_id, p_marketplace_id: IFOOD_ID,
        });
        if (error) throw new Error(error.message);
        r = await ifood(c, "POST", `/item/v1.0/ingestion/${loja}?reset=true`, itens);
        r.itens_enviados = (itens as unknown[]).length;
        break;
      }
      default:
        return json({ erro: "ação desconhecida" }, 400);
    }
    await registrar(c.empresa_id, acao, r);
    return json(r, r.ok ? 200 : 502);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    await registrar(c.empresa_id, acao, { ok: false, status: 0, erro: msg });
    return json({ ok: false, erro: msg }, 500);
  }
});

type Resultado = { ok: boolean; status: number; dados?: unknown; erro?: string; itens_enviados?: number };

// turnos: [{dia: 'sabado', inicio: '10:00', fim: '19:00'}, ...] → shifts do iFood
function montarShifts(turnos: unknown): Array<Record<string, unknown>> | string {
  if (!Array.isArray(turnos)) return "turnos inválidos";
  const shifts = [];
  for (const t of turnos) {
    const dia = DIAS[String(t?.dia)];
    const m = (s: unknown) => /^(\d{2}):(\d{2})$/.exec(String(s ?? ""));
    const a = m(t?.inicio), b = m(t?.fim);
    if (!dia || !a || !b) return "turno inválido";
    const ini = Number(a[1]) * 60 + Number(a[2]);
    let fim = Number(b[1]) * 60 + Number(b[2]);
    if (fim === 0) fim = 24 * 60; // 00:00 = meia-noite
    if (fim <= ini) return `turno de ${t.dia} termina antes de começar`;
    shifts.push({ dayOfWeek: dia, start: `${a[1]}:${a[2]}:00`, duration: fim - ini });
  }
  return shifts;
}

async function token(c: Config): Promise<string> {
  const { data } = await admin
    .from("marketplace_token_cache").select("access_token, expira_em")
    .eq("empresa_id", c.empresa_id).eq("marketplace_id", IFOOD_ID).maybeSingle();
  if (data && new Date(data.expira_em).getTime() > Date.now() + 60_000) return data.access_token;

  const resp = await fetch(`${API}/authentication/v1.0/oauth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grantType: "client_credentials", clientId: c.api_key, clientSecret: c.api_secret }),
  });
  const t = await resp.json().catch(() => ({}));
  if (!resp.ok || !t.accessToken) throw new Error(`token iFood recusado (${resp.status})`);
  await admin.from("marketplace_token_cache").upsert({
    empresa_id: c.empresa_id, marketplace_id: IFOOD_ID, access_token: t.accessToken,
    expira_em: new Date(Date.now() + (Number(t.expiresIn) || 21600) * 1000).toISOString(),
    atualizado_em: new Date().toISOString(),
  });
  return t.accessToken;
}

async function ifood(c: Config, method: string, path: string, corpo?: unknown, marketplacePedidoId?: string): Promise<Resultado> {
  const resp = await fetch(API + path, {
    method,
    headers: { Authorization: `Bearer ${await token(c)}`, ...(corpo !== undefined ? { "Content-Type": "application/json" } : {}) },
    body: corpo !== undefined ? JSON.stringify(corpo) : undefined,
  });
  const texto = await resp.text();
  let dados: unknown = null;
  try { dados = texto ? JSON.parse(texto) : null; } catch { dados = texto; }
  // Tela "Chamadas da integração": cada chamada com o status HTTP real.
  await admin.from("marketplace_api_chamadas").insert({
    empresa_id: c.empresa_id, marketplace_id: IFOOD_ID, marketplace_pedido_id: marketplacePedidoId ?? null,
    metodo: method, endpoint: path.split("?")[0] + (path.includes("reset=true") ? "?reset=true" : ""),
    http_status: resp.status, sucesso: resp.ok, origem: "gestor",
    detalhe: resp.ok ? null : texto.slice(0, 1000),
  }).then(() => {}, () => {});
  return resp.ok ? { ok: true, status: resp.status, dados } : { ok: false, status: resp.status, dados, erro: `iFood respondeu ${resp.status}` };
}

async function registrar(empresaId: string, acao: string, r: Resultado) {
  const dados = r;
  await admin.from("eventos_sistema").insert({
    tipo_evento: `ifood_merchant_${acao || "desconhecida"}`,
    tabela_origem: "empresa_marketplace_config",
    dados: { empresa_id: empresaId, ...dados },
  });
}
