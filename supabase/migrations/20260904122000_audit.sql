-- Breeze — baseline 20: trilha de auditoria — schema audit (ADR-0013). Fonte: docs/schema.md §12;
-- SPEC §7.

-- ============================================================================
-- audit.log — mutação de dado. Append-only, encadeada por hash, PERMANENTE.
-- ============================================================================
create table audit.log (
  seq           bigint generated always as identity primary key,
  ts            timestamptz not null default clock_timestamp(),
  actor_uid     uuid,          -- auth.uid()
  actor_pessoa_id uuid,
  actor_papel   text,
  acao          text not null check (acao in ('INSERT','UPDATE','DELETE','TRUNCATE')),
  schema_nome   text not null,
  tabela        text not null,
  registro_id   text,
  antes         jsonb,
  depois        jsonb,
  ip            inet,
  user_agent    text,
  hash_anterior bytea,
  hash_registro bytea not null unique
);
create index log_tabela_registro_idx on audit.log (tabela, registro_id, seq desc);
create index log_ts_idx              on audit.log (ts desc);

comment on table audit.log is
  'RLS: fora do PostgREST (schema audit sem USAGE para anon/authenticated). RLS habilitada, sem '
  'FORCE — o dono da tabela (postgres) precisa gravar via audit.fn_registrar() SECURITY DEFINER '
  'sem ser bloqueado; role sem privilégio de dono continua barrada por RLS + REVOKE + ausência '
  'de exposição. Imutabilidade real vem do trigger audit_log_imutavel abaixo, que bloqueia '
  'UPDATE/DELETE/TRUNCATE para QUALQUER role, inclusive o dono e service_role — REVOKE por si só '
  'não alcança nenhum dos dois.';

alter table audit.log enable row level security;
-- Higiene explícita — documental: quem realmente impede update/delete/truncate é o trigger
-- abaixo, que vale para QUALQUER role, inclusive quem tem GRANT ou é dono da tabela.
revoke update, delete, truncate on audit.log from public;
revoke all on audit.log from anon, authenticated;

-- ============================================================================
-- Imutabilidade em duas camadas. REVOKE não alcança o dono da tabela nem service_role
-- (service_role, no Supabase, não é o dono, mas herda privilégios amplos que REVOKE ... FROM
-- PUBLIC não remove); o trigger alcança, porque roda incondicionalmente para qualquer role.
-- TRUNCATE exige trigger STATEMENT-level (Postgres não permite trigger ROW-level em TRUNCATE).
-- ============================================================================
create or replace function audit.tg_log_imutavel()
returns trigger language plpgsql as $$
begin
  raise exception
    'audit.log é imutável e permanente (ADR-0013). % bloqueado — inclusive para o dono da '
    'tabela e para service_role. Nenhuma linha de trilha é corrigida ou apagada; se um valor '
    'estiver errado, a correção é uma NOVA linha que documenta o erro.', tg_op;
end $$;

create trigger audit_log_imutavel_linha
  before update or delete on audit.log
  for each row execute function audit.tg_log_imutavel();

create trigger audit_log_imutavel_truncate
  before truncate on audit.log
  for each statement execute function audit.tg_log_imutavel();

-- ----------------------------------------------------------------------------
-- SERIALIZAÇÃO CANÔNICA — parte do contrato. Mudar isto quebra a cadeia.
--   canonico = convert_to( jsonb_build_object(
--       'seq', seq, 'ts', ts, 'actor_uid', actor_uid, 'acao', acao,
--       'schema', schema_nome, 'tabela', tabela, 'registro_id', registro_id,
--       'antes', antes, 'depois', depois )::text, 'UTF8')
--   hash_registro = extensions.digest(coalesce(hash_anterior,'\x00'::bytea) || canonico,'sha256')
-- jsonb ordena e deduplica chaves de forma determinística -> hash reproduzível por qualquer
-- verificador que leia a linha. Ver audit.verificar_cadeia() no fim deste arquivo.
-- ----------------------------------------------------------------------------

-- ============================================================================
-- audit.fn_registrar() — AFTER INSERT/UPDATE/DELETE FOR EACH ROW, SECURITY DEFINER.
-- ============================================================================
create or replace function audit.fn_registrar()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_seq           bigint;
  v_ts            timestamptz := clock_timestamp();
  v_actor_uid     uuid := auth.uid();
  v_actor_pessoa_id uuid;
  v_actor_papel   text;
  v_row           jsonb;
  v_registro_id   text;
  v_antes         jsonb;
  v_depois        jsonb;
  v_headers       jsonb;
  v_ip            inet;
  v_user_agent    text;
  v_hash_anterior bytea;
  v_canonico      bytea;
  v_hash_registro bytea;
begin
  -- 1) Advisory lock ANTES de ler o último hash. Sem isso, duas transações concorrentes leem o
  --    mesmo hash_anterior e a cadeia BIFURCA — falha que só aparece sob carga (SPEC §7).
  --    Chave fixa, arbitrária, documentada aqui: identifica só "a fila da cadeia de audit.log".
  perform pg_advisory_xact_lock(72170314);

  select l.hash_registro into v_hash_anterior from audit.log l order by l.seq desc limit 1;

  -- 2) Ator: pessoa e papel vigente no momento do evento (não confiar em claim de JWT — mesma
  --    régua do app.tem_papel()).
  begin
    v_actor_pessoa_id := app.pessoa_atual();
    v_actor_papel := app.papel_atual()::text;
  exception when others then
    v_actor_pessoa_id := null;
    v_actor_papel := null;
  end;

  -- 3) Linha antes/depois, com REDAÇÃO de coluna sensível — senão a trilha vira segunda cópia
  --    irremovível de dado pessoal (ADR-0013). cpf_enc é a única coluna com esta exigência
  --    explícita no desenho (docs/schema.md §12).
  if tg_op in ('UPDATE', 'DELETE') then
    v_antes := to_jsonb(old);
    if v_antes ? 'cpf_enc' then
      v_antes := jsonb_set(v_antes, '{cpf_enc}', '"[redigido]"'::jsonb);
    end if;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    v_depois := to_jsonb(new);
    if v_depois ? 'cpf_enc' then
      v_depois := jsonb_set(v_depois, '{cpf_enc}', '"[redigido]"'::jsonb);
    end if;
  end if;

  -- 4) Identificador do registro — a maioria das tabelas auditadas tem `id`; as exceções têm
  --    chave primária textual (`configuracoes.chave`, `periodos_fechados.competencia`) ou
  --    composta (`documento_unidades`). Genérico o bastante para servir às 19 tabelas auditadas
  --    sem 19 versões desta função (armadilha nº1 se reescrita por tabela).
  v_row := coalesce(to_jsonb(new), to_jsonb(old));
  v_registro_id := coalesce(
    nullif(v_row->>'id', ''),
    nullif(v_row->>'chave', ''),
    nullif(v_row->>'competencia', ''),
    nullif((v_row->>'documento_id') || ':' || (v_row->>'unidade_id'), ':')
  );

  -- 5) IP/user-agent: melhor esforço, lidos de request.headers quando a chamada vem via '
  --    PostgREST/Supabase Auth. NÃO fazem parte do canônico assinado — falha aqui nunca quebra
  --    a cadeia.
  begin
    v_headers := nullif(current_setting('request.headers', true), '')::jsonb;
    v_ip := nullif(split_part(coalesce(v_headers->>'x-forwarded-for', ''), ',', 1), '')::inet;
    v_user_agent := v_headers->>'user-agent';
  exception when others then
    v_ip := null;
    v_user_agent := null;
  end;

  -- 6) Reserva o próximo seq explicitamente (não dá para INSERT...depois...UPDATE hash_registro:
  --    audit.log é imutável até para quem grava).
  v_seq := nextval(pg_get_serial_sequence('audit.log', 'seq'));

  v_canonico := convert_to(
    jsonb_build_object(
      'seq', v_seq, 'ts', v_ts, 'actor_uid', v_actor_uid, 'acao', tg_op,
      'schema', tg_table_schema, 'tabela', tg_table_name, 'registro_id', v_registro_id,
      'antes', v_antes, 'depois', v_depois
    )::text,
    'UTF8'
  );
  v_hash_registro := extensions.digest(coalesce(v_hash_anterior, '\x00'::bytea) || v_canonico, 'sha256');

  insert into audit.log
    (seq, ts, actor_uid, actor_pessoa_id, actor_papel, acao, schema_nome, tabela, registro_id,
     antes, depois, ip, user_agent, hash_anterior, hash_registro)
  overriding system value
  values
    (v_seq, v_ts, v_actor_uid, v_actor_pessoa_id, v_actor_papel, tg_op, tg_table_schema,
     tg_table_name, v_registro_id, v_antes, v_depois, v_ip, v_user_agent, v_hash_anterior,
     v_hash_registro);

  return coalesce(new, old);
end $$;

comment on function audit.fn_registrar() is
  'Fonte única de gravação em audit.log — nenhuma tabela audita "do seu próprio jeito". '
  'Contrato de serialização canônica é FIXO (comentário acima); mudar quebra verificação de '
  'cadeias já gravadas.';

-- ============================================================================
-- Triggers de auditoria — exatamente as 19 tabelas listadas em docs/schema.md §12.
-- NÃO auditadas: chunks, documento_paginas, job.fila (saída determinística de máquina, alto
-- volume, sem intenção humana, reproduzível a partir do PDF original); tipos_documento,
-- tipos_alerta, sinonimos (taxonomia, não decisão de negócio); alertas, parecer_signatarios
-- (fora da lista do desenho).
-- ============================================================================
create trigger audit_pessoas                  after insert or update or delete on public.pessoas                  for each row execute function audit.fn_registrar();
create trigger audit_papeis                   after insert or update or delete on public.papeis                   for each row execute function audit.fn_registrar();
create trigger audit_vinculos                 after insert or update or delete on public.vinculos                 for each row execute function audit.fn_registrar();
create trigger audit_documentos               after insert or update or delete on public.documentos               for each row execute function audit.fn_registrar();
create trigger audit_documento_unidades       after insert or update or delete on public.documento_unidades       for each row execute function audit.fn_registrar();
create trigger audit_lancamentos              after insert or update or delete on public.lancamentos              for each row execute function audit.fn_registrar();
create trigger audit_lancamento_anexos        after insert or update or delete on public.lancamento_anexos        for each row execute function audit.fn_registrar();
create trigger audit_orcamento                after insert or update or delete on public.orcamento                for each row execute function audit.fn_registrar();
create trigger audit_cobrancas                after insert or update or delete on public.cobrancas                for each row execute function audit.fn_registrar();
create trigger audit_fornecedores             after insert or update or delete on public.fornecedores             for each row execute function audit.fn_registrar();
create trigger audit_fornecedor_dados_bancarios after insert or update or delete on public.fornecedor_dados_bancarios for each row execute function audit.fn_registrar();
create trigger audit_contratos                after insert or update or delete on public.contratos                for each row execute function audit.fn_registrar();
create trigger audit_deliberacoes             after insert or update or delete on public.deliberacoes             for each row execute function audit.fn_registrar();
create trigger audit_assembleias              after insert or update or delete on public.assembleias              for each row execute function audit.fn_registrar();
create trigger audit_configuracoes            after insert or update or delete on public.configuracoes            for each row execute function audit.fn_registrar();
create trigger audit_periodos_fechados        after insert or update or delete on public.periodos_fechados        for each row execute function audit.fn_registrar();
create trigger audit_questionamentos          after insert or update or delete on public.questionamentos          for each row execute function audit.fn_registrar();
create trigger audit_pareceres                after insert or update or delete on public.pareceres                for each row execute function audit.fn_registrar();
create trigger audit_contas                   after insert or update or delete on public.contas                   for each row execute function audit.fn_registrar();

-- ============================================================================
-- audit.ancoras — âncora semanal do hash-topo, enviada por e-mail ao conselho (SPEC §7).
-- É o que impede reescrever o passado E recomputar a cadeia inteira para casar.
-- ============================================================================
create table audit.ancoras (
  id         uuid primary key default extensions.gen_random_uuid(),
  ate_seq    bigint not null,
  hash_topo  bytea not null,
  gerada_em  timestamptz not null default now(),
  enviada_em timestamptz,
  destinatarios text[]
);

alter table audit.ancoras enable row level security;
revoke all on audit.ancoras from anon, authenticated;

-- ============================================================================
-- audit.acesso — LEITURA de dado sensível. SEM encadeamento, EXPURGÁVEL em 6 meses.
-- [ADR-0016 item 9] Separada de audit.log de propósito: SPEC §7 exige retenção de 6 meses para
-- log de acesso, e expurgo é INCOMPATÍVEL com cadeia de hash.
-- Escrita: rotina de servidor (service_role), nunca trigger — não há "AFTER SELECT" em Postgres;
-- quem lê CPF em claro/inadimplência nominal/anexo financeiro/export grava aqui explicitamente.
-- ============================================================================
create table audit.acesso (
  id         bigint generated always as identity primary key,
  ts         timestamptz not null default now(),
  actor_pessoa_id uuid,
  recurso    text not null,   -- 'cpf_em_claro','inadimplencia_nominal','anexo_financeiro','export'
  recurso_id text,
  motivo     text,
  ip         inet
);
create index acesso_ts_idx on audit.acesso (ts desc);
create index acesso_recurso_idx on audit.acesso (recurso, ts desc);

comment on table audit.acesso is
  'RLS: fora do PostgREST, mesmo isolamento de audit.log. SEM encadeamento — expurgável em 6 '
  'meses (retenção SPEC §7), o que seria incompatível com hash-chain. Escrita por rotina de '
  'servidor com service_role (bypassa RLS), não por trigger.';

alter table audit.acesso enable row level security;
revoke all on audit.acesso from anon, authenticated;

-- ============================================================================
-- audit.verificar_cadeia(desde, ate) — recalcula o encadeamento e devolve a PRIMEIRA linha
-- inconsistente (ou nada). Roda semanalmente, antes de gerar a âncora, e sob demanda.
-- ============================================================================
create or replace function audit.verificar_cadeia(desde bigint default 1, ate bigint default null)
returns table(seq bigint, motivo text)
language plpgsql security definer set search_path = '' as $$
declare
  r record;
  v_hash_esperado bytea;
  v_hash_anterior bytea;
  v_canonico bytea;
begin
  if desde > 1 then
    select l.hash_registro into v_hash_anterior from audit.log l where l.seq = desde - 1;
  else
    v_hash_anterior := '\x00'::bytea;
  end if;

  for r in
    select l.* from audit.log l
     where l.seq >= desde and (ate is null or l.seq <= ate)
     order by l.seq
  loop
    v_canonico := convert_to(
      jsonb_build_object(
        'seq', r.seq, 'ts', r.ts, 'actor_uid', r.actor_uid, 'acao', r.acao,
        'schema', r.schema_nome, 'tabela', r.tabela, 'registro_id', r.registro_id,
        'antes', r.antes, 'depois', r.depois
      )::text,
      'UTF8'
    );
    v_hash_esperado := extensions.digest(coalesce(v_hash_anterior, '\x00'::bytea) || v_canonico, 'sha256');

    if r.hash_anterior is distinct from v_hash_anterior or r.hash_registro is distinct from v_hash_esperado then
      seq := r.seq;
      motivo := case
        when r.hash_anterior is distinct from v_hash_anterior
          then 'hash_anterior não bate com hash_registro da linha anterior (seq ' || (r.seq - 1)::text || ')'
        else 'hash_registro não bate com o recomputado a partir do conteúdo canônico da própria linha'
      end;
      return next;
      return;
    end if;

    v_hash_anterior := r.hash_registro;
  end loop;

  return;
end $$;

revoke all on function audit.verificar_cadeia(bigint, bigint) from public, anon, authenticated;
