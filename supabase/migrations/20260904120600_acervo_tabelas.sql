-- Breeze — baseline 06: acervo documental (tipos_documento, documentos, documento_unidades,
-- documento_paginas, chunks). Fonte: docs/schema.md §6; SPEC §2, §3, §7.
--
-- CORREÇÃO DE SCHEMA (orquestrador, 2026-09-04, docs/inventario-acervo.md achado "um PDF pode
-- conter mais de uma visibilidade"): a sonda do acervo real achou uma ata (AGE 04.02.2026, 36
-- páginas) que embute o Regimento Interno inteiro como anexo — mesmo documento_id, conteúdo que
-- deveria ser público (o regimento) e conteúdo que exige autenticação (a ata, com nomes e
-- deliberações). Visibilidade deixa de ser resolvida só em `documentos`; passa a ser resolvida
-- POR PÁGINA, com herança de `documentos.visibilidade` quando a página não tem override, e com
-- uma trava de "não vira público por omissão" quando o documento está marcado como misto — ver
-- `documentos.tem_paginas_mistas` e `documento_paginas.visibilidade` abaixo, e as funções em
-- 20260904120800_visibilidade_documento_funcoes.sql (app.nivel_efetivo, app.pagina_visivel).
-- Continua valendo a regra de uma função só (armadilha nº1, SPEC §7): nenhuma policy reescreve
-- este predicado, todas chamam a função.

-- ============================================================================
-- tipos_documento — tabela de domínio (ADR-0015)
-- ============================================================================
create table public.tipos_documento (
  codigo              text primary key,         -- 'convencao','regimento','ata_assembleia',...
  nome                text not null,
  visibilidade_padrao public.visibilidade_documento not null default 'autenticado',
  -- Trava do Briefing §7.1 / SPEC §7: só normativo impessoal pode ser público.
  permite_publico     boolean not null default false,
  retencao_meses      int,                      -- null = permanente
  ordem               int not null default 100,
  ativo               boolean not null default true
);

comment on table public.tipos_documento is
  'RLS: leitura para todos (inclusive anon — a UI pública lista tipos); escrita só editor. '
  'Por quê: é taxonomia, não dado. Tabela de domínio (e não enum) porque a taxonomia cresce com '
  'a operação — laudo novo não deve exigir deploy (ADR-0015).';

-- ============================================================================
-- documentos
-- ============================================================================
create table public.documentos (
  id             uuid primary key default extensions.gen_random_uuid(),
  tipo           text not null references public.tipos_documento(codigo) on delete restrict,
  titulo         text not null check (length(btrim(titulo)) >= 3),
  data_documento date,
  competencia    date,   -- mês de referência; sempre dia 1
  storage_bucket text not null default 'documentos',
  storage_path   text not null unique,
  -- Nome do objeto NÃO carrega informação (ADR-0004 item 5): '<uuid>.pdf'.
  sha256         bytea not null unique check (octet_length(sha256) = 32),  -- dedupe (SPEC §3.1)
  bytes          bigint check (bytes > 0),
  paginas        int check (paginas > 0),
  ocr_aplicado   boolean not null default false,
  status         public.status_documento not null default 'pendente',
  visibilidade   public.visibilidade_documento not null default 'autenticado',
  -- [ADR-0023/D16] Sinalizador de INTENÇÃO/curadoria PURO — true quando o documento embute
  -- conteúdo de nível de exposição diferente do padrão (ex.: ata que embute o regimento como
  -- anexo). A editora pode ligá-la cedo para declarar intenção; um trigger (ver
  -- 20260904120800_visibilidade_documento_funcoes.sql) liga-a sozinha assim que a primeira
  -- página ganha override e NUNCA a desliga automaticamente.
  -- ATENÇÃO: esta coluna NUNCA governou decisão de segurança, e desde ADR-0023/D16 nem o
  -- CONCEITO que ela representa ("documento misto") participa mais de app.nivel_efetivo() —
  -- existiu ali como `app.documento_tem_override()`, um `exists` sobre outras páginas do mesmo
  -- documento (predicado NÃO LOCAL, espécie modal), e foi esse `exists` que vazou na 3ª rodada
  -- do auditor-rls (apagar a única página com override reabria páginas não classificadas que
  -- nada tinham a ver com a página apagada). A correção não foi consertar o predicado — foi
  -- eliminar o conceito: sob a invariante do piso (ADR-0019), herdar o piso do documento para
  -- página sem override é sempre seguro, então o `exists` nunca protegia nada. Esta coluna
  -- sobrevive só como sinal de UI/curadoria.
  tem_paginas_mistas boolean not null default false,
  versao_pipeline int not null default 1,   -- idempotência do reprocessamento (SPEC §3)
  metadados      jsonb not null default '{}'::jsonb,  -- extração da classificação (SPEC §3.5)
  publicado_em   timestamptz,
  publicado_por  uuid references public.pessoas(id),
  erro_detalhe   text,
  criado_em      timestamptz not null default now(),
  criado_por     uuid references public.pessoas(id),
  atualizado_em  timestamptz not null default now(),
  constraint documentos_competencia_ck check (
    competencia is null or competencia = date_trunc('month', competencia::timestamp)::date),
  constraint documentos_publicacao_ck check (
    status <> 'publicado' or (publicado_em is not null and publicado_por is not null))
);

create index documentos_tipo_data_idx     on public.documentos (tipo, data_documento desc);
create index documentos_competencia_idx   on public.documentos (competencia desc) where competencia is not null;
create index documentos_status_idx        on public.documentos (status);
-- Índice que a RLS percorre (ADR-0012: policy sem índice vira varredura por linha):
create index documentos_visibilidade_idx  on public.documentos (visibilidade, status);
create index documentos_mistos_idx        on public.documentos (id) where tem_paginas_mistas;
create index documentos_ano_idx           on public.documentos ((extract(year from coalesce(competencia, data_documento))));
create index documentos_titulo_trgm_idx   on public.documentos using gin (titulo extensions.gin_trgm_ops);
create index documentos_metadados_idx     on public.documentos using gin (metadados jsonb_path_ops);

-- Trigger de visibilidade: 'publico' só para tipo com permite_publico.
-- Não pode ser CHECK (CHECK não faz subconsulta), e não pode ficar só na aplicação:
-- publicar ata como pública é vazamento de nome, unidade e às vezes CPF (SPEC §7).
-- Note: isto valida `documentos.visibilidade` (o nível PADRÃO/whole-document). Uma página
-- individual pode ser 'publico' via override mesmo num documento não-publico (ex.: o regimento
-- embutido numa ata) — esse override vive em documento_paginas e é papel de curadoria humana,
-- não desta trigger.
create or replace function public.tg_documentos_valida_visibilidade()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.visibilidade = 'publico'
     and not exists (select 1 from public.tipos_documento t
                      where t.codigo = new.tipo and t.permite_publico) then
    raise exception
      'Tipo de documento % não pode ter visibilidade pública (Briefing §7.1, SPEC §7)', new.tipo;
  end if;
  return new;
end $$;
create trigger documentos_valida_visibilidade
  before insert or update of visibilidade, tipo on public.documentos
  for each row execute function public.tg_documentos_valida_visibilidade();

comment on table public.documentos is
  'RLS: TODA leitura passa por app.documento_visivel(id) (linha/arquivo inteiro) ou por '
  'app.pagina_visivel(id, pagina) (conteúdo por página, ver documento_paginas/chunks). Escrita '
  'só editor. documento_unidades, documento_paginas, chunks, deliberacoes e storage.objects '
  'espelham esta regra CHAMANDO AS MESMAS FUNÇÕES — nunca copiando o predicado (SPEC §7, '
  'armadilha nº1).';
comment on column public.documentos.tem_paginas_mistas is
  'Sinalizador de curadoria (ADR-0023/D16), NUNCA fonte de decisão de segurança — o conceito de '
  '"documento misto" foi removido de app.nivel_efetivo() por não-localidade (era um exists sobre '
  'outras páginas; vazou na 3ª rodada do auditor-rls). Liga sozinha por trigger ao primeiro '
  'override; nunca desliga sozinha. A editora pode ligá-la antes, para declarar intenção.';

-- ============================================================================
-- documento_unidades — [ADR-0016 item 7]
-- ============================================================================
-- Sem esta tabela, visibilidade 'restrito' não é avaliável e vira sinônimo de 'conselho'.
create table public.documento_unidades (
  documento_id uuid not null references public.documentos(id) on delete cascade,
  unidade_id   uuid not null references public.unidades(id)   on delete restrict,
  criado_em    timestamptz not null default now(),
  primary key (documento_id, unidade_id)
);
create index documento_unidades_unidade_idx on public.documento_unidades (unidade_id);

comment on table public.documento_unidades is
  'RLS: leitura para gestão e para a própria unidade; escrita só editor. '
  'Por quê: é o predicado que torna visibilidade=restrito implementável. A própria existência da '
  'linha é informação ("a unidade 302 foi notificada"), então a leitura é restrita do mesmo jeito.';

-- ============================================================================
-- documento_paginas — espelha `documentos` (com override por página desde 2026-09-04)
-- ============================================================================
create table public.documento_paginas (
  id            uuid primary key default extensions.gen_random_uuid(),
  documento_id  uuid not null references public.documentos(id) on delete cascade,
  pagina        int not null check (pagina > 0),
  texto         text,          -- texto EFETIVO (nativo ou OCR) — é dele que saem os chunks
  texto_nativo  text,          -- o que a extração nativa achou; preservado p/ diagnóstico (ADR-0006)
  fonte_texto   text not null default 'nativo'
                check (fonte_texto in ('nativo','ocr','misto','vazio')),
  confianca_ocr numeric(4,3) check (confianca_ocr between 0 and 1),  -- não é dinheiro
  rotacao       int check (rotacao in (0,90,180,270)),
  -- [Correção 2026-09-04] NULL = herda documentos.visibilidade. Preenchida = sobrescreve para
  -- ESTA página (ex.: páginas do regimento embutido numa ata ganham 'publico' aqui, mesmo com a
  -- ata em 'autenticado'). Resolução de herança inteira em app.nivel_efetivo() — nunca reescrita
  -- em policy.
  visibilidade  public.visibilidade_documento,
  versao_pipeline int not null default 1,
  criado_em     timestamptz not null default now(),
  constraint documento_paginas_uk unique (documento_id, pagina)
);
create index documento_paginas_documento_idx on public.documento_paginas (documento_id);

comment on table public.documento_paginas is
  'RLS: ESPELHA documentos via app.pagina_visivel(documento_id, pagina) — resolve herança/override '
  'de visibilidade por página (correção 2026-09-04). '
  'Por quê: ARMADILHA Nº1 (SPEC §7, §8.1). Esta tabela contém o texto integral do documento; RLS '
  'em documentos sem RLS aqui entrega o conteúdo restrito inteiro por uma consulta trivial. '
  'Escrita: NENHUM papel de usuário. Só o worker, por service_role — é saída de máquina.';
comment on column public.documento_paginas.visibilidade is
  'Override por página. NULL = herda de documentos.visibilidade — SEMPRE (app.nivel_efetivo é '
  '`coalesce(documento_paginas.visibilidade, documentos.visibilidade)`, puramente local desde '
  'ADR-0023/D16; não existe mais "documento misto" nem exceção de fail-closed por página não '
  'classificada — essa exceção dependia de outras páginas do mesmo documento e foi o que vazou '
  'na 3ª rodada do auditor-rls). '
  'PISO (ADR-0019/D13): quando preenchida, só pode ser IGUAL OU MAIS PERMISSIVA que '
  'documentos.visibilidade (app.ordem_visibilidade) — nunca mais restritiva. Validado nos DOIS '
  'lados: documento_paginas_valida_piso (página) e documentos_valida_piso_paginas (documento, '
  'V3-R) — os dois DÃO ERRO, nunca sobrescrevem em silêncio. Com este piso garantido dos dois '
  'lados, herdar o padrão do documento para página sem override é seguro por construção — '
  'nenhuma página pode exigir mais do que o arquivo já exige de quem o baixou.';

-- ============================================================================
-- chunks — espelha `documentos` — o ponto mais crítico do schema
-- ============================================================================
create table public.chunks (
  id            uuid primary key default extensions.gen_random_uuid(),
  documento_id  uuid not null references public.documentos(id) on delete cascade,
  pagina_ini    int not null check (pagina_ini > 0),
  pagina_fim    int not null,
  ordem         int not null check (ordem >= 0),
  texto         text not null,
  tokens        int,
  -- Coluna gerada: exige to_tsvector de DOIS argumentos com config qualificada (ADR-0005).
  tsv           tsvector generated always as (to_tsvector('public.pt_br', texto)) stored,
  embedding     extensions.vector(1536),
  versao_pipeline int not null default 1,
  criado_em     timestamptz not null default now(),
  constraint chunks_paginas_ck check (pagina_fim >= pagina_ini),
  constraint chunks_uk unique (documento_id, versao_pipeline, ordem)
);

create index chunks_tsv_idx        on public.chunks using gin (tsv);
create index chunks_documento_idx  on public.chunks (documento_id);
create index chunks_texto_trgm_idx on public.chunks using gin (texto extensions.gin_trgm_ops);
-- HNSW SÓ ACIMA DE ~10k LINHAS (ADR-0005). Abaixo disso, varredura é mais rápida e mais exata.
-- Fica comentado na baseline; vira migração própria quando o acervo justificar:
-- create index chunks_embedding_idx on public.chunks
--   using hnsw (embedding extensions.vector_cosine_ops) with (m = 16, ef_construction = 64);

comment on table public.chunks is
  'RLS: ESPELHA documentos via app.pagina_visivel(documento_id, pagina_ini) — a página inicial do '
  'trecho é a âncora de visibilidade (correção 2026-09-04: chunk não pode cruzar fronteira de '
  'visibilidade num documento misto — ver trigger chunks_valida_visibilidade_uniforme em '
  '20260904120800_visibilidade_documento_funcoes.sql). '
  'Por quê: ESTA É A ARMADILHA Nº1 (SPEC §7, §8.1). A busca lê chunks. RLS em documentos sem RLS '
  'aqui faz o motor de busca vazar trecho de documento restrito para qualquer morador — e vaza '
  'pela funcionalidade central do produto, com o texto já destacado. '
  'A policy DEVE chamar app.pagina_visivel(), nunca reescrever o predicado. '
  'Escrita: nenhum papel de usuário; só o worker via service_role.';
comment on column public.chunks.pagina_ini is
  'A citação depende disto (SPEC §3.4, §6.2): resultado de busca leva a "abrir na página X". '
  'Também é a âncora de visibilidade do chunk desde a correção de 2026-09-04.';

-- ============================================================================
-- RLS — enable + force + revoke/grant, sem policy ainda (policies dependem de
-- app.documento_visivel/app.pagina_visivel, criadas em 20260904120800 depois de
-- 20260904120700_tipos_documento_seed.sql). Ver 20260904120900_acervo_rls.sql.
-- ============================================================================

alter table public.tipos_documento enable row level security;
alter table public.tipos_documento force row level security;
revoke all on public.tipos_documento from public, anon, authenticated, service_role;
grant select on public.tipos_documento to anon, authenticated;
grant insert, update, delete on public.tipos_documento to authenticated;

alter table public.documentos enable row level security;
alter table public.documentos force row level security;
revoke all on public.documentos from public, anon, authenticated, service_role;
grant select on public.documentos to anon, authenticated;
grant insert, update on public.documentos to authenticated; -- delete: ninguém (arquivar por status)
-- V4: o worker atualiza status/metadados/ocr_aplicado/paginas/erro_detalhe/versao_pipeline
-- conforme processa — a linha em si nasce pelo editor (authenticated), o pipeline só evolui o
-- estado. Sem INSERT/DELETE: criação e arquivamento continuam humanos.
grant select, update on public.documentos to service_role;

alter table public.documento_unidades enable row level security;
alter table public.documento_unidades force row level security;
revoke all on public.documento_unidades from public, anon, authenticated, service_role;
grant select on public.documento_unidades to authenticated;
grant insert, update, delete on public.documento_unidades to authenticated;

alter table public.documento_paginas enable row level security;
alter table public.documento_paginas force row level security;
revoke all on public.documento_paginas from public, anon, authenticated, service_role;
grant select on public.documento_paginas to anon, authenticated;
-- V4: esta é literalmente a tabela do worker (declarado no comentário da própria tabela: "Só o
-- worker, por service_role — é saída de máquina"). Sem este GRANT explícito, o worker não tinha
-- NENHUM DML aqui e o pipeline de ingestão era inoperável como desenhado.
grant select, insert, update, delete on public.documento_paginas to service_role;

alter table public.chunks enable row level security;
alter table public.chunks force row level security;
revoke all on public.chunks from public, anon, authenticated, service_role;
grant select on public.chunks to anon, authenticated;
-- V4: mesma razão de documento_paginas — reprocessamento idempotente (SPEC §3) substitui chunks.
grant select, insert, update, delete on public.chunks to service_role;
