# Medição: OCR local (Apple Vision) sobre a Convenção registrada

Data: 2026-09-06. Ferramenta: `scripts/ocr/vision_ocr.swift`, 300 DPI, `VNRecognizeTextRequest`
revisão 3, `pt-BR` + `pt-PT`, correção de linguagem ligada. Máquina: macOS 26.6.2, Apple Silicon.
Documento: `Breeze-Bosque-da-Saude-Convencao-de-Condominio-registrada.pdf`, 18 páginas,
**0 caractere de camada nativa** — escaneado puro.

Esta medição existe para dar base factual à revisão do ADR-0006 (que escolheu API paga partindo de
premissa que o acervo real não confirma) e para dizer, com número, quando a API paga volta a ser
necessária.

## Resultado bruto

| métrica | valor |
|---|---|
| páginas processadas | 18/18 |
| tempo total | 22 s (~1,2 s/página) |
| custo | R$ 0,00 |
| dado enviado para fora da máquina | nenhum |
| linhas reconhecidas | 945 |
| caracteres extraídos | 58.566 (~3.250/página) |
| confiança média por linha | 0,985 |
| confiança mediana | 1,000 |
| linhas com confiança < 0,9 | 26 (2,8%) |
| linhas com confiança < 0,5 | 5 (0,5%) |

**As 26 linhas de baixa confiança são quase todas marcadores de item de uma ou duas letras**
(`a)`, `c)`, `f)`, `K)`) — string curta é ambígua por natureza para o reconhecedor. Duas são ruído
de selo de cartório na última página (`ОСОВАРСО`, em cirílico). **Nenhuma é parágrafo de texto
corrido com confiança baixa.**

## Erros sistemáticos encontrados (amostragem manual de 4 páginas)

| classe | exemplo | frequência | risco |
|---|---|---|---|
| **marcador de lista romano** | `ii.` → `il.`, `iii.` → `li.`, `o)` → `0)` | 6 ocorrências claras | **Alto** — o marcador é a unidade de citação da Convenção |
| expoente | `m²` → `m?` | 25 | Baixo para busca, médio para o trecho literal exibido |
| acento perdido | `Síndico` → `Sindico`, `domínio` → `dominio` | dezenas | Baixo — `unaccent` na config `public.pt_br` (ADR-0005) neutraliza na busca |
| barra virando letra | `manobrista/garagista` → `manobristalgaragista` | 2 | Baixo |
| palavra corrompida | `comuns` → `comans`, `área` → `prea` | esparso | Baixo |
| ordem de leitura em diagrama | rótulos de planta baixa (`RECHO CARRAL`) | 1 página | Médio — vira ruído dentro do chunk |

Qualidade do texto corrido, verificada contra o PDF em passagem juridicamente sensível (quórum de
instalação e de deliberação, pág. 12): **correta**, incluindo `2/3 (dois terços)`, `90% (noventa
por cento)` e a lista completa de competências da AGO. O que falhou nessa mesma página foram os
marcadores (`il.` por `ii.`), não o conteúdo.

## Achado que muda a regra de citação

**A Convenção do Breeze não é articulada.** Só 2 ocorrências de `Art.` em 58 mil caracteres: a
estrutura é `1. CONDIÇÕES GERAIS` → item `a)` → subitem `i.`. O Regimento Interno, esse sim, tem
191 artigos. A skill `rag-citacao-juridica-ptbr` e o SPEC §4 pressupõem citação por artigo — para a
Convenção, a unidade citável é **cláusula + item + página**, e o item é exatamente o token que o
OCR erra. Consequência direta para F1: o normalizador de marcador de lista (o item seguinte a `i.`
é `ii.`, o seguinte a `n)` é `o)`) não é polimento, é pré-requisito de citação correta.

## O normalizador de marcador, medido contra o mesmo texto

`lib/ocr/marcadores.ts` (testes em `tests/unit/ocr-marcadores.test.ts`) roda sobre a saída bruta.
Resultado sobre as 945 linhas: **26 marcadores corrigidos, 42 linhas sinalizadas** para conferência
humana. As 26 correções foram lidas uma a uma contra o PDF — todas certas, incluindo as quatro da
página 12 (quórum), que era a passagem de maior risco.

O que esse exercício ensinou vale mais que o número: **as duas primeiras versões do módulo
acertavam mais e corrompiam junto.** A primeira "corrigia" `VI. ADMINISTRAÇÃO DO CONDOMÍNIO`
(título de capítulo) para `ii. ADMINISTRAÇÃO DO CONDOMÍNIO`, absorvendo um título na lista de
subitens aberta acima — caixa é nível hierárquico, não estilo. A segunda fazia pior: quando o OCR
perdia um marcador no meio da lista (o `xi.` da página 8), a contagem dessincronizava e **todos os
itens seguintes, que estavam corretos, eram renumerados para trás** — `xvi.` virava `xv.`, `xvii.`
virava `xvi.`, em cascata. Um item não lido corrompia o resto do capítulo.

Nenhum dos dois apareceu em teste unitário escrito antes; os dois apareceram ao rodar sobre o
documento real e ler a saída. Ambos estão travados como teste de regressão agora. A regra que
sobrou é conservadora por decisão: **token que já é um marcador válido nunca é reescrito** — se a
sequência está dessincronizada, o certo é sinalizar a lacuna, não renumerar o documento.

## Critério de descarte — quando a API paga volta

O OCR local é aceito **como camada de proposta**, nunca como fonte publicável direta (a
conferência humana já era obrigatória por SPEC §3.5 e §5.1). Voltar para API paga se, em qualquer
documento futuro:

1. a confiança média por página cair abaixo de **0,90**, ou mais de **10%** das linhas ficarem
   abaixo de 0,6; ou
2. a conferência humana precisar corrigir mais de **1 em cada 20 linhas** de texto corrido; ou
3. entrar no acervo documento anterior a 2025, com scan torto ou abaixo de 200 DPI — o cenário que
   o ADR-0006 descreveu e que este acervo não tem; ou
4. o documento for balancete escaneado e a extração de tabela for necessária — Vision devolve
   linhas, não estrutura de tabela, e F2 depende disso.

O item 4 é o mais provável de disparar primeiro: é F2, não F1.

## Segundo documento escaneado

`COMUNICADO FACIAL.pdf` (1 página) também foi processado localmente: 64 linhas, confiança média
1,000. **Não contém dado biométrico** — é aviso de que o cadastro facial passou a ser feito pelo
app "Guardia Portaria" (Tecnorise), com links de loja. Duas observações que não são desta fase:
a ordem de leitura saiu embaralhada (é um pôster com mockup de celular sobreposto), e o fato de o
condomínio ter contratado um serviço terceiro que coleta biometria de morador é assunto de
`juridico-lgpd` sobre o condomínio — não sobre o Breeze, que só indexa o comunicado.
