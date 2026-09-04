-- ============================================================================
-- Breeze — auditoria de superficie de privilegio (catalogo, nao leitura de codigo).
-- Alvo: o que cada papel PODE, independentemente de existir policy. RLS so filtra linha depois
-- que o GRANT deixou entrar; e RLS nao se aplica a TRUNCATE nem esconde coluna.
--
-- Cada arquivo e auto-contido (pg_prove roda um por um): abre `begin`, cria a propria fixture,
-- roda os asserts e fecha em `rollback` — nada fica no banco. Impersonacao por
-- pg_temp.probe/tenta/executa (troca request.jwt.claims + `set local role` e VOLTA para postgres
-- antes de retornar, para o pgTAP seguir rodando como postgres). `tenta` desfaz o efeito do
-- ataque: um ataque que passa nao pode destruir a fixture do teste seguinte.
-- Atores: ...e1 editor(AAL2) | ...c1 conselho | ...a1 morador un.101 | ...b1 morador un.102
--         ...f1 mandato vencido ontem | ...d1 JWT authenticated sem linha em pessoas
-- ============================================================================
begin;
select plan(22);

create function pg_temp.tenta(p_role text, p_sql text)
returns text language plpgsql as $f$
declare r text;
begin
  perform set_config('request.jwt.claims', null, true);
  execute 'set local role '||quote_ident(p_role);
  begin
    declare n int;
    begin
      execute p_sql; get diagnostics n = row_count;
      raise exception using errcode='22000', message='__desfaz__'||n;
    end;
  exception
    when sqlstate '22000' then
      if sqlerrm like '__desfaz__%' then r := 'OK'; else r := 'ERRO[22000]'; end if;
    when others then r := 'ERRO['||sqlstate||']';
  end;
  execute 'set local role postgres';
  return r;
end $f$;

-- ======================================================================
-- A. Negacao por padrao
-- ======================================================================
select is(
  (select coalesce(string_agg(c.relname,',' order by c.relname),'(nenhuma)')
     from pg_class c
    where c.relnamespace in ('public'::regnamespace,'audit'::regnamespace,'job'::regnamespace)
      and c.relkind='r' and not c.relrowsecurity),
  '(nenhuma)', 'A1 toda tabela de public/audit/job tem RLS habilitada');

select is(
  (select coalesce(string_agg(c.relname,',' order by c.relname),'(nenhuma)')
     from pg_class c
    where c.relnamespace='public'::regnamespace and c.relkind='r' and not c.relforcerowsecurity),
  '(nenhuma)', 'A2 toda tabela de public tem RLS FORCADA (o dono tambem passa pela policy)');

-- Tabela com GRANT de leitura e sem nenhuma policy = tabela aberta a quem tem o GRANT.
select is(
  (select coalesce(string_agg(c.relname,',' order by c.relname),'(nenhuma)')
     from pg_class c
    where c.relnamespace='public'::regnamespace and c.relkind='r'
      and (has_table_privilege('anon',c.oid,'SELECT') or has_table_privilege('authenticated',c.oid,'SELECT'))
      and not exists (select 1 from pg_policy p where p.polrelid=c.oid)),
  '(nenhuma)', 'A3 nenhuma tabela com GRANT SELECT ficou sem policy');

select is( pg_temp.tenta('anon',   $$select 1 from audit.log limit 1$$), 'ERRO[42501]', 'A4 anon nao tem USAGE no schema audit');
select is( pg_temp.tenta('anon',   $$select 1 from job.fila limit 1$$),  'ERRO[42501]', 'A5 anon nao tem USAGE no schema job');
select is( pg_temp.tenta('authenticated', $$select 1 from job.fila limit 1$$), 'ERRO[42501]', 'A6 authenticated nao tem USAGE no schema job');

-- ======================================================================
-- B. A armadilha do REVOKE de coluna (ADR-0014)
-- ======================================================================
-- `REVOKE SELECT (col)` NAO subtrai de um `GRANT SELECT` de tabela: ACL de tabela e de coluna
-- sao UNIAO. A unica forma de excluir uma coluna e nunca conceder SELECT da tabela inteira.
-- Este teste vale para QUALQUER tabela futura que tente esconder coluna: se a tabela tem ACL de
-- coluna, ela nao pode ter tambem ACL de tabela.
select is(
  (select coalesce(string_agg(distinct c.relname,',' order by c.relname),'(nenhuma)')
     from pg_class c
     join pg_attribute a on a.attrelid=c.oid and a.attacl is not null
    where c.relnamespace='public'::regnamespace
      and (has_table_privilege('anon',c.oid,'SELECT') or has_table_privilege('authenticated',c.oid,'SELECT'))),
  '(nenhuma)',
  'B1 nenhuma tabela combina GRANT de coluna com GRANT SELECT de tabela (revoke de coluna nao subtrai)');

select ok( not has_column_privilege('authenticated','public.pessoas','cpf_enc','SELECT'),
  'B2 authenticated NAO tem SELECT em pessoas.cpf_enc');
select ok( has_column_privilege('authenticated','public.pessoas','nome','SELECT'),
  'B3 authenticated TEM SELECT em pessoas.nome (controle: o grant de coluna funciona)');
select ok( not has_column_privilege('authenticated','public.fornecedores','cpf_enc','SELECT'),
  'B4 authenticated NAO tem SELECT em fornecedores.cpf_enc');
select ok( has_column_privilege('authenticated','public.fornecedores','razao_social','SELECT'),
  'B5 authenticated TEM SELECT em fornecedores.razao_social (controle)');

-- ======================================================================
-- C. service_role — o que ele PODE tem de ser o que o desenho diz que ele faz
-- ======================================================================
-- O desenho descreve service_role como o gravador do worker (chunks, documento_paginas), do
-- motor de alertas e da trilha de acesso. Nada disso e concedido explicitamente na baseline: o
-- privilegio real de service_role e o que o default do provedor deixou. Ou seja, o poder do
-- papel mais forte do sistema nao esta declarado em lugar nenhum das migracoes.
select is( pg_temp.tenta('service_role',
  $$insert into public.documento_paginas (documento_id,pagina,texto)
    select id,999,'worker' from public.documentos limit 1$$),
  'OK', 'C1 service_role escreve em documento_paginas (o worker do pipeline)');
select is( pg_temp.tenta('service_role',
  $$insert into public.alertas (tipo,severidade,conta_id,chave_dedupe)
    select 'estouro_orcamento','alta',id,'dedupe-teste' from public.contas limit 1$$),
  'OK', 'C2 service_role escreve em public.alertas (o motor de alertas)');
select is( pg_temp.tenta('service_role',
  $$insert into audit.acesso (recurso) values ('cpf_em_claro')$$),
  'OK', 'C3 service_role escreve em audit.acesso (SPEC §5.5/§7)');
select is( pg_temp.tenta('service_role',
  $$select 1 from job.fila limit 1$$),
  'OK', 'C4 service_role consome job.fila (ADR-0007)');
-- ...e NAO pode ter o unico privilegio que apaga o passado inteiro sem trilha:
select is(
  (select coalesce(string_agg(c.relname,',' order by c.relname),'(nenhuma)')
     from pg_class c
    where c.relnamespace='public'::regnamespace and c.relkind='r'
      and has_table_privilege('service_role',c.oid,'TRUNCATE')),
  '(nenhuma)', 'C5 service_role nao tem TRUNCATE em nenhuma tabela de public');

-- ======================================================================
-- D. Funcoes de autorizacao
-- ======================================================================
select is(
  (select coalesce(string_agg(n.nspname||'.'||p.proname,',' order by p.proname),'(nenhuma)')
     from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('app','audit','public') and p.prosecdef
      and (p.proconfig is null or not exists (
            select 1 from unnest(p.proconfig) x where x like 'search_path=%'))),
  '(nenhuma)', 'D1 toda funcao security definer tem search_path fixo (senao e escalada)');

-- A migracao concede EXECUTE de eh_gestao/eh_autenticado a anon de proposito. Se a chamada
-- estoura permissao em vez de devolver false, qualquer policy futura `to anon` que use estes
-- helpers vira erro 500 no PostgREST — nao uma negacao limpa.
select is( pg_temp.tenta('anon', $$select app.eh_autenticado()$$),
  'OK', 'D2 anon consegue avaliar app.eh_autenticado() (o GRANT a anon precisa ser utilizavel)');
select is( pg_temp.tenta('anon', $$select app.eh_gestao()$$),
  'OK', 'D3 anon consegue avaliar app.eh_gestao()');
select is( pg_temp.tenta('anon', $$select app.tem_papel('editor')$$),
  'ERRO[42501]', 'D4 anon NAO avalia app.tem_papel diretamente (primitiva so para authenticated)');

-- ======================================================================
-- E. Views — fronteira de autorizacao so onde foi decidido que seria
-- ======================================================================
select is(
  (select coalesce(string_agg(c.relname,',' order by c.relname),'(nenhuma)')
     from pg_class c
    where c.relnamespace='public'::regnamespace and c.relkind='v'
      and c.relname not in ('vw_inadimplencia_agregada','vw_lancamentos_com_comprovante')
      and not coalesce((select option_value='true' from pg_options_to_table(c.reloptions)
                         where option_name='security_invoker'), false)),
  '(nenhuma)',
  'E1 toda view e security_invoker, exceto as duas excecoes documentadas em 20260904122200_views.sql');

select is(
  (select coalesce(string_agg(c.relname,',' order by c.relname),'(nenhuma)')
     from pg_class c
    where c.relnamespace='public'::regnamespace and c.relkind='v'
      and c.relname in ('vw_inadimplencia_agregada','vw_inadimplencia_nominal','vw_pessoas_mascaradas',
                        'vw_lancamentos_com_comprovante')
      and has_table_privilege('anon',c.oid,'SELECT')),
  '(nenhuma)', 'E2 nenhuma view com dado pessoal ou financeiro e legivel por anon');

select * from finish();
rollback;
