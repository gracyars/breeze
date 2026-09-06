# ADR-0029 — Autenticação é o primeiro corte de F1; o backfill é máquina para ingerir, humano para publicar

## Contexto

O SPEC §9 lista `auth` como entrega de **F0**. F0 fechou (commit `c4d26bc`) com 24 migrações, RLS
auditada em quatro rodadas e 176/176 asserts — **e zero código de autenticação**. Não há cliente
Supabase, não há sessão, não há enrolamento de TOTP. O que existe é o schema e a RLS que *dependem*
do JWT: `app.eh_gestao()`, `app.eh_autenticado()`, o requisito de `aal2` para papel privilegiado
(ADR-0003/0012), `papeis` e `vinculos` com vigência.

Isso tem duas consequências que precisam de decisão, não de improviso:

1. **Nada de visibilidade autenticada é verificável ponta a ponta.** A suíte pgTAP simula o claim
   `aal` diretamente no JWT de teste — a dívida **D1** diz isso com todas as letras e a classifica
   como risco **alto**: nunca foi confirmado que o GoTrue só emite `aal2` **depois** da verificação
   do segundo fator, e não logo no enrolamento. Toda a autorização de `editor` e `conselho` repousa
   nessa suposição.
2. **O backfill dos 43 PDFs** pode ser feito por script com `service_role`, que ignora RLS por
   construção — e portanto **não prova nada** sobre visibilidade, e não pode publicar sem
   atropelar a confirmação humana do SPEC §3.5.

## Decisão

### 1. Auth é o corte C1 de F1, antes de qualquer código de acervo

Magic link (com CPF como alias que resolve no e-mail cadastrado — D2), enrolamento e verificação de
TOTP, `aal2` de verdade, códigos de recuperação impressos (D9), cliente Supabase de servidor e
sessão na aplicação.

Três razões, em ordem:

1. **Fecha D1, que é risco alto e não fecha de outro jeito.** O teste é literalmente: entrar, olhar
   o claim `aal` do JWT logo após o enrolamento e antes da primeira verificação. Se o GoTrue emitir
   `aal2` cedo, **todo o modelo de autorização de F0 está mais fraco do que 176 asserts sugerem** —
   e essa é uma informação que vale antes de construir seis cortes em cima dela, não depois.
2. É a peça menor de F1 e destrava a verificação de todas as outras. Sem sessão, cada tela de
   curadoria seria construída contra um mock e validada de verdade só no fim.
3. Publicação exige `editor` com `aal2` (RLS), e publicação é o passo final do backfill. Auth não é
   pré-requisito do backfill inteiro — é pré-requisito do que dá valor a ele.

**Valor observável ao fim de C1:** a mantenedora entra com e-mail e segundo fator, vê o próprio
nome e o papel `editor`, e o acervo vazio. Parece pouco; é o primeiro momento em que o sistema
existe para uma pessoa.

**Correção proposta ao SPEC §9** (não aplicada — §9 está fora do escopo de escrita do `arquiteto`;
fica para o orquestrador aprovar, no espírito do ADR-0016): *F0 — Fundação: repo, ambientes, schema,
RLS + testes de policy, design tokens.* / *F1 — Acervo: **autenticação**, upload, pipeline de
ingestão, backfill, busca híbrida, leitor.* Registrar assim é melhor do que fingir que F0 entregou:
o veredito de F0 é honesto sobre o que cobriu, e a fase não deve carregar um item que não existiu.

### 2. O backfill se divide onde a natureza do trabalho se divide

> **Script com `service_role` para o que é máquina. UI autenticada para o que é julgamento.
> Nenhum documento é publicado por `service_role`, nunca.**

| Metade | Como | Faz o quê | Termina em |
|---|---|---|---|
| **Ingestão** | script local, `service_role`, na máquina da mantenedora | envia os 43 arquivos ao bucket, cria as linhas, roda hash/dedupe, extração, OCR, chunking, indexação léxica | `status = 'em_revisao'`, **nada publicado** |
| **Conferência** | UI, sessão `editor` com `aal2` | confirma tipo, data, competência, visibilidade, fronteiras de página, publica | `status = 'publicado'` |

Por que o script não publica, ainda que tecnicamente pudesse (`service_role` tem `UPDATE` em
`documentos`): publicar é o ato em que uma pessoa assume responsabilidade pelo que os moradores vão
ler. `documentos_publicacao_ck` já exige `publicado_por`; a trilha do ADR-0013 quer um ator; e a
confirmação humana antes de publicar é o SPEC §3.5. Um script que publica 43 documentos "para
adiantar" apaga exatamente a etapa que dá autoridade ao acervo.

**Uma exceção ao "script cria a linha", registrada:** `service_role` **não tem `INSERT` em
`documentos`** (baseline 06, deliberado: "criação e arquivamento continuam humanos"). O script de
ingestão portanto **autentica como a editora** para criar as linhas — usa a mesma sessão da UI, por
API — e usa `service_role` apenas para os estágios de máquina (páginas, chunks, fila), que é
precisamente o conjunto de `GRANT`s que o achado V4 concedeu. O schema já dizia onde fica a
fronteira; o script obedece em vez de contorná-la. *Isso torna C1 pré-requisito também da ingestão,
não só da publicação — e reforça a ordem.*

### 3. A conferência de 43 documentos, desenhada para uma pessoa só

D4 é o fato dominante: **um editor, humano, e o gargalo de publicação é ele.** Se a conferência for
enfadonha, o produto morre de backlog — não por bug, por desistência. Sete decisões de desenho, e
elas são arquiteturais porque determinam o que o schema e as telas precisam suportar:

1. **Fila, não lista.** Um documento por vez, com "próximo", e progresso visível ("12 de 43").
   Uma grade com 43 linhas parece dever de casa; uma fila com contador parece progresso.
2. **Ordem por valor, não alfabética.** A fila é ordenada para que as primeiras conferências já
   produzam produto: Regimento (público, é a peça-chave e o canônico do ADR-0028), Convenção (depois
   do OCR), as 5 atas, os 3 balancetes. Dez documentos.
3. **Depois do décimo, o produto liga.** A busca léxica e o leitor (corte C6) entram **entre** os
   dez primeiros e os 33 restantes. A décima conferência é onde a mantenedora para de alimentar um
   banco de dados e começa a usar o próprio produto. É a resposta direta a "não desistir no
   décimo": o décimo é a recompensa, por sequenciamento, não por força de vontade.
4. **Lote para o que é homogêneo.** Os 24 comunicados de 1–3 páginas, mesmo tipo e mesma
   visibilidade, entram numa tela de 8 por vez com miniatura, título e tipo proposto, cada um
   desmarcável individualmente. Continua sendo confirmação humana (SPEC §3.5) — a pessoa vê e
   aprova cada item —, sem 24 carregamentos de tela.
5. **Zero digitação no caminho feliz.** Título, tipo e data vêm de regra determinística sobre o
   nome do arquivo, que neste acervo é estruturado (`2215 - BREEZE AGE 04.02.2026 site.pdf`,
   `PrestContas janeiro 2026.pdf`). Sem LLM (ADR-0027), e cobrindo a maior parte do lote.
6. **Parar no meio é normal.** `status = 'em_revisao'` já persiste o estado; a fila é retomável a
   qualquer momento, sem assistente de sessão única, sem "perdi tudo".
7. **Nada bloqueia nada.** A Convenção esperando OCR e conferência não segura os outros 42. Um
   documento em `erro` fica na fila com o erro à vista e um botão de reenfileirar (ADR-0026),
   não some.

**O acervo real já entrega dois presentes para essa fila**, e vale registrar porque servem de teste
de aceitação com dado verdadeiro: o par de lembretes de AGE byte-idênticos (#15/#16) faz a fila
mostrar **42 e não 43**, dizendo por quê — a `unique` de `sha256` funcionando à vista; e a ata AGE
de 36 páginas é o único item da fila com passo extra (fronteira de páginas do ADR-0028), o que dá à
mantenedora a experiência de que o caso difícil é raro, não a regra.

### 4. Onde o backfill roda e contra o quê

Na máquina da mantenedora, contra o **stack local primeiro** (`supabase start`) — o acervo inteiro,
os 43, ponta a ponta, antes de existir produção. Isso transforma o backfill em teste de integração
de tamanho real, de graça, e é a única forma de descobrir os defeitos de extração e chunking com
dados verdadeiros antes de haver dado verdadeiro publicado.

Quando houver projeto remoto, o mesmo script roda de novo contra ele. Rodar duas vezes é seguro por
construção (ADR-0025) e não é retrabalho de conferência: a conferência de produção pode reaproveitar
`metadados` exportados do local. Se o remoto não vier em F1, o produto simplesmente vive no local —
o que também é a resposta honesta para a dívida **D2** (comportamento em Supabase hospedado não
confirmado), que continua aberta e **não bloqueia F1**.

## Consequências

- **A ordem de F1 fica determinada por dependência real, não por preferência:** OCR sonda → auth →
  ingestão de um documento → OCR no pipeline → reindexação garantida → dez documentos conferidos →
  busca e leitor → 33 restantes → anexo replicado. Detalhado em `docs/f1-plano.md`.
- Se a sonda de C1 mostrar que o GoTrue emite `aal2` cedo demais (D1), **é achado bloqueante de F1**
  e volta para o `arquiteto` + `auditor-rls` antes de qualquer tela de curadoria — a alternativa
  seria construir seis cortes sobre uma autorização mais fraca do que se acredita.
- O script de ingestão e o worker compartilham o código de pipeline (ADR-0007: "ambos rodam o mesmo
  código, parametrizado"). O script é um enfileirador em lote + o worker rodando até a fila esvaziar,
  não um caminho paralelo. Se divergirem, o backfill deixa de ser teste de nada.
- **F1 exige um papel que o time não tem.** Os agentes existentes são `arquiteto`, `eng-supabase`,
  `auditor-rls`, `devops`, `design-system`, `juridico-lgpd` e `guardiao-dominio` — nenhum escreve
  Next.js nem worker Node. Auth, UI de curadoria, busca, leitor e o próprio worker precisam de dono.
  **Isso é decisão do orquestrador**, não do arquiteto; registrado aqui porque é a maior dependência
  não resolvida do plano.

## Alternativas descartadas

- **Backfill primeiro, auth depois.** Encheria o banco com 43 documentos cujo estado de visibilidade
  nunca foi exercido por uma sessão real, e deixaria D1 aberta sob seis cortes de código. Se o
  modelo de `aal2` estiver errado, descobre-se com o acervo dentro em vez de com ele vazio.
- **Publicar por script e conferir depois.** Inverte a garantia central do produto: o acervo estaria
  público antes de alguém ter olhado. Contra o SPEC §3.5 e contra a razão de o produto existir.
- **Upload dos 43 pela UI, um por um, sem script.** 43 uploads manuais que a máquina faz melhor —
  e consome, no trabalho mecânico, a paciência que é o recurso mais escasso do projeto (D4).
- **Conferir tudo e só então entregar busca.** Põe a recompensa depois do trabalho inteiro. Cortar
  a busca entre o décimo e o décimo primeiro documento custa nada tecnicamente e muda a experiência
  por completo.
- **Adiar auth para depois da busca, usando um "modo local sem login".** Criaria um segundo caminho
  de acesso sem RLS, exatamente o tipo de atalho que vira permanente. A fronteira única de
  autorização é o ADR-0012; um bypass de desenvolvimento é um furo nela.

## Status

Aceito, 2026-09-06. Propõe correção ao SPEC §9 (auth de F0 → F1), **não aplicada** — depende do
orquestrador. Sequência completa em `docs/f1-plano.md`. Fecha D1 quando C1 for entregue.
