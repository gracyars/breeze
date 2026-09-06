-- Breeze — F1 corte C2: `job.enfileirar` — único caminho de enfileiramento (ADR-0025 §2,
-- ADR-0026 §1-2).
--
-- Todo enfileiramento — Server Action de upload (estágio 1), o próprio worker ao concluir um
-- estágio (próximo estágio, mesmo commit), o trigger invalidador de chunks (ADR-0026 caminho 3,
-- corte C4 — NÃO implementado nesta migração), ação humana de curadoria ("rodar OCR nesta
-- página"), comando de reprocessamento e o botão "tentar de novo" num documento em erro — passa
-- por ESTA função. `insert` direto em `job.fila` não deve existir em lugar nenhum do schema.
-- Mesma razão do ADR-0012 para uma função só de visibilidade: seis lugares construindo
-- payload/chave à mão divergem, e divergem calados.
--
-- SECURITY DEFINER porque `job.fila` não tem GRANT direto para `authenticated` (schema fora do
-- PostgREST desde 20260904120000, ADR-0007/ADR-0025 §7) — quem chama precisa da PORTA, não de
-- acesso de tabela. A função roda com o privilégio do seu dono (o papel que aplica migração,
-- com BYPASSRLS local do Supabase — mesmo raciocínio já documentado no comentário de job.fila
-- sobre service_role), então o insert funciona independente de RLS/GRANT de quem chamou.
--
-- `on conflict (chave_idempotencia) where status in ('pendente','processando') do nothing`
-- depende da unicidade PARCIAL fila_chave_idempotencia_ativa_uk (migração anterior); contra a
-- unicidade total anterior isto seria o no-op permanente que o ADR-0026 corrige (bug E2).
create or replace function job.enfileirar(
  p_tipo         text,
  p_documento_id uuid,
  p_chave        text,
  p_payload      jsonb,
  p_prioridade   int default 100
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id      bigint;
  v_payload jsonb;
begin
  if p_tipo is null or btrim(p_tipo) = '' then
    raise exception 'job.enfileirar: p_tipo é obrigatório';
  end if;
  if p_documento_id is null then
    raise exception 'job.enfileirar: p_documento_id é obrigatório';
  end if;
  if p_chave is null or btrim(p_chave) = '' then
    raise exception 'job.enfileirar: p_chave (chave_idempotencia) é obrigatória';
  end if;

  -- documento_id sempre viaja no payload, mesmo que o chamador tenha esquecido de incluí-lo: é a
  -- chave que fila_documento_idx (migração anterior) e a futura sentinela (ADR-0026 §4, corte C4)
  -- leem. Fonte única, nunca reconstruída por quem lê a fila.
  v_payload := coalesce(p_payload, '{}'::jsonb)
               || jsonb_build_object('documento_id', p_documento_id::text);

  insert into job.fila (tipo, payload, chave_idempotencia, prioridade)
  values (p_tipo, v_payload, p_chave, coalesce(p_prioridade, 100))
  on conflict (chave_idempotencia) where status in ('pendente', 'processando') do nothing
  returning id into v_id;

  -- NULL quando já existia pendente/processando com esta chave — idempotência de fila
  -- (ADR-0025 §2). Quem chama e precisa saber "já havia trabalho em curso" lê o retorno NULL;
  -- não é erro.
  return v_id;
end;
$$;

comment on function job.enfileirar(text, uuid, text, jsonb, int) is
  'ÚNICO caminho de enfileiramento em job.fila (ADR-0025 §2, ADR-0026 §1). SECURITY DEFINER: '
  'chamador não precisa de GRANT direto na tabela job.fila. Retorna o id do job inserido, ou '
  'NULL quando já existia um job pendente/processando com a mesma chave_idempotencia — não '
  'impede reenfileirar depois que o job anterior CONCLUIU (era isso que a unicidade total '
  'quebrava, fechado pela migração 20260906100100).';

-- Postgres concede EXECUTE a PUBLIC por padrão em toda função nova — revogar explicitamente
-- antes de conceder só a quem deve chamar (mesmo padrão de defesa em profundidade já usado em
-- job.fila: revoke amplo, depois grant nomeado).
revoke all on function job.enfileirar(text, uuid, text, jsonb, int) from public;
-- `authenticated`: Server Action de upload, ação humana de curadoria/OCR, botão "tentar de novo"
-- — todos correm como o editor autenticado (ADR-0025 §Consequências: "estágio 0 é a ÚNICA
-- escrita de insert em documentos, feita por authenticated"). `service_role`: o worker, ao
-- concluir um estágio, enfileira o próximo na mesma transação (ADR-0025 §1). `anon` NUNCA: só
-- editor cria trabalho de ingestão.
grant usage on schema job to authenticated;
grant execute on function job.enfileirar(text, uuid, text, jsonb, int) to authenticated, service_role;
