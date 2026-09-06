# ADR-0027 — F1 entrega busca léxica; embedding e classificação por LLM ficam atrás de porta, desligados e declarados

## Contexto

Não há chave de LLM. Duas etapas do pipeline dependem dela: **embedding** (metade semântica da
busca híbrida do ADR-0005) e **classificação** (SPEC §3.5, extração de tipo/data/competência).

O jeito errado de lidar com isso tem nome e é o padrão do mercado: deixar a etapa "para depois",
com um `if` espalhado, um `TODO` e uma UI que não diz nada. O resultado é sempre o mesmo — a metade
desligada vira invisível para quem constrói e invisível para quem usa, e o produto entrega uma
busca que falha em paráfrase enquanto se apresenta como busca semântica. Num produto cuja tese é
proveniência e confiança, uma busca que devolve "nenhum resultado" sem explicar por quê é
especialmente cara: a pessoa não conclui "a busca está pela metade", conclui **"o acervo não tem"**
— e vai perguntar no grupo do WhatsApp, que é exatamente o que o produto existe para substituir.

## Decisão

### 1. O que F1 entrega: busca léxica, completa, ponta a ponta

`chunks.tsv` com a configuração `public.pt_br`, índice GIN, `ts_rank_cd`, facetas, pré-filtro,
`pg_trgm` para erro de digitação em nome próprio, e a expansão de sinônimos na aplicação. Tudo isso
já existe no schema de F0 e **não depende de chave nenhuma**.

### 2. Nada de fork na fusão: RRF com uma lista vazia é RRF

`score = Σ 1/(60 + rank_i)` sobre as listas disponíveis. Com a lista semântica vazia, o resultado é
a ordem da lista léxica — sem ramo especial, sem `if desligado`. Essa é uma propriedade real do RRF
(ADR-0005) e é o motivo de a metade desligada **não** contaminar o código de busca. A função de
busca é escrita uma vez, para N listas, e recebe uma.

### 3. As etapas são portas com um adaptador `Desligado` de verdade

`GeradorDeEmbedding` e `ClassificadorDeDocumento` são interfaces com duas implementações cada:
a real e a `Desligado`. A `Desligado` é **código de produção com teste**, não um `null` circulando.

> **Regra dura: desligado nunca produz valor falso.** Nada de vetor de zeros, nada de classificação
> "chutada", nada de string vazia. `chunks.embedding` permanece `NULL`; `documentos.metadados` fica
> sem a proposta. A **ausência é o registro** — e é o que torna o reprocessamento seletivo
> expressável como `where embedding is null`.

Vetor de zeros seria o pior desfecho possível: passa em todo teste de tipo, entra no índice, e
produz similaridade cosseno indefinida ou constante — uma busca semântica que "funciona" e ordena
por ruído. Essa é a dívida escondida contra a qual este ADR existe.

Quais capacidades estão ligadas vive em `configuracoes`
(`pipeline.capacidades = {"embedding": false, "classificacao_llm": false}`), lido pelo worker e pela
aplicação. Uma fonte, não uma variável de ambiente em cada lugar.

### 4. O que a UI diz — e ela diz, não esconde

Três lugares, em ordem de importância:

1. **Estado vazio da busca** (o que mais importa): quando não há resultado, a tela diz explicitamente
   que a busca hoje encontra **palavras**, não **significado**, sugere o termo exato ou um sinônimo,
   e oferece o caminho de sempre: navegar por tipo e ano. Não é um "ops, nada encontrado".
2. **Cabeçalho de resultados**, uma linha discreta e permanente: *"Busca por palavra — encontra o
   termo e suas variações. A busca por significado está desligada."* Discreta e sempre presente;
   banner que se fecha vira banner que ninguém viu.
3. **Painel da editora**: quantos chunks estão sem embedding, ao lado da sentinela do ADR-0026.
   As duas respondem à mesma pergunta — "o que está incompleto no índice agora".

Nada disso pede desculpas nem promete data. Descreve o que a ferramenta faz hoje.

### 5. A tabela `sinonimos` deixa de ser acessório e vira entrega de F1

Com a metade semântica desligada, **a expansão de sinônimos é o único mecanismo de paráfrase que
existe**. O SPEC §4 já lista o núcleo ("taxa condominial | cota | rateio", "fundo de reserva | FR",
"prestação de contas | balancete", "AGE | assembleia extraordinária"). Ele precisa ser semeado com o
vocabulário **deste** condomínio — o acervo real usa "PrestContas", "composição da cota", "enxoval",
"portaria remota", "AGI" — e alimentado pelas buscas que devolvem zero resultado, que passam a ser
registradas (termo e contagem, sem identificar quem buscou).

Isso troca um custo variável em dólar por um trabalho de curadoria de vocabulário que a mantenedora
faz melhor que qualquer modelo, porque ela conhece o prédio.

### 6. Classificação desligada impõe a ordem certa, e é bom que imponha

Sem LLM, o documento chega à conferência com **campos vazios** e a editora preenche. O formulário
humano é construído primeiro; o pré-preenchimento vem depois, no mesmo formulário. Consequência boa
e permanente: **o LLM nunca está no caminho da publicação** — ele preenche um formulário que já
funcionava sem ele. É exatamente o que o SPEC §3.5 e §5.1 exigem ("o modelo propõe, nunca publica"),
e a falta de chave torna essa arquitetura obrigatória em vez de disciplinada.

O pré-preenchimento de F1 vem de graça, do **nome do arquivo**, que neste acervo é estruturado
(`2215 - BREEZE AGE 04.02.2026 site.pdf` carrega tipo e data; `PrestContas janeiro 2026.pdf` carrega
tipo e competência). Regras de nome de arquivo, determinísticas e auditáveis, cobrem a maior parte do
lote e o custo do erro é a editora corrigir um campo — que é o mesmo custo do erro do LLM.

### 7. Como as etapas acendem: reprocessamento seletivo, sem tocar no que já está pronto

**`versao_pipeline` não muda.** Ligar embedding não altera o texto nem a fronteira dos chunks —
altera uma coluna. Bumpar a versão reprocessaria extração, OCR e chunking dos 43 documentos para
nada, e usaria a versão do pipeline como "flag de já rodou".

Isso obriga uma correção de rumo sobre o ADR-0005, que registrou *"a dimensão 1536 fica registrada
em `chunks.versao_pipeline`"*: **a versão do modelo de embedding precisa de campo próprio**,
`chunks.versao_embedding smallint null`. Com a dimensão colada em `versao_pipeline`, trocar de
modelo de embedding — que o próprio ADR-0005 antecipa como "reindexação completa" — forçaria a
reextração de tudo. Migração para o `eng-supabase`; `NULL` significa "sem embedding".

O acendimento é então, literalmente, um comando:

```
reprocessar --estagio=embedding --onde="embedding is null"
```

que enfileira lotes por `job.enfileirar` (ADR-0026), roda com o worker, e o painel do item 4 vai
a zero. A busca passa a ter duas listas sem nenhuma mudança na função de fusão. A mesma coisa para
`--estagio=classificacao --onde="metadados = '{}'"`, com uma diferença que **não é negociável**:
classificação sobre documento **já publicado** não altera nada sozinha — ela propõe, e a editora
confirma. Nenhum documento muda de tipo, data ou visibilidade porque um modelo foi ligado.

### 8. Por que isto não vira dívida escondida — os três amarradores

1. **Quem usa vê.** O item 4 põe o estado desligado na tela de todo dia. Dívida escondida é dívida
   que só o desenvolvedor conhece.
2. **É medido, não lembrado.** "Chunks sem embedding" é uma contagem no mesmo painel da sentinela
   do ADR-0026, não uma anotação num backlog.
3. **É um corte datado no plano.** `docs/f1-plano.md` traz o acendimento como o corte **C9**, com
   pré-condição nomeada (existir chave e teto de custo mensal — SPEC §8.7), e **fora da definição
   de pronto de F1**. F1 fecha completo sem ele; C9 é adição, não conclusão.

## Consequências

- F1 entrega busca que **acha o termo exato e a referência** ("art. 12", "AGE de março", nome de
  fornecedor) — que é, segundo o próprio ADR-0005, a metade em que a busca vetorial falha e o erro
  é fatal em documento legal. A metade que fica faltando é a que erra menos perigosamente.
- Custo recorrente de F1 **cai**, não sobe: sem LLM e sem OCR pago (ADR-0024), o pipeline inteiro
  custa banda e eletricidade. Nada a escalar no §1.2.
- Existe risco real de a busca léxica decepcionar em pergunta normativa ("posso ter cachorro?" não
  casa com "é vedada a permanência de animais nas áreas comuns"). Mitigação de F1: sinônimos,
  o estado vazio honesto e o leitor por artigo — a pessoa que chega ao Regimento navega por
  artigo mesmo sem busca semântica. Se ainda assim doer, isso é o argumento de custo/benefício
  para comprar a chave, medido em buscas com zero resultado, e não uma suposição.
- O adaptador `Desligado` precisa de teste. Sem teste, ele é o `if` disfarçado de arquitetura.

## Alternativas descartadas

- **Embedding local (modelo pequeno rodando na máquina).** Tentador, e a estrutura deste ADR o
  acomoda depois sem mudança. Descartado para F1 por uma razão específica: modelo local de
  qualidade inferior produz uma metade semântica **ruim**, e uma lista ruim dentro do RRF **piora**
  o resultado com aparência de funcionalidade completa — pior do que a lista ausente, que ao menos é
  declarada. Se voltar, volta com avaliação de recall antes de entrar no RRF (a skill
  `rag-citacao-juridica-ptbr` tem o protocolo).
- **Esperar a chave e entregar F1 completo depois.** Trava um acervo inteiro atrás de uma decisão
  de compra. O fim de F1 já é produto útil sozinho (SPEC §9) — com busca léxica, é.
- **Vetor de zeros / classificação padrão para "manter o formato".** Detalhado no item 3. É a forma
  clássica de a dívida virar bug de qualidade indetectável.
- **Flag por variável de ambiente.** Muda por deploy, não é visível de dentro do produto e não dá
  para a UI ler. `configuracoes` já existe, é auditada e a editora pode ver.
- **Bumpar `versao_pipeline` ao ligar embedding.** Reprocessa 43 documentos inteiros para preencher
  uma coluna.

## Status

Aceito, 2026-09-06. Corrige o registro de dimensão do ADR-0005 (campo próprio `versao_embedding`).
Migração: `eng-supabase`. Acendimento: corte C9 de `docs/f1-plano.md`, fora da definição de pronto
de F1.
