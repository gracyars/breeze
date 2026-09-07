# ADR-0030 — Vigência de papel e de vínculo é intervalo **meia-aberto em instante**, não período em dias

> Fecha a dívida **R4** (`docs/ops/divida-tecnica.md`). Achado do `auditor-rls` em 2026-09-06 ao
> consertar R3; medido contra o banco, não deduzido.

## Contexto

`papeis.mandato_inicio/mandato_fim` e `vinculos.inicio/fim` são `date`, e a vigência é avaliada
como **intervalo fechado em dias**: `inicio <= current_date and (fim is null or fim >= current_date)`.
A autorização que esses intervalos concedem, porém, é **instantânea**: `app.tem_papel()` responde a
cada avaliação de policy, muitas vezes por segundo.

Os quatro fatos medidos pelo `auditor-rls` para "revogar hoje um mandato aberto hoje":

| Tentativa | Resultado medido |
|---|---|
| `mandato_fim = current_date - 1` | `ERRO[23514]` — viola `papeis_mandato_ck` (`fim >= inicio`) |
| `mandato_fim = current_date` | aceito, **e a pessoa segue vigente o dia inteiro** |
| `delete from papeis` | negado a todos os papéis de aplicação, de propósito (B6/B7) |
| reescrever `mandato_inicio` | falsifica quem foi editora e desde quando |

Não existe, portanto, caminho legal para revogar hoje. Com `editor` única (D4) e `aal2`, quem
assumiu por engano hoje fica com **toda a escrita do sistema até amanhã**, e a única saída é acesso
direto ao banco por quem tem a chave do projeto — exatamente a intervenção que o ADR-0022 reservou
para o caso extremo de perda total de acesso, agora virando rotina para um erro de cadastro.

### Por que é contradição interna, e não inconveniência

Duas afirmações do projeto são falsas na granularidade em que estão escritas:

1. **SPEC §7 / parecer `off-boarding-ex-morador.md` §1:** *"o acesso cessa em `vinculos.fim` + 0
   dias"*. O sistema cumpre "+ 0 dias" com **resolução de um dia**. Não é a mesma coisa: um
   ex-morador que vendeu a unidade às 9h continua enxergando o condomínio até a meia-noite.
2. **ADR-0023:** *"nunca monotonizar predicado constitutivo — revogação precisa afrouxar."* O
   predicado de `papeis`/`vinculos` não é monotônico por desenho, mas **é grosseiro demais para
   afrouxar quando a revogação acontece**. O efeito prático, dentro de uma janela de até 24h, é o
   mesmo que o ADR-0023 proíbe: um predicado constitutivo que não obedece à revogação.

### O diagnóstico

O schema mistura **duas coisas diferentes na mesma coluna**:

- o **fato de negócio** — "fulana foi editora entre 04/09 e 06/09" —, que é confortavelmente diário
  e é o que uma pessoa lê;
- a **janela de autorização** — o instante em que o poder começa e o instante em que cessa —, que
  não é diária em nenhuma leitura honesta.

A resolução do tipo foi escolhida pela primeira, e a segunda é quem manda. Some-se a isso a
semântica de intervalo **fechado** (`fim >= hoje` ⇒ o dia de `fim` ainda vale): com intervalo
fechado, "cessar agora" é literalmente inexprimível, porque não existe instante entre `fim` e
`fim + 1 dia`. É essa combinação — resolução errada **e** intervalo fechado — que produz o beco.

## Decisão

### 1. O princípio

> **Vigência de autorização é um intervalo meia-aberto de instantes: `[inicio, fim)`, avaliado em
> `now()`.** Uma coluna que participa de predicado de autorização não pode ter resolução mais
> grossa que o ato que ela autoriza. Revogar é escrever o instante em que o poder cessou —
> **nunca** encurtar, apagar ou reescrever o instante em que ele começou.

Corolários que valem para qualquer coluna futura da mesma família:

- `date` em predicado de autorização é sinal de alerta, do mesmo naipe que `exists` do ADR-0023.
- Intervalo **fechado** em predicado de autorização é sempre errado: torna "cessar agora"
  inexprimível e força a mentir em uma das duas pontas.
- **Referencial não declarado é da mesma família que resolução errada.** `date` num predicado
  deixa a **resolução** implícita; `::timestamptz` numa conversão deixa o **fuso** implícito, herdado
  do `TimeZone` de quem por acaso rodou o comando. Os dois produzem uma janela de autorização
  diferente da pretendida — em horas ou em dias — **sem erro e sem aviso**, para o lado que o
  ambiente escolher. Regra: toda fronteira de vigência — o tipo da coluna, a expressão que a
  converte, a expressão que a tela grava — **nomeia seu referencial no texto**, nunca o herda da
  sessão. Isto vale tanto para `at time zone 'America/Sao_Paulo'` no passo 3 quanto na tela (§3);
  se é inaceitável num, é inaceitável no outro, e pelo mesmo motivo.
- `now()` (= `transaction_timestamp()`), **nunca** `clock_timestamp()`: os helpers de RLS são
  `STABLE` e precisam continuar sendo, senão o plano reavalia por linha e o predicado pode mudar de
  valor no meio de uma mesma consulta.

### 2. A mudança de tipo

`papeis.mandato_inicio`, `papeis.mandato_fim`, `vinculos.inicio` e `vinculos.fim` passam de `date`
para **`timestamptz`**, e o predicado de vigência passa de fechado para meia-aberto:

```sql
-- antes:  inicio <= current_date and (fim is null or fim >= current_date)
-- depois: inicio <= now()        and (fim is null or fim >  now())
```

Com isso, `fim = now()` é **aceito** (satisfaz `fim >= inicio`) **e efetivo no mesmo instante** —
que é precisamente a operação que hoje não existe. Quando `inicio` é futuro, a forma correta é
`greatest(inicio, now())`; ver §3.

`fim = inicio` passa a ser um intervalo **vazio** e é legítimo: registra que a concessão existiu e
foi desfeita sem nunca ter tido efeito. É a forma honesta de "cadastrei a pessoa errada e desfiz
antes que ela usasse", em vez de apagar a linha.

### 3. O que a tela grava — **derivado de `motivo_fim`, nunca escolhido**

> **Emendado em 2026-09-06** pelo parecer
> `docs/juridico/pareceres/2026-09-06-default-da-tela-encerramento-de-vinculo.md`, que confirmou a
> leitura do "+ 0 dias" e **recusou a forma** que este parágrafo tinha. A versão anterior oferecia
> "cessar agora" e "encerra no dia D" como **escolha da editora**. Estava errada, e por um motivo
> que eu deveria ter visto: **contradizia o §6 deste mesmo ADR.** A promessa de que "no instante
> `now()` a nova editora já é vigente e a antiga já não é" só vale se a substituição gravar o
> instante — e a tabela binária permitia registrar a entrega de gestão como "encerra hoje",
> deixando **duas editoras vigentes até a meia-noite**. Eu fechava a janela no banco e a reabria
> pela tela. O texto abaixo substitui integralmente a versão recusada.

Ninguém digita um `timestamptz`, e **ninguém escolhe o instante**. A tela pergunta o **motivo**
(obrigatório) e, só para os motivos datados, a **data**. A ponta final é consequência do motivo,
porque a espécie do fato já determina a granularidade honesta:

- **Fato datado** — a propriedade transfere-se **com o registro do título** (CC art. 1.245): evento
  com **data** na matrícula e hora que o condomínio não conhece. Fim de locação e término de mandato
  são igualmente datados. Aqui a resolução de dia **não é desleixo — é a granularidade do fato
  constitutivo**, e cortar antes do fim de D negaria acesso a quem ainda é condômino.
- **Fato instantâneo** — óbito, pedido do titular, erro de cadastro, renúncia, substituição, conta
  comprometida. Não têm dia: têm o **momento em que o controlador soube**. Manter a janela até a
  meia-noite não preserva direito nenhum; é excesso puro, e em `conta_comprometida` é falha do dever
  de segurança.

#### `vinculos`

| `motivo_fim` | Campo de data na tela | `fim` gravado |
|---|---|---|
| `venda` | **sim**, obrigatório (D) | `(D + 1) 00:00 America/Sao_Paulo` |
| `fim_locacao` | **sim**, obrigatório (D) | `(D + 1) 00:00 America/Sao_Paulo` |
| `obito` | não | `greatest(inicio, now())` |
| `pedido_titular` | não | `greatest(inicio, now())` |
| `erro_cadastral` | não | `greatest(inicio, now())` |

#### `papeis`

| `motivo_fim` | Campo de data na tela | `mandato_fim` gravado |
|---|---|---|
| `termino_de_mandato` | **sim**, obrigatório (D) | `(D + 1) 00:00 America/Sao_Paulo` |
| `renuncia` | não | `greatest(mandato_inicio, now())` |
| `substituicao` | não | `greatest(mandato_inicio, now())` |
| `erro_cadastral` | não | `greatest(mandato_inicio, now())` |
| `conta_comprometida` | não | `greatest(mandato_inicio, now())` |

#### Regras que acompanham as tabelas

- **`greatest(inicio, now())`, nunca `now()` puro.** Com `inicio` futuro (locação ou mandato
  cadastrado para começar depois), `now()` viola `vinculos_periodo_ck`/`papeis_mandato_ck` e
  **reintroduz pela tela o mesmíssimo `ERRO[23514]` que este ADR existe para eliminar**, agora pela
  outra ponta. Com `greatest`, o resultado é o intervalo vazio `fim = inicio` que o §2 já
  legitimou — o caso pousa exatamente onde o modelo já tinha lugar para ele.
- **`D` no passado é gravação normal.** `(D+1) 00:00` já ficou para trás, `fim > now()` é falso, o
  acesso cessa na gravação. Sem caso especial.
- **`D` anterior a `inicio` a tela recusa — não clampeia.** É contradição do fato ("terminou antes
  de começar"); corrigir em silêncio grava mentira. Se a intenção era desfazer, o motivo é
  `erro_cadastral`.
- **`pedido_titular` não é oferecido quando `tipo = proprietario`.** Encerrar o vínculo do
  proprietário a pedido, sem venda, falsifica o fato e corta direito vigente; o pedido do titular
  sobre os próprios dados se atende pelo art. 18, não apagando a condição de condômino.
- **A hora nunca aparece na interface, para papel nenhum.** As quatro colunas viram `timestamptz`,
  mas a tela exibe **data** para `morador`, `conselho` e `editor`. "Vendeu a unidade às 09h14" não
  acrescenta nada à prestação de contas e é granularidade a mais sobre pessoa. O instante é dado
  técnico de autorização: vive no banco e na trilha, não na tela. **Fronteira a não confundir:** a
  restrição é sobre a exibição do *dado de domínio*; se F1 construir uma tela de leitura de
  `audit.log`, o instante aparece lá por definição — é o que uma trilha é.
- **O fuso é explícito no ponto da tradução** (`(D::date + 1)::timestamp at time zone
  'America/Sao_Paulo'`), nunca o fuso implícito do servidor — **a mesma exigência, pela mesma razão,
  vale para a conversão das linhas existentes no passo 3 da especificação**, e é o corolário 3 do
  §1 que amarra as duas. Isso resolve o item **F4 da INV-02** ("vigência usa `current_date` no fuso
  do servidor", hoje `ACEITO`): com `now()` a comparação é absoluta, e a ambiguidade de fuso sai do
  predicado e passa a viver só em dois lugares nomeados — esta expressão e a do passo 3.

#### Onde eu discordo do parecer, e onde não

Aceito integralmente as três correções e a derivação por `motivo_fim` — o argumento é melhor que o
meu e a contradição era real. **Divirjo apenas na dose de duas sugestões que o parecer deixou como
"endurecimento opcional" do schema**, e separo as duas porque não têm o mesmo mérito:

- **`pedido_titular` × `tipo = proprietario` merece virar `CHECK`.** É regra sem exceção legítima,
  e é **local a uma linha** (`tipo` e `motivo_fim` moram na mesma) — não precisa de matriz do
  ADR-0021, custa uma cláusula. Deixá-la só na tela é a "proteção que depende de alguém lembrar"
  que o ADR-0022 descartou. Honestidade sobre o que ela é: **regra de veracidade de dado, não de
  segurança** — falsificar o motivo não vaza nada. Por isso é recomendação, não gate.
- **`motivo_fim` obrigatório junto com `fim` deve ficar na tela mesmo**, como o parecer pôs. Aqui
  eu não endureceria: existem escritas legítimas sem motivo — backfill, restore, correção de
  migração — e um `CHECK` transformaria essas rotas em incidente. Regra da tela é o nível certo.

Nos dois casos, dono é `eng-supabase` e **nada disso bloqueia** a migração do R4.

### 4. `vinculos.fim` — mesma mudança, mesma migração, efeito maior

O problema é idêntico e atinge **todo morador**, não só a editora. Não há motivo para tratar as
duas tabelas em tempos diferentes, e há um motivo forte para não tratar: são as duas pernas de
`app.eh_autenticado()` (vínculo vigente **ou** papel vigente). Consertar uma e deixar a outra
produz um sistema onde "o acesso cessa imediatamente" vale para quem tem papel e não vale para quem
só tem vínculo — que é o inverso da prioridade, porque moradores são muitos e a editora é uma.

**Não muda o alcance do veto jurídico, e não o reinterpreta.** Sob a tradução da §3, um vínculo
encerrado "no dia D" continua valendo até o fim de D, exatamente como hoje; o que passa a existir é
a capacidade de encerrar **agora** quando é isso que se quer. A mudança é estritamente na direção
que o parecer pediu.

### 5. Quem revogou e por quê — `papeis` ganha a simetria que `vinculos` já tem

`vinculos` tem `motivo_fim` (enum fechado). `papeis` tem `concedido_por` e `motivo` na concessão e
**nada** no encerramento. O momento em que mais importa saber "por quê" é justamente a revogação —
distinguir *erro de cadastro* de *entrega de gestão* de *conta comprometida* muda a resposta a
incidente. Entram duas colunas: `encerrado_por` e `motivo_fim`.

`motivo_fim` é **enum**, não texto livre, por uma razão mecânica e não estética: `audit.fn_registrar()`
redige toda coluna ausente de `audit.colunas_liberadas`, e `papeis.motivo` (texto livre) está
deliberadamente fora dessa lista. Um `motivo_fim` textual apareceria na trilha como `[REDIGIDO]` —
o campo que existe para ser lido na auditoria seria o único ilegível nela. Enum fechado entra na
lista pelo mesmo critério já aplicado a `vinculos.motivo_fim` ("valor de enum fechado, não texto
livre").

### 6. INV-02, revogar e conceder — **corrigindo a premissa do pedido**

O pedido enuncia: *"revogar e conceder têm de ser um ato atômico, não dois."* **Isso é mais forte
do que a INV-02 exige, e a diferença importa para não construir mecanismo caro à toa.**

A INV-02 é um **piso** (`count(*) >= 1`), não uma igualdade. Concedendo antes de revogar, a
contagem faz `1 → 2 → 1`: **nunca passa por zero**, mesmo em duas transações separadas. O trigger
`papeis_impede_fim_ultimo_editor` já força essa ordem hoje e continua forçando. Atomicidade não é
requisito de segurança aqui.

O que a atomicidade compra é **higiene da D4**: se a concessão comita e a revogação falha (sessão
cai, erro de rede), o sistema fica com duas editoras em silêncio — não é vazamento nem
indisponibilidade, mas contraria a política de editora única sem que nada avise.

Decisão, então, em dois níveis:

- **Obrigatório:** a troca de editora acontece em **uma transação**, na ordem `INSERT` da nova →
  `UPDATE` da antiga. A ordem inversa **falha**, e é bom que falhe: o trigger dispara no `UPDATE` e
  conta as linhas visíveis — se a nova ainda não foi inserida, a contagem dá zero e a operação é
  recusada. Esse é o comportamento correto, não um bug a contornar.
- **Recomendado, não bloqueante:** sentinela `app.editores_vigentes_excedentes` (gestão-only), no
  mesmo espírito de `app.documentos_fora_da_busca` do ADR-0026 — a D4 vira observável em vez de
  prometida. Se atrapalhar o corte, fica para depois; não é parte do conserto do R4.

**Sem gap e sem sobreposição em instante nenhum:** com `[inicio, fim)`, no instante `now()` a nova
editora já é vigente (`inicio <= now()`, ponta inicial inclusiva) e a antiga já não é (`fim > now()`
falso). O intervalo meia-aberto é o que garante as duas propriedades ao mesmo tempo — com intervalo
fechado é impossível.

**Esta promessa tem uma dependência, e ela mora no §3:** só vale se a substituição gravar o
**instante**. É por isso que `substituicao` é motivo instantâneo e não datado. Registrar a entrega
de gestão como "encerra hoje" deixaria duas editoras vigentes até a meia-noite — reabrindo pela tela
a janela que a migração fecha no banco. Foi exatamente esse o defeito da primeira versão do §3.

### 7. A trilha fica mais honesta, não menos

A pergunta "quem era editora às 14h de terça?" **hoje não tem resposta** — o schema só sabe
responder por dia. Depois desta mudança ela passa a ter, e passa a ter em dois lugares
independentes: o intervalo na própria linha de `papeis`, e o `audit.log` encadeado, que já registra
`INSERT`/`UPDATE`/`DELETE` de `papeis` e `vinculos` (`audit_papeis`, `audit_vinculos`).

A condição para que isso valha é uma só, e é a parte do backfill que não pode sair errada: **nenhuma
linha existente pode ter seu período estreitado nem alargado pela conversão** (§ Especificação,
passo 3).

---

## Especificação para o `eng-supabase`

**Uma única migração**, incremental (a baseline está fechada; ADR-0008). Nome sugerido:
`<timestamp>_vigencia_em_instante.sql`.

### Passo 0 — por que é uma migração só, e não uma por tabela

Estado meio-aplicado (colunas convertidas, funções ainda comparando com `current_date`) **não é
inofensivo: é um buraco de autorização silencioso.** Postgres aceita `timestamptz >= date`
promovendo a `date` à meia-noite. Com `mandato_fim` já convertido para `(d+1) 00:00` e o predicado
antigo `mandato_fim >= current_date`, todo mandato encerrado passa a valer **um dia a mais**, sem
erro, sem aviso, na direção permissiva. Colunas, constraints e funções vão no mesmo arquivo.

### Passo 1 — enum e dependências

```sql
create type public.motivo_fim_mandato as enum
  ('renuncia', 'substituicao', 'termino_de_mandato', 'erro_cadastral', 'conta_comprometida');
```

Antes de alterar tipo, **listar os dependentes pelo catálogo, não de memória**:

```sql
select distinct dependente.relname, dependente.relkind
  from pg_depend d
  join pg_rewrite r on r.oid = d.objid
  join pg_class dependente on dependente.oid = r.ev_class
  join pg_class origem on origem.oid = d.refobjid
 where origem.relname in ('papeis','vinculos')
   and d.refobjsubid > 0;
```

Pelo levantamento do arquiteto o resultado esperado é **uma** view: `public.vw_inadimplencia_nominal`
(usa `v.fim is null`). Se aparecer outra, ela entra no mesmo `drop`/`create` — e a divergência entre
esta previsão e o catálogo é achado, não detalhe: reporte.

`ALTER COLUMN TYPE` **falha** com view dependente. `drop view public.vw_inadimplencia_nominal;` antes,
recriar idêntica no passo 6 (o corpo não muda: `v.fim is null` continua correto), com os `grant`s
originais.

### Passo 2 — colunas novas em `papeis`

```sql
alter table public.papeis
  add column encerrado_por uuid references public.pessoas(id),
  add column motivo_fim    public.motivo_fim_mandato,
  add constraint papeis_encerramento_ck
    check ((encerrado_por is null and motivo_fim is null) or mandato_fim is not null);
```

Espelha `vinculos_motivo_fim_ck`: só preenchível junto com `mandato_fim`.

### Passo 3 — conversão de tipo (**o passo que não pode sair errado**)

Ordem por coluna: `drop default` → `alter type ... using` → `set default`.

```sql
-- papeis
alter table public.papeis alter column mandato_inicio drop default;
alter table public.papeis alter column mandato_inicio type timestamptz
  using mandato_inicio::timestamp at time zone 'America/Sao_Paulo';    -- meia-noite do próprio dia
alter table public.papeis alter column mandato_inicio set default now();

alter table public.papeis alter column mandato_fim type timestamptz
  using (mandato_fim + 1)::timestamp at time zone 'America/Sao_Paulo'; -- meia-noite do dia SEGUINTE

-- vinculos: idêntico, em inicio e fim
```

Duas coisas nessa expressão, e as duas erram em silêncio se saírem:

**(a) `(fim + 1)` e não `fim` puro.** O intervalo antigo era fechado: `fim = 2026-09-06`
significava "vigente até o fim do dia 06". O equivalente meia-aberto é `2026-09-07 00:00`. Converter
para `2026-09-06 00:00` **revogaria retroativamente um dia inteiro de todo mundo**. `inicio`
converte sem `+ 1`: a ponta inicial já era inclusiva nas duas semânticas, e a assimetria é
proposital.

**(b) `::timestamp at time zone 'America/Sao_Paulo'`, e não `::timestamptz`.**
*(Corrigido em 2026-09-06 — ver `docs/auditoria/veredito-20260906160000-vigencia-em-instante.md`,
ressalva 2. A versão anterior deste passo prescrevia o cast implícito, contrariando o §3 do próprio
ADR.)* `::timestamptz` sobre um `date` resolve o fuso pelo `TimeZone` **da sessão que roda a
migração**. Rodar num banco em UTC para uma aplicação em `America/Sao_Paulo` **estreita três horas
em cada linha existente** — sem erro, sem aviso, só linhas expirando três horas antes do que
deveriam. É o mesmo estreitamento retroativo do item (a), em outra escala, entrando pela única porta
que o ADR tinha deixado destrancada. Impacto **hoje é zero e foi medido** (stack local em
`TimeZone = UTC` de ponta a ponta, sem projeto hospedado — dívida `D2`); o custo é integral no dia
em que houver dado real, e é a única vez que essa migração roda.

O `::timestamp` intermediário **não é decorativo**: `date` converte implicitamente tanto para
`timestamp` quanto para `timestamptz`, e `date at time zone 'x'` é ambíguo para o resolvedor de
operadores. Fixar `::timestamp` primeiro é o que torna a expressão determinística.

O fuso nomeado vive **na expressão**, não num `set timezone` no topo do arquivo: o objetivo é que o
referencial esteja escrito onde a conversão acontece, e não em estado de sessão que a próxima pessoa
não vê ao ler a linha. Se o produto um dia deixar de ser um condomínio em um só fuso, esta literal é
um dos pontos a revisar — junto do item F4 da INV-02.

Sanidade a rodar **na mesma transação**, antes do commit — se qualquer uma falhar, `raise`:

```sql
-- ninguém perde nem ganha vigência hoje
-- (contagem de vigentes antes/depois tem de bater; capture o "antes" em temp table no início)
select count(*) from public.papeis
 where mandato_inicio <= now() and (mandato_fim is null or mandato_fim > now());
select count(*) from public.vinculos
 where inicio <= now() and (fim is null or fim > now());
```

Hoje isso roda apenas contra o stack local (F1, acervo de 43 documentos, editora semeada, usuárias
de e2e) — não há projeto hospedado (dívida `D2`). O passo continua tendo de estar correto: é a mesma
migração que rodará no dia em que houver.

### Passo 4 — constraints e comentários

`papeis_mandato_ck` e `vinculos_periodo_ck` **sobrevivem** à conversão (`>=` vale para `timestamptz`)
e continuam corretos. O que muda é o significado, então recrie com `comment` explícito de que o
intervalo é `[inicio, fim)` e que `fim = inicio` é intervalo vazio e legítimo. Atualize também os
`comment on column` das quatro colunas.

### Passo 5 — funções (**atenção à armadilha de assinatura**)

Cinco corpos mudam. Em todos: `current_date` → `now()`, e `fim >= …` → `fim > …`.

| Função | Onde |
|---|---|
| `app.tem_papel(public.papel)` | `20260904120400_funcoes_app.sql` |
| `app.eh_autenticado()` | idem — **as duas pernas**, `vinculos` e `papeis` |
| `app.unidades_da_pessoa()` | idem |
| `public.eh_editor_vigente_linha(...)` | `20260904120300_identidade_tabelas.sql` |

**`eh_editor_vigente_linha` muda de assinatura** (`date` → `timestamptz` nos parâmetros 2 e 3).
`create or replace` **não** substitui: cria uma **sobrecarga**, deixando a versão `date` viva. Os
dois triggers resolvem por nome e podem ligar na antiga — que compara `timestamptz` promovido contra
`current_date` e devolve resposta errada, em silêncio, na guarda do último editor.

```sql
drop function if exists public.eh_editor_vigente_linha(public.papel, date, date, boolean);
create function public.eh_editor_vigente_linha(
  p_papel public.papel, p_mandato_inicio timestamptz, p_mandato_fim timestamptz, p_pessoa_ativa boolean
) ...
```

Confira depois com `select proname, pg_get_function_identity_arguments(oid) from pg_proc where proname = 'eh_editor_vigente_linha';` — **uma** linha.

Os corpos de `tg_pessoas_impede_autotranca_editor` e `tg_papeis_impede_fim_ultimo_editor`
**não mudam** (só chamam a função). Não os toque.

`app.pessoa_atual()`, `app.eh_editor()`, `app.eh_gestao()`, `app.papel_atual()` não mudam.

### Passo 6 — recriar a view, `grant`s e a lista de auditoria

```sql
insert into audit.colunas_liberadas (tabela, coluna, motivo) values
  ('papeis','encerrado_por','FK técnica'),
  ('papeis','motivo_fim','valor de enum fechado, não texto livre');
```

Sem isso a trilha mostra `[REDIGIDO]` exatamente no campo que existe para ser lido nela.
Atualize também os `motivo` das linhas já existentes de `papeis.mandato_inicio`/`mandato_fim` e
`vinculos.inicio`/`fim`: deixam de ser "data técnica", passam a ser "instante técnico — janela de
autorização". Recrie a view do passo 1 com os `grant`s originais.

### Passo 7 — fora do banco

`pnpm db:types` (os quatro campos continuam `string` no TS; o valor passa a trazer hora).
`scripts/dev/semeia-editora.ts` e `tests/e2e/apoio.ts` inserem sem data explícita ou com
`current_date` — conferir e ajustar para `now()`. `supabase db reset` local tem de aplicar limpo.

### O que **não** é do `eng-supabase` nesta entrega

- **`supabase/tests/`** — inclusive os dois `todo` do bloco G, que viram verde-inesperado. Dono:
  `auditor-rls`. Notas para ele: (a) `G2` chama `eh_editor_vigente_linha(..., current_date, ...)` e
  precisa passar a `now()`; (b) o `least(mandato_inicio, current_date - 60)` do bloco F deixa de ser
  necessário — encerrar hoje um mandato aberto hoje passa a ser operação legal, e a montagem pode
  usar a operação real; (c) o assert que falta e não existe hoje é o **de revogação instantânea**:
  conceder, revogar com `fim = now()`, e afirmar que `tem_papel` já devolve `false` na mesma
  transação.
- **A UI de gestão de papéis e vínculos** — dono: quem construir a tela em F1. Ela implementa o §3
  **inteiro**: motivo obrigatório, campo de data só nos motivos datados, nenhum campo de instante,
  nenhuma hora exibida, `greatest(inicio, now())` nos instantâneos, recusa de `D < inicio`,
  `pedido_titular` fora da lista quando `tipo = proprietario`. **Armadilha específica desta base:**
  a revogação é instantânea *no banco* porque papel é dado e não claim (ADR-0012 §5), mas qualquer
  cache de RSC/`use cache` sobre papel ou vínculo reintroduz a janela pela porta da frente — e desta
  vez com TTL que ninguém escreveu num ADR.
- **Dois endurecimentos de schema opcionais** discutidos no fim do §3 (`CHECK` de
  `pedido_titular` × `proprietario`, recomendado; `motivo_fim` obrigatório, **não** recomendado).
  Dono `eng-supabase`, fora do caminho crítico do R4 — não entram nesta migração.

### Ordem e tamanho, em resumo

4 colunas convertidas · 2 colunas novas · 1 enum novo · 5 funções (1 com `drop` obrigatório) ·
2 triggers **intocados** · 1 view derrubada e recriada · 2 constraints recomentadas · 0 índices
alterados (rebuild automático, todos os parciais em `fim is null` seguem válidos) · 1 arquivo de
migração · 1 regeneração de tipos.

---

## Consequências

- **A afirmação do SPEC §7 passa a ser verdadeira.** Hoje ela descreve uma intenção; depois disto
  descreve o mecanismo. Nenhuma correção do §7 é necessária — e é exatamente por isso que esta é a
  opção que **não** exige reinterpretar veto alheio (ver §Status).
- **Revogação passa a ser operação de produto**, não escalada para acesso direto ao banco. O
  caminho do ADR-0022 (intervenção com privilégio de dono, auditada) volta a ser o que sempre
  deveria ter sido: recurso para perda total de acesso, não para erro de cadastro.
- **A trilha ganha resolução.** "Quem era editora às 14h de terça" passa a ter resposta na linha e
  no `audit.log`. Nenhuma linha existente muda de significado (passo 3).
- **INV-02 muda de enunciado** (`current_date` → `now()`, `>=` → `>`) e o item **F4 (fuso)** deixa
  de ser um `ACEITO`: a vigência passa a ser absoluta. INV-12 e INV-06 mudam pelo mesmo motivo. A
  matriz de caminhos da INV-02 **não** muda — os 9 caminhos e F1–F3 continuam válidos, só o
  predicado que cada célula avalia é outro.
- **Invariante nova, INV-14:** nenhuma função de autorização compara período com `current_date`.
  É testável por catálogo (varredura dos corpos em `pg_proc` no schema `app`) além de
  comportamentalmente — e é a forma de impedir que a regressão volte por uma função nova, que é
  como ela voltaria.
- **Custo por avaliação: inalterado.** `now()` é `STABLE` como `current_date`; mesmos índices,
  mesmos planos.
- **`fim = inicio` (intervalo vazio) passa a ser possível e visível.** Uma concessão desfeita no
  mesmo instante fica registrada em vez de desaparecer — é o efeito desejado, mas quem ler a tabela
  precisa saber que essa linha existe e não é lixo.
- **Fica um `timestamptz` de hora exata em `vinculos.fim`**, marginalmente mais granular como dado
  pessoal do que uma data. Eu havia registrado isso "por honestidade"; o parecer de 2026-09-06
  transformou em **requisito**: a hora não é exibida na interface para papel nenhum (§3). O instante
  é dado técnico de autorização — sobrevive no banco e na trilha, não na tela. Retenção e base legal
  inalteradas.
- **O veto do "+ 0 dias" alcança o cache, e isso é consequência de autorização, não de desempenho.**
  Qualquer `use cache`/cache de RSC sobre papel ou vínculo restaura a janela de acesso pós-`fim`
  com um TTL que ninguém aprovou — desfazendo, na camada de aplicação, a propriedade que esta
  migração compra no banco. **Papel e vínculo se leem sempre no banco.** Está aqui, e não só numa
  nota de implementação, porque é o tipo de mudança que alguém faz por latência sem perceber que
  está mexendo em autorização — e o ADR-0012 §1 já diz que a RLS é a fronteira: cache na frente dela
  é fronteira nova, não otimização.
- **`obito` desloca levemente o relógio de retenção.** Com `greatest(inicio, now())`, `vinculos.fim`
  passa a marcar o instante do **registro**, não a data do óbito, e os 5 anos de PII cadastral
  contam de lá. Custo aceito e declarado no parecer: manter viva a sessão de uma pessoa falecida é
  entregar o acervo a quem tiver a caixa de e-mail dela. A data do óbito é fato de sucessão e
  pertence a outro campo, de quem modelar sucessão — não à janela de autorização.

## Alternativas descartadas

- **Aceitar a resolução de um dia e corrigir o SPEC §7.** Legítima, e era a saída barata. Descartada
  por dois motivos, nesta ordem: (a) o conserto custa **uma** migração e nenhuma decisão nova —
  desproporcional pagar com uma propriedade de segurança; (b) o "+ 0 dias" é veto do `juridico-lgpd`
  e reinterpretá-lo não é ato do arquiteto. Escolher esta alternativa **exigiria** consultá-los
  antes; escolher a decisão acima **não exige**, porque implementa o veto em vez de renegociá-lo.
  Foi um critério de escolha, não uma consequência dela.
- **Manter `date` e tornar `mandato_fim` exclusivo (`fim > current_date`).** Um caractere em cada
  função, e é a alternativa que alguém vai propor. Descartada porque **quebra a trilha para trás**:
  `fim = current_date` escrito às 14h passaria a significar "não era vigente desde 00:00 de hoje",
  falsificando a manhã inteira em que a pessoa de fato escreveu no sistema. Troca um beco por uma
  mentira retroativa — e o ADR-0013 é metade do produto.
- **Manter `date` e acrescentar `revogado_em timestamptz` à parte.** Parece menor: nada de conversão
  de tipo, nada de backfill. Não é. Cria **duas fontes de verdade para a mesma pergunta** ("está
  vigente?" passa a exigir as duas), que é a classe de defeito que já custou a este projeto V1-R,
  V3-R e V10-R, e que a D12 nomeia ("uma fonte, nunca duas cópias"). Além disso: obriga
  `papeis_vigente_uk` a virar índice parcial sobre duas colunas, deixa **duas** maneiras de encerrar
  um mandato com semânticas diferentes para os triggers cobrirem, e **não resolve `vinculos.fim`**
  sem uma segunda coluna simétrica — dobrando o problema em vez de resolvê-lo.
- **Relaxar `papeis_mandato_ck` para `fim >= inicio - 1`.** Desbloqueia o `ERRO[23514]` e produz uma
  linha afirmando que o mandato terminou antes de começar. Mentira gravada, pelo mesmo preço.
- **`tstzrange` com constraint de exclusão** no lugar de duas colunas. Tecnicamente superior — `[)`
  é o default do tipo, `@>` e `&&` de graça, sobreposição de mandatos vira constraint. Descartada
  **por ora** por custo desproporcional ao conserto: troca todos os índices btree por GiST, reescreve
  todos os predicados e todos os asserts de pgTAP, e o par de colunas é mais legível para quem lê a
  tabela e para quem escreve teste. Fica registrada como a evolução natural se algum dia for preciso
  proibir mandatos sobrepostos por constraint.
- **Usar `pessoas.ativa = false` como revogação imediata.** Já existe e já é instantâneo (é boolean,
  não tem resolução). Não serve: desliga a *pessoa*, não o *papel* — não atende "tirar o papel de
  editor e manter a moradora", não se aplica a `vinculos`, e o próprio
  `20260904120400_funcoes_app.sql` registra que `ativa` é kill-switch administrativo e **nunca** o
  portão sozinho. É contorno, e é o contorno que estaria em uso hoje se ninguém tivesse medido.
- **Conta de quebra-vidro para desfazer concessão errada.** Já recusada na D9 e de novo no ADR-0022,
  pelo mesmo motivo: credencial privilegiada parada é superfície contínua para cobrir evento raro.
- **Rotina que expira mandatos à meia-noite.** Não resolve nada — o problema é a janela **até** a
  meia-noite. Trocaria um defeito de modelo por uma dependência de cron.

## Status

**Aceito, 2026-09-06 — com o §3 emendado no mesmo dia** pelo parecer
`docs/juridico/pareceres/2026-09-06-default-da-tela-encerramento-de-vinculo.md` (a versão original
do §3 está descrita e sepultada dentro do próprio §3; ADR aceito não se reescreve calado).
Fecha a dívida **R4**. Estende o ADR-0012 (§5, "papel é dado, não claim" —
que estava certo no mecanismo e grosseiro na resolução) e o ADR-0023 (a espécie *constitutiva*
precisa afrouxar, e não afrouxava a tempo). Não conflita com o ADR-0022: a guarda do último editor
continua valendo, com o mesmo trigger e o mesmo advisory lock.

Implementação: `eng-supabase` (migração). Testes: `auditor-rls` (inclusive os dois `todo` do bloco
G). Tradutor de data → instante e a tela: F1, gestão de papéis.

**Consulta ao `juridico-lgpd` — perguntada e respondida, 2026-09-06.** Esta decisão **não**
reinterpretou o veto "+ 0 dias": implementou-o com resolução mais fina, preservando para saída
planejada o comportamento atual. A pergunta que ficou aberta — *"encerra no dia D" vale até o fim de
D, ou cessa no instante do registro?* — foi respondida em
`docs/juridico/pareceres/2026-09-06-default-da-tela-encerramento-de-vinculo.md`:
**vale até o fim do dia D**, com fundamento em CC art. 1.245 (a propriedade transfere-se com o
registro do título, fato que tem data e não hora conhecida do condomínio). O mesmo parecer
**recusou a forma** do §3 original e o substituiu pela derivação por `motivo_fim`. **Nada mudou no
banco:** tipo, predicado, enum, constraints e a especificação de migração acima seguem válidos e
intocados — a emenda é toda de tela.

**Implementado e auditado.** Migração `20260906160000_vigencia_em_instante.sql` (`eng-supabase`);
veredito **APROVADO** em `docs/auditoria/veredito-20260906160000-vigencia-em-instante.md`, suíte
298 → **320/320, zero `todo`**, com teste de mutação que fica vermelho quando o intervalo volta a
ser fechado, quando a sobrecarga `date` ressuscita e quando a conversão perde o `+ 1`. Os dois
`todo` do bloco G viraram a matriz de revogação de 16 asserts que este ADR pediu por nome.

**Registro de método, porque o erro é reutilizável — e aconteceu duas vezes neste documento.**

1. A versão recusada do §3 contradizia o **§6** do próprio ADR: o §6 prometia zero sobreposição de
   editoras, o §3 dava à editora um botão para criá-la. Achou o revisor jurídico.
2. O passo 3 da especificação contradizia o **§3**: o §3 exige fuso explícito e argumenta por quê,
   o passo 3 prescrevia o cast implícito. Achou o `auditor-rls`, auditando a migração.

Nos dois casos o autor enunciou o princípio numa seção e o violou em outra, e nos dois casos quem
achou foi quem leu o documento **de fora**, procurando outra coisa. A lição não é "revisar mais": é
que **princípio declarado numa seção vira obrigação de conferência contra todas as demais** — a
mesma classe do V1-R/V3-R/V10-R (regra validada no caminho enumerado, não no estado resultante),
desta vez entre **parágrafos de um ADR** em vez de entre colunas ou tabelas. Um ADR longo o
bastante para ter especificação embutida tem superfície interna, e superfície interna vaza igual.

**Pendente de aprovação do orquestrador (não editado por este agente):** SPEC §2, tabela de
`papeis`/`vinculos` — tipo das quatro colunas e as duas colunas novas de `papeis`; e SPEC §2.1,
parágrafo "mandato que termina hoje deixa de valer hoje", que deve passar a dizer **"mandato
encerrado agora deixa de valer agora"**, porque é o que o sistema passa a fazer e a frase atual é
justamente a que descrevia o comportamento que não existia.
