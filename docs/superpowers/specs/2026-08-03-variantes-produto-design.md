# Variantes de produto (peso/dose) — design

## Contexto

Hoje cada opção de peso/dose de um produto é um registro totalmente
independente na tabela `produtos` — nome, SKU, preço e estoque próprios, sem
nenhum vínculo entre eles. Isso já foi observado durante a limpeza de nomes
do catálogo (ver memória "Padrão de nome de produto" do projeto): por
exemplo, "Ração Golden ... 10kg" e "Ração Golden ... 3kg" são duas linhas
sem relação estrutural no banco, apenas com nomes parecidos.

O pedido: no site do cliente (Gestor Loja), produtos que são a mesma
oferta em opções diferentes de peso/tamanho (ração) ou dose/apresentação
(farmácia) devem aparecer agrupados em um único card, com um seletor de
opção — em vez de aparecerem como produtos totalmente separados no
catálogo.

## Escopo

- **Site (Gestor Loja)**: catálogo e página de produto passam a agrupar
  variantes visualmente.
- **App Gestor (Flutter, admin)**: continua tratando cada variante como um
  produto próprio na listagem — a única mudança é uma forma de marcar quais
  produtos pertencem ao mesmo grupo (via revisão de sugestões automáticas).
- Categorias-alvo iniciais: Ração (variação por peso) e Farmácia (variação
  por dose e/ou apresentação/quantidade). Outras categorias podem reusar o
  mesmo mecanismo depois, sem mudança de design.
- Fora de escopo: seletor de sabor/cor genérico (não pedido agora — só
  peso/tamanho para ração, dose/apresentação para farmácia).

## 1. Modelo de dados

### Tabela nova `grupos_variante`

| coluna | tipo | notas |
|---|---|---|
| `id` | uuid, PK | |
| `empresa_id` | uuid, FK `empresas` | multi-tenant, mesmo padrão do resto do schema |
| `categoria` | text | herdada dos produtos do grupo, só pra filtro/consulta |
| `nome_base` | text | nome exibido no card do site, sem a parte que varia (ex: "Ração Golden Fórmula Para Cães Adultos de Porte Pequeno Sabor Carne e Arroz - PremieRpet") |
| `created_at` | timestamptz | |

### Colunas novas em `produtos`

- `grupo_variante_id uuid null references grupos_variante(id)` — a qual
  grupo esse produto pertence, se algum. Produtos sem grupo continuam
  funcionando exatamente como hoje (grupo é opt-in, não obrigatório).
- `variante_label text null` — o que diferencia essa linha dentro do
  grupo: `"1kg"`, `"250mg"`, `"500mg (10 comprimidos)"`. Pré-preenchido
  automaticamente a partir da coluna `peso` quando ela existir (caso comum
  de ração); quando não existir (farmácia, que não tem coluna de dose),
  pré-preenchido por extração via regex do campo `nome` (padrão
  número+unidade, ex: `250mg`, `30 comprimidos`). Sempre editável no
  fluxo de aprovação antes de virar definitivo — nunca publicado sem
  confirmação humana.

### Tabela nova `sugestoes_grupo_variante`

| coluna | tipo | notas |
|---|---|---|
| `id` | uuid, PK | |
| `produto_id` | uuid, FK `produtos` | o produto novo/editado que disparou a sugestão |
| `produto_candidato_id` | uuid, FK `produtos`, null | produto existente parecido (quando o alvo ainda não tem grupo) |
| `grupo_variante_id` | uuid, FK `grupos_variante`, null | grupo existente (quando o alvo já tem grupo) |
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

Ao disparar, a função:

1. Normaliza o nome do produto que mudou: remove acentuação/pontuação,
   remove tokens de número+unidade (`\d+[.,]?\d*\s*(kg|g|mg|ml|l|un|cp|
   comprimidos?|capsulas?)`), gera uma string "base" para comparação.
2. Busca candidatos **apenas dentro da mesma `categoria` e mesmo
   `fabricante`** (nunca compara contra o catálogo inteiro — reduz custo
   e, mais importante, reduz risco de falso positivo entre produtos não
   relacionados).
3. Compara a string base via similaridade de trigram (`pg_trgm`,
   `similarity()`) contra: (a) `nome_base` de grupos já existentes nessa
   categoria/fabricante, e (b) nomes normalizados de outros produtos sem
   grupo ainda.
4. Acima de um limiar de similaridade (a calibrar durante os testes,
   ponto de partida `0.5`), insere uma linha `pendente` em
   `sugestoes_grupo_variante` apontando pro melhor candidato. Abaixo do
   limiar, não sugere nada — silêncio é o comportamento seguro aqui
   (prefere exigir agrupamento manual a arriscar juntar dois produtos
   errados sem revisão).
5. Se já existe uma sugestão `pendente` ou `rejeitado` para o mesmo par
   produto/candidato, não duplica.

## 3. Revisão no app Gestor

Reaproveita o padrão já existente no app para o fluxo de "revisar preço"
(`produto.revisarPreco` → chip laranja no card do produto em
`produtos_screen.dart`), em vez de criar uma tela dedicada nova:

- Produto com sugestão `pendente` ganha um chip "Sugestão de variante" no
  card da listagem (mesmo estilo visual do chip de revisar preço, ícone
  diferente).
- Tocar no chip abre um diálogo comparando os dois produtos lado a lado
  (foto, nome, preço) com os campos `variante_label` de cada um
  pré-preenchidos e editáveis.
- **Aprovar**: se nenhum dos dois já tem grupo, cria um `grupos_variante`
  novo (com `nome_base` = nome normalizado sugerido, editável) e associa
  ambos; se um já tem grupo, associa o outro a esse grupo existente.
  Marca a sugestão como `aprovado`.
- **Rejeitar**: marca a sugestão como `rejeitado`, produto continua sem
  grupo, nunca mais sugerido para esse par específico.

## 4. Exibição no site (Gestor Loja)

- **`catalogo_produtos_publico`** (view pública já existente) passa a
  expor `grupo_variante_id` e `variante_label`.
- **Catálogo**: produtos com o mesmo `grupo_variante_id` colapsam em um
  único card. Card usa `grupos_variante.nome_base`, mostra "a partir de
  R$X" (menor preço entre as opções em estoque; se nenhuma em estoque,
  menor preço entre todas) e a foto do produto representativo (mesma
  regra de preço mais baixo).
- **Página de produto**: quando o produto pertence a um grupo, busca as
  demais opções do mesmo `grupo_variante_id` e renderiza um seletor
  (pills) com os `variante_label`, ordenado numericamente quando possível
  (extrai o número do label pra ordenar, cai pra ordem alfabética se não
  conseguir). Cada opção continua sendo a página de produto própria dela
  (URL/SEO individual preservados) — selecionar uma opção navega para a
  página irmã correspondente, sem estado dinâmico de preço/estoque no
  cliente.

## Testes / validação

- Trigger: testar inserção/edição de produtos reais de ração e farmácia
  com nomes parecidos, confirmar que só produtos da mesma
  categoria+fabricante geram sugestão, confirmar que sugestões rejeitadas
  não reaparecem.
- Fluxo de aprovação: testar criação de grupo novo e associação a grupo
  existente, confirmar edição do `variante_label` antes de salvar.
- Site: testar catálogo com um grupo real (card único, preço "a partir
  de"), testar página de produto com seletor navegando entre variantes,
  confirmar que um produto sem grupo continua funcionando exatamente como
  hoje (regressão).
