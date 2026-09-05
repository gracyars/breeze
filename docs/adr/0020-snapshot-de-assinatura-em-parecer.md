# ADR-0020 — Snapshot do nome do signatário em `parecer_signatarios`, e o critério que autoriza denormalizar PII

## Contexto

`parecer_signatarios` guarda `(parecer_id, pessoa_id, assinado_em)`. A identidade de quem assinou
existe **exclusivamente** em `pessoas.nome`, por chave estrangeira. O `auditor-rls` demonstrou no
banco: rodada a anonimização, o signatário do parecer vira "ANONIMIZADO".

Por que isso pesa mais do que parece: com editora única (D4), **o parecer do conselho é a peça de
contrapeso** — é o julgamento independente que dá credibilidade a um sistema operado por quem
seria auditada (Risco §8.6). Parecer sem signatário identificável não tem valor probatório nenhum.
Perder o nome não degrada o registro: destrói a função dele.

O caso é concreto, não hipotético. Um conselheiro que depois vende o apartamento é, ao mesmo
tempo, ex-morador com direito à eliminação (LGPD art. 18) e signatário de ato cuja assinatura,
segundo o `juridico-lgpd` (`docs/juridico/off-boarding-ex-morador.md` §4), **nunca se anonimiza**
— "assinatura é a validade do parecer (CC art. 1.356); LGPD art. 16, I". As duas regras incidem
sobre a mesma pessoa.

O `auditor-rls` isolou o conflito e **deliberadamente não escreveu teste vermelho**, para não
forçar uma das saídas por acidente. Foi a escolha certa: teste é o mecanismo que congela decisão,
e esta não estava tomada.

## A fronteira legal, confirmada com o `juridico-lgpd`

O parecer dele já fixa a resposta e este ADR não a reabre, só a implementa:

- Retenção contra pedido de eliminação tem base em **LGPD art. 16, I** — cumprimento de obrigação
  legal ou regulatória. Não é exceção discricionária: exige que a obrigação exista.
- A obrigação aqui é a validade do próprio ato (**CC art. 1.356**, conselho fiscal) somada ao
  dever de prestação de contas (**CC art. 1.348, VIII**), que é a base legal do produto inteiro
  (SPEC §7).
- Lista fechada do que **nunca** se anonimiza, no §4 daquele parecer: `pareceres` /
  `parecer_signatarios`; nome em ata, deliberação e voto; `lancamentos` e `cobrancas` do período;
  `audit.log`.
- Tudo o mais da PII cadastral do ex-morador é anonimizado em `vinculos.fim + 5 anos`.

**Até onde a validade do ato justifica reter** — o limite, e ele é estreito: justifica reter o
**mínimo que torna o ato atribuível**, não o cadastro da pessoa. Nome e a qualificação em que
assinou, sim. CPF, e-mail, telefone, unidade: **não** — nada disso é elemento da assinatura, e
retê-los sob esse pretexto seria usar uma exceção legal estreita como guarda-chuva (LGPD art. 6º,
III, necessidade). Essa distinção é a decisão de desenho deste ADR.

## Decisão

**(a) Snapshot, com escopo fechado.** Em `parecer_signatarios`:

```sql
alter table public.parecer_signatarios
  add column nome_signatario text,   -- snapshot, congelado no momento da assinatura
  add column qualificacao    text;   -- em que qualidade assinou: "Conselho fiscal, mandato 2026/2028"
```

Regras que fazem disto um snapshot, e não uma cópia solta:

1. **`pessoa_id` permanece.** A FK não é substituída — ela é a chave técnica dos agregados
   (`juridico-lgpd` §4: "`pessoa_id`: preservar sempre"). O snapshot **coexiste** com a
   referência: a FK liga, o snapshot atesta. Desambiguação de homônimo é técnica, por `pessoa_id`,
   não por acumular mais PII no snapshot.
2. **Congela na assinatura, não na criação da linha.** Trigger preenche `nome_signatario` e
   `qualificacao` quando `assinado_em` deixa de ser nulo. Antes disso não há ato, e portanto não
   há o que congelar — um rascunho com signatário previsto não gera retenção.
3. **Imutável depois de preenchido.** Trigger rejeita `UPDATE` das duas colunas. Snapshot que pode
   ser reescrito não é snapshot; e aqui a imutabilidade é o objetivo, não efeito colateral.
4. **Só nome e qualificação.** Proibido acrescentar CPF, e-mail, telefone ou unidade a esta tabela
   — ver a fronteira legal acima.
5. **Fora do alcance da rotina de anonimização, por construção.** A rotina atua em `pessoas`; estas
   colunas não vivem lá. É a diferença entre depender de um `WHERE ... NOT IN (signatários)` que
   alguém precisa escrever certo e não haver nada a excluir.
6. **A recusa de eliminação precisa ser dizível ao titular.** Reter contra pedido do titular exige
   justificar a ele. Consequência operacional, não opcional: a resposta a pedido de eliminação
   enumera o que permanece e sob qual base — e o registro de operações (RIPD) traz esta retenção
   com fundamento em LGPD art. 16, I. Item para `juridico-lgpd` e `devops` (runbook), não para o
   schema.
7. **Escopo travado:** este ADR autoriza o snapshot **em `parecer_signatarios` e em mais nada**.
   Qualquer outro precisa de ADR próprio passando nos três testes abaixo.

## O critério — três testes cumulativos

Este é o item que vai ser citado por analogia. Denormalizar PII exige **os três**, não a maioria.

| # | Teste | Pergunta | Falha típica |
|---|---|---|---|
| 1 | **Constituição** | O dado **é elemento do ato**, sem o qual o ato deixa de existir juridicamente? | "É útil na tela", "evita um join", "fica mais rápido" |
| 2 | **Irreversibilidade legítima** | Existe base legal que **impede** eliminar a pedido do titular (LGPD art. 16), nomeável em artigo? | "Seria uma pena perder o histórico" |
| 3 | **Congelamento** | O valor correto é o **do momento do ato** — e atualizar o dado atual **não** deveria propagar? | Se corrigir o nome (casamento, retificação) deveria refletir, é referência, não snapshot |

Qualquer "não" ⇒ **FK para `pessoas`**, e a anonimização propaga como deve.

Aplicando ao próprio schema, que é como o critério ganha utilidade:

| Caso | T1 | T2 | T3 | Veredito |
|---|:--:|:--:|:--:|---|
| `parecer_signatarios.nome_signatario` | sim | sim (CC 1.356 + LGPD 16, I) | sim — quem assinou assinou com aquele nome | **Snapshot** |
| `questionamentos.autor_id` | não — o texto do questionamento vale por si; a autoria é referência | — | — | FK |
| `documentos.publicado_por`, `lancamentos.criado_por` | não — a proveniência é sustentada por `pessoa_id` e pela cadeia de hash, não pelo nome legível | — | — | FK |
| `alertas.resolvido_por` | não | — | — | FK |
| Nome em ata / deliberação | não se aplica: o nome está **dentro do texto do documento**, não em coluna estruturada. Permanece porque o documento não é reescrito (SPEC §6.3) | — | — | Nem FK nem snapshot |

**Terceiro teste é o mais útil na prática**, porque não exige juízo jurídico: separa *cache* de
*snapshot*. Se você ficaria incomodado com o dado ficando desatualizado, é cache — e cache de PII
é dívida, não decisão.

### Por que isto não é precedente para "denormalizar PII é aceitável"

Porque o teste 1 é quase sempre "não". A denormalização aqui é autorizada **porque o dado é parte
do ato jurídico**, não porque é conveniente, nem porque a estrutura é imutável. A imutabilidade
não justifica nada — ela é justamente o que torna o erro irreparável.

O contraste com o **V9** é o melhor uso do critério: `audit.log.antes/depois` copia
`pessoas.nome` para dentro de uma cadeia de hash, de onde não sai. Esse dado **falha T1** (é
registro de mudança, não elemento de ato) e **falha T3** (o valor deveria acompanhar a pessoa) —
o próprio `juridico-lgpd` diz que a trilha "só fica coberta se `actor` for id, nunca nome
denormalizado". Ou seja: mesma forma técnica, veredito oposto. Lá a cópia é dívida a minimizar
**antes** que mais linhas entrem na cadeia (redação retroativa quebra o encadeamento — ADR-0013);
aqui é o próprio objeto do registro. *A resolução do V9 não é deste ADR; o critério só mostra de
que lado ele cai, e que a janela para decidir é agora.*

## Consequências

- O parecer sobrevive à anonimização do signatário **por construção**, sem ninguém precisar
  lembrar de nada. Era o requisito.
- **PII denormalizada passa a existir no schema.** É uma tabela, duas colunas, escopo declarado,
  com base legal nomeada e registro no RIPD. O custo é real e está contabilizado.
- Nome corrigido em `pessoas` (casamento, retificação) **não** propaga para parecer já assinado.
  Correto — o ato foi assinado com aquele nome — e é a razão pela qual o T3 existe. Se um dia
  precisar constar retificação, é anotação nova no parecer, nunca reescrita do snapshot.
- A rotina de anonimização fica **mais simples**, não mais complexa: não precisa conhecer exceções.
- Teste do `auditor-rls` a escrever agora que a decisão existe: anonimizar `pessoas` e afirmar que
  `parecer_signatarios.nome_signatario` **permanece**; e que `UPDATE` do snapshot é rejeitado.
- O `juridico-lgpd` ganha um item: a resposta padrão a pedido de eliminação precisa enumerar o que
  permanece e por quê. Reter sem saber explicar é o que transforma base legal em problema.

## Alternativas descartadas

- **(b) Regra de processo — "quem assinou parecer não se anonimiza".** Descartada pela mesma razão
  que a D12 e o V1 já custaram duas vezes: **regra que depende de execução humana correta não é
  regra, é intenção** — e com editora única (D4) o executante é uma pessoa só, que pode esquecer,
  adoecer ou sair. Pior: falha em silêncio e só aparece quando o parecer é necessário, que é
  exatamente o pior momento.
- **(b′) Regra de processo implementada como trigger que bloqueia anonimizar signatário.** Melhor
  que (b), e ainda descartada: mantém o nome dentro de `pessoas`, onde ele é dado cadastral vivo,
  e transforma o direito de eliminação em erro de execução — o titular pediria e a rotina falharia,
  sem caminho de saída. O snapshot separa as duas coisas: o cadastro é eliminado, o ato permanece.
- **Congelar o cadastro inteiro do signatário** (CPF, e-mail, unidade). Descartada por
  necessidade/minimização (LGPD art. 6º, III): nada disso é elemento da assinatura, e usar uma
  exceção estreita como guarda-chuva é o abuso clássico do art. 16.
- **Snapshot só do nome, sem `qualificacao`.** Descartada: "Fulano assinou" sem dizer em que
  qualidade não sustenta o valor probatório — a assinatura vale por ser de um membro do conselho
  em mandato vigente. A qualificação é parte do ato, e é dado de papel, não dado pessoal adicional.
- **Documento PDF assinado como única prova, sem colunas.** Empurra o problema para o Storage e
  perde a consulta estruturada ("quais pareceres Fulano assinou"), além de não resolver: o PDF
  também conteria o nome, com o agravante de estar fora de qualquer política de retenção
  modelada.
- **Substituir a FK pelo snapshot.** Descartada: `pessoa_id` é chave técnica dos agregados e o
  `juridico-lgpd` manda preservar sempre. FK e snapshot têm funções diferentes e coexistem.

## Status

Aceito, 2026-09-04. Implementa a linha `pareceres`/`parecer_signatarios` do §4 do parecer
`docs/juridico/off-boarding-ex-morador.md`. Altera o modelo de dados (SPEC §2). Registrado em
`docs/04-DECISOES.md` como D14. Migração com o `eng-supabase`; teste com o `auditor-rls`.
