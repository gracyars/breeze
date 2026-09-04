-- Breeze — baseline 22: views. Fonte: docs/schema.md §14; SPEC §2 ("orçado×realizado e
-- inadimplência são views, não tabelas materializadas").
--
-- REGRA GERAL (ADR-0012): `security_invoker = true` — a view herda a RLS de quem consulta; view
-- não é fronteira de autorização. Vale para 5 das 7 views abaixo.
--
-- DUAS EXCEÇÕES DOCUMENTADAS, decididas nesta migração (docs/schema.md §14 diz "todas" sem
-- ressalva; na prática duas views EXISTEM para expor um AGREGADO/SINAL derivado de uma tabela
-- que é gestão-only por linha — com security_invoker=true elas devolveriam zero para quem não é
-- gestão, quebrando o próprio propósito que a tabela-base já documenta):
--   • vw_inadimplencia_agregada — cobrancas.select já é "própria unidade OU gestão"; o comentário
--     da própria tabela `cobrancas` diz "o agregado vai para todos por VIEW, não por acesso a
--     esta tabela" — ou seja, esta view É o mecanismo de ampliação deliberado.
--   • vw_lancamentos_com_comprovante — lancamento_anexos.select é só gestão; o comentário da
--     própria tabela diz "morador vê que o comprovante EXISTE (via view agregada), não o
--     arquivo" — mesmo padrão.
-- As duas usam security_invoker = false (padrão) para rodar com o privilégio do DONO da view
-- (bypassa RLS das tabelas-base), e por isso são as ÚNICAS deste arquivo com GRANT restrito
-- (nunca a anon) e projeção de coluna deliberadamente mínima — nenhuma delas expõe unidade_id/
-- pessoa/storage_path, só o agregado. Recomendação para o arquiteto: refletir esta ressalva em
-- docs/schema.md §14, que hoje diz "todas" sem exceção.

-- ============================================================================
-- vw_orcado_realizado — security_invoker=true (lancamentos.select já é autenticado geral, sem
-- filtro por linha — não há diferença entre invoker e owner aqui).
-- ============================================================================
create view public.vw_orcado_realizado
with (security_invoker = true) as
select
  o.exercicio,
  o.mes,
  o.conta_id,
  o.valor_previsto_centavos as previsto_centavos,
  coalesce(r.realizado_centavos, 0) as realizado_centavos,
  coalesce(r.realizado_centavos, 0) - o.valor_previsto_centavos as variacao_centavos,
  case when o.valor_previsto_centavos = 0 then null
       else round(
         (coalesce(r.realizado_centavos, 0) - o.valor_previsto_centavos)::numeric
         / o.valor_previsto_centavos * 100, 2)
  end as variacao_pct
from public.orcamento o
left join (
  select conta_id, data_competencia, sum(valor_centavos) as realizado_centavos
    from public.lancamentos
   group by conta_id, data_competencia
) r on r.conta_id = o.conta_id
   and r.data_competencia = make_date(o.exercicio, o.mes, 1);

comment on view public.vw_orcado_realizado is
  'SUM(bigint) devolve numeric no Postgres — o código de aplicação precisa esperar numeric, não '
  'bigint (ADR-0010). SUM já sai correto sem filtro: estorno é lançamento com valor negativo '
  '(ADR-0011).';

revoke all on public.vw_orcado_realizado from public, anon, authenticated;
grant select on public.vw_orcado_realizado to authenticated;

-- ============================================================================
-- vw_realizado_por_conta — security_invoker=true, mesmo motivo.
-- ============================================================================
create view public.vw_realizado_por_conta
with (security_invoker = true) as
select
  l.conta_id,
  c.codigo as conta_codigo,
  c.nome as conta_nome,
  l.data_competencia as competencia,
  sum(l.valor_centavos) as realizado_centavos
from public.lancamentos l
join public.contas c on c.id = l.conta_id
group by l.conta_id, c.codigo, c.nome, l.data_competencia;

revoke all on public.vw_realizado_por_conta from public, anon, authenticated;
grant select on public.vw_realizado_por_conta to authenticated;

-- ============================================================================
-- vw_inadimplencia_agregada — EXCEÇÃO (ver cabeçalho). security_invoker=false (padrão): roda com
-- privilégio do dono, bypassa a filtragem por unidade de `cobrancas`, para devolver o agregado
-- do CONDOMÍNIO INTEIRO a qualquer autenticado. NUNCA projeta unidade_id nem pessoa — é
-- justamente o que a mantém sem ser `vw_inadimplencia_nominal`.
-- ============================================================================
create view public.vw_inadimplencia_agregada as
select
  competencia,
  sum(valor_centavos) as total_centavos,
  coalesce(sum(valor_centavos) filter (where status in ('atrasada', 'acordo')), 0) as em_atraso_centavos,
  case when sum(valor_centavos) = 0 then 0
       else round(
         coalesce(sum(valor_centavos) filter (where status in ('atrasada', 'acordo')), 0)::numeric
         / sum(valor_centavos) * 100, 2)
  end as pct,
  count(*) filter (where status in ('atrasada', 'acordo')) as qtd_unidades_em_atraso
from public.cobrancas
group by competencia;

comment on view public.vw_inadimplencia_agregada is
  'EXCEÇÃO a "security_invoker=true em todas" (docs/schema.md §14) — deliberada, ver cabeçalho '
  'deste arquivo. Nunca projeta unidade_id nem pessoa_id: é o que a distingue de '
  'vw_inadimplencia_nominal. GRANT só para authenticated, nunca anon.';

revoke all on public.vw_inadimplencia_agregada from public, anon, authenticated;
grant select on public.vw_inadimplencia_agregada to authenticated;

-- ============================================================================
-- vw_inadimplencia_nominal — security_invoker=true DE PROPÓSITO: precisa herdar exatamente a
-- RLS de cobrancas (própria unidade OU gestão) — é o oposto da view anterior. Leitura por gestão
-- deve gerar audit.acesso; isso é responsabilidade da rotina de servidor que consulta esta view
-- (não é expressável em SQL de view/RLS — não há "AFTER SELECT").
-- ============================================================================
create view public.vw_inadimplencia_nominal
with (security_invoker = true) as
select
  c.unidade_id,
  u.bloco,
  u.numero,
  v.pessoa_id,
  p.nome as pessoa_nome,
  c.competencia,
  c.valor_centavos,
  c.valor_pago_centavos,
  c.status,
  c.vencimento
from public.cobrancas c
join public.unidades u on u.id = c.unidade_id
left join public.vinculos v on v.unidade_id = c.unidade_id
  and v.tipo = 'proprietario' and v.fim is null
left join public.pessoas p on p.id = v.pessoa_id
where c.status in ('atrasada', 'acordo');

comment on view public.vw_inadimplencia_nominal is
  'Leitura nominal por gestão PRECISA gerar audit.acesso (SPEC §5.5) — a cargo da rotina de '
  'servidor que consulta esta view, não da view em si (não existe "AFTER SELECT" em SQL).';

revoke all on public.vw_inadimplencia_nominal from public, anon, authenticated;
grant select on public.vw_inadimplencia_nominal to authenticated;

-- ============================================================================
-- vw_pessoas_mascaradas — security_invoker=true: herda "própria linha OU gestão" de pessoas.
-- Nunca toca cpf_enc.
-- ============================================================================
create view public.vw_pessoas_mascaradas
with (security_invoker = true) as
select
  id,
  nome,
  email,
  case when cpf_ultimos_digitos is null then null
       else '***.***.' || cpf_ultimos_digitos || '-**'
  end as cpf_mascarado
from public.pessoas;

revoke all on public.vw_pessoas_mascaradas from public, anon, authenticated;
grant select on public.vw_pessoas_mascaradas to authenticated;

-- ============================================================================
-- vw_documentos_publicados — security_invoker=true: herda app.documento_visivel(id) de
-- documentos, só que já filtrado a status='publicado' (conveniência de listagem).
-- ============================================================================
create view public.vw_documentos_publicados
with (security_invoker = true) as
select
  d.id, d.tipo, d.titulo, d.data_documento, d.competencia, d.visibilidade,
  d.paginas, d.publicado_em
from public.documentos d
where d.status = 'publicado';

revoke all on public.vw_documentos_publicados from public, anon, authenticated;
grant select on public.vw_documentos_publicados to anon, authenticated;

-- ============================================================================
-- vw_lancamentos_com_comprovante — EXCEÇÃO (ver cabeçalho). security_invoker=false: bypassa a
-- restrição gestão-only de lancamento_anexos para expor só a CONTAGEM por tipo — nunca
-- storage_path, descricao, sha256 nem enviado_por.
-- ============================================================================
create view public.vw_lancamentos_com_comprovante as
select
  l.id as lancamento_id,
  l.data_competencia,
  l.conta_id,
  l.valor_centavos,
  count(a.id) as total_anexos,
  count(a.id) filter (where a.tipo = 'cotacao') as total_cotacoes,
  (count(a.id) > 0) as tem_comprovante
from public.lancamentos l
left join public.lancamento_anexos a on a.lancamento_id = l.id
group by l.id, l.data_competencia, l.conta_id, l.valor_centavos;

comment on view public.vw_lancamentos_com_comprovante is
  'EXCEÇÃO a "security_invoker=true em todas" (docs/schema.md §14) — deliberada, ver cabeçalho '
  'deste arquivo. Projeta só contagem/booleano — nunca storage_path, descricao, sha256 ou '
  'enviado_por (esses continuam gestão-only, só acessíveis via lancamento_anexos direto ou '
  'signed URL). GRANT só para authenticated, nunca anon.';

revoke all on public.vw_lancamentos_com_comprovante from public, anon, authenticated;
grant select on public.vw_lancamentos_com_comprovante to authenticated;
