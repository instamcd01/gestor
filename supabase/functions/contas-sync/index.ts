// Contas e Conferência — sincronização das contas conectadas por API que
// o Gestor chama direto (Banco Inter com certificado/mTLS; Stone pela API
// de Conciliação com a chave do Portal Stone).
//
// Dois jeitos de chamar:
//  * agendador (pg_cron → pg_net): header `x-contas-sync` com o segredo do
//    Vault `contas_sync_segredo` → sincroniza todas as contas Inter/Stone de
//    todas as lojas;
//  * app (logo depois de conectar): JWT do usuário + {"conta_id"} → só
//    aquela conta, e só se o usuário enxerga ela (RLS).
//
// Credenciais vêm de contas_credenciais_para_sincronizar() (Vault), nunca
// passam pelo app. Só leitura (Inter: escopo `extrato.read`).
import { createClient } from "jsr:@supabase/supabase-js@2";
import { XMLParser } from "npm:fast-xml-parser@4.5.0";

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

  const resultados = [];
  for (const provedor of ["inter", "stone"] as const) {
    const { data: creds, error } = await admin.rpc("contas_credenciais_para_sincronizar", {
      p_provedor: provedor,
      p_conta_id: contaId,
    });
    if (error) return json({ erro: error.message }, 500);
    for (const c of (creds ?? []) as Credencial[]) {
      resultados.push(await sincronizarConta(provedor, c));
    }
  }
  return json({ contas: resultados.length, resultados });
});

async function sincronizarConta(provedor: "inter" | "stone", c: Credencial) {
  try {
    const r = provedor === "inter" ? await sincronizarInter(c) : await sincronizarStone(c);
    return { conta_id: c.conta_id, provedor, ...r };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    await admin.rpc("contas_registrar_erro_conta", { p_conta_id: c.conta_id, p_erro: msg });
    return { conta_id: c.conta_id, provedor, erro: msg };
  }
}

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

// ───────────────────────────── Stone ─────────────────────────────
// Arquivo de conciliação diário (layout 2.2, XML). Cada arquivo traz as
// vendas capturadas no dia (bruto, líquido por parcela, previsão), os
// cancelamentos, os pagamentos que caíram na conta e os eventos financeiros
// (aluguel, ajustes). Fica pronto a partir das 5h do dia seguinte; 7
// pedidos/hora por StoneCode+dia, então baixa no máximo 12 dias por rodada.

const STONE = "https://conciliation.stone.com.br/v2/merchant";
const BANDEIRAS: Record<string, string> = {
  "1": "Visa", "2": "Mastercard", "3": "Amex", "4": "Cabal", "5": "UnionPay", "9": "Hipercard", "171": "Elo",
};
const CARTEIRAS: Record<string, string> = {
  "1": "movimentos não transacionais", "2": "Visa Débito", "3": "Visa Crédito", "4": "Visa Antecipação",
  "5": "Mastercard Débito", "6": "Mastercard Crédito", "7": "Mastercard Antecipação", "8": "Hiper Débito",
  "9": "Hiper Crédito", "10": "Hiper Antecipação", "11": "Elo Débito", "12": "Elo Crédito", "13": "Elo Antecipação",
  "14": "Amex Débito", "15": "Amex Crédito", "16": "Amex Antecipação", "17": "Boleto",
};
const xml = new XMLParser({
  ignoreAttributes: true,
  parseTagValue: false,
  isArray: (nome: string) => ["Transaction", "Installment", "Payment", "Cancellation", "Event"].includes(nome),
});

async function sincronizarStone(c: Credencial) {
  const { data: dias, error } = await admin.rpc("contas_dias_pendentes", { p_conta_id: c.conta_id, p_limite: 12 });
  if (error) throw new Error(error.message);
  const auth = "Basic " + btoa(`${c.client_secret}:`);
  let vendas = 0, ligadas = 0, ambiguas = 0, recebimentos = 0, baixados = 0;

  for (const dia of (dias ?? []) as string[]) {
    const ref = String(dia).slice(0, 10);
    const r = await fetch(`${STONE}/${c.client_id}/conciliation-file/${ref.replaceAll("-", "")}?layout=XML2_2`, {
      headers: { Authorization: auth, "Accept-Encoding": "gzip", "x-user-type": "client" },
    });
    if (r.status === 401) {
      throw new Error("Stone recusou a chave (401): confira se a chave da API de Conciliação está ativa no Portal Stone");
    }
    if (r.status === 403) throw new Error("A chave não tem acesso a este StoneCode (403)");
    if (r.status === 429) break;
    if (r.status === 404) {
      await admin.rpc("contas_marcar_arquivo", {
        p_conta_id: c.conta_id, p_data: ref, p_status: "indisponivel", p_detalhe: "404",
      });
      continue;
    }
    if (!r.ok) {
      await admin.rpc("contas_marcar_arquivo", {
        p_conta_id: c.conta_id, p_data: ref, p_status: "erro", p_detalhe: `${r.status} ${resumo(await r.text())}`,
      });
      continue;
    }

    const doc = xml.parse(await textoTalvezGzip(r))?.Conciliation ?? {};
    const transacoes: any[] = doc.FinancialTransactions?.Transaction ?? [];
    const novasVendas = transacoes
      .filter((t) => Number(t.Events?.Captures ?? 0) > 0 && t.CapturedAmount)
      .map(vendaStone);
    if (novasVendas.length) {
      const { data, error: e } = await admin.rpc("contas_gravar_vendas_cartao", {
        p_conta_id: c.conta_id, p_vendas: novasVendas,
      });
      if (e) throw new Error(`Gravar vendas: ${e.message}`);
      vendas += data.novas;
      ligadas += data.ligadas;
      ambiguas += data.ambiguas;
    }
    // Cancelamento de venda de outro dia: só atualiza o que já está gravado.
    for (const t of transacoes.filter((t) => Number(t.Events?.Cancellations ?? 0) > 0)) {
      const devolvido = ((t.Cancellations?.Cancellation ?? []) as any[]).reduce((s, x) => s + num(x.ReturnedAmount), 0);
      if (devolvido > 0) {
        await admin.from("vendas_cartao").update({ valor_cancelado: devolvido })
          .eq("conta_id", c.conta_id).eq("id_externo", String(t.AcquirerTransactionKey));
      }
    }

    const movs = [
      ...((doc.Payments?.Payment ?? []) as any[]).filter((p) => num(p.TotalAmount) > 0).map((p) => ({
        id_externo: `stone-pag:${p.Id}`,
        data: ref,
        tipo: "entrada",
        valor: num(p.TotalAmount),
        descricao: `Recebimento Stone — ${CARTEIRAS[String(p.WalletTypeId)] ?? `carteira ${p.WalletTypeId}`}`,
        dados_brutos: { carteira: p.WalletTypeId, conta: p.FavoredBankAccount },
      })),
      ...((doc.FinancialEvents?.Event ?? []) as any[]).filter((e) => num(e.Amount) !== 0).map((e) => ({
        id_externo: `stone-evt:${e.EventId}`,
        data: ref,
        tipo: num(e.Amount) > 0 ? "entrada" : "saida",
        valor: Math.abs(num(e.Amount)),
        descricao: `Stone — ${e.Description ?? "evento financeiro"}`,
        dados_brutos: { tipo: e.Type, previsao: e.PrevisionPaymentDate },
      })),
    ];
    recebimentos += movs.length;
    if (movs.length) {
      const { error: e } = await admin.rpc("contas_gravar_extrato", {
        p_conta_id: c.conta_id, p_saldo: null, p_movimentacoes: movs,
      });
      if (e) throw new Error(`Gravar recebimentos: ${e.message}`);
    }

    await admin.rpc("contas_marcar_arquivo", {
      p_conta_id: c.conta_id, p_data: ref, p_status: transacoes.length || movs.length ? "ok" : "vazio",
    });
    baixados++;
  }

  // Marca a sincronização mesmo sem nada novo (sem mexer no saldo).
  await admin.rpc("contas_gravar_extrato", { p_conta_id: c.conta_id, p_saldo: null, p_movimentacoes: [] });
  return { dias: baixados, vendas, ligadas, ambiguas, recebimentos };
}

function vendaStone(t: any) {
  const parcelas: any[] = t.Installments?.Installment ?? [];
  const liquido = parcelas.reduce((s, p) => s + num(p.NetAmount), 0);
  const datas = parcelas.map((p) => p.PrevisionPaymentDate).filter(Boolean).map(dataStone).sort();
  const tipos: Record<string, string> = { "1": "debito", "2": "credito", "3": "pre_pago", "4": "pre_pago", "5": "voucher" };
  return {
    id_externo: String(t.AcquirerTransactionKey),
    capturada_em: dataHoraStone(String(t.CaptureLocalDateTime)),
    tipo: tipos[String(t.AccountType)] ?? "outro",
    bandeira: BANDEIRAS[String(t.BrandId)] ?? (t.BrandId ? `bandeira ${t.BrandId}` : null),
    parcelas: Number(t.NumberOfInstallments ?? parcelas.length) || 1,
    valor_bruto: num(t.CapturedAmount),
    valor_liquido: Math.round(liquido * 100) / 100,
    previsao_pagamento: datas[0] ?? null,
    ultima_parcela_em: datas[datas.length - 1] ?? null,
    codigo_autorizacao: t.IssuerAuthorizationCode ?? null,
    cartao_final: t.CardNumber ? String(t.CardNumber).slice(-4) : null,
    valor_cancelado: num(t.CanceledAmount),
    dados_brutos: { brandId: t.BrandId, accountType: t.AccountType, feeType: t.FeeType, poi: t.Poi?.PoiType },
  };
}

/** A Stone manda gzip às vezes como arquivo (sem Content-Encoding): descompacta na mão. */
async function textoTalvezGzip(r: Response): Promise<string> {
  const bytes = new Uint8Array(await r.arrayBuffer());
  if (bytes[0] === 0x1f && bytes[1] === 0x8b) {
    const fluxo = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip"));
    return await new Response(fluxo).text();
  }
  return new TextDecoder().decode(bytes);
}

const num = (v: unknown) => numero(v) ?? 0;
/** aaaammdd → aaaa-mm-dd */
const dataStone = (v: string) => `${v.slice(0, 4)}-${v.slice(4, 6)}-${v.slice(6, 8)}`;
/** aaaammddHHmmss (horário local da Stone, Brasília) → ISO com fuso */
const dataHoraStone = (v: string) =>
  `${dataStone(v)}T${v.slice(8, 10) || "00"}:${v.slice(10, 12) || "00"}:${v.slice(12, 14) || "00"}-03:00`;
