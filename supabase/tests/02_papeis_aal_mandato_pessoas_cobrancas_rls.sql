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
select plan(55);

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

-- ------------------------------------------------------ RUIDO: banco POVOADO --
-- A suite roda contra o banco de desenvolvimento, e a partir de F1 esse banco NUNCA esta vazio:
-- `scripts/dev/semeia-editora.ts` cria a editora (sem ela nao ha backfill — service_role nao tem
-- INSERT em documentos), o e2e de autenticacao cria moradoras, o backfill cria acervo, o
-- balancete cria cobrancas. Assert que so significa o que diz em banco vazio e FALSO VERDE
-- esperando a vez: passa por sorte, nao por causa da policy.
-- Por isso a fixture SUJA o banco de proposito, ANTES de criar os proprios atores, com linhas que
-- imitam o estado real de F1 — inclusive uma editora com `mandato_inicio = current_date`, que foi
-- exatamente o que abortou este arquivo em 2026-09-06 (R3 de docs/ops/divida-tecnica.md).
-- Estas linhas nao sao atores de nenhum assert: existem so para que todo assert abaixo continue
-- significando a MESMA coisa com o banco cheio. Prefixo `ff` em todos os uuids.
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
 ('ff000000-0000-0000-0000-0000000000e0','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ruido-editora@t.local',now(),now()),
 ('ff000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ruido-mora@t.local',now(),now());

insert into public.unidades (id, bloco, numero, fracao_ideal) values
 ('ff100000-0000-0000-0000-000000000901','R','901',0.01),
 ('ff100000-0000-0000-0000-000000000902','R','902',0.01);

insert into public.pessoas (id, auth_user_id, nome, cpf_hash, cpf_enc, cpf_ultimos_digitos) values
 ('ff200000-0000-0000-0000-0000000000e0','ff000000-0000-0000-0000-0000000000e0','Editora Semeada (ruido)',decode(repeat('90',32),'hex'),'\xBB90'::bytea,'901'),
 ('ff200000-0000-0000-0000-0000000000a0','ff000000-0000-0000-0000-0000000000a0','Moradora do e2e (ruido)',decode(repeat('91',32),'hex'),'\xBB91'::bytea,'902');

insert into public.vinculos (unidade_id, pessoa_id, tipo) values
 ('ff100000-0000-0000-0000-000000000901','ff200000-0000-0000-0000-0000000000a0','proprietario');

-- A editora semeada abre mandato HOJE. E o estado normal do sistema, nao um caso de borda.
insert into public.papeis (pessoa_id, papel, mandato_inicio) values
 ('ff200000-0000-0000-0000-0000000000e0','editor', current_date),
 ('ff200000-0000-0000-0000-0000000000a0','morador',current_date);

insert into public.cobrancas (id, unidade_id, competencia, valor_centavos, vencimento, status) values
 ('ff800000-0000-0000-0000-000000000901','ff100000-0000-0000-0000-000000000901',date_trunc('month',current_date)::date,41000,current_date+5,'aberta'),
 ('ff800000-0000-0000-0000-000000000902','ff100000-0000-0000-0000-000000000902',date_trunc('month',current_date)::date,41000,current_date-30,'atrasada');

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
-- C10 mede a POLICY, nao o conteudo do banco. A versao antiga listava a tabela inteira e
-- comparava com quatro valores fixos: qualquer pessoa cadastrada fora do teste (a editora
-- semeada, uma moradora do e2e) fazia a auditoria de seguranca falhar sem que nada da seguranca
-- tivesse mudado (R3). O que a policy promete e (a) para ESTAS pessoas, este mascaramento, e
-- (b) para QUALQUER pessoa que o conselho alcance, nunca algo que nao seja mascara. Sao dois
-- asserts, e o (b) fica mais forte quanto mais povoado o banco estiver.
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000c1','aal2',
  $$select string_agg(cpf_mascarado,',' order by cpf_mascarado) from public.vw_pessoas_mascaradas
     where id::text like '20000000-%'$$),
  '***.***.111-**,***.***.222-**,***.***.333-**,***.***.444-**',
  'C10 conselho ve CPF MASCARADO pela view, nunca o cifrado');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000c1','aal2',
  $$select count(*)::text from public.vw_pessoas_mascaradas
     where cpf_mascarado is not null
       and cpf_mascarado !~ '^[*]{3}[.][*]{3}[.][0-9]{3}-[*]{2}$'$$),
  '0',
  'C10b NENHUMA linha que o conselho alcanca pela view sai fora da mascara (vale com o banco cheio)');
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
-- D5 e o controle de D1-D4: o conselho em AAL2 nao e filtrado. Contar `3` era contar a fixture,
-- nao a policy — bastava uma cobranca de outro lugar para o controle quebrar. A forma correta do
-- controle e a IGUALDADE com o total real da tabela: seja qual for o povoamento, gestao ve tudo.
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000c1','aal2',
  $$select count(*)::text from public.cobrancas$$),
  (select count(*)::text from public.cobrancas),
  'D5 conselho em AAL2 ve TODAS as cobrancas do banco, sem filtro (controle)');
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

-- ======================================================================
-- F. V10 — auto-trancamento do ultimo editor (3a rodada)
-- ======================================================================
-- Com `editor` unica (D4), perder o ultimo editor vigente e perda irreversivel do acesso de
-- escrita: service_role nao tem UPDATE em pessoas nem em papeis (de proposito), entao so um
-- acesso direto ao banco recupera. Os dois triggers cobrem `pessoas.ativa` e `papeis.mandato_fim`
-- — mas um mandato sai de vigencia por mais caminhos que esses dois.
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
 ('00000000-0000-0000-0000-0000000000f9','00000000-0000-0000-0000-000000000000','authenticated','authenticated','p-solo@t.local',now(),now());
insert into public.pessoas (id, auth_user_id, nome) values
 ('20000000-0000-0000-0000-0000000000f9','00000000-0000-0000-0000-0000000000f9','Solo Editora');
-- Solo entra como editora ANTES de encerrar os outros: o proprio trigger impede deixar o
-- sistema sem editor, entao a ordem importa (e ja e a prova de que a trava basica funciona).
insert into public.papeis (id, pessoa_id, papel) values
 ('50000000-0000-0000-0000-0000000000f9','20000000-0000-0000-0000-0000000000f9','editor');
-- Encerrar os outros mandatos e a PRE-CONDICAO do bloco F: os triggers que ele exercita leem a
-- tabela inteira, entao "Solo e a ultima editora" e um fato sobre o BANCO, nao sobre a fixture —
-- e nao da para escopar. O que da para fazer e CONSTRUIR a pre-condicao de forma legal e depois
-- CONFERIR que ela vale (F0 abaixo), em vez de supor.
--   `least(mandato_inicio, current_date - 60)` existe por um motivo especifico e incomodo: sem
-- ele, um mandato que comecou HOJE (a editora de `scripts/dev/semeia-editora.ts`, que e o estado
-- normal do sistema) faz `mandato_fim = current_date - 1` violar `papeis_mandato_ck` e ABORTA o
-- arquivo inteiro — foi o que aconteceu em 2026-09-06. Recuar `mandato_inicio` e legitimo AQUI
-- porque isto e a montagem de um mundo de teste dentro de begin/rollback, nao uma operacao de
-- negocio. Que a operacao de negocio correspondente ("encerrar hoje um mandato que comecou hoje")
-- nao exista no schema e um problema do SCHEMA, e esta registrado nos dois TODO do bloco G.
update public.papeis
   set mandato_inicio = least(mandato_inicio, current_date - 60),
       mandato_fim    = current_date - 1
 where papel = 'editor'
   and pessoa_id <> '20000000-0000-0000-0000-0000000000f9'
   and (mandato_fim is null or mandato_fim >= current_date);

-- Pre-condicao CONFERIDA, nao suposta: se um dia a montagem acima parar de produzir "so a Solo
-- vigente", F1-F8 passariam a medir outra coisa (o trigger do ultimo editor nem dispararia) e a
-- suite mentiria em verde. Este assert e o que impede isso.
select is(
  (select coalesce(string_agg(pe.nome,',' order by pe.nome),'(nenhuma)')
     from public.papeis pa join public.pessoas pe on pe.id = pa.pessoa_id
    where pa.papel='editor' and pe.ativa and pa.mandato_inicio <= current_date
      and (pa.mandato_fim is null or pa.mandato_fim >= current_date)),
  'Solo Editora',
  'F0 pre-condicao do bloco F: a Solo e a UNICA editora vigente no banco (vale com o banco cheio)');

select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000f9','aal2',
  $$update public.pessoas set ativa=false where id='20000000-0000-0000-0000-0000000000f9'$$),
  'ERRO[P0001]', 'F1 a unica editora nao consegue se desativar (ativa=false)');

select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000f9','aal2',
  $$update public.papeis set mandato_fim=current_date-1 where id='50000000-0000-0000-0000-0000000000f9'$$),
  'ERRO[P0001]', 'F2 a unica editora nao consegue encerrar o proprio mandato (mandato_fim)');

-- Um mandato tambem sai de vigencia empurrando o INICIO para o futuro. O trigger so olha
-- mandato_fim, entao esta rota nao passa por checagem nenhuma.
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000f9','aal2',
  $$update public.papeis set mandato_inicio=current_date+30 where id='50000000-0000-0000-0000-0000000000f9'$$),
  'ERRO[P0001]', 'F3 a unica editora nao consegue jogar o proprio mandato_inicio para o futuro');

-- E o papel pode simplesmente deixar de ser 'editor'. O trigger dispara em UPDATE OF mandato_fim,
-- entao trocar a coluna `papel` nao o aciona.
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000f9','aal2',
  $$update public.papeis set papel='morador' where id='50000000-0000-0000-0000-0000000000f9'$$),
  'ERRO[P0001]', 'F4 a unica editora nao consegue rebaixar o proprio papel para morador');

-- INVARIANTE, sem prescrever mecanismo: aconteca o que acontecer, tem de sobrar editor vigente.
select ok(
  exists (select 1 from public.papeis pa join public.pessoas pe on pe.id = pa.pessoa_id
           where pa.papel='editor' and pe.ativa and pa.mandato_inicio <= current_date
             and (pa.mandato_fim is null or pa.mandato_fim >= current_date)),
  'F5 depois de todas as tentativas de auto-trancamento, ainda existe editor vigente');

-- Rotas descobertas na 4a rodada. O trigger passou a disparar em UPDATE (sem `OF coluna`) e a
-- comparar o ESTADO RESULTANTE via public.eh_editor_vigente_linha(), entao qualquer caminho que
-- tire a linha de vigencia e pego — inclusive transferir o papel para uma pessoa inativa, que e
-- o unico que exige DOIS lookups de `pessoas.ativa` (antes/depois) para ser detectado.
insert into public.pessoas (id, nome, ativa) values
 ('20000000-0000-0000-0000-0000000000fa','Pessoa Inativa Alvo', false);

select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000f9','aal2',
  $$update public.papeis set pessoa_id='20000000-0000-0000-0000-0000000000fa'
     where id='50000000-0000-0000-0000-0000000000f9'$$),
  'ERRO[P0001]', 'F6 transferir o papel do ultimo editor para pessoa INATIVA e bloqueado');

select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000f9','aal2',
  $$update public.papeis set pessoa_id='20000000-0000-0000-0000-0000000000fa',
                             mandato_inicio=current_date-1
     where id='50000000-0000-0000-0000-0000000000f9'$$),
  'ERRO[P0001]', 'F7 transferir para inativa mexendo no mandato junto tambem e bloqueado');

-- "Designar" um editor numa pessoa inativa nao conta como designar ninguem.
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000f9','aal2',
  $$insert into public.papeis (pessoa_id,papel) values ('20000000-0000-0000-0000-0000000000fa','editor');
    update public.papeis set mandato_fim=current_date-1 where id='50000000-0000-0000-0000-0000000000f9'$$),
  'ERRO[P0001]', 'F8 dar papel de editor a uma pessoa INATIVA nao libera encerrar o proprio mandato');

-- A vigencia de editor tem de ser decidida num lugar so. Se cada trigger reescrever o predicado,
-- eles divergem — foi assim que a rota do mandato_inicio e a do papel escaparam na 3a rodada.
select ok( to_regprocedure('public.eh_editor_vigente_linha(public.papel,date,date,boolean)') is not null,
  'F9 existe UMA funcao que decide "esta linha e editor vigente" (predicado nao reescrito por trigger)');

-- Os dois triggers precisam disparar em UPDATE inteiro: vigiar `OF <coluna>` deixa de fora toda
-- coluna que ninguem lembrou de listar.
select is(
  (select coalesce(string_agg(t.tgname,',' order by t.tgname),'(nenhum)')
     from pg_trigger t join pg_class c on c.oid = t.tgrelid
    where c.relname in ('pessoas','papeis') and not t.tgisinternal
      and t.tgname like '%editor%' and t.tgattr <> ''::int2vector),
  '(nenhum)',
  'F10 os triggers do ultimo editor disparam em UPDATE inteiro, nao em UPDATE OF <coluna>');

-- ======================================================================
-- G. REVOGACAO NO MESMO DIA — achado de 2026-09-06, dono NAO e este arquivo
-- ======================================================================
-- O mandato tem granularidade de DIA (`mandato_inicio`/`mandato_fim` sao `date`, e a vigencia e
-- `mandato_fim >= current_date`), mas a autorizacao que ele concede e INSTANTANEA. Consequencia:
-- nao existe forma legal de revogar hoje um mandato aberto hoje.
--   `mandato_fim = current_date - 1`  -> `papeis_mandato_ck` recusa (fim < inicio).
--   `mandato_fim = current_date`      -> aceito, mas a pessoa segue vigente o dia inteiro.
--   `delete`                          -> negado a todos, de proposito (B6/B7).
--   reescrever `mandato_inicio`       -> falsifica o registro de quem foi editora e quando.
-- Com `editor` unica (D4), quem entrou por engano hoje fica com toda a escrita do sistema, em
-- AAL2, ate amanha. Isso e o oposto do "acesso cessa em vinculos.fim + 0 dias" que o SPEC §7
-- registra como veto do juridico-lgpd, e o cenario e banal: erro de cadastro, desistencia.
-- Os dois asserts abaixo sao TODO, nao vermelhos: o conserto e mudanca de MODELO DE DADOS
-- (SPEC §2) — cabe a ADR de `arquiteto` + `eng-supabase`, nao a este arquivo, e nao e regressao
-- desta migracao. Eles ficam visiveis no TAP toda rodada e viram verde-inesperado no dia do
-- conserto. O que este arquivo NAO faz e fingir que o buraco nao existe.
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
 ('00000000-0000-0000-0000-0000000000fb','00000000-0000-0000-0000-000000000000','authenticated','authenticated','p-hoje@t.local',now(),now());
insert into public.pessoas (id, auth_user_id, nome) values
 ('20000000-0000-0000-0000-0000000000fb','00000000-0000-0000-0000-0000000000fb','Editora Cadastrada Hoje Por Engano');
-- Segunda editora, para que os triggers do ULTIMO editor nao mascarem o resultado: aqui a
-- pergunta e sobre revogar, nao sobre auto-trancamento.
insert into public.papeis (id, pessoa_id, papel, mandato_inicio) values
 ('50000000-0000-0000-0000-0000000000fb','20000000-0000-0000-0000-0000000000fb','editor', current_date);

select todo_start('revogacao no mesmo dia nao e expressavel no schema (mandato e date, autorizacao e instantanea) — ADR de arquiteto/eng-supabase, ver docs/ops/divida-tecnica.md R4');

select is( pg_temp.tenta('postgres',null,null,
  $$update public.papeis set mandato_fim = current_date - 1
     where id='50000000-0000-0000-0000-0000000000fb'$$),
  'OK (1)',
  'G1 encerrar um mandato de editor aberto HOJE e operacao legitima e deveria ser aceita');

select is(
  (select public.eh_editor_vigente_linha(pa.papel, pa.mandato_inicio, current_date, pe.ativa)::text
     from public.papeis pa join public.pessoas pe on pe.id = pa.pessoa_id
    where pa.id='50000000-0000-0000-0000-0000000000fb'),
  'false',
  'G2 mandato encerrado HOJE deixa de ser vigente HOJE (SPEC §7: o acesso cessa em fim + 0 dias)');

select todo_end();

select * from finish();
rollback;
