-- Breeze — baseline 17: busca e configuração — sinonimos, configuracoes.
-- Fonte: docs/schema.md §10; SPEC §4, §5.3.

-- ============================================================================
-- sinonimos
-- ============================================================================
create table public.sinonimos (
  id         uuid primary key default extensions.gen_random_uuid(),
  termo      text not null,
  termo_normalizado text generated always as (lower(public.unaccent_imutavel(termo))) stored,
  expansoes  text[] not null check (cardinality(expansoes) > 0),
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now()
);
create unique index sinonimos_normalizado_uk on public.sinonimos (termo_normalizado);

comment on table public.sinonimos is
  'RLS: leitura para todos (inclusive anon — a busca pública em convenção/regimento precisa); '
  'escrita só editor. Sem PII. Expansão de sinônimo acontece NA APLICAÇÃO (SPEC §4): Supabase '
  'gerenciado não dá acesso a $SHAREDIR para dicionário synonym/thesaurus.';

alter table public.sinonimos enable row level security;
alter table public.sinonimos force row level security;
revoke all on public.sinonimos from public, anon, authenticated;
grant select on public.sinonimos to anon, authenticated;
grant insert, update, delete on public.sinonimos to authenticated;

create policy sinonimos_select on public.sinonimos
  for select to anon, authenticated using ( true );
create policy sinonimos_insert on public.sinonimos
  for insert to authenticated with check ( app.eh_editor() );
create policy sinonimos_update on public.sinonimos
  for update to authenticated using ( app.eh_editor() ) with check ( app.eh_editor() );
create policy sinonimos_delete on public.sinonimos
  for delete to authenticated using ( app.eh_editor() );

-- ============================================================================
-- configuracoes — limiares e parâmetros vivem em tabela, nunca em código (SPEC §5.3)
-- ============================================================================
create table public.configuracoes (
  chave         text primary key,
  valor         jsonb not null,
  descricao     text,
  publica       boolean not null default false,  -- se a UI do morador (autenticado) pode ler
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid references public.pessoas(id)
);

comment on table public.configuracoes is
  'RLS: linha com publica=true: autenticado (NUNCA anon — matriz §15); demais: SÓ gestão. '
  'Escrita só editor. '
  'Por quê: limiar de alerta é informação de fiscalização — saber que a cotação só é exigida '
  'acima de R$5.000 é convite a fracionar em R$4.999 (que é justamente o alerta "fracionamento '
  'suspeito"). Toda alteração é auditada.';

alter table public.configuracoes enable row level security;
alter table public.configuracoes force row level security;
revoke all on public.configuracoes from public, anon, authenticated;
grant select on public.configuracoes to authenticated; -- NUNCA anon, nem para linha publica=true
grant insert, update, delete on public.configuracoes to authenticated;

create policy configuracoes_select on public.configuracoes
  for select to authenticated
  using ( (publica and app.eh_autenticado()) or app.eh_gestao() );
create policy configuracoes_insert on public.configuracoes
  for insert to authenticated with check ( app.eh_editor() );
create policy configuracoes_update on public.configuracoes
  for update to authenticated using ( app.eh_editor() ) with check ( app.eh_editor() );
create policy configuracoes_delete on public.configuracoes
  for delete to authenticated using ( app.eh_editor() );
