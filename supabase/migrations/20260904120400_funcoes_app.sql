-- Breeze — baseline 04: funções auxiliares de autorização (schema app).
-- Fonte: docs/schema.md §4; ADR-0012. Fonte ÚNICA de toda regra de acesso.
-- Todas security definer, stable, com search_path fixo e referências qualificadas —
-- security definer sem search_path é escalada de privilégio.

-- Pessoa correspondente à sessão atual. NULL para anônimo.
create or replace function app.pessoa_atual()
returns uuid language sql stable security definer set search_path = '' as $$
  select p.id from public.pessoas p
   where p.auth_user_id = auth.uid() and p.ativa
$$;

-- PRIMITIVA de RLS. Papel vale se: mandato vigente E, para editor/conselho, sessão em AAL2.
-- Papel é DADO (tabela papeis), não claim do JWT: mandato que termina hoje deixa de valer hoje.
create or replace function app.tem_papel(p public.papel)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
      from public.papeis pa
      join public.pessoas pe on pe.id = pa.pessoa_id
     where pe.auth_user_id = auth.uid()
       and pe.ativa
       and pa.papel = p
       and pa.mandato_inicio <= current_date
       and (pa.mandato_fim is null or pa.mandato_fim >= current_date)
       -- TOTP obrigatório para papel privilegiado (ADR-0003 item 5):
       and ( p = 'morador'
             or coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2' )
  )
$$;

create or replace function app.eh_editor() returns boolean
  language sql stable as $$ select app.tem_papel('editor') $$;

create or replace function app.eh_gestao() returns boolean  -- conselho OU editor
  language sql stable as $$ select app.tem_papel('conselho') or app.tem_papel('editor') $$;

create or replace function app.eh_autenticado() returns boolean
  language sql stable as $$ select app.pessoa_atual() is not null $$;

-- Papel mais forte vigente. Para UI e para o SPEC §7 ("helper papel_atual").
-- NÃO é a primitiva de RLS — policy usa tem_papel/eh_gestao.
create or replace function app.papel_atual()
returns public.papel language sql stable as $$
  select case when app.tem_papel('editor')   then 'editor'::public.papel
              when app.tem_papel('conselho') then 'conselho'::public.papel
              when app.tem_papel('morador')  then 'morador'::public.papel
         end
$$;

-- Unidades da pessoa logada, por vínculo vigente.
create or replace function app.unidades_da_pessoa()
returns setof uuid language sql stable security definer set search_path = '' as $$
  select v.unidade_id
    from public.vinculos v
   where v.pessoa_id = app.pessoa_atual()
     and v.inicio <= current_date
     and (v.fim is null or v.fim >= current_date)
$$;

revoke all on all functions in schema app from public, anon, authenticated;
grant execute on function
  app.pessoa_atual(), app.tem_papel(public.papel), app.eh_editor(), app.eh_gestao(),
  app.eh_autenticado(), app.papel_atual(), app.unidades_da_pessoa()
to authenticated;
-- eh_gestao/eh_autenticado também precisam valer para anon (documento público sem login usa
-- app.documento_visivel()/app.pagina_visivel(), que chamam estas duas internamente).
grant execute on function app.eh_gestao(), app.eh_autenticado() to anon;

comment on function app.tem_papel(public.papel) is
  'PRIMITIVA de RLS. Nenhuma policy verifica papel de outro jeito — nem por app_metadata, nem '
  'reescrevendo este predicado (ADR-0012).';
