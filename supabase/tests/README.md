# supabase/tests/

Slot para os testes pgTAP de RLS (`auditor-rls`). Convenção: um arquivo `.sql` por
tabela/policy, nome `NN_<tabela>_rls.sql`.

O workflow de CI (`.github/workflows/ci.yml`, job `rls-test`) sobe o Supabase local
(`supabase start`, que aplica todas as migrações de `supabase/migrations`) e roda
`supabase test db --local supabase/tests` antes de qualquer `supabase db push`. Nenhum deploy
passa com teste vermelho aqui.

**Pré-requisito para o `auditor-rls`:** a extensão `pgtap` precisa estar habilitada antes dos
testes rodarem — adicionar `create extension if not exists pgtap;` na primeira migração que
introduzir schema, ou via `supabase/config.toml` (`[db.extensions]` se aplicável na versão do
CLI em uso). Sem isso, `supabase test db` falha ao encontrar `pg_prove`/funções de assert.

Ainda vazio em F0 — este devops só monta o slot; escrever os testes é escopo de `auditor-rls`.
Enquanto vazio, o job de CI detecta a ausência de `.sql` e não falha o build (ver comentário no
workflow) — isso deixa de valer assim que o primeiro teste for adicionado.
