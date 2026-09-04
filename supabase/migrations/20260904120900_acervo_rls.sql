-- Breeze — baseline 09: policies de RLS para tipos_documento, documentos, documento_unidades,
-- documento_paginas, chunks. Fonte: docs/schema.md §6, matriz §15; correção 2026-09-04
-- (visibilidade por página) em 20260904120800_visibilidade_documento_funcoes.sql.

-- ============================================================================
-- tipos_documento — leitura livre (inclusive anon); escrita editor
-- ============================================================================
create policy tipos_documento_select on public.tipos_documento
  for select to anon, authenticated
  using ( true );

create policy tipos_documento_insert on public.tipos_documento
  for insert to authenticated
  with check ( app.eh_editor() );

create policy tipos_documento_update on public.tipos_documento
  for update to authenticated
  using ( app.eh_editor() )
  with check ( app.eh_editor() );

create policy tipos_documento_delete on public.tipos_documento
  for delete to authenticated
  using ( app.eh_editor() );

-- ============================================================================
-- documentos — select via app.documento_visivel(id); escrita editor; delete ninguém
-- ============================================================================
create policy documentos_select on public.documentos
  for select to anon, authenticated
  using ( app.documento_visivel(id) );

create policy documentos_insert on public.documentos
  for insert to authenticated
  with check ( app.eh_editor() );

create policy documentos_update on public.documentos
  for update to authenticated
  using ( app.eh_editor() )
  with check ( app.eh_editor() );

-- ============================================================================
-- documento_unidades — select: própria unidade OU gestão; escrita editor
-- ============================================================================
create policy documento_unidades_select on public.documento_unidades
  for select to authenticated
  using ( app.eh_gestao() or unidade_id in (select app.unidades_da_pessoa()) );

create policy documento_unidades_insert on public.documento_unidades
  for insert to authenticated
  with check ( app.eh_editor() );

create policy documento_unidades_update on public.documento_unidades
  for update to authenticated
  using ( app.eh_editor() )
  with check ( app.eh_editor() );

create policy documento_unidades_delete on public.documento_unidades
  for delete to authenticated
  using ( app.eh_editor() );

-- ============================================================================
-- documento_paginas — ESPELHA documentos via app.pagina_visivel(documento_id, pagina).
-- Escrita: nenhuma policy — worker grava via service_role (bypassa RLS por construção).
-- ============================================================================
create policy documento_paginas_select on public.documento_paginas
  for select to anon, authenticated
  using ( app.pagina_visivel(documento_id, pagina) );

-- ============================================================================
-- chunks — ESPELHA documentos via app.pagina_visivel(documento_id, pagina_ini).
-- Escrita: nenhuma policy — worker grava via service_role.
-- ============================================================================
create policy chunks_select on public.chunks
  for select to anon, authenticated
  using ( app.pagina_visivel(documento_id, pagina_ini) );
