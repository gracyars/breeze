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
select plan(13);

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
-- B. Redacao por ALLOWLIST (V9) — a invariante que o parecer juridico fixou
-- ======================================================================
-- Parecer docs/juridico/pareceres/2026-09-04-cpf-hash-na-trilha.md: nome/email/telefone ficam EM
-- CLARO (nome ja e permanente em ata por exigencia legal; email/telefone provam desvio de magic
-- link — Risco nº6). cpf_hash/cpf_enc/cpf_ultimos_digitos/observacoes sao REDIGIDOS: o CPF nao
-- existe em nenhum outro lugar permanente do acervo, e cpf_hash e pseudonimizacao reversivel com
-- o pepper. audit.log e permanente e encadeado — redacao e na escrita ou nunca.
select is(
  (select string_agg(kv.key, ',' order by kv.key)
     from audit.log l, jsonb_each(l.depois) kv
    where l.seq > (select seq from _base) and l.tabela='pessoas'
      and jsonb_typeof(kv.value) <> 'null' and kv.value#>>'{}' = '[REDIGIDO]'),
  'cpf_enc,cpf_hash,cpf_ultimos_digitos,observacoes',
  'B1 exatamente cpf_enc/cpf_hash/cpf_ultimos_digitos/observacoes sao redigidos no snapshot de pessoas');

select is(
  (select (kv.value#>>'{}') || '|' ||
          (select (k2.value#>>'{}') from jsonb_each(l.depois) k2 where k2.key='email') || '|' ||
          (select (k3.value#>>'{}') from jsonb_each(l.depois) k3 where k3.key='telefone')
     from audit.log l, jsonb_each(l.depois) kv
    where l.seq > (select seq from _base) and l.tabela='pessoas' and kv.key='nome'),
  'Ana Maria da Silva|ana.silva@exemplo.com|+5511999998888',
  'B2 nome/email/telefone ficam EM CLARO, por juizo de proporcionalidade do parecer');

-- FAIL-SAFE: a allowlist e lista do que foi analisado e LIBERADO. Coluna nova numa tabela
-- auditada tem de NASCER redigida, sem ninguem lembrar de proteger — esquecer de LIBERAR e
-- inofensivo, esquecer de PROTEGER seria permanente.
alter table public.pessoas add column apelido text;
alter table public.pessoas add column endereco_completo text;
update public.pessoas set apelido='Aninha', endereco_completo='Rua X, 123, apto 101'
 where id='20000000-0000-0000-0000-0000000000a1';
select is(
  (select string_agg(kv.key||'='||(kv.value#>>'{}'), ' ' order by kv.key)
     from audit.log l, jsonb_each(l.depois) kv
    where l.seq > (select seq from _base) and l.tabela='pessoas' and l.acao='UPDATE'
      and kv.key in ('apelido','endereco_completo')),
  'apelido=[REDIGIDO] endereco_completo=[REDIGIDO]',
  'B3 coluna NOVA em tabela auditada nasce REDIGIDA sem tocar na allowlist (fail-safe real)');

-- Preservar o FATO de que a coluna mudou, sem o valor — mas nao inventar fato onde nao havia:
-- valor ja NULL na linha original permanece NULL, nunca vira um '[REDIGIDO]' falso.
select is(
  (select jsonb_typeof(kv.value)
     from audit.log l, jsonb_each(l.depois) kv
    where l.seq > (select seq from _base) and l.tabela='pessoas' and l.acao='INSERT'
      and kv.key='anonimizada_em'),
  'null',
  'B4 valor ja nulo permanece nulo na trilha (nao vira [REDIGIDO] falso-positivo)');

-- A redacao tem de acontecer ANTES da serializacao canonica. Se o hash tivesse sido calculado
-- sobre o valor em claro, recomputar a cadeia a partir da linha GRAVADA (ja redigida) nao
-- bateria — a verificacao e a prova direta da ordem das operacoes.
select is(
  coalesce((select string_agg(v.seq::text||': '||v.motivo,'; ') from audit.verificar_cadeia() v),
           'CADEIA INTEGRA'),
  'CADEIA INTEGRA',
  'B5 [REDIGIDO] entra antes do canonico: a cadeia recomputa a partir da linha ja redigida');

-- Retomada INCREMENTAL da verificacao. `audit.ancoras.ate_seq` existe exatamente para isso: a
-- verificacao semanal retoma de ate_seq+1 em vez de revarrer a cadeia inteira. Mas a funcao le
-- o hash da linha `desde-1`, e essa linha pode nao existir: toda transacao abortada queima um
-- nextval de audit.log.seq (constraint violada, policy negando escrita, deploy que falha no
-- meio). Depois de um gap, a retomada acusa quebra numa cadeia intacta — o mesmo alarme falso do
-- V5, por outra porta, e igualmente capaz de mascarar adulteracao real.
do $$ begin
  insert into public.pessoas (id,nome) values ('20000000-0000-0000-0000-00000000fa11','Queima Nextval');
  raise exception 'aborta de proposito, queimando o seq';
exception when others then null; end $$;
insert into public.pessoas (id,nome) values ('20000000-0000-0000-0000-00000000fa12','Depois Do Gap');

select is(
  coalesce((select string_agg(v.seq::text||': '||v.motivo,'; ')
              from audit.verificar_cadeia(
                (select seq from (select seq, lag(seq) over (order by seq) ant from audit.log) t
                  where ant is not null and seq <> ant+1 order by seq desc limit 1)) v),
           'CADEIA INTEGRA'),
  'CADEIA INTEGRA',
  'B7 verificacao INCREMENTAL a partir de uma linha logo apos gap de seq nao acusa quebra falsa');

-- Nenhuma tabela auditada pode ter coluna liberada sem motivo escrito — a liberacao e decisao
-- consciente, com dono e justificativa, nao um INSERT solto.
select is(
  (select coalesce(string_agg(tabela||'.'||coluna,',' order by tabela,coluna),'(nenhuma)')
     from audit.colunas_liberadas where motivo is null or length(btrim(motivo)) < 5),
  '(nenhuma)',
  'B6 toda coluna liberada na allowlist tem motivo escrito');

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
