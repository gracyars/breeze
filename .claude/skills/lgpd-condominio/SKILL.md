---
name: lgpd-condominio
description: Aplica a LGPD ao domínio condominial do Breeze — base legal, minimização por papel, inadimplência, CPF, retenção e direitos do titular — para qualquer agente que publique dado pessoal ou decida visibilidade/retenção.
---

# LGPD no Breeze

Skill operacional, não resumo da lei. Decisão de produto não coberta aqui: escalar ao
`juridico-lgpd`, não decidir por analogia.

## 1. Inventário de dados pessoais tratados

| Dado | Onde vive | Sensibilidade |
|---|---|---|
| Nome | `pessoas.nome`, atas, deliberações, `audit.log` | Identificador direto |
| CPF | `pessoas.cpf_hash` (HMAC, lookup) e `cpf_enc` (reversível) | Identificador direto, alto risco de mau uso |
| E-mail, telefone | `pessoas`, `audit.log` | Identificador de contato |
| Unidade (bloco/número) | `vinculos` | Quase-identificador — cruza com nome em condomínio pequeno |
| Situação de pagamento | `cobrancas` | Financeiro, alto potencial de constrangimento |
| Conteúdo de atas | `documentos`, `documento_paginas`, `chunks` | Cita pessoas nominalmente, votos; pode incluir terceiros não-usuários (convidado, prestador) |
| Anexos financeiros e cotações | `lancamento_anexos`, `documentos` | Notas, recibos e propostas, com CPF/contato de pessoa física (prestador, representante, responsável técnico) |

**Texto de ata e anexo carregam PII fora de qualquer campo estruturado** — por isso `chunks` e
`documento_paginas` precisam da mesma RLS de `documentos` (SPEC §7, "Armadilha nº1"). Um chunk
buscável de ata é, na prática, um `pessoas.nome` sem os controles da tabela `pessoas`.

**`cpf_hash` é pseudonimização, não anonimização — logo é dado pessoal.** HMAC determinístico
sobre um domínio de ~10⁹ CPFs válidos é reversível por força bruta para quem tem o pepper, e o
pepper é do próprio controlador: é a hipótese literal do art. 12 ("meios próprios") e a definição
do art. 13, §4º. Consequências: `cpf_hash` **nunca** entra em `audit.log` (é redigido junto com
`cpf_enc`), e apagar só o `cpf_enc` numa anonimização não elimina nada. Parecer:
`docs/juridico/pareceres/2026-09-04-cpf-hash-na-trilha.md`.

## 2. Base legal por finalidade — nunca consentimento

Duas bases cobrem o produto:

- **Cumprimento de obrigação legal** (LGPD art. 7º, II) — o síndico tem dever legal de prestar
  contas (Código Civil, art. 1.348 [NÃO CONFIRMADO — verificar inciso exato antes de citar em
  peça formal]). Tratar nome, unidade e valor em lançamento e balancete decorre desse dever.
- **Legítimo interesse** (LGPD art. 7º, IX, requisitos do art. 10) — fiscalização financeira
  pelo conselho e pelos moradores sobre a própria gestão. Concreto, proporcional, e não
  sobrepõe direitos do titular de forma desproporcional — porque o dado mais sensível
  (inadimplência nominal) já fica restrito a quem tem dever de sigilo (`conselho`, `editor`).

**Por que consentimento é errado aqui:** consentimento supõe que o titular pode recusar sem
prejuízo, e aqui não pode — morar na unidade já sujeita à prestação de contas e ao rateio, por
convenção e lei, não por vontade individual. Consentimento traria direito de revogação (art. 8º,
§5º) que, exercido, impediria registrar o lançamento daquele morador — inviabilizando a própria
contabilidade. É também operacionalmente mais frágil (prova de consentimento, gestão de
revogação) para uma finalidade que já tem base mais forte e estável disponível.

## 3. Minimização por papel

Cada papel vê o mínimo necessário à função, nunca o máximo disponível.

- **`editor`** (hoje só a dona do projeto) — único papel que vê CPF em claro (`cpf_enc`, via
  rotina de servidor) e único que escreve lançamento. Também o ponto único de exposição total —
  toda leitura de CPF em claro pela `editor` deve ser logada em `audit.acesso` como acesso
  sensível, não só como escrita.
- **`conselho`** — leitura financeira completa, incluindo inadimplência nominal, anexos e
  cotações na íntegra, mas **CPF sempre mascarado** (SPEC §7). Fiscaliza saldo e despesa; CPF em
  claro seria excesso frente à finalidade.
- **`morador`** — acervo publicado, financeiro agregado, dado da própria unidade. Nunca dado
  nominal de outra unidade, nunca CPF alheio, nunca PII de terceiro não-condômino.
- **`sindico_terceirizado`** — não é usuário, sem login, sem papel de acesso. Referenciado como
  sujeito (`fornecedores`, alertas), nunca como titular de sessão — nenhuma tela pode assumir
  que ele lê algo dentro do produto; comunicação com ele é sempre externa (e-mail, PDF).

Minimização não é só "quem lê a tabela" — é também "quantos campos o SELECT traz". Uma view de
`cobrancas` para `morador` nunca faz `SELECT *`; traz só a própria unidade mais o agregado.

**Minimização tem eixo temporal, não só de papel.** "Quem vê" inclui "até quando vê". Papel e
vínculo têm mandato datado e expiram sozinhos; qualquer flag booleana usada como portão de acesso
(`pessoas.ativa`) não expira e vira acesso indevido silencioso. Ver seção 6-bis. E o eixo temporal
tem **resolução**, não só existência: coluna `date` dentro de predicado de autorização é sinal de
alerta desta skill, porque promete um corte que ela não consegue executar. Ver seção 6-ter.

## 4. Inadimplência: por que nunca nominal para morador

Maior potencial de constrangimento do produto — expõe dificuldade financeira de vizinho
identificável. O princípio da necessidade (art. 6º, III) exige tratamento limitado ao mínimo
necessário à finalidade; para o morador comum, a finalidade legítima é entender a saúde
financeira do condomínio, não vigiar o vizinho. Exposição nominal ampla cria risco real de
constrangimento, cobrança extrajudicial informal ou represália social — nenhum desses é
finalidade do produto.

**Forma correta:** sempre agregada para `morador` — percentual de unidades inadimplentes, valor
total em aberto, em **faixas de aging** (0–30, 31–60, 61–90, 90+ dias), nunca com contagem que
permita inferir uma unidade específica em condomínio pequeno (faixa com N=1: agregar mais ou
suprimir). Inadimplência **nominal** (unidade + valor + aging) fica atrás da RLS de
`conselho`/`editor`, com log de acesso obrigatório (SPEC §5.5) — mesmo restrito a quem tem
dever de sigilo, é dado que exige trilha de quem olhou.

**O padrão "agregado para o morador, íntegra para a gestão" vale além da inadimplência.** É a
mesma solução para cotação de fornecedor: o morador vê quantas propostas houve, de quem e por
quanto — o suficiente para conferir o alerta "cotação ausente" do SPEC §5.3 — sem receber o PDF
com CPF e telefone do vendedor. Ver `condominio-documentos` §12-bis e
`docs/juridico/pareceres/2026-09-04-visibilidade-cotacoes.md`.

## 5. CPF: hash para lookup, versão reversível para exibição

Dois campos, dois propósitos:

- `cpf_hash` — HMAC-SHA256 com pepper fora do banco (variável de ambiente do servidor).
  Determinístico por definição de HMAC — mesmo CPF sempre gera o mesmo hash, o que permite
  `unique(cpf_hash)` e lookup no login. Não reversível **sem o pepper** — e, com ele, reversível
  por enumeração. É pseudônimo, não anônimo (seção 1).
- `cpf_enc` — criptografia reversível, decifrável só pela `editor` por rotina de servidor, para os
  raros casos administrativos em que o CPF em claro é necessário.

**Regra dura do login (SPEC §2.1):** CPF não é secreto — é enumerável (sequencial, ligado a
órgão emissor, há validadores públicos). Por isso CPF nunca é credencial, é alias de busca:
`CPF ou e-mail → lookup em cpf_hash → magic link ao e-mail cadastrado`. Sessão nunca nasce do
CPF sozinho.

**Por que a resposta do login precisa ser idêntica para CPF existente e inexistente:** resposta
diferenciada ("e-mail enviado" vs. "CPF não encontrado") transforma a tela em oráculo público de
"esta pessoa mora aqui" — qualquer um testa uma lista de CPFs e descobre quem é morador, o que já
é vazamento (associação pessoa↔condomínio) sem tocar em nenhum dado financeiro. Resposta sempre
genérica — "se cadastrado, enviamos um link" — nos dois casos, com tempo de resposta equivalente
para evitar side-channel por timing.

## 6. Retenção e descarte

Por tipo (SPEC §7):

- **Atas, convenção, laudos técnicos** — permanentes; valor legal e histórico contínuo.
- **Financeiro, cobranças e cotações** — 5 anos (Lei 4.591/64, art. 22, §1º, "g").
- **Log de acesso** (`audit.acesso`: quem consultou inadimplência nominal, quem leu CPF em claro)
  — 6 meses.
- **`audit.log`** — permanente e não expurgável, por construção (cadeia de hash).

## 6-bis. Off-boarding de ex-morador — dois estágios, nunca um

Parecer completo: `docs/juridico/off-boarding-ex-morador.md`. Resumo normativo:

**Estágio 1 — desativar o acesso, em `vinculos.fim`, com zero dias de tolerância.**
O direito de inspecionar documentos da administração é direito **do condômino**: extinta a
condição, extingue-se o direito.

> **Cite certo — correção de 2026-09-06, com o texto do Planalto em mãos.** Este direito **não**
> está no **CC art. 1.335**, e esta skill o atribuía a ele. O art. 1.335 vigente tem três incisos —
> usar/fruir/dispor da unidade, usar as partes comuns, e *votar nas deliberações da assembleia e
> delas participar, estando quite* — e **nenhum** menciona documentos. Fundamento textual correto:
> **CC art. 1.348, VIII** ("compete ao síndico [...] prestar contas à assembleia, anualmente e
> quando exigidas") + **CC art. 1.335, III** (participar da assembleia é direito de quem é
> condômino) + **Lei 4.591/64, art. 22, §1º, "g"**. O caráter **individual** — fiscalizar fora da
> assembleia — é **jurisprudencial, não textual**; `REsp 2.050.372` circula no projeto e
> **não foi verificado em acórdão**. Não repita o número como se fosse fonte checada. A conclusão
> não muda: o art. 1.335, III diz com todas as letras que o direito é *da condição*.

Manter leitura de `autenticado` depois disso viola necessidade (art. 6º, III) e o art. 15, I
(fim da finalidade). O acesso deve ser **derivado** do fato datado — vínculo vigente **ou** papel vigente — nunca de flag booleana
que exige um UPDATE humano que ninguém lembra de rodar. Não construir janela de acesso degradado:
o que o ex-morador tem direito de obter (cópia do próprio período, LGPD art. 18, II; documento
para defesa em processo, art. 7º, VI) se atende **por export sob pedido**, com registro em
`audit.acesso`, não por sessão aberta.

**Estágio 2 — anonimizar a PII cadastral, em `vinculos.fim + 5 anos.`**
Anonimizar já no `fim` é **erro** — foi a redação anterior desta skill e está corrigida aqui.
Cedo demais destrói a capacidade de cobrar débito remanescente, de responder a pedido do titular
e de provar quitação dentro do prazo de guarda de **5 anos** (Lei 4.591/64, art. 22, §1º, "g" —
único piso legal explícito de guarda documental condominial). Ao vencer o prazo, sem outro vínculo
ou papel vigente: (a) preservar todo lançamento, cobrança e agregado do período vinculado — seguem
fazendo parte da prestação de contas; (b) anonimizar o PII direto (`nome` → identificador
genérico; `cpf_hash`/`cpf_enc`/`cpf_ultimos_digitos`/`email`/`telefone` → nulos; `auth_user_id` →
nulo), preservando `pessoa_id` como chave técnica para os agregados históricos seguirem
consistentes. É anonimização (LGPD art. 12), não eliminação de registro — depois dela a LGPD
deixa de se aplicar porque o dado não identifica mais ninguém.

**Nunca se anonimiza — lista fechada, e cada item por um motivo distinto:**

| Objeto | Por quê |
|---|---|
| `pareceres` / `parecer_signatarios` de quem foi conselheiro | A assinatura **é** a validade do ato (CC art. 1.356). Anonimizar destrói a força probatória do parecer, não protege ninguém. LGPD art. 16, I |
| `audit.log` | Redação retroativa quebra a cadeia de hash e com ela toda a garantia de não-adulteração. A trilha só fica coberta se `actor` for **id**, nunca nome denormalizado — verificar antes de assumir |
| Nome, unidade e voto em ata e deliberação | Registro da assembleia; art. 16, I |
| `lancamentos`, `cobrancas` do período | Prestação de contas; imutáveis por ADR-0011 |

**A anonimização é parcial quanto à trilha, e isso se diz ao titular.** `audit.log` guarda
`antes`/`depois` de `pessoas`: `nome`, `email` e `telefone` permanecem lá por decisão de
proporcionalidade (art. 7º, IX + art. 10) — nome já é permanente em atas de qualquer forma, e
e-mail/telefone têm valor fiscalizatório específico (provar desvio de magic link pela editora
única). `cpf_hash` e `cpf_enc` **não** permanecem: são redigidos na escrita. Ao responder pedido
de eliminação, a `editor` informa esse limite com a base legal, em vez de afirmar eliminação
completa — afirmar completude e não entregar é pior que a retenção.

**O que a rotina não consegue fazer sozinha:** detectar venda que ninguém informou. Nenhum schema
adivinha o fato do mundo. O máximo honesto é tornar a inconsistência **visível** — alerta de
unidade sem vínculo vigente e de pessoa ativa sem vínculo e sem papel — não fingir automação.

## 6-ter. Quando o acesso cessa — o fato datado e o fato instantâneo

Vale para **qualquer** portão de leitura derivado de período, não só `vinculos`. Origem:
`docs/juridico/pareceres/2026-09-06-default-da-tela-encerramento-de-vinculo.md` e ADR-0030.

### "+ 0 dias" é zero tolerância depois do fato — não é "resolução de um dia"

O veto desta função diz que o acesso cessa em `vinculos.fim` **+ 0 dias**. Isso sempre significou
**nenhuma janela de carência depois do fato** — foi assim que a §6-bis recusou o acesso degradado de
90 dias. **Nunca** significou que um dia inteiro de folga é aceitável.

Foi o que aconteceu na prática, e ninguém percebeu por meses: com as colunas de período em `date` e
o intervalo **fechado** (`fim >= current_date`), quem vendeu a unidade às 9h continuava lendo o
acervo até a meia-noite, e revogar *hoje* um vínculo ou mandato aberto *hoje* era literalmente
inexprimível — `fim = hoje` seguia vigente, `fim = ontem` violava o `CHECK`. A frase do parecer era
verdadeira na intenção e falsa no mecanismo.

**Regra que fica:** coluna que participa de predicado de autorização **não pode ter resolução mais
grossa que o ato que ela autoriza**, e o intervalo é **meia-aberto** — `[inicio, fim)`, avaliado em
`now()`. Intervalo fechado torna "cessar agora" impossível e obriga a mentir numa das duas pontas.
`date` num predicado de autorização é achado, não detalhe de estilo.

### O direito é da condição, não do registro — e por isso a ponta é um proxy

O acesso do condômino existe porque ele **é** condômino; extingue-se quando a condição se extingue,
**não** quando alguém digita na tela. Qualquer valor gravado em `fim` é, portanto, um **proxy** de um
fato do mundo, e a pergunta correta nunca é "qual é o valor certo?", e sim "**qual proxy erra
menos, e para que lado?**".

Os dois erros não são simétricos:

| Proxy | Erra assim | Gravidade |
|---|---|---|
| Cessar **no instante do registro** | corta o acesso **antes** do fim do vínculo real (venda registrada com antecedência) | **Viola direito em vigor.** A pessoa ainda é condômina e perde documento que é dela. |
| Manter **até o fim do dia D** | mantém o acesso por horas depois do fato | **Excesso** (art. 6º, III) sobre dado a que ela teve acesso legítimo o dia inteiro. |

Entre suprimir direito atual e tolerar horas de excesso sobre dado já conhecido, **o excesso é o
erro menor**. Não porque excesso seja aceitável, mas porque o outro lado é lesão, não risco.

### O critério: a granularidade da ponta segue a granularidade do fato que a produz

**Fato datado.** A propriedade transfere-se com o **registro do título no Registro de Imóveis**
(CC art. 1.245, verificado em fonte primária) — evento que tem **data** na matrícula e hora que o
condomínio não conhece. Fim de locação e término de mandato, idem. Para estes, a ponta honesta é o
**fim do dia D**: `fim = (D + 1 dia) 00:00`, em **fuso explícito** (`America/Sao_Paulo`), nunca o
fuso implícito do servidor.

**Fato instantâneo.** Erro de cadastro, conta comprometida, óbito, renúncia, substituição de gestão
e pedido do próprio titular **não têm dia, têm momento** — o momento em que o controlador soube.
Aqui não há direito a preservar (o vínculo nunca existiu, ou o titular pediu, ou o acesso deixou de
ser dele), e esperar a meia-noite é excesso puro (art. 6º, III e art. 15, I) — em conta
comprometida, é descumprimento do dever de **segurança do tratamento (art. 46)**.

**Consequência de produto, e é a parte que se esquece:** a tela **não pergunta ao operador "agora ou
no dia D?"**. Escolha ambígua oferecida a quem está sob pressão é defeito de desenho, não
flexibilidade. O motivo do encerramento (`motivo_fim`, enum fechado, que ele já preenche por outra
razão) **classifica o fato**, e o sistema deriva a ponta. Campo de data só aparece para os motivos
datados.

**Três armadilhas de implementação que já custaram caro:**

- Gravar `now()` puro em vez de `greatest(inicio, now())`: com `inicio` futuro, viola o `CHECK` de
  período e reintroduz o beco que a mudança acabou de fechar.
- Data anterior ao `inicio`: a tela **recusa**, não corrige em silêncio — "terminou antes de
  começar" é contradição do fato, e clampear grava mentira. Se a intenção era desfazer, o motivo é
  erro cadastral, e o registro correto é o intervalo **vazio** (`fim = inicio`), não apagar a linha.
- Data no passado é gravação **normal**: a ponta já ficou para trás e o acesso cessa na gravação.
  Não existe revogação retroativa — o que já foi lido, foi lido; o remédio para o lançamento
  atrasado é o **alerta** de inconsistência da §6-bis, não o schema.

### A hora fica no banco, não na tela

Converter as colunas de período para instante torna o dado marginalmente mais granular sobre a
pessoa. Isso **não** muda base legal nem retenção, mas cria um dever: a interface exibe **data**,
para todos os papéis. "Vendeu a unidade às 09h14" não acrescenta nada à prestação de contas e é
granularidade a mais sobre pessoa (art. 6º, III). O instante é dado técnico de autorização — vive no
predicado e no `audit.log`, não na tela.

### O veto alcança o cache

**Papel e vínculo se leem sempre no banco.** Qualquer cache de renderização sobre eles — `use cache`,
cache de RSC, memoização de sessão, claim copiado para o token — **restaura a janela de acesso
pós-`fim` com um TTL que ninguém aprovou**, e desfaz do lado da aplicação o corte que o banco passou
a fazer no instante certo. É a mudança que alguém faz por **desempenho**, num arquivo de UI, sem
perceber que mexeu em autorização — e por isso ela não aparece em revisão de RLS. Se o portão é
derivado de período, cache sobre ele é decisão de visibilidade e passa por esta função.

## 7. Direitos do titular

Pedido de morador (acesso, correção, eliminação — LGPD art. 18):

- **Acesso** — `editor` exporta `pessoas`, `vinculos`, `cobrancas` da própria unidade do
  titular. CPF em claro só se o pedido vier do próprio titular autenticado, nunca por terceiro.
  Vale também para ex-morador dentro do prazo de guarda: é este o caminho, e não sessão mantida.
- **Correção** — dado cadastral simples corrigido direto pela `editor`; correção de CPF exige
  nova verificação, não só sobrescrever.
- **Eliminação** — aplicável a dado cadastral (e-mail, telefone) ao deixar o condomínio.
  **Não aplicável, e a recusar com justificativa:** lançamento, ata, deliberação ou anexo com
  valor contábil/legal — têm base legal própria (obrigação legal de prestação de contas),
  independente da vontade do titular, e são hipótese expressa de exceção ao direito de
  eliminação (LGPD art. 16). Resposta correta é explicar a base legal e, quando aplicável,
  aplicar a anonimização da seção 6-bis em vez da eliminação total — **informando que ela é
  parcial quanto a `audit.log`**.

Todo pedido e resposta ficam registrados (quem pediu, o que foi feito, quando).

## 8. Checklist do agente `juridico-lgpd` antes de publicar

Rodar antes de qualquer publicação nova (documento, campo novo em relatório, mudança de
visibilidade/retenção — gatilho do agente, `docs/02-AGENTES.md`):

1. O dado está no inventário da seção 1? Se não, atualizar antes de publicar.
2. Base legal exata (obrigação legal ou legítimo interesse)? Resposta "consentimento" ou
   "não sei" bloqueia.
3. O papel que vai enxergar é o mínimo necessário? `morador` veria algo restrito a
   `conselho`/`editor`?
4. Inadimplência agregada para `morador`? Nominal só atrás de RLS de `conselho`/`editor`, com
   log de acesso ativo?
5. CPF em claro só para `editor`, mascarado para `conselho`, ausente para `morador`?
6. `chunks` e `documento_paginas` espelham a `visibilidade`/RLS do `documentos` pai?
   (Armadilha nº1 — o erro mais fácil de cometer.)
7. Retenção definida (permanente/5 anos/6 meses) e rotina de descarte/anonimização existe?
8. Visibilidade `público`: só convenção e regimento passam sem redação. Ata e balancete exigem
   autenticação — proposta de publicar como público é veto automático sem etapa de anonimização.
9. Existe caminho testável de exercício de direito do titular para esse dado?
10. **O acesso a esse dado expira sozinho — e com que resolução?** Todo portão de leitura deriva
    de fato datado (vínculo ou mandato vigente). Portão que depende de alguém lembrar de um UPDATE
    é achado de vazamento, não pendência operacional (§6-bis). E a coluna do período tem resolução
    fina o bastante para o ato que autoriza, com intervalo **meia-aberto**? `date` em predicado de
    autorização é achado (§6-ter).
    - **Há cache entre o predicado e a tela?** `use cache`, cache de RSC ou claim no token sobre
      papel/vínculo reabre a janela pós-`fim` com TTL que ninguém aprovou. Cache sobre portão
      derivado de período é decisão de visibilidade, não de desempenho (§6-ter).
11. **Há PII de terceiro não-condômino** (representante de fornecedor, responsável técnico,
    funcionário) no que vai ser publicado? Ele nunca consentiu com nada e não tem relação com os
    moradores — o padrão é `conselho`. Ver `condominio-documentos` §12-bis.
12. **O dado vai parar em `audit.log`?** A trilha é permanente e irreparável. Identificador de
    alto poder de reidentificação (CPF em qualquer forma, inclusive `cpf_hash`) tem de ser
    redigido **na escrita** — depois é tarde, porque corrigir quebra a cadeia.

Item que falhar é veto, não sugestão — `juridico-lgpd` tem poder de veto explícito
(`docs/02-AGENTES.md`, item 3).
