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

### Fase 1 — biblioteca de templates (começar pequeno, crescer depois)
Em vez de 30-50 templates de cara, começar com **3-4 por pilar (~20 no total)** — valida o pipeline inteiro (dados → copy → imagem → aprovação → publicação) antes de investir em variedade. Schema: tabela `criativos_templates` (pilar, formato, tom, cta_padrao, canais_aplicaveis, ativo, layout_html — o template visual em si). Tabela `posts_conteudo` (histórico: pilar, formato, tema, canal, produto_id opcional, status: pendente_aprovacao/aprovado/recusado/publicado, imagem_url, data) — é a fonte pro controle de repetição E pro relatório futuro.

### Fase 2 — motor de decisão (pilar + formato do dia)
Função/RPC que, dado o histórico recente em `posts_conteudo`, sorteia o pilar (ponderado pelo mix — usar sua sugestão 20/20/20/15/15/10 como padrão, ajustável depois) e o formato dentro dele, excluindo o que já foi usado nos últimos N dias (config, sugestão inicial: não repetir o mesmo formato em 3 dias, não repetir o mesmo produto em 7 dias pro pilar Venda).

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
