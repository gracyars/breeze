-- Breeze — baseline 14: lancamento_anexos, orcamento, cobrancas. Fonte: docs/schema.md §8.6-8.8.

-- ============================================================================
-- lancamento_anexos
-- ============================================================================
create table public.lancamento_anexos (
  id             uuid primary key default extensions.gen_random_uuid(),
  lancamento_id  uuid not null references public.lancamentos(id) on delete restrict,
  storage_bucket text not null default 'anexos-financeiros',   -- bucket SEPARADO (SPEC §7)
  storage_path   text not null unique,
  sha256         bytea not null check (octet_length(sha256) = 32),
  tipo           text not null check (tipo in
                   ('nota_fiscal','recibo','boleto','comprovante_pagamento','cotacao',
                    'contrato','ordem_servico','outro')),
  descricao      text,
  enviado_por    uuid not null references public.pessoas(id),
  enviado_em     timestamptz not null default now()
);
create index lancamento_anexos_lancamento_idx on public.lancamento_anexos (lancamento_id);
-- Alerta "cotação ausente" (SPEC §5.3) conta tipo='cotacao' por lançamento acima do limiar.
create index lancamento_anexos_cotacao_idx on public.lancamento_anexos (lancamento_id)
  where tipo = 'cotacao';

comment on table public.lancamento_anexos is
  'RLS: leitura SÓ conselho e editor; escrita só editor. '
  'Por quê: nota fiscal e recibo carregam CNPJ, endereço, e às vezes nome de pessoa física. '
  'É o material mais sensível do financeiro. Bucket próprio, acesso só por signed URL de TTL '
  'curto gerada no servidor APÓS checagem de papel, nunca em página cacheada na CDN (SPEC §7, '
  'ADR-0004). Morador vê que o comprovante EXISTE (via vw_lancamentos_com_comprovante), não o '
  'arquivo.';

alter table public.lancamento_anexos enable row level security;
alter table public.lancamento_anexos force row level security;
revoke all on public.lancamento_anexos from public, anon, authenticated, service_role;
grant select on public.lancamento_anexos to authenticated;
grant insert, update, delete on public.lancamento_anexos to authenticated;

create policy lancamento_anexos_select on public.lancamento_anexos
  for select to authenticated using ( app.eh_gestao() );
create policy lancamento_anexos_insert on public.lancamento_anexos
  for insert to authenticated with check ( app.eh_editor() );
create policy lancamento_anexos_update on public.lancamento_anexos
  for update to authenticated using ( app.eh_editor() ) with check ( app.eh_editor() );
create policy lancamento_anexos_delete on public.lancamento_anexos
  for delete to authenticated using ( app.eh_editor() );

-- ============================================================================
-- orcamento
-- ============================================================================
create table public.orcamento (
  id                     uuid primary key default extensions.gen_random_uuid(),
  exercicio              int not null check (exercicio between 2000 and 2100),
  conta_id               uuid not null references public.contas(id) on delete restrict,
  mes                    int not null check (mes between 1 and 12),
  valor_previsto_centavos bigint not null check (valor_previsto_centavos >= 0),  -- [ADR-0016 item 2]
  documento_id           uuid references public.documentos(id) on delete restrict,
  criado_em              timestamptz not null default now(),
  criado_por             uuid references public.pessoas(id),
  constraint orcamento_uk unique (exercicio, conta_id, mes)
);

comment on table public.orcamento is
  'RLS: leitura para autenticado; escrita só editor. '
  'Por quê: orçado × realizado é o painel que o morador precisa ver (SPEC §6.4). Sem PII. '
  'É a base do alerta de estouro de orçamento (80% aviso / >100% crítico, SPEC §5.3).';

alter table public.orcamento enable row level security;
alter table public.orcamento force row level security;
revoke all on public.orcamento from public, anon, authenticated, service_role;
grant select on public.orcamento to authenticated;
grant insert, update, delete on public.orcamento to authenticated;

create policy orcamento_select on public.orcamento
  for select to authenticated using ( app.eh_autenticado() );
create policy orcamento_insert on public.orcamento
  for insert to authenticated with check ( app.eh_editor() );
create policy orcamento_update on public.orcamento
  for update to authenticated using ( app.eh_editor() ) with check ( app.eh_editor() );
create policy orcamento_delete on public.orcamento
  for delete to authenticated using ( app.eh_editor() );

-- ============================================================================
-- cobrancas — a tabela de RLS mais delicada
-- ============================================================================
create table public.cobrancas (
  id                 uuid primary key default extensions.gen_random_uuid(),
  unidade_id         uuid not null references public.unidades(id) on delete restrict,
  competencia        date not null
                     check (competencia = date_trunc('month', competencia::timestamp)::date),
  valor_centavos     bigint not null check (valor_centavos > 0),        -- [ADR-0016 item 2]
  vencimento         date not null,
  status             public.status_cobranca not null default 'aberta',
  valor_pago_centavos bigint not null default 0 check (valor_pago_centavos >= 0),
  data_pagamento     date,
  documento_id       uuid references public.documentos(id) on delete restrict,
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now(),
  constraint cobrancas_uk unique (unidade_id, competencia),
  constraint cobrancas_pagamento_ck check (
    status <> 'paga' or (data_pagamento is not null and valor_pago_centavos > 0))
);
create index cobrancas_status_vencimento_idx on public.cobrancas (status, vencimento);
create index cobrancas_unidade_idx           on public.cobrancas (unidade_id, competencia desc);

comment on table public.cobrancas is
  'RLS: morador vê SÓ as cobranças das PRÓPRIAS unidades; conselho e editor veem todas; escrita '
  'só editor. '
  'Por quê: inadimplência nominal JAMAIS é exposta a morador (SPEC §7, §5.5). Nome + unidade + '
  'valor em atraso de vizinho é dado pessoal negativo — e, na prática de condomínio, é o dado que '
  'gera conflito real. O agregado (taxa de inadimplência do mês) vai para todos por VIEW '
  '(vw_inadimplencia_agregada), não por acesso a esta tabela. Toda leitura nominal por gestão '
  'deve gerar linha em audit.acesso (SPEC §5.5) — responsabilidade da rotina de servidor que lê '
  'vw_inadimplencia_nominal, não desta tabela em si.';

alter table public.cobrancas enable row level security;
alter table public.cobrancas force row level security;
revoke all on public.cobrancas from public, anon, authenticated, service_role;
grant select on public.cobrancas to authenticated;
grant insert, update on public.cobrancas to authenticated; -- delete: ninguém (cancelar por status)

create policy cobrancas_select on public.cobrancas
  for select to authenticated
  using ( app.eh_gestao() or unidade_id in (select app.unidades_da_pessoa()) );
create policy cobrancas_insert on public.cobrancas
  for insert to authenticated with check ( app.eh_editor() );
create policy cobrancas_update on public.cobrancas
  for update to authenticated using ( app.eh_editor() ) with check ( app.eh_editor() );
