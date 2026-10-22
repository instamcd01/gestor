// Contas e Conferência — sincronização das contas conectadas por API que
// exigem certificado de cliente (mTLS), começando pelo Banco Inter.
//
// Dois jeitos de chamar:
//  * agendador (pg_cron → pg_net): header `x-contas-sync` com o segredo do
//    Vault `contas_sync_segredo` → sincroniza todas as contas Inter de todas
//    as lojas;
//  * app (logo depois de conectar): JWT do usuário + {"conta_id"} → só
//    aquela conta, e só se o usuário enxerga ela (RLS).
//
// Credenciais vêm de contas_credenciais_para_sincronizar() (Vault), nunca
// passam pelo app. Leitura apenas: escopo `extrato.read` (saldo + extrato).
import { createClient } from "jsr:@supabase/supabase-js@2";

const INTER = "https://cdpj.partners.bancointer.com.br";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

type Credencial = {
  conta_id: string;
  empresa_id: string;
  client_id: string;
  client_secret: string;
  certificado: string;
  chave: string;
  conta_corrente: string | null;
  token: string | null;
  token_expira_em: string | null;
  buscar_desde: string;
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  let contaId: string | null = null;
  const segredo = req.headers.get("x-contas-sync");
  if (segredo) {
    const { data: ok } = await admin.rpc("contas_conferir_segredo_sync", { p_segredo: segredo });
    if (!ok) return json({ erro: "não autorizado" }, 401);
  } else {
    const auth = req.headers.get("Authorization") ?? "";
    const body = await req.json().catch(() => ({}));
    contaId = body?.conta_id ?? null;
    if (!auth.startsWith("Bearer ") || !contaId) return json({ erro: "não autorizado" }, 401);
    const usuario = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: auth } },
      auth: { persistSession: false },
    });
    const { data: conta } = await usuario.from("contas_financeiras").select("id").eq("id", contaId).maybeSingle();
    if (!conta) return json({ erro: "conta não encontrada" }, 404);
  }

  const { data: creds, error } = await admin.rpc("contas_credenciais_para_sincronizar", {
    p_provedor: "inter",
    p_conta_id: contaId,
  });
  if (error) return json({ erro: error.message }, 500);

  const resultados = [];
  for (const c of (creds ?? []) as Credencial[]) {
    try {
      resultados.push({ conta_id: c.conta_id, ...(await sincronizarInter(c)) });
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      await admin.rpc("contas_registrar_erro_conta", { p_conta_id: c.conta_id, p_erro: msg });
      resultados.push({ conta_id: c.conta_id, erro: msg });
    }
  }
  return json({ contas: resultados.length, resultados });
});

async function sincronizarInter(c: Credencial) {
  const client = Deno.createHttpClient({ cert: c.certificado, key: c.chave });
  try {
    const token = await obterToken(c, client);
    const headers: Record<string, string> = { Authorization: `Bearer ${token}`, Accept: "application/json" };
    if (c.conta_corrente) {
      headers["x-conta-corrente"] = c.conta_corrente;
      headers["x-inter-conta-corrente"] = c.conta_corrente;
    }

    const saldo = await chamar(`${INTER}/banking/v2/saldo`, { headers, client }, "saldo");
    const disponivel = numero(saldo?.disponivel);

    // Extrato completo: até 90 dias por consulta, 10 chamadas/min.
    const hoje = dataBR(new Date());
    const transacoes: any[] = [];
    for (let pagina = 0; pagina < 20; pagina++) {
      const qs = new URLSearchParams({
        dataInicio: c.buscar_desde,
        dataFim: hoje,
        pagina: String(pagina),
        tamanhoPagina: "1000",
      });
      const r = await chamar(`${INTER}/banking/v2/extrato/completo?${qs}`, { headers, client }, "extrato");
      transacoes.push(...(r?.transacoes ?? []));
      const total = Number(r?.totalPaginas ?? 1);
      if (pagina + 1 >= total || !(r?.transacoes?.length)) break;
    }

    const movimentacoes = normalizar(transacoes);
    const { data, error } = await admin.rpc("contas_gravar_extrato", {
      p_conta_id: c.conta_id,
      p_saldo: disponivel,
      p_movimentacoes: movimentacoes,
    });
    if (error) throw new Error(`Gravar extrato: ${error.message}`);
    return { saldo: disponivel, ...data };
  } finally {
    client.close();
  }
}

/** Token vale ~1h; guarda e reaproveita (o Inter limita pedidos de token). */
async function obterToken(c: Credencial, client: Deno.HttpClient): Promise<string> {
  if (c.token && c.token_expira_em && new Date(c.token_expira_em).getTime() - Date.now() > 5 * 60_000) {
    return c.token;
  }
  const r = await fetch(`${INTER}/oauth/v2/token`, {
    method: "POST",
    client,
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: c.client_id,
      client_secret: c.client_secret,
      grant_type: "client_credentials",
      scope: "extrato.read",
    }),
  });
  const texto = await r.text();
  if (!r.ok) throw new Error(`Inter recusou o acesso (${r.status}): ${resumo(texto)}`);
  const t = JSON.parse(texto);
  const expira = new Date(Date.now() + Number(t.expires_in ?? 3600) * 1000).toISOString();
  await admin.rpc("contas_salvar_token", { p_conta_id: c.conta_id, p_token: t.access_token, p_expira_em: expira });
  return t.access_token;
}

async function chamar(url: string, init: RequestInit & { client: Deno.HttpClient }, oQue: string) {
  const r = await fetch(url, init);
  const texto = await r.text();
  if (!r.ok) throw new Error(`Inter (${oQue}) respondeu ${r.status}: ${resumo(texto)}`);
  return texto ? JSON.parse(texto) : null;
}

/**
 * Transação do extrato completo → formato de movimentacoes_financeiras.
 * Sem idTransacao, o id vira data+valor+título+ordem no dia (estável entre
 * consultas do mesmo período).
 */
function normalizar(transacoes: any[]) {
  const ordem = new Map<string, number>();
  return transacoes.map((t) => {
    const d = t.detalhes ?? {};
    const valor = Math.abs(numero(t.valor) ?? 0);
    const data = String(t.dataTransacao ?? t.dataEntrada ?? t.dataInclusao ?? "").slice(0, 10);
    const entrada = String(t.tipoOperacao ?? "").toUpperCase() === "C";
    let id = t.idTransacao ? String(t.idTransacao) : "";
    if (!id) {
      const chave = `${data}|${valor.toFixed(2)}|${t.tipoOperacao}|${t.titulo ?? ""}|${t.descricao ?? ""}`;
      const n = (ordem.get(chave) ?? 0) + 1;
      ordem.set(chave, n);
      id = `h:${chave}|${n}`;
    }
    const descricao = [t.titulo, t.descricao].filter((s) => s && String(s).trim()).join(" - ") || null;
    return {
      id_externo: id,
      data,
      data_hora: t.dataInclusao ?? null,
      tipo: entrada ? "entrada" : "saida",
      valor,
      descricao,
      contraparte_nome: entrada
        ? (d.nomePagador ?? d.nomeEmpresa ?? d.nomeRemetente ?? null)
        : (d.nomeRecebedor ?? d.nomeBeneficiario ?? d.nomeEmpresa ?? null),
      contraparte_documento: entrada
        ? (d.cpfCnpjPagador ?? d.cpfCnpjRemetente ?? null)
        : (d.cpfCnpjRecebedor ?? d.cpfCnpjBeneficiario ?? null),
      codigo_pix: d.endToEndId ?? d.txid ?? null,
      dados_brutos: { tipoTransacao: t.tipoTransacao, titulo: t.titulo, detalhes: d },
    };
  }).filter((m) => m.valor > 0 && m.data.length === 10);
}

function numero(v: unknown): number | null {
  if (v == null || v === "") return null;
  const n = typeof v === "number" ? v : Number(String(v).replace(",", "."));
  return Number.isFinite(n) ? n : null;
}

function dataBR(d: Date): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo" }).format(d);
}

function resumo(texto: string): string {
  return texto.replace(/\s+/g, " ").slice(0, 200);
}
