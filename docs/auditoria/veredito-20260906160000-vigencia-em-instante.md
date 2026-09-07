# Veredito — `20260906160000_vigencia_em_instante.sql` (ADR-0030)

**Data:** 2026-09-06 · **Auditor:** `auditor-rls` · **Migração:** vigência de papel e de vínculo
vira intervalo meia-aberto em instante · **Implementação:** `eng-supabase` · **Dívida fechada:** R4

## Decisão

**APROVADO.** As três falhas da suíte eram **dos asserts, não da migração** — confirmado caso a
caso contra o banco, não aceito do diagnóstico. Nenhuma delas foi acomodada ao comportamento:
os três foram reescritos para medir o que mediam, e a migração ganhou o teste de aceitação que
não tinha.

Suíte: **298 → 320 asserts**, 9 arquivos. Antes: 295 ok + 3 falhas (43, 48, 52) + 1 `todo`
verde-inesperado (55) + 1 `todo` vermelho (54). Depois: **320/320 verdes, zero `todo`**.
`pnpm lint`, `pnpm typecheck` e `pnpm vitest run` (100) limpos antes e depois — nenhum arquivo
fora de `supabase/tests/` foi tocado.

Duas ressalvas registradas no fim, nenhuma bloqueante, nenhuma delas de RLS.

---

## 1. As três falhas — confirmação antes de aceitar

### Testes 43 e 48 (F0, F5) — assert que **copia** o predicado

Confirmado no banco. `papeis.mandato_inicio` passou a ter `default now()`; `current_date`
promove a `timestamptz` na **meia-noite**:

```
now()                  = 2026-09-07 01:22:44.822973+00
current_date::timestamptz = 2026-09-07 00:00:00+00
```

O assert comparava `pa.mandato_inicio <= current_date` **direto**, sem passar por
`app.tem_papel`/`eh_editor_vigente_linha`. `01:22 <= 00:00` é falso, e F0 respondia `(nenhuma)`.

**A prova de que era o assert, e não a migração:** no mesmo instante, os dois triggers do último
editor — que **chamam** `eh_editor_vigente_linha` em vez de copiá-la — viam a Solo vigente e
barravam corretamente F1–F4 e F6–F8, que passaram. Assert e mecanismo discordando sobre a mesma
linha, com o mecanismo certo. É a mesma classe do R3 (assert que mede o estado do banco em vez do
efeito da policy), na forma **"assert que copia o predicado em vez de exercê-lo"**: a cópia não
tinha como envelhecer junto, porque não estava presa a nada.

Correção, e por que cada um foi para um lado diferente:

- **F0 chama `public.eh_editor_vigente_linha`** — de propósito a *mesma* função dos triggers. F0 é
  a **pré-condição** de um bloco que exercita esses triggers: o que precisa valer é que o mundo
  esteja como **o trigger o vê**.
- **F5 mede o efeito por `app.eh_editor()`** (→ `app.tem_papel`), caminho **independente**, que
  não consulta `eh_editor_vigente_linha`. Se F5 também chamasse a função de F0, um defeito nela
  passaria despercebido pelos dois asserts **e** pelos dois triggers ao mesmo tempo — co-falha. E
  F5 é a invariante "ainda dá para escrever", que é pergunta de autorização, não de linha.

### Teste 52 (F9) — assert certo no espírito, errado na letra

`to_regprocedure('public.eh_editor_vigente_linha(public.papel,date,date,boolean)')`. A assinatura
`date` foi **dropada de propósito** (armadilha nº 2 do ADR-0030: `create or replace` com
assinatura diferente cria sobrecarga, e os triggers resolvem por nome). Confirmado por catálogo:
existe **uma** função, com `p_mandato_inicio/p_mandato_fim timestamptz`.

Reescrito em dois asserts, porque nenhum dos dois sozinho fecha o buraco:

- **F9** conta (`= 1`) — é o que pega a **sobrecarga sobrevivente**.
- **F9b** confere os tipos dos argumentos por `pg_proc.proargtypes` — é o que pega a assinatura
  errada sobrevivendo sozinha.

### Teste 54 (G1) — `eng-supabase` está certo: **nunca testou a operação nova**

Confirmado. `mandato_fim = current_date - 1` sobre um mandato aberto hoje viola
`papeis_mandato_ck` (`ontem < hoje`) **antes e depois** da migração — o assert era insatisfazível
por construção, e continuaria sendo em qualquer implementação do ADR. A operação que passou a
existir é `fim = now()` (e `greatest(inicio, now())` quando `inicio` é futuro).

Removê-lo seria perder a cobertura; acomodá-lo ao comportamento seria falso verde. Foi
**reescrito para exercitar a operação real** e virou o bloco G inteiro.

### Teste 55 (G2) — verde-inesperado, mas passava medindo a coisa errada

Era o sinal esperado (mandato "encerrado hoje" deixou de ser vigente). Mas passava passando
`current_date` como **argumento literal** em vez de ler a coluna: media uma conta, não a linha —
e G1 nem tinha chegado a gravar nada, porque abortou. Absorvido pelos asserts de G, que leem a
linha depois de a revogação ter acontecido de verdade.

---

## 2. Matriz de revogação — o teste de aceitação que não existia

Bloco `G`, 16 asserts. O ADR-0030 pediu por nome (nota (c) ao `auditor-rls`) e não havia
cobertura regressiva nenhuma.

**Tudo roda na mesma transação, e isso é o teste, não montagem.** `now()` é
`transaction_timestamp()` e não anda dentro da transação — exigência do ADR §1 para os helpers
continuarem `STABLE`. Logo "revogar com `fim = now()` e deixar de ser reconhecida" é medido **no
mesmo instante**, não "um pouco depois". Com intervalo fechado a afirmação era inexprimível.

| Assert | O que prova |
|---|---|
| G1 | controle: a editora cadastrada por engano **é** editora agora (sem isto G3 passaria por vacuidade) |
| G2 | revogar agora um mandato aberto agora é operação **legítima**, e feita pelo caminho de produto (outra editora em AAL2, pela `papeis_update`) — não por `postgres` |
| **G3** | **no mesmo `now()`, `app.tem_papel` já devolve `false`** — ponta final exclusiva |
| G4 | o predicado dos triggers concorda com `tem_papel` sobre a linha revogada (não há dois predicados) |
| G5 | a revogação escreveu o instante em que o poder cessou e **não reescreveu** o instante em que começou |
| G6 | `now()` **puro** com `inicio` futuro viola `papeis_mandato_ck` — o caso que o parecer jurídico corrigiu |
| G7 | `greatest(mandato_inicio, now())` é aceito exatamente onde `now()` puro falhou |
| G8 | o resultado é o intervalo **vazio** `fim = inicio`, registrado e sem efeito |
| G9 | `fim = inicio` nasce legítimo no `INSERT` (a alternativa a apagar a linha, que B6/B7 negam) |
| G10 | e o intervalo vazio **não concede nada** nem no instante em que foi escrito |
| **G11** | **ordem inversa falha** (`ERRO[P0001]`) — e é correto que falhe (ADR §6) |
| G12 | ordem obrigatória (`INSERT` da nova → `UPDATE` da antiga) passa, numa transação |
| **G13** | **no mesmo instante a nova já é editora e a antiga já não é** — sem gap e sem sobreposição |
| G14 | depois da troca há **exatamente uma** editora vigente (D4 preservada, INV-02 nunca passou por zero) |
| G15 | a revogação registra **quem** encerrou e **por quê** (`encerrado_por`/`motivo_fim`, §5) |
| G16 | `motivo_fim` entra **legível** na trilha, não `[REDIGIDO]` (`audit.colunas_liberadas`, passo 6) |

A montagem do bloco F também deixou de usar o contorno `least(mandato_inicio, current_date - 60)`
(nota (b) do ADR) e passa a encerrar com `greatest(mandato_inicio, now())` — a mesma expressão que
a tela grava. A montagem não falsifica mais desde quando cada uma foi editora.

## 3. A conversão não revogou ninguém retroativamente

Bloco `H`, 7 asserts.

A sanidade embutida na migração **comparou zero com zero**: rodou sobre um banco que
`supabase db reset` acabara de esvaziar dessas linhas. É verdadeira e vazia, e o `eng-supabase`
foi honesto ao dizer que não provava. O passo 3 é "o passo que não pode sair errado", e no dia em
que houver projeto hospedado (dívida D2) é esta migração que roda.

A pré-migração é **reconstruída em `date`** (as colunas reais já são `timestamptz` e não aceitam
mais o estado antigo — a única prova honesta é reaplicar as duas semânticas sobre os mesmos
valores), com **15 linhas**: `−60`, ontem, hoje, amanhã, `+60` nas duas pontas, `fim` aberto,
`fim = inicio`, e concessão-e-revogação no mesmo dia. As expressões são literalmente as da
migração (`inicio::timestamptz`, `(fim + 1)::timestamptz`).

- **H1** — o conjunto de vigentes é **idêntico**: nenhum período estreitado, nenhum alargado.
- **H2** — a fixture **não é vácua**: 9 das 15 eram vigentes antes, 6 não eram. Fixture toda
  vigente faria H1 passar por vacuidade, que é a forma clássica de um assert de conversão mentir.
- **H3** — contrafactual: sem o `+ 1`, `d/h/j` (todo mundo que terminava **hoje**) seria revogado
  retroativamente. É o que dá dentes a H1.
- **H4** — contrafactual simétrico: `(inicio + 1)` negaria acesso a quem começou hoje. A
  assimetria da conversão é proposital, não descuido.
- **H5/H6** — liga a aritmética às **funções reais**: os valores convertidos das duas bordas
  vizinhas (`fim = HOJE` → `(HOJE+1) 00:00`; `fim = ONTEM` → `HOJE 00:00`) gravados na coluna de
  verdade produzem `app.eh_autenticado()` = `true` e `false`. Se a conversão tivesse deslizado um
  dia, as duas trocariam de lugar e quebrariam juntos.
- **H7** — INV-14 por comportamento: nenhuma função de autorização compara vigência com
  `current_date`, **incluindo `public.eh_editor_vigente_linha`**, que a varredura da própria
  migração não alcança (ver ressalva 1).

## 4. O que sustenta o veredito — os asserts ficam vermelhos quando o defeito volta

Cinco injeções de falha, cada uma dentro do `begin`/`rollback` do arquivo:

| Injeção | Asserts que caem |
|---|---|
| Intervalo volta a ser **fechado** (`fim >= now()`) em `tem_papel` e `eh_editor_vigente_linha` | **G3, G4, G10, G11, G13, G14** + F0, F1–F4, F6–F8 (14 no total) |
| A **sobrecarga `date`** de `eh_editor_vigente_linha` ressuscita (armadilha nº 2) | **F9, F9b** |
| A conversão do bloco H trocada pelo **cast direto** sem `+ 1` (armadilha nº 1) | **H1** |
| `current_date` volta a `app.unidades_da_pessoa()` | **H7** + D1 (comportamental) |
| `papeis_impede_fim_ultimo_editor` **dropado** | **G11** + F2–F4, F6–F8 |

A primeira e a última são as que importam: a regressão exata que o ADR existe para impedir cai em
seis asserts do bloco novo, e o trigger que garante "nunca zero editor" é pego pelo assert de
ordem inversa. Nenhum assert do bloco G ou H passa por vacuidade.

## 5. Varredura — a mesma doença em outro lugar?

Varridos os 9 arquivos atrás de **assert que copia predicado** (todo `is`/`ok` que não passa por
`pg_temp.probe/tenta/executa`, mais toda ocorrência de `current_date`, `mandato_*`, `inicio`,
`fim`). **F0 e F5 eram os únicos dois no repositório.** Os demais asserts fora dos helpers são de
catálogo (`pg_class`, `pg_policy`, `pg_proc`, `has_*_privilege`) ou de trilha — perguntas sobre o
schema, que é o lugar certo para elas. Os usos de `current_date` nos outros arquivos são fixture
(`mandato_inicio`, `competencia`, `vencimento`), não predicado.

Duas fixtures deste arquivo também tinham a semântica antiga embutida e foram corrigidas — não
estavam vermelhas, e é justamente por isso que valia mexer:

- o **ruído** da editora semeada agora nasce com o `default now()` (hora do dia), que é o valor
  que quebrou F0/F5. Ruído que não carrega a forma real do dado não protege de nada;
- o ator de **mandato vencido ontem** usava `current_date - 1`, que sob a semântica nova é
  "vencido há **dois** dias". Passava, medindo um caso mais frouxo que o pretendido. Agora é
  `current_date` — exatamente o que a migração gravaria ao converter o `date` antigo.

---

## Ressalvas — nenhuma bloqueante, nenhuma de RLS

**1. A varredura INV-14 da migração não alcança `public.eh_editor_vigente_linha`.** O bloco `do $$`
no fim da migração filtra `pronamespace = app`, e a função do predicado dos triggers mora em
`public`. É exatamente onde a sobrecarga `date` teria sobrevivido. Não há defeito hoje (medido), e
o buraco agora está coberto **por teste** (H7, que varre `app` e `public`). Sugestão a
`eng-supabase`: incluir `public.eh_editor_vigente_linha` na varredura da próxima migração que
tocar o assunto — a guarda de catálogo deveria bater com a de comportamento.

**2. Fuso na conversão do passo 3 — item para `arquiteto`, não para esta migração.**
`(mandato_fim + 1)::timestamptz` usa o `TimeZone` **implícito da sessão** que roda a migração. O
ADR §3 exige fuso explícito (`at time zone 'America/Sao_Paulo'`) no ponto da tradução da tela, mas
o passo 3 prescreve literalmente o cast implícito — a migração **segue o ADR**; a lacuna é do ADR.
Impacto hoje: **zero**, medido — o banco local é `TimeZone = UTC` de ponta a ponta e não há
projeto hospedado (D2). No dia em que houver dados reais e a migração rodar num banco em UTC para
uma aplicação em `America/Sao_Paulo`, cada linha existente perde 3h de vigência na conversão — que
é estreitamento retroativo, exatamente o que o passo 3 promete não fazer. Não bloqueio porque não
vaza nada e não há dado a converter; registro porque é o tipo de coisa que só aparece uma vez.

**3. Fora do meu escopo, mas o passo 7 do ADR não foi cumprido.** `scripts/dev/semeia-editora.ts`
(linha 82) e `tests/e2e/apoio.ts` (linha 122) continuam inserindo `mandato_inicio` com
`current_date`, e o ADR pediu `now()`. Não é falha de segurança — meia-noite de hoje é `<= now()`,
a editora fica vigente. É **veracidade**: a linha afirma que o mandato começou à meia-noite quando
começou agora, antedatando em até 24h o registro de quem foi editora e desde quando — que é a
única coisa que o ADR-0030 se compromete a não fazer. Dono: `eng-supabase`.
