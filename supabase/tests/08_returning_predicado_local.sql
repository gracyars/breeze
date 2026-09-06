-- ============================================================================
-- Breeze — auditoria de RLS: a CLASSE de defeito "policy de SELECT cujo predicado reconsulta a
-- propria tabela", formalizada como regressao. Fonte: SPEC §7 (ADR-0023, predicado local),
-- §2 (RLS por tabela), §2.1 (papeis e AAL), D4 (editora unica).
--
-- O DEFEITO QUE ORIGINOU ESTE ARQUIVO (commit 8e126fe, migracao
-- 20260906100500_documentos_select_predicado_local.sql): `documentos_select` chamava
-- `app.documento_visivel(id)`, que faz `select exists (select 1 from public.documentos ...)`.
-- Sob MVCC, `INSERT ... RETURNING` avalia a policy de SELECT sobre a linha nova DENTRO DO MESMO
-- COMANDO — e uma subconsulta disparada por esse comando nao enxerga a linha que o proprio
-- comando esta inserindo. `exists` falso, policy nega, 42501 para TODO MUNDO, editora com aal2
-- inclusive. O caminho normal de publicar documento pela aplicacao estava quebrado desde F0.
--
-- POR QUE 234 ASSERTS NAO PEGARAM: a suite inteira testava `insert`/`update` SEM `returning`.
-- Sem `returning`, a policy de SELECT nem entra no plano — o defeito era invisivel por
-- construcao. A licao nao e "faltou um assert em documentos": e que a forma do comando
-- (`... returning`) e parte da superficie de autorizacao e nunca tinha sido exercitada.
--
-- O QUE ESTE ARQUIVO PROVA, nesta ordem:
--   A/B  a matriz de `documentos`: INSERT/UPDATE ... RETURNING x {editor aal2, editor aal1,
--        conselho aal2, morador, anonimo}. A editora PRECISA conseguir; os demais precisam
--        continuar negados — e o assert distingue POR QUAL CAMADA cada um foi negado.
--   C    a assimetria entre "negado" e "nao fez nada": INSERT recusado levanta 42501; UPDATE
--        barrado pelo USING afeta zero linhas e NAO levanta nada. Tratar os dois como
--        "ok, bloqueou" esconde a diferenca — e foi exatamente essa diferenca que escondeu o bug.
--   D    a afirmacao do `eng-supabase` de que nenhuma outra tabela tem o defeito, EXECUTADA
--        (pessoas / papeis / vinculos), nao lida. Ver o achado documentado no bloco D.
--   E    a PROPRIEDADE, nao o caso: para TODAS as 24 tabelas em que um papel de usuario escreve,
--        o mesmo INSERT com e sem `returning` tem de dar o mesmo resultado. Se um dia divergirem,
--        e a classe voltando por uma tabela nova.
--   F    o canario estatico: quais policies de SELECT hoje reconsultam a propria tabela, e a
--        premissa que isenta `documento_paginas`/`chunks` (ninguem alem do worker escreve nelas).
--
-- VOCABULARIO DA MATRIZ (pg_temp.classifica), escolhido para nao confundir camadas:
--   PASSOU(n)     — o comando rodou e afetou n linhas.
--   SILENCIO(0)   — o comando rodou, NAO levantou erro e afetou ZERO linhas (USING de UPDATE
--                   filtrou a linha). Nao e a mesma coisa que "negado": nada avisou ninguem.
--   NEGADO-GRANT  — 42501 levantado pela camada de PRIVILEGIO (o papel nao tem o GRANT).
--   NEGADO-RLS    — 42501 levantado pela camada de POLICY (tem GRANT, a policy recusou).
--   ERRO[xxxxx]   — qualquer outro sqlstate, mostrado cru.
-- A separacao GRANT/RLS e feita por `has_any_column_privilege`, nao por texto de mensagem:
-- mensagem de erro depende de `lc_messages` e um teste de seguranca nao pode depender de idioma.
--
-- Cada arquivo e auto-contido (pg_prove roda um por um): abre `begin`, cria a propria fixture,
-- roda os asserts e fecha em `rollback` — nada fica no banco. Impersonacao por
-- pg_temp.probe/tenta/classifica (troca request.jwt.claims + `set local role` e VOLTA para
-- postgres antes de retornar, para o pgTAP seguir rodando como postgres). Todo ataque e DESFEITO:
-- um ataque que passa nao pode destruir a fixture do teste seguinte.
-- Atores: ...e1 editor | ...c1 conselho | ...a1 morador un.101 | ...b1 morador un.102
--         ...z1 pessoa sem papel (alvo de escrita, para nao colidir com unique parcial)
-- ============================================================================
begin;
select plan(30);

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

-- `tenta` executa o ataque e DESFAZ o efeito (subtransacao revertida por raise proposital).
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

-- `classifica` e `tenta` com o vocabulario da matriz: alem de OK/ERRO, diz QUAL CAMADA negou.
-- p_tabela/p_op existem so para separar GRANT de RLS sem depender do texto da mensagem.
create function pg_temp.classifica(p_role text, p_sub text, p_aal text,
                                   p_tabela text, p_op text, p_sql text)
returns text language plpgsql as $f$
declare r text; tem_grant boolean;
begin
  tem_grant := has_any_column_privilege(p_role, p_tabela, p_op);
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
      if sqlerrm like '__desfaz__%' then
        declare n2 text := replace(sqlerrm,'__desfaz__','');
        begin r := case when n2 = '0' then 'SILENCIO(0)' else 'PASSOU('||n2||')' end; end;
      else r := 'ERRO[22000]'; end if;
    when insufficient_privilege then
      r := case when tem_grant then 'NEGADO-RLS' else 'NEGADO-GRANT' end;
    when others then r := 'ERRO['||sqlstate||']';
  end;
  execute 'set local role postgres';
  return r;
end $f$;

-- `devolve` prova que `returning` DEVOLVE A LINHA, nao so que nao explodiu — o valor viaja de
-- volta pela mensagem da excecao que desfaz o efeito. Sem isto, um `returning` que passasse na
-- policy e devolvesse vazio contaria como sucesso.
create function pg_temp.devolve(p_role text, p_sub text, p_aal text, p_sql text)
returns text language plpgsql as $f$
declare r text;
begin
  if p_sub is null then perform set_config('request.jwt.claims', null, true);
  else perform set_config('request.jwt.claims',
    json_build_object('sub',p_sub,'role',p_role,'aal',coalesce(p_aal,'aal1'))::text, true); end if;
  execute 'set local role '||quote_ident(p_role);
  begin
    declare v text;
    begin
      execute p_sql into v;
      raise exception using errcode='22000', message='__desfaz__'||coalesce(v,'(nada devolvido)');
    end;
  exception
    when sqlstate '22000' then
      if sqlerrm like '__desfaz__%' then r := replace(sqlerrm,'__desfaz__','');
      else r := 'ERRO[22000]'; end if;
    when others then r := 'ERRO['||sqlstate||']';
  end;
  execute 'set local role postgres';
  return r;
end $f$;

-- ------------------------------------------------------ RUIDO: banco POVOADO --
-- A suite roda contra o banco de desenvolvimento, que a partir de F1 NUNCA esta vazio (editora
-- semeada, acervo do backfill, cobrancas do balancete). Todo assert deste arquivo mede a POLICY,
-- nao o conteudo do banco: a matriz e por linha e por papel, e a varredura do bloco E/F le
-- catalogo. Ainda assim a fixture suja o banco de proposito com uma editora de mandato aberto
-- HOJE — o estado normal do sistema — para que nada aqui dependa de banco limpo. Prefixo `ff`.
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
 ('ff000000-0000-0000-0000-0000000008e0','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ruido-ret-editora@t.local',now(),now());
insert into public.pessoas (id, auth_user_id, nome) values
 ('ff200000-0000-0000-0000-0000000008e0','ff000000-0000-0000-0000-0000000008e0','Editora Semeada (ruido)');
insert into public.papeis (pessoa_id, papel, mandato_inicio) values
 ('ff200000-0000-0000-0000-0000000008e0','editor', current_date);

-- ---------------------------------------------------------------- fixture --
-- Todo valor de chave unica aqui e ESTRANHO ao dominio real de proposito (bloco `ZZ8`, conta
-- `ZZ8.9.1`, competencia de 1997-1999, exercicio 2099): o bloco E exige que o insert BASE de
-- cada tabela passe (E1), entao uma colisao de unicidade com o acervo de verdade viraria
-- vermelho de auditoria de seguranca sem nada da seguranca ter mudado — a mesma armadilha de
-- banco povoado que abortou 02_* em 2026-09-06 (R3 de docs/ops/divida-tecnica.md).
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
 ('00000000-0000-0000-0000-0000000008e1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ret-editor@t.local',now(),now()),
 ('00000000-0000-0000-0000-0000000008c1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ret-conselho@t.local',now(),now()),
 ('00000000-0000-0000-0000-0000000008a1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ret-mora@t.local',now(),now()),
 ('00000000-0000-0000-0000-0000000008b1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ret-morb@t.local',now(),now());

insert into public.unidades (id, bloco, numero, fracao_ideal) values
 ('10000000-0000-0000-0000-000000008101','ZZ8','R101',0.001),
 ('10000000-0000-0000-0000-000000008102','ZZ8','R102',0.001),
 -- unidade virgem: alvo das escritas da matriz do bloco E (cobrancas/vinculos/documento_unidades
 -- tem unique parcial; escrever numa unidade ja usada colidiria com a fixture e o ERRO de
 -- unicidade se disfarcaria de "os dois caminhos deram igual").
 ('10000000-0000-0000-0000-000000008199','ZZ8','R199',0.001);

insert into public.pessoas (id, auth_user_id, nome) values
 ('20000000-0000-0000-0000-0000000008e1','00000000-0000-0000-0000-0000000008e1','Edna Editora'),
 ('20000000-0000-0000-0000-0000000008c1','00000000-0000-0000-0000-0000000008c1','Carlos Conselho'),
 ('20000000-0000-0000-0000-0000000008a1','00000000-0000-0000-0000-0000000008a1','Ana Moradora'),
 ('20000000-0000-0000-0000-0000000008b1','00000000-0000-0000-0000-0000000008b1','Bruno Morador'),
 ('20000000-0000-0000-0000-000000000821',null,'Zilda Sem Papel');

insert into public.vinculos (unidade_id, pessoa_id, tipo) values
 ('10000000-0000-0000-0000-000000008101','20000000-0000-0000-0000-0000000008a1','proprietario'),
 ('10000000-0000-0000-0000-000000008102','20000000-0000-0000-0000-0000000008b1','proprietario');

insert into public.papeis (pessoa_id, papel) values
 ('20000000-0000-0000-0000-0000000008e1','editor'),
 ('20000000-0000-0000-0000-0000000008c1','conselho'),
 ('20000000-0000-0000-0000-0000000008a1','morador'),
 ('20000000-0000-0000-0000-0000000008b1','morador');

-- Acervo minimo. `d1` e a ata que os asserts A/B usam como alvo de UPDATE.
insert into public.documentos (id,tipo,titulo,storage_path,sha256,paginas,bytes,status,visibilidade,
                               publicado_em,publicado_por) values
 ('30000000-0000-0000-0000-000000008001','ata_assembleia','Ata alvo da matriz RETURNING','ret-ata.pdf',decode(repeat('81',32),'hex'),4,1024,'publicado','autenticado',now(),'20000000-0000-0000-0000-0000000008e1'),
 ('30000000-0000-0000-0000-000000008002','notificacao_multa','Notificacao restrita da matriz','ret-mult.pdf',decode(repeat('82',32),'hex'),1,512,'publicado','restrito',now(),'20000000-0000-0000-0000-0000000008e1');

-- Plano de contas minimo ate a folha (contas_raiz_ck / contas_folha_ck / hierarquia por trigger).
insert into public.contas (id,codigo,nome,natureza,nivel,conta_pai_id,aceita_lancamento) values
 ('40000000-0000-0000-0000-000000008001','ZZ8','Grupo matriz','despesa',1,null,false),
 ('40000000-0000-0000-0000-000000008002','ZZ8.9','Subgrupo matriz','despesa',2,'40000000-0000-0000-0000-000000008001',false),
 ('40000000-0000-0000-0000-000000008003','ZZ8.9.1','Conta folha matriz','despesa',3,'40000000-0000-0000-0000-000000008002',true);

insert into public.fornecedores (id,cnpj,razao_social) values
 ('50000000-0000-0000-0000-000000008001','98765432000199','Fornecedor da matriz LTDA');

insert into public.assembleias (id,tipo,data) values
 ('60000000-0000-0000-0000-000000008001','ago',current_date-10);

insert into public.lancamentos (id,data_competencia,conta_id,historico,valor_centavos,tipo,
                                documento_id,pagina_origem,criado_por) values
 ('70000000-0000-0000-0000-000000008001',date_trunc('month',current_date)::date,
  '40000000-0000-0000-0000-000000008003','Lancamento alvo da matriz',12345,'despesa',
  '30000000-0000-0000-0000-000000008001',1,'20000000-0000-0000-0000-0000000008e1');

insert into public.pareceres (id,competencia_inicio,competencia_fim,texto) values
 ('90000000-0000-0000-0000-000000008001','1999-01-01','1999-12-01','Parecer alvo da matriz');

-- ======================================================================
-- A. documentos — INSERT ... RETURNING, a matriz completa (o defeito, congelado)
-- ======================================================================
-- A editora com aal2 PRECISA conseguir. Antes de 20260906100500 este assert era 'NEGADO-RLS':
-- e a linha que reprova o retorno do defeito.
select is( pg_temp.classifica('authenticated','00000000-0000-0000-0000-0000000008e1','aal2',
  'public.documentos','INSERT',
  $$insert into public.documentos (id,tipo,titulo,storage_path,sha256,paginas,bytes)
    values ('30000000-0000-0000-0000-0000000080a1','ata_assembleia','Ata nova por RETURNING',
            'ret-novo-a1.pdf',decode(repeat('a1',32),'hex'),2,2048) returning id$$),
  'PASSOU(1)',
  'A1 editora com aal2 CONSEGUE `insert ... returning` em documentos (regressao de 8e126fe: '
  'com o predicado nao-local isto dava 42501 para todo mundo e travava o upload)');

-- O par de controle: o MESMO insert sem `returning`. Antes do hotfix este passava e A1 nao —
-- essa diferenca E o defeito. Os dois asserts so significam alguma coisa juntos.
select is( pg_temp.classifica('authenticated','00000000-0000-0000-0000-0000000008e1','aal2',
  'public.documentos','INSERT',
  $$insert into public.documentos (id,tipo,titulo,storage_path,sha256,paginas,bytes)
    values ('30000000-0000-0000-0000-0000000080a2','ata_assembleia','Ata nova sem returning',
            'ret-novo-a2.pdf',decode(repeat('a2',32),'hex'),2,2048)$$),
  'PASSOU(1)',
  'A2 o MESMO insert sem `returning` tambem passa — o par A1/A2 e o teste: se um dia A2 passar '
  'e A1 nao, a policy de SELECT voltou a reconsultar documentos');

select is( pg_temp.devolve('authenticated','00000000-0000-0000-0000-0000000008e1','aal2',
  $$insert into public.documentos (id,tipo,titulo,storage_path,sha256,paginas,bytes)
    values ('30000000-0000-0000-0000-0000000080a3','ata_assembleia','Ata que volta pelo RETURNING',
            'ret-novo-a3.pdf',decode(repeat('a3',32),'hex'),2,2048) returning titulo$$),
  'Ata que volta pelo RETURNING',
  'A3 o `returning` DEVOLVE a linha nova de fato (nao basta nao explodir: a aplicacao precisa '
  'do id/titulo de volta para seguir o pipeline)');

select is( pg_temp.classifica('authenticated','00000000-0000-0000-0000-0000000008e1','aal1',
  'public.documentos','INSERT',
  $$insert into public.documentos (id,tipo,titulo,storage_path,sha256,paginas,bytes)
    values ('30000000-0000-0000-0000-0000000080a4','ata_assembleia','Ata da editora em aal1',
            'ret-novo-a4.pdf',decode(repeat('a4',32),'hex'),2,2048) returning id$$),
  'NEGADO-RLS',
  'A4 editora em AAL1 continua negada pela POLICY (TOTP obrigatorio, ADR-0003) — o hotfix nao '
  'afrouxou quem escreve, so tornou o predicado local');

select is( pg_temp.classifica('authenticated','00000000-0000-0000-0000-0000000008c1','aal2',
  'public.documentos','INSERT',
  $$insert into public.documentos (id,tipo,titulo,storage_path,sha256,paginas,bytes)
    values ('30000000-0000-0000-0000-0000000080a5','ata_assembleia','Ata do conselho',
            'ret-novo-a5.pdf',decode(repeat('a5',32),'hex'),2,2048) returning id$$),
  'NEGADO-RLS',
  'A5 conselho em AAL2 NAO publica documento (D4: contrapeso de LEITURA, escrita e do editor)');

select is( pg_temp.classifica('authenticated','00000000-0000-0000-0000-0000000008a1','aal1',
  'public.documentos','INSERT',
  $$insert into public.documentos (id,tipo,titulo,storage_path,sha256,paginas,bytes)
    values ('30000000-0000-0000-0000-0000000080a6','ata_assembleia','Ata do morador',
            'ret-novo-a6.pdf',decode(repeat('a6',32),'hex'),2,2048) returning id$$),
  'NEGADO-RLS',
  'A6 morador nao publica documento');

select is( pg_temp.classifica('anon',null,null,
  'public.documentos','INSERT',
  $$insert into public.documentos (id,tipo,titulo,storage_path,sha256,paginas,bytes)
    values ('30000000-0000-0000-0000-0000000080a7','ata_assembleia','Ata do anonimo',
            'ret-novo-a7.pdf',decode(repeat('a7',32),'hex'),2,2048) returning id$$),
  'NEGADO-GRANT',
  'A7 anonimo e barrado ANTES da policy, na camada de privilegio: `anon` so tem SELECT em '
  'documentos. Camada diferente de A4-A6, mesmo sqlstate 42501 — por isso a matriz nomeia a '
  'camada em vez de so dizer "42501"');

-- A8 e o caminho REAL do pipeline, e o que mais depende do predicado ser local: o documento
-- nasce `pendente` (o worker so publica depois de extrair e indexar). Com `status <> 'publicado'`,
-- o segundo operando de documentos_select e falso por construcao — quem autoriza o RETURNING e
-- SO `app.eh_gestao()`. Se alguem "endurecer" a policy tirando eh_gestao() do lado esquerdo do
-- `or`, A1 (que tambem insere pendente) e A8 caem juntos e a ingestao para.
select is( pg_temp.classifica('authenticated','00000000-0000-0000-0000-0000000008e1','aal2',
  'public.documentos','INSERT',
  $$insert into public.documentos (id,tipo,titulo,storage_path,sha256,paginas,bytes,visibilidade)
    values ('30000000-0000-0000-0000-0000000080a8','ata_conselho','Ata de conselho recem-enviada',
            'ret-novo-a8.pdf',decode(repeat('a8',32),'hex'),2,2048,'conselho') returning id$$),
  'PASSOU(1)',
  'A8 a editora consegue `insert ... returning` de documento AINDA NAO PUBLICADO e de '
  'visibilidade `conselho` — o caso do pipeline, em que so `app.eh_gestao()` autoriza a leitura '
  'da linha que acabou de nascer');

-- ======================================================================
-- B. documentos — UPDATE ... RETURNING, a mesma matriz
-- ======================================================================
-- HONESTIDADE SOBRE O ALCANCE DE B1/B2, medida e nao suposta: reintroduzindo o predicado
-- nao-local (`using (app.documento_visivel(id))`) e rodando este arquivo, A1/A3/E2/F1/F2 ficam
-- VERMELHOS e B1/B2 continuam VERDES. O motivo e preciso e vale registrar: no UPDATE a releitura
-- ENCONTRA a linha — a versao ANTIGA, que ja existia antes do comando e portanto e visivel no
-- snapshot — e para a editora `eh_gestao()` dentro de documento_visivel devolve true de qualquer
-- jeito. So o INSERT nao tem versao antiga nenhuma para achar. Ou seja: em `documentos` o defeito
-- e observavel pelo INSERT, nao pelo UPDATE, ao contrario do que o texto da migracao sugere.
-- B1-B6 nao sao, portanto, detectores desta regressao especifica: sao a metade da matriz que
-- prova que o hotfix nao afrouxou a ESCRITA de ninguem, e a base do contraste do bloco C.
select is( pg_temp.classifica('authenticated','00000000-0000-0000-0000-0000000008e1','aal2',
  'public.documentos','UPDATE',
  $$update public.documentos set titulo='Ata alvo (editada)'
     where id='30000000-0000-0000-0000-000000008001' returning id$$),
  'PASSOU(1)',
  'B1 editora com aal2 CONSEGUE `update ... returning` em documentos');

select is( pg_temp.devolve('authenticated','00000000-0000-0000-0000-0000000008e1','aal2',
  $$update public.documentos set titulo='Ata alvo (editada)'
     where id='30000000-0000-0000-0000-000000008001' returning titulo$$),
  'Ata alvo (editada)',
  'B2 o `returning` de UPDATE devolve o valor NOVO — e o novo que a policy de SELECT precisa '
  'aprovar, e e por ele que a nao-localidade quebraria');

select is( pg_temp.classifica('authenticated','00000000-0000-0000-0000-0000000008e1','aal1',
  'public.documentos','UPDATE',
  $$update public.documentos set titulo='Editada em aal1'
     where id='30000000-0000-0000-0000-000000008001' returning id$$),
  'SILENCIO(0)',
  'B3 editora em AAL1 nao edita — e o UPDATE NAO levanta erro: o USING filtra a linha e o '
  'comando afeta ZERO linhas. Este e o caso que um assert preguicoso ("bloqueou, ok") '
  'confundiria com A4');

select is( pg_temp.classifica('authenticated','00000000-0000-0000-0000-0000000008c1','aal2',
  'public.documentos','UPDATE',
  $$update public.documentos set titulo='Editada pelo conselho'
     where id='30000000-0000-0000-0000-000000008001' returning id$$),
  'SILENCIO(0)',
  'B4 conselho em AAL2 nao edita documento (silencioso, zero linhas)');

select is( pg_temp.classifica('authenticated','00000000-0000-0000-0000-0000000008a1','aal1',
  'public.documentos','UPDATE',
  $$update public.documentos set titulo='Editada pelo morador'
     where id='30000000-0000-0000-0000-000000008001' returning id$$),
  'SILENCIO(0)',
  'B5 morador nao edita documento (silencioso, zero linhas)');

select is( pg_temp.classifica('anon',null,null,
  'public.documentos','UPDATE',
  $$update public.documentos set titulo='Editada pelo anonimo'
     where id='30000000-0000-0000-0000-000000008001' returning id$$),
  'NEGADO-GRANT',
  'B6 anonimo nao tem sequer UPDATE em documentos — barrado no privilegio, nao no silencio');

-- ======================================================================
-- C. "Negado" nao e "nao fez nada" — a prova de que SILENCIO(0) e mesmo zero escrita
-- ======================================================================
-- SILENCIO(0) diz que o comando afetou zero linhas. Falta provar que nao afetou nenhuma OUTRA:
-- um UPDATE sem WHERE, barrado pelo USING, poderia em tese passar por cima do acervo inteiro.
select is( pg_temp.classifica('authenticated','00000000-0000-0000-0000-0000000008a1','aal1',
  'public.documentos','UPDATE',
  $$update public.documentos set visibilidade='publico' where true returning id$$),
  'SILENCIO(0)',
  'C1 UPDATE de morador SEM where nenhum tambem afeta zero linhas — o USING nao deixa nenhuma '
  'linha do acervo entrar no comando');

select is( pg_temp.probe('authenticated','00000000-0000-0000-0000-0000000008e1','aal2',
  $$select titulo from public.documentos where id='30000000-0000-0000-0000-000000008001'$$),
  'Ata alvo da matriz RETURNING',
  'C2 depois de B3-B6 e C1 o titulo original esta intacto — os SILENCIO(0) foram silencio de '
  'verdade, nao escrita invisivel');

-- ======================================================================
-- D. A afirmacao do `eng-supabase`, EXECUTADA (pessoas / papeis / vinculos)
-- ======================================================================
-- Ele afirmou que nenhuma outra tabela tem o defeito porque em `pessoas`/`papeis` a releitura
-- so aparece no segundo operando de um `or` cujo primeiro operando e local. Rodando, a
-- CONCLUSAO se confirma mas o ARGUMENTO nao se sustenta como escrito, e a diferenca importa:
--
--   * pessoas_select = `id = app.pessoa_atual() or app.eh_gestao()`. NAO existe operando que
--     deixe de tocar `pessoas`: `pessoa_atual()` le `pessoas`, e `eh_gestao() -> tem_papel()`
--     tambem le `pessoas` (join com papeis). Os DOIS operandos releem a tabela.
--   * vinculos_select = `unidade_id in (select app.unidades_da_pessoa()) or app.eh_gestao()`,
--     e `unidades_da_pessoa()` le `public.vinculos` — a PROPRIA tabela. O comentario da migracao
--     20260906100500 lista `vinculos_select` entre as que "nenhuma reconsulta a PROPRIA tabela".
--     Isso esta factualmente errado; a varredura do bloco F pega `vinculos`.
--
-- O que de fato salva as tres nao e "o outro operando e local": e que a releitura procura a
-- linha DO SUJEITO DA SESSAO, que ja existia antes do comando e por isso e visivel no snapshot —
-- diferente de `documento_visivel`, que procurava a LINHA QUE O COMANDO ESTAVA CRIANDO. Essa e a
-- distincao que separa "nao-local mas inofensivo" de "nao-local e quebrado", e nenhum comentario
-- a registrava. Os asserts abaixo prendem a conclusao pelo COMPORTAMENTO, que e o que vale.
select is( pg_temp.classifica('authenticated','00000000-0000-0000-0000-0000000008e1','aal2',
  'public.pessoas','INSERT',
  $$insert into public.pessoas (id,nome) values
    ('20000000-0000-0000-0000-0000000080d1','Pessoa criada por RETURNING') returning id$$),
  'PASSOU(1)',
  'D1 pessoas: `insert ... returning` da editora passa (a releitura de pessoas encontra a linha '
  'DA EDITORA, que e anterior ao comando, nao a linha nascendo)');

select is( pg_temp.devolve('authenticated','00000000-0000-0000-0000-0000000008e1','aal2',
  $$update public.pessoas set telefone='11999990000'
     where id='20000000-0000-0000-0000-0000000008e1' returning nome$$),
  'Edna Editora',
  'D2 pessoas: a editora edita a PROPRIA linha com `returning` — o caso mais proximo do defeito '
  '(o predicado avalia a linha que o comando esta reescrevendo) e ainda assim passa');

select is( pg_temp.classifica('authenticated','00000000-0000-0000-0000-0000000008e1','aal2',
  'public.papeis','INSERT',
  $$insert into public.papeis (id,pessoa_id,papel) values
    ('50000000-0000-0000-0000-0000000080d3','20000000-0000-0000-0000-000000000821',
     'morador') returning id$$),
  'PASSOU(1)',
  'D3 papeis: conceder papel a terceiro com `returning` passa, apesar de eh_gestao() reler papeis');

select is( pg_temp.classifica('authenticated','00000000-0000-0000-0000-0000000008e1','aal2',
  'public.papeis','UPDATE',
  $$update public.papeis set motivo='ajuste da matriz'
     where pessoa_id='20000000-0000-0000-0000-0000000008e1' and papel='editor' returning id$$),
  'PASSOU(1)',
  'D4 papeis: a editora reescreve o PROPRIO papel com `returning` — a releitura de papeis dentro '
  'do mesmo comando ainda enxerga a versao antiga da linha, que continua vigente');

select is( pg_temp.classifica('authenticated','00000000-0000-0000-0000-0000000008e1','aal2',
  'public.vinculos','INSERT',
  $$insert into public.vinculos (id,unidade_id,pessoa_id,tipo) values
    ('60000000-0000-0000-0000-0000000080d5','10000000-0000-0000-0000-000000008199',
     '20000000-0000-0000-0000-000000000821','proprietario') returning id$$),
  'PASSOU(1)',
  'D5 vinculos: `insert ... returning` passa — mas SO porque quem escreve e a editora, e '
  '`eh_gestao()` (que nao le vinculos) resolve o `or` sozinho. Se algum dia um morador puder '
  'registrar o proprio vinculo, `unidades_da_pessoa()` volta a ser o unico caminho de decisao e '
  'a classe reaparece exatamente como em documentos. Este assert e o marcador desse risco');

select is( pg_temp.classifica('authenticated','00000000-0000-0000-0000-0000000008e1','aal2',
  'public.documento_unidades','INSERT',
  $$insert into public.documento_unidades (documento_id,unidade_id) values
    ('30000000-0000-0000-0000-000000008002','10000000-0000-0000-0000-000000008199')
    returning documento_id$$),
  'PASSOU(1)',
  'D6 documento_unidades: `insert ... returning` passa (le vinculos, tabela ALHEIA — sem colisao '
  'de comando)');

-- ======================================================================
-- E. A PROPRIEDADE: o mesmo INSERT com e sem `returning` da o mesmo resultado, em TODA tabela
--    em que um papel de usuario escreve
-- ======================================================================
-- Varrer `pg_policies` procurando expressao que chame funcao que leia a mesma tabela da um
-- CANARIO (bloco F), nao uma prova: a decisao depende de QUEM escreve e de QUAL linha o
-- predicado procura, coisas que nao estao no catalogo. A prova e comportamental e e esta:
-- exercitar as duas formas do MESMO comando em todas as tabelas escritas por papel de usuario.
-- O texto do insert e escrito UMA vez; a variante com `returning` e o mesmo texto + a clausula.
create table pg_temp.alvos (
  tabela text primary key,
  sub    text not null,
  aal    text not null,
  ins    text not null,
  retorno text not null
);

insert into pg_temp.alvos values
 ('assembleias','00000000-0000-0000-0000-0000000008e1','aal2',
  $$insert into public.assembleias (id,tipo,data) values ('61000000-0000-0000-0000-000000008e01','age',current_date)$$,'id'),
 ('cobrancas','00000000-0000-0000-0000-0000000008e1','aal2',
  $$insert into public.cobrancas (id,unidade_id,competencia,valor_centavos,vencimento) values ('81000000-0000-0000-0000-000000008e01','10000000-0000-0000-0000-000000008199',date_trunc('month',current_date)::date,4321,current_date+7)$$,'id'),
 ('configuracoes','00000000-0000-0000-0000-0000000008e1','aal2',
  $$insert into public.configuracoes (chave,valor) values ('matriz.returning.teste','{}'::jsonb)$$,'chave'),
 ('contas','00000000-0000-0000-0000-0000000008e1','aal2',
  $$insert into public.contas (id,codigo,nome,natureza,nivel,conta_pai_id,aceita_lancamento) values ('41000000-0000-0000-0000-000000008e01','ZZ8.9.2','Conta folha da matriz','despesa',3,'40000000-0000-0000-0000-000000008002',true)$$,'id'),
 ('contratos','00000000-0000-0000-0000-0000000008e1','aal2',
  $$insert into public.contratos (id,fornecedor_id,objeto,vigencia_inicio) values ('51000000-0000-0000-0000-000000008e01','50000000-0000-0000-0000-000000008001','Objeto da matriz',current_date)$$,'id'),
 ('deliberacoes','00000000-0000-0000-0000-0000000008e1','aal2',
  $$insert into public.deliberacoes (id,assembleia_id,item,descricao,resultado) values ('62000000-0000-0000-0000-000000008e01','60000000-0000-0000-0000-000000008001',99,'Deliberacao da matriz','aprovado')$$,'id'),
 ('documento_unidades','00000000-0000-0000-0000-0000000008e1','aal2',
  $$insert into public.documento_unidades (documento_id,unidade_id) values ('30000000-0000-0000-0000-000000008002','10000000-0000-0000-0000-000000008199')$$,'documento_id'),
 ('documentos','00000000-0000-0000-0000-0000000008e1','aal2',
  $$insert into public.documentos (id,tipo,titulo,storage_path,sha256,paginas,bytes) values ('31000000-0000-0000-0000-000000008e01','balancete','Documento da matriz','matriz-doc.pdf',decode(repeat('e1',32),'hex'),3,3072)$$,'id'),
 ('fornecedor_dados_bancarios','00000000-0000-0000-0000-0000000008e1','aal2',
  $$insert into public.fornecedor_dados_bancarios (id,fornecedor_id,banco,conta_mascarada) values ('52000000-0000-0000-0000-000000008e01','50000000-0000-0000-0000-000000008001','001','****0000')$$,'id'),
 ('fornecedores','00000000-0000-0000-0000-0000000008e1','aal2',
  $$insert into public.fornecedores (id,cnpj,razao_social) values ('53000000-0000-0000-0000-000000008e01','98765432000188','Fornecedor da matriz')$$,'id'),
 ('lancamento_anexos','00000000-0000-0000-0000-0000000008e1','aal2',
  $$insert into public.lancamento_anexos (id,lancamento_id,storage_path,sha256,tipo,enviado_por) values ('71000000-0000-0000-0000-000000008e01','70000000-0000-0000-0000-000000008001','matriz-anexo.pdf',decode(repeat('e2',32),'hex'),'nota_fiscal','20000000-0000-0000-0000-0000000008e1')$$,'id'),
 ('lancamentos','00000000-0000-0000-0000-0000000008e1','aal2',
  $$insert into public.lancamentos (id,data_competencia,conta_id,historico,valor_centavos,tipo,documento_id,pagina_origem,criado_por) values ('72000000-0000-0000-0000-000000008e01',date_trunc('month',current_date)::date,'40000000-0000-0000-0000-000000008003','Lancamento da matriz',999,'despesa','30000000-0000-0000-0000-000000008001',2,'20000000-0000-0000-0000-0000000008e1')$$,'id'),
 ('orcamento','00000000-0000-0000-0000-0000000008e1','aal2',
  $$insert into public.orcamento (id,exercicio,conta_id,mes,valor_previsto_centavos) values ('43000000-0000-0000-0000-000000008e01',2099,'40000000-0000-0000-0000-000000008003',7,5000)$$,'id'),
 ('papeis','00000000-0000-0000-0000-0000000008e1','aal2',
  $$insert into public.papeis (id,pessoa_id,papel) values ('54000000-0000-0000-0000-000000008e01','20000000-0000-0000-0000-000000000821','morador')$$,'id'),
 -- pareceres e parecer_signatarios sao a UNICA escrita do conselho (SPEC §2.1); rodar como
 -- editora daria NEGADO-RLS nas duas variantes e o teste passaria vazio.
 ('parecer_signatarios','00000000-0000-0000-0000-0000000008c1','aal2',
  $$insert into public.parecer_signatarios (parecer_id,pessoa_id) values ('90000000-0000-0000-0000-000000008001','20000000-0000-0000-0000-0000000008c1')$$,'parecer_id'),
 ('pareceres','00000000-0000-0000-0000-0000000008c1','aal2',
  $$insert into public.pareceres (id,competencia_inicio,competencia_fim,texto) values ('91000000-0000-0000-0000-000000008e01','1998-01-01','1998-12-01','Parecer da matriz')$$,'id'),
 ('periodos_fechados','00000000-0000-0000-0000-0000000008e1','aal2',
  $$insert into public.periodos_fechados (competencia,fechado_por) values ('1997-03-01','20000000-0000-0000-0000-0000000008e1')$$,'competencia'),
 ('pessoas','00000000-0000-0000-0000-0000000008e1','aal2',
  $$insert into public.pessoas (id,nome) values ('21000000-0000-0000-0000-000000008e01','Pessoa da matriz')$$,'id'),
 ('questionamentos','00000000-0000-0000-0000-0000000008c1','aal2',
  $$insert into public.questionamentos (id,lancamento_id,autor_id,texto) values ('73000000-0000-0000-0000-000000008e01','70000000-0000-0000-0000-000000008001','20000000-0000-0000-0000-0000000008c1','Questionamento aberto pela matriz de teste')$$,'id'),
 ('sinonimos','00000000-0000-0000-0000-0000000008e1','aal2',
  $$insert into public.sinonimos (id,termo,expansoes) values ('44000000-0000-0000-0000-000000008e01','termo-da-matriz-returning',array['expansao'])$$,'id'),
 ('tipos_alerta','00000000-0000-0000-0000-0000000008e1','aal2',
  $$insert into public.tipos_alerta (codigo,nome,severidade_padrao,descricao_regra) values ('matriz_returning','Tipo de alerta da matriz','baixa','regra de teste')$$,'codigo'),
 ('tipos_documento','00000000-0000-0000-0000-0000000008e1','aal2',
  $$insert into public.tipos_documento (codigo,nome) values ('matriz_returning','Tipo de documento da matriz')$$,'codigo'),
 ('unidades','00000000-0000-0000-0000-0000000008e1','aal2',
  $$insert into public.unidades (id,bloco,numero,fracao_ideal) values ('11000000-0000-0000-0000-000000008e01','ZZ8','M01',0.001)$$,'id'),
 ('vinculos','00000000-0000-0000-0000-0000000008e1','aal2',
  $$insert into public.vinculos (id,unidade_id,pessoa_id,tipo) values ('63000000-0000-0000-0000-000000008e01','10000000-0000-0000-0000-000000008199','20000000-0000-0000-0000-000000000821','inquilino')$$,'id');

create function pg_temp.matriz() returns table(tabela text, sem_returning text, com_returning text)
language plpgsql as $f$
declare a record;
begin
  for a in select * from pg_temp.alvos order by tabela loop
    tabela := a.tabela;
    sem_returning := pg_temp.classifica('authenticated', a.sub, a.aal, 'public.'||a.tabela, 'INSERT', a.ins);
    com_returning := pg_temp.classifica('authenticated', a.sub, a.aal, 'public.'||a.tabela, 'INSERT',
                                        a.ins || ' returning ' || a.retorno);
    return next;
  end loop;
end $f$;

create table pg_temp.resultado as select * from pg_temp.matriz();

-- E0 impede que a matriz minta por OMISSAO: se alguem criar uma tabela nova com policy de INSERT
-- para `authenticated` e nao adicionar a linha aqui, este assert quebra antes de E1/E2 passarem
-- verde sem cobrir a tabela nova.
select set_eq(
  $$select tabela from pg_temp.alvos$$,
  $$select c.relname::text from pg_policy pol
      join pg_class c on c.oid = pol.polrelid
      join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
     where pol.polcmd = 'a'
       and 'authenticated' in (select rolname from pg_roles where oid = any(pol.polroles))$$,
  'E0 a matriz cobre TODAS as tabelas com policy de INSERT para authenticated, sem sobra nem falta');

-- E1 impede que a matriz minta por VACUIDADE: se o insert base falhar por constraint, as duas
-- variantes falham igual e E2 passaria sem ter exercitado `returning` nenhuma vez.
select is_empty(
  $$select tabela, sem_returning from pg_temp.resultado where sem_returning <> 'PASSOU(1)'$$,
  'E1 o insert base (sem `returning`) do papel que legitimamente escreve PASSA em todas as 24 '
  'tabelas — sem isto, E2 compararia dois fracassos e chamaria de acordo');

select is_empty(
  $$select tabela, sem_returning, com_returning from pg_temp.resultado
     where com_returning <> sem_returning$$,
  'E2 A PROPRIEDADE: em toda tabela escrita por papel de usuario, acrescentar `returning` NAO '
  'muda o resultado do comando. Divergir e a classe de 8e126fe voltando por outra tabela');

-- ======================================================================
-- F. O canario estatico: quais policies de SELECT reconsultam a PROPRIA tabela
-- ======================================================================
-- Isto NAO decide se ha defeito — decidir exige saber quem escreve e qual linha o predicado
-- procura (ver bloco D). Serve para uma coisa so: obrigar revisao consciente quando o conjunto
-- mudar. A varredura e heuristica (fecho transitivo por regex sobre prosrc, 4 niveis) e esta
-- documentada como tal; o que a torna util e que o conjunto esperado esta CONGELADO abaixo, com
-- justificativa por linha, e qualquer entrada ou saida derruba o CI.
create function pg_temp.policies_que_releem_a_si() returns table(tabela text) language sql stable as $f$
  with recursive
  sel as (
    select c.relname::text as tabela,
           coalesce(pg_get_expr(pol.polqual, pol.polrelid), '') as expr
      from pg_policy pol
      join pg_class c on c.oid = pol.polrelid
      join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
     where pol.polcmd = 'r'
  ),
  raiz as (
    select s.tabela, p.oid as fnoid, 0 as nivel
      from sel s
      join pg_proc p on true
      join pg_namespace fn on fn.oid = p.pronamespace
     where fn.nspname in ('app','public')
       and p.proname ~ '^[a-z_][a-z0-9_]*$'
       and s.expr ~ ('\m' || fn.nspname || '\.' || p.proname || '\s*\(')
  ),
  fecho as (
    select tabela, fnoid, nivel from raiz
    union
    select f.tabela, p2.oid, f.nivel + 1
      from fecho f
      join pg_proc p1 on p1.oid = f.fnoid
      join pg_proc p2 on true
      join pg_namespace n2 on n2.oid = p2.pronamespace
     where f.nivel < 4
       and n2.nspname in ('app','public')
       and p2.proname ~ '^[a-z_][a-z0-9_]*$'
       and p2.oid <> p1.oid
       and p1.prosrc ~ ('\m' || n2.nspname || '\.' || p2.proname || '\s*\(')
  )
  select distinct f.tabela
    from fecho f
    join pg_proc p on p.oid = f.fnoid
   where p.prosrc ~* ('(from|join)\s+(public\.)?' || f.tabela || '\M');
$f$;

select set_eq(
  $$select tabela from pg_temp.policies_que_releem_a_si()$$,
  $$values ('documento_paginas'),('papeis'),('pessoas'),('vinculos')$$,
  'F1 o conjunto de policies de SELECT que reconsultam a propria tabela esta CONGELADO em quatro '
  '(documento_paginas: nivel_efetivo; papeis: tem_papel; pessoas: pessoa_atual+tem_papel; '
  'vinculos: unidades_da_pessoa). Entrar ou sair alguem exige decisao humana, nao merge');

select ok(
  not exists (select 1 from pg_temp.policies_que_releem_a_si() where tabela = 'documentos'),
  'F2 `documentos` NAO esta mais no conjunto — documentos_select virou predicado local em '
  '20260906100500. Se voltar, este assert cai antes de A1');

-- A isencao de documento_paginas e chunks (bloco F1 inclui documento_paginas) repousa numa
-- PREMISSA: nenhum papel de usuario escreve nessas tabelas, so o worker por service_role, que
-- bypassa RLS e nunca avalia policy. Premissa nao verificada e premissa que expira em silencio.
select is(
  (select coalesce(string_agg(distinct c.relname, ',' order by c.relname),'(nenhuma)')
     from pg_policy pol
     join pg_class c on c.oid = pol.polrelid
     join pg_namespace n on n.oid = c.relnamespace and n.nspname='public'
    where c.relname in ('documento_paginas','chunks')
      and pol.polcmd <> 'r'),
  '(nenhuma)',
  'F3 PREMISSA da isencao: documento_paginas e chunks nao tem policy de INSERT/UPDATE/DELETE '
  'para papel de usuario. No dia em que ganharem uma, nivel_efetivo reconsultando '
  'documento_paginas vira o mesmo defeito de documentos — e este assert cai');

-- Armadilha nº1 (SPEC §7): espelhar CHAMANDO A MESMA FUNCAO, nunca copiando o predicado.
select is(
  (select string_agg(c.relname||'='||pg_get_expr(pol.polqual,pol.polrelid), ' | ' order by c.relname)
     from pg_policy pol
     join pg_class c on c.oid = pol.polrelid
     join pg_namespace n on n.oid = c.relnamespace and n.nspname='public'
    where c.relname in ('documento_paginas','chunks') and pol.polcmd='r'),
  'chunks=app.pagina_visivel(documento_id, pagina_ini) | '
  'documento_paginas=app.pagina_visivel(documento_id, pagina)',
  'F4 chunks e documento_paginas espelham documentos pela MESMA funcao app.pagina_visivel, sem '
  'predicado copiado — copia diverge e diverge calado (SPEC §7, armadilha nº1)');

-- O hotfix passou a chamar `app.nivel_visivel(...)` DIRETO da policy. Antes, `anon` so a
-- alcancava por dentro de `app.documento_visivel`, que e SECURITY DEFINER — a checagem de EXECUTE
-- de chamada aninhada roda com o privilegio do DONO, nao do chamador, e por isso `anon` nunca
-- precisou de GRANT proprio. Chamando direto, sem o GRANT, todo documento PUBLICO viraria 42501
-- para visitante nao logado: o hotfix de um vazamento de disponibilidade criaria outro.
select ok(
  has_function_privilege('anon','app.nivel_visivel(public.visibilidade_documento,uuid)','EXECUTE'),
  'F5 `anon` tem EXECUTE em app.nivel_visivel — o GRANT que o predicado local passou a exigir; '
  'sem ele, documento publico some para quem nao tem conta');

select finish();
rollback;
