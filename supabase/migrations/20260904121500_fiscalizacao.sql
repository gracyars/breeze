-- Breeze — baseline 15: fiscalização — questionamentos, tipos_alerta, alertas, pareceres,
-- parecer_signatarios. Fonte: docs/schema.md §9; SPEC §5.4, §6.4-bis (STJ REsp 2.050.372).

-- ============================================================================
-- questionamentos
-- ============================================================================
create table public.questionamentos (
  id             uuid primary key default extensions.gen_random_uuid(),
  lancamento_id  uuid not null references public.lancamentos(id) on delete restrict,
  autor_id       uuid not null references public.pessoas(id) on delete restrict,
  texto          text not null check (length(btrim(texto)) >= 10),
  status         public.status_questionamento not null default 'aberto',
  resposta       text,
  respondido_por uuid references public.pessoas(id),
  respondido_em  timestamptz,
  criado_em      timestamptz not null default now(),
  constraint questionamentos_resposta_ck check (
    status = 'aberto' or (resposta is not null and respondido_por is not null))
);
create index questionamentos_status_idx     on public.questionamentos (status);
create index questionamentos_lancamento_idx on public.questionamentos (lancamento_id);

comment on table public.questionamentos is
  'RLS: leitura e abertura SÓ conselho e editor; resposta só editor. '
  'Por quê SPEC §6.4-bis (STJ REsp 2.050.372): inspecionar documento é direito individual, mas '
  'EXIGIR CONTAS é direito coletivo — condômino sozinho não tem legitimidade. Questionamento '
  'formal é ato do órgão fiscalizador, não do morador. Dar INSERT ao morador aqui contradiria a '
  'restrição de copy do §6.4-bis no nível do dado, e não só na microcopy.';

alter table public.questionamentos enable row level security;
alter table public.questionamentos force row level security;
revoke all on public.questionamentos from public, anon, authenticated, service_role;
grant select on public.questionamentos to authenticated;
grant insert, update on public.questionamentos to authenticated;

create policy questionamentos_select on public.questionamentos
  for select to authenticated using ( app.eh_gestao() );
-- Abertura: conselho e editor (ato do órgão fiscalizador — não é "escrita só editor" aqui).
create policy questionamentos_insert on public.questionamentos
  for insert to authenticated with check ( app.eh_gestao() );
-- Resposta: só editor (é quem responde pela gestão financeira questionada).
create policy questionamentos_update on public.questionamentos
  for update to authenticated using ( app.eh_editor() ) with check ( app.eh_editor() );

-- ============================================================================
-- tipos_alerta — tabela de domínio (ADR-0015)
-- ============================================================================
create table public.tipos_alerta (
  codigo             text primary key,   -- 'despesa_sem_comprovante','estouro_orcamento',...
  nome               text not null,
  severidade_padrao  public.severidade_alerta not null,
  descricao_regra    text not null,
  -- Pendência (b), ADR-0016: quanto de série histórica a regra exige para produzir resultado com
  -- sentido. O motor NÃO avalia a regra enquanto o acervo não alcança este mínimo; a UI mostra
  -- "aguardando histórico" em vez de silenciar.
  requer_historico_meses int not null default 0 check (requer_historico_meses >= 0),
  ativo              boolean not null default true
);

comment on table public.tipos_alerta is
  'RLS: leitura gestão; escrita editor. Tabela de domínio (ADR-0015): as 10 regras do SPEC §5.3. '
  'Os LIMIARES vivem em `configuracoes`, não em código e não aqui.';

alter table public.tipos_alerta enable row level security;
alter table public.tipos_alerta force row level security;
revoke all on public.tipos_alerta from public, anon, authenticated, service_role;
grant select on public.tipos_alerta to authenticated;
grant insert, update, delete on public.tipos_alerta to authenticated;

create policy tipos_alerta_select on public.tipos_alerta
  for select to authenticated using ( app.eh_gestao() );
create policy tipos_alerta_insert on public.tipos_alerta
  for insert to authenticated with check ( app.eh_editor() );
create policy tipos_alerta_update on public.tipos_alerta
  for update to authenticated using ( app.eh_editor() ) with check ( app.eh_editor() );
create policy tipos_alerta_delete on public.tipos_alerta
  for delete to authenticated using ( app.eh_editor() );

-- ============================================================================
-- alertas — escrita pelo motor (service_role); resolução por gestão
-- ============================================================================
create table public.alertas (
  id            uuid primary key default extensions.gen_random_uuid(),
  tipo          text not null references public.tipos_alerta(codigo) on delete restrict,
  severidade    public.severidade_alerta not null,
  lancamento_id uuid references public.lancamentos(id) on delete cascade,
  contrato_id   uuid references public.contratos(id)   on delete cascade,
  fornecedor_id uuid references public.fornecedores(id) on delete cascade,
  conta_id      uuid references public.contas(id)      on delete cascade,
  competencia   date,
  detalhe       jsonb not null default '{}'::jsonb,
  status        public.status_alerta not null default 'aberto',
  -- Idempotência: o motor é re-executável. Sem esta chave, cada execução duplica o alerta e o
  -- painel do conselho vira ruído — que é como um motor de alertas morre.
  chave_dedupe  text not null unique,
  criado_em     timestamptz not null default now(),
  resolvido_por uuid references public.pessoas(id),
  resolvido_em  timestamptz,
  resolucao     text,
  constraint alertas_alvo_ck check (
    num_nonnulls(lancamento_id, contrato_id, fornecedor_id, conta_id) >= 1)
);
create index alertas_status_severidade_idx on public.alertas (status, severidade);
create index alertas_competencia_idx       on public.alertas (competencia desc);

comment on table public.alertas is
  'RLS: leitura SÓ conselho e editor; escrita (INSERT) pelo motor via service_role, sem policy de '
  'usuário; resolução (UPDATE) por gestão. '
  'Por quê: alerta é acusação em potencial ("fracionamento suspeito", "troca de dados '
  'bancários"). Exposto a morador antes de apuração, vira boato — e o sujeito do alerta é o '
  'síndico terceirizado, que sequer tem conta para se defender dentro do produto (D3).';

alter table public.alertas enable row level security;
alter table public.alertas force row level security;
revoke all on public.alertas from public, anon, authenticated, service_role;
grant select on public.alertas to authenticated;
grant update on public.alertas to authenticated; -- delete: ninguém
-- V4 (auditor-rls, achado real): "insert: só service_role" era só comentário — sem GRANT
-- explícito, service_role não tinha NENHUM privilégio aqui (BYPASSRLS bypassa RLS, não GRANT de
-- tabela, que é um gate separado). O motor de alertas, como desenhado, era inoperável.
grant select, insert on public.alertas to service_role;

-- V4 (auditor-rls, achado real, confirmado por teste ao vivo): GRANT só em `alertas` não bastava
-- — o motor precisa LER as tabelas que cada uma das 10 regras do SPEC §5.3 avalia para decidir
-- se levanta o alerta. Sem isso, `insert into alertas` falhava indiretamente porque a subquery
-- de origem (ex.: "pegue um lançamento/conta real") já não tinha SELECT. Concedido só leitura,
-- por regra:
--   despesa_sem_comprovante, fundo_sem_ata, variacao_atipica, fracionamento_suspeito,
--   fornecedor_nao_cadastrado -> lancamentos
--   despesa_sem_comprovante, cotacao_ausente                    -> lancamento_anexos
--   estouro_orcamento                                           -> orcamento
--   contrato_vencendo, renovacao_nao_deliberada                 -> contratos
--   fornecedor_nao_cadastrado, troca_dados_bancarios             -> fornecedores
--   troca_dados_bancarios                                        -> fornecedor_dados_bancarios
--   (classificação/nome de conta em qualquer regra)              -> contas
-- `cotacao_ausente`/`fracionamento_suspeito` também leem o limiar em `configuracoes`
-- (grant nesse schema fica em 20260904121700_busca_config.sql, onde a tabela é criada).
grant select on public.contas, public.lancamentos, public.lancamento_anexos, public.orcamento,
  public.contratos, public.fornecedores, public.fornecedor_dados_bancarios
  to service_role;

create policy alertas_select on public.alertas
  for select to authenticated using ( app.eh_gestao() );
-- Resolução: conselho E editor podem resolver/ignorar — exceção documentada (matriz §15:
-- "ler + resolver" para os dois papéis de gestão, não só editor).
create policy alertas_update on public.alertas
  for update to authenticated using ( app.eh_gestao() ) with check ( app.eh_gestao() );

-- ============================================================================
-- pareceres e parecer_signatarios — [ADR-0016 item 8] — única escrita do papel conselho
-- ============================================================================
create table public.pareceres (
  id                 uuid primary key default extensions.gen_random_uuid(),
  competencia_inicio date not null,
  competencia_fim    date not null,
  versao             int not null default 1 check (versao > 0),
  texto              text not null,
  conclusao          text check (conclusao in ('aprovado','aprovado_com_ressalva','rejeitado')),
  status             text not null default 'rascunho' check (status in ('rascunho','emitido')),
  documento_id       uuid references public.documentos(id) on delete restrict,
  emitido_em         timestamptz,
  criado_em          timestamptz not null default now(),
  constraint pareceres_periodo_ck check (competencia_fim >= competencia_inicio),
  constraint pareceres_uk unique (competencia_inicio, competencia_fim, versao)
);

comment on table public.pareceres is
  'RLS: rascunho SÓ conselho e editor; parecer emitido, leitura para autenticado. Escrita: SÓ '
  'conselho (app.tem_papel(''conselho'') com AAL2) — não eh_gestao(), porque é a ÚNICA escrita '
  'do papel conselho no schema inteiro e a exceção não deve se alargar por engano incluindo '
  'editor implicitamente (SPEC §2.1). O rigor de assinatura/versionamento depende do Briefing §7 '
  'item 3, ainda PENDENTE. O desenho comporta as duas respostas.';

alter table public.pareceres enable row level security;
alter table public.pareceres force row level security;
revoke all on public.pareceres from public, anon, authenticated, service_role;
grant select on public.pareceres to authenticated;
grant insert, update on public.pareceres to authenticated;

create policy pareceres_select on public.pareceres
  for select to authenticated
  using ( status = 'emitido' or app.eh_gestao() );
create policy pareceres_insert on public.pareceres
  for insert to authenticated with check ( app.tem_papel('conselho') );
create policy pareceres_update on public.pareceres
  for update to authenticated using ( app.tem_papel('conselho') ) with check ( app.tem_papel('conselho') );

create table public.parecer_signatarios (
  parecer_id  uuid not null references public.pareceres(id) on delete cascade,
  pessoa_id   uuid not null references public.pessoas(id) on delete restrict,
  assinado_em timestamptz,
  primary key (parecer_id, pessoa_id)
);

comment on table public.parecer_signatarios is
  'RLS: espelha a visibilidade do pareceres pai (rascunho: gestão; emitido: autenticado). '
  'Escrita: conselho, mesma régua de pareceres.';

alter table public.parecer_signatarios enable row level security;
alter table public.parecer_signatarios force row level security;
revoke all on public.parecer_signatarios from public, anon, authenticated, service_role;
grant select on public.parecer_signatarios to authenticated;
grant insert, update, delete on public.parecer_signatarios to authenticated;

create policy parecer_signatarios_select on public.parecer_signatarios
  for select to authenticated
  using ( exists (
    select 1 from public.pareceres p
     where p.id = parecer_signatarios.parecer_id
       and (p.status = 'emitido' or app.eh_gestao())
  ) );
create policy parecer_signatarios_insert on public.parecer_signatarios
  for insert to authenticated with check ( app.tem_papel('conselho') );
create policy parecer_signatarios_update on public.parecer_signatarios
  for update to authenticated using ( app.tem_papel('conselho') ) with check ( app.tem_papel('conselho') );
create policy parecer_signatarios_delete on public.parecer_signatarios
  for delete to authenticated using ( app.tem_papel('conselho') );
