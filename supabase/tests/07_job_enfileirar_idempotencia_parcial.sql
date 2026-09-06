-- ============================================================================
-- Breeze — F1 corte C2: unicidade PARCIAL de job.fila.chave_idempotencia (ADR-0025 §2) e
-- job.enfileirar() como único caminho de fila (ADR-0026 §1).
--
-- Pergunta do teste: a correção do bug E2 (docs/ops/divida-tecnica.md; unicidade TOTAL virava
-- no-op permanente em "on conflict do nothing" depois que o primeiro job concluía) funciona nos
-- dois sentidos — (a) duas execuções simultâneas do MESMO trabalho continuam impedidas, E
-- (b) reenfileirar o MESMO trabalho depois que o job anterior concluiu agora FUNCIONA. Testa os
-- dois no nível do índice bruto (SQL direto) e no nível da função (job.enfileirar).
--
-- Auto-contido (begin/rollback), sem tocar RLS de tabela de usuário — job.fila está fora do
-- PostgREST (ADR-0007) e sem policy própria; o que se testa aqui é UNICIDADE e GRANT de função,
-- não visibilidade por papel. Impersonação por pg_temp.probe (mesmo padrão dos demais arquivos
-- desta suíte — ver 01_visibilidade_documento_pagina_chunk_rls.sql).
-- ============================================================================
begin;
select plan(26);

create function pg_temp.probe(p_role text, p_sql text)
returns text language plpgsql as $f$
declare r text;
begin
  execute 'set local role '||quote_ident(p_role);
  begin execute p_sql into r; exception when others then r := 'ERRO['||sqlstate||']'; end;
  execute 'set local role postgres';
  return coalesce(r,'(null)');
end $f$;

-- fixture: um documento que serve de "documento_id" para os jobs de teste
insert into public.documentos (id, tipo, titulo, storage_path)
values ('99000000-0000-0000-0000-00000000c201', 'comunicado',
        'Comunicado de teste — job.enfileirar', '/test/job-enfileirar-c2.pdf');

-- ---------------------------------------------------------------------------
-- Bloco 1 — o índice bruto, sem passar pela função: prova que a trava é do BANCO, não convenção
-- ---------------------------------------------------------------------------

select has_index('job', 'fila', 'fila_chave_idempotencia_ativa_uk',
  'T01 índice único parcial de chave_idempotencia existe');

select has_index('job', 'fila', 'fila_documento_idx',
  'T02 índice de job por documento (payload->>documento_id) existe');

insert into job.fila (tipo, payload, chave_idempotencia)
values ('teste_direto', '{}'::jsonb, 'direto:pendente:v1');

select throws_ok(
  $$insert into job.fila (tipo, payload, chave_idempotencia)
    values ('teste_direto', '{}'::jsonb, 'direto:pendente:v1')$$,
  '23505',
  null,
  'T03 segunda linha PENDENTE com a mesma chave é rejeitada pelo índice parcial (execução simultânea impedida)');

update job.fila set status = 'processando', iniciado_em = now()
 where chave_idempotencia = 'direto:pendente:v1';

select throws_ok(
  $$insert into job.fila (tipo, payload, chave_idempotencia)
    values ('teste_direto', '{}'::jsonb, 'direto:pendente:v1')$$,
  '23505',
  null,
  'T04 segunda linha enquanto a primeira está PROCESSANDO também é rejeitada (mesma trava)');

update job.fila set status = 'concluido', concluido_em = now()
 where chave_idempotencia = 'direto:pendente:v1';

select lives_ok(
  $$insert into job.fila (tipo, payload, chave_idempotencia)
    values ('teste_direto', '{}'::jsonb, 'direto:pendente:v1')$$,
  'T05 depois de CONCLUÍDA, reenfileirar a MESMA chave funciona (o bug E2 que a unicidade total causava)');

select is(
  (select count(*)::int from job.fila where chave_idempotencia = 'direto:pendente:v1'),
  2,
  'T06 as duas linhas (concluída + nova pendente) coexistem — histórico não é sobrescrito');

-- ---------------------------------------------------------------------------
-- Bloco 2 — job.enfileirar(): idempotência de fila fim a fim
-- ---------------------------------------------------------------------------

select isnt(
  (select job.enfileirar('hash_dedupe', '99000000-0000-0000-0000-00000000c201'::uuid,
                          'ingestao:c2teste:v1', '{}'::jsonb)),
  null,
  'T07 primeira chamada cria o job (retorna id não nulo)');

select is(
  (select job.enfileirar('hash_dedupe', '99000000-0000-0000-0000-00000000c201'::uuid,
                          'ingestao:c2teste:v1', '{}'::jsonb)),
  null::bigint,
  'T08 segunda chamada com a MESMA chave, job ainda pendente, retorna NULL (on conflict do nothing)');

select is(
  (select count(*)::int from job.fila where chave_idempotencia = 'ingestao:c2teste:v1'),
  1,
  'T09 nenhuma linha nova foi criada pela segunda chamada — ainda uma só');

update job.fila set status = 'processando', iniciado_em = now()
 where chave_idempotencia = 'ingestao:c2teste:v1';

select is(
  (select job.enfileirar('hash_dedupe', '99000000-0000-0000-0000-00000000c201'::uuid,
                          'ingestao:c2teste:v1', '{}'::jsonb)),
  null::bigint,
  'T10 enquanto PROCESSANDO, enfileirar de novo continua sendo no-op (não duplica trabalho em curso)');

update job.fila set status = 'concluido', concluido_em = now()
 where chave_idempotencia = 'ingestao:c2teste:v1';

select isnt(
  (select job.enfileirar('hash_dedupe', '99000000-0000-0000-0000-00000000c201'::uuid,
                          'ingestao:c2teste:v1', '{}'::jsonb)),
  null,
  'T11 depois de CONCLUÍDO, job.enfileirar() com a mesma chave cria um job NOVO (reprocessamento funciona)');

select is(
  (select count(*)::int from job.fila where chave_idempotencia = 'ingestao:c2teste:v1'),
  2,
  'T12 histórico: uma linha concluída + uma pendente, para a mesma chave');

select is(
  (select count(*)::int from job.fila where chave_idempotencia = 'ingestao:c2teste:v1'
     and status in ('pendente','processando')),
  1,
  'T13 mas só UMA está ativa agora — é essa a garantia que a unicidade parcial protege');

-- payload sempre carrega documento_id, mesmo chamando com payload vazio
select is(
  (select payload ->> 'documento_id' from job.fila
     where chave_idempotencia = 'ingestao:c2teste:v1' and status = 'pendente'),
  '99000000-0000-0000-0000-00000000c201',
  'T14 job.enfileirar() grava documento_id no payload mesmo quando o chamador manda payload vazio');

-- payload explícito não é substituído, só complementado
select is(
  (select job.enfileirar('chunking', '99000000-0000-0000-0000-00000000c201'::uuid,
                          'chunking:c2teste:v1',
                          jsonb_build_object('motivo','reclassificacao')) is not null),
  true,
  'T15 chamada com payload não vazio ainda cria o job');

select is(
  (select payload from job.fila where chave_idempotencia = 'chunking:c2teste:v1'),
  jsonb_build_object('motivo','reclassificacao','documento_id','99000000-0000-0000-0000-00000000c201'),
  'T16 payload do chamador é preservado e documento_id é mesclado, não substitui o resto');

-- validação de entrada
select throws_ok(
  $$select job.enfileirar(null, '99000000-0000-0000-0000-00000000c201'::uuid, 'x:v1', '{}'::jsonb)$$,
  'P0001', null,
  'T17 p_tipo nulo é rejeitado');

select throws_ok(
  $$select job.enfileirar('hash_dedupe', null, 'x:v1', '{}'::jsonb)$$,
  'P0001', null,
  'T18 p_documento_id nulo é rejeitado');

select throws_ok(
  $$select job.enfileirar('hash_dedupe', '99000000-0000-0000-0000-00000000c201'::uuid, '', '{}'::jsonb)$$,
  'P0001', null,
  'T19 p_chave vazia é rejeitada');

-- ---------------------------------------------------------------------------
-- Bloco 3 — superfície de GRANT: só quem deve chamar, chama; ninguém insere direto na tabela
-- ---------------------------------------------------------------------------

select ok(
  pg_temp.probe('authenticated',
    $$select job.enfileirar('hash_dedupe', '99000000-0000-0000-0000-00000000c201'::uuid,
                             'grant:authenticated:v1', '{}'::jsonb)::text$$) !~ '^ERRO',
  'T20 authenticated (editora fazendo upload) executa job.enfileirar()');

select ok(
  pg_temp.probe('service_role',
    $$select job.enfileirar('hash_dedupe', '99000000-0000-0000-0000-00000000c201'::uuid,
                             'grant:service-role:v1', '{}'::jsonb)::text$$) !~ '^ERRO',
  'T21 service_role (o worker) executa job.enfileirar()');

select ok(
  pg_temp.probe('anon',
    $$select job.enfileirar('hash_dedupe', '99000000-0000-0000-0000-00000000c201'::uuid,
                             'grant:anon:v1', '{}'::jsonb)::text$$) ~ '^ERRO',
  'T22 anon NÃO executa job.enfileirar() (permission denied)');

select ok(
  pg_temp.probe('authenticated',
    $$insert into job.fila (tipo, payload, chave_idempotencia)
      values ('teste', '{}'::jsonb, 'direto:authenticated:v1') returning id::text$$) ~ '^ERRO',
  'T23 authenticated NÃO insere direto em job.fila — só pela função (SECURITY DEFINER é obrigatório, não conveniência)');

select ok(
  pg_temp.probe('anon',
    $$insert into job.fila (tipo, payload, chave_idempotencia)
      values ('teste', '{}'::jsonb, 'direto:anon:v1') returning id::text$$) ~ '^ERRO',
  'T24 anon NÃO insere direto em job.fila');

-- ---------------------------------------------------------------------------
-- Bloco 4 — colunas aditivas do corte C2 (confirmação de forma, não de RLS)
-- ---------------------------------------------------------------------------

select is(
  (select is_nullable from information_schema.columns
     where table_schema = 'public' and table_name = 'documentos' and column_name = 'sha256'),
  'YES',
  'T25 documentos.sha256 é nullable (o worker preenche no estágio 1, ADR-0025)');

select has_column('public', 'chunks', 'secao',
  'T26 chunks.secao existe (SPEC §4 D17 — capítulo+artigo+página é a unidade citável no Regimento)');

select * from finish();
rollback;
