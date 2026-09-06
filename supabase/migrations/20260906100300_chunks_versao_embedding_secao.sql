-- Breeze — F1 corte C2: duas colunas aditivas em `chunks`, nenhuma toca RLS/policy (são dado de
-- citação e de rastreabilidade de pipeline, não de autorização — a policy de `chunks` continua
-- inteiramente ancorada em `pagina_ini` via app.pagina_visivel(), ADR-0018/D11).

-- ============================================================================
-- 1. chunks.versao_embedding (ADR-0027, corrige registro de dimensão do ADR-0005)
-- ============================================================================
-- `chunks.versao_pipeline` muda só quando muda o TEXTO ou a FRONTEIRA dos chunks (chunker
-- corrigido). Trocar de MODELO de embedding não é isso (ADR-0025 §2, ADR-0027 "trocar modelo de
-- embedding não é mudança de versao_pipeline") — colar as duas coisas no mesmo campo forçaria
-- reextração do acervo inteiro só para registrar troca de modelo de embedding.
-- NULL = sem embedding — o estado de TODO chunk em F1 (ADR-0027: etapa desligada, sem chave de
-- LLM). `reprocessar --estagio=embedding --onde="embedding is null"` (ADR-0027) é a consulta que
-- este campo, junto com chunks.embedding, precisa sustentar quando a chave chegar.
alter table public.chunks add column versao_embedding smallint;

comment on column public.chunks.versao_embedding is
  'Versão do MODELO de embedding que preencheu chunks.embedding (ADR-0027) — independente de '
  'versao_pipeline, que muda só com texto/fronteira de chunk. NULL = sem embedding (estado de '
  'todo chunk em F1, etapa desligada por falta de chave de LLM). Trocar de modelo bumpa só este '
  'campo; reindexação de embedding não é reextração de texto.';

-- ============================================================================
-- 2. chunks.secao (SPEC §4, D17/ADR-0024, emenda "medida ao chunkizar o Regimento real")
-- ============================================================================
-- Achado ao chunkizar o Regimento Interno real (23 páginas, texto nativo): o documento REINICIA
-- a numeração de artigo a CADA CAPÍTULO — 24 capítulos, 187 linhas que começam com "Artigo" e
-- somente 25 números distintos (existem 24 "Artigo 1º" no mesmo documento). "Artigo 5º do
-- Regimento" não identifica nada; a unidade citável é capítulo + artigo + página. Corrige a
-- contagem de "191 artigos" de docs/inventario-acervo.md, que era ocorrência do token "Art.",
-- não estrutura.
--
-- O chunker (lib/ingestao/chunker.ts, fora do escopo deste agente) já resolve isso no código: o
-- título do capítulo vigente viaja com o chunk e nenhum chunk atravessa fronteira de capítulo —
-- a mesma disciplina de fronteira dura já usada para visibilidade (ADR-0018/D11: um chunk não
-- cruza fronteira de página com visibilidade diferente). Falta só persistir o rótulo.
--
-- COLUNA, não `metadados`/jsonb: a busca FILTRA e EXIBE por seção (SPEC §4 D17 — a citação exige
-- capítulo + artigo + página), o mesmo motivo que já fez `pagina_ini` ser coluna própria e não
-- jsonb (SPEC §3.4, §6.2: "a citação depende disto"). Citação errada é o modo de falha mais caro
-- do produto (confiança é o que o produto vende) — não vale enterrar em jsonb o campo que a UI
-- vai filtrar.
--
-- NULLABLE e sem CHECK de formato: nem todo documento tem estrutura de seção (ata, balancete,
-- edital) — NULL significa "documento sem hierarquia de seção conhecida", não erro. O rótulo é
-- texto livre escrito pelo chunker ("Capítulo V — Das Vagas de Garagem"), não um código de
-- domínio; fechar formato aqui acoplaria o schema a uma convenção de um único documento.
alter table public.chunks add column secao text;

comment on column public.chunks.secao is
  'Rótulo de seção/capítulo vigente no ponto do documento onde o chunk começa (SPEC §4, D17: '
  '"chunks carrega a seção"). NULL quando o documento não tem hierarquia de seção conhecida '
  '(ata, balancete, edital) ou antes do chunker rodar. Existe porque numeração de artigo NÃO é '
  'globalmente única em documento real (Regimento Interno: 24 capítulos, 24 "Artigo 1º" '
  'distintos) — sem capítulo, "Artigo 5º" não identifica nada. O chunker garante que nenhum '
  'chunk atravessa fronteira de seção, então secao é sempre não ambígua dentro de um chunk. '
  'Texto livre (não é código de domínio): é rótulo de citação, não predicado de autorização — '
  'não participa de RLS, que continua ancorada só em pagina_ini (app.pagina_visivel()).';
