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
| [0006](0006-extracao-nativa-ocr-condicional.md) | Extração nativa primeiro, OCR condicional | Aceito |
| [0007](0007-worker-node-fila-postgres.md) | Worker Node persistente com fila em Postgres | Aceito |
| [0008](0008-migracao-versionada-baseline.md) | Migração versionada, baseline única, dashboard proibido | Aceito |
| [0009](0009-politica-de-ambientes.md) | Política de ambientes e de dados por ambiente | Aceito |
| [0010](0010-valor-monetario-bigint-centavos.md) | Valor monetário em `bigint` de centavos | Aceito |
| [0011](0011-lancamentos-imutaveis-estorno.md) | Lançamentos imutáveis; correção por estorno assinado | Aceito |
| [0012](0012-rls-fronteira-unica-de-autorizacao.md) | RLS como fronteira única de autorização | Aceito |
| [0013](0013-audit-schema-isolado-hash-encadeado.md) | Trilha em schema `audit` isolado, com hash encadeado | Aceito |
| [0014](0014-cpf-hmac-lookup-cifra-na-aplicacao.md) | CPF: HMAC para lookup, cifra reversível na aplicação | Aceito |
| [0015](0015-enum-nativo-vs-tabela-de-dominio.md) | Enum nativo vs. tabela de domínio | Aceito |
| [0016](0016-correcoes-propostas-ao-spec-secao-2.md) | Correções propostas ao SPEC §2 | **Proposto — decisão do orquestrador** |

Desenho de schema derivado destes ADRs: [`../schema.md`](../schema.md).
