-- ============================================================================
-- Breeze — F1 corte C4: INV-13 (docs/invariantes/INV-13-derivado-invalidado-implica-reconstrucao-
-- enfileirada.md) — "documento publicado com indexado_em is null ⇒ existe job pendente/processando
-- de chunking, ou a sentinela mostra". Fecha o bug E2 (docs/ops/divida-tecnica.md), ADR-0026.
--
-- Migração sob teste: 20260906140000_reprocessamento_enfileirado_e_sentinela.sql.
--
-- Os QUATRO CAMINHOS VERMELHOS que o ADR-0026 pede (§6), um bloco cada, todos com o MESMO par de
-- asserts: (a) existe job `chunking` pendente/processando com a chave certa, (b) o documento
-- aparece em app.documentos_fora_da_busca. Um bloco final (E) prova a armadilha que o corte
-- existe para NÃO reintroduzir: a MESMA chave de reenfileiramento funciona de novo depois que o
-- job anterior CONCLUIU (unicidade parcial, ADR-0025 §2) — sem isso, "apagar chunk a mão" na
-- SEGUNDA vez seria um no-op silencioso, o próprio E2 embutido no mecanismo que deveria fechá-lo.
--
-- Auto-contido (begin/rollback). Mutações de documento_paginas/chunks rodam como `postgres`
-- (superuser, bypassa RLS por construção — mesmo padrão de setup de fixture usado em
-- 01/02/03/06/07): o que este arquivo mede é o MECANISMO de invalidação/reenfileiramento, não
-- "quem pode escrever" (isso já é coberto por 04_privilegios_grants_e_superficie.sql e pelo
-- comentário da própria tabela — "Escrita: NENHUM papel de usuário. Só o worker, por
-- service_role"). Só o bloco F (grant/gate da sentinela) impersona papel, via pg_temp.probe.
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
  return coalesce(r, '(vazio)');
end $f$;

-- A sentinela é gated por app.eh_gestao() (bloco F prova o gate em si) — para os blocos A-D, que
-- medem o MECANISMO de invalidação, ler a view como a editora (aal2) via este atalho evita
-- repetir o probe inteiro em cada bloco.
create function pg_temp.na_sentinela(p_documento_id uuid) returns boolean
language sql as $f$
  select pg_temp.probe('authenticated', '98000000-0000-0000-0000-0000000000e1', 'aal2',
    format('select (count(*) > 0)::text from app.documentos_fora_da_busca where documento_id = %L',
           p_documento_id)) = 'true'
$f$;

-- ---------------------------------------------------------------------------
-- Fixtures: uma editora (publicado_por + sessão de gestão para o bloco F) e uma moradora
-- (sessão authenticated SEM gestão, para provar que app.eh_gestao() é o portão real da
-- sentinela — GRANT sozinho não bastava no achado V6, mesma lição aqui).
-- ---------------------------------------------------------------------------
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
 ('98000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','c4-editora@t.local',now(),now()),
 ('98000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','c4-moradora@t.local',now(),now());

insert into public.pessoas (id, auth_user_id, nome) values
 ('98000000-0000-0000-0000-0000000000e2','98000000-0000-0000-0000-0000000000e1','Editora C4 (INV-13)'),
 ('98000000-0000-0000-0000-0000000000a2','98000000-0000-0000-0000-0000000000a1','Moradora C4 (INV-13)');

insert into public.papeis (pessoa_id, papel, mandato_inicio) values
 ('98000000-0000-0000-0000-0000000000e2','editor', current_date);

-- Documento A — RECLASSIFICAR PÁGINA. 3 páginas sem override (herdam 'autenticado' do doc);
-- 1 chunk uniforme cobrindo 1-3.
insert into public.documentos (id, tipo, titulo, storage_path, status, visibilidade,
                                publicado_em, publicado_por, versao_pipeline)
values ('98000000-0000-0000-0000-00000000da01', 'ata_assembleia', 'C4 — reclassificar página',
        '/test/c4-doc-a.pdf', 'publicado', 'autenticado', now(),
        '98000000-0000-0000-0000-0000000000e2', 1);
insert into public.documento_paginas (documento_id, pagina, texto) values
 ('98000000-0000-0000-0000-00000000da01', 1, 'p1'),
 ('98000000-0000-0000-0000-00000000da01', 2, 'p2'),
 ('98000000-0000-0000-0000-00000000da01', 3, 'p3');
insert into public.chunks (documento_id, pagina_ini, pagina_fim, ordem, texto, versao_pipeline)
values ('98000000-0000-0000-0000-00000000da01', 1, 3, 0, 'p1 p2 p3', 1);
update public.documentos set indexado_em = now() where id = '98000000-0000-0000-0000-00000000da01';

-- Documento B — APAGAR PÁGINA. 3 páginas TODAS com override 'publico' (piso do doc é
-- 'autenticado' — override só pode ampliar, ADR-0019/D13); chunk uniforme em 'publico'.
-- Apagar a página do meio derruba o override dela para o piso do documento e quebra a
-- uniformidade do chunk.
insert into public.documentos (id, tipo, titulo, storage_path, status, visibilidade,
                                publicado_em, publicado_por, versao_pipeline)
values ('98000000-0000-0000-0000-00000000da02', 'ata_assembleia', 'C4 — apagar página',
        '/test/c4-doc-b.pdf', 'publicado', 'autenticado', now(),
        '98000000-0000-0000-0000-0000000000e2', 1);
insert into public.documento_paginas (documento_id, pagina, texto, visibilidade) values
 ('98000000-0000-0000-0000-00000000da02', 1, 'p1', 'publico'),
 ('98000000-0000-0000-0000-00000000da02', 2, 'p2', 'publico'),
 ('98000000-0000-0000-0000-00000000da02', 3, 'p3', 'publico');
insert into public.chunks (documento_id, pagina_ini, pagina_fim, ordem, texto, versao_pipeline)
values ('98000000-0000-0000-0000-00000000da02', 1, 3, 0, 'p1 p2 p3', 1);
update public.documentos set indexado_em = now() where id = '98000000-0000-0000-0000-00000000da02';

-- Documento C — APAGAR CHUNK À MÃO. 1 página, 1 chunk. Sem nenhuma mudança em documento_paginas.
insert into public.documentos (id, tipo, titulo, storage_path, status, visibilidade,
                                publicado_em, publicado_por, versao_pipeline)
values ('98000000-0000-0000-0000-00000000da03', 'ata_assembleia', 'C4 — apagar chunk à mão',
        '/test/c4-doc-c.pdf', 'publicado', 'autenticado', now(),
        '98000000-0000-0000-0000-0000000000e2', 1);
insert into public.documento_paginas (documento_id, pagina, texto) values
 ('98000000-0000-0000-0000-00000000da03', 1, 'p1');
insert into public.chunks (documento_id, pagina_ini, pagina_fim, ordem, texto, versao_pipeline)
values ('98000000-0000-0000-0000-00000000da03', 1, 1, 0, 'p1', 1);
update public.documentos set indexado_em = now() where id = '98000000-0000-0000-0000-00000000da03';

-- Documento D — MUDAR versao_pipeline. 1 página, 1 chunk na versão 1.
insert into public.documentos (id, tipo, titulo, storage_path, status, visibilidade,
                                publicado_em, publicado_por, versao_pipeline)
values ('98000000-0000-0000-0000-00000000da04', 'ata_assembleia', 'C4 — mudar versao_pipeline',
        '/test/c4-doc-d.pdf', 'publicado', 'autenticado', now(),
        '98000000-0000-0000-0000-0000000000e2', 1);
insert into public.documento_paginas (documento_id, pagina, texto) values
 ('98000000-0000-0000-0000-00000000da04', 1, 'p1');
insert into public.chunks (documento_id, pagina_ini, pagina_fim, ordem, texto, versao_pipeline)
values ('98000000-0000-0000-0000-00000000da04', 1, 1, 0, 'p1', 1);
update public.documentos set indexado_em = now() where id = '98000000-0000-0000-0000-00000000da04';

-- ---------------------------------------------------------------------------
-- Estrutura (forma), antes de qualquer mutação.
-- ---------------------------------------------------------------------------
select has_column('public', 'documentos', 'indexado_em',
  'T01 documentos.indexado_em existe');
select has_index('public', 'documentos', 'documentos_fora_da_busca_idx',
  'T02 índice parcial (status publicado, indexado_em null) existe');
select has_view('app', 'documentos_fora_da_busca',
  'T03 view sentinela app.documentos_fora_da_busca existe');
select has_trigger('public', 'chunks', 'chunks_marca_indexado',
  'T04 trigger chunks_marca_indexado existe');
select has_trigger('public', 'chunks', 'chunks_invalida_documento',
  'T05 trigger chunks_invalida_documento existe');
select has_trigger('public', 'documentos', 'documentos_versao_pipeline_invalida_indexacao',
  'T06 trigger documentos_versao_pipeline_invalida_indexacao existe');

-- Pré-condição, para os quatro documentos: indexado, sem job pendente, fora da sentinela — o
-- sinal que os blocos abaixo criam tem de ser NOVO, não coincidência de estado inicial.
select is(
  (select count(*)::int from public.documentos
     where id in ('98000000-0000-0000-0000-00000000da01','98000000-0000-0000-0000-00000000da02',
                  '98000000-0000-0000-0000-00000000da03','98000000-0000-0000-0000-00000000da04')
       and indexado_em is null),
  0,
  'T07 pré-condição: os quatro documentos nascem com indexado_em preenchido');

select is(
  (select count(*)::int from job.fila
     where payload ->> 'documento_id' in ('98000000-0000-0000-0000-00000000da01','98000000-0000-0000-0000-00000000da02',
                  '98000000-0000-0000-0000-00000000da03','98000000-0000-0000-0000-00000000da04')
       and status in ('pendente','processando')),
  0,
  'T08 pré-condição: nenhum job de chunking pendente para os quatro documentos ainda');

-- ============================================================================
-- BLOCO A — reclassificar página (UPDATE documento_paginas.visibilidade)
-- ============================================================================
update public.documento_paginas set visibilidade = 'publico'
 where documento_id = '98000000-0000-0000-0000-00000000da01' and pagina = 2;

select is(
  (select count(*)::int from public.chunks where documento_id = '98000000-0000-0000-0000-00000000da01'),
  0,
  'T09 A: o chunk que cruzava a página reclassificada foi apagado');

select ok(
  exists (select 1 from job.fila
            where chave_idempotencia = 'chunking:98000000-0000-0000-0000-00000000da01:v1'
              and status in ('pendente','processando')),
  'T10 A: job de chunking pendente/processando com a chave certa foi criado');

select ok(
  pg_temp.na_sentinela('98000000-0000-0000-0000-00000000da01'),
  'T11 A: documento aparece na sentinela (lida como gestão — a view é gated por app.eh_gestao())');

-- ============================================================================
-- BLOCO B — apagar página (DELETE documento_paginas) — o caminho que a baseline 08 NÃO cobria
-- ============================================================================
delete from public.documento_paginas
 where documento_id = '98000000-0000-0000-0000-00000000da02' and pagina = 2;

select is(
  (select count(*)::int from public.chunks where documento_id = '98000000-0000-0000-0000-00000000da02'),
  0,
  'T12 B: o chunk que cruzava a página apagada foi invalidado (apagado)');

select ok(
  exists (select 1 from job.fila
            where chave_idempotencia = 'chunking:98000000-0000-0000-0000-00000000da02:v1'
              and status in ('pendente','processando')),
  'T13 B: job de chunking pendente/processando foi criado para a página apagada');

select ok(
  pg_temp.na_sentinela('98000000-0000-0000-0000-00000000da02'),
  'T14 B: documento aparece na sentinela');

-- ============================================================================
-- BLOCO C — apagar chunk à mão (DELETE chunks direto, sem tocar documento_paginas)
-- ============================================================================
delete from public.chunks where documento_id = '98000000-0000-0000-0000-00000000da03';

select is(
  (select indexado_em from public.documentos where id = '98000000-0000-0000-0000-00000000da03'),
  null::timestamptz,
  'T15 C: indexado_em zera quando o chunk é apagado à mão (célula ACEITO da INV-13, agora com sinal)');

select ok(
  exists (select 1 from job.fila
            where chave_idempotencia = 'chunking:98000000-0000-0000-0000-00000000da03:v1'
              and status in ('pendente','processando')),
  'T16 C: job de chunking pendente/processando foi criado — DELETE direto não é mais um caminho mudo');

select ok(
  pg_temp.na_sentinela('98000000-0000-0000-0000-00000000da03'),
  'T17 C: documento aparece na sentinela');

-- ============================================================================
-- BLOCO D — mudar versao_pipeline (UPDATE documentos, sem apagar nenhum chunk)
-- ============================================================================
update public.documentos set versao_pipeline = 2 where id = '98000000-0000-0000-0000-00000000da04';

select is(
  (select count(*)::int from public.chunks
     where documento_id = '98000000-0000-0000-0000-00000000da04' and versao_pipeline = 1),
  1,
  'T18 D: o chunk da versão ANTIGA continua existindo — bumpar versao_pipeline não apaga cauda '
      '(ADR-0025 §Consequências: "não vale complicar agora")');

select is(
  (select indexado_em from public.documentos where id = '98000000-0000-0000-0000-00000000da04'),
  null::timestamptz,
  'T19 D: indexado_em zera mesmo sem nenhum DELETE em chunks');

select ok(
  exists (select 1 from job.fila
            where chave_idempotencia = 'chunking:98000000-0000-0000-0000-00000000da04:v2'
              and status in ('pendente','processando')),
  'T20 D: job de chunking pendente/processando foi criado para a VERSÃO NOVA (v2), não a v1');

select ok(
  pg_temp.na_sentinela('98000000-0000-0000-0000-00000000da04'),
  'T21 D: documento aparece na sentinela');

-- ============================================================================
-- BLOCO E — a armadilha (docs/ops/divida-tecnica.md E2): a chave de reenfileiramento funciona
-- DEPOIS que o job anterior CONCLUIU — não só na primeira invalidação. Usa o documento A.
-- Simula também a reconstrução bem-sucedida do worker: DELETE + INSERT na mesma "transação"
-- (este arquivo inteiro já é uma única transação pgTAP) não deixa resíduo nem duplica job.
-- ============================================================================

-- E1: o worker "toma" o job pendente do bloco A.
update job.fila set status = 'processando', iniciado_em = now()
 where chave_idempotencia = 'chunking:98000000-0000-0000-0000-00000000da01:v1'
   and status = 'pendente';

-- E2: reconstrução do worker — chunking() faz DELETE (não há nada para apagar, o bloco A já
-- apagou) + INSERT dos chunks novos, na mesma transação da tomada do job. Três chunks de UMA
-- página cada (não um só cobrindo 1-3): depois da reclassificação do bloco A a página 2 é
-- 'publico' e 1/3 continuam 'autenticado' — um chunk 1-3 seria não-uniforme e a própria trigger
-- de uniformidade (chunks_valida_visibilidade_uniforme) rejeitaria a inserção. É exatamente esta
-- disciplina de fronteira que faz o chunker real reparticionar em vez de reinserir o chunk antigo.
insert into public.chunks (documento_id, pagina_ini, pagina_fim, ordem, texto, versao_pipeline)
values
  ('98000000-0000-0000-0000-00000000da01', 1, 1, 0, 'p1 — reindexado', 1),
  ('98000000-0000-0000-0000-00000000da01', 2, 2, 1, 'p2(publico) — reindexado', 1),
  ('98000000-0000-0000-0000-00000000da01', 3, 3, 2, 'p3 — reindexado', 1);

select is(
  (select count(*)::int from job.fila
     where chave_idempotencia = 'chunking:98000000-0000-0000-0000-00000000da01:v1'
       and status in ('pendente','processando')),
  1,
  'T22 E: ainda existe só UM job ativo para a chave — o INSERT do worker não duplicou trabalho');

select isnt(
  (select indexado_em from public.documentos where id = '98000000-0000-0000-0000-00000000da01'),
  null,
  'T23 E: indexado_em volta a ficar preenchido assim que o chunk novo é inserido (chunks_marca_indexado)');

select ok(
  not pg_temp.na_sentinela('98000000-0000-0000-0000-00000000da01'),
  'T24 E: documento sai da sentinela depois de reindexado');

-- E3: o worker conclui o job.
update job.fila set status = 'concluido', concluido_em = now()
 where chave_idempotencia = 'chunking:98000000-0000-0000-0000-00000000da01:v1'
   and status = 'processando';

-- E4: A ARMADILHA. Reenfileirar a MESMA chave AGORA (job anterior concluído, não mais
-- pendente/processando) precisa criar um job NOVO — é exatamente o caso que a unicidade TOTAL
-- (corrigida em 20260906100100_job_fila_idempotencia_parcial.sql) transformava em no-op
-- silencioso para sempre. Simula "apagar chunk à mão" de novo, depois de já ter sido corrigido
-- uma vez.
delete from public.chunks where documento_id = '98000000-0000-0000-0000-00000000da01';

select is(
  (select count(*)::int from job.fila
     where chave_idempotencia = 'chunking:98000000-0000-0000-0000-00000000da01:v1'
       and status in ('pendente','processando')),
  1,
  'T25 E: reenfileirar a MESMA chave depois que o job anterior CONCLUIU cria um job NOVO — não '
      'zero (a armadilha do E2) e não dois (duplicaria trabalho)');

select is(
  (select count(*)::int from job.fila
     where chave_idempotencia = 'chunking:98000000-0000-0000-0000-00000000da01:v1'),
  2,
  'T26 E: histórico preservado — uma linha concluída + uma pendente nova, para a MESMA chave');

-- ============================================================================
-- BLOCO F — a sentinela é gestão-only: GRANT amplo (authenticated) + app.eh_gestao() no WHERE
-- (mesma lição do achado V6 — GRANT de tabela/view sozinho não é a barreira real).
-- ============================================================================
select ok(
  pg_temp.probe('authenticated', '98000000-0000-0000-0000-0000000000e1', 'aal2',
    $$select documento_id::text from app.documentos_fora_da_busca
        where documento_id = '98000000-0000-0000-0000-00000000da02'$$)
    = '98000000-0000-0000-0000-00000000da02',
  'T27 F: editora (gestão, aal2) enxerga o documento B na sentinela');

select is(
  pg_temp.probe('authenticated', '98000000-0000-0000-0000-0000000000a1', 'aal1',
    $$select count(*)::text from app.documentos_fora_da_busca
        where documento_id = '98000000-0000-0000-0000-00000000da02'$$),
  '0',
  'T28 F: moradora (authenticated, SEM gestão) NÃO enxerga nada na sentinela — app.eh_gestao() '
      'é o portão, não o GRANT');

select ok(
  pg_temp.probe('anon', null, null,
    $$select count(*)::text from app.documentos_fora_da_busca$$) ~ '^ERRO',
  'T29 F: anon nem consegue SELECT na view (sem GRANT — permission denied, nem chega a avaliar o WHERE)');

-- ============================================================================
-- BLOCO G — a coluna indexado_em nunca participa de autorização (ADR-0026 §3): documento com
-- indexado_em NULL continua LEGÍVEL por quem já tinha acesso — só "fora da busca", nunca
-- "fora do acervo". Confirma que este corte não introduziu o erro descartado no próprio ADR
-- (rebaixar status faria o documento sumir inteiro).
-- ============================================================================
select is(
  (select status::text from public.documentos where id = '98000000-0000-0000-0000-00000000da03'),
  'publicado',
  'T30 G: documento C continua "publicado" depois de ter o chunk apagado à mão — status não foi tocado');

-- app.documento_visivel() é STABLE/security definer mas ainda lê app.eh_autenticado()/eh_gestao(),
-- que dependem de auth.uid() — chamado como `postgres` puro (sem JWT) dá sempre falso, então o
-- probe (sessão da editora) é o que isola exatamente a pergunta: "indexado_em null derruba
-- autorização?" — a resposta correta é não, porque a função nem lê a coluna.
select is(
  pg_temp.probe('authenticated', '98000000-0000-0000-0000-0000000000e1', 'aal2',
    $$select app.documento_visivel('98000000-0000-0000-0000-00000000da03')::text$$),
  'true',
  'T31 G: app.documento_visivel() continua TRUE para o documento C — indexado_em null não '
      'derruba autorização (é sinal de estado, não predicado de acesso)');

-- ============================================================================
-- BLOCO H — indexado_em nunca fica preenchido por versão errada.
-- ============================================================================
select is(
  (select count(*)::int from public.chunks
     where documento_id = '98000000-0000-0000-0000-00000000da04' and versao_pipeline = 1),
  1,
  'T32 H: chunk da v1 do documento D ainda existe (não foi tocado pelo bump de versao_pipeline)');

select is(
  (select indexado_em from public.documentos where id = '98000000-0000-0000-0000-00000000da04'),
  null::timestamptz,
  'T33 H: indexado_em do documento D continua NULL — o chunk que existe é da versão ERRADA (v1, '
      'documento já está em v2); chunks_marca_indexado corretamente não o confirmou');

insert into public.chunks (documento_id, pagina_ini, pagina_fim, ordem, texto, versao_pipeline)
values ('98000000-0000-0000-0000-00000000da04', 1, 1, 0, 'p1 — reindexado v2', 2);

select isnt(
  (select indexado_em from public.documentos where id = '98000000-0000-0000-0000-00000000da04'),
  null,
  'T34 H: inserir o chunk da versão CORRENTE (v2) confirma o índice');

select * from finish();
rollback;
