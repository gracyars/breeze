-- ============================================================================
-- Breeze — auditoria de RLS: ARMADILHA Nº1 (SPEC §7, §8.1).
-- Alvo: documentos / documento_paginas / chunks / storage.objects.
-- Método: tentar chegar ao TEXTO de conteúdo restrito sem tocar em `documentos`.
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
                               tem_paginas_mistas,publicado_em,publicado_por) values
 -- 01 público  02 autenticado  03 conselho  04 restrito(101)  05 não publicado
 ('30000000-0000-0000-0000-000000000001','convencao','Convencao publica','t-pub.pdf',decode(repeat('01',32),'hex'),3,'publicado','publico',false,now(),'20000000-0000-0000-0000-0000000000e1'),
 ('30000000-0000-0000-0000-000000000002','ata_assembleia','Ata autenticada','t-aut.pdf',decode(repeat('02',32),'hex'),3,'publicado','autenticado',false,now(),'20000000-0000-0000-0000-0000000000e1'),
 ('30000000-0000-0000-0000-000000000003','ata_conselho','Ata do conselho','t-cons.pdf',decode(repeat('03',32),'hex'),3,'publicado','conselho',false,now(),'20000000-0000-0000-0000-0000000000e1'),
 ('30000000-0000-0000-0000-000000000004','notificacao_multa','Multa da 101','t-rest.pdf',decode(repeat('04',32),'hex'),3,'publicado','restrito',false,now(),'20000000-0000-0000-0000-0000000000e1'),
 ('30000000-0000-0000-0000-000000000005','ata_assembleia','Ata NAO publicada','t-nao.pdf',decode(repeat('05',32),'hex'),3,'em_revisao','autenticado',false,null,null),
 -- 06: o caso real (docs/inventario-acervo.md): ata de 36p que embute o Regimento Interno.
 ('30000000-0000-0000-0000-000000000006','ata_assembleia','AGE 04.02.2026 (embute regimento)','t-misto.pdf',decode(repeat('06',32),'hex'),36,'publicado','autenticado',true,now(),'20000000-0000-0000-0000-0000000000e1'),
 -- 07: MESMO conteúdo misto, mas SEM tem_paginas_mistas (curadoria esqueceu de marcar).
 ('30000000-0000-0000-0000-000000000007','ata_assembleia','Ata mista sem a flag','t-trap.pdf',decode(repeat('07',32),'hex'),6,'publicado','autenticado',false,now(),'20000000-0000-0000-0000-0000000000e1'),
 -- 08: documento PÚBLICO com página restrita (caminho inverso).
 ('30000000-0000-0000-0000-000000000008','convencao','Convencao com anexo sigiloso','t-pubmisto.pdf',decode(repeat('08',32),'hex'),2,'publicado','publico',true,now(),'20000000-0000-0000-0000-0000000000e1');

insert into public.documento_unidades (documento_id, unidade_id) values
 ('30000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000101');

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
 ('30000000-0000-0000-0000-000000000007',5,'TRAP P5 PUBLICA','publico'),
 ('30000000-0000-0000-0000-000000000007',6,'TRAP P6 SIGILOSO nomes e CPF',null),
 ('30000000-0000-0000-0000-000000000008',1,'CONVENCAO PAGINA PUBLICA','publico'),
 ('30000000-0000-0000-0000-000000000008',2,'ANEXO SIGILOSO SO CONSELHO','conselho');

insert into public.chunks (documento_id,pagina_ini,pagina_fim,ordem,texto) values
 ('30000000-0000-0000-0000-000000000001',1,1,0,'CHUNK PUBLICO'),
 ('30000000-0000-0000-0000-000000000002',1,1,0,'CHUNK AUTENTICADO'),
 ('30000000-0000-0000-0000-000000000003',1,1,0,'CHUNK SEGREDO CONSELHO'),
 ('30000000-0000-0000-0000-000000000004',1,1,0,'CHUNK MULTA 101'),
 ('30000000-0000-0000-0000-000000000005',1,1,0,'CHUNK NAO PUBLICADO'),
 ('30000000-0000-0000-0000-000000000006',11,12,0,'CHUNK REGIMENTO PUBLICO'),
 ('30000000-0000-0000-0000-000000000006',1,1,1,'CHUNK ATA MISTA'),
 -- o chunk que cruza a fronteira num documento SEM a flag: aceito hoje pelo trigger
 ('30000000-0000-0000-0000-000000000007',5,6,0,'TRAP P5 PUBLICA TRAP P6 SIGILOSO nomes e CPF'),
 ('30000000-0000-0000-0000-000000000008',1,1,0,'CHUNK CONVENCAO PUBLICA'),
 ('30000000-0000-0000-0000-000000000008',2,2,1,'CHUNK ANEXO SIGILOSO');

insert into storage.objects (bucket_id,name) values
 ('documentos','t-pub.pdf'), ('documentos','t-cons.pdf'), ('documentos','t-rest.pdf'),
 ('documentos','t-misto.pdf'), ('documentos','t-pubmisto.pdf'), ('publicos','t-conv.pdf'),
 ('anexos-financeiros','t-anexo.pdf');

-- ======================================================================
-- A. Linha do documento (app.documento_visivel) — base de comparação
-- ======================================================================
select is( pg_temp.probe('anon',null,null,
  $$select string_agg(titulo,'|' order by titulo) from public.documentos$$),
  'Convencao com anexo sigiloso|Convencao publica',
  'A1 anonimo so enxerga as linhas de documento publico (nenhuma outra)');

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

-- chunks e documento_paginas precisam negar EXATAMENTE o mesmo conjunto que `documentos` nega:
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
-- D. Herança / override por página (correção 2026-09-04)
-- ======================================================================
select is( pg_temp.probe('anon',null,null,
  $$select string_agg(texto,'|' order by pagina) from public.documento_paginas
     where documento_id='30000000-0000-0000-0000-000000000006'$$),
  'REGIMENTO ART 1|REGIMENTO ART 2',
  'D1 anonimo le SO as paginas com override publico dentro da ata autenticada (regimento embutido)');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select count(*)::text from public.documento_paginas
     where documento_id='30000000-0000-0000-0000-000000000006' and pagina=5$$),
  '0', 'D2 pagina SEM classificacao em documento misto nao herda: falha fechado ate ser classificada');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000c1','aal2',
  $$select count(*)::text from public.documento_paginas
     where documento_id='30000000-0000-0000-0000-000000000006' and pagina=5$$),
  '1', 'D3 gestao continua vendo a pagina nao classificada (curadoria)');

select is( pg_temp.probe('anon',null,null,
  $$select count(*)::text from public.documentos where id='30000000-0000-0000-0000-000000000006'$$),
  '0', 'D4 pagina publica dentro de ata autenticada NAO torna a linha do documento visivel');

-- ======================================================================
-- E. Chunk cruzando fronteira de visibilidade  ← VAZAMENTO
-- ======================================================================
-- Documento 07 é o mesmo caso do 06 (misto), mas com tem_paginas_mistas = false. O trigger
-- chunks_valida_visibilidade_uniforme só roda quando a flag é true, e nada obriga a flag a ser
-- true quando existe override de página. Resultado: chunk 5-6 ancora na página 5 (publica) e
-- entrega o texto da página 6 (autenticada) a quem nem login tem.
select is( pg_temp.probe('anon',null,null,
  $$select count(*)::text from public.chunks where texto ilike '%TRAP P6 SIGILOSO%'$$),
  '0', 'E1 anonimo NAO pode ler texto de pagina autenticada por chunk que cruza fronteira (doc sem a flag)');

select is( pg_temp.tenta('postgres',null,null,
  $$insert into public.chunks (documento_id,pagina_ini,pagina_fim,ordem,texto)
    values ('30000000-0000-0000-0000-000000000007',5,6,90,'novo chunk cruzando')$$),
  'ERRO[P0001]',
  'E2 gravar chunk que cruza fronteira de visibilidade deve ser rejeitado mesmo sem tem_paginas_mistas');

-- E3 e a invariante em si, sem prescrever o mecanismo de correcao: nenhum chunk pode cobrir
-- paginas de niveis efetivos diferentes, com ou sem tem_paginas_mistas. Enquanto isso for
-- possivel, a ancora em pagina_ini entrega o resto do intervalo junto.
select is(
  (select count(*)::text from public.chunks c
    where (select count(distinct coalesce(app.nivel_efetivo(c.documento_id, g.p)::text,'(nulo)'))
             from generate_series(c.pagina_ini, c.pagina_fim) g(p)) > 1),
  '0',
  'E3 nenhum chunk cobre paginas de niveis de visibilidade efetiva distintos');

-- ======================================================================
-- F. Documento público com página restrita — o arquivo cru
-- ======================================================================
-- O texto da página restrita é corretamente negado...
select is( pg_temp.probe('anon',null,null,
  $$select count(*)::text from public.documento_paginas
     where documento_id='30000000-0000-0000-0000-000000000008' and pagina=2$$),
  '0', 'F1 anonimo nao le o texto da pagina conselho dentro do documento publico');

-- ...mas o PDF inteiro (que contém essa página) sai pelo bucket, porque storage é gated pelo
-- nível do DOCUMENTO. A restrição por página é ilusória enquanto isso for possível.
select is( pg_temp.probe('anon',null,null,
  $$select count(*)::text from storage.objects where name='t-pubmisto.pdf'$$),
  '0', 'F2 anonimo NAO pode baixar o PDF inteiro de documento publico que contem pagina restrita');

-- Controle: buckets separados continuam corretos.
select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000000a1','aal1',
  $$select coalesce(string_agg(name,'|' order by name),'(vazio)') from storage.objects where bucket_id='anexos-financeiros'$$),
  '(vazio)', 'F3 morador nao enxerga nenhum objeto do bucket anexos-financeiros');

select * from finish();
rollback;
