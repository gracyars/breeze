-- ============================================================================
-- Breeze — auditoria de RLS: papeis (editor/conselho/morador), AAL, mandato vencido,
-- anonimo, pessoas.cpf_enc e cobrancas por unidade. Fonte: SPEC §2.1, §5.5, §7; ADR-0014.
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
select plan(41);

create function pg_temp.probe(p_role text, p_sub text, p_aal text, p_sql text)
returns text language plpgsql as $f$
declare r text;
begin
  if p_sub is null then perform set_config('request.jwt.claims', null, true);
  else perform set_config('request.jwt.claims',
    json_build_object('sub',p_sub,'role',p_role,'aal',coalesce(p_aal,'aal1'))::text, true); end if;
  execute 'set local role '||quote_ident(p_role);
  begin execute p_sql into r; exception when others then r := 'ERRO['||sqlstate||']'; end;
  execute 'set local role postgres';
  return coalesce(r,'(vazio)');
end $f$;

-- `tenta` executa o ataque e DESFAZ o efeito (subtransacao revertida por raise proposital):
-- um ataque que passa nao pode destruir a fixture dos testes seguintes — senao o resultado de
-- um teste depende da ordem, e a suite mente. `executa` e a versao que persiste, usada so onde
-- o efeito precisa sobreviver para o teste seguinte.
create function pg_temp.tenta(p_role text, p_sub text, p_aal text, p_sql text)
returns text language plpgsql as $f$
declare r text;
begin
  if p_sub is null then perform set_config('request.jwt.claims', null, true);
  else perform set_config('request.jwt.claims',
    json_build_object('sub',p_sub,'role',p_role,'aal',coalesce(p_aal,'aal1'))::text, true); end if;
  execute 'set local role '||quote_ident(p_role);
  begin
    declare n int;
    begin
      execute p_sql;
      get diagnostics n = row_count;
      raise exception using errcode='22000', message='__desfaz__'||n;
    end;
  exception
    when sqlstate '22000' then
      if sqlerrm like '__desfaz__%' then r := 'OK ('||replace(sqlerrm,'__desfaz__','')||')';
      else r := 'ERRO[22000]'; end if;
    when others then r := 'ERRO['||sqlstate||']';
  end;
  execute 'set local role postgres';
  return r;
end $f$;

create function pg_temp.executa(p_role text, p_sub text, p_aal text, p_sql text)
returns text language plpgsql as $f$
declare n int;
begin
  if p_sub is null then perform set_config('request.jwt.claims', null, true);
  else perform set_config('request.jwt.claims',
    json_build_object('sub',p_sub,'role',p_role,'aal',coalesce(p_aal,'aal1'))::text, true); end if;
  execute 'set local role '||quote_ident(p_role);
  begin execute p_sql; get diagnostics n = row_count; execute 'set local role postgres'; return 'OK ('||n||')';
  exception when others then execute 'set local role postgres'; return 'ERRO['||sqlstate||']'; end;
end $f$;

-- ---------------------------------------------------------------- fixture --
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
 ('00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','p-editor@t.local',now(),now()),
 ('00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','p-conselho@t.local',now(),now()),
 ('00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','p-mora@t.local',now(),now()),
 ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','p-morb@t.local',now(),now()),
 ('00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','p-venc@t.local',now(),now()),
 ('00000000-0000-0000-0000-0000000000d1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','p-semp@t.local',now(),now());

insert into public.unidades (id, bloco, numero, fracao_ideal) values
 ('10000000-0000-0000-0000-000000000101','','T101',0.34),
 ('10000000-0000-0000-0000-000000000102','','T102',0.33),
 ('10000000-0000-0000-0000-000000000103','','T103',0.33);

insert into public.pessoas (id, auth_user_id, nome, cpf_hash, cpf_enc, cpf_ultimos_digitos) values
 ('20000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-0000000000e1','Edna Editora',   decode(repeat('e1',32),'hex'),'\xAAE1'::bytea,'111'),
 ('20000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000c1','Carlos Conselho',decode(repeat('c1',32),'hex'),'\xAAC1'::bytea,'222'),
 ('20000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000a1','Ana Moradora',   decode(repeat('a1',32),'hex'),'\xAAA1'::bytea,'333'),
 ('20000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000b1','Bruno Morador',  decode(repeat('b1',32),'hex'),'\xAAB1'::bytea,'444'),
 ('20000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-0000000000f1','Fabio Vencido',  null,null,null);

insert into public.vinculos (unidade_id, pessoa_id, tipo) values
 ('10000000-0000-0000-0000-000000000101','20000000-0000-0000-0000-0000000000a1','proprietario'),
 ('10000000-0000-0000-0000-000000000102','20000000-0000-0000-0000-0000000000b1','proprietario');

insert into public.papeis (pessoa_id, papel, mandato_inicio, mandato_fim) values
 ('20000000-0000-0000-0000-0000000000e1','editor',  current_date-30,null),
 ('20000000-0000-0000-0000-0000000000c1','conselho',current_date-30,null),
 ('20000000-0000-0000-0000-0000000000a1','morador', current_date-30,null),
 ('20000000-0000-0000-0000-0000000000b1','morador', current_date-30,null),
 -- mandato VENCIDO ONTEM: papel e dado, nao claim. Deixa de valer no dia seguinte.
 ('20000000-0000-0000-0000-0000000000f1','conselho',current_date-60,current_date-1),
 ('20000000-0000-0000-0000-0000000000f1','editor',  current_date-60,current_date-1);

insert into public.fornecedores (id,cnpj,razao_social,cpf_hash,cpf_enc) values
 ('50000000-0000-0000-0000-000000000001','11222333000181','Prestador PF LTDA',decode(repeat('f1',32),'hex'),'\xAAFF'::bytea);

insert into public.fornecedor_dados_bancarios (fornecedor_id, banco, conta_mascarada) values
 ('50000000-0000-0000-0000-000000000001','001','****1234');

insert into public.cobrancas (id, unidade_id, competencia, valor_centavos, vencimento, status) values
 ('80000000-0000-0000-0000-000000000101','10000000-0000-0000-0000-000000000101',date_trunc('month',current_date)::date,50000,current_date+10,'aberta'),
 ('80000000-0000-0000-0000-000000000102','10000000-0000-0000-0000-000000000102',date_trunc('month',current_date)::date,90000,current_date-40,'atrasada'),
 ('80000000-0000-0000-0000-000000000103','10000000-0000-0000-0000-000000000103',date_trunc('month',current_date)::date,70000,current_date-70,'atrasada');

-- ======================================================================
-- A. Papel e DADO, nao claim: mandato vencido e AAL
-- ======================================================================
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000e1','aal2',$$select app.eh_editor()::text$$),
  'true', 'A1 editor com mandato vigente e AAL2 e editor (controle)');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000e1','aal1',$$select app.eh_editor()::text$$),
  'false', 'A2 editor em sessao AAL1 NAO e editor (TOTP obrigatorio, ADR-0003)');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000e1',null,$$select app.eh_editor()::text$$),
  'false', 'A3 JWT sem claim aal e tratado como aal1');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000c1','aal1',$$select app.eh_gestao()::text$$),
  'false', 'A4 conselho em AAL1 nao e gestao');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000c1','aal2',$$select app.eh_gestao()::text$$),
  'true', 'A5 conselho em AAL2 e gestao (controle)');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000f1','aal2',$$select app.eh_gestao()::text$$),
  'false', 'A6 mandato vencido ontem nao vale hoje, mesmo com AAL2');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000f1','aal2',$$select coalesce(app.papel_atual()::text,'(nulo)')$$),
  '(nulo)', 'A7 papel_atual de mandato vencido e nulo');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000d1','aal2',$$select app.eh_autenticado()::text$$),
  'false', 'A8 JWT authenticated sem linha em pessoas nao e autenticado para a RLS');

-- ======================================================================
-- B. Escalada de privilegio pela tabela papeis
-- ======================================================================
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$insert into public.papeis (pessoa_id,papel) values ('20000000-0000-0000-0000-0000000000a1','editor')$$),
  'ERRO[42501]', 'B1 morador nao se promove a editor');
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000c1','aal2',
  $$insert into public.papeis (pessoa_id,papel) values ('20000000-0000-0000-0000-0000000000c1','editor')$$),
  'ERRO[42501]', 'B2 conselho em AAL2 nao se promove a editor');
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000e1','aal1',
  $$insert into public.papeis (pessoa_id,papel) values ('20000000-0000-0000-0000-0000000000b1','editor')$$),
  'ERRO[42501]', 'B3 editor em AAL1 nao concede papel');
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000f1','aal2',
  $$update public.papeis set mandato_fim=null where pessoa_id='20000000-0000-0000-0000-0000000000f1'$$),
  'OK (0)', 'B4 mandato vencido nao consegue reabrir o proprio mandato');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select count(*)::text from public.papeis$$),
  '1', 'B5 morador so enxerga o proprio papel');
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$delete from public.papeis where pessoa_id='20000000-0000-0000-0000-0000000000a1'$$),
  'ERRO[42501]', 'B6 ninguem apaga linha de papeis (encerra por mandato_fim)');
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000e1','aal2',
  $$delete from public.papeis where pessoa_id='20000000-0000-0000-0000-0000000000a1'$$),
  'ERRO[42501]', 'B7 nem o editor apaga linha de papeis');
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$insert into public.vinculos (unidade_id,pessoa_id,tipo)
    values ('10000000-0000-0000-0000-000000000102','20000000-0000-0000-0000-0000000000a1','residente')$$),
  'ERRO[42501]', 'B8 morador nao cria vinculo com a unidade do vizinho');

-- ======================================================================
-- C. pessoas.cpf_enc — GRANT de coluna, nao REVOKE de coluna (ADR-0014)
-- ======================================================================
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000e1','aal2',
  $$select encode(cpf_enc,'hex') from public.pessoas limit 1$$),
  'ERRO[42501]', 'C1 nem o editor le cpf_enc por SELECT direto');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000c1','aal2',
  $$select encode(cpf_enc,'hex') from public.pessoas limit 1$$),
  'ERRO[42501]', 'C2 conselho nao le cpf_enc');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select encode(cpf_enc,'hex') from public.pessoas where id='20000000-0000-0000-0000-0000000000a1'$$),
  'ERRO[42501]', 'C3 a pessoa nao le nem o proprio cpf_enc pela API');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000e1','aal2',
  $$select count(*)::text from (select * from public.pessoas) x$$),
  'ERRO[42501]', 'C4 SELECT * em pessoas e negado (nao existe GRANT SELECT de tabela)');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000e1','aal2',
  $$update public.pessoas set telefone='9' where id='20000000-0000-0000-0000-0000000000a1' returning encode(cpf_enc,'hex')$$),
  'ERRO[42501]', 'C5 cpf_enc nao sai por UPDATE ... RETURNING');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000e1','aal2',
  $$update public.pessoas set telefone='9' where cpf_enc is not null returning id::text$$),
  'ERRO[42501]', 'C6 cpf_enc nao serve de oraculo em WHERE de UPDATE');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000e1','aal2',
  $$insert into public.pessoas (nome,observacoes) select 'x', encode(cpf_enc,'hex') from public.pessoas limit 1 returning nome$$),
  'ERRO[42501]', 'C7 cpf_enc nao vaza por INSERT ... SELECT');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000e1','aal2',
  $$select encode(cpf_enc,'hex') from public.fornecedores limit 1$$),
  'ERRO[42501]', 'C8 fornecedores.cpf_enc tem a mesma trava (prestador PF, ADR-0014 item 7)');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000e1','aal2',
  $$select count(*)::text from (select * from public.fornecedores) x$$),
  'ERRO[42501]', 'C9 SELECT * em fornecedores e negado');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000c1','aal2',
  $$select string_agg(cpf_mascarado,',' order by cpf_mascarado) from public.vw_pessoas_mascaradas$$),
  '***.***.111-**,***.***.222-**,***.***.333-**,***.***.444-**',
  'C10 conselho ve CPF MASCARADO pela view, nunca o cifrado');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select string_agg(nome,',' order by nome) from public.pessoas$$),
  'Ana Moradora', 'C11 morador so le a propria linha de pessoas');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select string_agg(nome,',' order by nome) from public.vw_pessoas_mascaradas$$),
  'Ana Moradora', 'C12 a view mascarada herda a RLS (security_invoker), nao amplia');
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000e1','aal2',
  $$delete from public.pessoas where id='20000000-0000-0000-0000-0000000000a1'$$),
  'ERRO[42501]', 'C13 DELETE em pessoas e negado a todos (anonimizacao e UPDATE, SPEC §7)');

-- ======================================================================
-- D. cobrancas — inadimplencia nominal do vizinho
-- ======================================================================
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select string_agg(valor_centavos::text,',' order by valor_centavos) from public.cobrancas$$),
  '50000', 'D1 morador da 101 so ve a cobranca da propria unidade');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select count(*)::text from public.cobrancas where status='atrasada'$$),
  '0', 'D2 morador nao consegue nem CONTAR inadimplencia de outras unidades');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select count(*)::text from public.cobrancas where unidade_id='10000000-0000-0000-0000-000000000102'$$),
  '0', 'D3 morador da 101 nao alcanca a cobranca da 102 nem consultando pelo id da unidade');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000c1','aal1',
  $$select count(*)::text from public.cobrancas$$),
  '0', 'D4 conselho em AAL1 nao ve inadimplencia nominal');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000c1','aal2',
  $$select count(*)::text from public.cobrancas$$),
  '3', 'D5 conselho em AAL2 ve todas (controle)');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select coalesce(string_agg(numero,','),'(vazio)') from public.vw_inadimplencia_nominal$$),
  '(vazio)', 'D6 vw_inadimplencia_nominal nao entrega vizinho ao morador (security_invoker)');
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$update public.cobrancas set status='paga', valor_pago_centavos=1, data_pagamento=current_date
     where unidade_id='10000000-0000-0000-0000-000000000101'$$),
  'OK (0)', 'D7 morador nao quita a propria cobranca');
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000e1','aal2',
  $$delete from public.cobrancas$$),
  'ERRO[42501]', 'D8 DELETE em cobrancas e negado (cancelar e status)');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000d1','aal2',
  $$select count(*)::text from public.vw_inadimplencia_agregada$$),
  '0', 'D9 JWT sem cadastro em pessoas nao le o agregado de inadimplencia do condominio');

-- ======================================================================
-- E. Outras leituras fora do papel
-- ======================================================================
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select count(*)::text from public.fornecedor_dados_bancarios$$),
  '0', 'E1 morador nao le dados bancarios de fornecedor');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000c1','aal1',
  $$select count(*)::text from public.fornecedor_dados_bancarios$$),
  '0', 'E2 conselho em AAL1 nao le dados bancarios de fornecedor');
-- E3 (morador abrindo questionamento) vive em 03_*, que ja tem lancamentos na fixture.
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000e1','aal2',
  $$insert into public.pareceres (competencia_inicio,competencia_fim,texto) values (current_date,current_date,'x')$$),
  'ERRO[42501]', 'E4 editor NAO emite parecer: e a unica escrita exclusiva do conselho (SPEC §2.1)');

select * from finish();
rollback;
