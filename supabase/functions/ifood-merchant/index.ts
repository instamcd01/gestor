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
        // Cenário 29 (só neste botão do roteiro): rajadas de 15 requisições ao
        // mesmo tempo, no máximo 6, até o iFood responder 429; depois a mesma
        // chamada com backoff até passar. O resto do sistema faz uma por vez.
        let n = 0;
        let ultima: Resultado = { ok: true, status: 200 };
        for (let rajada = 0; rajada < 6 && ultima.status !== 429; rajada++) {
          const lote = await Promise.all(Array.from({ length: 15 }, () =>
            ifood(c, "GET", `/promotion/v2.0/merchants/${loja}/promotions?size=1`, undefined, { semRetentativa: true })));
          n += lote.length;
          ultima = lote.find((x) => x.status === 429) ?? lote[lote.length - 1];
        }
        if (ultima.status === 429) {
          r = await ifood(c, "GET", `/promotion/v2.0/merchants/${loja}/promotions?size=1`);
          r.requisicoes = n;
        } else {
          r = { ...ultima, requisicoes: n, erro: `o iFood não respondeu 429 em ${n} requisições` };
        }
        break;
      }
      // ── Financial v3.0 ────────────────────────────────────────────────
      // homologacao=true manda o header x-request-homologation (dados de
      // teste do iFood, exigido no questionário de homologação).
      case "fin_vendas": {
        // Máximo de 8 dias por consulta: quebra o período em janelas e pagina.
        const vendas: unknown[] = [];
        let ultima: Resultado = { ok: true, status: 200 };
        for (const [ini, fim] of janelas(String(body.inicio), String(body.fim), 8)) {
          for (let page = 1; page <= 30; page++) {
            ultima = await ifood(c, "GET",
              `/financial/v3.0/merchants/${loja}/sales?beginSalesDate=${ini}&endSalesDate=${fim}&page=${page}`,
              undefined, { homologacao: !!body.homologacao });
            if (!ultima.ok) break;
            const d = (ultima.dados ?? {}) as Record<string, unknown>;
            vendas.push(...((d.sales as unknown[]) ?? []));
            if (page >= Number(d.pageCount ?? 1)) break;
          }
          if (!ultima.ok) break;
        }
        r = ultima.ok ? { ok: true, status: 200, dados: { sales: vendas, total: vendas.length } } : ultima;
        break;
      }
      case "fin_eventos": {
        // Máximo de 33 dias por consulta; pagina por hasNextPage.
        const eventos: unknown[] = [];
        let ultima: Resultado = { ok: true, status: 200 };
        for (const [ini, fim] of janelas(String(body.inicio), String(body.fim), 33)) {
          for (let page = 1; page <= 50; page++) {
            ultima = await ifood(c, "GET",
              `/financial/v3.0/merchants/${loja}/financial-events?beginDate=${ini}&endDate=${fim}&page=${page}&size=100`,
              undefined, { homologacao: !!body.homologacao });
            if (!ultima.ok) break;
            const d = (ultima.dados ?? {}) as Record<string, unknown>;
            eventos.push(...((d.financialEvents as unknown[]) ?? []));
            if (!d.hasNextPage) break;
          }
          if (!ultima.ok) break;
        }
        r = ultima.ok ? { ok: true, status: 200, dados: { financialEvents: eventos, total: eventos.length } } : ultima;
        break;
      }
      case "fin_repasses": {
        r = await ifood(c, "GET",
          `/financial/v3.0/merchants/${loja}/settlements?beginPaymentDate=${body.inicio}&endPaymentDate=${body.fim}`,
          undefined, { homologacao: !!body.homologacao });
        break;
      }
      case "fin_antecipacoes": {
        r = await ifood(c, "GET",
          `/financial/v3.0/merchants/${loja}/anticipations?beginCalculationDate=${body.inicio}&endCalculationDate=${body.fim}`,
          undefined, { homologacao: !!body.homologacao });
        break;
      }
      case "fin_conciliacao_pedir": {
        const competencia = String(body.competencia ?? "");
        if (!/^\d{4}-\d{2}$/.test(competencia)) return json({ erro: "competência inválida (use AAAA-MM)" }, 400);
        r = await ifood(c, "POST", `/financial/v3.0/merchants/${loja}/reconciliation/on-demand`,
          { competence: competencia }, { homologacao: !!body.homologacao });
        let requestId = (r.dados as Record<string, unknown>)?.requestId as string | undefined;
        // 409 = já existe pedido pra essa competência: reaproveita o requestId guardado.
        if (r.status === 409 && !requestId) requestId = (await ultimaConciliacao(c, competencia, !!body.homologacao))?.request_id;
        if (requestId) {
          await admin.from("eventos_sistema").insert({
            tipo_evento: "ifood_conciliacao_on_demand", tabela_origem: "empresa_marketplace_config",
            dados: { empresa_id: c.empresa_id, competencia, request_id: requestId, homologacao: !!body.homologacao, status: "REQUESTED" },
          });
          r = { ...r, ok: true, dados: { ...(r.dados as object ?? {}), requestId, reaproveitado: r.status === 409 } };
        }
        break;
      }
      case "fin_conciliacao_status": {
        const competencia = String(body.competencia ?? "");
        const requestId = String(body.request_id ?? "") || (await ultimaConciliacao(c, competencia, !!body.homologacao))?.request_id;
        if (!requestId) return json({ erro: "nenhum pedido de conciliação para essa competência" }, 404);
        r = await ifood(c, "GET", `/financial/v3.0/merchants/${loja}/reconciliation/on-demand/${requestId}`,
          undefined, { homologacao: !!body.homologacao });
        break;
      }
      case "fin_conciliacao_listar": {
        const { data } = await admin.from("eventos_sistema").select("dados, created_at")
          .eq("tipo_evento", "ifood_conciliacao_on_demand").eq("dados->>empresa_id", c.empresa_id)
          .order("created_at", { ascending: false }).limit(24);
        r = { ok: true, status: 200, dados: { pedidos: data ?? [] } };
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
  homologacao?: boolean;        // Financial: header x-request-homologation (dados de teste)
};

// Quebra [inicio, fim] (AAAA-MM-DD) em janelas de no máximo `dias` dias.
function janelas(inicio: string, fim: string, dias: number): [string, string][] {
  const d = (s: string) => new Date(`${s}T00:00:00Z`);
  const f = (x: Date) => x.toISOString().slice(0, 10);
  const saida: [string, string][] = [];
  let a = d(inicio);
  const b = d(fim);
  if (isNaN(a.getTime()) || isNaN(b.getTime()) || a > b) return [[inicio, fim]];
  while (a <= b && saida.length < 60) {
    const z = new Date(a.getTime() + (dias - 1) * 86_400_000);
    saida.push([f(a), f(z < b ? z : b)]);
    a = new Date(z.getTime() + 86_400_000);
  }
  return saida;
}

async function ultimaConciliacao(c: Config, competencia: string, homologacao: boolean) {
  const { data } = await admin.from("eventos_sistema").select("dados")
    .eq("tipo_evento", "ifood_conciliacao_on_demand").eq("dados->>empresa_id", c.empresa_id)
    .eq("dados->>competencia", competencia).eq("dados->>homologacao", String(homologacao))
    .order("created_at", { ascending: false }).limit(1).maybeSingle();
  return (data?.dados ?? null) as { request_id?: string } | null;
}

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
      headers: {
        Authorization: `Bearer ${tokenAtual}`,
        ...(temCorpo ? { "Content-Type": "application/json" } : {}),
        ...(o.homologacao ? { "x-request-homologation": "true" } : {}),
      },
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
  // Financial devolve listas grandes com dados de pedido: guarda só o resumo.
  const dados = acao.startsWith("fin_") ? { ok: r.ok, status: r.status, erro: r.erro, tentativas: r.tentativas } : r;
  await admin.from("eventos_sistema").insert({
    tipo_evento: `ifood_merchant_${acao || "desconhecida"}`,
    tabela_origem: "empresa_marketplace_config",
    dados: { empresa_id: empresaId, ...dados },
  });
}
