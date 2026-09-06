# ADR-0025 — Pipeline de ingestão: estágios, fronteira transacional, idempotência e consumo da fila

> Concretiza o ADR-0007, que escolheu worker Node + fila Postgres e parou aí. Aqui está o desenho
> que falta: quais são os estágios, o que cada um commita, quem enfileira, como o worker toma o
> job, o que acontece com falha, e onde ele roda enquanto não há remoto.

## Contexto

O SPEC §3 lista seis passos de ingestão em prosa. O ADR-0007 escolheu a infraestrutura. Nenhum dos
dois diz o que é uma unidade de trabalho, o que é atômico com o quê, nem o que acontece quando o
terceiro passo falha depois que o segundo já escreveu. Sem isso, "idempotente por `sha256` +
`versao_pipeline`" é uma frase, não uma propriedade.

Três coisas do schema real de F0 restringem o desenho, e duas delas **contradizem decisões já
escritas** — registradas aqui como o ADR-0016 fez, não contornadas em silêncio:

1. `documentos.sha256` é **`not null unique`**. O ADR-0004 decidiu, com razão, que o hash é
   calculado **no worker** ("o cliente pode mentir"). As duas coisas não coexistem: a linha não
   pode nascer sem o hash e o hash só existe depois que o worker leu o arquivo.
2. `job.fila.chave_idempotencia` é **`text unique` total**, sobre toda a história da tabela. Isso
   torna `on conflict do nothing` num **no-op permanente**: depois que um job com a chave
   `ingestao:<sha>:v1` concluiu, reenfileirar a mesma chave não faz nada, **sem erro**. É
   exatamente a falha silenciosa que o item E2 descreve, embutida na trava que deveria protegê-la.
3. `service_role` tem `select, update` em `documentos` (não `insert`), e DML completo em
   `documento_paginas`, `chunks` e `job.fila`. O pipeline foi desenhado para isso: a linha nasce
   humana, a máquina evolui o estado.

## Decisão

### 1. Sete estágios, cada um com uma fronteira transacional própria

Cada estágio é um **tipo de job** em `job.fila.tipo`. Um documento atravessa vários jobs, nunca um
job longo. Nenhuma transação abrange dois estágios.

| # | Estágio (`tipo`) | Lê | Escreve, numa transação | Efeito externo |
|---|---|---|---|---|
| 0 | *(sem job)* **registro** | — | `documentos` (status `pendente`) **+** o job do estágio 1 | — |
| 1 | `hash_dedupe` | objeto no Storage | `documentos.sha256`, `bytes`, `paginas` + job do estágio 2 | leitura do Storage |
| 2 | `extracao_nativa` | objeto | todas as `documento_paginas` do documento (`texto_nativo`, `texto`, `rotacao`, `fonte_texto`) + jobs de OCR das páginas vazias + job do estágio 4 | leitura do Storage |
| 3 | `ocr_pagina` | objeto (1 página) | uma `documento_paginas` (`texto`, `confianca_ocr`, `motor_texto`) | subprocesso de OCR (ADR-0024) |
| 4 | `chunking` | `documento_paginas` | apaga e recria os `chunks` do documento na versão corrente | — |
| 5 | `embedding_lote` | `chunks` | `chunks.embedding` de um lote | API de embedding — **desligada em F1 (ADR-0027)** |
| 6 | `classificacao` | `documento_paginas` | `documentos.metadados` (proposta), status → `em_revisao` | LLM — **desligado em F1 (ADR-0027)** |
| — | *(humano)* **conferência e publicação** | tudo | `documentos.status = 'publicado'`, `visibilidade`, overrides de página | — |

Regras que decorrem, e que não são negociáveis:

- **O enfileiramento do próximo estágio commita junto com a escrita do estágio atual.** A fila está
  no mesmo Postgres: isso é um `insert` na mesma transação, não um outbox. É a maior vantagem
  concreta da escolha do ADR-0007 e ela não estava sendo usada. Consequência: **não existe estado
  "escreveu e não enfileirou"**. Ou os dois, ou nenhum.
- **Nenhum efeito externo dentro da transação.** Ler o Storage e rodar o OCR acontecem **antes** de
  abrir a transação de escrita. Transação longa em banco gerenciado é caminho de bloat (ADR-0007) e
  OCR de 18 páginas segurando um lock é o pior dos dois mundos.
- **Todo efeito externo é função pura da entrada.** Ler o mesmo objeto e rodar o mesmo OCR duas
  vezes produz o mesmo resultado. É isso — e não a chave da fila — que torna a re-execução segura.
- **Estágio 4 apaga antes de inserir**, no mesmo commit, com escopo
  `(documento_id, versao_pipeline)`. A `chunks_uk` já garante a unicidade; o `delete` garante que
  um chunking com menos chunks que o anterior não deixe cauda órfã.

### 2. Idempotência em duas camadas, porque a chave da fila não basta

**Camada de dado (a que importa):** cada estágio é `delete`+`insert` ou `update` sobre uma chave
natural determinística. Rodar duas vezes converge para o mesmo estado. Isto vale mesmo se a fila
inteira for perdida e refeita.

**Camada de fila (só evita trabalho duplicado):** `chave_idempotencia =
'<tipo>:<sha256 hex ou documento_id>:v<versao_pipeline>[:<pagina|lote>]'`, com uma correção
obrigatória no schema:

> A unicidade de `chave_idempotencia` passa a ser **parcial**:
> `create unique index ... on job.fila (chave_idempotencia) where status in ('pendente','processando')`.

O que se quer impedir é **duas execuções simultâneas do mesmo trabalho** e **enfileiramento
duplicado** (a UI e o trigger pedindo a mesma coisa). O que **não** se pode impedir é repetir mais
tarde — "reprocessar tudo deve ser um comando" (SPEC §3) e o reenfileiramento do ADR-0026 dependem
disso. Com a unicidade total, os dois viram no-op silencioso na segunda vez. Migração para o
`eng-supabase`; linhas concluídas permanecem como histórico.

**`versao_pipeline` muda apenas quando muda o texto ou a fronteira dos chunks.** Trocar modelo de
embedding **não** é mudança de `versao_pipeline` (ADR-0027).

### 3. Reprocessamento parcial: um estágio invalida a si e a jusante, nunca a montante

| O que mudou | Reprocessa a partir de | O que **não** é refeito |
|---|---|---|
| Página reclassificada pela curadoria | 4 (chunking) | extração, OCR |
| Editora forçou OCR de uma página | 3 → 4 | extração das outras páginas |
| Chunker corrigido (`versao_pipeline`++) | 4 | extração, OCR |
| Extrator corrigido | 2 | nada (é o topo) |
| Chave de LLM chegou | 5 e 6, seletivos | tudo o mais (ADR-0027) |

O comando de reprocessamento aceita `--estagio` e `--onde`, e enfileira **um job por unidade**, não
um job gigante. Reprocessar o acervo inteiro é 43 jobs, canceláveis, observáveis, retomáveis.

### 4. Consumo da fila

Tomada do job, uma consulta, sem transação longa:

```sql
update job.fila f
   set status = 'processando', iniciado_em = now(), tentativas = tentativas + 1
 where f.id = (
   select id from job.fila
    where status = 'pendente' and disponivel_em <= now()
    order by prioridade, disponivel_em
    for update skip locked
    limit 1)
returning f.*;
```

- **`for update skip locked`, sim** — é o que o ADR-0007 previu e é o mecanismo certo nesta escala.
- **Concorrência 1 em F1.** Uma máquina, e o estágio mais caro (OCR) é limitado por CPU. Paralelismo
  aqui só adiciona modos de falha para ganhar segundos.
- **Retentativa:** `disponivel_em = now() + least(interval '30 seconds' * 2^tentativas,
  interval '1 hour')`, até `max_tentativas` (5, já no schema).
- **Erro permanente não tenta de novo.** PDF com senha, arquivo corrompido, objeto inexistente,
  tamanho acima do limite: vão direto para `morto`. Repetir cinco vezes um PDF corrompido só atrasa
  a única coisa que resolve, que é uma pessoa olhar. Erro **não classificado** conta como
  transitório e tenta de novo — desconhecido costuma ser rede.
- **Lease:** `status = 'processando'` com `iniciado_em` mais velho que 15 minutos volta a
  `pendente`. O varredor roda **no arranque do worker e a cada ciclo de polling**, porque o caso que
  importa é exatamente "o worker morreu e voltou". Também existe como comando SQL no runbook, para
  o caso em que o worker não volta.
- **Dead-letter é `status = 'morto'` na própria tabela**, não uma tabela nova. O estado já está no
  enum e o valor de ter tudo numa consulta SQL supera o de separar.

### 5. Falha de job **precisa** aparecer no documento

O schema `job` está fora do PostgREST: nenhuma tela vê a fila. Então:

> **Todo job que termina em `morto` escreve, na mesma transação, `documentos.status = 'erro'` e
> `documentos.erro_detalhe`.**

Sem isso, o documento fica parado num estado intermediário para sempre e a pessoa que subiu o
arquivo nunca sabe. É a mesma classe de falha do E2, por outro caminho. A UI mostra o documento
com o erro e um botão que reenfileira — pela mesma função de enfileiramento do ADR-0026, nunca por
`insert` direto.

### 6. Onde o worker roda: na máquina da mantenedora, e a UI diz a verdade sobre isso

Não há remoto, não há container, e o estágio de OCR é acoplado ao macOS (ADR-0024). O worker roda
como processo `launchd` na máquina da mantenedora, contra o stack local no desenvolvimento e contra
o banco de produção quando houver produção.

O argumento que sustenta isso não é "não temos infraestrutura", é: **com editora única (D4), quem
sobe documento e quem tem a máquina são a mesma pessoa.** Não existe o cenário "alguém subiu um
arquivo e o processador estava desligado sem ninguém saber" — quem subiu é quem desligou.

Consequência obrigatória: a UI **não finge processamento instantâneo**. Documento recém-enviado
aparece como "na fila" com a informação de que o ingestor precisa estar ativo, e a tela de
sentinela do ADR-0026 mostra a fila parada. Prometer imediatismo e entregar silêncio é o mesmo
defeito de sempre.

**Gatilho para revisitar:** uma segunda pessoa com permissão de subir documento, ou fila parada
com pendências por mais de 48 h em duas ocasiões. A saída já está precificada (container ~R$15/mês,
SPEC §1.2) e não muda o custo recorrente — não é escalada.

### 7. Credencial do worker: `service_role` em F1, com o motivo escrito

O ADR-0007 pediu "credencial própria, não o `service_role` da API". A baseline de F0 concedeu os
`GRANT`s do pipeline **ao `service_role`** (achado V4 do `auditor-rls`), e é esse conjunto que foi
auditado nas quatro rodadas. Criar agora um papel `breeze_worker` significaria duplicar e
re-auditar a matriz de privilégios para separar duas chaves que **ficam na mesma máquina, com a
mesma pessoa**. É separação no papel, não no fato.

Decisão: F1 usa `service_role` por conexão direta (fora do PostgREST). O papel dedicado entra
**no mesmo dia em que o worker sair da máquina da mantenedora** — aí a separação passa a
significar alguma coisa. Fica como linha de dívida com gatilho, não como pendência sem data.

## Consequências

- **`documentos.sha256` passa a ser nullable** (mantendo `unique`; múltiplos `NULL` são permitidos e
  é isso que se quer, várias linhas pendentes sem hash). O hash é escrito pelo estágio 1, e a
  violação de unicidade **é** a detecção de duplicata: o documento vai para `erro` com
  `erro_detalhe` apontando o `documentos.id` original. O par #15/#16 do acervo real (byte-idênticos)
  é o caso de teste que já existe. O hash calculado no browser continua permitido como conveniência
  de UI ("você já enviou este arquivo"), nunca como valor gravado.
- O estágio 0 é a **única** escrita de `insert` em `documentos`, feita por `authenticated` (editora),
  como o schema já impõe. A máquina nunca cria documento — nem no backfill (ADR-0029).
- Depuração é SQL: `select tipo, status, count(*) from job.fila group by 1,2`. Nenhum painel novo.
- **Custo de o estágio 2 escrever todas as páginas de uma vez:** o Manual do Proprietário tem 95
  páginas — uma transação com 95 `insert`s, o que é trivial. Se algum dia houver documento de
  milhares de páginas, o estágio 2 se divide por faixa; não vale complicar agora.
- Três correções de schema saem daqui para o `eng-supabase`: `sha256` nullable, índice único parcial
  de `chave_idempotencia`, índice de busca de job por documento
  (`(tipo, (payload->>'documento_id')) where status in ('pendente','processando')`).

## Alternativas descartadas

- **Um job por documento, com todos os estágios dentro.** Simples até a primeira falha: OCR que
  quebra na página 12 obriga a refazer a extração das 11 anteriores, e a transação (ou o `lease`)
  precisa durar o pipeline inteiro. Também impede reprocessamento parcial, que é o mecanismo de
  que os ADR-0026 e 0027 dependem.
- **Máquina de estados só em `documentos.status`, sem fila.** É o desenho que produz o E2: o estado
  diz o que aconteceu, nunca o que **deve** acontecer. Sem uma linha que representa trabalho
  devido, "reprocessar" não tem onde ser registrado.
- **Manter `chave_idempotencia` única total e bumpar `versao_pipeline` para reprocessar.**
  Transforma toda reindexação pontual numa reindexação global do acervo, e usa a versão do pipeline
  como contador de tentativas — dois conceitos num campo só.
- **Hash no Server Action, para manter `sha256 not null`.** Faz até 50 MiB passarem pela função da
  Vercel, contra o espírito do ADR-0004, e duplica um trabalho que o worker faz de qualquer jeito
  ao ler o arquivo.
- **Retentativa infinita com backoff longo.** Sem teto, um documento quebrado fica escondido para
  sempre atrás de "vai tentar de novo". `morto` + erro visível no documento é a forma de falhar
  alto.
- **`pg_cron` chamando o worker.** Já descartado no ADR-0007; e o varredor de lease dentro do
  próprio worker cobre o caso real (crash e volta) sem nova dependência.

## Status

Aceito, 2026-09-06. Concretiza o ADR-0007. Migrações (nullable `sha256`, índice parcial, índice de
payload, `motor_texto` do ADR-0024): `eng-supabase`. Implementação do worker: F1, cortes C2/C3 de
`docs/f1-plano.md`.
