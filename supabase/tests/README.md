# supabase/tests/

Suíte pgTAP de RLS, escrita e mantida pelo `auditor-rls`:

- `01_visibilidade_documento_pagina_chunk_rls.sql`
- `02_papeis_aal_mandato_pessoas_cobrancas_rls.sql`
- `03_lancamentos_audit_imutabilidade.sql`
- `04_privilegios_grants_e_superficie.sql`

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

**Estado real:** a suíte roda hoje com asserts vermelhos de propósito — o `auditor-rls`
bloqueou a baseline com 7 vazamentos encontrados, e `eng-supabase`/`arquiteto` estão corrigindo.
Isso é o job funcionando como deveria, não uma falha de configuração: RLS vermelho barra
`supabase db push` até as correções entrarem e o `auditor-rls` rodar a suíte de novo.
