// iFood — busca de reserva (polling) para avisos que o webhook não entregou.
//
// O iFood reenvia aviso de webhook por até 15 min e depois descarta
// ("Use polling como fallback" — doc Events > Conceitos do webhook). Esta
// função NÃO processa nada: lê GET /events/v1.0/events:polling de cada loja
// com iFood ativo, guarda cada aviso novo na caixa de entrada
// (ifood_eventos_recebidos, status 'recebido') e confirma todos com
// POST /events/acknowledgment. Aviso que o webhook já entregou tem o mesmo id
// e é ignorado; o que faltar é processado pela conferência do banco
// (ifood_conferir_eventos, a cada 2 min) pelo caminho de reprocesso do robô.
//
// Chamada: pg_cron → pg_net com header `x-ifood-polling` (segredo no Vault).
import { createClient } from "jsr:@supabase/supabase-js@2";

const API = "https://merchant-api.ifood.com.br";
const IFOOD_ID = "d4811153-e210-47b0-b910-ee0440914f60";
const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

type Config = { empresa_id: string; id_loja_plataforma: string; api_key: string; api_secret: string };
type Evento = { id: string; code?: string; fullCode?: string; orderId?: string; merchantId?: string };

// Mesmo cache de token da ifood-merchant (marketplace_token_cache).
async function token(c: Config, forcar = false): Promise<string> {
  if (!forcar) {
    const { data } = await admin.from("marketplace_token_cache").select("access_token, expira_em")
      .eq("empresa_id", c.empresa_id).eq("marketplace_id", IFOOD_ID).maybeSingle();
    if (data && new Date(data.expira_em).getTime() > Date.now() + 5 * 60_000) return data.access_token;
  }
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

async function pollingLoja(c: Config) {
  let tk = await token(c);
  const ler = (t: string) => fetch(`${API}/events/v1.0/events:polling?categories=ALL`, {
    headers: { Authorization: `Bearer ${t}`, "x-polling-merchants": c.id_loja_plataforma },
  });
  let resp = await ler(tk);
  if (resp.status === 401 || resp.status === 403) { tk = await token(c, true); resp = await ler(tk); }
  if (resp.status === 204) return { loja: c.id_loja_plataforma, lidos: 0, novos: 0 };
  if (!resp.ok) throw new Error(`polling ${resp.status}: ${(await resp.text()).slice(0, 200)}`);

  const eventos = (await resp.json().catch(() => [])) as Evento[];
  const validos = eventos.filter((e) => e?.id && e.fullCode !== "KEEPALIVE");
  let novos = 0;
  if (validos.length) {
    const { data, error } = await admin.from("ifood_eventos_recebidos").upsert(
      validos.map((e) => ({
        event_id: e.id, full_code: e.fullCode ?? e.code ?? "", order_id: e.orderId ?? null,
        empresa_id: c.empresa_id, payload: JSON.stringify(e), status: "recebido",
      })),
      { onConflict: "event_id", ignoreDuplicates: true },
    ).select("event_id");
    if (error) throw new Error(`gravar caixa de entrada: ${error.message}`);
    novos = data?.length ?? 0;
  }
  // Confirma todos os lidos (inclusive os ignorados), como pede a doc — só depois de gravar.
  if (eventos.length) {
    const ack = await fetch(`${API}/events/v1.0/events/acknowledgment`, {
      method: "POST",
      headers: { Authorization: `Bearer ${tk}`, "Content-Type": "application/json" },
      body: JSON.stringify(eventos.filter((e) => e?.id).map((e) => ({ id: e.id }))),
    });
    if (!ack.ok) throw new Error(`acknowledgment ${ack.status}`);
  }
  return { loja: c.id_loja_plataforma, lidos: eventos.length, novos };
}

Deno.serve(async (req) => {
  const segredo = req.headers.get("x-ifood-polling") ?? "";
  const { data: ok } = await admin.rpc("ifood_conferir_segredo_polling", { p_segredo: segredo });
  if (!ok) return json({ erro: "não autorizado" }, 401);

  const { data: cfgs } = await admin.from("empresa_marketplace_config")
    .select("empresa_id, id_loja_plataforma, api_key, api_secret")
    .eq("marketplace_id", IFOOD_ID).eq("ativo", true);

  const resultados = [];
  for (const c of (cfgs ?? []) as Config[]) {
    if (!c.api_key || !c.id_loja_plataforma) continue;
    try { resultados.push(await pollingLoja(c)); }
    catch (e) { resultados.push({ loja: c.id_loja_plataforma, erro: String((e as Error).message ?? e) }); }
  }
  return json({ resultados });
});
