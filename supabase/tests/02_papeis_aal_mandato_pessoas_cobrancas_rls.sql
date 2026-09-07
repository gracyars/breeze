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
--
-- ADR-0030 (2026-09-06): vigencia de papel e de vinculo virou intervalo MEIA-ABERTO EM INSTANTE
-- — `inicio <= now() and (fim is null or fim > now())`, colunas `timestamptz`. Este arquivo e o
-- dono do teste de aceitacao dessa mudanca (blocos G e H). Regra que passa a valer para todo
-- assert daqui em diante: NENHUM assert reescreve o predicado de vigencia; ou chama
-- `app.tem_papel`/`app.eh_editor` (o efeito) ou `public.eh_editor_vigente_linha` (o predicado).
-- Foi a copia do predicado em F0/F5 que envelheceu sozinha quando o predicado mudou — mesma
-- classe do R3, na forma "assert que copia o predicado em vez de exercita-lo".
-- ============================================================================
begin;
select plan(77);

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

-- A editora semeada abre mandato AGORA. E o estado normal do sistema, nao um caso de borda —
-- e depois do ADR-0030 `mandato_inicio` tem DEFAULT `now()`, entao a linha nasce com hora do dia
-- (ex.: 01:16:56), nao a meia-noite. Este ruido fica DE PROPOSITO sem data explicita: foi
-- exatamente esse valor que quebrou F0/F5 quando o assert comparava com `current_date`
-- (`01:16:56 <= 00:00:00` e falso). O morador continua com `current_date` para que o ruido
-- carregue as DUAS formas — a que a tela grava e a que os scripts de semeadura ainda gravam.
insert into public.papeis (pessoa_id, papel, mandato_inicio) values
 ('ff200000-0000-0000-0000-0000000000e0','editor', default),
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
 -- ADR-0030: `mandato_fim` e ponta EXCLUSIVA em instante. "Vencido ontem" e `current_date`
 -- (meia-noite de hoje), nao `current_date - 1` — e exatamente o que a migracao gravaria ao
 -- converter o antigo `date` `current_date - 1` pela regra `(fim + 1)::timestamptz`. Manter
 -- `current_date - 1` deixaria o ator vencido ha DOIS dias: o assert continuaria verde medindo
 -- um caso mais frouxo que o pretendido. A borda adversarial e o vencimento mais recente.
 ('20000000-0000-0000-0000-0000000000f1','conselho',current_date-60,current_date),
 ('20000000-0000-0000-0000-0000000000f1','editor',  current_date-60,current_date);

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
-- `mandato_inicio` explicito no passado (nao o default `now()`): a Solo e a editora ESTABELECIDA
-- que o bloco G entrega a gestao no fim do arquivo. Com o default, `greatest(inicio, now())` da
-- `fim = inicio` e a revogacao dela viraria intervalo vazio — que e outro caso, testado a parte.
insert into public.papeis (id, pessoa_id, papel, mandato_inicio) values
 ('50000000-0000-0000-0000-0000000000f9','20000000-0000-0000-0000-0000000000f9','editor', now() - interval '90 days');
-- Encerrar os outros mandatos e a PRE-CONDICAO do bloco F: os triggers que ele exercita leem a
-- tabela inteira, entao "Solo e a ultima editora" e um fato sobre o BANCO, nao sobre a fixture —
-- e nao da para escopar. O que da para fazer e CONSTRUIR a pre-condicao de forma legal e depois
-- CONFERIR que ela vale (F0 abaixo), em vez de supor.
--   Ate 2026-09-06 esta montagem precisava de um contorno — `mandato_inicio = least(mandato_inicio,
-- current_date - 60)` — porque encerrar um mandato aberto HOJE era inexprimivel: `mandato_fim =
-- current_date - 1` violava `papeis_mandato_ck` e abortava o arquivo. Recuar o inicio era legitimo
-- so por ser montagem de mundo de teste, e o contorno estava registrado como divida (R4).
--   O ADR-0030 criou a operacao de negocio correspondente, e a montagem passa a usa-la: encerrar
-- e `greatest(mandato_inicio, now())` — a mesma expressao que a tela grava para os motivos
-- instantaneos (§3). Nenhum `mandato_inicio` e reescrito: a montagem nao falsifica mais desde
-- quando cada uma foi editora. O filtro tambem deixa de copiar o predicado — chama o proprio.
update public.papeis pa
   set mandato_fim   = greatest(pa.mandato_inicio, now()),
       motivo_fim    = 'substituicao',
       encerrado_por = '20000000-0000-0000-0000-0000000000f9'
  from public.pessoas pe
 where pe.id = pa.pessoa_id
   and pa.pessoa_id <> '20000000-0000-0000-0000-0000000000f9'
   and public.eh_editor_vigente_linha(pa.papel, pa.mandato_inicio, pa.mandato_fim, pe.ativa);

-- Pre-condicao CONFERIDA, nao suposta: se um dia a montagem acima parar de produzir "so a Solo
-- vigente", F1-F8 passariam a medir outra coisa (o trigger do ultimo editor nem dispararia) e a
-- suite mentiria em verde. Este assert e o que impede isso.
--   Este assert CHAMA o predicado (`public.eh_editor_vigente_linha`) em vez de reescreve-lo, e a
-- razao e um defeito real, nao estilo. Ate 2026-09-06 ele copiava a formula
-- (`mandato_inicio <= current_date and (mandato_fim is null or mandato_fim >= current_date)`).
-- Quando o ADR-0030 trocou o predicado por `now()`/`>`, a COPIA nao mudou junto e passou a mentir:
-- `mandato_inicio` default virou `now()` (hora do dia) e `current_date` promove a meia-noite, entao
-- `01:16:56 <= 00:00:00` deu falso e o assert respondeu "(nenhuma)" — enquanto os triggers, que
-- chamam a funcao, viam a Solo vigente e barravam corretamente F1-F8. Assert e mecanismo
-- discordando: o assert e que estava errado. Chamar a funcao e o que impede o proximo
-- envelhecimento silencioso.
--   Usar aqui a MESMA funcao que os triggers usam e proposital: F0 e a pre-condicao de um bloco que
-- exercita esses triggers, e o que precisa valer e que o mundo esteja como O TRIGGER o ve. A
-- verificacao independente do mecanismo esta em F5, que mede pelo outro caminho (app.eh_editor).
select is(
  (select coalesce(string_agg(pe.nome,',' order by pe.nome),'(nenhuma)')
     from public.papeis pa join public.pessoas pe on pe.id = pa.pessoa_id
    where public.eh_editor_vigente_linha(pa.papel, pa.mandato_inicio, pa.mandato_fim, pe.ativa)),
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
--   Este mede o EFEITO, nao o estado do banco, e por dois motivos. (1) O que a D9/V10 protege nao
-- e "existe uma linha em papeis": e "alguem ainda consegue escrever". A pergunta certa e feita na
-- sessao, pelo caminho de autorizacao real. (2) F0 ja chama `eh_editor_vigente_linha` — se F5
-- chamasse tambem, um defeito NESSA funcao passaria despercebido pelos dois asserts e pelos dois
-- triggers ao mesmo tempo (co-falha). `app.eh_editor()` -> `app.tem_papel('editor')` e um caminho
-- independente: a primitiva de RLS, que nao consulta `eh_editor_vigente_linha`.
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000f9','aal2',
  $$select app.eh_editor()::text$$),
  'true',
  'F5 depois de todas as tentativas de auto-trancamento, a Solo AINDA e editora pelo caminho de autorizacao real');

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
--   Ate 2026-09-06 este assert checava `to_regprocedure` da assinatura ANTIGA
-- (`public.papel, date, date, boolean`), que o ADR-0030 dropou DE PROPOSITO. Estava certo no
-- espirito (uma funcao so) e errado na letra (a assinatura mudou). A forma abaixo nao amarra o
-- assert a uma assinatura escrita a mao no lugar errado: F9 conta, F9b confere qual sobrou.
--   Os dois juntos sao a armadilha nº2 do ADR-0030: `create or replace` com assinatura diferente
-- nao substitui, cria SOBRECARGA — a versao `date` ficaria viva, os triggers resolveriam por nome
-- e poderiam ligar na antiga, que compara `timestamptz` promovido contra `current_date` e erra em
-- silencio na guarda do ultimo editor. F9 sozinho pega a sobrecarga; F9b sozinho nao pegaria.
select is(
  (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname='public' and p.proname='eh_editor_vigente_linha'),
  '1',
  'F9 existe UMA funcao que decide "esta linha e editor vigente" — UMA, sem sobrecarga sobrevivente');

select is(
  (select coalesce(string_agg(format_type(t.oid, null), ',' order by k.ord),'(nenhuma)')
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
     cross join lateral unnest(p.proargtypes) with ordinality as k(oid, ord)
     join pg_type t on t.oid = k.oid
    where n.nspname='public' and p.proname='eh_editor_vigente_linha'),
  'papel,timestamp with time zone,timestamp with time zone,boolean',
  'F9b e a funcao que sobrou recebe INSTANTE, nao `date` (ADR-0030: `date` em predicado de autorizacao e o defeito)');

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
-- G. MATRIZ DE REVOGACAO — teste de aceitacao do ADR-0030
-- ======================================================================
-- Ate 2026-09-06 este bloco eram dois `todo` que registravam um buraco de MODELO: revogar hoje um
-- mandato aberto hoje nao existia como operacao (`fim = current_date - 1` violava
-- `papeis_mandato_ck`; `fim = current_date` era aceito e a pessoa seguia vigente o dia inteiro;
-- `delete` e negado a todos de proposito; reescrever `mandato_inicio` falsifica o registro).
-- A migracao 20260906160000_vigencia_em_instante.sql fechou o buraco. Os dois `todo` saem, mas
-- NAO da forma que estavam:
--   * G2 virou verde-inesperado e era o sinal esperado — mandato "encerrado hoje" deixou de ser
--     vigente. Ele passava, porem, passando `current_date` como ARGUMENTO literal em vez de ler a
--     coluna: media uma conta, nao a linha. Foi absorvido pelos asserts abaixo, que leem a linha.
--   * G1 continuava vermelho e NUNCA testou a operacao nova: usava literalmente
--     `mandato_fim = current_date - 1`, que viola o check (`ontem < hoje`) e sempre vai violar,
--     antes e depois da migracao. Acomodar o assert ao comportamento seria falso verde numa suite
--     de seguranca; o assert foi REESCRITO para exercitar a operacao que passou a existir.
--
-- TUDO AQUI RODA NA MESMA TRANSACAO, e isso e o teste, nao um detalhe de montagem: `now()` e
-- `transaction_timestamp()` e NAO anda dentro da transacao (o ADR-0030 §1 exige `now()` e proibe
-- `clock_timestamp()` justamente para os helpers seguirem STABLE). Logo "revogar com fim = now() e
-- deixar de ser reconhecida" e medido AQUI NO MESMO INSTANTE — nao "um pouco depois", nao "na
-- proxima consulta". Com o intervalo FECHADO anterior essa afirmacao era inexprimivel.
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
 ('00000000-0000-0000-0000-0000000000fb','00000000-0000-0000-0000-000000000000','authenticated','authenticated','p-hoje@t.local',now(),now()),
 ('00000000-0000-0000-0000-0000000000fc','00000000-0000-0000-0000-000000000000','authenticated','authenticated','p-futuro@t.local',now(),now()),
 ('00000000-0000-0000-0000-0000000000fd','00000000-0000-0000-0000-000000000000','authenticated','authenticated','p-nova@t.local',now(),now());
insert into public.pessoas (id, auth_user_id, nome) values
 ('20000000-0000-0000-0000-0000000000fb','00000000-0000-0000-0000-0000000000fb','Editora Cadastrada Hoje Por Engano'),
 ('20000000-0000-0000-0000-0000000000fc','00000000-0000-0000-0000-0000000000fc','Editora com Mandato Futuro'),
 ('20000000-0000-0000-0000-0000000000fd','00000000-0000-0000-0000-0000000000fd','Nova Editora da Substituicao');

-- Segunda editora, para que os triggers do ULTIMO editor nao mascarem o resultado: aqui a
-- pergunta e sobre REVOGAR, nao sobre auto-trancamento. `now() - interval '2 hours'` e o cenario
-- literal do ADR: cadastrada por engano de manha, revogada agora.
insert into public.papeis (id, pessoa_id, papel, mandato_inicio) values
 ('50000000-0000-0000-0000-0000000000fb','20000000-0000-0000-0000-0000000000fb','editor', now() - interval '2 hours');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000fb','aal2',
  $$select app.tem_papel('editor')::text$$),
  'true',
  'G1 controle: a editora cadastrada por engano E editora agora — sem isto, G3 passaria por vacuidade');

-- A OPERACAO QUE NAO EXISTIA. Feita pelo caminho de produto (a outra editora, em AAL2, pela
-- policy `papeis_update`), nao por `postgres`: revogar tem de ser operacao de produto, e nao
-- escalada para acesso direto ao banco (ADR-0030, Consequencias).
select is( pg_temp.executa('authenticated','00000000-0000-0000-0000-0000000000f9','aal2',
  $$update public.papeis
       set mandato_fim = now(), motivo_fim = 'erro_cadastral',
           encerrado_por = '20000000-0000-0000-0000-0000000000f9'
     where id='50000000-0000-0000-0000-0000000000fb'$$),
  'OK (1)',
  'G2 revogar AGORA um mandato aberto AGORA e operacao legitima (fim = now() satisfaz papeis_mandato_ck)');

-- O assert que o ADR-0030 pediu por nome (nota (c) ao auditor-rls) e que nao existia.
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000fb','aal2',
  $$select app.tem_papel('editor')::text$$),
  'false',
  'G3 NO MESMO INSTANTE (mesmo now(), mesma transacao) tem_papel ja devolve false — ponta final EXCLUSIVA');

-- Os dois lados do predicado tem de concordar: a primitiva de RLS (que autoriza) e a funcao dos
-- triggers (que guarda a INV-02). Se divergirem, uma das duas esta protegendo o que a outra abre.
select is(
  (select public.eh_editor_vigente_linha(pa.papel, pa.mandato_inicio, pa.mandato_fim, pe.ativa)::text
     from public.papeis pa join public.pessoas pe on pe.id = pa.pessoa_id
    where pa.id='50000000-0000-0000-0000-0000000000fb'),
  'false',
  'G4 o predicado dos triggers concorda com tem_papel sobre a linha revogada (nao ha dois predicados)');

-- E a revogacao nao apagou nem estreitou o passado: o inicio segue onde estava.
select is(
  (select (pa.mandato_inicio = now() - interval '2 hours')::text || '/' || (pa.mandato_fim = now())::text
     from public.papeis pa where pa.id='50000000-0000-0000-0000-0000000000fb'),
  'true/true',
  'G5 revogar escreveu o instante em que o poder cessou e NAO reescreveu o instante em que comecou');

-- ---------------------------------------------------------------------------
-- `inicio` no futuro: o caso que o parecer juridico corrigiu no §3 do ADR-0030.
-- ---------------------------------------------------------------------------
insert into public.papeis (id, pessoa_id, papel, mandato_inicio) values
 ('50000000-0000-0000-0000-0000000000fc','20000000-0000-0000-0000-0000000000fc','editor', now() + interval '30 days');

-- A primeira versao do §3 mandava gravar `now()` puro nos motivos instantaneos. Com `inicio` no
-- futuro isso REINTRODUZ pela tela o mesmissimo ERRO[23514] que o ADR existe para eliminar, agora
-- pela outra ponta. Este assert existe para que a regra `greatest()` nao seja "simplificada"
-- depois por alguem que nunca viu o erro acontecer.
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000f9','aal2',
  $$update public.papeis set mandato_fim = now() where id='50000000-0000-0000-0000-0000000000fc'$$),
  'ERRO[23514]',
  'G6 `now()` PURO com mandato_inicio no futuro VIOLA papeis_mandato_ck — e por isso a regra e greatest(), nao now()');

select is( pg_temp.executa('authenticated','00000000-0000-0000-0000-0000000000f9','aal2',
  $$update public.papeis
       set mandato_fim = greatest(mandato_inicio, now()), motivo_fim = 'erro_cadastral',
           encerrado_por = '20000000-0000-0000-0000-0000000000f9'
     where id='50000000-0000-0000-0000-0000000000fc'$$),
  'OK (1)',
  'G7 greatest(mandato_inicio, now()) e aceito exatamente onde now() puro falhou (ADR-0030 §3)');

select is(
  (select (pa.mandato_fim = pa.mandato_inicio)::text || '/' ||
          public.eh_editor_vigente_linha(pa.papel, pa.mandato_inicio, pa.mandato_fim, pe.ativa)::text
     from public.papeis pa join public.pessoas pe on pe.id = pa.pessoa_id
    where pa.id='50000000-0000-0000-0000-0000000000fc'),
  'true/false',
  'G8 o resultado e o intervalo VAZIO fim = inicio: a concessao fica registrada e nunca teve efeito');

-- Intervalo vazio tambem nasce legitimo no INSERT — a forma honesta de "cadastrei a pessoa errada
-- e desfiz antes que ela usasse", em vez de apagar a linha (que B6/B7 negam a todos).
select is( pg_temp.executa('authenticated','00000000-0000-0000-0000-0000000000f9','aal2',
  $$insert into public.papeis (id, pessoa_id, papel, mandato_inicio, mandato_fim, motivo_fim)
    values ('50000000-0000-0000-0000-0000000000ce','20000000-0000-0000-0000-0000000000fc','conselho',
            now(), now(), 'erro_cadastral')$$),
  'OK (1)',
  'G9 fim = inicio e aceito no INSERT: registra a concessao desfeita em vez de apagar a linha');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000fc','aal2',
  $$select app.tem_papel('conselho')::text$$),
  'false',
  'G10 e o intervalo vazio nao concede NADA nem no instante em que foi escrito');

-- ---------------------------------------------------------------------------
-- Troca de editora: a ordem e obrigatoria, e a ordem inversa TEM de falhar (ADR-0030 §6).
-- ---------------------------------------------------------------------------
-- Neste ponto a Solo voltou a ser a unica editora vigente (fb e fc revogadas). Revogar a antiga
-- ANTES de conceder a nova faz o trigger contar as linhas visiveis, achar zero e recusar. Nao e
-- bug a contornar: e a INV-02 impedindo o sistema de passar por zero editor.
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000f9','aal2',
  $$update public.papeis
       set mandato_fim = greatest(mandato_inicio, now()), motivo_fim = 'substituicao',
           encerrado_por = '20000000-0000-0000-0000-0000000000fd'
     where id='50000000-0000-0000-0000-0000000000f9'$$),
  'ERRO[P0001]',
  'G11 ordem INVERSA (revogar a antiga antes de conceder a nova) falha — e e correto que falhe');

-- A ordem obrigatoria, numa transacao so: INSERT da nova -> UPDATE da antiga. A contagem faz
-- 1 -> 2 -> 1 e nunca passa por zero, que e o que a INV-02 (piso, nao igualdade) exige.
select is( pg_temp.executa('authenticated','00000000-0000-0000-0000-0000000000f9','aal2',
  $$insert into public.papeis (id, pessoa_id, papel)
      values ('50000000-0000-0000-0000-0000000000fd','20000000-0000-0000-0000-0000000000fd','editor');
    update public.papeis
       set mandato_fim = greatest(mandato_inicio, now()), motivo_fim = 'substituicao',
           encerrado_por = '20000000-0000-0000-0000-0000000000fd'
     where id='50000000-0000-0000-0000-0000000000f9'$$),
  'OK (1)',
  'G12 ordem OBRIGATORIA (INSERT da nova -> UPDATE da antiga) passa, na mesma transacao');

-- A promessa central do §6, medida nos dois lados no MESMO now(): sem gap e sem sobreposicao.
-- A nova nasceu com o DEFAULT `now()` — `inicio <= now()` e verdadeiro porque a ponta inicial e
-- INCLUSIVA; a antiga tem `fim = now()` e ja nao vale porque a final e EXCLUSIVA. Com intervalo
-- fechado as duas coisas nao podem ser verdade ao mesmo tempo: uma das duas mente.
select is(
  pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000fd','aal2',$$select app.tem_papel('editor')::text$$)
  || '/' ||
  pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000f9','aal2',$$select app.tem_papel('editor')::text$$),
  'true/false',
  'G13 no MESMO instante a nova JA e editora e a antiga JA nao e — sem gap e sem sobreposicao');

select is(
  (select coalesce(string_agg(pe.nome,',' order by pe.nome),'(nenhuma)')
     from public.papeis pa join public.pessoas pe on pe.id = pa.pessoa_id
    where public.eh_editor_vigente_linha(pa.papel, pa.mandato_inicio, pa.mandato_fim, pe.ativa)),
  'Nova Editora da Substituicao',
  'G14 depois da troca ha EXATAMENTE UMA editora vigente no banco, e e a nova (D4 preservada)');

-- §5: `papeis` ganhou a simetria que `vinculos` ja tinha. Sem isto, a pergunta que mais importa
-- na resposta a incidente ("foi erro de cadastro, entrega de gestao ou conta comprometida?") nao
-- tem resposta na linha.
select is(
  (select pa.motivo_fim::text || ' por ' || pe.nome
     from public.papeis pa join public.pessoas pe on pe.id = pa.encerrado_por
    where pa.id='50000000-0000-0000-0000-0000000000f9'),
  'substituicao por Nova Editora da Substituicao',
  'G15 a revogacao registra QUEM encerrou e POR QUE (papeis.encerrado_por/motivo_fim, ADR-0030 §5)');

-- E o campo que existe para ser lido na auditoria nao pode ser o unico ilegivel nela: `motivo_fim`
-- e enum fechado exatamente para entrar em `audit.colunas_liberadas`. Se alguem trocar por texto
-- livre, sai `[REDIGIDO]` e este assert quebra.
select is(
  (select l.depois->>'motivo_fim' from audit.log l
    where l.tabela='papeis' and l.acao='UPDATE'
      and l.registro_id='50000000-0000-0000-0000-0000000000f9'
    order by l.seq desc limit 1),
  'substituicao',
  'G16 motivo_fim entra LEGIVEL na trilha (audit.colunas_liberadas), nao [REDIGIDO]');

-- ======================================================================
-- H. A CONVERSAO DE TIPO NAO REVOGOU NEM ESTENDEU NINGUEM (ADR-0030, passo 3)
-- ======================================================================
-- A migracao traz a propria sanidade ("a contagem de vigentes antes e depois tem de bater"), mas
-- ela rodou sobre um banco que `supabase db reset` acabara de esvaziar dessas linhas: comparou
-- zero com zero. Isso e verdadeiro e vazio — nao prova nada sobre a aritmetica da conversao, e o
-- proprio eng-supabase registrou que nao provava. O passo 3 e "o passo que nao pode sair errado",
-- e no dia em que houver um projeto hospedado (divida D2) e este arquivo que rodara antes.
--   Aqui a pre-migracao e RECONSTRUIDA em `date` — as colunas reais ja sao `timestamptz` e nao
-- aceitam mais o estado antigo, entao a unica prova honesta e reaplicar as duas semanticas sobre
-- os mesmos valores. As expressoes usadas sao literalmente as da migracao:
--   inicio -> inicio::timestamptz          |  fim -> (fim + 1)::timestamptz
create temporary table _pre_adr0030 (quem text primary key, inicio date, fim date);
insert into _pre_adr0030 (quem, inicio, fim) values
 ('a -60 / aberto',      current_date-60, null),
 ('b -60 / -60',         current_date-60, current_date-60),
 ('c -60 / ontem',       current_date-60, current_date-1),
 ('d -60 / HOJE',        current_date-60, current_date),    -- a borda: era vigente o dia inteiro
 ('e -60 / amanha',      current_date-60, current_date+1),
 ('f -60 / +60',         current_date-60, current_date+60),
 ('g ontem / aberto',    current_date-1,  null),
 ('h ontem / HOJE',      current_date-1,  current_date),
 ('i HOJE / aberto',     current_date,    null),
 ('j HOJE / HOJE',       current_date,    current_date),     -- concedido e revogado no mesmo dia
 ('k HOJE / amanha',     current_date,    current_date+1),
 ('l amanha / aberto',   current_date+1,  null),
 ('m amanha / +60',      current_date+1,  current_date+60),
 ('n +60 / aberto',      current_date+60, null),
 ('o -60 / -1 dia extra',current_date-60, current_date-2);

create temporary view _conv as
select quem,
       -- predicado ANTIGO, sobre os valores `date` originais (fechado, em dias)
       (inicio <= current_date and (fim is null or fim >= current_date))                    as vigente_antes,
       -- predicado NOVO sobre a conversao DA MIGRACAO (meia-aberto, em instante)
       (inicio::timestamptz <= now()
        and ((fim + 1)::timestamptz is null or (fim + 1)::timestamptz > now()))             as vigente_depois,
       -- contrafactual 1: cast direto na ponta de fim, sem o `+ 1` (a armadilha nº1 do ADR)
       (inicio::timestamptz <= now()
        and (fim::timestamptz is null or fim::timestamptz > now()))                         as vigente_sem_mais_um,
       -- contrafactual 2: `+ 1` tambem na ponta de inicio (a assimetria e proposital)
       ((inicio + 1)::timestamptz <= now()
        and ((fim + 1)::timestamptz is null or (fim + 1)::timestamptz > now()))             as vigente_com_mais_um_no_inicio
  from _pre_adr0030;

-- H1 e a prova pedida. `(nenhum)` significa: para TODA linha reconstruida, quem era vigente antes
-- e vigente depois, e quem nao era continua nao sendo. Nenhum periodo estreitado, nenhum alargado.
select is(
  (select coalesce(string_agg(quem, ', ' order by quem),'(nenhum)')
     from _conv where vigente_antes is distinct from vigente_depois),
  '(nenhum)',
  'H1 a conversao da migracao preserva a vigencia de TODA linha pre-existente (ontem, hoje, amanha, +-60)');

-- H1 so vale se a fixture exercitar os dois resultados. Uma fixture toda vigente (ou toda vencida)
-- faria H1 passar por vacuidade — que e a forma classica de um assert de conversao mentir.
select is(
  (select coalesce(string_agg(quem, ',' order by quem),'(nenhum)') from _conv where vigente_antes),
  'a -60 / aberto,d -60 / HOJE,e -60 / amanha,f -60 / +60,g ontem / aberto,h ontem / HOJE,i HOJE / aberto,j HOJE / HOJE,k HOJE / amanha',
  'H2 a fixture nao e vacua: 9 das 15 linhas eram vigentes antes da conversao, 6 nao eram');

-- Contrafactual: o `+ 1` da ponta de fim e carga util, nao enfeite. Sem ele, todo mandato/vinculo
-- que terminava HOJE seria revogado retroativamente — um dia inteiro de todo mundo, em silencio,
-- na direcao permissiva ao contrario. Este assert e o que da dentes a H1.
select is(
  (select coalesce(string_agg(quem, ',' order by quem),'(nenhum)')
     from _conv where vigente_antes is distinct from vigente_sem_mais_um),
  'd -60 / HOJE,h ontem / HOJE,j HOJE / HOJE',
  'H3 contrafactual: `fim::timestamptz` sem o `+ 1` REVOGARIA retroativamente quem terminava hoje');

-- Contrafactual simetrico: a ponta de inicio converte DIRETO porque ja era inclusiva nas duas
-- semanticas. Aplicar `+ 1` nela tambem (a "simetria" que alguem proporia) atrasaria o inicio de
-- todo mundo em um dia — negando acesso a quem comecou hoje.
select is(
  (select coalesce(string_agg(quem, ',' order by quem),'(nenhum)')
     from _conv where vigente_antes is distinct from vigente_com_mais_um_no_inicio),
  'i HOJE / aberto,j HOJE / HOJE,k HOJE / amanha',
  'H4 contrafactual: `(inicio + 1)` negaria acesso a quem comecou HOJE — a assimetria da conversao e proposital');

-- A aritmetica acima prova que os PREDICADOS concordam. Falta ligar isso as FUNCOES reais: o valor
-- convertido, gravado na coluna de verdade, tem de produzir a mesma resposta de
-- `app.eh_autenticado()` que o `date` original produzia. Duas pessoas, as duas bordas vizinhas —
-- `fim = HOJE` (era vigente o dia inteiro) e `fim = ONTEM` (ja nao era), cujos valores convertidos
-- sao `(HOJE+1) 00:00` e `HOJE 00:00`. Sao os dois lados do mesmo corte: se a conversao tivesse
-- deslizado um dia, as duas respostas trocariam de lugar e H5/H6 quebrariam JUNTOS.
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
 ('00000000-0000-0000-0000-0000000000ea','00000000-0000-0000-0000-000000000000','authenticated','authenticated','p-conv-vig@t.local',now(),now()),
 ('00000000-0000-0000-0000-0000000000eb','00000000-0000-0000-0000-000000000000','authenticated','authenticated','p-conv-fora@t.local',now(),now());
insert into public.unidades (id, bloco, numero, fracao_ideal) values
 ('10000000-0000-0000-0000-000000000104','','T104',0.01),
 ('10000000-0000-0000-0000-000000000105','','T105',0.01);
insert into public.pessoas (id, auth_user_id, nome) values
 ('20000000-0000-0000-0000-0000000000ea','00000000-0000-0000-0000-0000000000ea','Convertida Vigente'),
 ('20000000-0000-0000-0000-0000000000eb','00000000-0000-0000-0000-0000000000eb','Convertida Ja Fora');
insert into public.vinculos (unidade_id, pessoa_id, tipo, inicio, fim) values
 -- pre-migracao: inicio = -60, fim = HOJE  -> conversao da migracao: (HOJE + 1) 00:00
 ('10000000-0000-0000-0000-000000000104','20000000-0000-0000-0000-0000000000ea','proprietario',
  (current_date-60)::timestamptz, (current_date + 1)::timestamptz),
 -- pre-migracao: inicio = -60, fim = ONTEM -> conversao da migracao: HOJE 00:00
 ('10000000-0000-0000-0000-000000000105','20000000-0000-0000-0000-0000000000eb','proprietario',
  (current_date-60)::timestamptz, current_date::timestamptz);

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000ea','aal1',
  $$select app.eh_autenticado()::text$$),
  'true',
  'H5 quem tinha `fim = HOJE` em date (vigente o dia inteiro) SEGUE autenticado depois da conversao');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000eb','aal1',
  $$select app.eh_autenticado()::text$$),
  'false',
  'H6 e quem tinha `fim = ONTEM` continua FORA — a conversao nao alargou vigencia de ninguem');

-- Fecho da INV-14 pelo comportamento, nao so pelo catalogo: a migracao varre `pg_proc` do schema
-- `app` atras de `current_date`, mas a varredura nao alcanca `public.eh_editor_vigente_linha`, que
-- e onde a comparacao de vigencia tambem mora e onde a sobrecarga `date` teria sobrevivido.
select is(
  (select coalesce(string_agg(p.proname, ',' order by p.proname),'(nenhuma)')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('app','public')
      and p.proname in ('tem_papel','eh_autenticado','unidades_da_pessoa','eh_editor_vigente_linha',
                        'papel_atual','eh_editor','eh_gestao','pessoa_atual')
      and pg_get_functiondef(p.oid) ilike '%current_date%'),
  '(nenhuma)',
  'H7 INV-14: nenhuma funcao de autorizacao (inclusive eh_editor_vigente_linha, fora do schema app) compara vigencia com current_date');

select * from finish();
rollback;
