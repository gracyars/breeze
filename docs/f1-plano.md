# F1 — Acervo: plano de cortes

Ordem de implementação, com o que cada corte entrega de **valor observável para a dona do projeto**.
Derivado dos ADRs 0024–0029. Um corte só começa quando o anterior está de pé — a ordem é por
dependência real, não por preferência.

**Definição de pronto de F1:** os 43 documentos dentro, conferidos e publicados por uma pessoa;
busca léxica ponta a ponta; leitor de documento com citação por página. Embedding e classificação
por LLM **não** fazem parte do pronto (ADR-0027).

---

## C0 — Sonda de OCR local *(meio dia, sem código de produto)*

Rodar Apple Vision sobre as 18 páginas da Convenção registrada, fora do pipeline, e aplicar os
gatilhos G1/G2 do ADR-0024: a sequência de artigos sai sem buraco? Três páginas sorteadas passam na
conferência sem erro que mude sentido?

**Valor:** a resposta "serve / não serve" antes de qualquer código depender dela. Se não servir, o
`juridico-lgpd` começa o contrato de operador agora, e não daqui a dois meses com o pipeline pronto
e a Convenção travada.

**Entrega:** um parágrafo de veredito no ADR-0024, com o resultado medido.

---

## C1 — Autenticação de verdade

Magic link, CPF como alias (D2), enrolamento e verificação de TOTP, `aal2`, códigos de recuperação
impressos (D9), cliente Supabase de servidor, sessão. **Primeiro teste do corte:** olhar o claim
`aal` logo após o enrolamento e antes da primeira verificação — é o que fecha a dívida **D1**.

**Valor:** *"eu entro no sistema com meu e-mail e o segundo fator, e ele sabe que sou a editora."*

**Bloqueia:** tudo. Se o `aal2` sair cedo demais, é achado bloqueante e volta para `arquiteto` +
`auditor-rls` antes de qualquer tela.

---

## C2 — Ingestão ponta a ponta de **um** documento

Upload por signed URL, linha em `documentos`, `job.enfileirar` como único caminho de fila, worker
Node local com `for update skip locked`, lease, backoff e dead-letter (ADR-0025). Estágios 1, 2 e 4:
hash/dedupe, extração nativa, chunking. Sem OCR, sem LLM. `tsv` sai de graça (coluna gerada).

Migrações necessárias antes (`eng-supabase`): `sha256` nullable, índice único **parcial** de
`chave_idempotencia`, índice de job por documento, `motor_texto`, `versao_embedding`.

**Valor:** *"subi o Regimento Interno e ele está no acervo, com 23 páginas e o texto dentro."*

---

## C3 — OCR local no pipeline + conferência de página

Adaptador de OCR como processo filho, estágio 3, `confianca_ocr` e `motor_texto` por página;
disparo automático só em página vazia, proposta à curadoria na faixa duvidosa (ADR-0024 §4).

**Valor:** *"a Convenção passa a ter texto e pode ser citada por artigo"* — o único documento
público do acervo sai do estado de imagem.

---

## C4 — Reindexação garantida (fecha E2)

O trigger invalidador passa a chamar `job.enfileirar` na mesma transação; `documentos.indexado_em`;
view `app.documentos_fora_da_busca`; sentinela no log do worker e no runbook; formulário
`docs/invariantes/INV-13` com matriz de caminhos; testes vermelhos no pgTAP (ADR-0026).

**Valor:** *"reclassifiquei uma página e o documento voltou para a busca sozinho — e existe uma
tela que me diz se algum documento está fora da busca agora."*

**Por que aqui e não depois:** sem este corte, a ata AGE de 36 páginas — o documento que motivou o
modelo de visibilidade inteiro — termina com um buraco silencioso no índice.

---

## C5 — Backfill dos 10 documentos que sustentam o produto + fila de conferência

Script de ingestão em lote (linha criada com sessão da editora, estágios de máquina por
`service_role` — ADR-0029 §2), contra o stack local. Fila de conferência com progresso, ordem por
valor, pré-preenchimento por nome de arquivo, retomável.

Os dez: Regimento, Convenção, 5 atas (AGI + 4 AGE), 3 balancetes. Inclui o override manual das
páginas do Regimento embutido na ata AGE (`motivo_override`, ADR-0028 §5) — e, com ele, o primeiro
exercício real do ciclo invalidar → reenfileirar → rechunkizar do C4.

**Valor:** *"o núcleo normativo e financeiro do condomínio está publicado, conferido por mim."*

---

## C6 — Busca léxica + leitor de documento

`tsvector` `public.pt_br`, RRF com uma lista, facetas, `pg_trgm`, expansão de sinônimos semeada com
o vocabulário deste condomínio (ADR-0027 §5), registro de buscas com zero resultado. Estado vazio
honesto e a linha permanente sobre a busca por significado estar desligada. Leitor com página,
trecho e citação.

**Valor:** *"eu pergunto 'churrasqueira' e chego na página do Regimento que responde."* É aqui que
o trabalho das dez conferências vira produto — e é de propósito que este corte fica entre o décimo
documento e os 33 restantes.

---

## C7 — Os 33 restantes, em lote

24 comunicados e os demais, na tela de lote de 8 por vez, com desmarcação individual (ADR-0029 §3).
Depende da decisão de taxonomia do `guardiao-dominio` sobre "comunicado" como 14º tipo —
**dependência externa, não deste plano.** Se a decisão atrasar, os comunicados esperam e os demais
seguem; nada mais bloqueia.

**Valor:** *"o acervo inteiro está buscável."*

---

## C8 — Anexo replicado: proposta automática e deduplicação na busca

Shingling/Jaccard propondo a faixa replicada, `trechos_replicados`, colapsagem no resultado com
fonte canônica declarada e nota da réplica (ADR-0028). Auditoria de `documento_paginas` (fecha A2).

**Valor:** *"perguntar sobre animais devolve um resultado, no Regimento, e ele me diz que o mesmo
texto também está na ata."*

---

## C9 — Acender embedding e classificação *(fora da definição de pronto de F1)*

Pré-condição: existir chave de LLM e teto mensal de custo definido (SPEC §8.7). Reprocessamento
seletivo, sem tocar em extração nem chunking:
`reprocessar --estagio=embedding --onde="embedding is null"` (ADR-0027 §7).

**Valor:** *"a busca passa a achar por significado, e o painel de 'chunks sem embedding' vai a
zero."*

---

## Dependências que não são deste plano

| O quê | Dono | Impacto se atrasar |
|---|---|---|
| **Quem escreve Next.js e o worker Node** — nenhum agente do time cobre isso hoje | orquestrador | **Bloqueia C1 em diante.** Maior risco do plano. |
| "Comunicado" como 14º tipo documental | `guardiao-dominio` | Atrasa C7; não bloqueia C0–C6. |
| Renomear `restrito`/`conselho` (armadilha de leitura, D13) | `guardiao-dominio` | Nenhum em F1; é enum, exige migração. |
| Projeto Supabase remoto (dívidas D2, D3) | orquestrador + dona | Nenhum: F1 inteiro roda no stack local. |
| Contrato de operador LGPD para OCR | `juridico-lgpd` | Só se C0 reprovar (gatilhos G1/G2 do ADR-0024). |

## Riscos do plano, nomeados

1. **`aal2` emitido cedo pelo GoTrue** (D1). Detectado em C1, e é por isso que C1 é o primeiro corte
   de código. Se ocorrer, replaneja F1.
2. **Busca léxica decepcionar em pergunta normativa.** Mitigado por sinônimos, estado vazio honesto
   e navegação por artigo. Medido pelo registro de buscas com zero resultado — que também é o
   argumento de compra da chave de LLM, com número em vez de suposição.
3. **A conferência travar no meio.** Mitigado pelo sequenciamento (C6 entre o 10º e o 11º), pelo
   lote e pela fila retomável. Se travar mesmo assim, o sintoma aparece como documentos em
   `em_revisao` parados — visível, não silencioso.
4. **Extração nativa entregar sopa de números em balancete** (SPEC §3.2). Descoberto em C5, com
   dado real, antes de F2 depender disso. É um dos motivos de os 3 balancetes estarem entre os dez
   primeiros.
