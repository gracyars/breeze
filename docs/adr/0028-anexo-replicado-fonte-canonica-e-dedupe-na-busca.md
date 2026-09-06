# ADR-0028 — Anexo replicado: curadoria declara, busca deduplica, e a norma é citada pelo documento normativo

## Contexto

A ata AGE de 04.02.2026 (36 páginas) embute o **Regimento Interno inteiro** — os mesmos 191 artigos
que existem no arquivo autônomo `RI - Regulamento Interno` (23 páginas). Um texto normativo,
impessoal e público, duplicado dentro de um documento autenticado que traz nome, unidade e voto.

A D11/ADR-0018 já resolveu **a exposição**: as páginas do regimento embutido recebem override
`publico` (o piso do ADR-0019 permite, porque `publico` é mais permissivo que `autenticado`), e o
PDF cru da ata continua atrás de login. O que **não** está resolvido é o que acontece depois que
esse texto está indexado duas vezes:

1. como se **detecta** que um trecho é réplica de outro documento;
2. o que a **busca** faz com dois chunks que dizem a mesma coisa;
3. qual dos dois é a **fonte canônica** quando alguém cita "art. 47 do Regimento".

A terceira é a que tem consequência real: um produto sobre proveniência que cita a mesma norma ora
por um documento, ora por outro, destrói a própria tese. Duas pessoas discutindo em assembleia com
a mesma regra e citações diferentes é pior do que não ter citação.

## Decisão

### 1. Detecção: a curadoria declara; a heurística só propõe, e não é a de artigo

**A fonte de verdade é a confirmação humana.** Coerente com a D11 ("a heurística pode propor a
fronteira, nunca aplicá-la sozinha") e por um motivo que não é filosófico: um falso positivo aqui
**publica uma página autenticada** — nome, unidade e voto na busca sem login. É a classe de erro
mais cara do produto, disparada por um limiar.

A heurística que propõe é **similaridade de página por shingling**: conjunto de 5-gramas de tokens
do texto normalizado (minúsculas, sem acento, sem pontuação, sem quebra de linha), Jaccard entre
páginas de documentos diferentes, proposta acima de 0,8. Barato, determinístico, sem modelo, e
generaliza para os outros casos que virão (convenção anexada a ata, orçamento anexado a ata — prática
comum de cartório e administradora).

**Estrutura de artigo é sinal ruim e há medida disso no acervo real:** a sondagem marcou "estrutura
de artigos" em documentos que apenas **citam** artigos de norma externa — Habite-se e "Procedimentos
para execução de reformas" — 2 falsos positivos entre 43 arquivos. Como sinal primário, reprovado.
Como sinal **secundário** (a faixa proposta contém sequência densa e crescente de `Art. N`), serve
para ordenar a fila de conferência, nunca para decidir.

A proposta aparece na tela de conferência como uma frase inteira e uma ação:

> *"As páginas 14–36 reproduzem 'RI — Regulamento Interno' (semelhança 0,93). Marcar como anexo
> replicado e tornar essas páginas públicas?"*

### 2. A réplica é declarada numa tabela, não recalculada

`public.trechos_replicados (id, documento_id, pagina_ini, pagina_fim, canonico_documento_id,
canonico_pagina_ini, canonico_pagina_fim, similaridade numeric, confirmado_por, confirmado_em)`.
Escrita só por `editor`; leitura para quem já enxerga o documento.

A declaração acontece **uma vez**, na curadoria. A busca depois faz um `join`, não um cálculo de
similaridade por consulta. Migração para o `eng-supabase`.

### 3. Deduplicação é **ranking, não autorização** — e essa fronteira é o ponto do ADR

> A busca deduplica **depois** de a RLS ter feito o trabalho dela, na camada de aplicação/consulta.
> Nada em `trechos_replicados` entra em policy, em `app.*` ou em qualquer predicado de acesso.

Pôr o dedupe na RLS criaria exatamente o defeito que o ADR-0023 proíbe: a visibilidade de um chunk
passaria a depender de **linhas de outro documento**, e apagar a réplica ou o canônico mudaria a
autorização de algo que ninguém tocou. Terceira vez que essa forma aparece no projeto; aqui ela é
recusada antes de ser escrita.

Regra da colapsagem, e ela cai fora sozinha porque a RLS já filtrou as duas listas:

- Se o resultado é um chunk dentro de uma faixa replicada **e** o chunk canônico correspondente
  também está no conjunto visível ao usuário ⇒ mantém-se **o canônico**, e a réplica vira uma linha
  secundária no mesmo resultado: *"este texto também consta da Ata AGE de 04.02.2026, p. 14–36"*.
- Se o canônico **não** aparece — porque a RLS o escondeu, porque foi despublicado, porque ainda
  não foi indexado — a réplica **permanece como resultado**. Um `left join` que não casa não remove
  nada.

> **O dedupe nunca remove a única cópia visível.** Não é uma salvaguarda acrescentada: é o
> comportamento natural de manter a decisão fora da autorização.

### 4. Fonte canônica de citação: o documento normativo; a ata prova o ato, não o texto

**Regra:** citação de **norma** aponta para o documento normativo (`regimento`, `convencao`);
citação de **decisão** aponta para a ata. São coisas diferentes e o schema já as separa —
`deliberacoes` existe para a segunda.

Três razões, na ordem em que pesam:

1. **A citação precisa ser conferível por quem tem o PDF.** O morador recebeu o Regimento; ele não
   recebeu a ata de 36 páginas. "Art. 47 do Regimento Interno, p. 9" ele confere; "art. 47, p. 22
   da ata AGE" ele não sabe nem por onde começar.
2. **A norma sobrevive à ata.** Quando o regimento for alterado, haverá um documento consolidado
   novo. Citação de norma tem de acompanhar a norma vigente, não a assembleia que a aprovou uma vez.
3. **A ata tem função própria e insubstituível:** provar quando, com que quórum e por quem a norma
   foi aprovada. É `deliberacoes` com âncora `(documento_id, pagina) + trecho_literal` (ADR-0016),
   e o leitor da norma mostra essa proveniência ao lado do artigo — "aprovado na AGE de
   04.02.2026". A ata ganha papel maior assim do que competindo como fonte de texto.

**Regra de desempate, para os casos que virão:**

| Situação | Canônico |
|---|---|
| Existe documento autônomo do tipo normativo | ele; entre vários, **o mais recente em vigor** |
| A norma só existe embutida numa ata | a faixa de páginas dentro da ata, **provisoriamente** — e a curadoria recebe a tarefa de obter e publicar o documento autônomo |
| Duas atas embutem a mesma norma | a mais recente é a réplica de referência; nenhuma é canônica se houver autônomo |

A segunda linha é uma decisão de produto, não de arquitetura: **norma que só existe dentro de uma
ata de 36 páginas é norma que ninguém lê**. O sistema pode indexá-la, mas o trabalho certo é
publicar o texto autônomo.

**Limite honesto, e é o inverso do caso de hoje:** se uma ata **altera** artigos e não há
consolidado novo, o autônomo fica desatualizado e a citação canônica passa a apontar para texto
superado. O mecanismo que resolve isso é a `deliberacao` ligada ao artigo, com aviso no leitor —
"há deliberação posterior que altera este artigo" (D10 item 4, "distinguir texto original de
alteração posterior"). Isso é **F3**, não F1. Em F1 o caso não existe no acervo: pela sondagem, a
AGE de 04.02.2026 **aprova** o regimento anexado, não emenda um anterior — *inferência a partir do
inventário, não leitura integral da ata; a curadoria confirma na conferência* (corte C5).

### 5. Duas exigências que este caso impõe a `documento_paginas`

O override de página para `publico` é hoje a operação mais perigosa do sistema: contorna
`tipos_documento.permite_publico` (o trigger `documentos_valida_visibilidade` só olha
`documentos.visibilidade`, deliberadamente — ver comentário da baseline 06), e o único guarda é o
julgamento de uma pessoa. Duas medidas baratas, que também fecham a dívida **A2**:

1. **`documento_paginas.motivo_override text`**, obrigatório quando `visibilidade is not null`.
   Não é burocracia: é o registro de por que uma página de documento autenticado ficou pública, e
   é o que uma auditoria futura vai querer ler. Local, sem custo de leitura.
2. **`documento_paginas` passa a ser auditada** em `audit.log` (dívida A2 do
   `docs/ops/divida-tecnica.md`). É tabela de autorização; F1 é quando ela começa a ser escrita de
   verdade — auditar depois de já ter histórico é pior e mais caro.

## Consequências

- A ata AGE deixa de competir com o Regimento na busca: uma pergunta sobre animais devolve **um**
  resultado, no Regimento, com a nota de que o texto também consta da ata.
- A ordem de conferência importa: se a ata for conferida **antes** do Regimento autônomo estar
  indexado, o canônico não existe ainda e a réplica aparece sozinha. Correto e temporário — mas o
  plano de F1 põe o Regimento em primeiro lugar na fila justamente por isso (corte C5).
- O chunking dessa ata só fica correto **depois** da reclassificação das páginas, o que passa pelo
  invalidador e pelo reenfileiramento: **este caso não funciona sem o ADR-0026.** É a prova
  concreta de que E2 é bloqueante e não higiene.
- Uma tabela nova, uma coluna nova, nenhum predicado de autorização novo. O modelo de visibilidade
  não cresce.
- `trechos_replicados` é declaração humana e pode ficar desatualizada se o canônico for
  substituído. Aceito: o `left join` degrada para "não deduplica", que é o comportamento seguro.

## Alternativas descartadas

- **Detecção automática aplicando o override sozinha.** Um limiar publicando página autenticada.
  A pior relação risco/benefício do projeto, para economizar um clique num caso por ano.
- **Estrutura de artigo como sinal primário.** 2 falsos positivos em 43 no acervo real, ambos por
  citação de norma externa.
- **Não indexar as páginas replicadas** (indexar só o canônico). Quebra a citação por página do
  documento que a pessoa tem na mão: quem lê a ata na página 22 não encontraria o próprio texto que
  está vendo. E deixaria um buraco silencioso no índice de um documento publicado — a classe de
  falha do E2.
- **Fatiar o PDF em dois documentos.** Já descartado na D11 e o motivo não mudou: quebra o `sha256`
  como identidade do arquivo recebido, destrói a proveniência do documento registrado em cartório
  (que é **um**), e desalinha a citação por página do PDF real.
- **Dedupe por similaridade calculada na hora da consulta.** Custo por busca para um fato que não
  muda, e reintroduz na leitura a dependência de outras linhas que o item 3 tira do caminho.
- **Deixar a citação apontar para os dois documentos.** É a saída "neutra" e é a pior: transfere ao
  leitor uma decisão que ele não tem como tomar, e garante que duas pessoas citem coisas diferentes
  na mesma discussão.

## Status

Aceito, 2026-09-06. Adendo ao ADR-0018/0019 (não os altera: nenhum predicado de autorização muda).
Depende do ADR-0026. Fecha a dívida **A2** quando implementado. Migrações (`trechos_replicados`,
`motivo_override`, auditoria de `documento_paginas`): `eng-supabase`. Cortes C5 (override manual) e
C8 (proposta automática + dedupe) de `docs/f1-plano.md`.
