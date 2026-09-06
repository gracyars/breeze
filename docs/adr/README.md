# ADRs — Breeze

Registro de decisões de arquitetura. Uma decisão por arquivo, numerada em sequência, imutável
depois de `Aceito`: decisão superada é marcada `Substituída por ADR-XXXX`, nunca reescrita.

Formato fixo: **Contexto / Decisão / Consequências / Alternativas descartadas / Status**.

| # | Título | Status |
|---|---|---|
| [0001](0001-nextjs-vercel.md) | Next.js App Router + TypeScript na Vercel | Aceito |
| [0002](0002-supabase-postgres-datastore-unico.md) | Supabase Postgres como datastore único | Aceito |
| [0003](0003-auth-magic-link-cpf-alias-totp.md) | Auth: magic link, CPF como alias, TOTP/AAL2 | Aceito |
| [0004](0004-storage-buckets-privados-signed-url.md) | Storage privado com signed URL de TTL curto | Aceito |
| [0005](0005-busca-hibrida-rrf.md) | Busca híbrida `tsvector` PT-BR + pgvector com RRF | Aceito |
| [0006](0006-extracao-nativa-ocr-condicional.md) | Extração nativa primeiro, OCR condicional | Aceito — item 3 **substituído pelo 0024** |
| [0007](0007-worker-node-fila-postgres.md) | Worker Node persistente com fila em Postgres | Aceito |
| [0008](0008-migracao-versionada-baseline.md) | Migração versionada, baseline única, dashboard proibido | Aceito |
| [0009](0009-politica-de-ambientes.md) | Política de ambientes e de dados por ambiente | Aceito |
| [0010](0010-valor-monetario-bigint-centavos.md) | Valor monetário em `bigint` de centavos | Aceito |
| [0011](0011-lancamentos-imutaveis-estorno.md) | Lançamentos imutáveis; correção por estorno assinado | Aceito |
| [0012](0012-rls-fronteira-unica-de-autorizacao.md) | RLS como fronteira única de autorização | Aceito |
| [0013](0013-audit-schema-isolado-hash-encadeado.md) | Trilha em schema `audit` isolado, com hash encadeado | Aceito |
| [0014](0014-cpf-hmac-lookup-cifra-na-aplicacao.md) | CPF: HMAC para lookup, cifra reversível na aplicação | Aceito |
| [0015](0015-enum-nativo-vs-tabela-de-dominio.md) | Enum nativo vs. tabela de domínio | Aceito |
| [0016](0016-correcoes-propostas-ao-spec-secao-2.md) | Correções ao SPEC §2 e §2.1 | Aceito (itens 1–10) |
| [0017](0017-privilegio-de-coluna-grant-explicito.md) | Privilégio de coluna: `GRANT` explícito, nunca `REVOKE` de coluna | Aceito — corrige o mecanismo de 0012 §7 e 0014 §4 |
| [0018](0018-visibilidade-por-pagina-documento-misto.md) | Visibilidade por página em documento de conteúdo misto | Aceito — adendo ao 0012, **emendado pelo 0019** |
| [0019](0019-visibilidade-do-arquivo-e-o-piso-do-documento.md) | Visibilidade do documento é o **piso**; override de página só amplia | Aceito — **emenda o 0018**; fecha V1 e V3 |
| [0020](0020-snapshot-de-assinatura-em-parecer.md) | Snapshot do signatário em `parecer_signatarios`, e **o critério de 3 testes** para denormalizar PII | Aceito |
| [0021](0021-invariante-de-dois-lados.md) | **Invariante de dois lados, guarda de um lado só** — matriz de caminhos de violação e hierarquia de soluções | Aceito — fecha V1-R, V3-R, V5-R |
| [0022](0022-ultimo-editor-nao-desativavel.md) | O último `editor` vigente não pode ser desativado | Aceito — fecha V10 |

| [0023](0023-predicado-de-autorizacao-local.md) | **Predicado de autorização deve ser local** — não pode depender de linhas que não são a avaliada | Aceito — estende o 0021; corrige 0018/0019 |

### F1 — Acervo

| # | Título | Status |
|---|---|---|
| [0024](0024-ocr-local-offline-e-o-gatilho-da-api-paga.md) | **OCR local offline** (Apple Vision); API paga só por gatilho nomeado | Aceito — **substitui parcialmente o 0006** (item 3) |
| [0025](0025-pipeline-de-ingestao-estagios-e-fila.md) | Pipeline de ingestão: sete estágios, fronteira transacional, idempotência, consumo da fila | Aceito — concretiza o 0007; corrige `sha256 not null` e a unicidade de `chave_idempotencia` |
| [0026](0026-invalidar-e-enfileirar-na-mesma-transacao.md) | **Quem invalida, enfileira** — reprocessamento é obrigação do banco | Aceito — **fecha a dívida E2** |
| [0027](0027-busca-lexica-primeiro-etapas-de-llm-desligadas.md) | Busca léxica em F1; embedding e classificação atrás de porta, **desligados e declarados** | Aceito — corrige o registro de dimensão do 0005 |
| [0028](0028-anexo-replicado-fonte-canonica-e-dedupe-na-busca.md) | Anexo replicado: curadoria declara, busca deduplica, **norma é citada pelo documento normativo** | Aceito — adendo ao 0018/0019; fecha A2 |
| [0029](0029-auth-antes-do-backfill-e-o-desenho-da-conferencia.md) | **Auth é o primeiro corte de F1**; backfill é máquina para ingerir, humano para publicar | Aceito — propõe correção ao SPEC §9; fecha D1 |

**Antes de escrever trigger de invariante entre duas tabelas:** ADR-0021 — e preencha o formulário
em [`../invariantes/`](../invariantes/README.md), que é o artefato com gate de CI.
**Antes de escrever função chamada por policy:** ADR-0023. `exists`/`count`/`min` sobre outras
linhas é sinal de alerta.
**Antes de denormalizar qualquer dado pessoal:** ADR-0020.
**Antes de apagar dado derivado (chunk, embedding, índice):** ADR-0026 — quem invalida, enfileira,
na mesma transação. `DELETE` que aposta em reprocessamento futuro é falha silenciosa.
**Antes de escrever qualquer etapa de pipeline:** ADR-0025 (fronteira transacional e idempotência)
e ADR-0027 (etapa desligada nunca produz valor falso).

Desenho de schema derivado destes ADRs: [`../schema.md`](../schema.md).
Sequência de implementação de F1: [`../f1-plano.md`](../f1-plano.md).
