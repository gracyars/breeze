-- Breeze — baseline 19: fila de processamento — schema job (ADR-0007). Fonte: docs/schema.md §11.

create table job.fila (
  id                 bigint generated always as identity primary key,
  tipo               text not null,           -- 'ingestao_documento','ocr_pagina','embedding_lote',...
  payload            jsonb not null,
  status             public.status_job not null default 'pendente',
  prioridade         int not null default 100,
  tentativas         int not null default 0,
  max_tentativas     int not null default 5,
  disponivel_em      timestamptz not null default now(),   -- backoff exponencial
  iniciado_em        timestamptz,                          -- lease: recupera worker morto
  concluido_em       timestamptz,
  erro               text,
  -- SPEC §3: "job re-executável por sha256 + versão do pipeline"
  chave_idempotencia text unique,
  criado_em          timestamptz not null default now()
);
create index fila_pronto_idx on job.fila (prioridade, disponivel_em)
  where status = 'pendente';
create index fila_travado_idx on job.fila (iniciado_em)
  where status = 'processando';   -- varredura de lease expirado

comment on table job.fila is
  'RLS: irrelevante — schema fora do PostgREST, sem GRANT a papel de usuário (verificado: '
  '"job" não está em api.schemas no config.toml). '
  'Por quê: o payload carrega caminho de storage e identificadores; não é dado de usuário e '
  'nenhuma tela precisa dele. Vigilância obrigatória: job "processando" com iniciado_em antigo '
  'volta a pendente, senão um crash de worker engole o documento em silêncio (ADR-0007).';

-- Defesa em profundidade: RLS habilitada mesmo sem exposição via PostgREST (o schema "job" já
-- não tem USAGE para anon/authenticated desde 20260904120000). Consumo real é
-- SELECT ... FOR UPDATE SKIP LOCKED com a credencial própria do worker (não authenticated/anon).
alter table job.fila enable row level security;
alter table job.fila force row level security;
revoke all on job.fila from public, anon, authenticated;
-- Sem GRANT, sem policy: mesmo que o schema algum dia entrasse em exposed_schemas por engano,
-- esta tabela continuaria inacessível a anon/authenticated.
