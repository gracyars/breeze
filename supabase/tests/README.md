# supabase/tests/

Suíte pgTAP de RLS, escrita e mantida pelo `auditor-rls`:

- `01_visibilidade_documento_pagina_chunk_rls.sql`
- `02_papeis_aal_mandato_pessoas_cobrancas_rls.sql`
- `03_lancamentos_audit_imutabilidade.sql`
- `04_privilegios_grants_e_superficie.sql`
- `05_trilha_pii_anonimizacao.sql`
- `06_taxonomia_f1_restricao_unidade.sql`
- `07_job_enfileirar_idempotencia_parcial.sql`
- `08_returning_predicado_local.sql`

O workflow de CI (`.github/workflows/ci.yml`, job `rls-test`) instala `pg_prove`, sobe o
Supabase local (`supabase start`, que aplica todas as migrações de `supabase/migrations`) e
roda `supabase test db --local supabase/tests` antes de qualquer `supabase db push`. **O job
falha se qualquer assert falhar — sem condicional de "pula se não tiver teste", sem mascarar.**
Nenhum deploy passa com teste vermelho aqui.

**Extensão `pgtap`:** habilitada por
`supabase/migrations/20260904122300_pgtap_test_only.sql`, em migração própria e nomeada com o
sufixo `_test_only.sql` de propósito — pgTAP é ferramenta de teste, não pertence a um banco de
produção. O job `db-push` do CI filtra automaticamente qualquer migração `*_test_only.sql`
antes de tocar staging/produção (ver comentário no próprio workflow). Local e CI aplicam o
arquivo normalmente via `supabase start`; produção nunca vê essa migração.

**`08_returning_predicado_local.sql` — a forma do comando faz parte da superfície de
autorização.** Até 2026-09-06 a suíte inteira exercitava `insert`/`update` **sem `returning`**, e
por isso 234 asserts verdes conviveram com `insert into documentos ... returning id` dando `42501`
para todo mundo, editora com `aal2` inclusive (commit `8e126fe`). Sem `returning`, a policy de
SELECT nem entra no plano — o defeito era invisível por construção, não por descuido pontual.
Este arquivo formaliza a classe, não o caso: além da matriz de `documentos`
(`INSERT`/`UPDATE ... RETURNING` × editor `aal2` / editor `aal1` / conselho / morador / anônimo),
o bloco E exercita **as duas formas do mesmo comando em todas as tabelas com policy de `INSERT`
para `authenticated`**, e o `set_eq` de cobertura quebra se alguém criar tabela escrita por papel
de usuário e não incluí-la. Distinguir `SILENCIO(0)` de `NEGADO-RLS` de `NEGADO-GRANT` é
requisito, não estilo: `UPDATE` barrado pelo `USING` afeta zero linhas **sem levantar erro**, e
tratar isso como "ok, bloqueou" é o hábito que escondeu o bug.

**Estado real (2026-09-06):** 264 asserts em 8 arquivos, todos verdes, com dois `todo` abertos em
`02_*` (revogação de mandato no mesmo dia, R4 de `docs/ops/divida-tecnica.md`). Veredito de
auditoria em `docs/auditoria/veredito-20260906100500-documentos-select-predicado-local.md`.
