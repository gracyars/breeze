-- Breeze — baseline 03: identidade e cadastro (unidades, pessoas, vinculos, papeis).
-- Fonte: docs/schema.md §5. Convenção de dinheiro (ADR-0010), CPF (ADR-0014), RLS (ADR-0012).
--
-- RLS é HABILITADA e FORÇADA aqui, na mesma migração que cria cada tabela (ADR-0008 item 5).
-- As policies concretas dependem de app.tem_papel()/app.eh_gestao()/app.unidades_da_pessoa(),
-- que só existem depois (essas funções leem estas tabelas) — ver
-- 20260904120400_funcoes_app.sql e 20260904120500_identidade_rls.sql. Enquanto não há policy,
-- RLS forçada + zero policy = negação total: é o "nasce com política de negação por padrão".

-- ============================================================================
-- unidades
-- ============================================================================
create table public.unidades (
  id            uuid primary key default extensions.gen_random_uuid(),
  bloco         text not null default '',        -- '' quando o condomínio não tem bloco
  numero        text not null,                   -- [ADR-0016 item 10] texto: '101-A', 'Cob 02', 'Loja 1'
  ordem         int,                             -- ordenação natural; evita cast de numero
  fracao_ideal  numeric(12,9) not null check (fracao_ideal > 0 and fracao_ideal <= 1),
  area_m2       numeric(10,2) check (area_m2 > 0),
  ativa         boolean not null default true,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint unidades_bloco_numero_uk unique (bloco, numero)
);
create index unidades_ordem_idx on public.unidades (bloco, ordem, numero);

comment on table public.unidades is
  'RLS: leitura para qualquer autenticado; escrita só editor. Não é dado pessoal — é a planta do '
  'condomínio, e todo morador precisa vê-la para entender rateio por fração ideal.';
comment on column public.unidades.fracao_ideal is
  'Fração ideal, NÃO é dinheiro (ADR-0010 item 5). A soma das frações das unidades ativas deve '
  'ser 1; isso é invariante verificada por teste, não por constraint de tabela.';

-- ============================================================================
-- pessoas — tabela mais sensível do schema
-- ============================================================================
create table public.pessoas (
  id            uuid primary key default extensions.gen_random_uuid(),
  -- Única amarra a auth.users (ADR-0002). Anulável: pessoa pode existir sem conta
  -- (ex-morador preservado para histórico; morador ainda não convidado).
  auth_user_id  uuid unique references auth.users(id) on delete set null,
  nome          text not null check (length(btrim(nome)) >= 3),
  -- e-mail já normalizado em minúsculas pela aplicação; check impede o resto.
  email         text unique check (email is null or email = lower(btrim(email))),
  -- ADR-0014: HMAC-SHA256(cpf_normalizado, PEPPER) calculado NA APLICAÇÃO.
  -- O pepper nunca entra no banco. Dump sem pepper não permite lookup por CPF.
  cpf_hash      bytea unique check (cpf_hash is null or octet_length(cpf_hash) = 32),
  -- ADR-0014: nonce(12) || AES-256-GCM(cpf) || tag(16), cifrado NA APLICAÇÃO.
  cpf_enc       bytea,
  -- Exibição mascarada ao conselho: '***.***.789-**'. Guarda os dígitos 7-9.
  -- NUNCA os dígitos verificadores (deles se deriva material para reduzir busca).
  cpf_ultimos_digitos char(3) check (cpf_ultimos_digitos ~ '^[0-9]{3}$'),
  telefone      text,
  ativa         boolean not null default true,
  observacoes   text,
  criado_em     timestamptz not null default now(),
  criado_por    uuid references public.pessoas(id),
  atualizado_em timestamptz not null default now(),
  -- V8 (parecer docs/juridico/off-boarding-ex-morador.md item 5.3): marca QUANDO a rotina de
  -- anonimização (fim+5 anos, F1 — não construída em F0) rodou sobre esta pessoa. NULL = nunca
  -- anonimizada. Não é consultada por nenhuma policy/função hoje; é só o registro do estado, para
  -- a futura rotina ser idempotente.
  anonimizada_em timestamptz,
  constraint pessoas_cpf_par_ck check ((cpf_hash is null) = (cpf_enc is null))
);
create index pessoas_nome_trgm_idx on public.pessoas using gin (nome extensions.gin_trgm_ops);

-- ADR-0012 item 7 / ADR-0014 item 4 — ÚNICA exceção de privilégio de coluna do schema.
-- RLS é por linha e não esconde coluna; cpf_enc sai do alcance de `authenticated` por GRANT.
-- ARMADILHA DE POSTGRES (achada e corrigida nesta migração antes de aplicar em qualquer
-- ambiente): `REVOKE SELECT (col) ON tabela FROM role` NÃO subtrai de um `GRANT SELECT ON
-- tabela` já concedido — table-level e column-level ACL são UNIÃO, nunca subtração. "GRANT
-- SELECT na tabela toda, depois REVOKE SELECT só na coluna" não bloqueia nada, em NENHUMA
-- ordem. A única forma real de excluir uma coluna é NUNCA conceder SELECT de tabela inteira e
-- em vez disso conceder SELECT coluna a coluna — ver GRANT explícito no bloco de RLS abaixo
-- (substitui o `grant select on public.pessoas` genérico).

comment on table public.pessoas is
  'RLS: pessoa lê a PRÓPRIA linha; conselho lê todas SEM CPF; editor lê todas. Escrita só editor. '
  'Por quê: é o cadastro de dado pessoal do condomínio. O lookup de login por CPF acontece em '
  'rotina de servidor com service_role (ADR-0003) — não pela RLS, porque nesse momento não há '
  'sessão. CPF em claro exige decifra na aplicação + registro em audit.acesso (ADR-0014).';

-- ============================================================================
-- vinculos
-- ============================================================================
create table public.vinculos (
  id          uuid primary key default extensions.gen_random_uuid(),
  unidade_id  uuid not null references public.unidades(id) on delete restrict,
  pessoa_id   uuid not null references public.pessoas(id) on delete restrict,
  tipo        public.tipo_vinculo not null,
  inicio      date not null default current_date,
  fim         date,
  -- V8 (parecer off-boarding-ex-morador.md item 5.3): `fim` já é o fato datado que a editora
  -- registra para parar a cobrança — `motivo_fim` só torna esse fato explícito e distingue venda
  -- de erro de cadastro para a futura rotina de anonimização (F1). Só preenchível junto com `fim`.
  motivo_fim  public.motivo_fim_vinculo,
  criado_em   timestamptz not null default now(),
  criado_por  uuid references public.pessoas(id),
  constraint vinculos_periodo_ck check (fim is null or fim >= inicio),
  constraint vinculos_motivo_fim_ck check (motivo_fim is null or fim is not null)
);
create index vinculos_unidade_fim_idx on public.vinculos (unidade_id, fim);
create index vinculos_pessoa_vigente_idx on public.vinculos (pessoa_id) where fim is null;
create unique index vinculos_vigente_uk on public.vinculos (unidade_id, pessoa_id, tipo)
  where fim is null;

comment on table public.vinculos is
  'RLS: pessoa vê os vínculos das PRÓPRIAS unidades; gestão vê todos; escrita só editor. '
  'Por quê: esta tabela É o predicado de "própria unidade" usado por cobrancas e por documento '
  'restrito. Vínculo errado = morador vendo dado de vizinho. Escrita aqui é evento auditado.';

-- ============================================================================
-- papeis
-- ============================================================================
create table public.papeis (
  id             uuid primary key default extensions.gen_random_uuid(),
  pessoa_id      uuid not null references public.pessoas(id) on delete cascade,
  papel          public.papel not null,
  mandato_inicio date not null default current_date,
  mandato_fim    date,
  concedido_por  uuid references public.pessoas(id),
  motivo         text,
  criado_em      timestamptz not null default now(),
  constraint papeis_mandato_ck check (mandato_fim is null or mandato_fim >= mandato_inicio)
);
create index papeis_pessoa_fim_idx on public.papeis (pessoa_id, mandato_fim);
create unique index papeis_vigente_uk on public.papeis (pessoa_id, papel) where mandato_fim is null;
-- Índice que app.tem_papel() percorre a cada avaliação de policy:
create index papeis_papel_vigente_idx on public.papeis (papel, mandato_inicio, mandato_fim);

comment on table public.papeis is
  'RLS: pessoa lê os PRÓPRIOS papéis; gestão lê todos; escrita só editor com AAL2. '
  'Por quê: é a tabela que decide quem pode o quê — a raiz da autorização. Uma pessoa pode '
  'acumular papéis (morador + conselho); por isso a primitiva é tem_papel(), não papel_atual(). '
  '[ADR-0016 item 3] Não existe papel admin — é o editor com AAL2. '
  'RISCO REGISTRADO (D4/D9): com editor única, quem concede papel é quem já detém todos. A '
  'trilha encadeada (ADR-0013) é a única contenção.';

-- ============================================================================
-- RLS — enable + force + revoke/grant de tabela, na mesma migração da criação (ADR-0008 item 5).
-- Sem policy ainda: RLS forçada nega tudo, inclusive para o dono da tabela e para authenticated/
-- anon com GRANT concedido — é a rede de segurança até 20260904120500_identidade_rls.sql.
-- ============================================================================

alter table public.unidades enable row level security;
alter table public.unidades force row level security;
revoke all on public.unidades from public, anon, authenticated, service_role;
grant select on public.unidades to authenticated;
grant insert, update, delete on public.unidades to authenticated;

alter table public.pessoas enable row level security;
alter table public.pessoas force row level security;
revoke all on public.pessoas from public, anon, authenticated, service_role;
-- GRANT SELECT coluna a coluna, SEM cpf_enc — nunca "grant select on public.pessoas" (ver
-- armadilha de Postgres comentada junto à definição da tabela: revoke de coluna não subtrai de
-- grant de tabela, em nenhuma ordem).
grant select (id, auth_user_id, nome, email, cpf_hash, cpf_ultimos_digitos, telefone, ativa,
  observacoes, criado_em, criado_por, atualizado_em, anonimizada_em) on public.pessoas to authenticated;
grant insert, update on public.pessoas to authenticated; -- delete: ninguém (anonimização, não exclusão)
-- INSERT/UPDATE de tabela inteira (acima) permanecem, inclusive cpf_enc: é o editor cifrando e
-- gravando; só a LEITURA de volta é vedada.
-- V4: service_role precisa da tabela INTEIRA (inclusive cpf_enc) para duas rotinas de servidor
-- sem sessão de usuário — lookup de login por cpf_hash (SPEC §2.1) e decifra de CPF sob pedido
-- do editor, registrada em audit.acesso (ADR-0014). Papel diferente de `authenticated`: a
-- restrição de cpf_enc é só para o papel de app, não para o backend que decifra por definição.
grant select on public.pessoas to service_role;

alter table public.vinculos enable row level security;
alter table public.vinculos force row level security;
revoke all on public.vinculos from public, anon, authenticated, service_role;
grant select on public.vinculos to authenticated;
grant insert, update, delete on public.vinculos to authenticated;

alter table public.papeis enable row level security;
alter table public.papeis force row level security;
revoke all on public.papeis from public, anon, authenticated, service_role;
grant select on public.papeis to authenticated;
grant insert, update on public.papeis to authenticated; -- delete: ninguém (mandato_fim, nunca apagar linha)

-- ****************************************************************************
-- V10 (decisão do orquestrador, 2026-09-04), corrigido na 3ª rodada (V10-R, auditor-rls).
-- Com editor única (D4), a editora consegue rodar UPDATE pessoas SET ativa=false NELA MESMA.
-- app.pessoa_atual() filtra por `ativa` — ela deixa de ser editor, e ninguém reverte:
-- service_role não tem UPDATE em pessoas nem papeis (V4, de propósito). Não é vazamento, é
-- indisponibilidade IRREVERSÍVEL do produto inteiro — mesma classe de risco da D9.
--
-- V10-R (achado real): a 1ª versão vigiava COLUNA (`update of ativa`, `update of mandato_fim`) e
-- deixou passar três rotas que não tocam nessas colunas nomeadas ou que escapam da checagem
-- sequencial:
--   1. UPDATE papeis SET mandato_inicio = current_date + 30  -- não é `mandato_fim`, mas também
--      tira a vigência (mandato passa a começar no futuro).
--   2. UPDATE papeis SET papel = 'morador'                    -- não é `mandato_fim` nem
--      `mandato_inicio`, e também tira a vigência de editor.
--   3. Duas transações concorrentes, cada uma desativando um editor diferente: sob READ
--      COMMITTED, `not exists (...)` de cada uma não enxerga a mudança (ainda não commitada) da
--      outra — as duas passam, o resultado final é ZERO editores vigentes.
-- MESMA CLASSE DE DEFEITO do V1-R/V3-R (predicado validado no caminho enumerado, não no estado
-- resultante) — agora entre COLUNAS da mesma tabela, não entre tabelas. Correção: trigger sem
-- `OF coluna` nenhuma (dispara em QUALQUER UPDATE da linha) comparando o ESTADO — "era editor
-- vigente e deixou de ser" — nunca o caminho; mais um advisory lock explícito, com a MESMA chave
-- nos dois triggers (pessoas e papeis), porque a corrida também existe ENTRE os dois caminhos
-- (alguém desativando via pessoas.ativa enquanto outra sessão fecha o mandato via papeis).
-- ****************************************************************************

-- Predicado único de "esta linha de papeis conta como editor vigente" — evita duplicar a fórmula
-- nos dois triggers (a mesma lição da D12/armadilha nº1: uma fonte, nunca duas cópias).
create or replace function public.eh_editor_vigente_linha(
  p_papel public.papel, p_mandato_inicio date, p_mandato_fim date, p_pessoa_ativa boolean
) returns boolean language sql stable as $$
  select p_pessoa_ativa
     and p_papel = 'editor'
     and p_mandato_inicio <= current_date
     and (p_mandato_fim is null or p_mandato_fim >= current_date)
$$;

-- Caminho 1: qualquer UPDATE em pessoas que faça uma editora vigente deixar de ser ativa.
create or replace function public.tg_pessoas_impede_autotranca_editor()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_era_editor_vigente boolean;
begin
  if new.ativa then
    return new; -- não é uma transição para inativa; nada a checar
  end if;

  select exists (
    select 1 from public.papeis pa
     where pa.pessoa_id = new.id
       and public.eh_editor_vigente_linha(pa.papel, pa.mandato_inicio, pa.mandato_fim, old.ativa)
  ) into v_era_editor_vigente;

  if v_era_editor_vigente then
    -- Advisory lock — MESMA chave do trigger de papeis abaixo: serializa as duas rotas de saída
    -- (via pessoas.ativa e via papeis) contra si mesmas e uma contra a outra (V10-R item 3).
    perform pg_advisory_xact_lock(84032217);

    if not exists (
      select 1 from public.papeis pa
        join public.pessoas pe on pe.id = pa.pessoa_id
       where pa.pessoa_id <> new.id
         and public.eh_editor_vigente_linha(pa.papel, pa.mandato_inicio, pa.mandato_fim, pe.ativa)
    ) then
      raise exception
        'Não é possível desativar % (ativa=false): é a única pessoa com papel editor vigente '
        '(D9/V10). Designe outro editor antes de desativar esta — sem isso, o sistema perde o '
        'único papel de escrita e ninguém consegue reverter (service_role não tem UPDATE em '
        'pessoas nem papeis, de propósito).', new.id;
    end if;
  end if;

  return new;
end $$;

create trigger pessoas_impede_autotranca_editor
  before update on public.pessoas
  for each row execute function public.tg_pessoas_impede_autotranca_editor();

-- Caminho 2: qualquer UPDATE em papeis que faça uma linha de editor vigente deixar de sê-lo —
-- por mandato_fim, por mandato_inicio empurrado para o futuro, por troca de papel, ou por
-- qualquer outra combinação futura das mesmas três colunas. Vigia o ESTADO resultante
-- (eh_editor_vigente_linha antes/depois), não uma lista de colunas.
create or replace function public.tg_papeis_impede_fim_ultimo_editor()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_pessoa_ativa_antes  boolean;
  v_pessoa_ativa_depois boolean;
  v_era_editor_vigente boolean;
  v_continua_editor_vigente boolean;
begin
  -- Dois lookups, não um: papeis.pessoa_id pode mudar (INV-02, caminho 7 — transferir o papel de
  -- editor para uma pessoa inativa). Buscar a "atividade" uma vez só, por new.pessoa_id, e reusar
  -- para o estado ANTES é o bug que este comentário documenta para não voltar: fazia o "era
  -- editor vigente" ser calculado com a atividade da pessoa NOVA (o alvo, possivelmente
  -- inativo), então uma transferência para pessoa inativa nunca era detectada como perda de
  -- vigência — a checagem via `v_era_editor_vigente and not v_continua` dava sempre falso.
  select pe.ativa into v_pessoa_ativa_antes  from public.pessoas pe where pe.id = old.pessoa_id;
  select pe.ativa into v_pessoa_ativa_depois from public.pessoas pe where pe.id = new.pessoa_id;

  v_era_editor_vigente := public.eh_editor_vigente_linha(old.papel, old.mandato_inicio, old.mandato_fim, v_pessoa_ativa_antes);
  v_continua_editor_vigente := public.eh_editor_vigente_linha(new.papel, new.mandato_inicio, new.mandato_fim, v_pessoa_ativa_depois);

  if v_era_editor_vigente and not v_continua_editor_vigente then
    -- MESMA chave do advisory lock de pessoas acima — ver comentário lá.
    perform pg_advisory_xact_lock(84032217);

    if not exists (
      select 1 from public.papeis pa
        join public.pessoas pe on pe.id = pa.pessoa_id
       where pa.id <> new.id
         and public.eh_editor_vigente_linha(pa.papel, pa.mandato_inicio, pa.mandato_fim, pe.ativa)
    ) then
      raise exception
        'Não é possível alterar este papel de % (pessoa %) de forma que deixe de contar como '
        'editor vigente: é a última pessoa com papel editor vigente (D9/V10). Designe outro '
        'editor antes.', new.id, new.pessoa_id;
    end if;
  end if;

  return new;
end $$;

create trigger papeis_impede_fim_ultimo_editor
  before update on public.papeis
  for each row execute function public.tg_papeis_impede_fim_ultimo_editor();
