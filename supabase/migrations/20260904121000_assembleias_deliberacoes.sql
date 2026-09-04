-- Breeze — baseline 10: assembleias e deliberações. Fonte: docs/schema.md §7; ADR-0016 item 1.

-- ============================================================================
-- assembleias
-- ============================================================================
create table public.assembleias (
  id                  uuid primary key default extensions.gen_random_uuid(),
  tipo                public.tipo_assembleia not null,
  data                date not null,
  ata_documento_id    uuid references public.documentos(id) on delete restrict,
  edital_documento_id uuid references public.documentos(id) on delete restrict,
  quorum_presente     numeric(6,4) check (quorum_presente between 0 and 1),  -- fração, não dinheiro
  local               text,
  criado_em           timestamptz not null default now(),
  criado_por          uuid references public.pessoas(id)
);
create index assembleias_data_idx on public.assembleias (data desc);

comment on table public.assembleias is
  'RLS: leitura para autenticado; escrita só editor. '
  'Por quê: a existência e a data da assembleia são informação de convivência, não dado pessoal. '
  'O conteúdo sensível está na ATA, e a ata é um documento com sua própria visibilidade.';

alter table public.assembleias enable row level security;
alter table public.assembleias force row level security;
revoke all on public.assembleias from public, anon, authenticated;
grant select on public.assembleias to authenticated;
grant insert, update, delete on public.assembleias to authenticated;

create policy assembleias_select on public.assembleias
  for select to authenticated
  using ( app.eh_autenticado() );

create policy assembleias_insert on public.assembleias
  for insert to authenticated
  with check ( app.eh_editor() );

create policy assembleias_update on public.assembleias
  for update to authenticated
  using ( app.eh_editor() )
  with check ( app.eh_editor() );

create policy assembleias_delete on public.assembleias
  for delete to authenticated
  using ( app.eh_editor() );

-- ============================================================================
-- deliberacoes — [ADR-0016 item 1]: âncora de citação estável (documento_id, pagina,
-- trecho_literal); chunk_id é ponteiro FRACO, on delete set null.
-- ============================================================================
create table public.deliberacoes (
  id             uuid primary key default extensions.gen_random_uuid(),
  assembleia_id  uuid not null references public.assembleias(id) on delete cascade,
  item           int not null check (item > 0),
  descricao      text not null,
  resultado      text not null check (resultado in ('aprovado','rejeitado','adiado','retirado')),
  votos_favor    int check (votos_favor >= 0),
  votos_contra   int check (votos_contra >= 0),
  abstencoes     int check (abstencoes >= 0),
  valor_autorizado_centavos bigint check (valor_autorizado_centavos >= 0),  -- ADR-0010

  -- ÂNCORA DE CITAÇÃO [ADR-0016 item 1]: estável, sobrevive a reprocessamento.
  documento_id   uuid references public.documentos(id) on delete restrict,
  pagina         int check (pagina > 0),
  trecho_literal text,   -- snapshot do texto citado, imune a rechunking

  -- Ponteiro FRACO para o chunk. Reprocessar o pipeline regenera chunks e ANULA esta coluna;
  -- a citação continua íntegra por documento_id + pagina + trecho_literal.
  chunk_id       uuid references public.chunks(id) on delete set null,

  criado_em      timestamptz not null default now(),
  criado_por     uuid references public.pessoas(id),
  constraint deliberacoes_uk unique (assembleia_id, item)
);
create index deliberacoes_documento_idx on public.deliberacoes (documento_id);

comment on table public.deliberacoes is
  'RLS: select via app.pagina_visivel(documento_id, pagina) quando pagina is not null; '
  'app.documento_visivel(documento_id) quando há documento mas não página específica; '
  'autenticado quando documento_id is null. Escrita só editor. '
  'Por quê: a deliberação carrega trecho literal da ata — se a página citada é restrita/mista, o '
  'trecho segue a MESMA regra de app.pagina_visivel (correção 2026-09-04) — nunca reescrita.';
comment on column public.deliberacoes.chunk_id is
  '[ADR-0016 item 1] SPEC §2 ancorava a citação em chunk_id. Chunk é derivado e volátil: SPEC §3 '
  'exige reprocessamento idempotente, que regenera a segmentação. Âncora estável = '
  '(documento_id, pagina) + trecho_literal. chunk_id vira otimização reconstruível, on delete set '
  'null.';

alter table public.deliberacoes enable row level security;
alter table public.deliberacoes force row level security;
revoke all on public.deliberacoes from public, anon, authenticated;
grant select on public.deliberacoes to authenticated;
grant insert, update, delete on public.deliberacoes to authenticated;

create policy deliberacoes_select on public.deliberacoes
  for select to authenticated
  using (
    (documento_id is null and app.eh_autenticado())
    or (documento_id is not null and pagina is not null and app.pagina_visivel(documento_id, pagina))
    or (documento_id is not null and pagina is null and app.documento_visivel(documento_id))
  );

create policy deliberacoes_insert on public.deliberacoes
  for insert to authenticated
  with check ( app.eh_editor() );

create policy deliberacoes_update on public.deliberacoes
  for update to authenticated
  using ( app.eh_editor() )
  with check ( app.eh_editor() );

create policy deliberacoes_delete on public.deliberacoes
  for delete to authenticated
  using ( app.eh_editor() );
