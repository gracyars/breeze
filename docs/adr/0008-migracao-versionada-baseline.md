# ADR-0008 — Migração versionada com baseline única; schema nunca é editado pelo dashboard

## Contexto

O banco **é** o produto: ele guarda o dado, a autorização (ADR-0012) e a trilha (ADR-0013). Um
schema que diverge entre ambientes significa policy testada em um lugar e ausente em outro — que
é exatamente o modo de falha nº1 do projeto (SPEC §7, §8.1). O Supabase oferece um editor de
schema no dashboard, e é confortável usá-lo. É por isso que a proibição precisa ser explícita.

## Decisão

1. **Toda mudança de schema é uma migração SQL versionada** em
   `supabase/migrations/<timestamp>_<slug>.sql`, commitada, revisada e aplicada por
   `supabase db push` no CI. **Schema nunca é editado pelo dashboard** (SPEC §1.2), inclusive em
   staging — divergência de staging invalida o teste de RLS que roda lá.
2. **Uma única baseline**: `<timestamp>_00_baseline.sql` cria o schema inteiro de F0 (extensões,
   schemas `app`/`audit`/`job`, enums, tabelas, índices, funções auxiliares, RLS habilitada e
   `REVOKE` de base). Depois dela, **só migração incremental** — a baseline nunca é reescrita,
   nem "regenerada por conveniência", porque um ambiente já a aplicou.
3. **Migrações são aditivas e reversíveis por avanço**, não por `down`. Não há script de rollback:
   corrigir é uma nova migração. Rollback de schema com dado dentro é ficção.
4. **Renomear/remover coluna em duas fases**: adiciona nova → aplicação escreve nas duas → migra
   dado → remove antiga em migração posterior. Nunca em um passo, porque o deploy da aplicação e
   a migração não são atômicos entre si.
5. **RLS na mesma migração da tabela.** Criar tabela e habilitar RLS depois é abrir uma janela em
   que a tabela está exposta. `alter table ... enable row level security` e os `revoke` vêm no
   mesmo arquivo que o `create table`.
6. **Tipos TypeScript são gerados no CI** a partir do schema e commitados. Divergência entre tipo
   commitado e schema quebra o build. O tipo é derivado, nunca a fonte.
7. **Gate de CI obrigatório** (bloqueia merge): `supabase db reset` em banco limpo aplica todas
   as migrações sem erro → `lint` → `typecheck` → **testes pgTAP de RLS** → testes de aplicação.
   Regressão de RLS é vazamento (SPEC §7); o teste é gate, não relatório.
8. **Seed separado de migração.** `supabase/seed.sql` carrega dado de referência não sensível
   (plano de contas padrão, tipos de documento, sinônimos, configurações). Dado de produção nunca
   entra em migração.

Autoria: a baseline é do `arquiteto`; **toda migração posterior é do `eng-supabase`**. Dois
agentes não escrevem no mesmo diretório na mesma fase.

## Consequências

- O histórico de migrações é a história do modelo de dados, auditável em git — coerente com um
  produto cuja tese é rastreabilidade.
- Fricção deliberada: mudar o schema exige commit e CI verde. É lento de propósito.
- Migração que quebra em produção com dado real é o pior cenário. Mitigação: o CI aplica a
  migração sobre um dump anonimizado de produção antes do merge (ADR-0009), não só sobre banco
  vazio — migração que passa em banco vazio e falha com dado é o caso comum (constraint `NOT
  NULL` sem `DEFAULT`, `UNIQUE` sobre dado já duplicado).
- Extensões (`vector`, `unaccent`, `pg_trgm`, `citext`, `pgcrypto`) são criadas na baseline em
  `extensions`, e sua ausência quebra a migração cedo e alto — que é o comportamento desejado.

## Alternativas descartadas

- **Editar pelo dashboard e depois `db diff`.** O diff perde intenção, não gera comentário e
  costuma produzir SQL que não reflete a ordem correta de dependência. Além disso, normaliza a
  edição manual — e a exceção vira regra na primeira urgência.
- **ORM com migração automática (Prisma migrate / Drizzle push).** Nenhum ORM modela RLS,
  policies, triggers `SECURITY DEFINER`, colunas geradas com `tsvector` ou schema separado sem
  escape hatch. O schema aqui é rico demais para ser subproduto de um modelo TypeScript.
- **Schema declarativo (state-based) como fonte.** Atraente, mas gera DDL que o autor não leu —
  inaceitável para uma migração que mexe em policy de dado pessoal.
- **Múltiplas baselines / squash periódico.** Perde o histórico e força ambiente já provisionado
  a reconciliar. Descartado.

## Status

Aceito.
