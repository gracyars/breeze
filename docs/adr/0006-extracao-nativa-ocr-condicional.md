# ADR-0006 — Extração nativa primeiro, OCR condicional via API paga

## Contexto

O acervo tem PDF nativo (texto embutido) e PDF escaneado, em proporção desconhecida. Atas antigas
frequentemente já vêm com uma camada de OCR ruim — **pior que nenhuma**, porque parece texto e
não é. OCR em toda página custa dinheiro e, em página nativa, degrada o que já estava certo.

## Decisão

Pipeline em duas passadas por página:

1. **Extração nativa** sempre primeiro (texto + rotação), guardada em
   `documento_paginas.texto_nativo` — preservada mesmo quando descartada, para diagnóstico.
2. **Heurística de decisão** por página: dispara OCR quando
   `< 100 caracteres úteis/página` **ou** razão alta de gibberish (proporção de tokens fora do
   léxico PT-BR, sequências de consoantes improváveis, densidade de caracteres não imprimíveis).
   Os dois limiares vivem em `configuracoes`, não em código.
3. **OCR por API paga** quando a heurística dispara. Grava `confianca_ocr` por página e marca
   `fonte_texto = 'ocr'`. `documentos.ocr_aplicado = true`.
4. `documento_paginas.texto` é o texto **efetivo** (nativo ou OCR) — é dele que saem os chunks.

Regra dura que decorre: **valor financeiro nunca é aceito direto do OCR** (SPEC §3.3, §5.1).
Troca de dígito (8/3, 5/6, 0/O) é o modo de falha típico, e um dígito errado num balancete é
exatamente o erro que destrói a credibilidade do produto (Risco §8.4). Todo número passa pela
conferência humana lado a lado e pelas travas de consistência.

## Consequências

- Custo único de OCR do acervo estimado em R$50–300 (SPEC §1.2), e custo incremental baixo
  (5–20 documentos/mês). O envio para API externa é decisão de tratamento de dado pessoal:
  precisa constar do registro de operações LGPD e o fornecedor precisa ser contratado como
  operador. Item para `juridico-lgpd`.
- `confianca_ocr` por página é insumo de UI: a página com confiança baixa é sinalizada ao leitor
  e priorizada na revisão humana das atas estruturantes (Risco §8.3).
- A heurística vai errar nos dois sentidos. Por isso o reprocessamento precisa ser barato e
  idempotente: `documentos.sha256` + `versao_pipeline` como chave (SPEC §3), forçando OCR por
  flag quando a `editor` discordar da heurística.
- Fica registrado: PDF com camada de OCR ruim preexistente é o caso em que a extração nativa
  "funciona" e entrega lixo. A razão de gibberish existe para pegar exatamente isso — se ela não
  pegar na prática, o gatilho manual é a saída.

## Alternativas descartadas

- **Tesseract self-hosted.** Qualidade inferior em scan torto e abaixo de 200 DPI, que é
  justamente o acervo antigo do condomínio. Somaria manutenção de binário nativo (contra
  ADR-0007) para entregar pior resultado.
- **OCR em toda página.** Custo desnecessário e degradação ativa de páginas nativas.
- **Confiar na camada de OCR preexistente do PDF.** É a origem do pior dado do acervo.
- **Extração de tabela por modelo multimodal como fonte primária de valor.** Descartado por
  SPEC §5.1: a fonte de valor é a conferência humana; o modelo propõe, nunca publica.

## Status

Aceito. Formaliza ADR-6 da tabela do SPEC §1.1.
