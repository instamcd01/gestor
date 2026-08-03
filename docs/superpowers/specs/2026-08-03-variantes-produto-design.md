# Variantes de produto — design

## Contexto

Hoje cada opção de peso/dose/sabor/cor de um produto é um registro
totalmente independente na tabela `produtos` — nome, SKU, preço e estoque
próprios, sem nenhum vínculo entre eles. Isso já foi observado durante a
limpeza de nomes do catálogo (ver memória "Padrão de nome de produto" do
projeto): por exemplo, "Ração Golden ... 10kg" e "Ração Golden ... 3kg"
são duas linhas sem relação estrutural no banco, apenas com nomes
parecidos. Além disso, o `nome` hoje é sempre texto livre digitado à mão
seguindo um padrão apenas por convenção manual — não há nenhum campo
estruturado por trás (isso já estava registrado como pendência em aberto
da limpeza de nomes, ver memória do projeto).

O pedido: no site do cliente (Gestor Loja), produtos que são a mesma
oferta em opções diferentes (peso, dose, sabor, cor, tamanho, ou outros
eixos que apareçam conforme o catálogo crescer) devem aparecer agrupados
em um único card, com um seletor de opção — em vez de aparecerem como
produtos totalmente separados no catálogo. O catálogo está prestes a
crescer com produtos e categorias novas, então o mecanismo de detecção
precisa reconhecer tipos de variação novos **sem exigir mudança de
código** — só cadastro de dados.

Este design cobre dois pendentes de uma vez, porque um resolve o outro:
transformar o cadastro de produto em campos estruturados (em vez de nome
livre) torna a detecção de grupos de variantes muito mais confiável — não
precisa mais "adivinhar" por regex/dicionário a partir do texto do nome,
basta comparar se os campos batem e só o campo de variação difere.

## Estoque — não muda

Cada variante continua sendo uma linha própria em `produtos`, com seu
próprio vínculo em `estoque`. Preço, custo e quantidade permanecem 100%
independentes por variante, exatamente como hoje. O agrupamento é
puramente um link de exibição (`grupo_variante_id`) — nenhuma trigger de
baixa de estoque, cálculo de margem ou lucro é alterada por este design.

## Escopo

- **Site (Gestor Loja)**: catálogo e página de produto passam a agrupar
  variantes visualmente.
- **App Gestor (Flutter, admin)**: o cadastro/edição de produto ganha
  campos estruturados novos (opcionais); a listagem de produtos continua
  tratando cada variante como um produto próprio — a mudança é uma forma
  de marcar quais produtos pertencem ao mesmo grupo (via revisão de
  sugestões automáticas).
- **Qualquer categoria do catálogo**, atual ou futura — o mecanismo não é
  travado em Ração/Farmácia. Ração e Farmácia são os primeiros casos
  reais usados para validar o design (são os dois padrões já documentados
  na memória do projeto).
- **Eixo único por grupo**: dentro de um mesmo grupo de variantes, a
  variação é sempre em uma única dimensão por vez (só peso, OU só sabor,
  OU só dose — nunca uma grade/matriz combinando dois eixos no mesmo
  produto). Se um produto real varia em dois eixos ao mesmo tempo, isso
  vira dois agrupamentos separados, não um grupo com seletor duplo.
- **Catálogo já existente (~540 produtos)**: os campos estruturados são
  opcionais e não são retroativamente preenchidos por este projeto — os
  produtos já cadastrados continuam com `nome` livre e usam a detecção
  por regex/dicionário (fallback, ver seção 3). Um backfill do catálogo
  existente para campos estruturados, se algum dia for feito, é projeto
  à parte.

## 1. Cadastro estruturado de produto

Campos novos, opcionais, adicionados à tela de cadastro/edição de produto
(`cadastro_produto_screen.dart` / `editar_produto_screen.dart`) e à
tabela `produtos`:

| coluna | tipo | exemplo | uso no template Farmácia | uso no template Ração |
|---|---|---|---|---|
| `marca_linha` | text, null | `"Agemoxi"`, `"Golden Fórmula"` | nome comercial | marca/linha |
| `especie` | text, null | `"Cães e Gatos"` | espécie | espécie |
| `fase` | text, null | `"Adultos"` | — | fase |
| `porte` | text, null | `"Pequeno"` | — | porte |
| `sabor` | text, null | `"Carne e Arroz"` | — | sabor |
| `dose` | text, null | `"250mg"` | dose | — |
| `principio_ativo` | text, null | `"Amoxicilina"` | composição (parênteses) | — |
| `apresentacao_quantidade` | text, null | `"10 Comprimidos"` | apresentação | — |

`peso`/`volume` (já existem na tabela) e `fabricante` (já existe)
continuam sendo usados como estão — não duplicados.

Todos os campos ficam disponíveis sempre (não há um formulário diferente
por categoria) — o que não se aplica à categoria do produto fica em
branco. Isso evita ter que tocar em código toda vez que uma categoria
nova aparecer, coerente com o objetivo de extensibilidade sem deploy.

### Geração automática do `nome`

Um trigger `BEFORE INSERT OR UPDATE ON produtos` compõe `nome`
automaticamente a partir dos campos preenchidos, seguindo uma única
ordem genérica (pulando qualquer segmento cujo campo esteja vazio):

```
{categoria} {marca_linha} {dose} ({principio_ativo}) {apresentacao_quantidade}
Para {especie} {fase} {"de Porte " + porte} {"Sabor " + sabor} {peso ou volume}
- {fabricante}
```

Validado contra os dois padrões reais já documentados na memória do
projeto — reproduz exatamente:
- Farmácia: `Antibiotico Agemoxi 250mg (Amoxicilina) 10 Comprimidos Para Caes e Gatos - Agener Uniao`
- Ração: `Ração Golden Fórmula Para Cães Adultos de Porte Pequeno Sabor Carne e Arroz 10kg - PremieRpet`

**Escape hatch**: coluna nova `nome_manual_override boolean default false`.
Quando `true` (marcado ao editar `nome` manualmente em vez dos campos
estruturados), o trigger não sobrescreve — preserva o comportamento atual
pra qualquer produto que não se encaixe bem no template genérico. Produto
cadastrado só com `nome` livre (sem nenhum campo estruturado) continua
funcionando exatamente como hoje.

## 2. Modelo de dados de variantes

### Tabela nova `tipos_variacao`

Vocabulário dos eixos de variação conhecidos.

| coluna | tipo | notas |
|---|---|---|
| `id` | uuid, PK | |
| `nome` | text, unique | `"peso"`, `"dose"`, `"sabor"`, `"apresentacao_quantidade"`, etc. — mesmo nome da coluna estruturada correspondente, quando existir |
| `rotulo_site` | text | texto do seletor no site, ex: `"Escolha o peso:"`, `"Escolha o sabor:"` |

Linhas iniciais correspondem 1:1 às colunas estruturadas da seção 1
(`peso`, `dose`, `sabor`, `apresentacao_quantidade`). Tipos novos (ex.
categorias futuras com "cor", "textura") só precisam de uma linha nova
aqui — não exigem coluna nova em `produtos` se o valor puder ser
capturado como texto livre associado ao grupo (ver nota em `variante_label`
na seção seguinte).

### Tabela nova `termos_variacao`

Dicionário de valores conhecidos por tipo, usado **apenas pelo caminho de
fallback** (produtos sem campos estruturados, detecção por texto livre no
`nome` — ver seção 3.2).

| coluna | tipo | notas |
|---|---|---|
| `id` | uuid, PK | |
| `tipo_variacao_id` | uuid, FK `tipos_variacao` | |
| `termo` | text | ex: `"Frango"`, `"Carne"`, `"Salmão"` |
| `categoria` | text, null | restringe o termo a uma categoria específica; `null` = vale pra qualquer categoria |

### Tabela nova `grupos_variante`

| coluna | tipo | notas |
|---|---|---|
| `id` | uuid, PK | |
| `empresa_id` | uuid, FK `empresas` | multi-tenant, mesmo padrão do resto do schema |
| `categoria` | text | herdada dos produtos do grupo, só pra filtro/consulta |
| `tipo_variacao_id` | uuid, FK `tipos_variacao` | o eixo único deste grupo (peso, sabor, dose...) |
| `nome_base` | text | nome exibido no card do site, sem a parte que varia |
| `created_at` | timestamptz | |

### Colunas novas em `produtos`

- `grupo_variante_id uuid null references grupos_variante(id)` — a qual
  grupo esse produto pertence, se algum. Produtos sem grupo continuam
  funcionando exatamente como hoje (grupo é opt-in, não obrigatório).
- `variante_label text null` — o valor deste produto dentro do eixo do
  grupo, ex: `"1kg"`, `"250mg"`, `"Frango"`. Pré-preenchido
  automaticamente pelo detector: direto do campo estruturado
  correspondente quando existir (`peso`, `dose`, `sabor`,
  `apresentacao_quantidade`), ou por extração heurística do `nome` no
  caminho de fallback. Sempre editável no fluxo de aprovação antes de
  virar definitivo — nunca publicado sem confirmação humana.

### Tabela nova `sugestoes_grupo_variante`

| coluna | tipo | notas |
|---|---|---|
| `id` | uuid, PK | |
| `produto_id` | uuid, FK `produtos` | o produto novo/editado que disparou a sugestão |
| `produto_candidato_id` | uuid, FK `produtos`, null | produto existente parecido (quando o alvo ainda não tem grupo) |
| `grupo_variante_id` | uuid, FK `grupos_variante`, null | grupo existente (quando o alvo já tem grupo) |
| `tipo_variacao_id` | uuid, FK `tipos_variacao` | eixo detectado |
| `variante_label_sugerido` | text | valor extraído, pré-preenche o diálogo de revisão |
| `origem` | text | `"estruturado"` \| `"heuristico"` — de qual caminho de detecção veio (seção 3), mostrado na revisão pra dar mais ou menos confiança visualmente |
| `status` | text | `pendente` \| `aprovado` \| `rejeitado` |
| `criado_em` | timestamptz | |
| `revisado_em` | timestamptz, null | |

Exatamente um de `produto_candidato_id` / `grupo_variante_id` é
preenchido, nunca os dois. Sugestões rejeitadas ficam registradas
(`status = 'rejeitado'`) especificamente para nunca re-sugerir o mesmo
par de produtos de novo.

## 3. Detecção automática

Trigger Postgres `AFTER INSERT OR UPDATE OF nome, categoria, marca_linha,
especie, fase, porte, sabor, dose, apresentacao_quantidade, peso, volume
ON produtos` (mesmo padrão arquitetural já usado no projeto para lógica
de negócio via trigger, ex: `sinalizar_revisar_preco`, `baixar_estoque`).
Roda depois do trigger de geração de `nome` da seção 1.

### 3.1 Caminho estruturado (prioritário, alta confiança)

Quando o produto tem pelo menos um campo estruturado preenchido:

1. Busca candidatos na mesma `categoria` + `fabricante`, com os mesmos
   valores em **todos** os campos estruturados exceto um.
2. Se encontrar exatamente um campo diferente entre os dois produtos,
   esse campo é o eixo de variação — mapeia direto pro `tipo_variacao_id`
   correspondente (`peso`→peso, `dose`→dose, `sabor`→sabor, etc.) e o
   valor do campo vira `variante_label_sugerido`. Marca `origem =
   'estruturado'`.
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
   normalizada, compara via similaridade de trigram (`pg_trgm`) contra
   `nome_base` de grupos existentes e nomes de outros produtos sem grupo,
   sempre restrito a mesma categoria+fabricante+tipo de variação.
5. Acima de um limiar de similaridade (a calibrar durante os testes,
   ponto de partida `0.5`), sugere. Abaixo, não sugere — silêncio é o
   comportamento seguro (prefere agrupamento manual a arriscar juntar
   produtos errados). Marca `origem = 'heuristico'`.

### 3.3 Regras comuns aos dois caminhos

- Se já existe uma sugestão `pendente` ou `rejeitado` para o mesmo par
  produto/candidato, não duplica.
- **Extensibilidade**: cadastrar um termo novo em `termos_variacao`
  (caminho heurístico) ou simplesmente preencher um campo estruturado já
  existente com um valor novo (caminho estruturado) já basta pro detector
  reconhecer o caso, sem deploy. Um eixo estruturado genuinamente novo
  (nem peso/dose/sabor/apresentação) exigiria uma coluna nova em
  `produtos` + linha nova em `tipos_variacao` — mudança pequena e aditiva,
  não uma reescrita.

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
- **Aprovar**: se nenhum dos dois já tem grupo, cria um `grupos_variante`
  novo (com `nome_base` e `tipo_variacao_id` sugeridos, editáveis) e
  associa ambos; se um já tem grupo, associa o outro a esse grupo
  existente. Marca a sugestão como `aprovado`.
- **Rejeitar**: marca a sugestão como `rejeitado`, produto continua sem
  grupo, nunca mais sugerido para esse par específico.

## 5. Exibição no site (Gestor Loja)

- **`catalogo_produtos_publico`** (view pública já existente) passa a
  expor `grupo_variante_id` e `variante_label`. Nova view/consulta
  auxiliar expõe `grupos_variante` + `tipos_variacao.rotulo_site`.
- **Catálogo**: produtos com o mesmo `grupo_variante_id` colapsam em um
  único card. Card usa `grupos_variante.nome_base`, mostra "a partir de
  R$X" (menor preço entre as opções em estoque; se nenhuma em estoque,
  menor preço entre todas) e a foto do produto representativo (mesma
  regra de preço mais baixo).
- **Página de produto**: quando o produto pertence a um grupo, busca as
  demais opções do mesmo `grupo_variante_id` e renderiza um seletor
  (pills) rotulado com `tipos_variacao.rotulo_site` (ex: "Escolha o
  peso:", "Escolha o sabor:"), com os `variante_label` de cada opção,
  ordenados numericamente quando o tipo for numérico (peso/dose/volume)
  ou alfabeticamente quando for por texto (sabor). Cada opção continua
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
- Fluxo de aprovação: criação de grupo novo e associação a grupo
  existente, edição de `tipo_variacao`/`variante_label` antes de salvar.
- Site: catálogo com grupo real (card único, "a partir de"), seletor na
  página de produto navegando entre variantes, produto sem grupo
  continua funcionando como hoje (regressão).
