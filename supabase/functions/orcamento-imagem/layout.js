// Layout do orçamento (mesmo do OrcamentoImagemWidget do Gestor). Puro: recebe os dados e uma função h(tipo, props, ...filhos).
export const LARGURA = 540;
const TEXTO = "#1E1E24", APAGADO = "#5B5B66", LINHA = "#E6E6EA", VERDE = "#1F7A45", VERDE_FUNDO = "#E7F5EC", TRILHA = "#D5DEE8";
export const moeda = (v) => "R$ " + v.toFixed(2).replace(".", ",").replace(/\B(?=(\d{3})+(?!\d))/g, ".");
export const nomeCurto = (n) => n.split(/\s+[–—-]\s+/)[0].trim();

function corDoTextoSobre(hex) {
  const x = hex.replace("#", "");
  const [r, g, b] = [0, 2, 4].map((i) => parseInt(x.slice(i, i + 2), 16) / 255);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.6 ? TEXTO : "#FFFFFF";
}

// Largura/altura de um PNG pelos bytes do cabeçalho (IHDR) — o satori exige o tamanho da imagem.
export function tamanhoPng(bytes) {
  const v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (bytes.length < 24 || v.getUint32(0) !== 0x89504e47) return null;
  return { w: v.getUint32(16), h: v.getUint32(20) };
}

// Lista de produtos da atendente numa imagem só (24/11): número, foto, nome e preço de cada opção.
// Antes ia uma foto por produto e o WhatsApp entregava fora de ordem.
export function montarLista(dados, h, logo) {
  const itens = dados.itens.map((i) => ({ ...i, preco: Number(i.preco), preco_cheio: i.preco_cheio == null ? null : Number(i.preco_cheio) }));
  const sobre = corDoTextoSobre(dados.cor);
  const W = LARGURA - 48;
  // nome curto do WhatsApp ("Sachê Whiskas gato adulto carne 85g") e o R$/kg que a busca já calculou
  const partes = (i) => {
    const l = String(i.linha || nomeCurto(i.nome || ""));
    const nome = l.split(/\s+[—–]\s+/)[0].trim();
    const kg = (l.match(/\((R\$\s?[\d.,]+\/kg)\)/) || [])[1] || null;
    return { nome, kg };
  };
  // linha = 17px × 1,3 ≈ 22; foto 76 + 20 de respiro; rodapé 12 + 48 + 16 de margem (medido no PNG de 24/11)
  const alturaItem = (i) => Math.max(76, Math.ceil(partes(i).nome.length / 27) * 22 + (partes(i).kg ? 22 : 0)) + 20;
  const altura = 92 + 8 + itens.reduce((s, i) => s + alturaItem(i) + 1, 0) + 76;

  const cabecalho = h("div", { style: { display: "flex", width: LARGURA, height: 92, alignItems: "center", backgroundColor: dados.cor, paddingLeft: 24, paddingRight: 24 } },
    h("div", { style: { display: "flex", flexGrow: 1, alignItems: "center" } },
      logo
        ? h("img", { src: logo.src, width: Math.round(56 * logo.w / logo.h), height: 56 })
        : h("div", { style: { display: "flex", fontSize: 24, fontWeight: 800, color: sobre } }, dados.loja)),
    h("div", { style: { display: "flex", flexDirection: "column", alignItems: "flex-end" } },
      h("div", { style: { display: "flex", fontSize: 16, fontWeight: 700, color: sobre } }, "Opções pra você"),
      h("div", { style: { display: "flex", fontSize: 14, color: sobre } }, dados.data)));

  const blocos = [];
  itens.forEach((i, idx) => {
    if (idx > 0) blocos.push(h("div", { style: { display: "flex", width: W, height: 1, backgroundColor: LINHA, marginLeft: 24 } }));
    const { nome, kg } = partes(i);
    const promo = !!i.preco_cheio && i.preco_cheio > i.preco;
    const direita = [];
    if (promo) direita.push(h("div", { style: { display: "flex", fontSize: 15, color: APAGADO, textDecoration: "line-through", whiteSpace: "nowrap" } }, moeda(i.preco_cheio)));
    direita.push(h("div", { style: { display: "flex", whiteSpace: "nowrap", fontSize: 20, fontWeight: 800, color: promo ? VERDE : TEXTO } }, moeda(i.preco)));
    const texto = [h("div", { style: { display: "flex", fontSize: 17, lineHeight: 1.3, fontWeight: 600, color: TEXTO } }, nome)];
    if (kg) texto.push(h("div", { style: { display: "flex", fontSize: 14, color: APAGADO, marginTop: 4 } }, `sai a ${kg.replace(/\s/g, " ")}`));
    blocos.push(
      h("div", { style: { display: "flex", width: LARGURA, alignItems: "center", paddingLeft: 24, paddingRight: 24, paddingTop: 10, paddingBottom: 10 } },
        h("div", { style: { display: "flex", width: 34, height: 34, flexShrink: 0, borderRadius: 17, backgroundColor: dados.cor, color: sobre, fontSize: 18, fontWeight: 800, alignItems: "center", justifyContent: "center" } }, String(i.n)),
        h("div", { style: { display: "flex", width: 76, height: 76, flexShrink: 0, marginLeft: 12, border: `1px solid ${LINHA}`, borderRadius: 10, backgroundColor: "#FFFFFF", alignItems: "center", justifyContent: "center" } },
          i.foto ? h("img", { src: i.foto, width: 68, height: 68, style: { objectFit: "contain" } }) : h("div", { style: { display: "flex" } }, "")),
        h("div", { style: { display: "flex", flexDirection: "column", flexGrow: 1, flexShrink: 1, width: W - 34 - 12 - 76 - 14 - 12 - 112, marginLeft: 14 } }, ...texto),
        h("div", { style: { display: "flex", flexDirection: "column", alignItems: "flex-end", flexShrink: 0, width: 112, marginLeft: 12 } }, ...direita)));
  });

  const rodape = h("div", { style: { display: "flex", width: W, marginLeft: 24, marginTop: 12, padding: "12px 16px", backgroundColor: "#F0F6FD", borderRadius: 12, alignItems: "center" } },
    h("div", { style: { display: "flex", fontSize: 16, color: TEXTO } }, "É só responder com o"),
    h("div", { style: { display: "flex", fontSize: 16, fontWeight: 800, color: TEXTO, marginLeft: 5 } }, "número"),
    h("div", { style: { display: "flex", fontSize: 16, color: TEXTO, marginLeft: 5 } }, "da opção que quiser"));

  const arvore = h("div", { style: { display: "flex", flexDirection: "column", width: LARGURA, height: altura, backgroundColor: "#FFFFFF", fontFamily: "Inter" } },
    cabecalho, h("div", { style: { display: "flex", height: 8 } }), ...blocos, rodape);
  return { arvore, altura };
}

export function montar(dados, h, logo) {
  const itens = dados.itens.map((i) => ({ ...i, preco: Number(i.preco), preco_cheio: i.preco_cheio == null ? null : Number(i.preco_cheio) }));
  const sub = itens.reduce((s, i) => s + i.qtd * i.preco, 0);
  const subCheio = itens.reduce((s, i) => s + i.qtd * (i.preco_cheio && i.preco_cheio > i.preco ? i.preco_cheio : i.preco), 0);
  const descPromo = subCheio - sub;
  const entrega = Number(dados.entrega || 0);
  const total = sub + entrega;
  const minimo = dados.minimo_frete_gratis ? Number(dados.minimo_frete_gratis) : null;
  const falta = minimo && entrega > 0 && sub < minimo ? minimo - sub : 0;
  const mostrarMeta = !!minimo && falta > 0 && falta <= minimo * 0.5; // longe demais desanima (regra do Gestor)
  const economia = descPromo;
  const sobre = corDoTextoSobre(dados.cor);
  const W = LARGURA - 48; // conteúdo dentro das margens de 24

  const alturaItem = (i) => Math.max(68, Math.ceil(nomeCurto(i.nome).length / 30) * 22 + 28) + 24;
  const altura = 92 + 8 + itens.reduce((s, i) => s + alturaItem(i) + 1, 0)
    + 8 + 15 + (descPromo >= 0.01 ? 3 : 2) * 28 + 52
    + (mostrarMeta ? 84 : 0) + (economia >= 0.01 ? 66 : 0) + 4;

  const linhaResumo = (rotulo, valor, cor = APAGADO) =>
    h("div", { style: { display: "flex", width: W, alignItems: "center", marginBottom: 6 } },
      h("div", { style: { display: "flex", flexGrow: 1, fontSize: 16, color: cor } }, rotulo),
      h("div", { style: { display: "flex", fontSize: 16, fontWeight: 600, color: cor } }, valor));

  const cabecalho = h("div", { style: { display: "flex", width: LARGURA, height: 92, alignItems: "center", backgroundColor: dados.cor, paddingLeft: 24, paddingRight: 24 } },
    h("div", { style: { display: "flex", flexGrow: 1, alignItems: "center" } },
      logo
        ? h("img", { src: logo.src, width: Math.round(56 * logo.w / logo.h), height: 56 })
        : h("div", { style: { display: "flex", fontSize: 24, fontWeight: 800, color: sobre } }, dados.loja)),
    h("div", { style: { display: "flex", flexDirection: "column", alignItems: "flex-end" } },
      h("div", { style: { display: "flex", fontSize: 16, fontWeight: 700, color: sobre } }, "Orçamento"),
      h("div", { style: { display: "flex", fontSize: 14, color: sobre } }, dados.data)));

  const blocosItens = [];
  itens.forEach((i, idx) => {
    if (idx > 0) blocosItens.push(h("div", { style: { display: "flex", width: W, height: 1, backgroundColor: LINHA, marginLeft: 24 } }));
    const promo = !!i.preco_cheio && i.preco_cheio > i.preco;
    const pct = promo ? Math.round((1 - i.preco / i.preco_cheio) * 100) : 0;
    const direita = [];
    if (promo) direita.push(h("div", { style: { display: "flex", fontSize: 15, color: APAGADO, textDecoration: "line-through" } }, moeda(i.qtd * i.preco_cheio)));
    direita.push(h("div", { style: { display: "flex", fontSize: 18, fontWeight: 700, color: promo ? VERDE : TEXTO } }, moeda(i.qtd * i.preco)));
    const linhaQtd = [h("div", { style: { display: "flex", fontSize: 15, color: APAGADO } }, `${i.qtd} × ${moeda(i.preco)}`)];
    if (pct > 0) linhaQtd.push(h("div", { style: { display: "flex", marginLeft: 8, backgroundColor: VERDE, color: "#FFFFFF", fontSize: 13, fontWeight: 700, borderRadius: 5, paddingLeft: 7, paddingRight: 7, paddingTop: 2, paddingBottom: 2 } }, `−${pct}%`));
    blocosItens.push(
      h("div", { style: { display: "flex", width: LARGURA, alignItems: "center", paddingLeft: 24, paddingRight: 24, paddingTop: 12, paddingBottom: 12 } },
        h("div", { style: { display: "flex", width: 68, height: 68, flexShrink: 0, border: `1px solid ${LINHA}`, borderRadius: 10, backgroundColor: "#FFFFFF", alignItems: "center", justifyContent: "center" } },
          i.foto ? h("img", { src: i.foto, width: 60, height: 60, style: { objectFit: "contain" } }) : h("div", { style: { display: "flex", fontSize: 12, color: APAGADO } }, "")),
        h("div", { style: { display: "flex", flexDirection: "column", flexGrow: 1, flexShrink: 1, width: W - 68 - 14 - 12 - 104, marginLeft: 14 } },
          h("div", { style: { display: "flex", fontSize: 17, lineHeight: 1.3, fontWeight: 600, color: TEXTO } }, nomeCurto(i.nome)),
          h("div", { style: { display: "flex", alignItems: "center", marginTop: 4 } }, ...linhaQtd)),
        h("div", { style: { display: "flex", flexDirection: "column", alignItems: "flex-end", flexShrink: 0, width: 104, marginLeft: 12 } }, ...direita)));
  });

  const resumo = [linhaResumo("Subtotal", moeda(subCheio))];
  if (descPromo >= 0.01) resumo.push(linhaResumo("Promoções", "− " + moeda(descPromo), VERDE));
  resumo.push(linhaResumo("Entrega", entrega === 0 ? "Grátis" : moeda(entrega), entrega === 0 ? VERDE : APAGADO));
  resumo.push(h("div", { style: { display: "flex", width: W, alignItems: "flex-end", marginTop: 4 } },
    h("div", { style: { display: "flex", flexGrow: 1, fontSize: 22, fontWeight: 700, color: TEXTO, paddingBottom: 4 } }, "Total"),
    h("div", { style: { display: "flex", fontSize: 34, fontWeight: 800, color: TEXTO } }, moeda(total))));

  const filhos = [cabecalho, h("div", { style: { display: "flex", height: 8 } }), ...blocosItens,
    h("div", { style: { display: "flex", flexDirection: "column", width: W, marginLeft: 24, marginTop: 8, paddingTop: 14, borderTop: `2px solid ${TEXTO}` } }, ...resumo)];

  if (mostrarMeta) filhos.push(
    h("div", { style: { display: "flex", flexDirection: "column", width: W, marginLeft: 24, marginTop: 14, padding: "13px 16px 15px", backgroundColor: "#F0F6FD", borderRadius: 12 } },
      h("div", { style: { display: "flex", fontSize: 17, color: TEXTO } },
        h("span", {}, "Faltam"), h("span", { style: { fontWeight: 800, marginLeft: 5, marginRight: 5 } }, moeda(falta)),
        h("span", {}, "para o"), h("span", { style: { fontWeight: 800, marginLeft: 5 } }, "frete grátis")),
      h("div", { style: { display: "flex", width: W - 32, marginTop: 9, height: 9, borderRadius: 5, backgroundColor: TRILHA } },
        h("div", { style: { display: "flex", width: Math.round((W - 32) * Math.min(1, sub / minimo)), height: 9, borderRadius: 5, backgroundColor: dados.cor } }))));

  if (economia >= 0.01) filhos.push(
    h("div", { style: { display: "flex", width: W, marginLeft: 24, marginTop: 14, alignItems: "center", padding: "12px 16px", backgroundColor: VERDE_FUNDO, borderRadius: 12 } },
      h("div", { style: { display: "flex", flexGrow: 1, fontSize: 17, fontWeight: 600, color: VERDE } }, "Você está economizando"),
      h("div", { style: { display: "flex", fontSize: 20, fontWeight: 800, color: VERDE } }, moeda(economia))));

  const arvore = h("div", { style: { display: "flex", flexDirection: "column", width: LARGURA, height: altura, backgroundColor: "#FFFFFF", fontFamily: "Inter" } }, ...filhos);
  return { arvore, altura };
}
