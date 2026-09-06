-- Breeze — F1 corte C2: unicidade de `job.fila.chave_idempotencia` passa de TOTAL para PARCIAL
-- (ADR-0025 §2, ADR-0026 §1) — e índice de job por documento (ADR-0025 §Consequências, item 3
-- da lista do corte C2 em docs/f1-plano.md).
--
-- BUG QUE ISTO FECHA (E2, docs/ops/divida-tecnica.md; ADR-0026): com `unique` TOTAL sobre toda a
-- história da tabela, `insert ... on conflict (chave_idempotencia) do nothing` vira NO-OP
-- PERMANENTE assim que o primeiro job daquela chave chega a `concluido`. Reenfileirar o MESMO
-- trabalho mais tarde — reprocessamento parcial (SPEC §3: "reprocessar tudo deve ser um
-- comando"), o botão "tentar de novo" de um job `morto` (ADR-0026 caminho 6), ou o trigger
-- invalidador de chunks (ADR-0026 caminho 3, corte C4) — nunca insere nada, SEM ERRO.
--
-- O que precisa continuar impedido é só (a) DUAS EXECUÇÕES SIMULTÂNEAS do mesmo trabalho e
-- (b) enfileiramento duplicado por caminhos concorrentes pedindo a mesma coisa ao mesmo tempo
-- (ex.: UI e trigger). Nenhum dos dois exige olhar para jobs já `concluido`/`erro`/`morto` — só
-- para o que está `pendente` ou `processando` agora. Linhas concluídas permanecem como histórico,
-- fora do escopo desta unicidade (ADR-0025 §2).
alter table job.fila drop constraint fila_chave_idempotencia_key;

create unique index fila_chave_idempotencia_ativa_uk on job.fila (chave_idempotencia)
  where status in ('pendente', 'processando');

comment on index job.fila_chave_idempotencia_ativa_uk is
  'Unicidade PARCIAL (ADR-0025 §2, fecha o bug E2 do ADR-0026): impede job pendente/processando '
  'duplicado para a mesma chave_idempotencia. NÃO impede reenfileirar a mesma chave depois que o '
  'job anterior CONCLUIU — isso é intencional, é o comportamento que a unicidade total quebrava. '
  'job.enfileirar() (migração seguinte) é o único ponto que insere contra este índice.';

-- Índice de job por documento (ADR-0025 §Consequências: "índice de busca de job por documento").
-- É a consulta que sustenta: o botão "tentar de novo" num documento em erro (ADR-0026 caminho 6,
-- §5 — "leitura de indexado_em na UI" depende de saber se já há job em curso para não duplicar
-- visualmente), a sentinela de documentos fora da busca (ADR-0026 §4, corte C4) e a tela de
-- acervo da editora ("há trabalho pendente para este documento?"). Escopo restrito a
-- pendente/processando: histórico concluído/morto não responde a essa pergunta e não deve
-- inflar o índice para sempre — mesmo raciocínio do índice acima.
create index fila_documento_idx on job.fila ((payload ->> 'documento_id'))
  where status in ('pendente', 'processando');

comment on index job.fila_documento_idx is
  'Suporta "quais jobs pendentes/processando existem para este documento?" (ADR-0025 '
  '§Consequências). job.enfileirar() garante que payload sempre carrega a chave ''documento_id'' '
  '(como texto do uuid), então esta expressão nunca depende de um chamador lembrar de incluí-la.';
