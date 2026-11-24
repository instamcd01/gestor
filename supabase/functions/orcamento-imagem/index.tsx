// Orçamento em imagem do pedido fechado pela atendente do WhatsApp (24/11).
// Mesmo layout do OrcamentoImagemWidget do Gestor (lib/widgets/orcamento_imagem_widget.dart), desenhado no
// servidor porque a atendente não tem o app aberto. Recebe { conversa_id }, lê os dados em
// whatsapp_orcamento_dados, desenha o PNG (layout.js), salva no bucket público "orcamentos" e devolve { url }.
// Chamada pelo n8n com o cabeçalho x-orcamento-segredo (valor em whatsapp_atendente_parametros).
import { ImageResponse } from "https://deno.land/x/og_edge@0.0.4/mod.ts";
import { encodeBase64 } from "jsr:@std/encoding@1/base64";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { montar, tamanhoPng, LARGURA } from "./layout.js";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

// mesma forma de elemento que o React gera; o satori (dentro do og_edge) aceita
// deno-lint-ignore no-explicit-any
const h = (type: string, props: any, ...children: any[]) => ({ type, key: null, props: { ...props, children: children.length === 1 ? children[0] : children } });

let fontes: { name: string; data: ArrayBuffer; weight: 400 | 600 | 700 | 800; style: "normal" }[] | null = null;
async function carregarFontes() {
  if (fontes) return fontes;
  fontes = await Promise.all(([400, 600, 700, 800] as const).map(async (w) => ({
    name: "Inter", weight: w, style: "normal" as const,
    data: await (await fetch(`https://cdn.jsdelivr.net/fontsource/fonts/inter@5.0.16/latin-${w}-normal.woff`)).arrayBuffer(),
  })));
  return fontes;
}

async function baixar(url: string) {
  const r = await fetch(url);
  if (!r.ok) return null;
  return { bytes: new Uint8Array(await r.arrayBuffer()), tipo: r.headers.get("content-type") || "image/jpeg" };
}

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") return json(405, { erro: "use POST" });
    const { data: seg } = await admin.from("whatsapp_atendente_parametros").select("valor").eq("nome", "orcamento_segredo").maybeSingle();
    if (!seg || req.headers.get("x-orcamento-segredo") !== seg.valor) return json(401, { erro: "sem permissão" });

    const { conversa_id } = await req.json();
    const { data: dados, error } = await admin.rpc("whatsapp_orcamento_dados", { p_conversa_id: conversa_id });
    if (error) return json(500, { erro: error.message });
    if (!dados || !dados.itens?.length) return json(200, { url: null, motivo: "sem itens" });

    // logo e fotos viram data URI: o desenho não depende do motor baixar sozinho
    let logo = null;
    if (dados.logo) {
      const b = await baixar(dados.logo);
      const t = b && tamanhoPng(b.bytes);
      if (b && t) logo = { src: `data:image/png;base64,${encodeBase64(b.bytes)}`, ...t };
    }
    await Promise.all(dados.itens.map(async (i: { foto: string | null }) => {
      if (!i.foto) return;
      const b = await baixar(i.foto);
      i.foto = b ? `data:${b.tipo};base64,${encodeBase64(b.bytes)}` : null;
    }));

    const { arvore, altura } = montar(dados, h, logo);
    const resp = new ImageResponse(arvore, { width: LARGURA, height: altura, fonts: await carregarFontes() });
    const png = new Uint8Array(await resp.arrayBuffer());
    const caminho = `${dados.empresa_id}/atendente-${crypto.randomUUID()}.png`;
    const up = await admin.storage.from("orcamentos").upload(caminho, png, { contentType: "image/png" });
    if (up.error) return json(500, { erro: up.error.message });
    const { data: pub } = admin.storage.from("orcamentos").getPublicUrl(caminho);
    return json(200, { url: pub.publicUrl, altura });
  } catch (e) {
    return json(500, { erro: String(e) });
  }
});
