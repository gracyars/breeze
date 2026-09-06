-- Breeze — F1 corte C2: `documento_paginas.motor_texto` (ADR-0024 §2).
--
-- `fonte_texto` já registra a CLASSE do texto efetivo desta página (nativo/ocr/misto/vazio) —
-- falta registrar qual MOTOR produziu esse texto. Sem isso, "reprocessar só as páginas que o
-- motor local (Apple Vision) errou" não é expressável como consulta, e a eventual queda para API
-- paga por gatilho nomeado (ADR-0024 §3, G1/G2/G3) vira varredura manual em vez de filtro.
--
-- Domínio: valor do TIPO (não enum fechado — o rótulo carrega versão/fornecedor, que muda sem
-- exigir migração; ADR-0024 §2 escreve o formato por extenso, não fecha uma lista):
--   'nativo'                     — extração nativa (estágio 2), sem OCR.
--   'vision:<versão do SO>'      — Apple Vision local (estágio 3), motor primário (ADR-0024 §1).
--   'api:<fornecedor>:<modelo>'  — API paga, só sob gatilho G1/G2/G3 (ADR-0024 §3), documento a
--                                  documento, nunca acervo inteiro.
-- O CHECK abaixo fecha o prefixo (garante que todo valor gravado é reconhecível por consulta —
-- `motor_texto like 'vision:%'`, etc.) sem fechar a versão/fornecedor, que são informação livre.
alter table public.documento_paginas
  add column motor_texto text
    check (motor_texto is null
           or motor_texto = 'nativo'
           or motor_texto like 'vision:%'
           or motor_texto like 'api:%');

comment on column public.documento_paginas.motor_texto is
  'Qual motor produziu documento_paginas.texto (ADR-0024 §2). NULL antes do estágio 2/3 rodar. '
  '''nativo'' = extração nativa, sem OCR. ''vision:<versão do SO>'' = Apple Vision local, motor '
  'primário desde ADR-0024. ''api:<fornecedor>:<modelo>'' = API paga, só sob gatilho nomeado '
  'G1/G2/G3 (ADR-0024 §3), por documento. Distinto de fonte_texto: fonte_texto é a CLASSE '
  '(nativo/ocr/misto/vazio); motor_texto é o adaptador concreto — necessário para filtrar '
  'reprocessamento por motor sem virar varredura manual.';
