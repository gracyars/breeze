# ADR-0005 — Busca híbrida: `tsvector` PT-BR + pgvector, fundidos por RRF

## Contexto

As perguntas reais são de dois tipos incompatíveis (SPEC §4, §6.2): normativa em linguagem
natural ("posso ter cachorro?") e identificador exato ("art. 12", "R$ 43.200", "AGE de março").
FTS falha na primeira (paráfrase, sinônimo); busca vetorial falha na segunda (número e
referência legal somem no embedding) — e errar identificador exato em documento legal é fatal.

## Decisão

Duas listas independentes, fundidas por **Reciprocal Rank Fusion**:

- **Léxica:** `chunks.tsv` (`tsvector` gerado, coluna `stored`) com configuração de texto
  customizada `public.pt_br`, que encadeia `unaccent` antes de `portuguese_stem` — resolve
  "sindico"/"síndico". Índice GIN.
- **Semântica:** `chunks.embedding vector(1536)`, distância cosseno. **Sem índice vetorial até
  ~10k chunks** — varredura sequencial é mais rápida e mais exata nessa faixa. Acima disso, HNSW.
- **Fusão:** `score = Σ 1/(60 + rank_i)` sobre o top-50 de cada lista → top-10.
  `ts_rank_cd` e distância cosseno **alimentam ranks, nunca são somados** — as escalas não são
  comparáveis e somá-las é calibração invisível que quebra silenciosamente.
- **Rede de digitação:** `pg_trgm` sobre nome próprio (fornecedor, pessoa, título).
- **Sinônimos:** tabela `sinonimos` com expansão **da query na aplicação**, não no dicionário do
  Postgres — Supabase gerenciado não dá acesso a `$SHAREDIR` para `synonym`/`thesaurus`.
- **Pré-filtro em Postgres antes do vetorial** (tipo, ano, competência, fornecedor). Nesta escala
  é barato e evita o problema clássico de filtro pós-ANN devolver menos que k resultados.

**Roteamento de intenção, regra dura (SPEC §4):** pergunta sobre valor nunca é respondida por RAG
sobre balancete escaneado — vai para SQL sobre `lancamentos`. Pergunta normativa vai para busca
semântica sobre convenção e regimento. O OCR erra dígito (SPEC §3.3); número só sai do fluxo
estruturado e conferido.

## Consequências

- A configuração `public.pt_br` precisa existir **antes** de qualquer coluna gerada que a use, e
  precisa ser referenciada com nome qualificado: `to_tsvector('public.pt_br', texto)` é
  `IMMUTABLE` (a forma de 1 argumento, que lê `default_text_search_config`, não é) — sem isso a
  coluna gerada não compila. Trava de migração, não detalhe.
- Trocar o modelo de embedding é reindexação completa do acervo e mudança de dimensão da coluna.
  A dimensão 1536 fica registrada em `chunks.versao_pipeline`; reprocessar é um comando (SPEC §3).
- RRF com k=60 dispensa calibração de peso, mas não é gratuito: ele iguala a importância das duas
  listas. Se a busca léxica se mostrar dominante na prática, o ajuste é por peso no RRF
  (`w_i/(60+rank_i)`), com o valor em `configuracoes`, não em código.
- A skill `postgres-hybrid-text-search` (Timescale, D6) é **referência de RRF apenas**: pressupõe
  `pg_textsearch`/BM25, indisponível no Supabase gerenciado. A receita dela não roda aqui.

## Alternativas descartadas

- **FTS puro.** Morre em paráfrase — e a pergunta do morador é sempre paráfrase.
- **Vetorial puro.** Morre em "art. 12" e em valor. Inaceitável em documento legal.
- **Motor externo (Elasticsearch, Pinecone, Typesense).** Mais um serviço, mais um backup, mais
  uma consistência eventual, custo fora do teto. Contraria ADR-0002.
- **Soma ponderada de `ts_rank_cd` com similaridade cosseno.** Exige calibração por corpus e
  degrada em silêncio quando o acervo muda. RRF é robusto por construção.
- **HNSW desde o dia 1.** Índice aproximado sobre ~2k chunks só adiciona risco de recall
  faltante sem ganho mensurável. Não otimizar antes de doer (SPEC §2).

## Status

Aceito. Formaliza ADR-5 da tabela do SPEC §1.1.
