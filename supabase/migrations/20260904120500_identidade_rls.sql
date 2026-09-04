-- Breeze — baseline 05: policies de RLS para unidades, pessoas, vinculos, papeis.
-- Tabelas e RLS habilitada/forçada em 20260904120300; funções app.* em 20260904120400.
-- Fonte: docs/schema.md §5, matriz §15.

-- ============================================================================
-- unidades — leitura: autenticado; escrita: editor
-- ============================================================================
create policy unidades_select on public.unidades
  for select to authenticated
  using ( app.eh_autenticado() );

create policy unidades_insert on public.unidades
  for insert to authenticated
  with check ( app.eh_editor() );

create policy unidades_update on public.unidades
  for update to authenticated
  using ( app.eh_editor() )
  with check ( app.eh_editor() );

create policy unidades_delete on public.unidades
  for delete to authenticated
  using ( app.eh_editor() );

-- ============================================================================
-- pessoas — select: própria linha OU gestão; insert/update: editor; delete: ninguém
-- ============================================================================
create policy pessoas_select on public.pessoas
  for select to authenticated
  using ( id = app.pessoa_atual() or app.eh_gestao() );

create policy pessoas_insert on public.pessoas
  for insert to authenticated
  with check ( app.eh_editor() );

create policy pessoas_update on public.pessoas
  for update to authenticated
  using ( app.eh_editor() )
  with check ( app.eh_editor() );

-- Sem policy de delete: anonimização é UPDATE (SPEC §7), nunca DELETE.

-- ============================================================================
-- vinculos — select: própria unidade OU gestão; escrita: editor
-- ============================================================================
create policy vinculos_select on public.vinculos
  for select to authenticated
  using ( unidade_id in (select app.unidades_da_pessoa()) or app.eh_gestao() );

create policy vinculos_insert on public.vinculos
  for insert to authenticated
  with check ( app.eh_editor() );

create policy vinculos_update on public.vinculos
  for update to authenticated
  using ( app.eh_editor() )
  with check ( app.eh_editor() );

create policy vinculos_delete on public.vinculos
  for delete to authenticated
  using ( app.eh_editor() );

-- ============================================================================
-- papeis — select: próprios OU gestão; insert/update: editor (AAL2 já exigido dentro de
-- tem_papel/eh_editor); delete: ninguém (mandato_fim, nunca apagar linha)
-- ============================================================================
create policy papeis_select on public.papeis
  for select to authenticated
  using ( pessoa_id = app.pessoa_atual() or app.eh_gestao() );

create policy papeis_insert on public.papeis
  for insert to authenticated
  with check ( app.eh_editor() );

create policy papeis_update on public.papeis
  for update to authenticated
  using ( app.eh_editor() )
  with check ( app.eh_editor() );
