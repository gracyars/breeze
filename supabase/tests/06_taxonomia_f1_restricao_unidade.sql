-- ============================================================================
-- Breeze — F1: taxonomia documental do acervo real (docs/dominio/taxonomia-documental-decisoes.md)
-- Alvo: as duas travas novas de 20260906090100 —
--   (1) demonstrativo_cota/comunicado vinculado a uma unidade em documento_unidades nunca pode
--       circular como `autenticado` (§5 da entrada de domínio) — testado nos DOIS LADOS
--       (vínculo criado antes vs. visibilidade rebaixada depois, ADR-0021);
--   (2) deliberacoes.documento_id nunca ancora em resumo_assembleia, só em ata_assembleia (§3);
-- e o catálogo novo de 20260906090000 (5 tipos_documento).
--
-- Mesmo método dos demais arquivos: auto-contido, `begin`/`rollback`, impersonação por
-- pg_temp.probe/tenta/executa (ver comentário completo em
-- supabase/tests/01_visibilidade_documento_pagina_chunk_rls.sql).
-- Atores: ...e1 editor | ...a1 morador un.201 | ...b1 morador un.202
-- ============================================================================
begin;
select plan(26);

-- ---------------------------------------------------------------- helpers --
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
  return coalesce(r, '(vazio)');
end $f$;

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
 ('00000000-0000-0000-0000-0000000000e2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','tax-editor@t.local',now(),now()),
 ('00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','tax-mora201@t.local',now(),now()),
 ('00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','tax-mora202@t.local',now(),now());

insert into public.unidades (id, bloco, numero, fracao_ideal) values
 ('11000000-0000-0000-0000-000000000201','','TX201',0.5),
 ('11000000-0000-0000-0000-000000000202','','TX202',0.5);

insert into public.pessoas (id, auth_user_id, nome) values
 ('21000000-0000-0000-0000-0000000000e2','00000000-0000-0000-0000-0000000000e2','Edna Editora F1'),
 ('21000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-0000000000a2','Ana da 201'),
 ('21000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000b2','Bruno da 202');

insert into public.vinculos (unidade_id, pessoa_id, tipo) values
 ('11000000-0000-0000-0000-000000000201','21000000-0000-0000-0000-0000000000a2','proprietario'),
 ('11000000-0000-0000-0000-000000000202','21000000-0000-0000-0000-0000000000b2','proprietario');

insert into public.papeis (pessoa_id, papel) values
 ('21000000-0000-0000-0000-0000000000e2','editor'),
 ('21000000-0000-0000-0000-0000000000a2','morador'),
 ('21000000-0000-0000-0000-0000000000b2','morador');

-- Documentos:
--   DC1: demonstrativo_cota RESTRITO, vinculado a 201 (caminho correto)
--   DC2: demonstrativo_cota AUTENTICADO, sem vinculo (agregado do condominio — permitido)
--   DC3: demonstrativo_cota RESTRITO, sem vinculo ainda (usado no teste de INSERT do vinculo)
--   CM1: comunicado RESTRITO, vinculado a 201 (caminho correto)
--   CM2: comunicado AUTENTICADO, sem vinculo (aviso geral — permitido)
--   NM1: notificacao_multa AUTENTICADO (controle: tipo FORA do escopo da trava nova)
--   ATA1: ata_assembleia AUTENTICADO (ancora valida de deliberacao)
--   RES1: resumo_assembleia AUTENTICADO (ancora invalida de deliberacao)
insert into public.documentos (id,tipo,titulo,storage_path,sha256,paginas,status,visibilidade,
                               publicado_em,publicado_por) values
 ('31000000-0000-0000-0000-000000000001','demonstrativo_cota','Demonstrativo 201 fev/2026','tx-dc1.pdf',decode(repeat('a1',32),'hex'),1,'publicado','restrito',now(),'21000000-0000-0000-0000-0000000000e2'),
 ('31000000-0000-0000-0000-000000000002','demonstrativo_cota','Demonstrativo agregado fev/2026','tx-dc2.pdf',decode(repeat('a2',32),'hex'),1,'publicado','autenticado',now(),'21000000-0000-0000-0000-0000000000e2'),
 ('31000000-0000-0000-0000-000000000003','demonstrativo_cota','Demonstrativo 202 mar/2026','tx-dc3.pdf',decode(repeat('a3',32),'hex'),1,'publicado','restrito',now(),'21000000-0000-0000-0000-0000000000e2'),
 ('31000000-0000-0000-0000-000000000004','comunicado','Comunicado cota atrasada 201','tx-cm1.pdf',decode(repeat('a4',32),'hex'),1,'publicado','restrito',now(),'21000000-0000-0000-0000-0000000000e2'),
 ('31000000-0000-0000-0000-000000000005','comunicado','Comunicado churrasqueira reabriu','tx-cm2.pdf',decode(repeat('a5',32),'hex'),1,'publicado','autenticado',now(),'21000000-0000-0000-0000-0000000000e2'),
 ('31000000-0000-0000-0000-000000000006','notificacao_multa','Multa barulho 201','tx-nm1.pdf',decode(repeat('a6',32),'hex'),1,'publicado','autenticado',now(),'21000000-0000-0000-0000-0000000000e2'),
 ('31000000-0000-0000-0000-000000000007','ata_assembleia','Ata AGE 04.02.2026','tx-ata1.pdf',decode(repeat('a7',32),'hex'),1,'publicado','autenticado',now(),'21000000-0000-0000-0000-0000000000e2'),
 ('31000000-0000-0000-0000-000000000008','resumo_assembleia','Resumo AGE 04.02.2026','tx-res1.pdf',decode(repeat('a8',32),'hex'),1,'publicado','autenticado',now(),'21000000-0000-0000-0000-0000000000e2');

insert into public.documento_unidades (documento_id, unidade_id) values
 ('31000000-0000-0000-0000-000000000001','11000000-0000-0000-0000-000000000201'),
 ('31000000-0000-0000-0000-000000000004','11000000-0000-0000-0000-000000000201');

insert into public.documento_paginas (documento_id,pagina,texto) values
 ('31000000-0000-0000-0000-000000000001',1,'DEMONSTRATIVO DA 201'),
 ('31000000-0000-0000-0000-000000000002',1,'DEMONSTRATIVO AGREGADO'),
 ('31000000-0000-0000-0000-000000000004',1,'COMUNICADO COTA DA 201'),
 ('31000000-0000-0000-0000-000000000005',1,'COMUNICADO CHURRASQUEIRA');

insert into public.assembleias (id, tipo, data, ata_documento_id) values
 ('41000000-0000-0000-0000-000000000001','age','2026-02-04','31000000-0000-0000-0000-000000000007');

-- ======================================================================
-- A. Trave de visibilidade — demonstrativo_cota/comunicado vinculado a unidade
-- ======================================================================
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a2','aal1',
  $$select count(*)::text from public.documentos where id='31000000-0000-0000-0000-000000000001'$$),
  '1', 'A1 morador da 201 ve o proprio demonstrativo de cota restrito');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000b2','aal1',
  $$select count(*)::text from public.documentos where id='31000000-0000-0000-0000-000000000001'$$),
  '0', 'A2 morador da 202 NAO ve o demonstrativo de cota restrito da 201');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000b2','aal1',
  $$select count(*)::text from public.documento_paginas where documento_id='31000000-0000-0000-0000-000000000001'$$),
  '0', 'A3 ARMADILHA Nº1: morador da 202 tambem nao le a PAGINA do demonstrativo da 201');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a2','aal1',
  $$select count(*)::text from public.documentos where id='31000000-0000-0000-0000-000000000002'$$),
  '1', 'A4 demonstrativo agregado (sem vinculo, autenticado) e visivel a qualquer morador');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000b2','aal1',
  $$select count(*)::text from public.documentos where id='31000000-0000-0000-0000-000000000002'$$),
  '1', 'A5 mesmo controle A4, pelo morador da outra unidade');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a2','aal1',
  $$select count(*)::text from public.documentos where id='31000000-0000-0000-0000-000000000004'$$),
  '1', 'A6 morador da 201 ve o comunicado individual restrito a ela');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000b2','aal1',
  $$select count(*)::text from public.documentos where id='31000000-0000-0000-0000-000000000004'$$),
  '0', 'A7 morador da 202 NAO ve o comunicado individual restrito a 201');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000b2','aal1',
  $$select count(*)::text from public.documento_paginas where documento_id='31000000-0000-0000-0000-000000000004'$$),
  '0', 'A8 ARMADILHA Nº1: morador da 202 tambem nao le a PAGINA do comunicado da 201');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000b2','aal1',
  $$select count(*)::text from public.documentos where id='31000000-0000-0000-0000-000000000005'$$),
  '1', 'A9 comunicado geral (sem vinculo, autenticado) e visivel a qualquer morador');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000e2','aal2',
  $$select count(*)::text from public.documentos where id='31000000-0000-0000-0000-000000000001'$$),
  '1', 'A10 editor (gestao, AAL2) ve o demonstrativo restrito de qualquer unidade');

-- ======================================================================
-- B. Trigger lado 1 — vincular unidade exige visibilidade ja RESTRITA
-- ======================================================================
select is( pg_temp.tenta('postgres',null,null,
  $$insert into public.documento_unidades (documento_id, unidade_id)
    values ('31000000-0000-0000-0000-000000000002','11000000-0000-0000-0000-000000000201')$$),
  'ERRO[P0001]',
  'B1 vincular unidade a demonstrativo_cota AUTENTICADO (DC2) e rejeitado');

select is( pg_temp.tenta('postgres',null,null,
  $$insert into public.documento_unidades (documento_id, unidade_id)
    values ('31000000-0000-0000-0000-000000000005','11000000-0000-0000-0000-000000000201')$$),
  'ERRO[P0001]',
  'B2 vincular unidade a comunicado AUTENTICADO (CM2) e rejeitado');

select is( pg_temp.tenta('postgres',null,null,
  $$insert into public.documento_unidades (documento_id, unidade_id)
    values ('31000000-0000-0000-0000-000000000003','11000000-0000-0000-0000-000000000202')$$),
  'OK (1)',
  'B3 controle: vincular unidade a demonstrativo_cota JA restrito (DC3) e aceito');

select is( pg_temp.tenta('postgres',null,null,
  $$insert into public.documento_unidades (documento_id, unidade_id)
    values ('31000000-0000-0000-0000-000000000006','11000000-0000-0000-0000-000000000201')$$),
  'OK (1)',
  'B4 controle de escopo: notificacao_multa AUTENTICADO aceita vinculo (tipo fora da trava nova — gap pre-existente, nao desta rodada)');

-- ======================================================================
-- C. Trigger lado 2 — rebaixar visibilidade e rejeitado enquanto o vinculo existir
-- ======================================================================
select is( pg_temp.tenta('postgres',null,null,
  $$update public.documentos set visibilidade='autenticado'
     where id='31000000-0000-0000-0000-000000000001'$$),
  'ERRO[P0001]',
  'C1 rebaixar demonstrativo_cota vinculado (DC1) para autenticado e rejeitado');

select is( pg_temp.tenta('postgres',null,null,
  $$update public.documentos set visibilidade='autenticado'
     where id='31000000-0000-0000-0000-000000000004'$$),
  'ERRO[P0001]',
  'C2 rebaixar comunicado vinculado (CM1) para autenticado e rejeitado');

select is( pg_temp.executa('postgres',null,null,
  $$update public.documentos set visibilidade='conselho'
     where id='31000000-0000-0000-0000-000000000002'$$),
  'OK (1)',
  'C3 controle: rebaixar demonstrativo_cota SEM vinculo (DC2) e escrita legitima, nao bloqueada');

-- ======================================================================
-- D. Catalogo — 5 tipos novos de tipos_documento
-- ======================================================================
select is( (select count(*)::text from public.tipos_documento
             where codigo in ('resumo_assembleia','material_apoio_assembleia',
                              'comunicado_governanca','demonstrativo_cota','documento_construtora')),
  '5', 'D1 os 5 tipos novos existem em tipos_documento');

select is( (select count(*)::text from public.tipos_documento
             where codigo in ('resumo_assembleia','material_apoio_assembleia',
                              'comunicado_governanca','demonstrativo_cota','documento_construtora')
               and visibilidade_padrao = 'autenticado' and permite_publico = false),
  '5', 'D2 todos os 5 nascem autenticado/nao-publico (nenhum vira publico por omissao)');

select is( (select visibilidade_padrao::text from public.tipos_documento where codigo='comunicado'),
  'autenticado', 'D3 regressao: comunicado (tipo ja existente) continua autenticado, linha intocada');

select is( (select retencao_meses::text from public.tipos_documento where codigo='comunicado'),
  '24', 'D4 regressao: retencao de comunicado continua 24 meses, linha intocada');

-- ======================================================================
-- E. Enum tipo_assembleia — 'agi' ja presente (verifica, nao reintroduz)
-- ======================================================================
select is( (select 'agi' = any(enum_range(null::public.tipo_assembleia)::text[]))::text,
  'true', 'E1 valor agi ja existe em public.tipo_assembleia (baseline F0, nao desta migracao)');

-- ======================================================================
-- F. Ancora de citacao — deliberacoes.documento_id so aponta para ata_assembleia
-- ======================================================================
-- F1 usa `executa` (persiste), nao `tenta` (desfaz): F4 precisa desta linha viva para tentar
-- rechear o documento_id dela com um resumo.
select is( pg_temp.executa('postgres',null,null,
  $$insert into public.deliberacoes (assembleia_id, item, descricao, resultado, documento_id, pagina, trecho_literal)
    values ('41000000-0000-0000-0000-000000000001',1,'Aprovacao de contas','aprovado',
            '31000000-0000-0000-0000-000000000007',1,'texto da ata')$$),
  'OK (1)',
  'F1 ancorar deliberacao em ata_assembleia (documento correto) e aceito');

select is( pg_temp.tenta('postgres',null,null,
  $$insert into public.deliberacoes (assembleia_id, item, descricao, resultado, documento_id, pagina, trecho_literal)
    values ('41000000-0000-0000-0000-000000000001',2,'Aprovacao de contas (via resumo)','aprovado',
            '31000000-0000-0000-0000-000000000008',1,'texto do resumo')$$),
  'ERRO[P0001]',
  'F2 ancorar deliberacao em resumo_assembleia e rejeitado');

select is( pg_temp.tenta('postgres',null,null,
  $$insert into public.deliberacoes (assembleia_id, item, descricao, resultado)
    values ('41000000-0000-0000-0000-000000000001',3,'Item sem documento citado','aprovado')$$),
  'OK (1)',
  'F3 deliberacao sem documento_id (null) continua aceita — a trava so olha quando ha citacao');

select is( pg_temp.tenta('postgres',null,null,
  $$update public.deliberacoes set documento_id='31000000-0000-0000-0000-000000000008', pagina=1
     where assembleia_id='41000000-0000-0000-0000-000000000001' and item=1$$),
  'ERRO[P0001]',
  'F4 mudar uma deliberacao ja ancorada em ata para apontar para resumo tambem e rejeitado');

select * from finish();
rollback;
