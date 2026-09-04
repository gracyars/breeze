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
  constraint pessoas_cpf_par_ck check ((cpf_hash is null) = (cpf_enc is null))
);
create index pessoas_nome_trgm_idx on public.pessoas using gin (nome extensions.gin_trgm_ops);

-- ADR-0012 item 7 / ADR-0014 item 4 — ÚNICA exceção de privilégio de coluna do schema.
-- RLS é por linha e não esconde coluna; cpf_enc sai do alcance de `authenticated` por GRANT.
revoke select (cpf_enc) on public.pessoas from authenticated, anon;

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
  criado_em   timestamptz not null default now(),
  criado_por  uuid references public.pessoas(id),
  constraint vinculos_periodo_ck check (fim is null or fim >= inicio)
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
revoke all on public.unidades from public, anon, authenticated;
grant select on public.unidades to authenticated;
grant insert, update, delete on public.unidades to authenticated;

alter table public.pessoas enable row level security;
alter table public.pessoas force row level security;
revoke all on public.pessoas from public, anon, authenticated;
grant select on public.pessoas to authenticated; -- cpf_enc já sem SELECT por grant de coluna acima
grant insert, update on public.pessoas to authenticated; -- delete: ninguém (anonimização, não exclusão)

alter table public.vinculos enable row level security;
alter table public.vinculos force row level security;
revoke all on public.vinculos from public, anon, authenticated;
grant select on public.vinculos to authenticated;
grant insert, update, delete on public.vinculos to authenticated;

alter table public.papeis enable row level security;
alter table public.papeis force row level security;
revoke all on public.papeis from public, anon, authenticated;
grant select on public.papeis to authenticated;
grant insert, update on public.papeis to authenticated; -- delete: ninguém (mandato_fim, nunca apagar linha)
