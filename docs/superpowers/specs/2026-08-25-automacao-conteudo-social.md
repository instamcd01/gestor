# Automação de conteúdo para Instagram/Stories/Status — plano

**Origem**: usuário pediu automação pra gerar imagens (não genéricas — cada uma com finalidade específica) pra Instagram, Stories e Status do WhatsApp, com publicação automatizada e aprovação obrigatória via WhatsApp antes de cada post (botões Aprovar/Recusar; recusa = usuário explica o motivo em texto e a IA ajusta e reenvia).

Usuário colou um framework de estratégia de conteúdo bem estruturado — 6 pilares (Conversão, Engajamento, Educação, Entretenimento, Comunidade, Marca), mix de frequência sugerido, e a ideia de uma "biblioteca de templates" com 30-50 criativos escolhidos por objetivo, com controle de repetição. Esse framework vira a espinha dorsal do plano abaixo.

## ⚠️ Duas limitações técnicas reais, não contornáveis — confirmar antes de prosseguir

1. **Não existe API pública da Meta pra postar no Status do WhatsApp.** É um recurso pessoal/comercial sem endpoint de publicação (diferente de Mensagens, que já usamos). O que dá pra automatizar de verdade: **Instagram Feed** e **Instagram Stories** (ambos suportados pela Instagram Graph API — Content Publishing API — pra contas Business/Creator). Pro Status, o máximo automatizável é: a automação gera a imagem e manda pronta no seu WhatsApp (a mesma mensagem de aprovação já serve pra isso) — postar no Status continua sendo 1 toque manual seu, sem jeito de eliminar esse passo.
2. **Conta do Instagram precisa estar em modo Business/Creator, vinculada a uma Página do Facebook, dentro do mesmo Business Manager que já usamos pro WhatsApp Cloud API.** Você respondeu "não sei/provavelmente não" — isso é pré-requisito técnico da Meta pra qualquer publicação via API, não uma preferência de design. Vira a Fase 0 do plano, bloqueia a Fase de publicação (mas não bloqueia construir o resto: geração de imagem, aprovação por WhatsApp, etc. podem ser construídos e testados em paralelo, só a etapa final de "publicar de verdade" espera essa configuração).

**Fase 0 já verificada em 25/08 — muito melhor do que o esperado**: investigado direto no Meta Business Suite (portfólio "Delivery Pet", `business_id=254839687550114`). `@deliverypetrj` já é conta Business/Creator, já está no portfólio ("Propriedade: Delivery Pet") e **já está conectada à Página do Facebook "Delivery Pet"** (aba "Ativos conectados", 1 ativo conectado). Existe uma 2ª conta (`@clube.delivery.pet`) mas com "Login necessário" — não é a que usaríamos. O app já usado pro WhatsApp (`[n8n] WPP Delivery Pet`, id `792354710007372`) já tem um usuário do sistema (`n8n-whatsapp`) com "Acesso total" no portfólio. **Falta só**: confirmar em developers.facebook.com que o produto "Instagram Graph API" está adicionado a esse app (ou adicionar), e gerar/testar um token do sistema `n8n-whatsapp` com os escopos `instagram_basic`+`instagram_content_publish`+`pages_show_list`+`pages_read_engagement` — como o uso é só pra ativos do próprio Business (não pra terceiros), não deve precisar de App Review da Meta. Não fiz essa parte ainda (é a próxima ação técnica concreta antes de codar a Fase 6).

## Arquitetura de decisão (aplicando o princípio já usado no projeto: "LLM interpreta, banco decide")

Nem toda decisão dessa automação deve passar por LLM — só onde criatividade/interpretação de linguagem natural genuinamente agrega:

| Decisão | Quem decide | Por quê |
|---|---|---|
| Qual PILAR hoje (Venda/Engajamento/Educação/Entretenimento/Comunidade/Marca) | Determinístico (sorteio ponderado + regras de não-repetição) | É rotação/agenda, não criatividade — LLM aqui só adiciona custo e risco de repetir sem perceber |
| Qual FORMATO dentro do pilar (enquete, oferta, meme, 3-dicas...) | Determinístico (sorteio dentro do pilar, evita repetir o mesmo formato usado nos últimos N dias) | Idem |
| Qual PRODUTO (pilar Venda) | Determinístico, direto do catálogo real (promoção ativa, mais vendido, produto novo — mesmas views já usadas no site: `catalogo_mais_vendidos_publico`, `getPromocoesDoDia`) | Nunca inventar produto/preço — mesmo princípio já aplicado em toda tool de WhatsApp |
| TEXTO/copy do post (headline, legenda, CTA) | LLM, com template estrutural fixo por formato e proibição explícita de inventar dado de produto (preço/composição vêm sempre prontos, só o texto ao redor é gerado) | Onde criatividade de verdade importa — mesmo padrão já usado no gerador de descrição de produto |
| Interpretar o motivo da recusa | LLM (classifica em categorias: trocar produto / trocar tom / trocar formato / trocar imagem / cancelar) | Linguagem natural livre, não dá pra tratar por regra fixa |
| Reajustar e regenerar após recusa | Determinístico, a partir da classificação acima | Reaplica os mesmos geradores com o parâmetro ajustado, nunca "a IA decide sozinha o que fazer" |

## Fases

### Fase 0 — pré-requisito (bloqueia só a publicação, não o resto)
Verificar/configurar conta Instagram Business ou Creator vinculada a uma Página do Facebook no mesmo Business Manager do WhatsApp. Posso investigar e (com autorização, via browser já logado, mesmo processo usado antes pra provisionar a chave do Google Maps) configurar isso.

### Fase 1 — biblioteca de templates ✅ CONSTRUÍDA (25/08)

Schema criado no Supabase (`dwswpwxnzjgoohucngbb`): `criativos_templates` (empresa_id, pilar, formato, tipo_midia imagem/video, tom, cta_padrao, canais_aplicaveis text[], usa_mascote, descricao, ativo) e `posts_conteudo` (histórico: empresa_id, template_id, pilar, formato, tema, produto_id opcional, canal, status pendente_aprovacao/aprovado/recusado/publicado/cancelado, midia_url, copy_texto, motivo_recusa, tentativas, meta_publicacao_id, criado_em/publicado_em) — fonte pro controle de repetição (Fase 2) e pro relatório (Fase 7). RLS habilitado nas duas (`empresa_id = get_empresa_id()`), `anon` sem acesso, confirmado via `has_table_privilege`. Índices por `(empresa_id, pilar, criado_em)` e `(empresa_id, produto_id, criado_em)` pra sustentar as consultas de não-repetição da Fase 2.

**20 templates seed pra Delivery Pet**, quantidade proporcional ao mix (Venda/Engajamento/Educação 4 cada, Entretenimento/Comunidade 3 cada, Marca 2) — 7 em vídeo (35%, perto do ~40% recomendado pela pesquisa), 8 usam o mascote como personagem:

| Pilar | Formatos (video=🎬, mascote=🐾) |
|---|---|
| Venda | oferta_relampago, mais_vendido_semana, lancamento_novidade 🎬🐾, kit_combo |
| Engajamento | enquete_rapida 🐾, quiz_multipla_escolha 🐾, complete_a_frase, pergunta_divertida_video 🎬🐾 |
| Educação | tres_dicas 🎬🐾, mito_ou_verdade, comparativo_produtos, passo_a_passo 🎬🐾 |
| Entretenimento | meme_tutor, pov_mascote 🎬🐾, ranking_divertido |
| Comunidade | pet_da_semana, aniversariante_semana 🎬🐾, pergunta_para_comunidade |
| Marca | bastidores_loja 🎬, valores_novidades |

Só a METADATA de cada template está pronta (o que é, tom, CTA, canal, se usa mascote/vídeo) — o layout visual real (HTML/Remotion) é construído na Fase 3.

### Fase 3 — renderizador ✅ v1 CONSTRUÍDA E TESTADA (25/26-08)

Repositório novo e separado: `gestor-conteudo-social` (Node.js/TypeScript, fora do monorepo Flutter de propósito — stack diferente, deploy independente). Commit inicial `be31664`.

**Confirmado antes de construir**: n8n e Easypanel rodam na MESMA VPS (Hostinger KVM 2, 8GB RAM, Campinas — README do `gestor-loja`) — não existe distinção real entre "deployar no servidor do n8n" e "deployar no Easypanel", é a mesma máquina. Deploy previsto ali.

**Stack**: imagem via Chromium headless (Playwright) renderizando HTML/CSS; vídeo via Remotion (composições React), navegador aberto/fechado a cada render de propósito (não mantém instância persistente — VPS de 8GB compartilhada com n8n+site). Bucket novo `conteudo-social` no Storage (RLS por empresa, leitura pública, mesmo padrão de `produtos`/`banners`/`logos`).

**2 templates reais implementados e testados de ponta a ponta** (dos 20 seed — os outros 18 ficam pendentes, implementação incremental):
- `oferta_relampago` (imagem, 1080x1080) — testado com produto e logo REAIS da Delivery Pet (Antipulgas Banni 3, R$59,90→R$39,90, badge "33% OFF" calculado certo). Resultado conferido visualmente.
- `tres_dicas` (vídeo, 1080x1920, Remotion) — abertura+3 dicas+encerramento com logo, testado gerando MP4 real (1,7MB, ~18s) e conferindo 3 frames individuais (abertura, dica 1, encerramento) visualmente.

**Achado real durante a construção — Kit de Marca não tem NENHUM mascote cadastrado** (`marca_ativos` só tem `logo_completa`/`nome_loja_imagem` pra Delivery Pet, zero linhas `tipo='mascote'`) — apesar de todo o plano (a pedido do próprio usuário) depender do mascote como "personagem" dos vídeos. Os testes usaram um placeholder (emoji 🐾 num círculo branco) só pra provar o pipeline de composição/animação — **nenhum vídeo real deve ser publicado até o usuário cadastrar pelo menos 1 mascote de verdade no Kit de Marca do app** (Configurações > Kit de Marca, só dono).

**2 bugs reais achados e corrigidos construindo**: (1) Remotion não aceita `_` no id de composição (só a-z/A-Z/0-9/hífen) — `formato` do banco usa snake_case; corrigido convertendo `_`→`-` só na hora de chamar o Remotion, sem mudar a convenção do resto do projeto; (2) imports dentro da pasta `src/remotion/` (bundlados pelo webpack do Remotion) não podem ter extensão `.js` como os do resto do serviço (que roda via Node/tsx, exige extensão em import relativo) — as duas convenções coexistem no mesmo repo por motivos diferentes, documentado em comentário no código pra não confundir depois.

**Não verificado nesta sessão**: build Docker real (Docker Desktop não estava rodando na máquina) — Dockerfile segue o padrão oficial da imagem do Playwright (`mcr.microsoft.com/playwright`), mas precisa de um build de verdade antes do primeiro deploy. Repositório só existe local (`git init` feito, sem remoto no GitHub ainda — `gh` CLI não disponível neste ambiente pra criar automaticamente).

### v2 dos templates (26/08) — usuário testou e pediu mais estratégia real

Feedback direto depois de ver a v1: a imagem "parecia print de catálogo" (sem técnica de venda nenhuma) e o vídeo tinha "o mascote minúsculo flutuando aleatoriamente" durante as dicas. Princípio explícito do usuário, registrado em [[feedback_estrategia_humana_em_conteudo_visual]]: toda peça precisa ser desenhada pensando em quem vai assistir/ver e no comportamento humano — extensão do mesmo princípio já aplicado ao agente WhatsApp.

**Corrigido e retestado com produto e mascote reais**:
- `oferta_relampago`: faixa de urgência ("⚡ Oferta relâmpago — por tempo limitado"), selo de desconto em formato de estrela (não pílula discreta), tagline de benefício, **"Você economiza R$X" (dado real calculado — preço de menos preço por, nunca inventado)**, CTA em formato de botão, mascote virou selo de marca no canto (não mais central — o produto é o protagonista).
- `tres_dicas`: mascote agora só na abertura (recebe o espectador) e no encerramento (assinatura de marca) — **nunca mais durante as dicas**. Cada dica ganhou um **ícone contextual grande** específico do conteúdo dela (🫙 pote hermético / ☀️ sol / 🔀 não misturar) no lugar do mascote repetido — reforço visual real (dual-coding: quem rola rápido entende do que se trata só pelo ícone). Adicionado indicador "Dica X de 3" (pontinhos de progresso) pra dar noção de ritmo a quem assiste.

Commit `e9dc10f` no `gestor-conteudo-social`. Nova galeria publicada no mesmo Artifact de antes (mesma URL, republicado).

### v3 dos templates (26/08) — pesquisa real de design antes de tentar de novo

Usuário rejeitou a v2 com força: "exagerou demais... muito poluído... precisa melhorar pelo menos uns 1000%" e pediu estudo real (não mais tentativa e erro). Pesquisei (WebSearch) princípios reais de: banner/flash-sale design (regra dos 3 segundos — cada elemento precisa justificar o espaço; urgência é 1 elemento nítido, não vários empilhados), hierarquia visual e whitespace (restrição sinaliza profissionalismo — marcas com espaço em branco generoso são percebidas como mais modernas/confiantes), e pacing de Reels/TikTok (cortes de ~2,5-4s pra Reels; conteúdo educativo "salvável" tolera o lado mais lento dessa faixa — confirma que os 4s por dica já estavam certos, o problema da v2 era só visual).

**Aplicado**:
- `oferta_relampago`: de 4 cores competindo (verde+vermelho/laranja+amarelo×2+mascote) pra 1 fundo verde plano + 1 único acento âmbar. Mascote SAIU do formato (o produto é o herói de uma oferta, a marca não precisa estar no meio disso). Preço é o elemento tipográfico dominante (Fraunces 900, 92px); desconto e economia viram apoio discreto abaixo, não elementos gritando junto.
- `tres_dicas`: removido o "bounce" contínuo (seno) que fazia tudo entrar E continuar balançando — exatamente o que lia como "flutuando aleatoriamente" mesmo depois de assentar. Ícone de cada dica virou um chip pequeno achatado (mesmo âmbar da imagem, sem brilho/sombra pesada) — apoio, não protagonista. O TEXTO da dica é agora o elemento dominante da cena (consistente com o que Reels educativo "pra salvar" realmente entrega).

Commit `2167fd7`. Retestado com produto+mascote reais, galeria republicada (mesma URL).

### v4 dos templates (26/08) — correção de cor de marca + design/motion, pesquisa de Remotion/Claude profissional

Usuário rejeitou a v3 de novo: layout "meio estranho", logo pequena, foto de produto "muito quadrada" (queria cantos arredondados), **e a cor verde não combina com a cor da marca**; vídeo "muito ruim ainda... parece que uma criança de 5 anos fez". Pediu explicitamente pra ver o que profissionais fazem com Remotion+Claude antes de tentar de novo.

**Correção crítica de dado, não só de design**: `empresas.cor_secundaria` (verde `#059F0B` no banco) NUNCA foi a cor secundária real da marca — o usuário confirmou que esse campo só personaliza itens internos do app Gestor, sem relação com a identidade visual da loja/site. A cor secundária real é **laranja** (cor do mascote), sem campo próprio no banco ainda. Extraída por amostragem de pixel direto da arte do mascote (histograma de cor via Playwright+canvas, não chutada): `#D8540C`. Confirmado visualmente depois: o mascote usa exatamente azul (uniforme/sacola, bate com `cor_primaria` `#409BFD`) + laranja (pelagem) — os 2 tons reais. Novo `src/lib/cores.ts` centraliza `paletaMarca(corPrimaria, corSecundaria)`, recebendo as 2 cores reais como parâmetro (nunca hardcoded por empresa) e documentando por que `cor_secundaria` do banco não pode ser usada aqui.

**Pesquisa aplicada** (fontes: dplooy.com sobre Remotion+Claude Code — springs `{damping:200,stiffness:100,mass:0.5}`, `<Sequence>` modular com timing escalonado, "pensar em frames"; artigo do Medium sobre o mesmo tema retornou HTTP 403, não pôde ser lido): emoji cru em peça de marca lê como "barato/genérico" — ícone de linha customizado (estilo Lucide) é o padrão profissional; tipografia cinética (revelação palavra por palavra com atraso escalonado) é a técnica real de reels profissionais pra dar "emoção"; formato vertical 9:16 com conteúdo curto dead-center deixa muito vazio em cima/embaixo — resolvido com um eco GIGANTE e quase invisível (~5% opacidade) do mesmo ícone da dica atrás do texto, que usa o espaço sem virar mais um elemento competindo por atenção (mantém a disciplina de restrição já validada na v3).

**Aplicado**:
- `oferta_relampago`: paleta real (azul+laranja) no lugar do verde; logo dobrada de tamanho; cartão branco com cantos arredondados (raio 32px) pro produto; badge de desconto ANCORADO no canto desse cartão (não mais solto na linha de preço) — fluxo de leitura: marca → produto+urgência (mesmo bloco) → identidade → preço → CTA.
- `tres_dicas`: ícones SVG de linha customizados (jarro/sol/troca) no lugar dos emoji; tipografia cinética por palavra (com destaque opcional de palavra-chave via `**palavra**`); eco gigante do ícone da dica no fundo; marca discreta (logo+nome) persistente durante as 3 dicas, não só abertura/encerramento; reposicionamento vertical pra zona de leitura segura (evita a área onde Instagram/WhatsApp sobrepõe UI embaixo); paleta real aplicada também aqui.

Commit `de17355`. Retestado com produto+mascote reais (vídeo completo renderizado, ~1,3MB), galeria republicada (mesma URL).

**Pendências reais antes de considerar a Fase 3 pronta pra produção**:
1. ~~Usuário cadastrar pelo menos 1 mascote real no Kit de Marca~~ — feito em 26/08.
2. Criar o repositório remoto no GitHub (ou outro host) e dar push.
3. Testar o build Docker de verdade.
4. Deploy no Easypanel + configurar `SUPABASE_SERVICE_ROLE_KEY`/`RENDER_API_KEY`.
5. Implementar os outros 18 formatos (incremental, conforme o uso real for pedindo).
6. Se uma empresa nova precisar da cor secundária real, hoje só existe via extração manual do mascote (sem campo no banco) — considerar um campo dedicado no Kit de Marca se isso virar recorrente.

### Fase 2 — motor de decisão ✅ CONSTRUÍDA (25/08)

Tabela nova `pilares_mix_conteudo` (empresa_id, pilar, peso) — pesos ajustáveis sem mudar código, seed com 20/20/20/15/15/10 pra Delivery Pet.

RPC `selecionar_proximo_conteudo(p_empresa_id, p_canal, p_dias_sem_repetir_formato default 3, p_dias_sem_repetir_produto default 7)`: sorteia o pilar (ponderado, só entre os que têm template ativo pro canal pedido E não usado nos últimos N dias nesse canal — com fallback que ignora a anti-repetição se TODOS os pilares elegíveis ficarem de fora), sorteia o formato dentro do pilar (mesma lógica de anti-repetição+fallback), resolve produto real via `_resolver_produto_conteudo_venda` quando o pilar é Venda, e grava a linha em `posts_conteudo` com `status='planejado'`. `anon` sem acesso a nenhuma das duas funções (confirmado via `has_function_privilege`), `authenticated` com EXECUTE nas duas.

`_resolver_produto_conteudo_venda(empresa_id, formato, dias_sem_repetir_produto)` resolve produto real do catálogo (nunca inventado) por formato: `oferta_relampago` → produto com promoção ativa; `mais_vendido_semana` → melhor ranking em `catalogo_mais_vendidos_publico`; `lancamento_novidade` → produto mais recente ainda não usado; `kit_combo` → kit ativo (`eh_kit=true`) — hoje retorna `null` porque a Delivery Pet ainda não tem nenhum kit cadastrado, comportamento correto, não é bug.

**2 bugs reais achados e corrigidos testando** (não só lendo o código):
1. **Sorteio ponderado quebrado**: `where acumulado >= random() * total` chama `random()` UMA VEZ POR LINHA (é volátil), não uma vez só pro sorteio inteiro — destrói a técnica de distribuição cumulativa. Testado com 600 sorteios antes do fix: Venda (peso 20) saiu com só 1,5% em vez de ~20%. Corrigido calculando `v_sorteio := random() * peso_total` UMA VEZ em variável plpgsql, comparando essa mesma variável fixa contra o acumulado de cada pilar. Reteste com 600 sorteios (anti-repetição desligada de propósito pra isolar só a distribuição): Venda 20,2%, Engajamento 21,7%, Educação 20,2%, Comunidade 14,8%, Entretenimento 14,3%, Marca 8,8% — todos dentro da variação estatística esperada do alvo 20/20/20/15/15/10.
2. **Vazamento de grant recorrente do projeto**: revogar de `anon` não bastou — o Supabase concede `EXECUTE` pra `PUBLIC` por padrão na criação da função, e `anon` herda isso através do `PUBLIC` mesmo com o `REVOKE ... FROM anon` explícito. Corrigido com `REVOKE ALL ... FROM PUBLIC` nas duas funções. Achado também: `selecionar_proximo_conteudo` não é `SECURITY DEFINER` (roda com o privilégio de quem chama), então a chamada interna pro helper `_resolver_produto_conteudo_venda` também precisava de `GRANT EXECUTE` pra `authenticated` — só revogar não bastava, faltava conceder de volta.

Testado ponta a ponta como o role `authenticated` de verdade (`SET LOCAL ROLE authenticated` + `SET LOCAL request.jwt.claims` com um usuário real da Delivery Pet, não só a conexão privilegiada usada nos testes de distribuição) — sem erro de permissão, produto resolvido corretamente pro pilar Venda. Dados de teste sempre limpos depois (`count(*)=0` confirmado).

### Fase 3 — geração da imagem
**Decisão em aberto, dois caminhos**:
- **HTML/CSS renderizado por headless browser** (self-hosted, sem custo por imagem, mais controle visual, mais código pra manter) — consistente com a preferência já demonstrada no projeto por self-hosted (Backblaze em vez de serviço gerenciado, etc.).
- **Serviço de template pronto** (Bannerbear/Placid) — editor visual arrastar-solta, sem escrever HTML, mas com custo recorrente por imagem/mês e mais uma dependência externa.

Cada template puxa: foto do produto (quando aplicável) do Storage já existente, ativos do Kit de Marca (logo/mascote), copy gerado na Fase 4, e gera as proporções certas por canal (1:1 feed, 9:16 stories/status).

**Vídeo/Reels confirmado na v1 (25/08)** — usuário decidiu incluir desde o início, não deixar pra depois. **O mascote (já existente em `marca_ativos`/Kit de Marca, galeria de variações) supre a necessidade de "gente de verdade" nos vídeos** — decisão explícita do usuário, evita precisar filmar funcionário/cliente real. Implicação técnica: os vídeos são **motion graphics montados a partir de arte estática já existente** (mascote + foto de produto + logo + texto), nunca filmagem real nem geração de vídeo por IA — renderizados via `Remotion` (framework que compõe vídeo a partir de React/HTML+CSS, mesma filosofia self-hosted já escolhida pra imagem), com animações simples (zoom/pan tipo Ken Burns, mascote entrando na cena, balão de fala com o texto/CTA, texto aparecendo). Cada template de vídeo referencia qual variação do mascote usar (da galeria já existente) como o "personagem" — pilares onde isso faz mais sentido primeiro: Engajamento, Entretenimento, Comunidade, Educação (mascote "explicando" a dica) e Venda (mascote "apresentando" a oferta).

**Ressalva operacional a registrar**: renderizar vídeo é mais lento que imagem estática (segundos a minutos, não instantâneo) — o loop de aprovação por WhatsApp (Fase 5) precisa considerar esse tempo maior de espera entre "recusar com motivo" e "nova versão chegar", principalmente se cair no limite de 3 tentativas.

### Fase 4 — geração de copy (LLM com guardrails)
Workflow n8n novo, mesmo padrão do gerador de descrição de produto: prompt estruturado por formato (ex: formato "3 dicas" tem uma estrutura fixa diferente de formato "oferta"), nunca inventa dado de produto (preço/composição sempre vêm prontos da Fase 2/dados reais), sempre gera dentro do tom configurado no template.

### Fase 5 — aprovação por WhatsApp
Envia a imagem + botões (Aprovar/Recusar) pro seu WhatsApp — mesmo padrão de template aprovado pela Meta já usado nos alertas de uptime/erro (mensagem business-initiated fora de janela de 24h precisa de template pré-aprovado). Aguarda resposta:
- **Aprovar** → segue pra Fase 6.
- **Recusar** → pergunta o motivo → LLM classifica → regenera (Fase 3/4 de novo com o ajuste) → reenvia pra aprovação. **Limite de tentativas** (sugestão: 3) — depois disso, marca como "cancelado, revisar manualmente" em vez de ficar num loop infinito.

### Fase 6 — publicação
Instagram Graph API (Content Publishing API) — Feed e Stories. WhatsApp Status fica de fora por limitação técnica (ver aviso no topo) — a imagem já chegou pronta na aprovação, postar lá é 1 toque manual seu.

### Fase 7 — acompanhamento
Relatório periódico (reaproveitando o padrão já usado no Auditor de Atendimento): o que foi publicado, em qual pilar, taxa de aprovação vs. recusa por formato (sinaliza quais formatos estão errando o tom/expectativa com mais frequência).

## Decisões fechadas (25/08)

1. Mix de pilares: **20/20/20/15/15/10** (Venda/Engajamento/Educação/Entretenimento/Comunidade/Marca), como sugerido pelo usuário.
2. Fase 3 (geração de imagem): **HTML/CSS self-hosted** (renderizado por headless browser), não serviço de template pago.
3. Frequência: **substituída após pesquisa** (usuário pediu pra pesquisar em vez de assumir) — ver seção "Pesquisa de estratégia" abaixo. 6-7 posts/dia no Feed foi descartado: dado real mostra que isso reduziria alcance, não aumentaria.
4. Fase 0 (Instagram): autorizado e já investigado — ver achado acima (conta já pronta, falta só confirmar/ativar o produto Instagram Graph API no app existente).

## Pesquisa de estratégia (25/08) — usuário pediu pra pesquisar antes de decidir frequência, e deixou claro: quer ser SUPERIOR aos outros petshops, não igual

Pesquisa real (não suposição), fontes no fim desta seção.

**Achado que descarta "1 post por pilar por dia" (6-7/dia no Feed)**: o algoritmo de 2026 não recompensa mais volume — frequência de postagem nem é mais um sinal de ranking central. Postar demais com pouco esforço faz o alcance CAIR (o algoritmo suprime ativamente). O ponto ótimo pra pequeno negócio é **3-5 posts de Feed por semana** — o maior ganho de alcance vem de sair de 1-2/semana pra 3-5/semana; postar mais que isso não ajuda e pode prejudicar. Consistência (um "batimento" regular) gera 5x mais engajamento que volume esporádico alto.

**Achado que muda o escopo do projeto — Reels (vídeo curto)**: é hoje o formato de MAIOR alcance (2-3x mais que imagem estática), mix ideal sugerido pros pequenos negócios é ~40% Reels, resto carrossel/imagem estática. O plano original (só imagem estática renderizada em HTML) fica sem o formato que mais entrega alcance. Feed e Reels são ranqueados por sinais DIFERENTES (Feed: força de relacionamento, salvamentos, resposta real no comentário; Reels: tempo assistido, replay, envios/compartilhamentos) — reforça a ideia de "um objetivo por post", que já bate com o desenho por pilar.

**Onde está a superioridade de verdade, pra quem tem loja física de pet (não é postar mais)**: a pesquisa aponta que pet shop compete com loja virtual grande em 2 coisas que ela não tem — **expertise real** (ex: vídeo explicando diferença nutricional entre rações — o pilar Educação já cobria isso) e **comunidade/conexão local** (o pilar Comunidade já cobria isso). Autenticidade e conteúdo original bem feito superam concorrente que só posta oferta genérica — o diferencial não é "postar 6x mais", é fazer os pilares Educação/Comunidade de verdade bem, com vídeo, em vez de tratá-los como preenchimento.

**Recomendação revisada** (ainda não implementada, aguardando confirmação):
- **Feed**: 3-5 posts/semana, rotacionando os 6 pilares pelo mix 20/20/20/15/15/10 ao longo da SEMANA (não do dia) — ex. numa semana de 5 posts: 1 Venda, 1 Engajamento, 1 Educação, 1 Entretenimento/Comunidade (alternando), 1 Marca a cada 2 semanas.
- **Stories**: aguenta frequência bem maior sem o mesmo risco de supressão (é outro algoritmo, mais tolerante) — pode ser diário, inclusive múltiplos por dia, sem o mesmo custo de "cansar" o algoritmo do Feed.
- **Status do WhatsApp**: não tem algoritmo nenhum (só timeline dos seus contatos) — pode reaproveitar o que já foi aprovado pro Stories sem problema de frequência.
- **Reels vira parte do escopo**: pelo menos os pilares Educação e Venda deveriam ter versão em vídeo curto além (ou no lugar) da imagem estática, dado que é o formato de maior alcance — implica estender a Fase 3 pra também gerar vídeo (ex: `Remotion`, framework que renderiza React/HTML+CSS em vídeo — mesma filosofia self-hosted já escolhida pra imagem, só que pra vídeo), não só imagem parada. Isso é escopo REAL a mais, não incremental — vale decidir se entra já na v1 ou fica pra uma fase 2 depois do pipeline de imagem estar validado.

Fontes: [Buffer — How the Instagram Algorithm Works: Your 2026 Guide](https://buffer.com/resources/instagram-algorithms/), [Buffer — How Often Should You Post on Instagram in 2026?](https://buffer.com/resources/how-often-to-post-on-instagram/), [Hootsuite — Instagram algorithm tips for 2026](https://blog.hootsuite.com/instagram-algorithm/), [Aibrify — Instagram Reels vs Posts Reach 2026](https://aibrify.com/blog/instagram-algorithm-2026-reels-vs-static-posts), [Moonb — Reels vs Post Instagram](https://www.moonb.io/blog/reels-vs-post-instagram), [SocialChamp — Instagram Marketing Strategy For Small Business In 2026](https://www.socialchamp.com/blog/instagram-marketing-strategy-for-small-business/), [Thryv — Pet Store Marketing Ideas](https://www.thryv.com/blog/pet-store-marketing/), [Conbersa — How Should Pet Stores Use Social Media Marketing?](https://www.conbersa.ai/learn/social-media-for-pet-stores).

## Pergunta feita pelo usuário: essa automação fica vinculada ao Gestor (app)/site/app da loja?

Resposta: é uma automação nova, 100% dentro do n8n (mesmo padrão dos outros workflows de WhatsApp/marketplace já existentes) — **não depende de nenhuma tela nova no app Flutter nem no site** pra funcionar (a aprovação acontece pelo WhatsApp, não pelo app). Ela SE CONECTA aos mesmos dados reais do catálogo (produtos, promoções ativas, mais vendidos — mesmas fontes já usadas no site) pro pilar Venda, então nesse sentido já "conversa" com o mesmo banco de tudo. Se no futuro fizer sentido ter uma tela de histórico/relatório dentro do Gestor (Fase 7), é perfeitamente possível adicionar depois — não é pré-requisito pra este projeto funcionar.
