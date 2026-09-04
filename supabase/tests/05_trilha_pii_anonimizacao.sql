-- ============================================================================
-- Breeze — auditoria: PII denormalizada na trilha vs. anonimizacao (LGPD art. 16/18).
-- A trilha e imutavel e encadeada por hash: o que entra aqui nao sai depois. Logo, o que ela
-- guarda tem de ser decidido ANTES de a baseline ir a producao.
-- O MECANISMO (redigir coluna, pseudonimizar, ou gravar so o diff de colunas nao-PII) e decisao
-- de eng-supabase + juridico-lgpd. Este arquivo trava a INVARIANTE, nao o mecanismo.
--
-- Cada arquivo e auto-contido: abre `begin`, cria a propria fixture, roda os asserts e fecha em
-- `rollback` — nada fica no banco.
-- ============================================================================
begin;
select plan(8);

-- ---------------------------------------------------------------- fixture --
-- Marca o topo da cadeia ANTES da fixture: os asserts abaixo olham so as linhas que ESTE teste
-- produziu, nunca o historico ja existente no banco (senao o resultado depende da ordem de
-- execucao e o teste mente).
create temp table _base on commit drop as select coalesce(max(seq),0) as seq from audit.log;

insert into auth.users (id,instance_id,aud,role,email,created_at,updated_at) values
 ('00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','pii-ana@t.local',now(),now());
insert into public.unidades (id,bloco,numero,fracao_ideal) values
 ('10000000-0000-0000-0000-000000000101','','P101',1.0);
insert into public.pessoas (id,auth_user_id,nome,email,telefone,observacoes,cpf_hash,cpf_enc,cpf_ultimos_digitos) values
 ('20000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000a1',
  'Ana Maria da Silva','ana.silva@exemplo.com','+5511999998888',
  'Mudou-se em 2026; pendencia de taxa', decode(repeat('a1',32),'hex'),'\xDEAD'::bytea,'789');

-- ======================================================================
-- A. Forma do identificador do ator (a pergunta direta)
-- ======================================================================
select is( (select data_type from information_schema.columns
             where table_schema='audit' and table_name='log' and column_name='actor_pessoa_id'),
  'uuid', 'A1 audit.log.actor_pessoa_id e uuid, nao nome denormalizado');
select is( (select data_type from information_schema.columns
             where table_schema='audit' and table_name='log' and column_name='actor_uid'),
  'uuid', 'A2 audit.log.actor_uid e uuid (referencia auth.users), nao nome');
select is( (select data_type from information_schema.columns
             where table_schema='audit' and table_name='acesso' and column_name='actor_pessoa_id'),
  'uuid', 'A3 audit.acesso.actor_pessoa_id e uuid, nao nome');
-- actor_papel e text mas nao e PII: guarda o VALOR DO ENUM public.papel, nao identidade.
select ok( (select actor_papel from audit.log order by seq desc limit 1) is null
        or (select actor_papel from audit.log order by seq desc limit 1)
             in ('editor','conselho','morador'),
  'A4 audit.log.actor_papel so contem valor do enum public.papel, nunca identidade');

-- ======================================================================
-- B. PII denormalizada no SNAPSHOT — o ponto que a anonimizacao nao alcanca
-- ======================================================================
-- fn_registrar grava to_jsonb(NEW)/to_jsonb(OLD) inteiro e redige SO cpf_enc. Todo o resto do
-- cadastro pessoal entra em claro, permanente e encadeado. Anonimizar `pessoas` depois nao
-- alcanca estas linhas, e corrigi-las quebra a cadeia — a escolha e irreversivel por construcao.
select is(
  (select coalesce(string_agg(k,',' order by k),'(nenhuma)')
     from audit.log l, lateral (select unnest(array['nome','email','telefone','observacoes','cpf_ultimos_digitos']) k) c
    where l.seq > (select seq from _base) and l.tabela='pessoas' and l.depois ? c.k
      and l.depois->>c.k is not null and l.depois->>c.k <> '[redigido]'),
  '(nenhuma)',
  'B1 o snapshot de pessoas na trilha nao guarda nome/email/telefone/observacoes/cpf_ultimos_digitos em claro');

-- E o proprio ato de anonimizar re-grava o valor antigo em `antes`:
update public.pessoas set nome='ANONIMIZADO', email=null, telefone=null, observacoes=null,
       cpf_hash=null, cpf_enc=null, cpf_ultimos_digitos=null, ativa=false
 where id='20000000-0000-0000-0000-0000000000a1';
select is(
  (select antes->>'nome' from audit.log
     where seq > (select seq from _base) and tabela='pessoas' and acao='UPDATE' order by seq desc limit 1),
  null,
  'B2 o UPDATE de anonimizacao nao pode gravar o nome antigo em claro na propria trilha');

-- ======================================================================
-- C. O que mantem a decisao reversivel
-- ======================================================================
-- audit.acesso e expurgavel de proposito (sem encadeamento). Se um dia ganhar hash-chain, PII
-- em `recurso_id`/`motivo`/`ip` vira irreversivel do mesmo jeito que audit.log.
select is(
  (select coalesce(string_agg(column_name,',' order by column_name),'(nenhuma)')
     from information_schema.columns
    where table_schema='audit' and table_name='acesso'
      and column_name in ('hash_registro','hash_anterior')),
  '(nenhuma)',
  'C1 audit.acesso continua SEM encadeamento de hash (expurgo de 6 meses so funciona assim)');

select is(
  (select count(*)::text from pg_trigger t
    where t.tgrelid='audit.log'::regclass and not t.tgisinternal),
  '2',
  'C2 audit.log mantem as duas travas de imutabilidade (linha + statement) — a cadeia e mesmo definitiva');

select * from finish();
rollback;
