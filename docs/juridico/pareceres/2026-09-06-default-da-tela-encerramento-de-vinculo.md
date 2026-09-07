# Parecer — O default da tela ao encerrar vínculo ou mandato (ADR-0030 §3)

**Pergunta recebida (orquestrador, 2026-09-06):** quando a editora registra "vínculo encerrado no
dia D", o "+ 0 dias" do veto significa acesso **até o fim do dia D** (o que o sistema faz hoje e a
migração do ADR-0030 preserva) ou **cessar no instante do registro**?

**Alcance:** decide o valor gravado em `vinculos.fim` e `papeis.mandato_fim` pela tela de gestão.
Não toca tipo, predicado, migração nem RLS. Vale para a UI de F1.

---

## Veredito: **APROVADO COM CONDIÇÃO — e a alternativa binária do ADR §3 é recusada**

1. **Confirmo a primeira leitura.** Para saída **planejada**, o acesso vale **até o fim do dia D**.
   `fim = (D + 1 dia) 00:00 America/Sao_Paulo`, como o ADR-0030 §3 propõe. O "+ 0 dias" nunca
   significou "cessar ao registrar" — significa **zero tolerância depois do fato**, que é o que o
   parecer de off-boarding §3 decidiu ao recusar a janela degradada de 90 dias. A leitura do
   arquiteto está correta e não reinterpreta o veto.

2. **Recuso, porém, a forma da tabela do §3.** Ela oferece as duas entradas como **escolha da
   editora**. Isso é exatamente a escolha ambígua sob pressão que o pedido quer eliminar, e é
   evitável: o sistema já sabe a resposta antes de perguntar. A condição desta aprovação é que o
   default **derive de `motivo_fim`**, coluna que a editora já é obrigada a preencher no mesmo ato
   (C3 do parecer de off-boarding; `vinculos.motivo_fim` já existe em
   `20260904120300_identidade_tabelas.sql`).

3. **É a terceira opção que o ADR não previu**, e ela não custa nada além de trocar um campo de
   rádio por uma consequência do enum.

---

## O fundamento: a granularidade da ponta final segue a granularidade do fato que a produz

O direito de acesso do condômino é **direito da condição**, não da pessoa (parecer de off-boarding
§1). Ele se extingue quando a condição se extingue — **não** quando a editora digita. Logo, tanto
`(D+1) 00:00` quanto `now()` são *proxies* de um fato externo, e a escolha é sobre qual proxy erra
menos. Mas os fatos que encerram um vínculo não são todos da mesma espécie:

**Fatos datados.** A propriedade transfere-se **com o registro do título no Registro de Imóveis**
(CC art. 1.245, verificado em fonte primária hoje) — evento que tem **data** na matrícula, não hora
conhecida do condomínio. Fim de locação e término de mandato são igualmente datados. Para estes, a
granularidade honesta da revogação é **o dia**, porque é a granularidade do fato constitutivo. Fixar
a ponta em `(D+1) 00:00` não é folga: é a fronteira declarada de um fato que só se conhece por dia.
Cortar antes seria **negar acesso a quem ainda é condômino** — supressão de direito atual (CC
art. 1.348, VIII c/c art. 1.335, III: a prestação de contas se deve à assembleia, da qual ele ainda
participa), e a LGPD não exige nem autoriza isso: o art. 6º, III (necessidade) mede excesso, não
manda antecipar a extinção da finalidade. O erro é assimétrico e o pedido o descreveu bem — mas é
**mais grave** do lado do corte antecipado, porque ali o sistema viola um direito **em vigor**,
enquanto do outro lado há, no máximo, horas de excesso sobre dado a que a pessoa teve acesso legítimo
o dia inteiro.

**Fatos instantâneos.** Erro de cadastro, conta comprometida, óbito, renúncia, substituição de
editora e pedido do próprio titular **não têm dia: têm momento** — o momento em que o controlador
soube. Aqui `(D+1) 00:00` não preserva direito nenhum, porque não há direito a preservar: o vínculo
ou nunca existiu, ou o titular pediu para encerrá-lo, ou o acesso deixou de ser dele. Manter a janela
até a meia-noite é **excesso puro** (LGPD art. 6º, III e art. 15, I) e, no caso de conta
comprometida, descumprimento do dever de segurança do art. 46. Para estes, `now()` é obrigatório.

**Consequência:** a pergunta "agora ou fim do dia D?" nunca precisa ser feita à editora. Ela é
respondida por `motivo_fim`, que já distingue as duas espécies — e que a editora preenche por outra
razão (parar a cobrança, alimentar a rotina de anonimização).

**Coerência interna.** O próprio ADR-0030 §6 depende disto: a promessa de que "no instante `now()` a
nova editora já é vigente e a antiga já não é" **só é verdadeira se `substituicao` gravar `now()`**.
Sob a tabela binária do §3, uma editora que registrasse a entrega de gestão como "encerra hoje"
deixaria duas editoras vigentes até a meia-noite — contrariando a D4 e reabrindo, pela tela, a janela
que a migração fechou no banco.

---

## O critério que a tela aplica sozinha

A tela **não pergunta o instante**. Pergunta o motivo (obrigatório) e, só para os motivos datados,
a data. O resto é derivado.

### `vinculos`

| `motivo_fim` | Campo de data na tela | `fim` gravado |
|---|---|---|
| `venda` | **sim**, obrigatório (D) | `(D + 1) 00:00 America/Sao_Paulo` |
| `fim_locacao` | **sim**, obrigatório (D) | `(D + 1) 00:00 America/Sao_Paulo` |
| `obito` | não | `greatest(inicio, now())` |
| `pedido_titular` | não | `greatest(inicio, now())` |
| `erro_cadastral` | não | `greatest(inicio, now())` |

### `papeis` (enum novo do ADR-0030 §5)

| `motivo_fim` | Campo de data | `mandato_fim` gravado |
|---|---|---|
| `termino_de_mandato` | **sim**, obrigatório (D) | `(D + 1) 00:00 America/Sao_Paulo` |
| `renuncia` | não | `greatest(mandato_inicio, now())` |
| `substituicao` | não | `greatest(mandato_inicio, now())` |
| `erro_cadastral` | não | `greatest(mandato_inicio, now())` |
| `conta_comprometida` | não | `greatest(mandato_inicio, now())` |

### Regras que acompanham a tabela

- **`greatest(inicio, now())`, nunca `now()` puro.** Se `inicio` for futuro (locação ou mandato
  cadastrado para começar depois), `fim = now()` viola `vinculos_periodo_ck` / `papeis_mandato_ck`
  — o mesmo `ERRO[23514]` que o ADR-0030 acabou de eliminar, reintroduzido pela tela. Com
  `greatest`, o resultado é o intervalo vazio `fim = inicio` que o ADR §2 já declarou legítimo.
  **Correção à linha 1 da tabela do ADR §3.**
- **D no passado é gravação normal, não erro.** `(D+1) 00:00` já ficou para trás, `fim > now()` é
  falso, o acesso cessa na gravação. Nenhum caso especial na tela.
- **D anterior a `inicio` a tela recusa**, não corrige. É contradição do fato ("terminou antes de
  começar"); silenciar clampeando grava mentira. Se a intenção era desfazer, o motivo é
  `erro_cadastral`.
- **`motivo_fim` obrigatório sempre que a tela escreve `fim`.** Hoje o `CHECK` só impede o inverso
  (`motivo_fim` sem `fim`). A obrigatoriedade é da tela; endurecer o schema é opcional, do
  `eng-supabase`, e **não** bloqueia.
- **`pedido_titular` não é oferecido para `tipo = proprietario`.** Encerrar o vínculo do proprietário
  a pedido, sem venda, falsifica o fato e corta direito vigente (CC art. 1.335, III). O pedido do
  titular sobre os próprios dados se atende pelo art. 18, não apagando a condição de condômino.
- **A hora nunca aparece na interface.** As quatro colunas viram `timestamptz`, mas a tela — para
  `morador`, `conselho` e `editor` — exibe **data**. "Vendeu a unidade às 09h14" não acrescenta nada
  à prestação de contas e é granularidade a mais sobre pessoa (art. 6º, III). O instante é dado
  técnico de autorização; vive no banco e no `audit.log`, não na tela.
- **Cache é reabertura do veto.** Qualquer `use cache`/cache de RSC sobre papel ou vínculo restaura
  a janela de acesso pós-`fim` com um TTL que ninguém aprovou. O veto do "+ 0 dias" alcança o cache:
  papel e vínculo se leem sempre no banco.

---

## Base legal e retenção

**Base legal do tratamento:** **obrigação legal** — dever de prestar contas do síndico (CC art.
1.348, VIII, verificado em fonte primária) e guarda documental condominial (Lei 4.591/64, art. 22,
§1º, "g"). Para a ponta de **revogação instantânea** (`conta_comprometida`, `erro_cadastral`),
acresce **legítimo interesse** na forma do dever de segurança do tratamento (LGPD art. 46).
**Nunca consentimento** — e esta decisão não altera isso.

**Retenção (SPEC §7 — inalterada por esta decisão):**

| Objeto | Retenção |
|---|---|
| Acesso derivado de `vinculos.fim` / `papeis.mandato_fim` | cessa em `fim` **+ 0 dias**, agora com resolução de instante |
| PII cadastral do ex-morador (`pessoas`) | 5 anos após `fim`, depois anonimização (parecer de off-boarding §4) |
| `fim` / `mandato_fim` como dado (o instante em si) | acompanha a linha; **não** é exibido, só avaliado |
| `audit.log` (inclusive `motivo_fim`, enum liberado) | permanente, não expurgável |
| `audit.acesso` | 6 meses |

**Nota sobre `obito`:** para este motivo, `vinculos.fim` passa a marcar o **instante do registro**,
não a data do óbito — o relógio dos 5 anos conta de lá, portanto um pouco mais tarde. Custo aceito e
declarado: manter viva a sessão de uma pessoa falecida significa entregar o acervo a quem tem a caixa
de e-mail dela, e isso é pior que algumas semanas de guarda a mais. A data do óbito é fato de
sucessão e pertence a outro campo, de quem modelar sucessão — não à janela de autorização.

---

## O que este parecer **não** decide

- Não altera o ADR-0030 §§1, 2, 4–7, nem a migração, nem o tipo, nem o predicado. A resposta é
  "primeira leitura", logo **nada muda no banco**.
- Não decide abertura de acervo além de convenção e regimento — permanece decisão pendente nº1 do
  dono do projeto (SPEC §7).

## Ações

- [ ] **UI de F1 (gestão de papéis e vínculos):** implementar as duas tabelas acima; `motivo_fim`
      obrigatório; sem campo de instante; sem hora na exibição.
- [ ] **ADR-0030 §3** — substituir a tabela de duas entradas escolhidas pela editora pela derivação
      por `motivo_fim`, e corrigir `now()` → `greatest(inicio, now())`. Dono: `arquiteto`.
- [ ] **`eng-supabase` (opcional, não bloqueante):** endurecer `vinculos_motivo_fim_ck` /
      `papeis_encerramento_ck` para exigir `motivo_fim` junto com `fim`.
- [ ] **Skill `lgpd-condominio` §6-bis** — acrescentar que "+ 0 dias" é zero tolerância **depois do
      fato**, e que a espécie do fato (datado × instantâneo) define a ponta. Fora do escopo de
      arquivo deste agente nesta sessão.
