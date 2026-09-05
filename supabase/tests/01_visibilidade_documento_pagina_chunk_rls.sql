-- ============================================================================
-- Breeze — auditoria de RLS: ARMADILHA Nº1 (SPEC §7, §8.1) sob o modelo do PISO (ADR-0019/D13).
-- Alvo: documentos / documento_paginas / chunks / storage.objects.
-- Método: tentar chegar ao TEXTO (ou ao ARQUIVO) de conteúdo restrito sem tocar em `documentos`.
--
-- MODELO NOVO (reescrito na 2ª rodada de auditoria): documentos.visibilidade é o PISO — o nível
-- MAIS RESTRITIVO do documento inteiro. Página só pode ser IGUAL ou MAIS PERMISSIVA.
-- Ordem de permissividade: conselho(0) < restrito(1) < autenticado(2) < publico(3).
-- Por isso "ata que embute o regimento" nasce `autenticado` com páginas `publico` por override,
-- e "convenção com anexo sigiloso" nasce `conselho` com páginas `publico` — nunca o contrário.
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
select plan(47);

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
 ('00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','rls-editor@t.local',now(),now()),
 ('00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','rls-conselho@t.local',now(),now()),
 ('00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','rls-mora@t.local',now(),now()),
 ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','rls-morb@t.local',now(),now());

insert into public.unidades (id, bloco, numero, fracao_ideal) values
 ('10000000-0000-0000-0000-000000000101','','T101',0.5),
 ('10000000-0000-0000-0000-000000000102','','T102',0.5);

insert into public.pessoas (id, auth_user_id, nome) values
 ('20000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-0000000000e1','Edna Editora'),
 ('20000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000c1','Carlos Conselho'),
 ('20000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000a1','Ana Moradora'),
 ('20000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000b1','Bruno Morador');

insert into public.vinculos (unidade_id, pessoa_id, tipo) values
 ('10000000-0000-0000-0000-000000000101','20000000-0000-0000-0000-0000000000a1','proprietario'),
 ('10000000-0000-0000-0000-000000000102','20000000-0000-0000-0000-0000000000b1','proprietario');

insert into public.papeis (pessoa_id, papel) values
 ('20000000-0000-0000-0000-0000000000e1','editor'),
 ('20000000-0000-0000-0000-0000000000c1','conselho'),
 ('20000000-0000-0000-0000-0000000000a1','morador'),
 ('20000000-0000-0000-0000-0000000000b1','morador');

insert into public.documentos (id,tipo,titulo,storage_path,sha256,paginas,status,visibilidade,
                               publicado_em,publicado_por) values
 ('30000000-0000-0000-0000-000000000001','convencao','Convencao publica','t-pub.pdf',decode(repeat('01',32),'hex'),3,'publicado','publico',now(),'20000000-0000-0000-0000-0000000000e1'),
 ('30000000-0000-0000-0000-000000000002','ata_assembleia','Ata autenticada','t-aut.pdf',decode(repeat('02',32),'hex'),3,'publicado','autenticado',now(),'20000000-0000-0000-0000-0000000000e1'),
 ('30000000-0000-0000-0000-000000000003','ata_conselho','Ata do conselho','t-cons.pdf',decode(repeat('03',32),'hex'),3,'publicado','conselho',now(),'20000000-0000-0000-0000-0000000000e1'),
 ('30000000-0000-0000-0000-000000000004','notificacao_multa','Multa da 101','t-rest.pdf',decode(repeat('04',32),'hex'),3,'publicado','restrito',now(),'20000000-0000-0000-0000-0000000000e1'),
 ('30000000-0000-0000-0000-000000000005','ata_assembleia','Ata NAO publicada','t-nao.pdf',decode(repeat('05',32),'hex'),3,'em_revisao','autenticado',null,null),
 -- 06: o caso real (docs/inventario-acervo.md) no modelo do piso — ata `autenticado` com as
 -- paginas do regimento embutido promovidas a `publico` por override (mais permissivo, valido).
 ('30000000-0000-0000-0000-000000000006','ata_assembleia','AGE 04.02.2026 (embute regimento)','t-misto.pdf',decode(repeat('06',32),'hex'),36,'publicado','autenticado',now(),'20000000-0000-0000-0000-0000000000e1'),
 -- 07: usado no ataque TEMPORAL (override aplicado depois que o chunk ja existe).
 ('30000000-0000-0000-0000-000000000007','ata_assembleia','Ata classificada depois da chunkizacao','t-temporal.pdf',decode(repeat('07',32),'hex'),6,'publicado','autenticado',now(),'20000000-0000-0000-0000-0000000000e1'),
 -- 08: "convencao com anexo sigiloso" no modelo do piso — o documento nasce `conselho` (o nivel
 -- mais restritivo que ele contem) e as paginas publicas sobem por override.
 ('30000000-0000-0000-0000-000000000008','convencao','Convencao com anexo sigiloso','t-pubmisto.pdf',decode(repeat('08',32),'hex'),2,'publicado','conselho',now(),'20000000-0000-0000-0000-0000000000e1'),
 -- 09: documento `conselho` com pagina `restrito` (mais permissiva: conselho < restrito).
 ('30000000-0000-0000-0000-000000000009','ata_conselho','Ata do conselho com anexo da 101','t-c9.pdf',decode(repeat('09',32),'hex'),2,'publicado','conselho',now(),'20000000-0000-0000-0000-0000000000e1');

insert into public.documento_unidades (documento_id, unidade_id) values
 ('30000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000101'),
 ('30000000-0000-0000-0000-000000000009','10000000-0000-0000-0000-000000000101');

insert into public.documento_paginas (documento_id,pagina,texto,visibilidade) values
 ('30000000-0000-0000-0000-000000000001',1,'TEXTO PUBLICO',null),
 ('30000000-0000-0000-0000-000000000002',1,'TEXTO AUTENTICADO',null),
 ('30000000-0000-0000-0000-000000000003',1,'SEGREDO DO CONSELHO',null),
 ('30000000-0000-0000-0000-000000000004',1,'MULTA DA UNIDADE 101',null),
 ('30000000-0000-0000-0000-000000000005',1,'RASCUNHO NAO PUBLICADO',null),
 ('30000000-0000-0000-0000-000000000006',1,'ATA MISTA P1 nomes','autenticado'),
 ('30000000-0000-0000-0000-000000000006',5,'ATA MISTA P5 SEM CLASSIFICACAO',null),
 ('30000000-0000-0000-0000-000000000006',11,'REGIMENTO ART 1','publico'),
 ('30000000-0000-0000-0000-000000000006',12,'REGIMENTO ART 2','publico'),
 -- 07: as duas paginas nascem SEM override — e o que o worker produz antes da curadoria.
 ('30000000-0000-0000-0000-000000000007',5,'TEMPORAL P5 regimento embutido',null),
 ('30000000-0000-0000-0000-000000000007',6,'TEMPORAL P6 SIGILOSO nomes e CPF',null),
 ('30000000-0000-0000-0000-000000000008',1,'CONVENCAO PAGINA PUBLICA','publico'),
 ('30000000-0000-0000-0000-000000000008',2,'ANEXO SIGILOSO SO CONSELHO','conselho'),
 ('30000000-0000-0000-0000-000000000009',1,'C9 P1 deliberacao do conselho','conselho'),
 ('30000000-0000-0000-0000-000000000009',2,'C9 P2 anexo dirigido a unidade 101','restrito');

insert into public.chunks (documento_id,pagina_ini,pagina_fim,ordem,texto) values
 ('30000000-0000-0000-0000-000000000001',1,1,0,'CHUNK PUBLICO'),
 ('30000000-0000-0000-0000-000000000002',1,1,0,'CHUNK AUTENTICADO'),
 ('30000000-0000-0000-0000-000000000003',1,1,0,'CHUNK SEGREDO CONSELHO'),
 ('30000000-0000-0000-0000-000000000004',1,1,0,'CHUNK MULTA 101'),
 ('30000000-0000-0000-0000-000000000005',1,1,0,'CHUNK NAO PUBLICADO'),
 ('30000000-0000-0000-0000-000000000006',11,12,0,'CHUNK REGIMENTO PUBLICO'),
 ('30000000-0000-0000-0000-000000000006',1,1,1,'CHUNK ATA MISTA'),
 -- 07: no momento da insercao, paginas 5 e 6 tem o MESMO nivel efetivo (autenticado, herdado).
 -- O trigger de uniformidade aprova — corretamente, para o estado de agora.
 ('30000000-0000-0000-0000-000000000007',5,6,0,'TEMPORAL P5 regimento embutido TEMPORAL P6 SIGILOSO nomes e CPF'),
 ('30000000-0000-0000-0000-000000000008',1,1,0,'CHUNK CONVENCAO PUBLICA'),
 ('30000000-0000-0000-0000-000000000008',2,2,1,'CHUNK ANEXO SIGILOSO');

insert into storage.objects (bucket_id,name) values
 ('documentos','t-pub.pdf'), ('documentos','t-cons.pdf'), ('documentos','t-rest.pdf'),
 ('documentos','t-misto.pdf'), ('documentos','t-pubmisto.pdf'), ('documentos','t-c9.pdf'),
 ('publicos','t-conv.pdf'), ('anexos-financeiros','t-anexo.pdf');

-- ======================================================================
-- A. Linha do documento (app.documento_visivel) — base de comparação
-- ======================================================================
select is( pg_temp.probe('anon',null,null,
  $$select string_agg(titulo,'|' order by titulo) from public.documentos$$),
  'Convencao publica',
  'A1 anonimo so enxerga a linha do documento cujo PISO e publico');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000b1','aal1',
  $$select count(*)::text from public.documentos where id='30000000-0000-0000-0000-000000000004'$$),
  '0', 'A2 morador da 102 nao enxerga a linha do documento restrito a 101');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select count(*)::text from public.documentos where id='30000000-0000-0000-0000-000000000003'$$),
  '0', 'A3 morador nao enxerga a linha do documento de visibilidade conselho');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select count(*)::text from public.documentos where id='30000000-0000-0000-0000-000000000005'$$),
  '0', 'A4 morador nao enxerga documento nao publicado');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000c1','aal1',
  $$select count(*)::text from public.documentos where id='30000000-0000-0000-0000-000000000003'$$),
  '0', 'A5 conselho em sessao AAL1 (sem TOTP) nao enxerga documento de conselho');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000c1','aal2',
  $$select count(*)::text from public.documentos where id='30000000-0000-0000-0000-000000000003'$$),
  '1', 'A6 conselho em AAL2 enxerga documento de conselho (controle: a fixture funciona)');

-- ======================================================================
-- B. ARMADILHA Nº1 — chegar ao TEXTO por documento_paginas, sem tocar em documentos
-- ======================================================================
select is( pg_temp.probe('anon',null,null,
  $$select string_agg(texto,'|' order by texto) from public.documento_paginas
     where documento_id in ('30000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000003',
                            '30000000-0000-0000-0000-000000000004','30000000-0000-0000-0000-000000000005')$$),
  '(vazio)', 'B1 anonimo nao le NENHUMA pagina de documento nao-publico');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select count(*)::text from public.documento_paginas where documento_id='30000000-0000-0000-0000-000000000003'$$),
  '0', 'B2 morador nao le a pagina do documento de conselho');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000b1','aal1',
  $$select count(*)::text from public.documento_paginas where documento_id='30000000-0000-0000-0000-000000000004'$$),
  '0', 'B3 morador da 102 nao le a pagina da notificacao da 101');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select count(*)::text from public.documento_paginas where documento_id='30000000-0000-0000-0000-000000000005'$$),
  '0', 'B4 morador nao le pagina de documento nao publicado');

-- ======================================================================
-- C. ARMADILHA Nº1 — chegar ao TEXTO por chunks (a BUSCA), sem tocar em documentos
-- ======================================================================
select is( pg_temp.probe('anon',null,null,
  $$select string_agg(texto,'|' order by texto) from public.chunks
     where texto ilike '%SEGREDO%' or texto ilike '%MULTA%' or texto ilike '%NAO PUBLICADO%'$$),
  '(vazio)', 'C1 anonimo nao acha por busca chunk de documento restrito/conselho/nao publicado');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select count(*)::text from public.chunks where documento_id='30000000-0000-0000-0000-000000000003'$$),
  '0', 'C2 morador nao acha chunk de documento de conselho');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000b1','aal1',
  $$select count(*)::text from public.chunks where documento_id='30000000-0000-0000-0000-000000000004'$$),
  '0', 'C3 morador da 102 nao acha chunk da notificacao da 101');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select count(*)::text from public.chunks where documento_id='30000000-0000-0000-0000-000000000005'$$),
  '0', 'C4 morador nao acha chunk de documento nao publicado');

-- INVARIANTE DE ESPELHO: para todo chunk que um papel enxerga, TODA pagina do intervalo
-- [pagina_ini, pagina_fim] tem de ser legivel por esse mesmo papel. Ancorar so em pagina_ini
-- deixa o resto do intervalo passar junto.
select is( pg_temp.probe('anon',null,null,
  $$select count(*)::text from public.chunks c
     where exists (select 1 from generate_series(c.pagina_ini,c.pagina_fim) g(p)
                    where not exists (select 1 from public.documento_paginas dp
                                       where dp.documento_id=c.documento_id and dp.pagina=g.p))$$),
  '0', 'C5 todo chunk visivel ao anonimo tem TODAS as suas paginas legiveis por ele (espelho exato)');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select count(*)::text from public.chunks c
     where exists (select 1 from generate_series(c.pagina_ini,c.pagina_fim) g(p)
                    where not exists (select 1 from public.documento_paginas dp
                                       where dp.documento_id=c.documento_id and dp.pagina=g.p))$$),
  '0', 'C6 mesma invariante de espelho para o morador');

-- ======================================================================
-- D. Herança / override por página, sob o piso
-- ======================================================================
select is( pg_temp.probe('anon',null,null,
  $$select string_agg(texto,'|' order by pagina) from public.documento_paginas
     where documento_id='30000000-0000-0000-0000-000000000006'$$),
  'REGIMENTO ART 1|REGIMENTO ART 2',
  'D1 anonimo le SO as paginas com override publico dentro da ata autenticada (regimento embutido)');

-- [ADR-0023] "Documento misto" deixou de ser fator de autorizacao. Pagina sem override herda
-- documentos.visibilidade — e o PISO do ADR-0019 garante que herdar nunca afrouxa: nenhum
-- override pode ser mais restritivo que o piso, logo o piso E o nivel mais restritivo que
-- qualquer pagina daquele documento poderia ter. O antigo "falha fechado" nao protegia nada e
-- errava nas duas direcoes (num documento publico o unico override possivel e publico — um
-- no-op — e marca-lo fechava todas as outras paginas).
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select coalesce(app.nivel_efetivo('30000000-0000-0000-0000-000000000006',5)::text,'(nulo)')$$),
  'autenticado', 'D2 pagina sem override herda o piso do documento (que e o minimo garantido)');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000c1','aal2',
  $$select count(*)::text from public.documento_paginas
     where documento_id='30000000-0000-0000-0000-000000000006' and pagina=5$$),
  '1', 'D3 gestao continua vendo a pagina nao classificada (curadoria)');

select is( pg_temp.probe('anon',null,null,
  $$select count(*)::text from public.documentos where id='30000000-0000-0000-0000-000000000006'$$),
  '0', 'D4 pagina publica dentro de ata autenticada NAO torna a linha do documento visivel');

-- A flag `tem_paginas_mistas` deixou de ser fonte de decisao (V1): mexer nela, para mais ou para
-- menos, nao pode alterar o que alguem enxerga.
select is( pg_temp.probe('anon',null,null,
  $$select count(*)::text from public.documento_paginas where documento_id='30000000-0000-0000-0000-000000000006'$$),
  (select pg_temp.probe('anon',null,null,
    $$select count(*)::text from public.documento_paginas where documento_id='30000000-0000-0000-0000-000000000006'$$)
   from (select pg_temp.executa('postgres',null,null,
     $$update public.documentos set tem_paginas_mistas = not tem_paginas_mistas
        where id='30000000-0000-0000-0000-000000000006'$$)) _),
  'D5 inverter a flag tem_paginas_mistas nao muda o que o anonimo enxerga (flag nao decide acesso)');

-- ======================================================================
-- E. Piso de permissividade (ADR-0019/D13) — a ordem contra a AUDIENCIA REAL
-- ======================================================================
-- A ordem conselho < restrito precisa bater com quem de fato enxerga: restrito = gestao + a
-- unidade vinculada, logo audiencia estritamente maior que conselho = so gestao.
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select (select count(*) from public.documentos where id='30000000-0000-0000-0000-000000000003')::text
        || '/' ||
           (select count(*) from public.documentos where id='30000000-0000-0000-0000-000000000004')::text$$),
  '0/1', 'E1 morador vinculado ve o documento RESTRITO e nao ve o CONSELHO (restrito e mais permissivo)');

select is( pg_temp.tenta('postgres',null,null,
  $$insert into public.documento_paginas (documento_id,pagina,texto,visibilidade)
    values ('30000000-0000-0000-0000-000000000004',2,'x','conselho')$$),
  'ERRO[P0001]',
  'E2 pagina CONSELHO dentro de documento RESTRITO e rejeitada (viola o piso)');

select is( pg_temp.tenta('postgres',null,null,
  $$insert into public.documento_paginas (documento_id,pagina,texto,visibilidade)
    values ('30000000-0000-0000-0000-000000000003',2,'x','restrito')$$),
  'OK (1)',
  'E3 pagina RESTRITO dentro de documento CONSELHO e aceita (mais permissiva, nao viola o piso)');

select is( pg_temp.tenta('postgres',null,null,
  $$insert into public.documento_paginas (documento_id,pagina,texto,visibilidade)
    values ('30000000-0000-0000-0000-000000000001',2,'x','conselho')$$),
  'ERRO[P0001]',
  'E4 pagina CONSELHO dentro de documento PUBLICO e rejeitada (era o vazamento V3)');

-- O piso tem de valer nos DOIS lados da relacao. Subir documentos.visibilidade depois que as
-- paginas ja estao classificadas quebra a invariante pelo lado do documento — e nada revalida.
select is( pg_temp.tenta('postgres',null,null,
  $$update public.documentos set visibilidade='autenticado'
     where id='30000000-0000-0000-0000-000000000009'$$),
  'ERRO[P0001]',
  'E5 subir o piso do documento acima de uma pagina ja classificada e rejeitado');

-- ======================================================================
-- F. Chunk cruzando fronteira de visibilidade
-- ======================================================================
select is( pg_temp.tenta('postgres',null,null,
  $$insert into public.chunks (documento_id,pagina_ini,pagina_fim,ordem,texto)
    values ('30000000-0000-0000-0000-000000000006',5,11,90,'chunk cruzando')$$),
  'ERRO[P0001]',
  'F1 gravar chunk que cobre niveis efetivos distintos e rejeitado');

select is(
  (select count(*)::text from public.chunks c
    where (select count(distinct coalesce(app.nivel_efetivo(c.documento_id, g.p)::text,'(nulo)'))
             from generate_series(c.pagina_ini, c.pagina_fim) g(p)) > 1),
  '0',
  'F2 nenhum chunk cobre paginas de niveis de visibilidade efetiva distintos');

-- ATAQUE TEMPORAL — o caminho REAL do pipeline: o worker chunkiza ANTES de a curadoria
-- classificar pagina por pagina. Quando o override chega depois, nada revalida os chunks que ja
-- cobrem aquele intervalo.
-- F3 nao prescreve mecanismo: a reclassificacao pode ser ACEITA (desde que os chunks afetados
-- sejam reprocessados/invalidados junto) ou REJEITADA com erro explicito (exigindo rechunk
-- antes). O que nao pode e ser aceita em silencio deixando chunk inconsistente — e o que F4/F6
-- medem logo abaixo. Bloquear pura e simplesmente tem custo: e o fluxo real de curadoria do
-- acervo (classificar o regimento embutido DEPOIS da ingestao).
select ok(
  pg_temp.executa('postgres',null,null,
    $$update public.documento_paginas set visibilidade='publico'
       where documento_id='30000000-0000-0000-0000-000000000007' and pagina=5$$)
  in ('OK (1)','ERRO[P0001]'),
  'F3 classificar a pagina 5 depois da chunkizacao: aceita (com reprocesso) ou recusada com erro');

select is( pg_temp.probe('anon',null,null,
  $$select count(*)::text from public.chunks where texto ilike '%TEMPORAL P6 SIGILOSO%'$$),
  '0',
  'F4 anonimo NAO le a pagina 6 pelo chunk que passou a cruzar fronteira DEPOIS de gravado');

select is( pg_temp.probe('anon',null,null,
  $$select count(*)::text from public.documento_paginas
     where documento_id='30000000-0000-0000-0000-000000000007' and pagina=6$$),
  '0',
  'F5 controle: a pagina 6 em si segue corretamente negada ao anonimo');

select is(
  (select count(*)::text from public.chunks c
    where (select count(distinct coalesce(app.nivel_efetivo(c.documento_id, g.p)::text,'(nulo)'))
             from generate_series(c.pagina_ini, c.pagina_fim) g(p)) > 1),
  '0',
  'F6 a invariante de uniformidade continua valendo DEPOIS de uma reclassificacao de pagina');

-- ======================================================================
-- G. Arquivo cru no storage — o piso e o que torna herdar seguro
-- ======================================================================
select is( pg_temp.probe('anon',null,null,
  $$select count(*)::text from public.documento_paginas
     where documento_id='30000000-0000-0000-0000-000000000008' and pagina=2$$),
  '0', 'G1 anonimo nao le o texto da pagina conselho do documento de piso conselho');

select is( pg_temp.probe('anon',null,null,
  $$select coalesce(string_agg(texto,'|'),'(vazio)') from public.documento_paginas
     where documento_id='30000000-0000-0000-0000-000000000008' and pagina=1$$),
  'CONVENCAO PAGINA PUBLICA',
  'G2 anonimo LE a pagina publica embutida no documento de piso conselho (a funcionalidade)');

select is( pg_temp.probe('anon',null,null,
  $$select count(*)::text from storage.objects where name='t-pubmisto.pdf'$$),
  '0', 'G3 anonimo NAO baixa o PDF que contem a pagina restrita (era o vazamento V3)');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select count(*)::text from storage.objects where name='t-c9.pdf'$$),
  '0', 'G4 morador vinculado nao baixa o PDF de piso conselho, mesmo tendo pagina restrita nele');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000c1','aal2',
  $$select count(*)::text from storage.objects where name='t-pubmisto.pdf'$$),
  '1', 'G5 gestao baixa o PDF (controle)');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select coalesce(string_agg(name,'|' order by name),'(vazio)') from storage.objects where bucket_id='anexos-financeiros'$$),
  '(vazio)', 'G6 morador nao enxerga nenhum objeto do bucket anexos-financeiros');

-- ======================================================================
-- H. LOCALIDADE (ADR-0023) — a propriedade que substituiu "falha fechado"
-- ======================================================================
-- Escrever, alterar ou apagar a pagina X nao pode mudar o nivel efetivo NEM o acesso real a
-- pagina Y. Foi a nao-localidade de app.documento_tem_override() que produziu os achados das
-- rodadas 1-3; com nivel_efetivo puramente local, a propriedade e testavel diretamente.
-- Medimos as duas coisas: o predicado isolado E o acesso real por anon/authenticated — o
-- vazamento das rodadas anteriores foi sempre pelo acesso, nunca pelo predicado sozinho.
insert into public.documentos (id,tipo,titulo,storage_path,sha256,paginas,status,visibilidade,
                               publicado_em,publicado_por) values
 ('30000000-0000-0000-0000-00000000000a','ata_assembleia','Alvo de localidade','t-loc.pdf',decode(repeat('da',32),'hex'),9,'publicado','autenticado',now(),'20000000-0000-0000-0000-0000000000e1');
insert into public.documento_paginas (documento_id,pagina,texto,visibilidade) values
 ('30000000-0000-0000-0000-00000000000a',3,'LOC P3 — a pagina que sera mexida',null),
 ('30000000-0000-0000-0000-00000000000a',5,'LOC P5 — nao pode mudar',null),
 ('30000000-0000-0000-0000-00000000000a',6,'LOC P6 — nao pode mudar',null);
insert into public.chunks (documento_id,pagina_ini,pagina_fim,ordem,texto) values
 ('30000000-0000-0000-0000-00000000000a',5,6,0,'LOC CHUNK 5-6');

-- Assinatura do que NAO pode mudar: nivel efetivo das paginas 5/6 + acesso real de anon e
-- morador as paginas 5/6, aos chunks e ao objeto do documento.
create function pg_temp.assinatura_localidade() returns text language sql stable as $f$
  select coalesce(app.nivel_efetivo('30000000-0000-0000-0000-00000000000a',5)::text,'(nulo)')
      || '|' || coalesce(app.nivel_efetivo('30000000-0000-0000-0000-00000000000a',6)::text,'(nulo)')
      || '|anon:' || pg_temp.probe('anon',null,null,
           $q$select coalesce(string_agg(pagina::text,',' order by pagina),'-') from public.documento_paginas
               where documento_id='30000000-0000-0000-0000-00000000000a' and pagina in (5,6)$q$)
      || '/' || pg_temp.probe('anon',null,null,
           $q$select count(*)::text from public.chunks where documento_id='30000000-0000-0000-0000-00000000000a'$q$)
      || '|mor:' || pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
           $q$select coalesce(string_agg(pagina::text,',' order by pagina),'-') from public.documento_paginas
               where documento_id='30000000-0000-0000-0000-00000000000a' and pagina in (5,6)$q$)
      || '/' || pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
           $q$select count(*)::text from public.chunks where documento_id='30000000-0000-0000-0000-00000000000a'$q$)
$f$;

create temp table _loc0 on commit drop as select pg_temp.assinatura_localidade() as sig;

-- H1: INSERT de override numa pagina que nao existia (pagina 4, dentro do documento).
select is( pg_temp.executa('postgres',null,null,
  $$insert into public.documento_paginas (documento_id,pagina,texto,visibilidade)
    values ('30000000-0000-0000-0000-00000000000a',4,'LOC P4 nova','publico')$$),
  'OK (1)', 'H1 controle: classificar uma pagina nova e escrita legitima');
select is( pg_temp.assinatura_localidade(), (select sig from _loc0),
  'H2 INSERT de override na pagina 4 nao muda nivel nem acesso das paginas 5 e 6');

-- H3: UPDATE do override de uma pagina vizinha.
select is( pg_temp.executa('postgres',null,null,
  $$update public.documento_paginas set visibilidade='publico'
     where documento_id='30000000-0000-0000-0000-00000000000a' and pagina=3$$),
  'OK (1)', 'H3 controle: reclassificar a pagina 3 e escrita legitima');
select is( pg_temp.assinatura_localidade(), (select sig from _loc0),
  'H4 UPDATE de override na pagina 3 nao muda nivel nem acesso das paginas 5 e 6');

-- H5: DELETE — o caminho que nenhum trigger cobre, e que sob o modelo antigo abria o documento.
select is( pg_temp.executa('postgres',null,null,
  $$delete from public.documento_paginas
     where documento_id='30000000-0000-0000-0000-00000000000a' and pagina=3$$),
  'OK (1)', 'H5 controle: apagar a pagina 3 e escrita legitima do worker (reprocessamento)');
select is( pg_temp.assinatura_localidade(), (select sig from _loc0),
  'H6 DELETE da pagina 3 nao muda nivel nem acesso das paginas 5 e 6');

-- H7: apagar TODAS as paginas classificadas do documento (o caso da 3a rodada).
select is( pg_temp.executa('postgres',null,null,
  $$delete from public.documento_paginas
     where documento_id='30000000-0000-0000-0000-00000000000a' and pagina=4$$),
  'OK (1)', 'H7 controle: apagar a ultima pagina com override');
select is( pg_temp.assinatura_localidade(), (select sig from _loc0),
  'H8 apagar a ULTIMA pagina com override nao muda nivel nem acesso das paginas 5 e 6');

-- H9: nenhum predicado de autorizacao pode depender de quantas paginas do documento estao
-- classificadas — a versao "de catalogo" da mesma invariante.
with alvo as materialized (
  select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'app' and p.prokind = 'f'
)
select is(
  (select count(*)::text from alvo
    where pg_get_functiondef(oid) ~* 'documento_tem_override|tem_paginas_mistas'),
  '0',
  'H9 nenhuma funcao de autorizacao le "documento e misto" (nao-localidade modal, ADR-0023)');

select * from finish();
rollback;
