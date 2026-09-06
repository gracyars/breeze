# INV-13 — Derivado invalidado implica reconstrução enfileirada

> Fecha a dívida **E2** (`docs/ops/divida-tecnica.md`): *"documento pode sumir da busca em
> silêncio"*. Especificada em `docs/adr/0026-invalidar-e-enfileirar-na-mesma-transacao.md`.
> Implementada em `supabase/migrations/20260906140000_reprocessamento_enfileirado_e_sentinela.sql`.
> Testada em `supabase/tests/09_reprocessamento_enfileirado_sentinela.sql`.

| Campo | Valor |
|---|---|
| **Enunciado formal** | Se `documentos.status = 'publicado'` e `documentos.indexado_em is null`, então existe uma linha em `job.fila` com `tipo = 'chunking'`, `status in ('pendente','processando')` e `payload ->> 'documento_id' = documentos.id::text` — **ou** o documento aparece em `app.documentos_fora_da_busca` (a sentinela é a rede que pega o caso em que a primeira metade falhou: job morreu, worker nunca rodou, ou ninguém enfileirou). |
| **Onde é usada** | Trigger `chunks_marca_indexado` (`AFTER INSERT` em `chunks`), trigger `chunks_invalida_documento` (`AFTER DELETE` em `chunks`), trigger `documentos_versao_pipeline_invalida_indexacao` (`BEFORE UPDATE OF versao_pipeline` em `documentos`), trigger `documento_paginas_invalida_chunks_afetados` (estendida nesta migração para `DELETE`) — e a view `app.documentos_fora_da_busca`, que é o lado de leitura da invariante. |
| **ADR de origem** | `docs/adr/0026-invalidar-e-enfileirar-na-mesma-transacao.md` (concretiza `docs/adr/0025-pipeline-de-ingestao-estagios-e-fila.md` §2, unicidade parcial de `chave_idempotencia`) |
| **Migração** | `supabase/migrations/20260906140000_reprocessamento_enfileirado_e_sentinela.sql` |
| **Dono** | `eng-supabase` (implementação) · `auditor-rls` (testes) |

## 1. Conjunto de dependência

| Tabela.coluna | Espécie (ADR-0023) | Justificativa da espécie |
|---|---|---|
| `documentos.status` | constitutiva | é a condição "publicado" do enunciado — sem ela o antecedente nunca é verdadeiro |
| `documentos.indexado_em` | constitutiva | é o próprio sinal que o enunciado testa — a coluna que este corte introduz |
| `documentos.versao_pipeline` | constitutiva | define qual é o "índice corrente" — um chunk de versão velha não pode confirmar o índice, e mudar esta coluna é, por si só, um caminho de invalidação (bloco D/H do teste) |
| `chunks.documento_id` | constitutiva | a existência (ou ausência) de chunk é o fato que o mecanismo observa para atualizar `indexado_em` |
| `chunks.versao_pipeline` | constitutiva | só um chunk da versão corrente confirma o índice (guarda em `chunks_marca_indexado`/`chunks_invalida_documento`) |
| `documento_paginas.documento_id` | constitutiva | liga a página ao documento cujo índice pode ficar desatualizado |
| `documento_paginas.pagina` | constitutiva | identifica qual chunk intersecta — delimita o efeito de uma reclassificação |
| `documento_paginas.visibilidade` | constitutiva | reclassificação de página é o gatilho mais comum de invalidação (o caso da ata AGE 04.02.2026, D11, que motivou o modelo inteiro) |
| `job.fila.tipo` | constitutiva | só job `'chunking'` conta como "reconstrução a caminho" para este documento |
| `job.fila.status` | constitutiva | só `pendente`/`processando` conta como "alguém encarregado" |
| `job.fila.payload` (chave `documento_id`) | constitutiva | liga o job ao documento — sem isso a sentinela não sabe filtrar por documento |

Nenhuma dependência **modal**: cada coluna acima **é** parte da decisão ("o índice está em dia?"),
nenhuma delas só influencia *como* uma decisão já tomada se aplica. Isso é esperado — INV-13, como
INV-02, é uma invariante sobre um **fato distribuído em várias tabelas** (o estado do índice), não
sobre uma linha só; ADR-0023 nível 1 (derivada) não se aplica aqui pela mesma razão que não se
aplica a "existe editor vigente": não há uma fonte única de onde derivar isto sem contagem/leitura
de outra tabela.

## 2. Matriz de caminhos de violação

| # | Caminho | Estado | Teste vermelho |
|---|---|---|---|
| 1 | `INSERT` em `documentos` (nasce `publicado` direto, ex.: backfill/migração escrevendo `status='publicado'` sem nunca ter passado por `chunking`) | `IMPOSSÍVEL(indexado_em nasce NULL por padrão — não há como este caminho escapar da sentinela; app.documentos_fora_da_busca não distingue "nunca indexado" de "invalidado depois", mostra os dois igual)` | `09_...sql::T07` (pré-condição: documento nasce indexado — a suíte não cria um doc publicado-sem-índice porque o caso é coberto por construção, não por guarda ativa) |
| 2 | `UPDATE` de `documentos.status` (→ `'publicado'`, publicação humana) | `IMPOSSÍVEL(mesmo argumento da linha 1 — se indexado_em já era null antes da publicação, a sentinela mostra a partir do instante em que status vira 'publicado'; se já estava preenchido, esta UPDATE não o toca)` | coberto pelo desenho da view (`WHERE status='publicado' AND indexado_em is null`), sem teste dedicado — é ausência de guarda por não haver nada a guardar |
| 3 | `UPDATE` de `documentos.indexado_em` (escrita direta, fora dos triggers desta migração) | `ACEITO(só authenticated com app.eh_editor() ou service_role têm GRANT de UPDATE em documentos/têm acesso à tabela; um editor mal-intencionado ou um bug de aplicação PODE escrever indexado_em=now() sem chunk nenhum, mentindo para a sentinela — mesma classe de risco já aceita para "editora publica o que quiser", D4/A1 de docs/ops/divida-tecnica.md. Efeito do dano é só a SENTINELA (nunca autorização, ver bloco G do teste) e o ator é o mesmo papel único e confiável que já pode publicar qualquer coisa)` | não há teste vermelho de bloqueio (não é bloqueada de propósito); `09_...sql::T30-T31` prova o limite do dano — mesmo com indexado_em adulterado, autorização não é afetada |
| 4 | `UPDATE` de `documentos.versao_pipeline` | `GUARDADO(documentos_versao_pipeline_invalida_indexacao — zera indexado_em e enfileira chunking:<id>:v<nova versão> na MESMA transação, BEFORE UPDATE)` | `09_...sql::T18-T21` (bloco D) |
| 5 | `DELETE` em `documentos` | `IMPOSSÍVEL(nenhuma policy permite DELETE em documentos — "arquivar por status, não apagar", docs/schema.md §6.2; e cascade em chunks/documento_paginas não teria documento para aparecer na sentinela nem job para apontar)` | `04_privilegios_grants_e_superficie.sql` (cobertura geral de ausência de policy DELETE em `documentos`) |
| 6 | `INSERT` em `chunks` | `GUARDADO(chunks_marca_indexado — AFTER INSERT seta indexado_em=now(), só se o chunk inserido for da versao_pipeline CORRENTE do documento)` | `09_...sql::T23` (bloco E) e `T34` (bloco H — insere na versão certa e confirma) |
| 7 | `UPDATE` de `chunks.documento_id` | `ACEITO(mover um chunk para outro documento_id é uma operação que não existe em código nenhum — nem o worker faz isso, ele sempre delete+insert; se acontecesse, chunks_valida_visibilidade_uniforme e chunks_uk provavelmente rejeitariam primeiro por violarem outras invariantes antes desta)` | sem teste dedicado — caminho sem uso real, coberto indiretamente pelas travas de `chunks_valida_visibilidade_uniforme`/`chunks_uk` |
| 8 | `UPDATE` de `chunks.versao_pipeline` | `ACEITO(mesma justificativa da linha 7 — não é uma operação que o pipeline realiza; um chunk muda de versão só por DELETE+INSERT)` | sem teste dedicado |
| 9 | `DELETE` em `chunks` | `GUARDADO(chunks_invalida_documento — AFTER DELETE zera indexado_em e enfileira chunking:<id>:v<versão corrente>, só se o chunk apagado era da versão CORRENTE do documento; on conflict do nothing evita duplicar quando é a própria reconstrução do worker no meio de uma transação)` | `09_...sql::T15-T17` (bloco C, "apagar chunk à mão" — célula que o próprio ADR-0026 §6 já previa como `ACEITO` e que ganhou sinal ativo aqui) |
| 10 | `INSERT` em `documento_paginas` | `GUARDADO(documento_paginas_invalida_chunks_afetados dispara também em INSERT — herdado da baseline 08; uma página nova com override pode tornar um chunk pré-existente não-uniforme)` | `01_visibilidade_documento_pagina_chunk_rls.sql` (V1-R original); não duplicado em `09` |
| 11 | `UPDATE` de `documento_paginas.documento_id` | `IMPOSSÍVEL(não há UPDATE de FK em código nenhum; documento_paginas_uk e o cascade de documentos tornam isso uma operação que nada no pipeline realiza)` | sem teste dedicado |
| 12 | `UPDATE` de `documento_paginas.pagina` | `ACEITO(renumerar uma página é operação que não existe no pipeline atual — o worker sempre escreve por número de página fixo; se acontecesse, o trigger de invalidação dispara só por mudança de `visibilidade`, não de `pagina` — GAP real, mas sem caminho de escrita que o exercite hoje)` | sem teste dedicado — registrado como gap latente, não there é vetor de escrita conhecido |
| 13 | `UPDATE` de `documento_paginas.visibilidade` (reclassificação) | `GUARDADO(documento_paginas_invalida_chunks_afetados apaga o chunk não-uniforme; chunks_invalida_documento, disparada pelo DELETE resultante, zera indexado_em e enfileira)` | `09_...sql::T09-T11` (bloco A) |
| 14 | `DELETE` em `documento_paginas` | `GUARDADO(documento_paginas_invalida_chunks_afetados agora também dispara em DELETE — extensão desta migração; a baseline 08 só cobria INSERT/UPDATE OF visibilidade, then apagar a página que carregava um override não invalidava nada)` | `09_...sql::T12-T14` (bloco B) — o caminho que a baseline 08 não cobria |
| 15 | `INSERT` em `job.fila` | `IMPOSSÍVEL(schema job fora do PostgREST, sem GRANT a authenticated/anon; o único caminho é job.enfileirar(), que sempre grava tipo/payload/chave corretos — 07_job_enfileirar_idempotencia_parcial.sql já prova que insert direto é negado)` | `07_job_enfileirar_idempotencia_parcial.sql::T23-T24` |
| 16 | `UPDATE` de `job.fila.tipo` | `IMPOSSÍVEL(nenhum código de aplicação ou trigger atualiza o tipo de um job depois de criado; o worker só lê tipo para rotear, nunca escreve)` | sem teste dedicado |
| 17 | `UPDATE` de `job.fila.status` | `ACEITO(é o próprio worker, via service_role, quem faz as transições pendente→processando→concluido/morto — é o mecanismo funcionando, não uma violação; forçar 'concluido' à mão sem trabalho real é a mesma classe de risco da linha 3, mesmo ator confiável)` | `09_...sql::T22, T25-T26` (bloco E exercita as transições reais) |
| 18 | `UPDATE` de `job.fila.payload` | `ACEITO(só service_role tem GRANT na tabela; alterar payload->>'documento_id' desviaria o job para outro documento — mas isso só FAZ O DOCUMENTO ORIGINAL aparecer na sentinela mais cedo, nunca o esconde por mais tempo do que já estaria; a direção do erro é sempre "mais visível", nunca "mais escondido")` | sem teste dedicado — a via de exploração não piora o pior caso (documento aparece na sentinela) |
| 19 | `DELETE` em `job.fila` | `IMPOSSÍVEL(a sentinela é computada pelo ESTADO atual — documentos.indexado_em e a existência de linha pendente/processando — não por histórico; apagar uma linha concluída/morta não muda nenhuma das duas coisas, e apagar uma linha pendente só faz o documento aparecer na sentinela mais cedo, nunca some com o sinal)` | `09_...sql` (não exercitado à parte — decorre do desenho da view, que nunca lê linhas fora de `pendente`/`processando`) |
| F1 | Escrita por `service_role` / worker | `ACEITO — duas células, ambas já detalhadas: DELETE direto em chunks (linha 9, célula ACEITO/GUARDADO do próprio ADR-0026 §6) e UPDATE de job.fila.status/payload (linhas 17-18). O worker É o mecanismo — não há "bypass" aqui, é o próprio caminho legítimo` | `09_...sql::T15-T17, T22-T26` |
| F2 | **Concorrência** — duas transações simultâneas | `GUARDADO(fila_chave_idempotencia_ativa_uk, índice único parcial do ADR-0025 §2, impede duas linhas pendente/processando com a mesma chave — duas reclassificações simultâneas do mesmo documento geram UM job, não dois)` + `ACEITO(múltiplos workers concorrentes são explicitamente fora de escopo em F1 — ADR-0025 §4, "Concorrência 1")` | `07_job_enfileirar_idempotencia_parcial.sql::T03-T04` (a trava é a mesma, testada lá) |
| F3 | Restore, migração, backfill | `GUARDADO(job.fila é restaurada junto com documentos no mesmo pg_dump, ADR-0007; job 'processando' no instante do dump volta com lease vencida, e o varredor de lease do ADR-0025 §4 devolve a 'pendente' — a sentinela nunca fica "presa" mostrando indefinidamente um job fantasma)` | sem teste pgTAP (é comportamento de operação, não de transação única) — runbook cobre smoke pós-restore |
| F4 | Propriedade assumida por leitor (contiguidade, ordenação, unicidade) | `GUARDADO(job.enfileirar() SEMPRE mescla 'documento_id' no payload — nenhum job legítimo nasce sem essa chave, então a expressão (payload ->> 'documento_id') que a view e o índice fila_documento_idx usam nunca depende de um chamador lembrar de incluir o campo)` | `07_job_enfileirar_idempotencia_parcial.sql::T14` |

## 3. Nível da solução (ADR-0021)

- [x] **3 — invalidação/reprocessamento** (bloquear a reclassificação de página quebraria o fluxo
  de curadoria que motiva o modelo inteiro de visibilidade por página — SPEC §3, o caso da ata AGE
  04.02.2026 embutindo o Regimento, D11)

**Por que não o nível 2 (validar dos dois lados, sem invalidar):** não há como *validar* que um
chunk continua correspondendo a um texto/visibilidade que mudou — o chunk É o derivado; a única
correção possível é apagá-lo e pedir reconstrução. Isso é herdado do V1-R (baseline 08) e não muda
aqui: o que este corte adiciona é garantir que "pedir reconstrução" deixe de ser aposta.

**Por que não o nível 1 (derivar):** `indexado_em` já É a tentativa de eliminar a necessidade de
agregação (`exists chunk`) — mas o próprio ADR-0026 é explícito que persistir esse booleano como
coluna, e não recalculá-lo por consulta a cada leitura, é a escolha certa para não pagar `exists`
sobre a tabela mais lida do schema (`chunks`) em toda leitura de `documentos`. A sentinela, que
PRECISA agregar, existe separada — de leitura pouco frequente, gestão-only — exatamente para não
forçar essa agregação no caminho quente.

## 4. O que fica aceito, e por quê

**Linha 3 — `UPDATE` direto de `documentos.indexado_em`.** Não há guarda ativa contra um editor (ou
um bug de código de aplicação futuro) escrever `indexado_em = now()` sem chunk nenhum por trás.
Aceito pelo mesmo argumento já registrado em `docs/ops/divida-tecnica.md` item A1 para
`deliberacoes.trecho_literal`: o ator com esse poder é o mesmo papel único e confiável que já pode
publicar qualquer conteúdo (D4) — não é uma escalada de privilégio, é o MESMO privilégio aplicado a
mais uma coluna. O dano tem teto baixo e conhecido: `indexado_em` **nunca** participa de
autorização (bloco G do teste, `T30-T31`), então o pior caso é a sentinela ficar cega para um
documento genuinamente desatualizado — não um vazamento de conteúdo. Se um dia isto doer (edição
maliciosa por um papel que deixa de ser único, D4 revisado), a correção é um trigger que só aceita
a escrita vinda de dentro das três funções desta migração (via GUC de sessão), não antes.

**Linhas 7, 8, 11, 12 — `UPDATE` de colunas que nenhum código escreve hoje.** `chunks.documento_id`,
`chunks.versao_pipeline`, `documento_paginas.documento_id`, `documento_paginas.pagina`. Nenhum
caminho do pipeline (worker, curadoria, backfill) executa esses UPDATEs — o padrão é sempre
`DELETE`+`INSERT`. Aceito como ausência de vetor de escrita, não como guarda deliberada; registrado
para não reaparecer como "esquecido" numa auditoria futura. A linha 12 em particular
(`documento_paginas.pagina`) é um **gap latente genuíno**: se algum dia existir um caminho que
renumera páginas, o trigger de invalidação (que só escuta `visibilidade`) não dispara. Não fechado
agora porque fechar uma trigger para um caminho de escrita que não existe é complexidade sem teste
vermelho possível (não há como provar que uma guarda funciona contra uma escrita que nada faz).

**Linhas 17, 18 — `UPDATE` de `job.fila.status`/`payload` por `service_role`.** É o próprio worker
operando — não é bypass, é o mecanismo. Documentado aqui porque a matriz obriga a linha a existir;
a resposta correta não é bloquear (bloquearia o worker de fazer seu trabalho), é observar que o
pior caso de um uso indevido dessa escrita (forjar conclusão sem trabalho, ou desviar o
`documento_id` do payload) sempre empurra o sistema na direção de **mais visível** na sentinela,
nunca de mais escondido — a mesma garantia que sustenta a linha 18.

**F1/F3 — já detalhados nas células correspondentes.** F1 são as mesmas duas células (9 e 17/18)
vistas pelo ângulo "é o worker fazendo isso", sem conteúdo novo. F3 depende do varredor de lease do
ADR-0025 §4, que é infraestrutura já auditada, não uma trava nova desta migração.
