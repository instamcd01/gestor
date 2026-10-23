// Guias do site, etapa 3 — Reel educativo novo no Instagram da loja vira
// RASCUNHO de guia (/loja/<slug>/dicas no site), pro dono aprovar no Gestor.
//
// Chamado pelo pg_cron (header `x-guias-segredo`, Vault
// `guias_rascunho_segredo`). Por loja em conteudos_guia_fontes:
//  1. lista os vídeos do Instagram publicados depois de `desde`;
//  2. pula os já analisados (conteudos_guia_posts);
//  3. transcreve a narração (OpenAI) e manda legenda + fala pro modelo, que
//     decide se é educativo e escreve o guia — ou junta como "parte 2" num
//     rascunho da mesma conversa;
//  4. copia vídeo e capa pro Storage (o link do Instagram expira) e grava o
//     rascunho + notificação (push) pro dono.
// O modelo só escreve rascunho: nada vai ao ar sem o dono publicar.
// Um post por loja por chamada — transcrição + escrita levam ~30-60 s.
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const admin = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const GRAPH = "https://graph.facebook.com/v23.0";
const BUCKET = "conteudo-social";
const MODELO = "gpt-4.1";
const MAX_TENTATIVAS = 3;

type Fonte = {
  empresa_id: string;
  catalogo_slug: string;
  ig_id: string;
  desde: string;
  token: string | null;
  openai_key: string | null;
};
type Midia = {
  id: string;
  caption?: string;
  media_type: string;
  media_url?: string;
  thumbnail_url?: string;
  permalink: string;
  timestamp: string;
};
type Bloco = { tipo: "h2" | "p" | "lista" | "passos"; texto: string | null; itens: string[] | null };
type Resposta = {
  educativo: boolean;
  motivo: string;
  guia_existente_id: string | null;
  titulo_video: string;
  guia: {
    slug: string;
    titulo: string;
    resumo: string;
    resposta_curta: string;
    corpo: Bloco[];
    perguntas: { pergunta: string; resposta: string }[];
    serie: string | null;
    tema: string;
    especie: "cao" | "gato" | "ambos";
    categorias_relacionadas: string[];
  } | null;
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  const { data: ok } = await admin.rpc("guias_conferir_segredo", { p_segredo: req.headers.get("x-guias-segredo") ?? "" });
  if (!ok) return json({ erro: "não autorizado" }, 401);

  const { data: fontes, error } = await admin.rpc("guias_fontes_para_processar");
  if (error) return json({ erro: error.message }, 500);

  const resultados = [];
  for (const fonte of (fontes ?? []) as Fonte[]) {
    try {
      resultados.push({ empresa: fonte.catalogo_slug, ...(await processarFonte(fonte)) });
    } catch (e) {
      console.error("[guias-rascunho]", fonte.catalogo_slug, e);
      resultados.push({ empresa: fonte.catalogo_slug, erro: (e as Error).message });
    }
  }
  return json({ resultados });
});

async function processarFonte(fonte: Fonte) {
  if (!fonte.token || !fonte.openai_key) return { pulado: "sem token do Instagram ou chave da OpenAI no Vault" };

  const campos = "id,caption,media_type,media_url,thumbnail_url,permalink,timestamp";
  const r = await fetch(`${GRAPH}/${fonte.ig_id}/media?fields=${campos}&limit=15&access_token=${encodeURIComponent(fonte.token)}`);
  const corpo = await r.json();
  if (!r.ok) throw new Error(`Instagram: ${corpo?.error?.message ?? r.status}`);

  const desde = Date.parse(fonte.desde);
  const videos = ((corpo.data ?? []) as Midia[])
    .filter((m) => m.media_type === "VIDEO" && Date.parse(m.timestamp) >= desde && m.media_url)
    .sort((a, b) => Date.parse(a.timestamp) - Date.parse(b.timestamp));
  if (!videos.length) return { novos: 0 };

  const { data: vistos } = await admin
    .from("conteudos_guia_posts")
    .select("ig_media_id, decisao, tentativas")
    .eq("empresa_id", fonte.empresa_id)
    .in("ig_media_id", videos.map((v) => v.id));
  const jaVisto = new Map((vistos ?? []).map((v) => [v.ig_media_id, v]));
  const proximo = videos.find((v) => {
    const visto = jaVisto.get(v.id);
    return !visto || (visto.decisao === "erro" && visto.tentativas < MAX_TENTATIVAS);
  });
  if (!proximo) return { novos: 0 };

  try {
    return { post: proximo.permalink, ...(await processarPost(fonte, proximo)) };
  } catch (e) {
    const tentativas = (jaVisto.get(proximo.id)?.tentativas ?? 0) + 1;
    await admin.from("conteudos_guia_posts").upsert({
      empresa_id: fonte.empresa_id,
      ig_media_id: proximo.id,
      decisao: "erro",
      motivo: (e as Error).message.slice(0, 500),
      permalink: proximo.permalink,
      tentativas,
    });
    throw e;
  }
}

async function processarPost(fonte: Fonte, midia: Midia) {
  const video = new Uint8Array(await (await fetch(midia.media_url!)).arrayBuffer());
  const fala = await transcrever(video, fonte.openai_key!);

  const [{ data: rascunhos }, { data: categorias }] = await Promise.all([
    admin
      .from("conteudos_guia")
      .select("id, titulo, resumo, resposta_curta, corpo, perguntas, serie, tema, especie, categorias_relacionadas, videos")
      .eq("empresa_id", fonte.empresa_id)
      .eq("status", "rascunho")
      .gte("created_at", new Date(Date.now() - 14 * 86_400_000).toISOString()),
    admin.from("catalogo_categorias_publico").select("nome").eq("empresa_id", fonte.empresa_id),
  ]);
  const nomesCategorias = (categorias ?? []).map((c: { nome: string }) => c.nome);

  const resposta = await escrever(fonte.openai_key!, midia.caption ?? "", fala, rascunhos ?? [], nomesCategorias);
  if (!resposta.educativo || !resposta.guia) {
    await admin.from("conteudos_guia_posts").upsert({
      empresa_id: fonte.empresa_id,
      ig_media_id: midia.id,
      decisao: "ignorado",
      motivo: resposta.motivo.slice(0, 500),
      permalink: midia.permalink,
    });
    return { decisao: "ignorado", motivo: resposta.motivo };
  }

  const g = resposta.guia;
  const existente = (rascunhos ?? []).find((x: { id: string }) => x.id === resposta.guia_existente_id);
  const slug = existente ? null : await slugLivre(fonte.empresa_id, g.slug);
  const pasta = `guias/${fonte.catalogo_slug}/${midia.id}`;
  const urlVideo = await subir(`${pasta}.mp4`, video, "video/mp4");
  const urlCapa = midia.thumbnail_url
    ? await subir(`${pasta}.jpg`, new Uint8Array(await (await fetch(midia.thumbnail_url)).arrayBuffer()), "image/jpeg")
    : null;
  const novoVideo = {
    titulo: resposta.titulo_video,
    url: urlVideo,
    capa_url: urlCapa,
    duracao_s: duracaoMp4(video),
    instagram_url: midia.permalink,
    publicado_em: new Date(midia.timestamp).toISOString(),
  };

  const campos = {
    titulo: g.titulo,
    resumo: g.resumo.slice(0, 160),
    resposta_curta: g.resposta_curta,
    corpo: g.corpo.map(limparBloco).filter(Boolean),
    perguntas: g.perguntas,
    serie: g.serie,
    tema: g.tema,
    especie: g.especie,
    categorias_relacionadas: g.categorias_relacionadas.filter((c) => nomesCategorias.includes(c)),
  };

  let guiaId: string;
  if (existente) {
    const { error } = await admin
      .from("conteudos_guia")
      .update({ ...campos, videos: [...(existente.videos ?? []), novoVideo] })
      .eq("id", existente.id);
    if (error) throw new Error(`gravar rascunho: ${error.message}`);
    guiaId = existente.id;
  } else {
    const { data, error } = await admin
      .from("conteudos_guia")
      .insert({ ...campos, empresa_id: fonte.empresa_id, slug, videos: [novoVideo], capa_url: urlCapa, status: "rascunho" })
      .select("id")
      .single();
    if (error) throw new Error(`gravar rascunho: ${error.message}`);
    guiaId = data.id;
  }

  await admin.from("conteudos_guia_posts").upsert({
    empresa_id: fonte.empresa_id,
    ig_media_id: midia.id,
    decisao: "guia",
    guia_id: guiaId,
    motivo: resposta.motivo.slice(0, 500),
    permalink: midia.permalink,
  });
  await admin.from("notificacoes").insert({
    empresa_id: fonte.empresa_id,
    tipo: "guia_rascunho",
    titulo: existente ? "Parte 2 juntada no rascunho do site" : "Dica nova pro site esperando aprovação",
    mensagem: `"${g.titulo}" — confira o texto e publique em Catálogo Online > Dicas.`,
    entidade_tipo: "conteudos_guia",
    entidade_id: guiaId,
  });
  return { decisao: existente ? "juntado" : "rascunho", guia_id: guiaId, titulo: g.titulo };
}

async function transcrever(video: Uint8Array<ArrayBuffer>, chave: string): Promise<string> {
  const form = new FormData();
  form.append("file", new Blob([video], { type: "video/mp4" }), "reel.mp4");
  form.append("model", "gpt-4o-transcribe");
  form.append("language", "pt");
  const r = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: { Authorization: `Bearer ${chave}` },
    body: form,
  });
  const corpo = await r.json();
  if (!r.ok) throw new Error(`transcrição: ${corpo?.error?.message ?? r.status}`);
  return (corpo.text ?? "").trim();
}

const INSTRUCOES = `Você escreve os guias educativos do site de um pet shop de bairro, a partir dos Reels que a loja posta no Instagram.

Primeiro decida se o Reel é EDUCATIVO: ensina algo útil sobre cuidar de pet (alimentação, saúde, comportamento, raça, cuidados no calor etc.). NÃO é educativo: humor, bastidor, história de cliente, promoção, sorteio, anúncio de produto. Na dúvida, não é. Se não for, devolva educativo=false, explique em "motivo" e guia=null.

Se for, escreva o guia em português do Brasil do dia a dia, frases curtas, falando com o dono do pet ("você"):
- titulo = a PERGUNTA que a pessoa digitaria no Google (ex.: "Cachorro pode comer ovo?"); sem nome da série nem emoji.
- slug = titulo em minúsculas, sem acento, palavras separadas por hífen (palavra composta mantém o hífen: "vira-lata"), até 60 letras.
- resumo = até 155 letras, responde e convida a ler.
- resposta_curta = 2 a 4 frases respondendo direto, como no começo de um bom artigo.
- corpo = 3 a 5 seções: cada seção abre com um bloco h2 e segue com blocos p, lista ou passos ("passos" = sequência numerada). Use texto em h2/p e itens em lista/passos; o outro campo vai null.
- perguntas = 3 ou 4 dúvidas relacionadas que a pessoa também teria, com resposta curta.
- Explique o PORQUÊ, não só a regra. Vá além do vídeo só com o que é consenso e bem estabelecido em cuidado de pets; não invente estudo, número, estatística ou marca.
- Saúde: nunca diagnóstico, remédio, dose ou promessa de cura; sinais de alerta e casos especiais terminam em "procure o veterinário". Frequência de vacina, vermífugo ou antipulgas: sempre "no calendário/na frequência que o veterinário orientar", nunca um intervalo fixo ("todo ano", "a cada 3 meses").
- categorias_relacionadas = 1 ou 2 categorias da lista dada que combinam com o tema (só nomes exatos da lista). Se o texto fala de um tipo de produto que a lista tem (ração, petisco, sachê, vermífugo, antipulgas, areia…), escolha essa categoria. Vazio só se nenhuma combina.
- serie = nome da série se a legenda/hashtag indicar (ex.: "Mito ou Verdade", "Pergunta da Semana", "Sinal de Alerta", "Lê o Rótulo", "Gato Não É Cachorro Pequeno", "Raça em 30s", "Pet no Rio"), senão null.
- titulo_video = título curto deste vídeo (ex.: "O jeito certo de guardar a ração").

PARTE 2: se a lista de rascunhos abertos tiver um do MESMO assunto (o vídeo continua ou completa aquele, ex.: parte 1 "pode?" e parte 2 "como fazer"), devolva guia_existente_id com o id dele e um guia COMPLETO que junta o que já estava lá com o conteúdo novo. Senão, guia_existente_id = null.`;

const SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["educativo", "motivo", "guia_existente_id", "titulo_video", "guia"],
  properties: {
    educativo: { type: "boolean" },
    motivo: { type: "string" },
    guia_existente_id: { type: ["string", "null"] },
    titulo_video: { type: "string" },
    guia: {
      anyOf: [
        { type: "null" },
        {
          type: "object",
          additionalProperties: false,
          required: ["slug", "titulo", "resumo", "resposta_curta", "corpo", "perguntas", "serie", "tema", "especie", "categorias_relacionadas"],
          properties: {
            slug: { type: "string" },
            titulo: { type: "string" },
            resumo: { type: "string" },
            resposta_curta: { type: "string" },
            corpo: {
              type: "array",
              items: {
                type: "object",
                additionalProperties: false,
                required: ["tipo", "texto", "itens"],
                properties: {
                  tipo: { type: "string", enum: ["h2", "p", "lista", "passos"] },
                  texto: { type: ["string", "null"] },
                  itens: { anyOf: [{ type: "null" }, { type: "array", items: { type: "string" } }] },
                },
              },
            },
            perguntas: {
              type: "array",
              items: {
                type: "object",
                additionalProperties: false,
                required: ["pergunta", "resposta"],
                properties: { pergunta: { type: "string" }, resposta: { type: "string" } },
              },
            },
            serie: { type: ["string", "null"] },
            tema: { type: "string", enum: ["alimentacao", "saude", "comportamento", "gatos", "racas", "cuidados", "outros"] },
            especie: { type: "string", enum: ["cao", "gato", "ambos"] },
            categorias_relacionadas: { type: "array", items: { type: "string" } },
          },
        },
      ],
    },
  },
};

async function escrever(
  chave: string,
  legenda: string,
  fala: string,
  rascunhos: Record<string, unknown>[],
  categorias: string[],
): Promise<Resposta> {
  const abertos = rascunhos.map((r) => ({
    id: r.id,
    titulo: r.titulo,
    resumo: r.resumo,
    resposta_curta: r.resposta_curta,
    corpo: r.corpo,
    perguntas: r.perguntas,
    serie: r.serie,
  }));
  const pedido = `LEGENDA DO REEL:\n${legenda || "(sem legenda)"}\n\nNARRAÇÃO (transcrita):\n${fala || "(sem narração)"}\n\nCATEGORIAS DO CATÁLOGO:\n${categorias.join("; ")}\n\nRASCUNHOS ABERTOS (pra decidir se é parte 2):\n${abertos.length ? JSON.stringify(abertos) : "(nenhum)"}`;
  const r = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: `Bearer ${chave}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: MODELO,
      temperature: 0.4,
      messages: [
        { role: "system", content: INSTRUCOES },
        { role: "user", content: pedido },
      ],
      response_format: { type: "json_schema", json_schema: { name: "guia", strict: true, schema: SCHEMA } },
    }),
  });
  const corpo = await r.json();
  if (!r.ok) throw new Error(`escrita: ${corpo?.error?.message ?? r.status}`);
  const msg = corpo.choices?.[0]?.message;
  if (msg?.refusal || !msg?.content) throw new Error(`escrita recusada: ${msg?.refusal ?? "vazia"}`);
  return JSON.parse(msg.content) as Resposta;
}

function limparBloco(b: Bloco) {
  if (b.tipo === "h2" || b.tipo === "p") return b.texto?.trim() ? { tipo: b.tipo, texto: b.texto.trim() } : null;
  const itens = (b.itens ?? []).map((i) => i.trim()).filter(Boolean);
  return itens.length ? { tipo: b.tipo, itens } : null;
}

async function slugLivre(empresaId: string, base: string): Promise<string> {
  const limpo = base
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60)
    .replace(/-+$/g, "") || "dica";
  const { data } = await admin.from("conteudos_guia").select("slug").eq("empresa_id", empresaId).like("slug", `${limpo}%`);
  const usados = new Set((data ?? []).map((d: { slug: string }) => d.slug));
  if (!usados.has(limpo)) return limpo;
  for (let i = 2; ; i++) if (!usados.has(`${limpo}-${i}`)) return `${limpo}-${i}`;
}

async function subir(caminho: string, bytes: Uint8Array, tipo: string): Promise<string> {
  const { error } = await admin.storage.from(BUCKET).upload(caminho, bytes, {
    contentType: tipo,
    upsert: true,
    cacheControl: "31536000",
  });
  if (error) throw new Error(`storage: ${error.message}`);
  return admin.storage.from(BUCKET).getPublicUrl(caminho).data.publicUrl;
}

/** Duração pelo cabeçalho `mvhd` do mp4 (sem ffprobe na Edge). */
function duracaoMp4(b: Uint8Array): number | null {
  for (let i = 0; i < b.length - 32; i++) {
    if (b[i] === 0x6d && b[i + 1] === 0x76 && b[i + 2] === 0x68 && b[i + 3] === 0x64) {
      const v = new DataView(b.buffer, b.byteOffset + i + 4);
      const versao = v.getUint8(0);
      const escala = versao === 1 ? v.getUint32(20) : v.getUint32(12);
      const duracao = versao === 1 ? Number(v.getBigUint64(24)) : v.getUint32(16);
      return escala ? Math.round(duracao / escala) : null;
    }
  }
  return null;
}
