# Variantes de produto — design

## Contexto

Hoje cada opção de peso/dose/sabor/cor de um produto é um registro
totalmente independente na tabela `produtos` — nome, SKU, preço e estoque
próprios, sem nenhum vínculo entre eles. Isso já foi observado durante a
limpeza de nomes do catálogo (ver memória "Padrão de nome de produto" do
projeto): por exemplo, "Ração Golden ... 10kg" e "Ração Golden ... 3kg"
são duas linhas sem relação estrutural no banco, apenas com nomes
parecidos.

O pedido: no site do cliente (Gestor Loja), produtos que são a mesma
oferta em opções diferentes (peso, dose, sabor, cor, tamanho, ou outros
eixos que apareçam conforme o catálogo crescer) devem aparecer agrupados
em um único card, com um seletor de opção — em vez de aparecerem como
produtos totalmente separados no catálogo. O catálogo está prestes a
crescer com produtos e categorias novas, então o mecanismo de detecção
precisa reconhecer tipos de variação novos **sem exigir mudança de
código** — só cadastro de dados.

## Estoque — não muda

Cada variante continua sendo uma linha própria em `produtos`, com seu
próprio vínculo em `estoque`. Preço, custo e quantidade permanecem 100%
independentes por variante, exatamente como hoje. O agrupamento é
puramente um link de exibição (`grupo_variante_id`) — nenhuma trigger de
baixa de estoque, cálculo de margem ou lucro é alterada por este design.

## Escopo

- **Site (Gestor Loja)**: catálogo e página de produto passam a agrupar
  variantes visualmente.
- **App Gestor (Flutter, admin)**: continua tratando cada variante como um
  produto próprio na listagem — a única mudança é uma forma de marcar quais
  produtos pertencem ao mesmo grupo (via revisão de sugestões automáticas).
- **Qualquer categoria do catálogo**, atual ou futura — o mecanismo não é
  travado em Ração/Farmácia. Ração e Farmácia são só os primeiros casos
  reais usados para validar o design.
- **Eixo único por grupo**: dentro de um mesmo grupo de variantes, a
  variação é sempre em uma única dimensão por vez (só peso, OU só sabor,
  OU só cor — nunca uma grade/matriz combinando dois eixos no mesmo
  produto). Se um produto real varia em dois eixos ao mesmo tempo, isso
  vira dois agrupamentos separados, não um grupo com seletor duplo.
  Decidido para manter o modelo de dados simples; suportar grade
  multi-eixo é uma extensão de design própria, não incluída aqui.

## 1. Modelo de dados

### Tabela nova `tipos_variacao`

Vocabulário extensível dos eixos de variação conhecidos — cadastrada via
SQL/Supabase diretamente (sem tela dedicada por enquanto; é raro o
suficiente para não justificar UI própria ainda — reavaliar se virar
tarefa frequente).

| coluna | tipo | notas |
|---|---|---|
| `id` | uuid, PK | |
| `nome` | text, unique | `"peso"`, `"dose"`, `"sabor"`, `"cor"`, `"tamanho"`, etc. |
| `rotulo_site` | text | texto do seletor no site, ex: `"Escolha o peso:"`, `"Escolha o sabor:"` |

### Tabela nova `termos_variacao`

Dicionário de valores conhecidos por tipo, usado pelo detector para
reconhecer variação **por texto** (sabor, cor, tamanho categórico) — a
variação **numérica** (peso, dose, volume) não depende deste dicionário,
é reconhecida por regex de número+unidade diretamente (ver seção 2).

| coluna | tipo | notas |
|---|---|---|
| `id` | uuid, PK | |
| `tipo_variacao_id` | uuid, FK `tipos_variacao` | |
| `termo` | text | ex: `"Frango"`, `"Carne"`, `"Salmão"`, `"Azul"`, `"Rosa"` |
| `categoria` | text, null | restringe o termo a uma categoria específica quando necessário (ex: "Azul" só faz sentido pra Brinquedos, não pra Farmácia); `null` = vale pra qualquer categoria |

Cadastrar um tipo de variação novo (ex: "textura") ou um termo novo (ex:
mais um sabor) é só um INSERT nessas duas tabelas — o trigger de detecção
não precisa de deploy novo pra reconhecer casos novos, exceto se o eixo
novo for numérico com uma unidade ainda não coberta pela regex (ver
seção 2), caso mais raro.

### Tabela nova `grupos_variante`

| coluna | tipo | notas |
|---|---|---|
| `id` | uuid, PK | |
| `empresa_id` | uuid, FK `empresas` | multi-tenant, mesmo padrão do resto do schema |
| `categoria` | text | herdada dos produtos do grupo, só pra filtro/consulta |
| `tipo_variacao_id` | uuid, FK `tipos_variacao` | o eixo único deste grupo (peso, sabor, cor...) |
| `nome_base` | text | nome exibido no card do site, sem a parte que varia (ex: "Ração Golden Fórmula Para Cães Adultos de Porte Pequeno - PremieRpet") |
| `created_at` | timestamptz | |

### Colunas novas em `produtos`

- `grupo_variante_id uuid null references grupos_variante(id)` — a qual
  grupo esse produto pertence, se algum. Produtos sem grupo continuam
  funcionando exatamente como hoje (grupo é opt-in, não obrigatório).
- `variante_label text null` — o valor deste produto dentro do eixo do
  grupo: `"1kg"`, `"250mg"`, `"Frango"`, `"Azul"`. Pré-preenchido
  automaticamente pelo detector (a partir da coluna `peso` quando
  existir, ou por extração do `nome` via regex numérica ou dicionário de
  termos — ver seção 2). Sempre editável no fluxo de aprovação antes de
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
| `status` | text | `pendente` \| `aprovado` \| `rejeitado` |
| `criado_em` | timestamptz | |
| `revisado_em` | timestamptz, null | |

Exatamente um de `produto_candidato_id` / `grupo_variante_id` é
preenchido, nunca os dois. Sugestões rejeitadas ficam registradas
(`status = 'rejeitado'`) especificamente para nunca re-sugerir o mesmo
par de produtos de novo.

## 2. Detecção automática

Trigger Postgres `AFTER INSERT OR UPDATE OF nome, categoria ON produtos`
(mesmo padrão arquitetural já usado no projeto para lógica de negócio via
trigger, ex: `sinalizar_revisar_preco`, `baixar_estoque`).

Ao disparar, a função tenta extrair um token de variação do nome do
produto, em ordem:

1. **Extração numérica** (cobre peso/dose/volume/quantidade
   automaticamente, sem precisar de dicionário): regex de número+unidade
   (`\d+[.,]?\d*\s*(kg|g|mg|ml|l|un|cp|comprimidos?|capsulas?)`) sobre o
   `nome`. Se casar, o tipo de variação é inferido pela unidade (kg/g →
   `peso`, mg → `dose`, ml/l → `volume`, etc. — mapeamento fixo
   unidade→tipo) e o token vira o `variante_label_sugerido`.
2. **Extração por dicionário** (cobre sabor/cor/tamanho categórico e
   qualquer tipo novo cadastrado em `termos_variacao`): se a extração
   numérica não encontrou nada, busca no `nome` qualquer `termo` de
   `termos_variacao` cujo `categoria` seja `null` ou igual à categoria do
   produto. Se casar, esse é o tipo/label.
3. Se nenhuma extração encontrar nada, não gera sugestão — produto segue
   sem grupo, sem erro.

Com um token de variação em mãos:

4. Remove o token do nome pra gerar uma string "base" normalizada
   (acentuação/pontuação removidas).
5. Busca candidatos **apenas dentro da mesma `categoria` e mesmo
   `fabricante`** (nunca compara contra o catálogo inteiro — reduz custo
   e, mais importante, reduz risco de falso positivo entre produtos não
   relacionados).
6. Compara a string base via similaridade de trigram (`pg_trgm`,
   `similarity()`) contra: (a) `nome_base` de grupos já existentes nessa
   categoria/fabricante **com o mesmo `tipo_variacao_id`**, e (b) nomes
   normalizados de outros produtos sem grupo ainda que também tenham
   gerado o mesmo tipo de token.
7. Acima de um limiar de similaridade (a calibrar durante os testes,
   ponto de partida `0.5`), insere uma linha `pendente` em
   `sugestoes_grupo_variante` apontando pro melhor candidato. Abaixo do
   limiar, não sugere nada — silêncio é o comportamento seguro aqui
   (prefere exigir agrupamento manual a arriscar juntar dois produtos
   errados sem revisão).
8. Se já existe uma sugestão `pendente` ou `rejeitado` para o mesmo par
   produto/candidato, não duplica.

**Nota sobre extensibilidade**: cadastrar um sabor/cor/tamanho novo em
`termos_variacao` já basta pro detector passar a reconhecê-lo, sem
deploy. Um eixo novo puramente numérico com unidade ainda não coberta
(ex: "L" de litro já coberto, mas algo tipo "cm" não estaria) exigiria
uma alteração pequena na regex/mapeamento da função — único caso que
ainda pede mudança de código, documentado aqui para não ser surpresa
futura.

## 3. Revisão no app Gestor

Reaproveita o padrão já existente no app para o fluxo de "revisar preço"
(`produto.revisarPreco` → chip laranja no card do produto em
`produtos_screen.dart`), em vez de criar uma tela dedicada nova:

- Produto com sugestão `pendente` ganha um chip "Sugestão de variante" no
  card da listagem (mesmo estilo visual do chip de revisar preço, ícone
  diferente).
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

## 4. Exibição no site (Gestor Loja)

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
  ou alfabeticamente quando for por texto (sabor/cor). Cada opção
  continua sendo a página de produto própria dela (URL/SEO individual
  preservados) — selecionar uma opção navega para a página irmã
  correspondente, sem estado dinâmico de preço/estoque no cliente.

## Testes / validação

- Trigger: testar inserção/edição de produtos reais de ração (peso),
  farmácia (dose) e pelo menos um caso de variação por texto (sabor, se
  já houver dado real cadastrado) — confirmar que só produtos da mesma
  categoria+fabricante+tipo de variação geram sugestão, confirmar que
  sugestões rejeitadas não reaparecem.
- Extensibilidade: cadastrar um termo novo em `termos_variacao` (ex: um
  sabor que ainda não existia) e confirmar que o detector passa a
  reconhecê-lo em um produto novo sem qualquer alteração de código.
- Fluxo de aprovação: testar criação de grupo novo e associação a grupo
  existente, confirmar edição do `tipo_variacao`/`variante_label` antes
  de salvar.
- Site: testar catálogo com um grupo real (card único, preço "a partir
  de"), testar página de produto com seletor navegando entre variantes,
  confirmar que um produto sem grupo continua funcionando exatamente como
  hoje (regressão).
