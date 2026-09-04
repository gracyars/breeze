-- Breeze — baseline 00: extensões, schemas e higiene de privilégio.
-- Fonte: docs/schema.md §1; ADR-0008 (migração versionada), ADR-0012 (RLS como fronteira única).
--
-- A ausência de qualquer extensão abaixo deve quebrar a migração cedo e alto: nenhuma delas tem
-- fallback silencioso aceitável neste schema (busca híbrida, embedding, CPF via hash/cifra e
-- exclusão de período dependem delas).

create extension if not exists pgcrypto   with schema extensions; -- gen_random_uuid, digest, hmac
create extension if not exists vector     with schema extensions; -- pgvector (ADR-0005)
create extension if not exists unaccent   with schema extensions; -- config pt_br (ADR-0005)
create extension if not exists pg_trgm    with schema extensions; -- erro de digitação em nome próprio
create extension if not exists btree_gist with schema extensions; -- exclusão de período sobreposto

-- pgtap NÃO entra aqui: é habilitado em migração própria, sinalizada como local/CI apenas
-- (ver 20260904122300_pgtap_test_only.sql). Nunca na baseline de produção.

-- Schemas auxiliares. NENHUM dos três entra em db.exposed_schemas do config.toml — verificado
-- separadamente (supabase/config.toml já lista só ["public", "graphql_public"]).
create schema if not exists app;    -- funções auxiliares de autorização (ADR-0012)
create schema if not exists audit;  -- trilha imutável (ADR-0013)
create schema if not exists job;    -- fila de processamento (ADR-0007)

revoke all on schema app, audit, job from public, anon, authenticated;
grant usage on schema app to authenticated;  -- só USAGE; EXECUTE é concedido função a função
grant usage on schema app to anon;           -- documento público precisa ser avaliável sem login

comment on schema app is
  'Fonte única de predicado de autorização (ADR-0012). Toda função aqui é security definer, '
  'stable, com search_path fixo. Nenhuma policy reescreve um predicado que já exista aqui — '
  'predicado copiado é a armadilha nº1 do projeto (SPEC §7).';
comment on schema audit is
  'Trilha imutável (ADR-0013): audit.log encadeado por hash, permanente; audit.acesso sem '
  'encadeamento, expurgável em 6 meses. Fora do PostgREST — nunca em db.exposed_schemas.';
comment on schema job is
  'Fila de processamento (ADR-0007). Fora do PostgREST. Consumida por worker com credencial '
  'própria via SELECT ... FOR UPDATE SKIP LOCKED.';

-- Higiene de privilégio — roda aqui e é reafirmada (por tabela) em toda migração que cria tabela.
-- Nada é acessível por padrão; cada GRANT é explícito, por tabela e por operação.
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke all on functions from anon, authenticated;
revoke all on all tables in schema public from anon, authenticated;
