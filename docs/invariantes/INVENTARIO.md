# Inventário de invariantes de autorização

Toda função em `app.*` referenciada por policy, e todo trigger de autorização, precisa de um
arquivo `INV-*.md` preenchido. **Célula vazia bloqueia merge** — ver `README.md`.

Backlog datado: preenchimento **antes de produção**, não antes do próximo merge. O gate passa a
valer imediatamente para invariante **nova ou alterada**.

| # | Invariante | ADR | Estado | Dono |
|---|---|---|---|---|
| INV-01 | Nível efetivo da página = override da própria página, ou piso do documento — **e nada mais** | 0023 | a preencher (o predicado muda: remoção do ramo não-local) | `eng-supabase` |
| **INV-02** | **Existe sempre ao menos um `editor` vigente** | 0022, **0030** | **preenchida — exemplo de referência.** **ALTERADA pelo ADR-0030:** o enunciado formal troca `current_date` por `now()` e `mandato_fim >= …` por `mandato_fim > …` (intervalo meia-aberto). A **matriz de caminhos não muda** — os 9 caminhos e F1–F3 continuam válidos, só o predicado avaliado em cada célula é outro. **F4 (fuso) deixa de ser `ACEITO`**: com `now()` a vigência é absoluta, e a ambiguidade de fuso sai do predicado e passa a viver só no tradutor data → instante (ADR-0030 §3), onde é declarada | `eng-supabase` |
| INV-03 | Piso: `ordem(documentos.visibilidade) <= ordem(cada página sua)` | 0019 | a preencher | `eng-supabase` |
| INV-04 | Chunk não cruza fronteira de visibilidade no seu intervalo | 0018, 0021 | a preencher — inclui o segundo caminho (reclassificação) | `eng-supabase` |
| INV-05 | `documento_visivel` ⊇ união do que suas páginas liberam (arquivo nunca mais aberto que conteúdo) | 0019 | a preencher | `eng-supabase` |
| INV-06 | Papel privilegiado exige AAL2 e mandato vigente | 0003, 0012, **0030** | a preencher — **"vigente" passa a ser `[inicio, fim)` em `now()`** | `eng-supabase` |
| INV-07 | `lancamentos` sem `UPDATE`/`DELETE`, inclusive `service_role` | 0011 | a preencher | `eng-supabase` |
| INV-08 | Estorno: valor exato inverso, mesma conta/tipo/fundo, uma vez só, não estornável | 0011 | a preencher | `eng-supabase` |
| INV-09 | `audit.log` append-only e cadeia íntegra (inclui contiguidade **não** assumida) | 0013, 0021 | a preencher — F4 é o V5-R | `eng-supabase` |
| INV-10 | `cpf_enc` fora do `GRANT SELECT`; nenhuma coluna nova entra por omissão | 0017 | a preencher | `eng-supabase` |
| INV-11 | Snapshot de signatário congela na assinatura e é imutável | 0020 | a preencher | `eng-supabase` |
| INV-12 | Acesso cessa em `vinculos.fim` + 0 dias (`eh_autenticado` derivada de vínculo/papel) | parecer `juridico-lgpd` C1, **0030** | a preencher — **bloqueia produção**. **ALTERADA pelo ADR-0030:** hoje o "+ 0 dias" é cumprido com resolução de **um dia** (ex-morador que vendeu às 9h enxerga o condomínio até a meia-noite); passa a ser cumprido em instante. Preencher **depois** da migração, contra o predicado novo — preencher agora congelaria a granularidade errada na célula | `eng-supabase` |
| INV-13 | **Derivado invalidado implica reconstrução enfileirada** — documento publicado com `indexado_em is null` tem job de `chunking` pendente/processando, ou aparece na sentinela | 0026 | **preenchida — 2026-09-06, corte C4.** Matriz de 19 linhas + 4 fixas; nível 3 (invalidação/reprocessamento); dois `ACEITO` documentados (escrita direta de `indexado_em` por editor/service_role — mesmo risco já aceito para D4/A1; e um gap latente sem vetor de escrita conhecido, `documento_paginas.pagina`) | `eng-supabase` |

| **INV-14** | **Vigência é `[inicio, fim)` avaliada em `now()`** — nenhuma função de autorização compara período com `current_date`, e nenhuma coluna de período de autorização é `date` | **0030** | a preencher — **nova, criada pelo ADR-0030**; preencher junto da migração | `eng-supabase` |

**Ordem sugerida de preenchimento:** INV-12 e INV-01 primeiro (bloqueiam produção e o predicado
está mudando), depois INV-03/04/05 (a família de visibilidade, onde três das quatro rodadas
falharam), depois o resto. **INV-12 e INV-14 caminham juntas com a migração do ADR-0030** — a
INV-12 não deve ser preenchida antes dela, sob pena de gravar na célula a granularidade que o ADR
acabou de rejeitar.

**Nota de método sobre a INV-14.** É a primeira invariante do inventário que é verificável **por
catálogo**, não só por comportamento: varrer `pg_proc` no schema `app` atrás de `current_date` em
função chamada por policy pega a regressão trazida por uma função **nova** — que é exatamente como
ela voltaria, já que nenhum assert existente cobre código que ainda não foi escrito. Teste
comportamental e varredura de catálogo são complementares aqui, não redundantes.

## Observação de método

O INV-02 achou uma quarta lacuna (`UPDATE papeis.pessoa_id`) que nenhuma das três rodadas de
auditoria tinha nomeado, e ela apareceu **só porque a linha foi gerada pelo produto cartesiano**,
não pensada. É a evidência de que o formato funciona: a matriz encontra o que a imaginação não
enumera.
