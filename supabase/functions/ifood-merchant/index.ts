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
      // ── Promotion v2.0 ────────────────────────────────────────────────
      // merchant_id opcional só pra cenários de homologação (merchant
      // inexistente / de outro merchant); quem autoriza é o próprio iFood.
      case "promo_criar": {
        const m = body.merchant_id ?? loja;
        r = await ifood(c, "POST", `/promotion/v2.0/merchants/${m}/promotions`, body.payload,
          { corpoBruto: typeof body.corpo_bruto === "string" ? body.corpo_bruto : undefined });
        const pid = idPromocao(r.dados);
        if (pid && m === loja) {
          await salvarPromocao(c, pid, {
            nome: String(body.payload?.promotions?.promotionName ?? "sem nome"),
            resumo: (r.dados as Record<string, unknown>)?.summary ?? null,
            erros: (r.dados as Record<string, unknown>)?.errors ?? null,
            payload_enviado: body.payload ?? null, homologacao: !!body.homologacao, status: "ACTIVE",
          });
        }
        break;
      }
      case "promo_consultar": {
        const m = body.merchant_id ?? loja;
        r = await ifood(c, "GET", `/promotion/v2.0/merchants/${m}/promotions/${body.promotion_id}`, undefined,
          { promotionId: body.promotion_id, tokenInvalido: !!body.simular_token_expirado });
        if (r.ok && m === loja) {
          const d = r.dados as Record<string, unknown>;
          const s = (d?.summary ?? {}) as Record<string, unknown>;
          await salvarPromocao(c, String(body.promotion_id), {
            nome: String(d?.promotionName ?? ""), resumo: d?.summary ?? null, erros: d?.errors ?? null,
            em_processamento: Number(s.inProgress ?? 0) > 0,
          });
        }
        break;
      }
      case "promo_listar": {
        const q = new URLSearchParams();
        for (const k of ["page", "size", "status", "startDate", "endDate"]) {
          if (body[k] !== undefined && body[k] !== null && body[k] !== "") q.set(k, String(body[k]));
        }
        const qs = q.toString();
        r = await ifood(c, "GET", `/promotion/v2.0/merchants/${loja}/promotions${qs ? `?${qs}` : ""}`);
        const itens = ((r.dados as Record<string, unknown>)?.items ?? []) as Record<string, unknown>[];
        for (const it of Array.isArray(itens) ? itens : []) {
          if (typeof it.promotionId === "string" && typeof it.status === "string") {
            await admin.from("marketplace_promocoes").update({ status: it.status, atualizado_em: new Date().toISOString() })
              .eq("empresa_id", c.empresa_id).eq("promotion_id", it.promotionId);
          }
        }
        break;
      }
      case "promo_editar": {
        r = await ifood(c, "PATCH", `/promotion/v2.0/merchants/${loja}/promotions/${body.promotion_id}`, body.payload,
          { promotionId: body.promotion_id });
        if (r.ok) {
          await salvarPromocao(c, String(body.promotion_id), {
            resumo: (r.dados as Record<string, unknown>)?.summary ?? null,
            erros: (r.dados as Record<string, unknown>)?.errors ?? null,
            payload_enviado: body.payload ?? null, em_processamento: true,
          });
        }
        break;
      }
      case "promo_remover_itens": {
        const corpo = Array.isArray(body.items) && body.items.length ? { items: body.items } : {};
        r = await ifood(c, "PATCH", `/promotion/v2.0/merchants/${loja}/promotions/${body.promotion_id}/items/remove`, corpo,
          { promotionId: body.promotion_id });
        if (r.ok && !("items" in corpo)) {
          await salvarPromocao(c, String(body.promotion_id), { status: "INACTIVE", em_processamento: false });
        }
        break;
      }
      case "promo_itens": {
        r = await ifood(c, "GET", `/promotion/v2.0/merchants/${loja}/promotions/${body.promotion_id}/items?size=${Number(body.size) || 200}`,
          undefined, { promotionId: body.promotion_id });
        break;
      }
      case "promo_pedidos": {
        const q = new URLSearchParams();
        for (const k of ["page", "size", "startDate", "endDate"]) {
          if (body[k] !== undefined && body[k] !== null && body[k] !== "") q.set(k, String(body[k]));
        }
        const qs = q.toString();
        r = await ifood(c, "GET", `/promotion/v2.0/merchants/${loja}/promotions/${body.promotion_id}/orders${qs ? `?${qs}` : ""}`,
          undefined, { promotionId: body.promotion_id });
        break;
      }
      case "promo_teste_429": {
        // Cenário 29: requisições seguidas (uma por vez, sem paralelismo) até o
        // iFood responder 429; depois a mesma chamada com backoff até passar.
        let n = 0;
        let ultima: Resultado = { ok: true, status: 200 };
        while (n < 60) {
          n++;
          ultima = await ifood(c, "GET", `/promotion/v2.0/merchants/${loja}/promotions?size=1`, undefined, { semRetentativa: true });
          if (ultima.status === 429) break;
        }
        if (ultima.status === 429) {
          r = await ifood(c, "GET", `/promotion/v2.0/merchants/${loja}/promotions?size=1`);
          r.requisicoes = n;
        } else {
          r = { ...ultima, requisicoes: n, erro: `o iFood não respondeu 429 em ${n} requisições` };
        }
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

type Resultado = {
  ok: boolean; status: number; dados?: unknown; erro?: string; itens_enviados?: number;
  tentativas?: number; token_renovado?: boolean; requisicoes?: number;
};

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

// Renovação preventiva: 5 min antes de vencer (critério do iFood). Reativa: `forcar` depois de um 401.
async function token(c: Config, forcar = false): Promise<string> {
  let data: { access_token: string; expira_em: string } | null = null;
  if (!forcar) {
    ({ data } = await admin
      .from("marketplace_token_cache").select("access_token, expira_em")
      .eq("empresa_id", c.empresa_id).eq("marketplace_id", IFOOD_ID).maybeSingle());
  }
  if (data && new Date(data.expira_em).getTime() > Date.now() + 5 * 60_000) return data.access_token;

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

type Opcoes = {
  marketplacePedidoId?: string;
  promotionId?: string;
  corpoBruto?: string;          // envia o texto como está (cenário "JSON malformado")
  tokenInvalido?: boolean;      // cenário "token expirado": 1ª tentativa com token inválido
  semRetentativa?: boolean;     // cenário 429: mostrar o 429 sem esperar
};

const esperar = (ms: number) => new Promise((r) => setTimeout(r, ms));

// Chamada à API do iFood com renovação de token no 401 e backoff exponencial
// no 429/5xx (máx. 4 tentativas). Cada tentativa vira uma linha em
// marketplace_api_chamadas (endpoint, status HTTP, promotionId, errorCode).
async function ifood(c: Config, method: string, path: string, corpo?: unknown, opc: Opcoes | string = {}): Promise<Resultado> {
  const o: Opcoes = typeof opc === "string" ? { marketplacePedidoId: opc } : opc;
  const MAX = o.semRetentativa ? 1 : 4;
  let tokenAtual = o.tokenInvalido ? "token-expirado-simulado" : await token(c);
  let renovou = false;
  let ultimo: Resultado = { ok: false, status: 0, erro: "sem resposta" };
  for (let tentativa = 1; tentativa <= MAX; tentativa++) {
    const temCorpo = o.corpoBruto !== undefined || corpo !== undefined;
    const resp = await fetch(API + path, {
      method,
      headers: { Authorization: `Bearer ${tokenAtual}`, ...(temCorpo ? { "Content-Type": "application/json" } : {}) },
      body: o.corpoBruto !== undefined ? o.corpoBruto : corpo !== undefined ? JSON.stringify(corpo) : undefined,
    });
    const texto = await resp.text();
    let dados: unknown = null;
    try { dados = texto ? JSON.parse(texto) : null; } catch { dados = texto; }
    const errorCode = codigoErro(dados);
    await admin.from("marketplace_api_chamadas").insert({
      empresa_id: c.empresa_id, marketplace_id: IFOOD_ID, marketplace_pedido_id: o.marketplacePedidoId ?? null,
      metodo: method, endpoint: path.split("?")[0] + (path.includes("reset=true") ? "?reset=true" : ""),
      http_status: resp.status, sucesso: resp.ok, origem: "gestor", tentativa,
      promotion_id: o.promotionId ?? idPromocao(dados) ?? null, error_code: errorCode,
      detalhe: resp.ok && resp.status !== 206 ? (path.includes("?") ? path.slice(path.indexOf("?")) : null) : texto.slice(0, 1000),
    }).then(() => {}, () => {});
    ultimo = resp.ok
      ? { ok: true, status: resp.status, dados, tentativas: tentativa }
      : { ok: false, status: resp.status, dados, erro: `iFood respondeu ${resp.status}`, tentativas: tentativa };
    if (resp.status === 401 && !renovou) {          // token vencido/inválido: renova e reenvia uma vez
      renovou = true;
      tokenAtual = await token(c, true);
      continue;
    }
    if ((resp.status === 429 || resp.status >= 500) && tentativa < MAX) {
      const retry = Number(resp.headers.get("retry-after"));
      await esperar(Math.min(retry > 0 ? retry * 1000 : 500 * 2 ** (tentativa - 1) + Math.floor(Math.random() * 250), 8000));
      continue;
    }
    break;
  }
  if (renovou) ultimo.token_renovado = true;
  return ultimo;
}

// O iFood devolve erro em vários formatos: {errors:[{errorCode}]}, {code}, {error}.
function codigoErro(d: unknown): string | null {
  if (!d || typeof d !== "object") return null;
  const x = d as Record<string, unknown>;
  if (Array.isArray(x.errors) && x.errors.length) {
    const cods = [...new Set((x.errors as Record<string, unknown>[]).map((e) => String(e?.errorCode ?? e?.error ?? "")).filter(Boolean))];
    if (cods.length) return cods.join(",");
  }
  if (typeof x.code === "string") return x.code;
  return null;
}
function idPromocao(d: unknown): string | null {
  if (!d || typeof d !== "object") return null;
  const v = (d as Record<string, unknown>).promotionId;
  return typeof v === "string" ? v : null;
}

async function salvarPromocao(c: Config, promotionId: string, campos: Record<string, unknown>) {
  const limpo = Object.fromEntries(Object.entries(campos).filter(([k, v]) => v !== undefined && !(k === "nome" && !v)));
  const { data: existe } = await admin.from("marketplace_promocoes").select("id")
    .eq("empresa_id", c.empresa_id).eq("marketplace_id", IFOOD_ID).eq("promotion_id", promotionId).maybeSingle();
  if (existe) {
    await admin.from("marketplace_promocoes").update({ ...limpo, atualizado_em: new Date().toISOString() }).eq("id", existe.id);
  } else {
    await admin.from("marketplace_promocoes").insert({
      empresa_id: c.empresa_id, marketplace_id: IFOOD_ID, promotion_id: promotionId, nome: "sem nome", ...limpo,
    });
  }
}

async function registrar(empresaId: string, acao: string, r: Resultado) {
  const dados = r;
  await admin.from("eventos_sistema").insert({
    tipo_evento: `ifood_merchant_${acao || "desconhecida"}`,
    tabela_origem: "empresa_marketplace_config",
    dados: { empresa_id: empresaId, ...dados },
  });
}
