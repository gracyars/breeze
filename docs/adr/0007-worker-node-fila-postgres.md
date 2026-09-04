# ADR-0007 — Worker Node persistente consumindo fila em Postgres; backfill histórico local

## Contexto

Ingestão de PDF é trabalho pesado e longo: extração, OCR, chunking, embeddings. Não cabe em
função serverless (timeout, binário nativo). Mas o acervo é **finito e conhecido**: centenas de
PDFs históricos, mais 5–20/mês. Dimensionar infraestrutura para o backfill seria pagar o ano
inteiro por um pico de uma semana.

## Decisão

Separar os dois regimes:

- **Backfill histórico:** script rodando **na máquina do mantenedor**, uma vez, contra o banco de
  produção (ou contra staging e depois promovido). Custo de infraestrutura: zero. Pode demorar
  horas; ninguém está esperando.
- **Incremental:** um worker Node persistente (container pequeno, ~R$15/mês no SPEC §1.2)
  consumindo uma fila em tabela Postgres (`job.fila`), com `SELECT ... FOR UPDATE SKIP LOCKED`,
  backoff exponencial e teto de tentativas.

Ambos rodam **o mesmo código de pipeline**, parametrizado — o backfill não é um script paralelo
que diverge. Idempotência por `chave_idempotencia = sha256(documento) || versao_pipeline`
(SPEC §3): reexecutar é seguro, e "reprocessar tudo" é um comando que reenfileira.

A fila fica no schema `job`, **fora do PostgREST**. O worker conecta por string de conexão
direta com credencial própria, não pelo `service_role` da API.

## Consequências

- Zero infraestrutura de fila (SQS, Redis, RabbitMQ) e zero backup adicional: a fila está no
  `pg_dump` (ADR-0002). O estado de processamento é consultável com SQL, o que torna depuração
  trivial.
- `SKIP LOCKED` em tabela não escala para alta vazão. Nesta escala (dezenas de jobs/mês) sobra
  ordem de grandeza. Se um dia doer, a saída é pgmq ou fila externa — decisão adiada de propósito.
- Job travado (worker morto no meio) precisa de recuperação por *lease*: `iniciado_em` +
  timeout devolve o job para `pendente`. Sem isso um crash come o documento em silêncio.
- O worker é um processo que pode cair e ninguém percebe. Precisa de heartbeat e alerta de fila
  parada (item de `devops`), senão o sintoma será "o documento que subi semana passada nunca
  apareceu".
- O backfill rodar na máquina do mantenedor significa credencial de produção fora da nuvem por
  algumas horas. Mitigação: credencial temporária, dedicada, revogada ao fim, e execução contra
  staging primeiro.

## Alternativas descartadas

- **Vercel Functions.** Timeout e ausência de binário nativo confortável para PDF/OCR.
- **Supabase Edge Functions (Deno).** Limites de tempo/memória para OCR e ecossistema de
  bibliotecas de PDF mais pobre em Deno.
- **Fila gerenciada (SQS/Upstash) + worker.** Serviço a mais, backup a mais, custo a mais, para
  um volume que cabe folgado em uma tabela.
- **Worker dimensionado para o backfill.** Pagar o ano por um pico único de uma semana.
- **`pg_cron` + `pg_net` disparando processamento no banco.** OCR e embedding dentro do Postgres
  é uso errado da ferramenta; e transação longa em banco gerenciado é caminho de bloat.

## Status

Aceito. Formaliza ADR-7 da tabela do SPEC §1.1.
