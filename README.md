# Breeze

Sistema de transparência e fiscalização do condomínio Breeze Bosque da Saúde. Ver
`docs/01-SPEC.md` (spec técnica e funcional) e `docs/04-DECISOES.md` (decisões travadas) antes
de qualquer mudança — toda implementação deve citar a seção da spec que a justifica.

Stack: Next.js (App Router) + TypeScript + Tailwind, Supabase (Postgres + Auth + Storage),
deploy na Vercel. `pnpm` como gerenciador de pacotes.

## Setup local

```bash
corepack enable        # ou: npm install -g pnpm
pnpm install

cp .env.example .env.local   # preencher com credenciais locais — nunca commitar .env.local

supabase start          # sobe Postgres local + Auth + Storage (requer Docker)
pnpm dev                 # http://localhost:3000
```

## Scripts

| Comando | O que faz |
|---|---|
| `pnpm dev` | Servidor de desenvolvimento |
| `pnpm build` | Build de produção |
| `pnpm lint` | ESLint |
| `pnpm typecheck` | `next typegen` + `tsc --noEmit` |
| `pnpm test` | Testes unitários (Vitest) |
| `pnpm test:watch` | Vitest em modo watch |
| `pnpm db:types` | Gera `lib/supabase/database.types.ts` a partir do schema local |

## Estrutura

```
app/              Rotas (App Router)
components/       Componentes de UI (components/ui = primitivos do design system)
lib/              Código compartilhado sem UI (lib/supabase = clientes e tipos gerados)
supabase/         Projeto Supabase local — migrations, testes pgTAP (supabase/tests)
scripts/          Scripts operacionais (backup.sh) — não é código de aplicação
tests/unit/       Testes Vitest
docs/             Spec, decisões, e docs/ops (runbook, backup)
.github/workflows Pipeline de CI e backup agendado
```

## Ambientes (SPEC §1.2)

Local (`supabase start`) → staging (Supabase free + preview Vercel) → produção (Supabase Pro).
Schema **nunca** é editado pelo dashboard — só migração versionada em `supabase/migrations`,
aplicada via `supabase db push` no CI. Tipos TS gerados no CI.

## CI/CD

`.github/workflows/ci.yml` roda, nesta ordem, em todo PR e push em `main`: lint → typecheck →
testes unitários (Vitest) → testes de a11y (Playwright + axe) → testes de RLS (pgTAP,
`supabase/tests/`, aprovados na auditoria de F0 — `docs/auditoria/veredito-f0.md`) →
`supabase db push` (só em `main`, e só se tudo acima passar). Nenhum deploy passa com qualquer
etapa vermelha.

**Gate de merge.** Os cinco primeiros jobs formam uma cadeia via `needs`; se um falhar, os
seguintes ficam `skipped` — e o GitHub trata `skipped` como requisito satisfeito em branch
protection por padrão, o que abriria um jeito de mergear com CI quebrado. Por isso existe o job
`ci-gate`: roda sempre (`if: always()`), inspeciona o resultado de cada job da cadeia e falha de
verdade se qualquer um não foi `success`. **É `ci-gate` — e só ele — que deve ser marcado como
"required status check"** quando este repositório ganhar um remoto no GitHub (branch protection
de `main`). Pendência registrada em `docs/ops/divida-tecnica.md`; enquanto não houver remoto,
não há como configurar branch protection de verdade — o gate roda e falha corretamente hoje, mas
"barrar o merge" no sentido do GitHub só existe depois desse passo manual.

`.github/workflows/backup.yml` roda `scripts/backup.sh` semanalmente — ver
`docs/ops/backup.md` e `docs/ops/runbook-restauracao.md`.

## Dívida técnica

`docs/ops/divida-tecnica.md` rastreia os itens que a auditoria de RLS de F0 deixou "fora de
cobertura" ou como observação com dono, um por agente responsável, para não evaporarem depois
que a fase fechar.

## Custo

Orçamento recorrente de referência ~R$300/mês (Vercel, Supabase, worker, LLM, backup). Teto de
custo de LLM configurável via `LLM_MONTHLY_BUDGET_CENTS` (`.env.example`) — ver
`docs/ops/backup.md` §5.
