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
revoke all on audit.log from anon, authenticated, service_role;
-- V4: `service_role` continua SEM NENHUM privilégio aqui, de propósito — audit.log só é escrito
-- pelo trigger SECURITY DEFINER (roda como o dono da tabela, não como service_role) e só é lido
-- por audit.verificar_cadeia(), também SECURITY DEFINER. "service_role não alcança o schema
-- audit" é o comportamento correto, não uma lacuna (D3 do auditor-rls).

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
-- ============================================================================
-- V9 (auditor-rls + juridico-lgpd, docs/juridico/pareceres/2026-09-04-cpf-hash-na-trilha.md) —
-- allowlist de colunas LIBERADAS para entrar em claro no snapshot antes/depois de audit.log.
-- FAIL-SAFE POR DESENHO: esta tabela é lista do que foi ANALISADO e liberado, com motivo — nunca
-- do que deve sumir. Coluna nova em qualquer tabela auditada nasce REDIGIDA por padrão, sem
-- ninguém precisar lembrar de protegê-la; alguém precisa lembrar de LIBERAR, que é decisão
-- consciente, com dono e justificativa (mesma lição de D12: não reescrever o predicado por
-- tabela, uma fonte só). audit.log é permanente e encadeado por hash — redação é na escrita ou
-- nunca; não existe "corrigir depois" sem quebrar a cadeia.
-- ============================================================================
create table audit.colunas_liberadas (
  tabela text not null,
  coluna text not null,
  motivo text not null,
  primary key (tabela, coluna)
);

comment on table audit.colunas_liberadas is
  'Fonte única de "o que pode aparecer em claro" no snapshot antes/depois de audit.log. Qualquer '
  'coluna de qualquer tabela auditada que NÃO esteja aqui é redigida ([REDIGIDO]) automaticamente '
  'por audit.fn_registrar() — inclusive coluna criada depois desta migração. Ver parecer '
  'docs/juridico/pareceres/2026-09-04-cpf-hash-na-trilha.md.';

insert into audit.colunas_liberadas (tabela, coluna, motivo) values
  -- pessoas: nome/email/telefone LIBERADOS por juízo de proporcionalidade do parecer (nome já é
  -- permanente em atas por exigência legal; email/telefone provam desvio de magic link — Risco
  -- nº6). cpf_hash/cpf_enc/cpf_ultimos_digitos/observacoes continuam redigidos: cpf_hash é
  -- pseudonimização (determinístico + domínio ~10⁹ = reversível com o pepper), e o CPF não existe
  -- em nenhum outro lugar permanente do acervo — a trilha seria a única cópia eterna.
  ('pessoas','id','identificador técnico'),
  ('pessoas','auth_user_id','identificador técnico'),
  ('pessoas','nome','parecer 2026-09-04: permanente em atas por exigência legal (art. 16, I); redigir não compra privacidade e cega o registro no Risco nº6'),
  ('pessoas','email','parecer 2026-09-04: prova desvio de magic link pela editora — ataque concreto do desenho (SPEC §2.1)'),
  ('pessoas','telefone','parecer 2026-09-04: mesmo motivo de email'),
  ('pessoas','ativa','flag operacional, sem conteúdo pessoal em si'),
  ('pessoas','anonimizada_em','marcador técnico da rotina de anonimização'),
  ('pessoas','criado_em','timestamp técnico'),
  ('pessoas','criado_por','FK técnica (uuid), resolvível por join'),
  ('pessoas','atualizado_em','timestamp técnico'),
  -- papeis
  ('papeis','id','identificador técnico'),
  ('papeis','pessoa_id','FK técnica'),
  ('papeis','papel','valor de enum fechado, não identidade'),
  ('papeis','mandato_inicio','data técnica'),
  ('papeis','mandato_fim','data técnica'),
  ('papeis','concedido_por','FK técnica'),
  ('papeis','criado_em','timestamp técnico'),
  -- vinculos
  ('vinculos','id','identificador técnico'),
  ('vinculos','unidade_id','FK técnica'),
  ('vinculos','pessoa_id','FK técnica'),
  ('vinculos','tipo','valor de enum fechado'),
  ('vinculos','inicio','data técnica'),
  ('vinculos','fim','data técnica — o fato datado do off-boarding (parecer off-boarding-ex-morador.md)'),
  ('vinculos','motivo_fim','valor de enum fechado, não texto livre'),
  ('vinculos','criado_em','timestamp técnico'),
  ('vinculos','criado_por','FK técnica'),
  -- documentos (titulo e metadados FORA — podem conter nome, ex.: "CARTA DE RENÚNCIA - SÍNDICO
  -- [NOME]", achado real do acervo em docs/inventario-acervo.md)
  ('documentos','id','identificador técnico'),
  ('documentos','tipo','FK textual de domínio'),
  ('documentos','data_documento','data técnica'),
  ('documentos','competencia','data técnica'),
  ('documentos','storage_bucket','identificador técnico'),
  ('documentos','storage_path','identificador técnico, sem nome legível (ADR-0004 item 5)'),
  ('documentos','sha256','hash de conteúdo, não de pessoa'),
  ('documentos','bytes','metadado técnico'),
  ('documentos','paginas','metadado técnico'),
  ('documentos','ocr_aplicado','flag técnica'),
  ('documentos','status','valor de enum fechado'),
  ('documentos','visibilidade','valor de enum fechado'),
  ('documentos','tem_paginas_mistas','flag técnica'),
  ('documentos','versao_pipeline','metadado técnico'),
  ('documentos','publicado_em','timestamp técnico'),
  ('documentos','publicado_por','FK técnica'),
  ('documentos','criado_em','timestamp técnico'),
  ('documentos','criado_por','FK técnica'),
  ('documentos','atualizado_em','timestamp técnico'),
  -- documento_unidades
  ('documento_unidades','documento_id','FK técnica'),
  ('documento_unidades','unidade_id','FK técnica'),
  ('documento_unidades','criado_em','timestamp técnico'),
  -- lancamentos (historico e motivo_estorno FORA — texto livre, V9)
  ('lancamentos','id','identificador técnico'),
  ('lancamentos','data_competencia','data técnica'),
  ('lancamentos','data_caixa','data técnica'),
  ('lancamentos','conta_id','FK técnica'),
  ('lancamentos','fornecedor_id','FK técnica'),
  ('lancamentos','valor_centavos','valor financeiro — é o próprio propósito da trilha (ADR-0011)'),
  ('lancamentos','tipo','valor de enum fechado'),
  ('lancamentos','fundo','valor de enum fechado'),
  ('lancamentos','documento_id','FK técnica'),
  ('lancamentos','pagina_origem','metadado técnico'),
  ('lancamentos','origem','valor de enum fechado'),
  ('lancamentos','deliberacao_id','FK técnica'),
  ('lancamentos','estorna_lancamento_id','FK técnica'),
  ('lancamentos','criado_por','FK técnica'),
  ('lancamentos','criado_em','timestamp técnico'),
  -- lancamento_anexos (descricao FORA — texto livre)
  ('lancamento_anexos','id','identificador técnico'),
  ('lancamento_anexos','lancamento_id','FK técnica'),
  ('lancamento_anexos','storage_bucket','identificador técnico'),
  ('lancamento_anexos','storage_path','identificador técnico'),
  ('lancamento_anexos','sha256','hash de conteúdo'),
  ('lancamento_anexos','tipo','valor de enum fechado'),
  ('lancamento_anexos','enviado_por','FK técnica'),
  ('lancamento_anexos','enviado_em','timestamp técnico'),
  -- orcamento
  ('orcamento','id','identificador técnico'),
  ('orcamento','exercicio','metadado técnico'),
  ('orcamento','conta_id','FK técnica'),
  ('orcamento','mes','metadado técnico'),
  ('orcamento','valor_previsto_centavos','valor financeiro, propósito da trilha'),
  ('orcamento','documento_id','FK técnica'),
  ('orcamento','criado_em','timestamp técnico'),
  ('orcamento','criado_por','FK técnica'),
  -- cobrancas
  ('cobrancas','id','identificador técnico'),
  ('cobrancas','unidade_id','FK técnica'),
  ('cobrancas','competencia','data técnica'),
  ('cobrancas','valor_centavos','valor financeiro, propósito da trilha'),
  ('cobrancas','vencimento','data técnica'),
  ('cobrancas','status','valor de enum fechado'),
  ('cobrancas','valor_pago_centavos','valor financeiro, propósito da trilha'),
  ('cobrancas','data_pagamento','data técnica'),
  ('cobrancas','documento_id','FK técnica'),
  ('cobrancas','criado_em','timestamp técnico'),
  ('cobrancas','atualizado_em','timestamp técnico'),
  -- fornecedores (razao_social e nome_fantasia FORA — prestador PF é nome de pessoa, V9; cpf_*
  -- redigido pela MESMA régua de pessoas, ADR-0014 item 7)
  ('fornecedores','id','identificador técnico'),
  ('fornecedores','cnpj','identificador de pessoa jurídica, não física'),
  ('fornecedores','categoria','taxonomia'),
  ('fornecedores','eh_sindico_terceirizado','flag técnica'),
  ('fornecedores','eh_administradora','flag técnica'),
  ('fornecedores','ativo','flag técnica'),
  ('fornecedores','criado_em','timestamp técnico'),
  ('fornecedores','criado_por','FK técnica'),
  -- fornecedor_dados_bancarios (banco/agencia/conta_mascarada/chave_pix_hash FORA — dado
  -- financeiro identificador, não avaliado)
  ('fornecedor_dados_bancarios','id','identificador técnico'),
  ('fornecedor_dados_bancarios','fornecedor_id','FK técnica'),
  ('fornecedor_dados_bancarios','vigente_desde','timestamp técnico'),
  ('fornecedor_dados_bancarios','vigente_ate','timestamp técnico'),
  ('fornecedor_dados_bancarios','documento_id','FK técnica'),
  ('fornecedor_dados_bancarios','registrado_por','FK técnica'),
  -- contratos (objeto FORA — texto livre, não avaliado)
  ('contratos','id','identificador técnico'),
  ('contratos','fornecedor_id','FK técnica'),
  ('contratos','vigencia_inicio','data técnica'),
  ('contratos','vigencia_fim','data técnica'),
  ('contratos','valor_mensal_centavos','valor financeiro, propósito da trilha'),
  ('contratos','indice_reajuste','taxonomia'),
  ('contratos','documento_id','FK técnica'),
  ('contratos','deliberacao_id','FK técnica'),
  ('contratos','contrato_anterior_id','FK técnica'),
  ('contratos','encerrado_em','data técnica'),
  ('contratos','criado_em','timestamp técnico'),
  ('contratos','criado_por','FK técnica'),
  -- deliberacoes (descricao e trecho_literal FORA — texto literal de ata, V9 explícito)
  ('deliberacoes','id','identificador técnico'),
  ('deliberacoes','assembleia_id','FK técnica'),
  ('deliberacoes','item','metadado técnico'),
  ('deliberacoes','resultado','valor fechado'),
  ('deliberacoes','votos_favor','metadado técnico'),
  ('deliberacoes','votos_contra','metadado técnico'),
  ('deliberacoes','abstencoes','metadado técnico'),
  ('deliberacoes','valor_autorizado_centavos','valor financeiro, propósito da trilha'),
  ('deliberacoes','documento_id','FK técnica'),
  ('deliberacoes','pagina','metadado técnico'),
  ('deliberacoes','chunk_id','FK técnica (ponteiro fraco)'),
  ('deliberacoes','criado_em','timestamp técnico'),
  ('deliberacoes','criado_por','FK técnica'),
  -- assembleias (local FORA — texto livre, não avaliado)
  ('assembleias','id','identificador técnico'),
  ('assembleias','tipo','valor fechado'),
  ('assembleias','data','data técnica'),
  ('assembleias','ata_documento_id','FK técnica'),
  ('assembleias','edital_documento_id','FK técnica'),
  ('assembleias','quorum_presente','metadado técnico'),
  ('assembleias','criado_em','timestamp técnico'),
  ('assembleias','criado_por','FK técnica'),
  -- configuracoes (descricao FORA — texto livre, não avaliado; valor é limiar/config, não PII)
  ('configuracoes','chave','identificador técnico'),
  ('configuracoes','valor','limiar de configuração, nunca dado pessoal por desenho (SPEC §5.3)'),
  ('configuracoes','publica','flag técnica'),
  ('configuracoes','atualizado_em','timestamp técnico'),
  ('configuracoes','atualizado_por','FK técnica'),
  -- periodos_fechados (motivo_reabertura FORA — texto livre)
  ('periodos_fechados','competencia','chave técnica'),
  ('periodos_fechados','fechado_em','timestamp técnico'),
  ('periodos_fechados','fechado_por','FK técnica'),
  ('periodos_fechados','saldo_inicial_centavos','valor financeiro, propósito da trilha'),
  ('periodos_fechados','saldo_final_centavos','valor financeiro, propósito da trilha'),
  ('periodos_fechados','reaberto_em','timestamp técnico'),
  ('periodos_fechados','reaberto_por','FK técnica'),
  -- questionamentos (texto e resposta FORA — V9 explícito)
  ('questionamentos','id','identificador técnico'),
  ('questionamentos','lancamento_id','FK técnica'),
  ('questionamentos','autor_id','FK técnica'),
  ('questionamentos','status','valor fechado'),
  ('questionamentos','respondido_por','FK técnica'),
  ('questionamentos','respondido_em','timestamp técnico'),
  ('questionamentos','criado_em','timestamp técnico'),
  -- pareceres (texto FORA — V9 explícito; a identidade do signatário é discussão separada, ADR
  -- pendente com arquiteto/juridico-lgpd sobre parecer_signatarios)
  ('pareceres','id','identificador técnico'),
  ('pareceres','competencia_inicio','data técnica'),
  ('pareceres','competencia_fim','data técnica'),
  ('pareceres','versao','metadado técnico'),
  ('pareceres','conclusao','valor fechado'),
  ('pareceres','status','valor fechado'),
  ('pareceres','documento_id','FK técnica'),
  ('pareceres','emitido_em','timestamp técnico'),
  ('pareceres','criado_em','timestamp técnico'),
  -- contas (nome/nome_administradora LIBERADOS — nomenclatura de plano de contas, não dado de
  -- pessoa; renomear conta É o evento que a trilha precisa mostrar)
  ('contas','id','identificador técnico'),
  ('contas','codigo','identificador técnico'),
  ('contas','nome','nomenclatura de plano de contas, não dado de pessoa — renomear conta é o evento auditável'),
  ('contas','natureza','valor fechado'),
  ('contas','nivel','metadado técnico'),
  ('contas','conta_pai_id','FK técnica'),
  ('contas','aceita_lancamento','flag técnica'),
  ('contas','fundo','valor fechado'),
  ('contas','codigo_administradora','identificador técnico'),
  ('contas','nome_administradora','nomenclatura de plano de contas, não dado de pessoa'),
  ('contas','ativa','flag técnica'),
  ('contas','criado_em','timestamp técnico');

alter table audit.colunas_liberadas enable row level security;
revoke all on audit.colunas_liberadas from anon, authenticated, service_role;

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

  -- 3) Linha antes/depois, com REDAÇÃO por ALLOWLIST (V9) — senão a trilha vira segunda cópia
  --    irremovível de dado pessoal (ADR-0013), permanente e encadeada por hash: redação é na
  --    escrita ou nunca. Só o que está em audit.colunas_liberadas passa em claro; toda coluna
  --    fora da lista — inclusive coluna criada depois desta migração — vira '[REDIGIDO]'
  --    (preservando o FATO de que a coluna tinha valor e mudou, sem expor o valor: "ninguém
  --    audita a correção de um CPF lendo a trilha; o valor antigo não tem uso fiscalizatório",
  --    parecer 2026-09-04). Valor já NULL na linha original permanece NULL — não há fato a
  --    preservar aí.
  if tg_op in ('UPDATE', 'DELETE') then
    select jsonb_object_agg(
             kv.key,
             case
               when jsonb_typeof(kv.value) = 'null' then kv.value
               when exists (select 1 from audit.colunas_liberadas cl
                             where cl.tabela = tg_table_name and cl.coluna = kv.key)
                 then kv.value
               else to_jsonb('[REDIGIDO]'::text)
             end
           )
      into v_antes
      from jsonb_each(to_jsonb(old)) kv;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    select jsonb_object_agg(
             kv.key,
             case
               when jsonb_typeof(kv.value) = 'null' then kv.value
               when exists (select 1 from audit.colunas_liberadas cl
                             where cl.tabela = tg_table_name and cl.coluna = kv.key)
                 then kv.value
               else to_jsonb('[REDIGIDO]'::text)
             end
           )
      into v_depois
      from jsonb_each(to_jsonb(new)) kv;
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

  -- 5) IP/user-agent: DECISÃO PENDENTE (V9, docs/juridico/pareceres/2026-09-04-cpf-hash-na-trilha.md
  --    §"ip e user_agent"). IP é dado pessoal, e audit.log é permanente e imutável — gravá-lo sem
  --    decisão explícita é a mesma classe de erro que motivou este parecer inteiro (redigir/reter
  --    é decisão de escrita, nunca corrigível depois). Até essa decisão vir, as colunas
  --    permanecem NULL sempre — elas continuam existindo no schema (não é regressão de schema,
  --    é conservadorismo de dado). v_headers fica lido mas não usado, para o dia em que a decisão
  --    vier ser só trocar estas duas linhas por null, sem tocar no resto da função.
  v_headers := null; -- intencionalmente não lido de request.headers ainda
  v_ip := null;
  v_user_agent := null;

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
revoke all on audit.ancoras from anon, authenticated, service_role;

-- ============================================================================
-- audit.acesso — LEITURA de dado sensível. SEM encadeamento, EXPURGÁVEL em 6 meses.
-- [ADR-0016 item 9] Separada de audit.log de propósito: SPEC §7 exige retenção de 6 meses para
-- log de acesso, e expurgo é INCOMPATÍVEL com cadeia de hash.
-- Escrita: rotina de servidor (service_role), nunca trigger — não há "AFTER SELECT" em Postgres;
-- quem lê CPF em claro/inadimplência nominal/anexo financeiro/export grava aqui explicitamente.
--
-- NÃO ADICIONAR hash_registro/hash_anterior AQUI. Instrução explícita do orquestrador (V9): esta
-- tabela é o que mantém a decisão de retenção REVERSÍVEL — expurgo de 6 meses só funciona
-- porque não há cadeia para quebrar. Encadear audit.acesso um dia repete, aqui, o mesmo problema
-- que motivou o parecer inteiro sobre audit.log. Qualquer proposta de encadeamento passa pelo
-- orquestrador antes de virar migração.
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
  'servidor com service_role (bypassa RLS), não por trigger. NÃO adicionar hash-chain aqui sem '
  'aprovação do orquestrador (V9) — é o que mantém a retenção curta reversível.';

alter table audit.acesso enable row level security;
revoke all on audit.acesso from anon, authenticated, service_role;
-- V4: `service_role` é quem grava aqui (rotina de servidor sem sessão de usuário) e quem expurga
-- depois de 6 meses. USAGE na schema é o pré-requisito que faltava — sem ele, mesmo com GRANT de
-- tabela, o acesso falha em "permission denied for schema audit".
grant usage on schema audit to service_role;
grant select, insert, delete on audit.acesso to service_role;

-- ============================================================================
-- audit.verificar_cadeia(desde, ate) — recalcula o encadeamento e devolve a PRIMEIRA linha
-- inconsistente (ou nada). Roda semanalmente, antes de gerar a âncora, e sob demanda.
--
-- V5 (auditor-rls, achado real — corrigido): fn_registrar() grava `hash_anterior = NULL` na
-- linha gênese (não há linha anterior) e calcula hash_registro com
-- `digest(coalesce(hash_anterior,'\x00') || canonico, ...)`. A versão anterior desta função
-- comparava o `hash_anterior` ARMAZENADO (NULL na gênese) contra o SENTINELA `'\x00'::bytea` —
-- `NULL IS DISTINCT FROM '\x00'::bytea` é sempre verdadeiro, então a gênese era relatada como
-- quebrada em TODA execução, mesmo numa cadeia intacta. Alarme permanente = nenhuma detecção
-- (a âncora semanal gritaria toda semana, e adulteração real ficaria indistinguível do falso
-- positivo). Correção: comparar o `hash_anterior` armazenado contra o valor ESPERADO NÃO
-- coalescido (NULL na gênese, o hash_registro real da linha anterior nos demais casos); o
-- COALESCE só entra no cálculo do hash — exatamente como em fn_registrar().
-- ============================================================================
create or replace function audit.verificar_cadeia(desde bigint default 1, ate bigint default null)
returns table(seq bigint, motivo text)
language plpgsql security definer set search_path = '' as $$
declare
  r record;
  v_hash_esperado bytea;
  v_canonico bytea;
  -- O que hash_anterior DEVERIA conter nesta linha: NULL só na gênese real (não existe nenhuma
  -- linha com seq < desde); o hash_registro de fato da ÚLTIMA linha EXISTENTE antes de `desde`
  -- em todo o resto — nunca o sentinela '\x00' diretamente, que só entra coalescido no CÁLCULO
  -- do hash abaixo.
  v_hash_anterior_esperado bytea;
begin
  -- V5-R (auditor-rls, 2ª rodada): a versão anterior buscava `seq = desde - 1`, assumindo seq
  -- contíguo. Toda transação abortada queima um nextval(): `desde - 1` pode simplesmente não
  -- existir, mesmo com a cadeia íntegra — e a verificação incremental (a que audit.ancoras
  -- existe para servir) acusava quebra falsa depois de qualquer gap. Buscar "a última linha
  -- ANTES de `desde`", em vez de assumir que `desde - 1` existe, corrige nos dois modos (desde=1
  -- e desde>1) com a MESMA consulta — não é caso especial, é a forma certa de expressar "a linha
  -- anterior", contígua ou não.
  select l.hash_registro into v_hash_anterior_esperado
    from audit.log l where l.seq < desde order by l.seq desc limit 1;

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
    v_hash_esperado := extensions.digest(coalesce(v_hash_anterior_esperado, '\x00'::bytea) || v_canonico, 'sha256');

    if r.hash_anterior is distinct from v_hash_anterior_esperado or r.hash_registro is distinct from v_hash_esperado then
      seq := r.seq;
      motivo := case
        when r.hash_anterior is distinct from v_hash_anterior_esperado
          then 'hash_anterior não bate com hash_registro da linha anterior (ou não é NULL na gênese, seq ' || r.seq::text || ')'
        else 'hash_registro não bate com o recomputado a partir do conteúdo canônico da própria linha'
      end;
      return next;
      return;
    end if;

    v_hash_anterior_esperado := r.hash_registro;
  end loop;

  return;
end $$;

revoke all on function audit.verificar_cadeia(bigint, bigint) from public, anon, authenticated;
