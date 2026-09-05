-- Breeze — baseline 11: financeiro — contas, fornecedores, fornecedor_dados_bancarios,
-- contratos, periodos_fechados. Fonte: docs/schema.md §8; ADR-0010 (dinheiro), ADR-0014 (CPF),
-- ADR-0016 item 8.

-- ============================================================================
-- contas — árvore do plano de contas
-- ============================================================================
create table public.contas (
  id               uuid primary key default extensions.gen_random_uuid(),
  codigo           text not null unique,   -- 'G.SS.CC' (condominio-plano-de-contas §1)
  nome             text not null,
  natureza         public.natureza_conta not null,
  nivel            int not null check (nivel between 1 and 3),
  conta_pai_id     uuid references public.contas(id) on delete restrict,
  aceita_lancamento boolean not null default false,   -- só folha (nível 3) recebe lançamento
  -- [D12/docs/dominio/plano-de-contas-decisoes.md] Só legítimo em conta de RECEITA de fundo
  -- (1.3.x contribuição/rendimento do fundo de reserva, 1.4.x do fundo de obras) — natureza
  -- estrutural da conta, sem ambiguidade. NUNCA setar em conta de DESPESA: uso de fundo não é
  -- despesa autônoma, é a MESMA despesa finalística (bomba, obra, elevador) paga com recurso de
  -- origem diferente — a origem do recurso é atributo do LANÇAMENTO (lancamentos.fundo), nunca
  -- da conta. Existiu uma exceção errada aqui (subgrupo 2.12 "Uso de fundos", removido por D12)
  -- que empilhava naturezas de despesa incompatíveis numa conta só e divergia do balancete real
  -- da administradora — não repetir.
  fundo            public.fundo not null default 'nenhum',
  -- ESPELHAMENTO 1:1 do plano da administradora. Divergir destrói comparabilidade
  -- (condominio-plano-de-contas §8). Nunca "corrigir" o nome dela.
  codigo_administradora text,
  nome_administradora   text,
  ativa            boolean not null default true,
  criado_em        timestamptz not null default now(),
  constraint contas_raiz_ck  check ((nivel = 1) = (conta_pai_id is null)),
  constraint contas_folha_ck check (not aceita_lancamento or nivel = 3)
);
create index contas_pai_idx    on public.contas (conta_pai_id);
create index contas_codigo_idx on public.contas (codigo text_pattern_ops);  -- prefixo '2.04.%'

-- Trigger de hierarquia: nivel = nivel(pai)+1, natureza igual à do pai, sem ciclo. CHECK não
-- alcança a linha do pai.
create or replace function public.tg_contas_valida_hierarquia()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_pai public.contas;
begin
  if new.conta_pai_id is not null then
    select * into v_pai from public.contas where id = new.conta_pai_id;
    if v_pai is null then
      raise exception 'conta_pai_id % não existe', new.conta_pai_id;
    end if;
    if new.nivel <> v_pai.nivel + 1 then
      raise exception 'conta % (nível %) precisa ter nível % sob o pai % (nível %)',
        new.codigo, new.nivel, v_pai.nivel + 1, v_pai.codigo, v_pai.nivel;
    end if;
    if new.natureza <> v_pai.natureza then
      raise exception 'conta % (natureza %) diverge da natureza do pai % (%)',
        new.codigo, new.natureza, v_pai.codigo, v_pai.natureza;
    end if;
    if new.conta_pai_id = new.id then
      raise exception 'conta % não pode ser pai de si mesma', new.codigo;
    end if;
  end if;
  return new;
end $$;
create trigger contas_valida_hierarquia
  before insert or update of conta_pai_id, nivel, natureza on public.contas
  for each row execute function public.tg_contas_valida_hierarquia();

comment on table public.contas is
  'RLS: leitura para autenticado; escrita só editor. '
  'Por quê: o plano de contas é o vocabulário do painel financeiro — o morador precisa ler para '
  'entender "para onde foi o dinheiro" (SPEC §6.4). Não contém PII. A escrita é sensível por '
  'outro motivo: renomear ou reclassificar conta reescreve o significado da série histórica. '
  'Mudança de plano é EVENTO REGISTRADO (auditado), não edição silenciosa.';

alter table public.contas enable row level security;
alter table public.contas force row level security;
revoke all on public.contas from public, anon, authenticated, service_role;
grant select on public.contas to authenticated;
grant insert, update, delete on public.contas to authenticated;

create policy contas_select on public.contas
  for select to authenticated using ( app.eh_autenticado() );
create policy contas_insert on public.contas
  for insert to authenticated with check ( app.eh_editor() );
create policy contas_update on public.contas
  for update to authenticated using ( app.eh_editor() ) with check ( app.eh_editor() );
create policy contas_delete on public.contas
  for delete to authenticated using ( app.eh_editor() );

-- ============================================================================
-- fornecedores e fornecedor_dados_bancarios — [ADR-0016 item 8]
-- ============================================================================
create table public.fornecedores (
  id            uuid primary key default extensions.gen_random_uuid(),
  cnpj          char(14) unique check (cnpj is null or cnpj ~ '^[0-9]{14}$'),  -- só dígitos
  -- Prestador pessoa física recebe EXATAMENTE o mesmo tratamento de CPF (ADR-0014 item 7).
  cpf_hash      bytea unique check (cpf_hash is null or octet_length(cpf_hash) = 32),
  cpf_enc       bytea,
  razao_social  text not null,
  nome_fantasia text,
  categoria     text,
  -- D3: o síndico terceirizado existe AQUI, como entidade fiscalizada. Não é papel, não é conta,
  -- não tem login, nenhum fluxo depende de ação dele dentro do produto.
  eh_sindico_terceirizado boolean not null default false,
  eh_administradora       boolean not null default false,
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now(),
  criado_por    uuid references public.pessoas(id),
  constraint fornecedores_doc_ck check (cnpj is not null or cpf_hash is not null),
  constraint fornecedores_cpf_par_ck check ((cpf_hash is null) = (cpf_enc is null))
);
create index fornecedores_razao_trgm_idx on public.fornecedores using gin (razao_social extensions.gin_trgm_ops);
-- cpf_enc fica de fora do GRANT SELECT coluna a coluna no bloco de RLS abaixo — NUNCA
-- "grant select on public.fornecedores" seguido de revoke da coluna: REVOKE de coluna não
-- subtrai de GRANT de tabela em nenhuma ordem (armadilha de Postgres documentada em
-- 20260904120300_identidade_tabelas.sql, onde foi achada e corrigida).

comment on table public.fornecedores is
  'RLS: leitura para autenticado (razão social e CNPJ de quem o condomínio paga é informação de '
  'prestação de contas); escrita só editor. cpf_enc fora do alcance por GRANT de coluna. '
  'Por quê D3: o síndico terceirizado é linha aqui, nunca usuário.';

alter table public.fornecedores enable row level security;
alter table public.fornecedores force row level security;
revoke all on public.fornecedores from public, anon, authenticated, service_role;
-- GRANT SELECT coluna a coluna, SEM cpf_enc — nunca "grant select on public.fornecedores".
grant select (id, cnpj, cpf_hash, razao_social, nome_fantasia, categoria,
  eh_sindico_terceirizado, eh_administradora, ativo, criado_em, criado_por)
  on public.fornecedores to authenticated;
grant insert, update, delete on public.fornecedores to authenticated;
-- INSERT/UPDATE/DELETE de tabela inteira (acima) permanecem, inclusive cpf_enc: é o editor
-- cifrando e gravando; só a LEITURA de volta é vedada.
-- V4: mesma razão de pessoas — rotina de servidor decifra CPF de prestador PF sob pedido do
-- editor, registrada em audit.acesso (ADR-0014 item 7).
grant select on public.fornecedores to service_role;

create policy fornecedores_select on public.fornecedores
  for select to authenticated using ( app.eh_autenticado() );
create policy fornecedores_insert on public.fornecedores
  for insert to authenticated with check ( app.eh_editor() );
create policy fornecedores_update on public.fornecedores
  for update to authenticated using ( app.eh_editor() ) with check ( app.eh_editor() );
create policy fornecedores_delete on public.fornecedores
  for delete to authenticated using ( app.eh_editor() );

-- Histórico de dados bancários. Existe SÓ para detectar o alerta crítico "troca de dados
-- bancários" (golpe do boleto, SPEC §5.3). Por isso guarda o MÍNIMO: nada em claro.
create table public.fornecedor_dados_bancarios (
  id             uuid primary key default extensions.gen_random_uuid(),
  fornecedor_id  uuid not null references public.fornecedores(id) on delete restrict,
  banco          text,
  agencia        text,
  conta_mascarada text,           -- '****1234' — suficiente para conferência humana
  chave_pix_hash bytea,           -- HMAC, mesmo esquema do CPF: compara sem armazenar
  vigente_desde  timestamptz not null default now(),
  vigente_ate    timestamptz,
  documento_id   uuid references public.documentos(id),
  registrado_por uuid references public.pessoas(id)
);
create index fdb_fornecedor_idx on public.fornecedor_dados_bancarios (fornecedor_id, vigente_ate);

comment on table public.fornecedor_dados_bancarios is
  'RLS: leitura e escrita só gestão (escrita só editor). '
  'Por quê: dado bancário de terceiro; e a própria mudança é o sinal de fraude que o alerta '
  'procura. Minimização deliberada: nada em claro — só máscara e hash.';

alter table public.fornecedor_dados_bancarios enable row level security;
alter table public.fornecedor_dados_bancarios force row level security;
revoke all on public.fornecedor_dados_bancarios from public, anon, authenticated, service_role;
grant select on public.fornecedor_dados_bancarios to authenticated;
grant insert, update, delete on public.fornecedor_dados_bancarios to authenticated;

create policy fdb_select on public.fornecedor_dados_bancarios
  for select to authenticated using ( app.eh_gestao() );
create policy fdb_insert on public.fornecedor_dados_bancarios
  for insert to authenticated with check ( app.eh_editor() );
create policy fdb_update on public.fornecedor_dados_bancarios
  for update to authenticated using ( app.eh_editor() ) with check ( app.eh_editor() );
create policy fdb_delete on public.fornecedor_dados_bancarios
  for delete to authenticated using ( app.eh_editor() );

-- ============================================================================
-- contratos
-- ============================================================================
create table public.contratos (
  id                    uuid primary key default extensions.gen_random_uuid(),
  fornecedor_id         uuid not null references public.fornecedores(id) on delete restrict,
  objeto                text not null,
  vigencia_inicio       date not null,
  vigencia_fim          date,
  valor_mensal_centavos bigint check (valor_mensal_centavos >= 0),  -- [ADR-0016 item 2] + ADR-0010
  indice_reajuste       text,                                       -- 'IPCA','IGPM','INPC',...
  documento_id          uuid references public.documentos(id) on delete restrict,
  -- Renovação acima da alçada exige ata (alerta "renovação não deliberada", SPEC §5.3):
  deliberacao_id        uuid references public.deliberacoes(id) on delete restrict,
  contrato_anterior_id  uuid references public.contratos(id),       -- cadeia de renovação
  encerrado_em          date,
  criado_em             timestamptz not null default now(),
  criado_por            uuid references public.pessoas(id),
  constraint contratos_vigencia_ck check (vigencia_fim is null or vigencia_fim >= vigencia_inicio)
);
create index contratos_fornecedor_idx on public.contratos (fornecedor_id);
create index contratos_vencimento_idx on public.contratos (vigencia_fim)
  where vigencia_fim is not null and encerrado_em is null;  -- alerta "contrato vencendo" (30 dias)

comment on table public.contratos is
  'RLS: leitura para autenticado; escrita só editor. '
  'Por quê: "quanto pagamos pela portaria" é pergunta legítima de qualquer morador (SPEC §6.2). '
  'Contrato com pessoa física que exponha dado individual deve entrar como documento de '
  'visibilidade conselho — a restrição fica no DOCUMENTO, não nesta linha.';

alter table public.contratos enable row level security;
alter table public.contratos force row level security;
revoke all on public.contratos from public, anon, authenticated, service_role;
grant select on public.contratos to authenticated;
grant insert, update, delete on public.contratos to authenticated;

create policy contratos_select on public.contratos
  for select to authenticated using ( app.eh_autenticado() );
create policy contratos_insert on public.contratos
  for insert to authenticated with check ( app.eh_editor() );
create policy contratos_update on public.contratos
  for update to authenticated using ( app.eh_editor() ) with check ( app.eh_editor() );
create policy contratos_delete on public.contratos
  for delete to authenticated using ( app.eh_editor() );

-- ============================================================================
-- periodos_fechados — [ADR-0016 item 8]
-- ============================================================================
create table public.periodos_fechados (
  competencia            date primary key
                         check (competencia = date_trunc('month', competencia::timestamp)::date),
  fechado_em             timestamptz not null default now(),
  fechado_por            uuid not null references public.pessoas(id),
  saldo_inicial_centavos bigint,
  saldo_final_centavos   bigint,
  reaberto_em            timestamptz,
  reaberto_por           uuid references public.pessoas(id),
  motivo_reabertura      text,
  constraint periodos_reabertura_ck check (
    reaberto_em is null or (reaberto_por is not null and length(btrim(motivo_reabertura)) >= 10))
);

comment on table public.periodos_fechados is
  'RLS: leitura para autenticado (o selo "mês fechado" é sinal de confiança na UI); escrita só '
  'editor. Por quê: é a trava que impede mexer no passado. saldo_final de um mês = saldo_inicial '
  'do seguinte é uma das três travas de consistência do SPEC §5.1.3.';

alter table public.periodos_fechados enable row level security;
alter table public.periodos_fechados force row level security;
revoke all on public.periodos_fechados from public, anon, authenticated, service_role;
grant select on public.periodos_fechados to authenticated;
grant insert, update on public.periodos_fechados to authenticated; -- delete: ninguém (histórico de fechamento é permanente)

create policy periodos_fechados_select on public.periodos_fechados
  for select to authenticated using ( app.eh_autenticado() );
create policy periodos_fechados_insert on public.periodos_fechados
  for insert to authenticated with check ( app.eh_editor() );
create policy periodos_fechados_update on public.periodos_fechados
  for update to authenticated using ( app.eh_editor() ) with check ( app.eh_editor() );
