# Variantes de produto — design

## Contexto

Hoje cada opção de peso/dose/sabor/cor de um produto é um registro
totalmente independente na tabela `produtos` — nome, SKU, preço e estoque
próprios, sem nenhum vínculo entre eles. Isso já foi observado durante a
limpeza de nomes do catálogo (ver memória "Padrão de nome de produto" do
projeto): por exemplo, "Ração Golden ... 10kg" e "Ração Golden ... 3kg"
são duas linhas sem relação estrutural no banco, apenas com nomes
parecidos.

**Achado que mudou este design**: o banco já tem, de uma sessão anterior,
exatamente o gancho pra essa feature — nunca usado em código nenhum:
- `produtos.produto_pai_id uuid references produtos(id)` (self-FK,
  migração `20260718134038`, comentário original no SQL: *"Ajustes no
  produto: variações (agrupamento futuro)"*).
- `produtos.nome_comercial / dose / composicao / apresentacao / especie /
  fase / porte / sabor` — colunas já existem (adicionadas fora do
  histórico de migrations rastreadas, provavelmente durante a limpeza de
  nomes), mas nunca referenciadas em `produto.dart` nem em nenhuma tela.

Este design reaproveita as duas coisas em vez de criar um modelo
paralelo: `produto_pai_id` vira o mecanismo de agrupamento (variante →
produto principal, mesmo padrão pai/filho já usado em outras partes do
projeto), e os 8 campos estruturados já existentes viram o cadastro
estruturado, em vez de nome livre.

O pedido original: no site do cliente (Gestor Loja), produtos que são a
mesma oferta em opções diferentes (peso, dose, sabor, ou outros eixos que
apareçam conforme o catálogo crescer) devem aparecer agrupados em um
único card, com um seletor de opção — em vez de aparecerem como produtos
totalmente separados no catálogo. O catálogo está prestes a crescer com
produtos e categorias novas, então o mecanismo de detecção precisa
reconhecer tipos de variação novos **sem exigir mudança de código** — só
cadastro de dados.

## Estoque — não muda

Cada variante continua sendo uma linha própria em `produtos`, com seu
próprio vínculo em `estoque`. Preço, custo e quantidade permanecem 100%
independentes por variante, exatamente como hoje. O agrupamento é
puramente um link de exibição (`produto_pai_id`) — nenhuma trigger de
baixa de estoque, cálculo de margem ou lucro é alterada por este design.

## Escopo

- **Site (Gestor Loja)**: catálogo e página de produto passam a agrupar
  variantes visualmente.
- **App Gestor (Flutter, admin)**: o cadastro/edição de produto ganha
  campos estruturados (já existem no banco, faltam no app); a listagem de
  produtos continua tratando cada variante como um produto próprio — a
  mudança é uma forma de marcar quais produtos pertencem à mesma família
  (via revisão de sugestões automáticas).
- **Qualquer categoria do catálogo**, atual ou futura — o mecanismo não é
  travado em Ração/Farmácia.
- **Eixo único por família**: dentro de uma mesma família de variantes, a
  variação é sempre em uma única dimensão por vez (só peso, OU só sabor,
  OU só dose — nunca uma grade/matriz combinando dois eixos no mesmo
  produto). Se um produto real varia em dois eixos ao mesmo tempo, isso
  vira duas famílias separadas, não uma família com seletor duplo.
- **Catálogo já existente (~540 produtos)**: os campos estruturados não
  são retroativamente preenchidos por este projeto — os produtos já
  cadastrados continuam com `nome` livre e usam a detecção por
  regex/dicionário (fallback, ver seção 3.2). Um backfill do catálogo
  existente para campos estruturados, se algum dia for feito, é projeto
  à parte.

## 1. Cadastro estruturado de produto

Campos que **já existem em `produtos`** (não criar de novo — só passar a
usar) e entram na tela de cadastro/edição
(`cadastro_produto_screen.dart` / `editar_produto_screen.dart`) e no
`produto.dart`:

| coluna existente | exemplo | uso no template Farmácia | uso no template Ração |
|---|---|---|---|
| `nome_comercial` | `"Agemoxi"`, `"Golden Fórmula"` | nome comercial | marca/linha |
| `especie` | `"Cães e Gatos"` | espécie | espécie |
| `fase` | `"Adultos"` | — | fase |
| `porte` | `"Pequeno"` | — | porte |
| `sabor` | `"Carne e Arroz"` | — | sabor |
| `dose` | `"250mg"` | dose | — |
| `composicao` | `"Amoxicilina"` | composição (parênteses) | — |
| `apresentacao` | `"10 Comprimidos"` | apresentação | — |

`peso`/`volume`/`fabricante` (já existem e já são usados) continuam como
estão.

Todos os campos ficam disponíveis sempre (não há um formulário diferente
por categoria) — o que não se aplica à categoria do produto fica em
branco. Isso evita ter que tocar em código toda vez que uma categoria
nova aparecer.

### Geração automática do `nome`

Uma função SQL `compor_nome_produto(...)` (parâmetros = os campos
estruturados) monta o `nome` a partir dos campos preenchidos, seguindo
uma ordem genérica fixa (pulando qualquer segmento cujo campo esteja
vazio):

```
{categoria} {nome_comercial} {dose} ({composicao}) {apresentacao}
Para {especie} {fase} {"de Porte " + porte} {"Sabor " + sabor} {peso ou volume}
- {fabricante}
```

Validado contra os dois padrões reais já documentados na memória do
projeto — reproduz exatamente:
- Farmácia: `Antibiotico Agemoxi 250mg (Amoxicilina) 10 Comprimidos Para Caes e Gatos - Agener Uniao`
- Ração: `Ração Golden Fórmula Para Cães Adultos de Porte Pequeno Sabor Carne e Arroz 10kg - PremieRpet`

Um trigger `BEFORE INSERT OR UPDATE ON produtos` chama essa função e
grava o resultado em `nome`, exceto quando `nome_manual_override = true`
(coluna nova, `boolean default false`, marcada quando o usuário edita
`nome` manualmente em vez de mexer nos campos estruturados — preserva o
comportamento atual pra qualquer produto que não se encaixe no template).
A mesma função `compor_nome_produto` é reaproveitada na seção 5 pra
montar o nome do card de família no site, sem duplicar a lógica.

## 2. Modelo de dados de variantes

### `produto_pai_id` — já existe, é o mecanismo de agrupamento

Uma família de variantes é: um produto "âncora" (`produto_pai_id IS
NULL`) + um ou mais produtos com `produto_pai_id` apontando pra ele. O
produto âncora é ele mesmo uma variante vendável normal (ex: pode ser a
opção "1kg"), não um registro fantasma — mesmo padrão simples de
pai/filho, sem tabela de grupo à parte.

### Colunas novas em `produtos`

- `tipo_variacao text null` — o eixo desta família: `"peso"`, `"dose"`,
  `"sabor"`, etc. Igual em todos os produtos da mesma família (âncora e
  filhos). `null` = produto não faz parte de nenhuma família.
- `variante_label text null` — o valor deste produto especificamente
  dentro do eixo: `"1kg"`, `"250mg"`, `"Frango"`. Pré-preenchido pelo
  detector: direto do campo estruturado correspondente ao `tipo_variacao`
  quando existir, ou por extração heurística do `nome` no caminho de
  fallback (seção 3.2). Sempre editável no fluxo de aprovação — nunca
  publicado sem confirmação humana.
- `nome_manual_override boolean default false` — ver seção 1.

### Tabela nova `tipos_variacao`

Vocabulário dos eixos conhecidos, só pra dar um rótulo amigável no site —
mesmo padrão de `categorias`/`subcategorias`/`fabricantes` (lookup table
com os valores permitidos, sem FK forçada na tabela principal).

| coluna | tipo | notas |
|---|---|---|
| `id` | uuid, PK | |
| `nome` | text, unique | mesmo valor usado em `produtos.tipo_variacao` (`"peso"`, `"dose"`, `"sabor"`...) |
| `rotulo_site` | text | texto do seletor no site, ex: `"Escolha o peso:"`, `"Escolha o sabor:"` |

Linhas iniciais: `peso`, `dose`, `sabor`, `apresentacao`. Tipo novo (ex:
categoria futura com "cor") é só um INSERT aqui.

### Tabela nova `termos_variacao`

Dicionário de valores conhecidos por tipo, usado **apenas pelo caminho de
fallback** (produtos sem campos estruturados, detecção por texto livre no
`nome` — seção 3.2).

| coluna | tipo | notas |
|---|---|---|
| `id` | uuid, PK | |
| `tipo_variacao` | text | referencia `tipos_variacao.nome` (mesmo padrão sem FK forçada) |
| `termo` | text | ex: `"Frango"`, `"Carne"`, `"Salmão"` |
| `categoria` | text, null | restringe o termo a uma categoria específica; `null` = vale pra qualquer categoria |

### Tabela nova `sugestoes_variante`

| coluna | tipo | notas |
|---|---|---|
| `id` | uuid, PK | |
| `produto_id` | uuid, FK `produtos` | o produto novo/editado que disparou a sugestão |
| `produto_candidato_id` | uuid, FK `produtos` | produto existente parecido — pode já ser âncora, já ser filho de uma família, ou ainda estar sozinho |
| `tipo_variacao` | text | eixo detectado |
| `variante_label_sugerido` | text | valor extraído, pré-preenche o diálogo de revisão |
| `origem` | text | `"estruturado"` \| `"heuristico"` — de qual caminho de detecção veio (seção 3) |
| `status` | text | `pendente` \| `aprovado` \| `rejeitado` |
| `criado_em` | timestamptz | |
| `revisado_em` | timestamptz, null | |

Sugestões rejeitadas ficam registradas (`status = 'rejeitado'`)
especificamente para nunca re-sugerir o mesmo par de produtos de novo.

**Resolução do pai ao aprovar** (seção 4): se `produto_candidato_id` já
tem `produto_pai_id` preenchido, o pai da família é esse
`produto_pai_id`; senão, o próprio `produto_candidato_id` vira o pai. Só
`produto_id` (o novo/editado) recebe um `produto_pai_id` novo —
`produto_candidato_id` nunca é modificado.

## 3. Detecção automática

Trigger Postgres `AFTER INSERT OR UPDATE OF nome, categoria,
nome_comercial, especie, fase, porte, sabor, dose, apresentacao, peso,
volume ON produtos` (mesmo padrão arquitetural já usado no projeto, ex:
`sinalizar_revisar_preco`, `baixar_estoque`). Roda depois do trigger de
geração de `nome` da seção 1.

### 3.1 Caminho estruturado (prioritário, alta confiança)

Quando o produto tem pelo menos um campo estruturado preenchido:

1. Busca candidatos na mesma `categoria` + `fabricante`, com os mesmos
   valores em **todos** os campos estruturados exceto um.
2. Se encontrar exatamente um campo diferente entre os dois produtos,
   esse campo é o eixo de variação — vira `tipo_variacao` e o valor do
   campo vira `variante_label_sugerido`. Marca `origem = 'estruturado'`.
3. Se encontrar mais de um campo diferente (ambíguo — pode ser produto
   genuinamente diferente, não só variante), não sugere nada.

Não depende de similaridade de texto — é comparação exata de campos, por
isso a confiança é mais alta que o caminho heurístico abaixo.

### 3.2 Caminho heurístico (fallback, produtos sem campos estruturados)

Só roda quando o produto **não** tem nenhum campo estruturado preenchido
(catálogo legado, ou cadastro futuro que opte por não usar os campos
novos):

1. **Extração numérica**: regex de número+unidade
   (`\d+[.,]?\d*\s*(kg|g|mg|ml|l|un|cp|comprimidos?|capsulas?)`) sobre o
   `nome`. Se casar, tipo inferido pela unidade (kg/g → `peso`, mg →
   `dose`, ml/l → `volume`, etc.).
2. **Extração por dicionário**: se a extração numérica não achou nada,
   busca no `nome` qualquer `termo` de `termos_variacao` compatível com a
   categoria do produto.
3. Se nenhuma extração encontrar nada, não gera sugestão.
4. Remove o token encontrado do nome pra gerar uma string "base"
   normalizada, compara via similaridade de trigram (`pg_trgm`, extensão
   a ativar — hoje só `unaccent` está ativa no projeto) contra nomes
   (normalizados da mesma forma) de outros produtos sem família ainda,
   restrito a mesma categoria+fabricante+tipo de variação.
5. Acima de um limiar de similaridade (a calibrar durante os testes,
   ponto de partida `0.5`), sugere. Abaixo, não sugere — silêncio é o
   comportamento seguro. Marca `origem = 'heuristico'`.

### 3.3 Regras comuns aos dois caminhos

- Se já existe uma sugestão `pendente` ou `rejeitado` para o mesmo par
  produto/candidato, não duplica.
- **Extensibilidade**: cadastrar um termo novo em `termos_variacao`
  (caminho heurístico) ou preencher um campo estruturado já existente com
  um valor novo (caminho estruturado) já basta pro detector reconhecer o
  caso, sem deploy.

## 4. Revisão no app Gestor

Reaproveita o padrão já existente no app para o fluxo de "revisar preço"
(`produto.revisarPreco` → chip laranja no card do produto em
`produtos_screen.dart`), em vez de criar uma tela dedicada nova:

- Produto com sugestão `pendente` ganha um chip "Sugestão de variante" no
  card da listagem (mesmo estilo visual do chip de revisar preço, ícone
  diferente; indica visualmente se a origem é estruturada — mais
  confiável — ou heurística).
- Tocar no chip abre um diálogo comparando os dois produtos lado a lado
  (foto, nome, preço), mostrando o `tipo_variacao` detectado (editável
  via dropdown dos tipos cadastrados) e o `variante_label` de cada um
  (pré-preenchido, editável).
- **Aprovar**: resolve o pai da família (ver "Resolução do pai" na seção
  2) e grava `produto_id.produto_pai_id` = esse pai, além de
  `tipo_variacao`/`variante_label` em ambos os produtos. Marca a
  sugestão como `aprovado`.
- **Rejeitar**: marca a sugestão como `rejeitado`, produto continua sem
  família, nunca mais sugerido para esse par específico.

## 5. Exibição no site (Gestor Loja)

- **`catalogo_produtos_publico`** (view pública já existente) passa a
  expor `produto_pai_id`, `tipo_variacao` e `variante_label`. Nova
  view/consulta auxiliar expõe `tipos_variacao.rotulo_site`.
- **Catálogo**: produtos com o mesmo pai (ou o próprio pai) colapsam em
  um único card. Nome do card = `compor_nome_produto(...)` do produto
  âncora omitindo o campo indicado por `tipo_variacao` (mesma função da
  seção 1, reaproveitada — não duplica lógica). Mostra "a partir de R$X"
  (menor preço entre as opções em estoque; se nenhuma em estoque, menor
  preço entre todas) e a foto do produto representativo (mesma regra de
  preço mais baixo).
- **Página de produto**: quando o produto pertence a uma família, busca
  as demais opções (mesmo `produto_pai_id`, ou os filhos, se o produto
  atual for o pai) e renderiza um seletor (pills) rotulado com
  `tipos_variacao.rotulo_site` (ex: "Escolha o peso:", "Escolha o
  sabor:"), com os `variante_label` de cada opção, ordenados
  numericamente quando o tipo for numérico (peso/dose/volume) ou
  alfabeticamente quando for por texto (sabor). Cada opção continua
  sendo a página de produto própria dela (URL/SEO individual preservados)
  — selecionar uma opção navega para a página irmã correspondente, sem
  estado dinâmico de preço/estoque no cliente.

## Testes / validação

- Geração de nome: testar preenchendo campos estruturados de um produto
  de ração e um de farmácia, confirmar que o `nome` gerado bate com os
  exemplos reais documentados; testar `nome_manual_override` preservando
  edição manual.
- Trigger de detecção (caminho estruturado): dois produtos com todos os
  campos iguais exceto `peso` (ou `dose`) geram sugestão `origem =
  'estruturado'` correta; três ou mais campos diferentes não geram
  sugestão.
- Trigger de detecção (caminho heurístico): produtos reais existentes de
  ração/farmácia (sem campos estruturados) ainda geram sugestão via nome,
  confirmando que o catálogo legado não fica sem cobertura.
- Extensibilidade: cadastrar um termo novo em `termos_variacao` e
  confirmar reconhecimento sem alteração de código; preencher um campo
  estruturado com valor novo e confirmar o mesmo.
- Fluxo de aprovação: aprovar sugestão onde nenhum dos dois tinha família
  (cria a relação pai/filho do zero) e onde o candidato já era pai de
  outros filhos (só adiciona mais um filho) — confirmar resolução correta
  em ambos os casos.
- Site: catálogo com família real (card único, "a partir de"), seletor na
  página de produto navegando entre variantes, produto sem família
  continua funcionando como hoje (regressão).
