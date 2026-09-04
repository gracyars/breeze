# ADR-0002 — Supabase Postgres como datastore único

## Contexto

O Breeze precisa, ao mesmo tempo, de: dado relacional com integridade forte (lançamento →
documento → página), busca textual em português, busca vetorial, autorização por linha,
metadados semiestruturados e trilha de auditoria transacional. Escala pequena e estável:
~50 unidades, centenas de PDFs, 5–20 documentos/mês (SPEC, preâmbulo). Um mantenedor.

## Decisão

Um único Postgres gerenciado pelo Supabase guarda **todo** o estado do produto: dado relacional,
`tsvector`, `pgvector`, JSONB, fila de processamento e trilha de auditoria. Nenhum outro
datastore (nem cache, nem motor de busca, nem fila dedicada) entra sem ADR próprio.

Extensões assumidas como disponíveis no Supabase gerenciado: `pgcrypto`, `vector`, `unaccent`,
`pg_trgm`, `citext`, `btree_gist`, `pgtap` (só em local/CI). Extensões **não** disponíveis e que
não podem ser pressupostas: `pg_textsearch`/BM25 (ver SPEC §4 e ADR-0005), dicionários de
sinônimo em `$SHAREDIR`.

## Consequências

- Um backup cobre tudo (SPEC §7: `pg_dump` semanal + espelho do Storage). Um modelo mental,
  um lugar para procurar quando algo está errado.
- Transação real entre lançamento, anexo e trilha de auditoria: não existe estado meio-gravado.
  Isso é pré-requisito do ADR-0013.
- Postgres é portável. Trocar de Supabase por outro Postgres gerenciado é migração de dados,
  não reescrita — desde que o acoplamento a `auth.*` e `storage.*` fique confinado (as tabelas
  de domínio referenciam `auth.users` por uma única coluna, `pessoas.auth_user_id`).
- Limite conhecido: fila em tabela Postgres não escala para milhares de mensagens/segundo. Nesta
  escala é irrelevante (ADR-0007).
- Supabase Pro (~R$140/mês) no orçamento do SPEC §1.2. O plano Free não serve para produção
  (pausa por inatividade, sem PITR).

## Alternativas descartadas

- **Firebase/Firestore.** Sem agregação relacional; orçado×realizado e balancete viram código
  de aplicação. Fatal para um produto cujo núcleo é somar números com integridade.
- **MongoDB.** O dado aqui é relacional (unidade↔pessoa↔vínculo↔cobrança, conta↔lançamento↔
  documento↔página). Modelar isso em documento é perder as garantias que dão credibilidade.
- **Postgres + Elasticsearch/Pinecone.** Mais um serviço, mais um backup, mais uma consistência
  eventual a explicar, e um custo recorrente adicional fora do teto de R$300/mês.
- **Postgres cru em VPS.** Ver ADR-0001: manutenção.

## Status

Aceito. Formaliza ADR-2 da tabela do SPEC §1.1.
