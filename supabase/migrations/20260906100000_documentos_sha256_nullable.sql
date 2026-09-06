-- Breeze — F1 corte C2: `documentos.sha256` passa a ser NULLABLE (ADR-0025, contradição nº1 do
-- schema real de F0).
--
-- O ADR-0004 decidiu, com razão, que o hash é calculado NO WORKER, nunca aceito do cliente
-- ("o cliente pode mentir"). A coluna nascia `not null unique`: com as duas regras juntas, a
-- linha não podia nascer — o estágio 0 (registro humano, ADR-0025 §1) cria `documentos` ANTES de
-- qualquer leitura do Storage; `sha256` só passa a existir depois que o estágio 1 (`hash_dedupe`)
-- lê o objeto.
--
-- O `unique` PERMANECE — não é relaxado, só deixa de coexistir com `not null`. Múltiplos NULL
-- são permitidos (semântica padrão de índice único em Postgres: NULL nunca é igual a NULL), e é
-- isso que se quer: várias linhas `pendente` sem hash ainda ao mesmo tempo. Quando o hash É
-- preenchido, a violação de unicidade CONTINUA sendo a detecção de duplicata (SPEC §3.1) — é
-- assim que o par #15/#16 do acervo real (dois lembretes da ata AGE de 04.02.2026, byte-idênticos,
-- docs/inventario-acervo.md) deve se comportar: o segundo upload vai para `documentos.status =
-- 'erro'` com `erro_detalhe` apontando o `documentos.id` original (ADR-0025 §Consequências),
-- nunca duas linhas com o mesmo sha256.
alter table public.documentos alter column sha256 drop not null;

comment on column public.documentos.sha256 is
  'NULL até o estágio 1 (hash_dedupe, ADR-0025 §1) rodar — a linha nasce humana (estágio 0, sem '
  'hash: o cliente pode mentir, ADR-0004), o worker calcula e grava o hash ao ler o objeto no '
  'Storage. UNIQUE permanece (múltiplos NULL são permitidos): a violação de unicidade na escrita '
  'do estágio 1 É a detecção de duplicata — vai para documentos.status=''erro'' com '
  'erro_detalhe apontando o documentos.id original (ADR-0025 §Consequências; caso de teste real: '
  'par #15/#16 do acervo, docs/inventario-acervo.md). O hash calculado no browser continua '
  'permitido como conveniência de UI (''você já enviou este arquivo''), nunca como valor gravado.';
