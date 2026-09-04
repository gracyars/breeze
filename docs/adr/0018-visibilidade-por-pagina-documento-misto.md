# ADR-0018 — Visibilidade resolvida por página em documento de conteúdo misto

> **Adendo ao ADR-0012.** Não o substitui e não altera seu mérito: a RLS continua sendo a
> fronteira única, e o espelhamento continua feito por função compartilhada. Muda **o que a
> função recebe** — o par `(documento_id, pagina)` no lugar de só `documento_id`.

## Contexto

O ADR-0012 assumiu, sem dizer, que **visibilidade é propriedade do documento**. A sonda do acervo
real desmentiu isso (`docs/inventario-acervo.md`): existe uma ata de assembleia de 36 páginas que
**embute o Regimento Interno inteiro como anexo**.

É um único `documento_id` com dois níveis de exposição legítimos ao mesmo tempo:

- o **regimento** é normativo e impessoal — deveria ser `publico` (Briefing §7.1, SPEC §7);
- a **ata** traz nome, unidade e voto — exige `autenticado`.

Com visibilidade só no documento, as duas saídas eram ruins e nenhuma era aceitável:
marcar `publico` **vaza nomes pela busca**; marcar `autenticado` **esconde o regimento**, que é
justamente o documento que o produto existe para tornar consultável. Fatiar o PDF em dois
`documentos` foi considerado e descartado (abaixo).

Isto não é caso isolado nem exótico: ata que anexa regimento, convenção ou orçamento é prática
comum de cartório e administradora. É o acervo real que se comporta assim.

## Decisão

**Visibilidade passa a ser resolvível por página, com herança e com falha fechada.**

### Modelo

- `documentos.tem_paginas_mistas boolean not null default false` — marca o documento cujo
  conteúdo não é homogêneo.
- `documento_paginas.visibilidade` (nullable) — override por página. `NULL` = herda.

### Duas camadas de função, para preservar "uma função só"

| Função | Responde |
|---|---|
| `app.nivel_visivel(nivel, documento_id)` | dado um nível **já resolvido**, este papel enxerga? **Núcleo único** do mapeamento nível → papel |
| `app.nivel_efetivo(documento_id, pagina)` | qual **é** o nível desta página? Resolve override e herança |
| `app.documento_visivel(documento_id)` | o **arquivo inteiro** é visível? Semântica inalterada |
| `app.pagina_visivel(documento_id, pagina)` | o **conteúdo desta página** é visível? |

O mapeamento nível → papel continua existindo em **um lugar só** (`app.nivel_visivel`). As duas
funções de entrada compõem sobre ele. É por isso que este ADR é adendo e não revisão: a razão do
ADR-0012 — predicado copiado diverge, e diverge calado — segue intacta.

### Onde cada entrada é usada

- `app.documento_visivel` → `documentos`, `storage.objects` do bucket `documentos`. **O PDF cru
  não é fatiado**: baixar o arquivo inteiro continua governado pelo nível do documento. Um
  anônimo não baixa a ata inteira só porque 12 das 36 páginas são públicas.
- `app.pagina_visivel` → `documento_paginas`, `chunks` (pela `pagina_ini`), `deliberacoes`
  (pela `pagina`). É onde vive o texto extraído, a busca e a citação — a granularidade que o
  caso real exige.

### Falha fechada, e é o ponto central

Enquanto `tem_paginas_mistas = true`, página **sem** `visibilidade` própria **não herda** o padrão
do documento: fica invisível a quem não é gestão até ser classificada. Marcar o documento como
misto é uma declaração de "este documento ainda não está classificado página a página" e o
sistema se comporta como tal. Se a herança valesse, marcar misto e esquecer de classificar
publicaria conteúdo com nomes — exatamente o erro que a flag existe para impedir.

### Chunk não cruza fronteira

Trigger `chunks_valida_visibilidade_uniforme`: em documento misto, um chunk só é aceito se todas
as páginas do intervalo `[pagina_ini, pagina_fim]` estiverem classificadas **e** com o mesmo
nível. Sem isso, o chunk herdaria a visibilidade de **uma borda** do intervalo e o texto das
demais páginas vazaria junto — ou ficaria preso por engano. O chunking com ~15% de overlap
(SPEC §3.4) atravessa fronteira de página por construção; sem a trava, o vazamento seria o
comportamento padrão, não a exceção. Documento não-misto não paga esse custo.

## Consequências

- **Curadoria ganha um passo** para o documento misto: classificar as páginas. É trabalho humano
  num gargalo que já é humano (D4). Mitigação: só documento marcado como misto exige isso, e a
  heurística de detecção (mudança abrupta de tipo de conteúdo no meio do PDF) pode **propor** a
  fronteira — nunca aplicá-la sozinha, pela mesma razão do SPEC §3.5.
- **O chunker precisa respeitar fronteira de visibilidade** ao segmentar documento misto, senão o
  trigger rejeita a inserção e o documento não indexa. Requisito de F1 para o pipeline, não
  detalhe de banco.
- Duas entradas de RLS em vez de uma. Risco novo e real: usar `documento_visivel` onde cabia
  `pagina_visivel` reabre a armadilha nº1 numa forma mais sutil. Contenção: a tabela acima é
  normativa, e o `auditor-rls` testa as duas — inclusive o caso "anônimo lê a página pública do
  regimento embutido **e não lê** a página seguinte, da ata".
- O custo por linha em `chunks` sobe: `pagina_visivel` faz um join a mais. Nesta escala
  (milhares de chunks), aceitável. Se doer, a saída continua sendo desnormalizar com trigger,
  nunca duplicar predicado.
- **Ganho que não é secundário:** o regimento embutido passa a ser encontrável em busca pública,
  o que é o objetivo declarado do produto. O modelo antigo obrigaria a escolher entre vazar e
  esconder.

## Alternativas descartadas

- **Fatiar o PDF em dois `documentos`.** Foi a primeira ideia e é a que alguém vai propor de novo.
  Descartada porque: (a) quebra `sha256` como identidade do arquivo recebido e o dedupe do
  SPEC §3.1; (b) o documento oficial registrado em cartório é **um** — publicar um recorte como
  se fosse o original destrói a proveniência, que é a tese do produto (SPEC §6.5, "nenhum número
  aparece sem proveniência rastreável"); (c) a citação por página do original deixa de bater com
  o PDF que a pessoa tem na mão.
- **Marcar o documento inteiro como `publico` e redigir os nomes.** Exige etapa de anonimização
  recorrente (Briefing §7.1) e altera o texto oficial — o SPEC §6.3 é explícito: o texto oficial
  nunca é reescrito.
- **Marcar `autenticado` e aceitar a perda.** Esconde o regimento atrás de login, contrariando o
  padrão adotado de acervo (normativo é público) e a razão de existir da busca.
- **Herança permissiva em documento misto** (página sem classificação herda o documento).
  Descartada: transforma esquecimento de curadoria em publicação indevida. Falha aberta.
- **Resolver na aplicação, filtrando resultado de busca.** Contraria o ADR-0012 frontalmente.
  A busca é um dos caminhos; PostgREST é outro.
- **Uma função só, recebendo `pagina` opcional (`documento_visivel(id, pagina default null)`).**
  Descartada: um argumento omitido por engano viraria "documento inteiro" silenciosamente,
  justamente na chamada mais perigosa. Duas funções com nomes diferentes tornam o erro visível
  na revisão.

## Status

Aceito, 2026-09-04. Adendo ao ADR-0012 (que permanece Aceito e íntegro).
**Emendado pelo ADR-0019:** este ADR resolveu a granularidade no índice e assumiu, sem verificar,
que isso bastava — o `auditor-rls` (V3) provou que o **arquivo** continuava monolítico e baixável
pelo nível do documento. O ADR-0019 impõe a invariante que faltava (`documentos.visibilidade` é o
**piso**: override de página só amplia) e torna `tem_paginas_mistas` derivada (V1). O caso real e
o modelo de duas entradas descritos aqui permanecem válidos.
Registrado em `docs/04-DECISOES.md` como D11. Implementado em
`supabase/migrations/20260904120600_acervo_tabelas.sql` e
`supabase/migrations/20260904120800_visibilidade_documento_funcoes.sql`.
