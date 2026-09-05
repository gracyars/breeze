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
(`pessoas.ativa`) não expira e vira acesso indevido silencioso. Ver seção 6-bis.

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
O direito de inspecionar documentos da administração é direito **do condômino** (CC art. 1.335;
STJ REsp 2.050.372): extinta a condição, extingue-se o direito. Manter leitura de `autenticado`
depois disso viola necessidade (art. 6º, III) e o art. 15, I (fim da finalidade). O acesso deve
ser **derivado** do fato datado — vínculo vigente **ou** papel vigente — nunca de flag booleana
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
10. **O acesso a esse dado expira sozinho?** Todo portão de leitura deriva de fato datado
    (vínculo ou mandato vigente). Portão que depende de alguém lembrar de um UPDATE é achado
    de vazamento, não pendência operacional — ver seção 6-bis.
11. **Há PII de terceiro não-condômino** (representante de fornecedor, responsável técnico,
    funcionário) no que vai ser publicado? Ele nunca consentiu com nada e não tem relação com os
    moradores — o padrão é `conselho`. Ver `condominio-documentos` §12-bis.
12. **O dado vai parar em `audit.log`?** A trilha é permanente e irreparável. Identificador de
    alto poder de reidentificação (CPF em qualquer forma, inclusive `cpf_hash`) tem de ser
    redigido **na escrita** — depois é tarde, porque corrigir quebra a cadeia.

Item que falhar é veto, não sugestão — `juridico-lgpd` tem poder de veto explícito
(`docs/02-AGENTES.md`, item 3).
