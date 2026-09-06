-- Breeze — F1 corte C4: fecha o bug E2 (docs/ops/divida-tecnica.md) — "documento some da busca em
-- silêncio" — conforme ADR-0026.
--
-- Três peças, na ordem em que o ADR as descreve:
--   1. `documentos.indexado_em` — eixo de ESTADO DA MÁQUINA, ortogonal a `status` (curadoria).
--      Rebaixar `status` faria o documento sumir INTEIRO pela RLS do morador (ADR-0026 §3) — esse
--      é o erro que este corte existe para não cometer.
--   2. O reenfileiramento passa a ser OBRIGAÇÃO DO BANCO, não promessa do worker: toda vez que um
--      chunk é apagado (por qualquer caminho — invalidador de página, ou à mão por service_role) e
--      não é substituído NA MESMA TRANSAÇÃO, `indexado_em` zera e um job de `chunking` é
--      enfileirado, pela função job.enfileirar() (ADR-0025 §2, ADR-0026 §1) — nunca por insert
--      direto. O mecanismo é genérico (trigger em `chunks`, não duplicado em cada chamador) de
--      propósito: um só lugar sabe "o índice ficou desatualizado", em vez de cada caminho que
--      apaga chunk ter de lembrar de chamar job.enfileirar() por conta própria.
--   3. A sentinela `app.documentos_fora_da_busca` — a pergunta com nome que transforma a falha
--      silenciosa em falha visível (ADR-0026 §4).
--
-- INV-13 (docs/invariantes/INV-13-...): "documento publicado com indexado_em is null ⇒ existe job
-- pendente/processando de chunking, ou a sentinela mostra". Matriz completa e testes vermelhos em
-- supabase/tests/09_reprocessamento_enfileirado_sentinela.sql.

-- ============================================================================
-- 1. `documentos.indexado_em` — nullable, escrita só por máquina (triggers desta migração).
-- ============================================================================
alter table public.documentos add column indexado_em timestamptz;

comment on column public.documentos.indexado_em is
  'ADR-0026 §3: eixo de ESTADO DA MÁQUINA, ortogonal a `status` (curadoria) e a `erro_detalhe` '
  '(falha). NULL = sem índice de busca válido para a versao_pipeline corrente — a UI mostra '
  '"reindexando" (documento publicado continua legível/baixável; só a busca está incompleta, e '
  'diz isso). NUNCA participa de autorização — é sinal de estado, não predicado de acesso '
  '(app.documento_visivel/app.pagina_visivel não leem esta coluna). Escrita EXCLUSIVAMENTE pelos '
  'triggers desta migração (chunks_marca_indexado zera→seta; chunks_invalida_documento e '
  'documentos_versao_pipeline_invalida_indexacao zeram) — nenhum código de aplicação escreve '
  'aqui diretamente.';

-- Sustenta a sentinela (`app.documentos_fora_da_busca`, abaixo) e a faixa da tela de acervo
-- ("3 documentos estão fora da busca") sem varrer a tabela inteira.
create index documentos_fora_da_busca_idx on public.documentos (id)
  where status = 'publicado' and indexado_em is null;

-- Backfill: documento já publicado que já tem chunk da versão corrente do pipeline estava
-- corretamente indexado em F0 (não havia ainda este eixo) — não introduzir falso-positivo na
-- sentinela para todo o acervo existente no dia em que esta migração roda. Documento publicado
-- SEM chunk nenhum permanece indexado_em = NULL — está genuinamente fora da busca, e é isso que
-- a sentinela deve mostrar desde o primeiro instante, não uma regressão desta migração.
update public.documentos d
   set indexado_em = coalesce(
         (select max(c.criado_em) from public.chunks c
           where c.documento_id = d.id and c.versao_pipeline = d.versao_pipeline),
         now())
 where d.status = 'publicado'
   and exists (
     select 1 from public.chunks c
      where c.documento_id = d.id and c.versao_pipeline = d.versao_pipeline
   );

-- ============================================================================
-- 2. Reenfileiramento como obrigação do banco.
-- ============================================================================

-- 2a. O invalidador de página (baseline 08) passa a reagir também a DELETE de documento_paginas
-- — hoje só reagia a INSERT/UPDATE OF visibilidade. Apagar uma página com override (ex.: a página
-- do regimento embutido que tinha visibilidade 'publico') muda o nivel_efetivo dela por queda para
-- o piso do documento (app.nivel_efetivo é um LEFT JOIN — página ausente = sem override) e pode
-- tornar um chunk existente não-uniforme, exatamente como reclassificar. Sem este `or delete`, o
-- caminho "apagar página" não invalidava nada — segunda lacuna do mesmo formato do V1-R/V3-R
-- (baseline 08): a invariante era validada num evento e não revalidada no evento irmão.
-- O CORPO da função não muda: já é genérico via coalesce(new.*, old.*, ...) — só o evento que a
-- dispara.
drop trigger documento_paginas_invalida_chunks_afetados on public.documento_paginas;
create trigger documento_paginas_invalida_chunks_afetados
  after insert or delete or update of visibilidade on public.documento_paginas
  for each row execute function public.tg_documento_paginas_invalida_chunks_afetados();

comment on function public.tg_documento_paginas_invalida_chunks_afetados() is
  'V1-R (auditor-rls) + corte C4/ADR-0026: fecha a variante temporal do achado V1 (reclassificar '
  'depois que o chunk existe) E a variante "apagar a página com override" (2026-09-06 — o mesmo '
  'formato de lacuna, achado ao estender a matriz da INV-13). Apaga, nunca bloqueia — bloquear '
  'quebraria o fluxo de curadoria (SPEC §3, regimento embutido). O reenfileiramento do trabalho '
  'apagado NÃO vive mais nesta função: é efeito automático do trigger chunks_invalida_documento '
  '(abaixo), disparado pelo DELETE em chunks que esta função já fazia — um só lugar decide '
  '"o índice ficou desatualizado", não um por chamador.';

-- 2b. Mecanismo genérico em `public.chunks`: qualquer linha que sai zera o índice do documento e
-- pede reconstrução; qualquer linha que entra (para a versão corrente do pipeline) confirma que
-- o índice está em dia. Isto cobre, com O MESMO código:
--   • o DELETE do invalidador de página (2a) — dispara como efeito colateral;
--   • "apagar chunk à mão" por service_role (ADR-0026 §6, célula ACEITO da INV-13) — sem isto,
--     esse caminho não deixava rastro nenhum;
--   • a própria reconstrução do worker (chunking(): DELETE + INSERT na MESMA transação) — o
--     DELETE zera e tenta enfileirar (vira no-op: já existe o job 'processando' que está rodando
--     esta própria reconstrução, mesma chave — é a unicidade parcial do ADR-0025 §2 protegendo);
--     o INSERT que segue, na mesma transação, seta indexado_em de volta antes do commit. Visto de
--     fora da transação (é tudo que importa, por MVCC), o índice nunca aparece "quebrado" por uma
--     reconstrução bem-sucedida — só por uma que NÃO reinsere.
create or replace function public.tg_chunks_marca_indexado()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.documentos
     set indexado_em = now()
   where id = new.documento_id
     and versao_pipeline = new.versao_pipeline;  -- inserção de versão velha/órfã não confirma o índice CORRENTE
  return new;
end $$;

create trigger chunks_marca_indexado
  after insert on public.chunks
  for each row execute function public.tg_chunks_marca_indexado();

comment on function public.tg_chunks_marca_indexado() is
  'ADR-0026 §3: só quem escreve public.chunks pode dizer "o índice está em dia" — nenhum código '
  'de aplicação escreve documentos.indexado_em diretamente. Guarda de versao_pipeline: inserir um '
  'chunk de uma versão que não é mais a corrente do documento não pode marcar o índice CORRENTE '
  'como pronto.';

create or replace function public.tg_chunks_invalida_documento()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_versao_atual int;
begin
  select versao_pipeline into v_versao_atual
    from public.documentos where id = old.documento_id;

  if not found then
    return old;  -- documento já não existe (cascade de DELETE em documentos) — nada a invalidar
  end if;

  if v_versao_atual <> old.versao_pipeline then
    -- o chunk apagado era de uma versão de pipeline que já não é a corrente (cauda histórica,
    -- ADR-0025 §Consequências: "não vale complicar agora" — nada limpa versão velha hoje). Apagar
    -- histórico não desatualiza o índice CORRENTE.
    return old;
  end if;

  update public.documentos
     set indexado_em = null
   where id = old.documento_id;

  -- on conflict do nothing (índice parcial, ADR-0025 §2) protege contra duplicar o job quando
  -- este DELETE é parte da própria reconstrução do worker (job 'processando' com a mesma chave já
  -- existe — ver comentário acima da trigger).
  perform job.enfileirar(
    'chunking',
    old.documento_id,
    'chunking:' || old.documento_id::text || ':v' || v_versao_atual::text,
    jsonb_build_object('motivo', 'chunk_invalidado'),
    200
  );

  return old;
end $$;

create trigger chunks_invalida_documento
  after delete on public.chunks
  for each row execute function public.tg_chunks_invalida_documento();

comment on function public.tg_chunks_invalida_documento() is
  'ADR-0026 §2: "não existe estado apagou-e-não-pediu-para-refazer". Genérico de propósito — '
  'cobre reclassificação de página, apagar página e apagar chunk à mão (célula ACEITO da INV-13) '
  'com o MESMO mecanismo, em vez de cada chamador ter de lembrar de invocar job.enfileirar().';

-- 2c. `versao_pipeline` muda (chunker corrigido, ADR-0025 §3) sem apagar nenhum chunk — os
-- antigos ficam como cauda histórica, tagueados com a versão velha. Sem este trigger, bumpar
-- versao_pipeline não deixava rastro nenhum: nenhum DELETE em chunks acontece, então o mecanismo
-- de 2b nunca dispara, e o documento ficaria com indexado_em de uma versão que não é mais a
-- corrente — indicando (errado) que o índice está em dia.
create or replace function public.tg_documentos_versao_pipeline_invalida_indexacao()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.versao_pipeline = old.versao_pipeline then
    return new;
  end if;

  -- BEFORE UPDATE: escreve na própria linha sendo gravada (predicado/efeito LOCAL, ADR-0023) —
  -- não é uma segunda instrução UPDATE, não reentra o trigger.
  new.indexado_em := null;

  perform job.enfileirar(
    'chunking',
    new.id,
    'chunking:' || new.id::text || ':v' || new.versao_pipeline::text,
    jsonb_build_object('motivo', 'versao_pipeline_alterada'),
    200
  );

  return new;
end $$;

create trigger documentos_versao_pipeline_invalida_indexacao
  before update of versao_pipeline on public.documentos
  for each row execute function public.tg_documentos_versao_pipeline_invalida_indexacao();

comment on function public.tg_documentos_versao_pipeline_invalida_indexacao() is
  'ADR-0025 §3 ("chunker corrigido reprocessa a partir do estágio 4") + ADR-0026: bumpar '
  'versao_pipeline não apaga chunk nenhum (a cauda velha fica de propósito), então o mecanismo '
  'genérico de chunks (chunks_invalida_documento) nunca dispararia sozinho para este caminho — '
  'precisa do seu próprio gatilho.';

-- ============================================================================
-- 3. A sentinela — ADR-0026 §4.
-- ============================================================================
-- security_invoker = false (padrão, DEFINER = dono da view): igual à exceção já documentada em
-- 20260904122200_views.sql para vw_inadimplencia_agregada/vw_lancamentos_com_comprovante — esta
-- view precisa ler `job.fila`, schema sem GRANT nenhum para authenticated (só service_role, e
-- nem esse tem SELECT direto de propósito — ver 20260904121900_job_fila.sql). Rodar com o
-- privilégio do dono é o que torna a leitura possível sem abrir job.fila para o papel de usuário.
-- Defesa em profundidade: app.eh_gestao() no WHERE, mesmo padrão do achado V6 (auditor-rls) —
-- GRANT de tabela/view sozinho não substitui checar que a sessão É, de fato, gestão.
create view app.documentos_fora_da_busca as
select
  d.id as documento_id,
  d.titulo,
  d.tipo,
  d.status,
  d.visibilidade,
  d.versao_pipeline,
  d.indexado_em,
  d.atualizado_em,
  -- Segunda linha do ADR-0026 §4 ("mais fraca"): job pendente/processando há mais de 48h é sinal
  -- de "worker parado", texto diferente de "reindexando". A VIEW expõe o dado; a UI/runbook
  -- decide a mensagem — não é papel de uma view decidir texto de tela.
  j.tem_job_ativo,
  j.job_mais_antigo_desde
from public.documentos d
left join lateral (
  select
    count(*) > 0 as tem_job_ativo,
    min(f.criado_em) as job_mais_antigo_desde
  from job.fila f
  where f.tipo = 'chunking'
    and f.status in ('pendente', 'processando')
    and f.payload ->> 'documento_id' = d.id::text
) j on true
where app.eh_gestao()
  and d.status = 'publicado'
  and d.indexado_em is null;

comment on view app.documentos_fora_da_busca is
  'INV-13 / ADR-0026 §4: "o que está fora da busca AGORA". Documento publicado sem índice válido '
  '(indexado_em is null) aparece aqui INDEPENDENTE de já existir job de chunking pendente/'
  'processando para ele — é essa presença mesmo-com-job que os testes vermelhos da INV-13 exigem '
  '(o sinal tem de acender no INSTANTE da invalidação, não só quando ninguém mais está cuidando). '
  'A coluna tem_job_ativo é o que distingue, para quem CONSOME esta view, "sendo reindexado agora" '
  '("reindexando", SPEC §3) de "ninguém encarregado" (a leitura mais estrita do texto do ADR-0026 '
  '§4 — quem quiser SÓ os órfãos filtra `where not tem_job_ativo`, e job_mais_antigo_desde há mais '
  'de 48h com tem_job_ativo é o sinal de "worker parado", runbook §5). '
  'security_invoker=false (exceção documentada em 20260904122200_views.sql): precisa ler job.fila, '
  'que não tem GRANT para papel de usuário nenhum. GRANT só para authenticated, nunca anon — e '
  'app.eh_gestao() no WHERE é defesa em profundidade (achado V6), não a única barreira.';

revoke all on app.documentos_fora_da_busca from public, anon, authenticated, service_role;
grant select on app.documentos_fora_da_busca to authenticated;
