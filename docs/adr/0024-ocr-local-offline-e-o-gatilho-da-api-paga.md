# ADR-0024 — OCR local offline (Apple Vision) como motor primário; API paga só por gatilho nomeado

> **Substitui parcialmente o ADR-0006** (item 3 da Decisão e a 1ª alternativa descartada).
> Os itens 1, 2 e 4 do ADR-0006 continuam valendo integralmente.

## Contexto

O ADR-0006 escolheu OCR por API paga sobre uma premissa explícita: *"scan torto e abaixo de
200 DPI, que é justamente o acervo antigo do condomínio"*. **A premissa é falsa.** A sondagem dos
43 PDFs reais (`docs/inventario-acervo.md`) mediu:

- **Nenhum documento é anterior a 2025.** O condomínio foi entregue em dez/2025 (D10). Não existe
  "acervo antigo" — existe acervo de oito meses, produzido em impressora e PDF nativo moderno.
- **2 de 43 arquivos são escaneados de verdade** (0 caractere extraído): a **Convenção registrada**
  (18 páginas) e um **"COMUNICADO FACIAL"** (1 página). 19 páginas, ~4,4% do acervo.
- **Nenhum documento tem o padrão mais traiçoeiro** que o ADR-0006 temia (texto nativo herdado de
  OCR antigo ruim): `repl_ratio = 0` em todas as páginas dos 6 falsos "MISTO".

O ADR-0006 descartou motor local por qualidade em condição que este acervo não tem. E o custo real
da API paga nunca foi o dinheiro (R$5 no lote inteiro): é **enviar documento do condomínio para
fora**, o que exige contratar o fornecedor como operador LGPD, entrada no registro de operações e
uma cláusula de transferência. Para 19 páginas. Uma delas é um comunicado sobre **reconhecimento
facial** — se o documento contiver dado biométrico, é dado sensível (LGPD art. 11) e o tratamento
por terceiro sobe de categoria.

## Decisão

### 1. O motor primário é OCR local, offline

Substitui o item 3 do ADR-0006. A etapa de OCR passa a rodar **na máquina do mantenedor, sem rede**,
via Apple Vision (`VNRecognizeTextRequest`, idioma `pt-BR`, nível `accurate`) exposta por um
executável Swift próprio. Custo monetário zero, nenhum byte sai da máquina, nenhum contrato de
operador, nada a registrar como transferência.

Continuam valendo sem alteração: extração nativa sempre primeiro (item 1), `texto_nativo`
preservado, `documento_paginas.texto` como texto efetivo (item 4), `confianca_ocr` por página, e a
**regra dura de que valor financeiro nunca é aceito direto do OCR**. Trocar o motor não muda nada
disso — o modo de falha "troca de dígito" existe em qualquer OCR, pago ou não.

### 2. OCR é uma porta; o motor local é um adaptador

O worker **não chama Apple Vision**. Chama uma interface `MotorOcr` com uma implementação por
processo filho (JSON por stdin/stdout, um processo por página). Três razões, nesta ordem:

1. **É o que torna a queda para API paga uma troca de configuração, e não uma reescrita.** Sem a
   porta, "só caio para a API se não servir" é intenção, não plano.
2. Mantém o worker Node **portável**. A dependência de macOS fica confinada a um executável.
   O dia em que o worker virar container Linux (ADR-0007, ~R$15/mês), só este adaptador precisa de
   resposta — os outros estágios seguem.
3. Um processo por página isola falha: OCR que trava ou estoura memória mata o filho, não o worker.

`documento_paginas` precisa registrar **qual motor** produziu o texto, não só a classe
(`fonte_texto` já diz `nativo`/`ocr`/`misto`/`vazio`). Sem isso, "reprocessar só o que o motor
local errou" não é expressável como consulta, e a queda para API paga vira varredura manual.
Migração para o `eng-supabase`: coluna `documento_paginas.motor_texto text` com valor do tipo
`nativo`, `vision:<versão do SO>`, `api:<fornecedor>:<modelo>`.

### 3. O gatilho da API paga — explícito, medível, por documento

A API paga volta quando **qualquer uma** destas condições ocorrer. Nenhuma delas é "achei que
ficou ruim".

| # | Gatilho | Como se mede | O que acontece |
|---|---|---|---|
| **G1** | Sequência de artigos incompleta na Convenção | Os cabeçalhos `Art. N` saem em sequência sem buraco? Buraco > 5% dos artigos reprova. Verificação mecânica, não opinião. | Uma retentativa com rasterização melhor (300 DPI, deskew). Persistindo, API paga **para este documento**. |
| **G2** | Erro que muda sentido, na conferência humana | A editora confere 3 páginas sorteadas + todas as que a Convenção usa para quórum, prazo e número. Qualquer erro que altere sentido (número, negação, prazo, quórum) reprova. | Idem G1. |
| **G3** | Documento futuro que o motor local não alcança | Manuscrito, foto torta, fax, carimbo sobre texto — `confianca_ocr` baixa **e** conferência confirmando ilegível. | API paga para aquele documento, depois do contrato de operador existir. |

**A queda é por documento, não pelo acervo.** Cair uma vez não reabre esta decisão: reabre só se G3
ocorrer de forma recorrente (mais de 3 documentos em 3 meses), e aí o item para reavaliar é o
motor primário, com ADR novo.

**Pré-requisito que não pode ser esquecido:** no dia em que G1/G2/G3 disparar, o contrato de
operador LGPD e a entrada no registro de operações **ainda não existem** — eles saíram do escopo
justamente por causa desta decisão. O `juridico-lgpd` tem lead time aqui. Por isso a sonda de OCR
da Convenção é a **primeira tarefa de F1** (`docs/f1-plano.md`, corte C0), antes de qualquer código
de produto: é uma decisão com prazo jurídico atrás dela.

### 4. A heurística de disparo perde autoridade, e ganha precisão

O ADR-0006 item 2 disparava OCR por `< 100 caracteres úteis/página` **ou** razão alta de gibberish.
Com dados reais, o limiar automático sinalizou **6 falsos positivos em 43** — todos por baixa
densidade de formato (sumário pontilhado, tabela numérica, capa espaçada, formulário em branco,
slide). Com OCR pago, o custo do falso positivo era dinheiro. Com OCR local, o custo é pior:
**sobrescrever texto nativo correto com OCR**, que é exatamente a degradação que o ADR-0006 queria
evitar.

Decisão: separar os dois ramos.

- **Automático, sem perguntar:** só quando a extração nativa devolve ~0 caractere útil (`vazio`).
  Não há o que degradar. Pegou os 2 casos reais, zero falso positivo.
- **Proposta à curadoria, nunca ação:** a faixa de gibberish e a de baixa densidade viram
  sinalizador na tela de conferência ("esta página tem pouco texto — rodar OCR?"). A editora
  decide. Custo do erro: um clique.
- **`texto_nativo` nunca é sobrescrito**, e OCR só substitui `texto` quando o nativo é `vazio` ou
  quando a editora mandou. Reverter é trocar `texto` de volta, sem reprocessar nada.

Os dois limiares continuam em `configuracoes`, não em código (ADR-0006).

## Consequências

- **Custo de OCR do acervo: R$0.** O item de R$50–300 do SPEC §1.2 sai do orçamento único.
  Não muda o custo recorrente (~R$300/mês), então não há nada a escalar.
- **Nenhum operador LGPD a contratar em F1**, nenhuma transferência a registrar, e o comunicado de
  reconhecimento facial não é enviado a terceiro nenhum. Não sendo enviado, a dúvida sobre dado
  biométrico deixa de ser urgente — continua sendo item de revisão do `juridico-lgpd` sobre o
  conteúdo publicado, não sobre o processamento.
- **Um estágio do pipeline fica acoplado ao macOS.** É acoplamento real e assumido. Hoje custa
  zero porque o worker já roda na máquina do mantenedor (ADR-0025) e porque quem sobe documento é
  a mesma pessoa que tem a máquina (D4). Deixa de custar zero no dia em que o worker sair da
  máquina — e esse dia tem resposta escrita: outro adaptador da mesma porta.
- **Contradiz o argumento "sem binário nativo" do ADR-0006/ADR-0007, e isso é deliberado.** O
  argumento era bom contra Tesseract (binário a compilar, modelos a versionar, qualidade pior).
  Apple Vision é do sistema operacional: não se instala, não se versiona, não se compila além de um
  executável de 100 linhas. O custo que o argumento protegia não existe aqui.
- A conferência humana **não** fica mais barata por o OCR ser local. Continua obrigatória
  (SPEC §5.1, §3.5). O que muda é que reprocessar é grátis, então a editora pode mandar rodar de
  novo sem calcular custo.

## Alternativas descartadas

- **Manter a API paga (ADR-0006 original).** Pagar contrato de operador, registro de transferência
  e revisão jurídica para 19 páginas — sendo uma delas possivelmente biométrica. O trabalho de
  conformidade custa muito mais que os R$5.
- **Tesseract.** O motivo do ADR-0006 continua parcialmente de pé (qualidade inferior), e agora
  soma um motivo novo: exige instalar e versionar binário e modelos, enquanto o motor do sistema
  já está na máquina. Fica como o adaptador de reserva se o worker for para Linux antes de haver
  contrato de operador.
- **Modelo multimodal local (Qwen-VL, etc.) para OCR.** Peso de instalação e VRAM
  desproporcionais a 19 páginas, e alucinação de dígito é um modo de falha **pior** que o do OCR
  clássico: o OCR erra o caractere, o modelo inventa o número plausível. Em documento com valor,
  é a troca errada.
- **OCR em toda página.** Segue descartado pelo ADR-0006, agora com dado: degradaria 41 dos 43.
- **Adiar OCR para F2 e publicar a Convenção sem texto.** A Convenção é o único documento público
  e o texto normativo-mãe. Publicá-la como imagem não citável é entregar o acervo sem a peça que
  justifica o acervo.

## Veredito da sonda C0 — medido, 2026-09-06

Executada antes de qualquer código de produto, como o corte C0 exige. Ferramenta:
`scripts/ocr/vision_ocr.swift`, 300 DPI. Medição completa em
`docs/ocr/medicao-vision-convencao.md`.

**G1 não é aplicável como escrito, e isso é um achado, não uma formalidade.** O gatilho supõe
cabeçalhos `Art. N` na Convenção. Não existem: são **2 ocorrências de "Art." em 58.566
caracteres**. A Convenção do Breeze não é articulada — a estrutura é `cláusula 1.` → `item a)` →
`subitem i.`, e quem tem 191 artigos é o Regimento Interno. A unidade citável da Convenção é o
**item**, não o artigo, o que muda a regra de citação de F1 (SPEC §4 e a skill
`rag-citacao-juridica-ptbr` pressupõem artigo).

G1 foi substituído pelo critério mecanicamente equivalente: **continuidade da sequência de
marcadores de item**. Resultado sobre 945 linhas — 26 marcadores corrigidos automaticamente
(`lib/ocr/marcadores.ts`, todos conferidos um a um) e 46 linhas sinalizadas para conferência
humana. Nenhum buraco estrutural: o texto sai completo e ordenado.

**G2: aprovado, com a ressalva de quem conferiu.** Três páginas conferidas contra a imagem
renderizada da própria página — 12 (quórum de instalação e de deliberação), 14 (fundo de reserva e
penalidades) e 17 (vedações e disposições transitórias). **Nenhum erro que mude sentido.** Todos os
números conferem: `2/3`, `90%`, `3/4`, `5%`, `20%`, prazo de 3 dias, multa de até 5 vezes, `50%`,
`100%`, juros de `1%`, multa moratória de `2%`, IGP-M. O que aparece é corrupção de palavra sem
perda de sentido (`trabalistas realivos`, `intrator`, acento perdido em maiúscula) e ruído de selo
de cartório.

A ressalva: **quem conferiu foi o orquestrador contra a imagem da página, não a editora.** G2 pede
conferência humana e ela continua sendo o portão de publicação — esta sonda mostra que o material
chega em condição de ser conferido, não que já está conferido.

**A classe de erro que sobrou é o marcador de item** — 2 na página 14, 2 na página 17. Como o
marcador é a unidade de citação da Convenção, é ele que o normalizador trata, e é ele que a
conferência precisa olhar primeiro.

**Um custo assumido, não escondido.** O normalizador é deliberadamente conservador: nunca reescreve
um token que já é marcador válido, porque a versão que reescrevia renumerava em cascata todos os
itens seguintes a partir de um marcador que o OCR não leu. O preço é perder correção verdadeira: na
página 17, o `xviii.` lido como `xvii.` **não** é corrigido — fica sinalizado para a conferência.
Trocamos recall por não corromper numeração de convenção. Para um documento cuja citação é o
produto, é a troca certa.

**Conclusão: o motor local serve.** Nenhum dos gatilhos G1/G2 disparou. O `juridico-lgpd` **não**
precisa iniciar contrato de operador de OCR agora — o que era o custo de prazo desta decisão.

## Status

Aceito, 2026-09-06. **Substitui parcialmente o ADR-0006** (item 3 e a alternativa "Tesseract
self-hosted", esta última por mudança da premissa, não do mérito técnico). Registrar como D17 em
`docs/04-DECISOES.md`. Migração de `motor_texto`: `eng-supabase`. Sonda de qualidade (C0): **executada e aprovada em 2026-09-06** — ver "Veredito da
sonda C0" acima.
