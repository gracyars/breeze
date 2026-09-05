# Invariantes de autorização — artefato de preenchimento obrigatório

**Isto não é documentação para ler. É formulário para preencher, com gate no CI.**

A razão de existir está registrada: nas três rodadas do `auditor-rls`, **todos** os defeitos
tiveram a mesma forma — página × documento, chunk × página, `mandato_fim` × as outras colunas de
vigência, página apagada × as páginas que sobraram. E a regra que teria evitado o V3-R **já estava
escrita, em negrito, no `docs/schema.md`**. Passou assim mesmo.

> Prosa em documento de desenho não sobrevive à implementação.

Por isso o formato é matriz com células, e não parágrafo. O critério de sucesso deste diretório é
que alguém tenha que **preencher**, não que tenha lido.

## Como as linhas da matriz são geradas

Este é o ponto que separa este artefato de uma checklist comum, e é o que o **V10** provou ser
necessário: aquela guarda vigiava `papeis.mandato_fim` e passaram `mandato_inicio`, `papel` e a
corrida concorrente. Foram três buracos porque as linhas foram **imaginadas**. Aqui elas são
**derivadas**.

**Passo 1 — Conjunto de dependência.** Liste toda `tabela.coluna` que o predicado lê. Sai da leitura
do corpo da função, não da memória. Se o predicado chama outra função, o conjunto dela entra no seu.

**Passo 2 — Produto cartesiano.** As linhas da matriz são, obrigatoriamente:

- `INSERT` em cada tabela do conjunto;
- `UPDATE` **de cada coluna** do conjunto, uma linha por coluna — não "UPDATE na tabela";
- `DELETE` em cada tabela do conjunto;
- mais as **quatro linhas fixas**, que nunca são geradas pelo conjunto e são onde os bugs moram:

| Linha fixa | Por que existe |
|---|---|
| Escrita por `service_role` / worker | bypassa RLS por construção (ADR-0012 item 6) |
| Concorrência (duas transações simultâneas) | a checagem "sou o último?" lê antes de escrever — **é a que o V10 perdeu** |
| Restore, migração, backfill | entram por fora de toda trigger que não seja `ALWAYS` |
| Propriedade assumida por leitor | contiguidade de `seq`, ordenação, unicidade — o **V5-R** |

**Passo 3 — Classificar a espécie de cada dependência não-local** (ADR-0023): *constitutiva* (as
outras linhas **são** a decisão — `papeis`, `vinculos`) ou *modal* (só decidem **como** a regra se
aplica). Modal é a espécie que vaza; se aparecer, a primeira pergunta é como **eliminá-la**.

## Vocabulário fechado das células

Célula não aceita texto livre — texto livre é onde "sim, pensei nisso" passa por resposta.
Cada célula é **exatamente um** destes, com o argumento entre parênteses:

| Valor | Significa | Exige |
|---|---|---|
| `GUARDADO(<trigger/constraint>)` | há guarda que rejeita a violação | nome do objeto no banco |
| `INVALIDA(<gatilho>)` | não rejeita; invalida o derivado e reprocessa (ADR-0021 nível 3) | nome do gatilho |
| `IMPOSSÍVEL(<motivo>)` | o caminho não existe | motivo estrutural, não "ninguém faria isso" |
| `MONOTÔNICO(<motivo>)` | o caminho só aperta, nunca afrouxa | por que não pode afrouxar |
| `ACEITO(<motivo>)` | a violação é possível e tolerada | motivo, e por que não é vazamento |

`TODO`, `?`, `n/a`, vazio ⇒ **bloqueia**.

## Coluna de teste vermelho — obrigatória

Cada célula tem um par: o identificador do teste pgTAP que **falha sem a guarda e passa com ela**.
Vem da regra do ADR-0021:

> Para cada proteção, qual é o teste vermelho que prova que ela funciona? Se não dá para escrever
> um teste que falha sem a guarda, não há guarda — há intenção.

Célula de teste vazia bloqueia igual a célula de caminho vazia. `IMPOSSÍVEL` e `ACEITO` também
exigem teste: o primeiro prova que o caminho realmente não existe; o segundo prova que a violação
tolerada não vira vazamento.

## O gate

**Quando aplica:** no merge da migração que implementa ou altera a invariante. Toda migração que
cria ou modifica função usada em policy, ou trigger de autorização, precisa de um arquivo aqui
criado ou atualizado no mesmo commit.

**O que o CI verifica** (implementação: `devops`, com `eng-supabase`):

1. Toda função em `app.*` referenciada por alguma policy tem arquivo `INV-*.md` correspondente.
2. Nenhum arquivo tem célula vazia, `TODO`, `?` ou valor fora do vocabulário fechado.
3. Toda célula referencia um teste que **existe** em `supabase/tests/`.
4. Toda tabela citada no conjunto de dependência tem, no mínimo, as linhas de `INSERT`,
   `DELETE` e um `UPDATE` por coluna listada — a checagem do produto cartesiano, que é o que
   teria feito o V10 gritar três vezes.
5. As quatro linhas fixas estão presentes em todo arquivo.

Falha em qualquer item ⇒ merge bloqueado. Mesmo peso do teste de RLS (ADR-0008, ADR-0012).

**Backlog datado, não bloqueio retroativo:** as invariantes que já existem são preenchidas antes de
produção, não antes do próximo merge. Lista em `INVENTARIO.md`.

## Arquivos

- `_TEMPLATE.md` — copiar para começar.
- `INV-<nn>-<slug>.md` — um por invariante.
- `INVENTARIO.md` — a lista do que precisa existir, com dono e estado.

## Por que isto e não uma regra no CLAUDE.md ou no SPEC

Já tentamos três vezes a versão "regra escrita": a D12 (regra apoiada em classificação),
o V1 (trava apoiada em flag marcada à mão) e o V3-R (regra em negrito no schema, implementada pela
metade). As três falharam em silêncio e nenhuma foi pega em revisão de código, porque **revisão lê
o que está escrito e estes bugs são o que não está escrito**. Ausência não tem linha para comentar.

Só duas coisas acham ausência: enumeração explícita e execução. Este diretório é a enumeração;
`supabase/tests/` é a execução. Um sem o outro não fecha.
