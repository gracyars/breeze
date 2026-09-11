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
| `pnpm test:a11y` | Acessibilidade (Playwright + axe) sobre `/design-system` |
| `pnpm test:e2e` | Ponta a ponta: entrada, segundo fator e ingestão — **exige `supabase start`** |
| `pnpm worker` | Worker de ingestão, em laço. `pnpm worker:uma-vez` drena a fila e sai |
| `pnpm backfill "<arquivo\|pasta>" [--todos]` | Sobe documento do acervo e enfileira a leitura; tipo, data e título saem do nome do arquivo. **Pede o código do seu autenticador** |
| `pnpm dev:semeia-editora` | Cria a editora no ambiente local (só contra o Supabase local) |
| `pnpm probe:aal2` | Sonda D1: confirma que o Auth só emite `aal2` depois do segundo fator |

## Estrutura

```
app/              Rotas (App Router)
components/       Componentes de UI (components/ui = primitivos do design system)
lib/              Código compartilhado sem UI (lib/supabase = clientes e tipos gerados)
supabase/         Projeto Supabase local — migrations, testes pgTAP (supabase/tests)
scripts/          Scripts operacionais — backup, OCR local, worker, backfill, sondas
tests/unit/       Testes Vitest
tests/a11y/       Acessibilidade (Playwright + axe), sem banco
tests/e2e/        Fluxos completos contra o Supabase local (entrada, MFA, ingestão)
docs/             Spec, decisões, e docs/ops (runbook, backup)
.github/workflows Pipeline de CI e backup agendado
```

## Ingestão do acervo (F1)

O pipeline tem sete estágios e uma fila no próprio Postgres (`job.fila`, ADR-0025). O caminho de
um documento:

```bash
supabase start
pnpm dev:semeia-editora              # uma vez, no ambiente local
# entre em /entrar, pegue o link em http://127.0.0.1:54324 e cadastre o 2º fator em /seguranca

pnpm backfill "Documentos do Condomínio" --todos   # 43 PDFs, tipo e data vindos do nome
pnpm worker                                        # hash/dedupe → extração → OCR se precisar → chunking
```

**Por que o backfill pede o código do autenticador:** `service_role` não tem `INSERT` em
`documentos` (decisão de F0). Quem cria documento é uma pessoa com papel `editor`, e `editor` só é
reconhecido com `aal2`. Uma máquina que publicasse sozinha no acervo seria exatamente o que o
desenho evita.

**O OCR roda na própria máquina** (`scripts/ocr/vision_ocr.swift`, Apple Vision): nada sai daqui,
custo zero, nenhum fornecedor a contratar como operador de dado pessoal. Medição e limites em
`docs/ocr/medicao-vision-convencao.md`; a decisão em `docs/adr/0024-…`.

**Nada é publicado automaticamente.** O pipeline termina em `em_revisao`; publicar é ato humano
(SPEC §3.5). A fila de conferência fica em `/curadoria`: um documento por vez, ordenado por valor
entregue, com o começo do texto lido ao lado para conferir — e é retomável, porque parar no meio é
o comportamento esperado de quem confere 43 documentos sozinha.

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
verdade se qualquer um não foi `success`. **`ci-gate` — e só ele — é o
"required status check"** da branch protection de `main`, ligada em 2026-09-11 junto com a
publicação do repositório (`strict`, sem force push, sem apagar a branch).

**O que a trava não faz, de propósito:** `enforce_admins` está desligado. Ela barra merge de PR
com CI vermelho, mas a administradora ainda consegue fazer push direto em `main` — que é o fluxo
de trabalho de hoje, com uma pessoa só. Ligar `enforce_admins` obriga toda mudança a passar por PR
com `ci-gate` verde; é decisão de fluxo, não de configuração, e o gatilho natural é a chegada de
uma segunda pessoa com escrita no repositório.

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
