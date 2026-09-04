-- Breeze — baseline 21: Storage (ADR-0004). Fonte: docs/schema.md §13.
--
-- Buckets criados aqui via storage.buckets — reproduzível do zero, sem passo manual no
-- dashboard (a mesma regra de "schema nunca editado pelo dashboard" vale para bucket).

insert into storage.buckets (id, name, public, file_size_limit)
values
  ('documentos',         'documentos',         false, 52428800),  -- 50MiB
  ('anexos-financeiros', 'anexos-financeiros',  false, 52428800),  -- bucket SEPARADO (SPEC §7)
  ('publicos',           'publicos',            true,  52428800)  -- SOMENTE convenção e regimento
on conflict (id) do nothing;

-- ============================================================================
-- RLS em storage.objects. insert/update/delete: NENHUM papel de usuário em nenhum bucket — todo
-- upload é por signed upload URL emitida no servidor, DEPOIS de checar papel (service_role
-- bypassa RLS por construção; é essa checagem prévia no servidor que é a barreira real).
-- A RLS aqui é a SEGUNDA camada, para acesso direto de leitura com o JWT do usuário.
-- ============================================================================

-- bucket 'documentos': PDF cru, gate pelo nível do DOCUMENTO (app.documento_visivel) — o arquivo
-- não é fatiado por página (ver 20260904120800 para a distinção com app.pagina_visivel).
create policy storage_documentos_select on storage.objects
  for select to anon, authenticated
  using (
    bucket_id = 'documentos'
    and exists (
      select 1 from public.documentos d
       where d.storage_path = storage.objects.name
         and app.documento_visivel(d.id)
    )
  );

-- bucket 'anexos-financeiros': só gestão, nunca anon nem morador (SPEC §7 — comprovante fiscal
-- é o material mais sensível do financeiro).
create policy storage_anexos_financeiros_select on storage.objects
  for select to authenticated
  using ( bucket_id = 'anexos-financeiros' and app.eh_gestao() );

-- bucket 'publicos': convenção e regimento, sem login.
create policy storage_publicos_select on storage.objects
  for select to anon, authenticated
  using ( bucket_id = 'publicos' );
