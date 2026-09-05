# ADR-0021 — Invariante de dois lados, guarda de um lado só

> O padrão comum aos achados **V1-R**, **V3-R** e **V5-R** da segunda rodada do `auditor-rls`.
> Este ADR vale mais que os três bugs: eles são a evidência, o padrão é o entregável.

## Contexto

Três vazamentos independentes, um padrão só:

> **A invariante é validada na escrita de um lado da relação e não é revalidada quando o outro
> lado muda.**

| Achado | A guarda existe em | O caminho não guardado | Efeito |
|---|---|---|---|
| **V1-R** | inserção de `chunks` (uniformidade de visibilidade no intervalo) | `UPDATE documento_paginas.visibilidade` **depois** de chunkizar | texto sigiloso na busca, com a chave `anon` |
| **V3-R** | escrita de `documento_paginas.visibilidade` (invariante do piso, ADR-0019) | `UPDATE documentos.visibilidade` afrouxando depois | texto negado, **PDF inteiro liberado** |
| **V5-R** | — | `verificar_cadeia` semeia com `seq = desde - 1` | acusa quebra falsa em cadeia intacta |

Por que o Postgres não ajuda: `CHECK` é intrinsecamente **de uma linha só**. No instante em que a
invariante atravessa duas linhas — ainda mais duas tabelas — não existe ferramenta declarativa, e a
completude da guarda vira **enumeração manual de caminhos de mutação**. Humano enumera o caminho
que está escrevendo agora.

**Detalhe que condena o método antigo:** no caso do V3-R, o desenho **já dizia** os dois lados —
`docs/schema.md` trazia "triggers nas **duas** direções — validar só um lado deixa a porta aberta
pelo outro", e o ADR-0019 idem. A implementação fez um. Prosa em documento de desenho não
sobrevive à implementação; **precisa ser célula de checklist, não frase de parágrafo.**

### O V1-R e o V3-R são a mesma forma; o V5-R é primo

Vale ser preciso, senão a analogia vira slogan:

- **V1-R e V3-R:** dois caminhos de escrita, uma guarda. Invariante assumida pelo autor de A,
  violada pelo autor de B.
- **V5-R:** um caminho de **leitura** assume uma propriedade que **nenhuma escrita jamais
  garantiu**. `verificar_cadeia` trata `seq` como **endereço** (`desde - 1`), quando `seq` é
  **ordem**. Sequência e identidade **nunca** prometem contiguidade: toda transação abortada
  queima um `nextval`. A linha "anterior" simplesmente não existe, o seed fica nulo, e o
  verificador grita.

A família que une os três: **uma suposição que vive na cabeça de quem escreveu um trecho e em
nenhum mecanismo do banco.**

Regra derivada do V5-R, curta e reutilizável: **`seq` dá ordem, não endereço.** Onde for preciso
"a linha anterior", pede-se por ordem, nunca por aritmética:

```sql
-- errado: assume contiguidade
select hash_registro from audit.log where seq = desde - 1;
-- certo: pede o predecessor por ordem
select hash_registro from audit.log where seq < desde order by seq desc limit 1;
```

## Decisão

### 1. Critério de reconhecimento — a matriz de caminhos de violação

**Antes de escrever o trigger**, e sempre que a invariante envolver duas tabelas (ou duas colunas
em tabelas diferentes), não se pergunta "como eu garanto isto aqui". Pergunta-se:

> **Quais são *todos* os caminhos que podem violar esta invariante?**

E a resposta vira artefato, não intenção — uma célula por `(tabela × operação)` para **cada** tabela
que a invariante toca, mais os caminhos que não são DML:

| Caminho | Estado | Como |
|---|---|---|
| `INSERT` em A | guardado / impossível / aceito-com-motivo | … |
| `UPDATE` de A.col | … | … |
| `DELETE` em A | … | … |
| `INSERT`/`UPDATE`/`DELETE` em B | … | … |
| Escrita direta por `service_role` | … | … |
| `TRUNCATE`, restore, migração | … | … |
| Propriedade assumida por leitor (contiguidade, ordenação, unicidade) | … | … |

**Célula vazia é bug**, não pendência. A matriz vai no comentário da migração, junto do trigger —
é o único lugar onde quem for alterar aquilo vai olhar.

Se a resposta tiver mais de um lado, a invariante **precisa** de guarda nos dois lados, ou de
derivação que torne o segundo lado impossível. É o item 2.

### 2. Hierarquia de soluções — nem toda invariante vira dois triggers

Em ordem de preferência. Só desce um degrau quando o de cima não couber, e **registra por quê**.

**Nível 0 — Eliminar: remodelar para a invariante não existir.**
A invariante mais barata é a que não existe. Ex.: se a visibilidade do chunk fosse computada em
leitura como o **mínimo** sobre seu intervalo de páginas, a invariante de uniformidade não
existiria — não haveria o que violar. **Descartado aqui conscientemente** (ADR-0019): vira agregação
por linha na tabela mais lida do produto. É troca de custo de escrita por custo de leitura, e neste
caso a leitura é o gargalo. Registrado para que a opção seja reavaliada, não redescoberta.

**Nível 1 — Derivar: fazer o segundo caminho não existir.**
Melhor solução realista. Foi o que se fez com `tem_paginas_mistas` no V1: a flag deixou de ser
autoral e passou a ser mantida por trigger, então "esquecer de marcar" saiu do conjunto de estados
possíveis. Aplica-se quando um dos lados é **derivável** do outro.

**Nível 2 — Validar dos dois lados: quando ambos precisam ser escritos por gente.**
`documentos.visibilidade` e `documento_paginas.visibilidade` são os dois decisões de curadoria
legítimas; nenhuma deriva da outra. Então **as duas** ganham trigger, e a matriz do item 1 é o que
prova que não sobrou lado. É o conserto do V3-R.

**Nível 3 — Invalidar/reprocessar o derivado: quando bloquear quebraria o fluxo legítimo.**
É o conserto do **V1-R**, e o critério de escolha é medível: *bloquear o segundo caminho quebra um
fluxo que precisa acontecer?* O `auditor-rls` mediu — o pipeline real **chunkiza primeiro e a
curadoria classifica depois**. Rejeitar a reclassificação de página quebraria exatamente o fluxo de
curadoria que motivou o modelo inteiro (ADR-0018). Então o `UPDATE` em
`documento_paginas.visibilidade` **não rejeita**: invalida os chunks afetados e reenfileira.

> **Regra de escolha entre nível 2 e nível 3:** se bloquear o segundo caminho impede um fluxo
> legítimo e frequente, você está no nível 3. Bloquear ali não é rigor, é desenho errado — e a
> pressão de trabalho vai produzir o contorno.

### 3. Os três consertos

**V1-R — trigger em `documento_paginas` `AFTER UPDATE OF visibilidade`:**
`DELETE` dos chunks cujo intervalo `[pagina_ini, pagina_fim]` intersecta a página alterada, mais
reenfileiramento do documento em `job.fila` (idempotente por `sha256 + versao_pipeline`, SPEC §3).

**Apagar, não marcar como inválido.** Um flag `invalidado_em` obrigaria toda policy e toda consulta
de busca a lembrar de `and invalidado_em is null` — mais um predicado que alguém esquece, que é o
erro que este ADR inteiro trata. Linha apagada não vaza. O custo é honesto: **a busca perde aqueles
trechos até o reprocessamento terminar** — uma lacuna temporária de busca é preferível a uma janela
de vazamento. `deliberacoes.chunk_id` já é `on delete set null` com âncora estável em
`(documento_id, pagina) + trecho_literal` (ADR-0016), então a citação não quebra.

**V3-R — trigger em `documentos` `BEFORE UPDATE OF visibilidade`:** rejeita afrouxar acima de
`min(ordem(visibilidade))` das páginas já classificadas. Estava no desenho desde o ADR-0019; falta
existir.

**V5-R — `audit.verificar_cadeia`:** pedir o predecessor por ordem
(`where seq < desde order by seq desc limit 1`), nunca por `desde - 1`.

### 4. Nota para F1 — e como torná-la encontrável

Quem escrever o chunker **vai** encontrar este caso, porque o pipeline reclassifica depois de
indexar. Três pontos de encontro, em ordem de eficácia:

1. **A mensagem de exceção do trigger cita o caminho do ADR.** É o que a pessoa lê às duas da
   manhã quando a inserção falha. Vale mais que qualquer índice de documentação.
2. `comment on function` / `comment on trigger` com o mesmo ponteiro.
3. Nota no SPEC §3 (ingestão), que é a seção que um autor de pipeline lê antes de começar.

## Consequências

- Um artefato novo e chato por invariante relacional: a matriz. É o ponto — ela transforma
  "lembrar de pensar nos dois lados" em uma tabela com células vazias visíveis.
- O nível 3 introduz **degradação temporária de busca** como comportamento normal e esperado.
  A UI precisa saber dizer "reindexando" em vez de mostrar acervo incompleto sem explicação.
- Reclassificar página passa a ter custo de reprocessamento. Aceitável: é operação rara de
  curadoria, e o pipeline é idempotente por desenho.
- Guarda de invariante relacional passa a exigir **teste de negação pelo segundo caminho**, não só
  pelo primeiro. Sem isso o teste passa e o buraco fica.

## A mesma família de erro, em roupas diferentes

Este é o terceiro membro. Vale ver os três juntos, porque a próxima ocorrência vai usar roupa nova:

| Registro | Forma | O que dependia de alguém |
|---|---|---|
| **D12** | regra de fiscalização apoiada em `contas.exige_deliberacao` | alguém ter classificado a conta certa antes |
| **V1 / D13** | trava de chunk apoiada em `tem_paginas_mistas` autoral | alguém ter marcado a caixinha |
| **Este (V1-R, V3-R)** | invariante validada num caminho só | alguém ter lembrado do segundo caminho |

As três **falham em silêncio**, as três **parecem certas em revisão de código**, e as três só
apareceram porque alguém **executou contra o banco**.

A razão de serem invisíveis na revisão é estrutural e vale nomear: **revisão de código lê o que
está escrito; estes bugs são o que não está escrito.** Ausência não tem linha para comentar. Só
duas coisas encontram ausência: enumeração explícita (a matriz) e execução (o teste vermelho).

Daí a prática que fica, e que se aplica a toda proteção deste projeto:

> **Para cada proteção, qual é o teste vermelho que prova que ela funciona?**
> Se não dá para escrever um teste que falha sem a guarda e passa com ela, não há guarda —
> há intenção.

E o corolário sobre o `auditor-rls`: ele não está achando bugs porque o desenho é ruim; está
achando a classe de bug que **só a execução acha**. O modo de falha padrão deste projeto é o
silêncio — por isso o teste de negação é gate de merge (ADR-0008, ADR-0012), não relatório.

## Alternativas descartadas

- **Confiar em revisão de código mais atenta.** É o que já existia. Falha por construção contra
  bug de ausência.
- **Uma "convenção do projeto" de sempre validar dos dois lados.** Convenção é o que a D12 e o V1
  já derrubaram duas vezes. Precisa ser artefato verificável, não hábito.
- **`CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED` para checar no fim da transação.**
  Ajuda em invariantes que ficam temporariamente violadas dentro de uma transação, e **não** é o
  problema aqui: as violações do V1-R e do V3-R acontecem em transações **separadas**, minutos ou
  dias depois. Útil no futuro; irrelevante para estes três.
- **Materializar a visibilidade efetiva em `chunks`, sincronizada por trigger.** É o nível 1
  (derivar) aplicado ao V1-R, e é atraente. Descartado por ora porque a sincronização teria os
  mesmos dois lados (página muda → chunk precisa mudar) — trocaria a invariante por outra da mesma
  família, com a diferença de que a versão errada fica **legível como dado** e parece correta.
  Reavaliar se o custo de reprocessamento incomodar.
- **Bloquear a reclassificação de página quando existirem chunks.** Nível 2 aplicado ao V1-R.
  Descartado com medição: quebra o fluxo de curadoria que motivou o ADR-0018.

## Status

Aceito, 2026-09-04. **Estendido pelo ADR-0023**, que trata o mesmo padrão visto do lado do
*predicado* e não da *guarda*: quando o valor de um predicado de autorização depende de outras
linhas, toda escrita naquelas linhas é uma mudança de autorização. E a matriz descrita aqui virou
artefato preenchível em **`docs/invariantes/`**, com gate de CI — porque este ADR, sozinho, é
prosa em documento de desenho, exatamente o que ele diz não sobreviver à implementação.

Fecha V1-R, V3-R e V5-R. Emenda operacional ao ADR-0019 (a guarda do lado
`documentos` passa a existir) e ao ADR-0013 (`verificar_cadeia`). Registrado em
`docs/04-DECISOES.md` como D15. Implementação com o `eng-supabase`; testes de negação **pelo
segundo caminho** com o `auditor-rls`.
