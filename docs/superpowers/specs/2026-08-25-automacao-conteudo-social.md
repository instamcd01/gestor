# Automação de conteúdo para Instagram/Stories/Status — plano

**Origem**: usuário pediu automação pra gerar imagens (não genéricas — cada uma com finalidade específica) pra Instagram, Stories e Status do WhatsApp, com publicação automatizada e aprovação obrigatória via WhatsApp antes de cada post (botões Aprovar/Recusar; recusa = usuário explica o motivo em texto e a IA ajusta e reenvia).

Usuário colou um framework de estratégia de conteúdo bem estruturado — 6 pilares (Conversão, Engajamento, Educação, Entretenimento, Comunidade, Marca), mix de frequência sugerido, e a ideia de uma "biblioteca de templates" com 30-50 criativos escolhidos por objetivo, com controle de repetição. Esse framework vira a espinha dorsal do plano abaixo.

## ⚠️ Duas limitações técnicas reais, não contornáveis — confirmar antes de prosseguir

1. **Não existe API pública da Meta pra postar no Status do WhatsApp.** É um recurso pessoal/comercial sem endpoint de publicação (diferente de Mensagens, que já usamos). O que dá pra automatizar de verdade: **Instagram Feed** e **Instagram Stories** (ambos suportados pela Instagram Graph API — Content Publishing API — pra contas Business/Creator). Pro Status, o máximo automatizável é: a automação gera a imagem e manda pronta no seu WhatsApp (a mesma mensagem de aprovação já serve pra isso) — postar no Status continua sendo 1 toque manual seu, sem jeito de eliminar esse passo.
2. **Conta do Instagram precisa estar em modo Business/Creator, vinculada a uma Página do Facebook, dentro do mesmo Business Manager que já usamos pro WhatsApp Cloud API.** Você respondeu "não sei/provavelmente não" — isso é pré-requisito técnico da Meta pra qualquer publicação via API, não uma preferência de design. Vira a Fase 0 do plano, bloqueia a Fase de publicação (mas não bloqueia construir o resto: geração de imagem, aprovação por WhatsApp, etc. podem ser construídos e testados em paralelo, só a etapa final de "publicar de verdade" espera essa configuração).

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

## Decisões ainda em aberto, pra fechar antes de começar a construir

1. Confirmar mix de pilares (uso o seu 20/20/20/15/15/10 como padrão?).
2. Caminho da Fase 3 (HTML self-hosted vs. serviço de template pago).
3. Frequência: quantos posts automatizados por dia/semana?
4. Autorização pra eu investigar/configurar a conta Instagram Business (Fase 0) via browser, como fiz antes com outras integrações.
