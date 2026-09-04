-- ============================================================================
-- Breeze — auditoria de RLS/imutabilidade: lancamentos (ADR-0011) e audit.log (ADR-0013).
-- Pergunta do teste: existe ALGUM papel, inclusive service_role e o dono da tabela, capaz de
-- alterar ou de fazer desaparecer um lancamento ja publicado, ou uma linha da trilha?
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
select plan(34);

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
 ('00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','l-editor@t.local',now(),now()),
 ('00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','l-conselho@t.local',now(),now()),
 ('00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','l-mora@t.local',now(),now());

insert into public.unidades (id,bloco,numero,fracao_ideal) values
 ('10000000-0000-0000-0000-000000000101','','L101',1.0);
insert into public.pessoas (id,auth_user_id,nome,cpf_hash,cpf_enc,cpf_ultimos_digitos) values
 ('20000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-0000000000e1','Edna Editora',   decode(repeat('e1',32),'hex'),'\xAAE1'::bytea,'111'),
 ('20000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000c1','Carlos Conselho',null,null,null),
 ('20000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000a1','Ana Moradora',   null,null,null);
insert into public.vinculos (unidade_id,pessoa_id,tipo) values
 ('10000000-0000-0000-0000-000000000101','20000000-0000-0000-0000-0000000000a1','proprietario');
insert into public.papeis (pessoa_id,papel) values
 ('20000000-0000-0000-0000-0000000000e1','editor'),
 ('20000000-0000-0000-0000-0000000000c1','conselho'),
 ('20000000-0000-0000-0000-0000000000a1','morador');

insert into public.contas (id,codigo,nome,natureza,nivel,aceita_lancamento) values
 ('40000000-0000-0000-0000-000000000001','9','Raiz teste','despesa',1,false);
insert into public.contas (id,codigo,nome,natureza,nivel,conta_pai_id,aceita_lancamento) values
 ('40000000-0000-0000-0000-000000000002','9.01','Sub teste','despesa',2,'40000000-0000-0000-0000-000000000001',false);
insert into public.contas (id,codigo,nome,natureza,nivel,conta_pai_id,aceita_lancamento) values
 ('40000000-0000-0000-0000-000000000003','9.01.01','Folha teste','despesa',3,'40000000-0000-0000-0000-000000000002',true);

insert into public.documentos (id,tipo,titulo,storage_path,sha256,paginas,status,visibilidade,publicado_em,publicado_por) values
 ('30000000-0000-0000-0000-000000000002','balancete','Balancete de origem','l-bal.pdf',decode(repeat('02',32),'hex'),3,'publicado','autenticado',now(),'20000000-0000-0000-0000-0000000000e1');

insert into public.lancamentos (id,data_competencia,conta_id,historico,valor_centavos,tipo,documento_id,pagina_origem,criado_por) values
 ('60000000-0000-0000-0000-000000000001',date_trunc('month',current_date)::date,'40000000-0000-0000-0000-000000000003',
  'Despesa publicada no balancete',100000,'despesa','30000000-0000-0000-0000-000000000002',1,'20000000-0000-0000-0000-0000000000e1');

insert into public.lancamento_anexos (lancamento_id,storage_path,sha256,tipo,enviado_por) values
 ('60000000-0000-0000-0000-000000000001','l-anexo.pdf',decode(repeat('0a',32),'hex'),'nota_fiscal','20000000-0000-0000-0000-0000000000e1');

-- ======================================================================
-- A. lancamentos — UPDATE e DELETE para ninguem (as tres camadas do ADR-0011)
-- ======================================================================
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$update public.lancamentos set valor_centavos=1$$), 'ERRO[42501]', 'A1 morador nao altera lancamento');
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000c1','aal2',
  $$update public.lancamentos set valor_centavos=1$$), 'ERRO[42501]', 'A2 conselho nao altera lancamento');
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000e1','aal2',
  $$update public.lancamentos set valor_centavos=1$$), 'ERRO[42501]', 'A3 editor nao altera lancamento');
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000e1','aal2',
  $$delete from public.lancamentos$$), 'ERRO[42501]', 'A4 editor nao apaga lancamento');
select is( pg_temp.tenta('service_role',null,null,
  $$update public.lancamentos set valor_centavos=1$$), 'ERRO[42501]', 'A5 service_role nao altera lancamento');
select is( pg_temp.tenta('service_role',null,null,
  $$delete from public.lancamentos$$), 'ERRO[42501]', 'A6 service_role nao apaga lancamento');
-- Terceira camada: o trigger tem de alcancar ate o DONO da tabela.
select is( pg_temp.tenta('postgres',null,null,
  $$update public.lancamentos set valor_centavos=1$$), 'ERRO[P0001]', 'A7 nem o dono da tabela altera lancamento (trigger)');
select is( pg_temp.tenta('postgres',null,null,
  $$delete from public.lancamentos$$), 'ERRO[P0001]', 'A8 nem o dono da tabela apaga lancamento (trigger)');

-- ======================================================================
-- B. TRUNCATE — o buraco das tres camadas
-- ======================================================================
-- REVOKE nao alcanca service_role (que tem TRUNCATE por privilegio padrao), a policy nao se
-- aplica a TRUNCATE, e o trigger de imutabilidade e FOR EACH ROW: TRUNCATE nao dispara trigger
-- de linha. audit.log resolveu isso com um trigger STATEMENT-level; lancamentos nao tem.
select is( pg_temp.tenta('service_role',null,null,
  $$truncate public.lancamentos cascade$$),
  'ERRO[42501]', 'B1 service_role NAO pode TRUNCATE lancamentos');
select is( pg_temp.tenta('postgres',null,null,
  $$truncate public.lancamentos cascade$$),
  'ERRO[P0001]', 'B2 nem o dono da tabela pode TRUNCATE lancamentos');
select is( pg_temp.tenta('service_role',null,null,
  $$truncate public.pessoas cascade$$),
  'ERRO[42501]', 'B3 service_role NAO pode TRUNCATE pessoas');
select is( pg_temp.tenta('service_role',null,null,
  $$truncate public.papeis cascade$$),
  'ERRO[42501]', 'B4 service_role NAO pode TRUNCATE papeis (a raiz da autorizacao)');
select is( pg_temp.tenta('service_role',null,null,
  $$truncate public.cobrancas$$),
  'ERRO[42501]', 'B5 service_role NAO pode TRUNCATE cobrancas');
-- Nenhuma tabela auditada pode ter TRUNCATE concedido a service_role:
select is(
  (select coalesce(string_agg(c.relname,',' order by c.relname),'(nenhuma)')
     from pg_class c
    where c.relnamespace='public'::regnamespace and c.relkind='r'
      and has_table_privilege('service_role', c.oid, 'TRUNCATE')),
  '(nenhuma)',
  'B6 nenhuma tabela de public concede TRUNCATE a service_role');

-- ======================================================================
-- C. lancamentos — INSERT e estorno
-- ======================================================================
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$insert into public.lancamentos (data_competencia,conta_id,historico,valor_centavos,tipo,documento_id,pagina_origem,criado_por)
    values (date_trunc('month',current_date)::date,'40000000-0000-0000-0000-000000000003','fraude do morador',1,'despesa','30000000-0000-0000-0000-000000000002',1,'20000000-0000-0000-0000-0000000000a1')$$),
  'ERRO[42501]', 'C1 morador nao lanca');
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000c1','aal2',
  $$insert into public.lancamentos (data_competencia,conta_id,historico,valor_centavos,tipo,documento_id,pagina_origem,criado_por)
    values (date_trunc('month',current_date)::date,'40000000-0000-0000-0000-000000000003','conselho lancando',1,'despesa','30000000-0000-0000-0000-000000000002',1,'20000000-0000-0000-0000-0000000000c1')$$),
  'ERRO[42501]', 'C2 conselho nao lanca (fiscaliza, nao escritura)');
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000e1','aal1',
  $$insert into public.lancamentos (data_competencia,conta_id,historico,valor_centavos,tipo,documento_id,pagina_origem,criado_por)
    values (date_trunc('month',current_date)::date,'40000000-0000-0000-0000-000000000003','editor sem totp',1,'despesa','30000000-0000-0000-0000-000000000002',1,'20000000-0000-0000-0000-0000000000e1')$$),
  'ERRO[42501]', 'C3 editor em AAL1 nao lanca');
select is( pg_temp.executa('authenticated','00000000-0000-0000-0000-0000000000e1','aal2',
  $$insert into public.lancamentos (data_competencia,conta_id,historico,valor_centavos,tipo,documento_id,pagina_origem,criado_por,estorna_lancamento_id,motivo_estorno)
    values (date_trunc('month',current_date)::date,'40000000-0000-0000-0000-000000000003','estorno correto',-100000,'despesa','30000000-0000-0000-0000-000000000002',1,'20000000-0000-0000-0000-0000000000e1','60000000-0000-0000-0000-000000000001','erro de classificacao no balancete')$$),
  'OK (1)', 'C4 editor AAL2 estorna (a unica forma de corrigir, ADR-0011)');
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000e1','aal2',
  $$insert into public.lancamentos (data_competencia,conta_id,historico,valor_centavos,tipo,documento_id,pagina_origem,criado_por,estorna_lancamento_id,motivo_estorno)
    values (date_trunc('month',current_date)::date,'40000000-0000-0000-0000-000000000003','estorno torto',-1,'despesa','30000000-0000-0000-0000-000000000002',1,'20000000-0000-0000-0000-0000000000e1','60000000-0000-0000-0000-000000000001','valor diferente do alvo')$$),
  'ERRO[P0001]', 'C5 estorno de valor diferente do alvo e rejeitado pelo trigger');
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$insert into public.questionamentos (lancamento_id,autor_id,texto)
    values ('60000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-0000000000a1','texto suficientemente longo')$$),
  'ERRO[42501]', 'C6 morador nao abre questionamento (SPEC §6.4-bis: exigir contas e ato coletivo)');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select count(*)::text from public.lancamento_anexos$$),
  '0', 'C7 morador nao le lancamento_anexos (nota fiscal com CNPJ/endereco)');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select tem_comprovante::text from public.vw_lancamentos_com_comprovante
     where lancamento_id='60000000-0000-0000-0000-000000000001'$$),
  'true', 'C8 morador ve que o comprovante EXISTE pela view agregada (controle)');
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select count(*)::text from information_schema.columns
     where table_schema='public' and table_name='vw_lancamentos_com_comprovante'
       and column_name in ('storage_path','descricao','sha256','enviado_por')$$),
  '0', 'C9 a view agregada nao projeta storage_path/descricao/sha256/enviado_por');

-- ======================================================================
-- D. audit.log — fora do PostgREST, imutavel, permanente
-- ======================================================================
select is( pg_temp.tenta('anon',null,null,$$select 1 from audit.log limit 1$$),
  'ERRO[42501]', 'D1 anon nao alcanca o schema audit');
select is( pg_temp.tenta('authenticated','00000000-0000-0000-0000-0000000000e1','aal2',
  $$select 1 from audit.log limit 1$$),
  'ERRO[42501]', 'D2 nem o editor alcanca o schema audit');
select is( pg_temp.tenta('service_role',null,null,$$select 1 from audit.log limit 1$$),
  'ERRO[42501]', 'D3 service_role nao alcanca o schema audit');
select is( pg_temp.tenta('postgres',null,null,$$update audit.log set depois='{}'::jsonb$$),
  'ERRO[P0001]', 'D4 nem o dono altera audit.log');
select is( pg_temp.tenta('postgres',null,null,$$delete from audit.log$$),
  'ERRO[P0001]', 'D5 nem o dono apaga audit.log');
select is( pg_temp.tenta('postgres',null,null,$$truncate audit.log$$),
  'ERRO[P0001]', 'D6 nem o dono trunca audit.log (trigger statement-level)');
select is( (select depois->>'cpf_enc' from audit.log where tabela='pessoas' and acao='INSERT' order by seq desc limit 1),
  '[redigido]', 'D7 cpf_enc entra REDIGIDO na trilha (a trilha nao vira 2a copia do dado pessoal)');
select is( (select actor_papel from audit.log where tabela='lancamentos' and acao='INSERT' order by seq desc limit 1),
  'editor', 'D8 a trilha grava o papel VIGENTE do ator, nao o claim do JWT');

-- ======================================================================
-- E. audit.log — cadeia de hash
-- ======================================================================
-- A verificacao tem de dizer "integra" numa cadeia intacta. Hoje a linha genese grava
-- hash_anterior = NULL e verificar_cadeia compara contra '\x00': `NULL is distinct from '\x00'`
-- e sempre verdadeiro, a funcao reporta quebra na PRIMEIRA linha e retorna — sem nunca
-- inspecionar o resto. Alarme permanente = nenhuma deteccao.
select is(
  coalesce((select string_agg(v.seq::text||': '||v.motivo,'; ') from audit.verificar_cadeia() v),'CADEIA INTEGRA'),
  'CADEIA INTEGRA',
  'E1 verificar_cadeia() numa cadeia intacta reporta integridade (sem falso positivo na genese)');

select is(
  coalesce((select string_agg(v.seq::text||': '||v.motivo,'; ')
              from audit.verificar_cadeia((select min(seq)+1 from audit.log)) v),'CADEIA INTEGRA'),
  'CADEIA INTEGRA',
  'E2 ignorada a genese, a cadeia recomputada bate linha a linha (o esquema de hash e solido)');

-- Adultera uma linha do meio e confirma que a verificacao acusa.
alter table audit.log disable trigger audit_log_imutavel_linha;
update audit.log set depois = jsonb_set(coalesce(depois,'{}'::jsonb),'{adulterado}','true'::jsonb)
 where seq = (select max(seq)-1 from audit.log);
alter table audit.log enable trigger audit_log_imutavel_linha;
select isnt(
  coalesce((select string_agg(v.seq::text||': '||v.motivo,'; ')
              from audit.verificar_cadeia((select min(seq)+1 from audit.log)) v),'CADEIA INTEGRA'),
  'CADEIA INTEGRA',
  'E3 adulteracao de uma linha do meio e detectada pela recomputacao');

select * from finish();
rollback;
