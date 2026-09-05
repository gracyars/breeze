-- Breeze — baseline 13: lancamentos — imutável, correção por estorno (ADR-0011).
-- Fonte: docs/schema.md §8.5. Bloqueio de UPDATE/DELETE em TRÊS camadas — a terceira alcança
-- inclusive service_role, que ignora RLS e REVOKE de tabela por padrão.

create table public.lancamentos (
  id               uuid primary key default extensions.gen_random_uuid(),
  data_competencia date not null
                   check (data_competencia = date_trunc('month', data_competencia::timestamp)::date),
  data_caixa       date,
  conta_id         uuid not null references public.contas(id) on delete restrict,
  fornecedor_id    uuid references public.fornecedores(id) on delete restrict,
  historico        text not null check (length(btrim(historico)) >= 3),
  valor_centavos   bigint not null check (valor_centavos <> 0),   -- ADR-0010
  tipo             public.tipo_lancamento not null,
  fundo            public.fundo not null default 'nenhum',

  -- SPEC §5.1.4: "todo lançamento nasce com documento_id + pagina_origem. Sem fonte, não existe."
  documento_id     uuid not null references public.documentos(id) on delete restrict,
  pagina_origem    int not null check (pagina_origem > 0),

  origem           public.origem_lancamento not null default 'balancete_importado',
  -- [ADR-0016 item 6] Débito em fundo exige a ata que autorizou (SPEC §5.3, alerta crítico).
  deliberacao_id   uuid references public.deliberacoes(id) on delete restrict,

  -- ADR-0011: estorno é lançamento comum com self-FK e valor negativo.
  estorna_lancamento_id uuid unique references public.lancamentos(id) on delete restrict,
  motivo_estorno   text,

  criado_por       uuid not null references public.pessoas(id),
  criado_em        timestamptz not null default now(),

  -- Sinal amarrado ao papel da linha: normal > 0, estorno < 0. SUM() fica correto sem filtro.
  constraint lancamentos_sinal_ck check (
    (estorna_lancamento_id is     null and valor_centavos > 0) or
    (estorna_lancamento_id is not null and valor_centavos < 0)),
  constraint lancamentos_motivo_ck check (
    estorna_lancamento_id is null or length(btrim(motivo_estorno)) >= 10)
);

create index lancamentos_competencia_conta_idx on public.lancamentos (data_competencia, conta_id);
create index lancamentos_conta_competencia_idx on public.lancamentos (conta_id, data_competencia);
create index lancamentos_fornecedor_idx        on public.lancamentos (fornecedor_id, data_competencia);
create index lancamentos_documento_idx         on public.lancamentos (documento_id);
create index lancamentos_fundo_idx             on public.lancamentos (fundo, data_competencia)
  where fundo <> 'nenhum';

-- ============================================================================
-- Trigger 1/4 — lancamentos_bloqueia_mutacao. Terceira camada do ADR-0011: REVOKE (abaixo) não
-- alcança service_role nem o dono da tabela; esta trava alcança, porque roda para QUALQUER role.
-- Levanta exceção SEMPRE, em UPDATE ou DELETE. Manutenção estrutural legítima (ex.: migração de
-- correção de dado por incidente grave) exige desabilitar o trigger explicitamente, dentro de
-- migração revisada — nunca em runtime.
-- ============================================================================
create or replace function public.tg_lancamentos_bloqueia_mutacao()
returns trigger language plpgsql as $$
begin
  raise exception
    'lancamentos é imutável (ADR-0011). Correção é sempre estorno: novo lançamento com '
    'estorna_lancamento_id e valor_centavos negativo. Tentativa de % bloqueada para o registro %.',
    tg_op, coalesce(old.id, new.id);
end $$;
create trigger lancamentos_bloqueia_mutacao
  before update or delete on public.lancamentos
  for each row execute function public.tg_lancamentos_bloqueia_mutacao();

-- ============================================================================
-- V2 (auditor-rls, achado real): TRUNCATE furava as três camadas do ADR-0011. REVOKE não
-- alcança service_role nem o dono da tabela (ver 20260904120000, default privilege de
-- plataforma); a policy de RLS não se aplica a TRUNCATE (não é DML de linha); e o trigger acima
-- é FOR EACH ROW — TRUNCATE não dispara trigger de linha, só de STATEMENT. `truncate lancamentos
-- cascade` zerava o razão inteiro sem deixar UMA linha de trilha. audit.log já resolvia isso com
-- um trigger STATEMENT-level (audit_log_imutavel_truncate) — mesmo padrão aqui, replicado.
-- ============================================================================
create or replace function public.tg_lancamentos_bloqueia_truncate()
returns trigger language plpgsql as $$
begin
  raise exception
    'lancamentos é imutável (ADR-0011). TRUNCATE bloqueado — inclusive para o dono da tabela e '
    'para service_role (V2, auditor-rls). Terceira camada, agora também cobrindo TRUNCATE.';
end $$;

create trigger lancamentos_bloqueia_truncate
  before truncate on public.lancamentos
  for each statement execute function public.tg_lancamentos_bloqueia_truncate();

-- ============================================================================
-- Trigger 2/4 — lancamentos_valida_estorno. BEFORE INSERT, só quando estorna_lancamento_id
-- is not null:
--   a) o alvo existe e tem estorna_lancamento_id is null (estorno de estorno é proibido)
--   b) new.valor_centavos = -alvo.valor_centavos (exato, sem tolerância)
--   c) new.conta_id = alvo.conta_id e new.tipo = alvo.tipo e new.fundo = alvo.fundo
--      (estorno não reclassifica; reclassificar é estornar e lançar de novo)
--   d) new.documento_id herdado do alvo quando não houver documento novo
-- "estornado no máximo uma vez" já vem do UNIQUE em estorna_lancamento_id.
-- ============================================================================
create or replace function public.tg_lancamentos_valida_estorno()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_alvo public.lancamentos;
begin
  if new.estorna_lancamento_id is null then
    return new;
  end if;

  select * into v_alvo from public.lancamentos where id = new.estorna_lancamento_id;
  if v_alvo is null then
    raise exception 'estorna_lancamento_id % não existe', new.estorna_lancamento_id;
  end if;
  if v_alvo.estorna_lancamento_id is not null then
    raise exception 'lançamento % já é um estorno; estorno de estorno é proibido', v_alvo.id;
  end if;
  if new.valor_centavos <> -v_alvo.valor_centavos then
    raise exception 'estorno de % precisa valer exatamente % (recebido %)',
      v_alvo.id, -v_alvo.valor_centavos, new.valor_centavos;
  end if;
  if new.conta_id <> v_alvo.conta_id or new.tipo <> v_alvo.tipo or new.fundo <> v_alvo.fundo then
    raise exception
      'estorno de % não pode reclassificar conta/tipo/fundo — estorne e lance de novo', v_alvo.id;
  end if;
  if new.documento_id is null then
    new.documento_id := v_alvo.documento_id;
  end if;

  return new;
end $$;
create trigger lancamentos_valida_estorno
  before insert on public.lancamentos
  for each row execute function public.tg_lancamentos_valida_estorno();

-- ============================================================================
-- Trigger 3/4 — lancamentos_periodo_aberto. BEFORE INSERT: rejeita competência com
-- periodos_fechados.reaberto_em IS NULL (SPEC §5.4). Vale também para o estorno — corrigir um
-- lançamento de mês fechado exige reabrir o período primeiro, com motivo auditado.
-- ============================================================================
create or replace function public.tg_lancamentos_periodo_aberto()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_fechado public.periodos_fechados;
begin
  select * into v_fechado from public.periodos_fechados where competencia = new.data_competencia;
  if v_fechado is not null and v_fechado.reaberto_em is null then
    raise exception
      'competência % está fechada (fechado_em %). Reabra o período (com motivo) antes de lançar.',
      new.data_competencia, v_fechado.fechado_em;
  end if;
  return new;
end $$;
create trigger lancamentos_periodo_aberto
  before insert on public.lancamentos
  for each row execute function public.tg_lancamentos_periodo_aberto();

-- ============================================================================
-- Trigger 4/4 — lancamentos_exige_deliberacao. BEFORE INSERT.
-- [D12, docs/dominio/plano-de-contas-decisoes.md] Reescrito: NÃO consulta mais
-- contas.exige_deliberacao (coluna removida — era flag fixa na conta, frágil, produzia falso
-- negativo silencioso sempre que a despesa finalística de fundo caía numa conta comum não
-- marcada). A regra correta é do LANÇAMENTO, não da conta: se tipo='despesa' e
-- fundo <> 'nenhum' e deliberacao_id is null -> NÃO bloqueia; grava aviso via RAISE WARNING
-- (a geração do alerta formal em `alertas` é do motor de F3, fora deste escopo). Sinalizar, não
-- bloquear silenciosamente (condominio-plano-de-contas §4) — trava dura aqui produziria
-- contorno criativo.
-- ============================================================================
create or replace function public.tg_lancamentos_exige_deliberacao()
returns trigger language plpgsql as $$
begin
  if new.tipo = 'despesa' and new.fundo <> 'nenhum' and new.deliberacao_id is null then
    raise warning
      'lançamento % debita fundo (%) sem deliberacao_id vinculada (SPEC §5.3, alerta "Fundo de '
      'reserva sem ata"). Não bloqueado — o motor de alertas (F3) sinaliza.', new.id, new.fundo;
  end if;
  return new;
end $$;
create trigger lancamentos_exige_deliberacao
  before insert on public.lancamentos
  for each row execute function public.tg_lancamentos_exige_deliberacao();

comment on table public.lancamentos is
  'RLS: leitura para autenticado (financeiro agregado é direito de qualquer condômino, SPEC '
  '§6.4-bis); INSERT só editor com AAL2; UPDATE e DELETE PARA NINGUÉM — sem policy, com REVOKE e '
  'com trigger que alcança inclusive service_role. '
  'Por quê: quem publica é quem seria auditada (Risco §8.6, D4). Lançamento editável faz do '
  'balancete publicado uma afirmação, não uma prova — que é a dor nº2 do briefing. '
  'Correção é sempre estorno (ADR-0011), visível na UI, nunca escondida.';

-- ============================================================================
-- RLS — select: autenticado; insert: editor; update/delete: NINGUÉM (sem policy + REVOKE +
-- trigger). REVOKE de UPDATE/DELETE aqui é defesa em profundidade — quem realmente impede
-- service_role é o trigger acima, que roda para QUALQUER role.
-- ============================================================================
alter table public.lancamentos enable row level security;
alter table public.lancamentos force row level security;
revoke all on public.lancamentos from public, anon, authenticated, service_role;
grant select on public.lancamentos to authenticated;
grant insert on public.lancamentos to authenticated; -- NUNCA update/delete, nem para authenticated

create policy lancamentos_select on public.lancamentos
  for select to authenticated
  using ( app.eh_autenticado() );

create policy lancamentos_insert on public.lancamentos
  for insert to authenticated
  with check ( app.eh_editor() );

-- Sem policy de update nem de delete — em conjunto com o REVOKE acima e o trigger
-- lancamentos_bloqueia_mutacao, fecha as três camadas do ADR-0011.
