# Veredito — `20260906100500_documentos_select_predicado_local.sql`

**Data:** 2026-09-06 · **Auditor:** `auditor-rls` · **Migração:** `documentos_select` passa a
predicado local · **Commit de origem:** `8e126fe`

## Decisão

**APROVADO.** A correção fecha o defeito, não afrouxa autorização nenhuma e agora está presa por
teste. A aprovação vale **com a ressalva do achado 1 abaixo**, que é de documentação da migração,
não da policy.

Suíte: **234 → 264 asserts**, 8 arquivos, todos verdes (`supabase test db --local`, três
execuções consecutivas). Os dois `todo` de `02_*` (revogação de mandato no mesmo dia, R4)
continuam abertos e fora do escopo desta rodada.

Arquivo novo: `supabase/tests/08_returning_predicado_local.sql`, 30 asserts.

## O que sustenta o veredito

O teste não vale porque está verde; vale porque fica **vermelho quando o defeito volta**. Três
injeções de falha, cada uma dentro de `begin`/`rollback`, contra o arquivo novo:

| Injeção | Asserts que caem |
|---|---|
| `documentos_select` de volta a `using (app.documento_visivel(id))` | **A1, A3, A8, E2, F1, F2** |
| `revoke execute on app.nivel_visivel from anon` | **F5** (e 4 asserts de `01_*`, que é a prova comportamental) |
| Defeito **plantado em outra tabela** (`questionamentos_select` passa a chamar função que relê `questionamentos`) | **E2, F1** |

A terceira injeção é a que responde ao pedido de "encontrar a classe, não o caso": o defeito foi
plantado numa tabela que não existia no incidente original e a suíte pegou, por comportamento
(E2) e por catálogo (F1), sem nenhum assert escrito sobre `questionamentos`.

## Cobertura declarada

**Coberto:**

- **A matriz de `documentos`** (A1–A8, B1–B6): `INSERT ... RETURNING` e `UPDATE ... RETURNING` ×
  {editor `aal2`, editor `aal1`, conselho `aal2`, morador, anônimo}. A editora com `aal2`
  consegue; os demais continuam negados. **A3/B2 provam que o `returning` devolve a linha**, não
  apenas que não explodiu.
- **A distinção que o orquestrador exigiu** (vocabulário `pg_temp.classifica`): `PASSOU(n)` /
  `SILENCIO(0)` / `NEGADO-RLS` / `NEGADO-GRANT`. `INSERT` recusado levanta `42501`; `UPDATE`
  barrado pelo `USING` afeta zero linhas **e não levanta nada**. A separação `NEGADO-RLS` ×
  `NEGADO-GRANT` é feita por `has_any_column_privilege`, **não** por texto de mensagem — mensagem
  depende de `lc_messages` e teste de segurança não pode depender de idioma.
- **C1/C2** fecham o buraco de `SILENCIO(0)`: um `UPDATE` de morador **sem `where` nenhum**
  também afeta zero linhas, e o título original continua intacto depois de todas as tentativas.
  "Zero linhas" é silêncio de verdade, não escrita invisível.
- **A propriedade (E0/E1/E2)**: para **todas as 24 tabelas** com policy de `INSERT` para
  `authenticated` — `assembleias`, `cobrancas`, `configuracoes`, `contas`, `contratos`,
  `deliberacoes`, `documento_unidades`, `documentos`, `fornecedor_dados_bancarios`,
  `fornecedores`, `lancamento_anexos`, `lancamentos`, `orcamento`, `papeis`,
  `parecer_signatarios`, `pareceres`, `periodos_fechados`, `pessoas`, `questionamentos`,
  `sinonimos`, `tipos_alerta`, `tipos_documento`, `unidades`, `vinculos` — o **mesmo** texto de
  `INSERT` roda com e sem `returning` e o resultado tem de bater. `E0` (`set_eq` contra
  `pg_policy`) impede mentir por **omissão**; `E1` (todo insert base tem de dar `PASSOU(1)`)
  impede mentir por **vacuidade**, comparando dois fracassos e chamando de acordo.
  `pareceres`/`parecer_signatarios` rodam como **conselho**, que é quem legitimamente escreve ali
  (SPEC §2.1) — rodar como editora daria `NEGADO-RLS` nas duas variantes e o teste passaria vazio.
- **A varredura estática (F1/F2)**: o conjunto de policies de `SELECT` cujo fecho de funções relê
  a própria tabela está congelado em quatro — `documento_paginas`, `papeis`, `pessoas`,
  `vinculos` — e `documentos` **saiu** dele.
- **Armadilha nº1 (F3/F4)**: `chunks` e `documento_paginas` espelham `documentos` **chamando a
  mesma função** `app.pagina_visivel`, sem predicado copiado; e a **premissa** que os isenta da
  classe (nenhum papel de usuário escreve neles) é verificada, não suposta.
- **F5**: `anon` tem `EXECUTE` em `app.nivel_visivel` — o `GRANT` que o predicado local passou a
  exigir. Sem ele, documento **público** vira `42501` para visitante sem conta, ou seja, o hotfix
  de um defeito criaria outro. Confirmado por injeção: o `revoke` derruba 4 asserts de `01_*`.

**Não coberto, e por quê:**

- **`chunks` e `documento_paginas` não entram na matriz do bloco E** porque hoje não têm policy
  de escrita para papel de usuário — não há `INSERT ... RETURNING` para quebrar. Isso é uma
  **premissa datada**, não um fato permanente: F3 é o assert que a derruba no dia em que ela
  deixar de valer.
- **`storage.objects`** fica fora deste arquivo (o gate do bucket é testado em `01_*`); a classe
  aqui é sobre RLS de tabela sob `RETURNING`, e ninguém faz `insert ... returning` em
  `storage.objects` pelo caminho da aplicação.
- **`audit.log` / `audit.acesso` / `job.fila`** ficam fora: estão fora do PostgREST e não têm
  policy de escrita para papel de usuário. `REVOKE UPDATE, DELETE` em `audit.log` continua em
  `03_*`/`04_*`.
- **`INSERT ... ON CONFLICT DO UPDATE ... RETURNING`** e CTEs modificadoras (`with x as (insert
  ... returning ...)`) não estão cobertos. São formas de comando distintas; pelo mecanismo, o
  caminho de conflito recai no `UPDATE` (linha antiga visível) e o de inserção recai em A1. Fica
  registrado como lacuna consciente, não como coisa esquecida.
- **A varredura estática é heurística** (fecho transitivo por regex sobre `prosrc`, 4 níveis) e
  está documentada como tal no próprio arquivo. Ela **não decide** se há defeito — decidir exige
  saber quem escreve e qual linha o predicado procura. Ela serve para obrigar revisão consciente
  quando o conjunto mudar. A prova é o bloco E, que é comportamental.

## Achados

### 1 — O comentário da migração afirma coisa factualmente errada sobre `vinculos` e `pessoas`

Severidade: **baixa (documentação)**. Não bloqueia. Não muda a policy.

O `eng-supabase` afirmou que nenhuma outra tabela tem o defeito, com o argumento de que em
`pessoas`/`papeis` a releitura só aparece no segundo operando de um `or` cujo primeiro operando é
local. **Verificado executando, não lendo.** A conclusão está certa; o argumento, como escrito,
não se sustenta:

- **`vinculos_select`** = `unidade_id in (select app.unidades_da_pessoa()) or app.eh_gestao()`, e
  `app.unidades_da_pessoa()` faz `select v.unidade_id from public.vinculos v` — **a própria
  tabela**. O comentário da migração lista `vinculos_select` entre as que "nenhuma reconsulta a
  PRÓPRIA tabela". A varredura do bloco F encontra `vinculos`.
- **`pessoas_select`** = `id = app.pessoa_atual() or app.eh_gestao()`. **Não existe** operando que
  deixe de tocar `pessoas`: `pessoa_atual()` lê `pessoas`, e `eh_gestao() → tem_papel()` também lê
  `pessoas` (join com `papeis`). Os **dois** operandos releem a tabela.

O que de fato salva as três não é "o outro operando é local". É que **a releitura procura a linha
do sujeito da sessão**, que já existia antes do comando e por isso é visível no snapshot —
diferente de `documento_visivel`, que procurava **a linha que o comando estava criando**. Essa é a
distinção que separa "não-local mas inofensivo" de "não-local e quebrado", e nenhum comentário a
registrava. Os asserts D1–D6 prendem a conclusão pelo **comportamento**, que é o que vale;
o comentário da migração merece correção quando `eng-supabase` tocar o arquivo de novo.

### 2 — Em `documentos`, o defeito é observável pelo `INSERT`, não pelo `UPDATE`

Severidade: **nenhuma (precisão do relato)**. Medido, não suposto.

O texto da migração diz "o mesmo vale para `UPDATE ... RETURNING`". O mecanismo é o mesmo (a
policy de `SELECT` é aplicada à linha nova), mas **o efeito não**: reintroduzindo o predicado
não-local, A1/A3/A8/E2/F1/F2 ficam vermelhos e **B1/B2 continuam verdes**. Motivo preciso: no
`UPDATE` a releitura **encontra** a linha — a versão antiga, anterior ao comando e portanto
visível — e para a editora `eh_gestao()` dentro de `documento_visivel` devolve `true` de qualquer
jeito. Só o `INSERT` não tem versão antiga nenhuma para achar. B1–B6 são, portanto, a metade da
matriz que prova que o hotfix **não afrouxou a escrita de ninguém**, e a base do contraste do
bloco C — não detectores desta regressão específica. Está anotado no próprio arquivo de teste para
que ninguém confie neles pelo motivo errado.

### 3 — Risco latente marcado, não corrigido: `vinculos` está a uma policy de distância da classe

Severidade: **informativa**. Não é ação para esta migração.

`D5` passa **só porque quem escreve `vinculos` é a editora**, e `eh_gestao()` (que não lê
`vinculos`) resolve o `or` sozinho. No dia em que um morador puder registrar o próprio vínculo,
`app.unidades_da_pessoa()` volta a ser o **único** caminho de decisão para esse papel e a classe
reaparece exatamente como em `documentos`: `insert ... returning` daria `42501` para o morador que
está cadastrando a si mesmo. O assert D5 existe como marcador desse risco, com o motivo escrito no
corpo do teste. Se essa policy for proposta, é decisão de `arquiteto` (ADR-0023) antes de
implementação.

## Nada de produto a reclassificar

Nenhum caso "negado" desta matriz deveria ser "permitido". Em particular: `conselho` não publica
documento nem escreve lançamento (D4 — contrapeso de **leitura**), editora em `aal1` não escreve
(ADR-0003), editora não emite parecer (única escrita exclusiva do conselho, já coberto por `02_*`
E4). O único ponto onde a matriz precisou de papel diferente da editora foi
`pareceres`/`parecer_signatarios`, e isso é o SPEC funcionando, não desvio.

## Escopo tocado

- `supabase/tests/08_returning_predicado_local.sql` (novo, 30 asserts)
- `supabase/tests/README.md` (índice e estado real)
- `docs/auditoria/veredito-20260906100500-documentos-select-predicado-local.md` (este arquivo)

Nenhuma migração, policy ou código de aplicação foi tocado — implementação é de `eng-supabase`.
