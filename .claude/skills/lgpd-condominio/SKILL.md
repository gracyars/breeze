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
| Nome | `pessoas.nome`, atas, deliberações | Identificador direto |
| CPF | `pessoas.cpf_hash` (HMAC, lookup) e `cpf_enc` (reversível) | Identificador direto, alto risco de mau uso |
| E-mail, telefone | `pessoas` | Identificador de contato |
| Unidade (bloco/número) | `vinculos` | Quase-identificador — cruza com nome em condomínio pequeno |
| Situação de pagamento | `cobrancas` | Financeiro, alto potencial de constrangimento |
| Conteúdo de atas | `documentos`, `documento_paginas`, `chunks` | Cita pessoas nominalmente, votos; pode incluir terceiros não-usuários (convidado, prestador) |
| Anexos financeiros | `lancamento_anexos` | Notas e recibos, às vezes com CPF de terceiro (prestador pessoa física) |

**Texto de ata e anexo carregam PII fora de qualquer campo estruturado** — por isso `chunks` e
`documento_paginas` precisam da mesma RLS de `documentos` (SPEC §7, "Armadilha nº1"). Um chunk
buscável de ata é, na prática, um `pessoas.nome` sem os controles da tabela `pessoas`.

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
  view dedicada) e único que escreve lançamento. Também o ponto único de exposição total — toda
  leitura de CPF em claro pela `editor` deve ser logada em `audit.log` como acesso sensível,
  não só como escrita.
- **`conselho`** — leitura financeira completa, incluindo inadimplência nominal e anexos, mas
  **CPF sempre mascarado** (SPEC §7). Fiscaliza saldo e despesa; CPF em claro seria excesso
  frente à finalidade.
- **`morador`** — acervo publicado, financeiro agregado, dado da própria unidade. Nunca dado
  nominal de outra unidade, nunca CPF alheio.
- **`sindico_terceirizado`** — não é usuário, sem login, sem papel de acesso. Referenciado como
  sujeito (`fornecedores`, alertas), nunca como titular de sessão — nenhuma tela pode assumir
  que ele lê algo dentro do produto; comunicação com ele é sempre externa (e-mail, PDF).

Minimização não é só "quem lê a tabela" — é também "quantos campos o SELECT traz". Uma view de
`cobrancas` para `morador` nunca faz `SELECT *`; traz só a própria unidade mais o agregado.

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

## 5. CPF: hash para lookup, versão reversível para exibição

Dois campos, dois propósitos:

- `cpf_hash` — HMAC-SHA256 com pepper fora do banco (variável de ambiente do servidor).
  Determinístico por definição de HMAC — mesmo CPF sempre gera o mesmo hash, o que permite
  `unique(cpf_hash)` e lookup no login. Não reversível.
- `cpf_enc` — criptografia reversível, decifrável só pela `editor` via view dedicada, para os
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
- **Financeiro e cobranças** — 5 anos, alinhado ao prazo usual de guarda contábil/fiscal no Brasil.
- **Log de acesso** (quem consultou inadimplência nominal, quem leu CPF em claro) — 6 meses.

**Rotina de anonimização de ex-morador:** ao encerrar o vínculo (`vinculos.fim`) sem outro
vínculo ativo, a rotina deve (a) preservar todo lançamento, cobrança e agregado do período
vinculado — seguem fazendo parte da prestação de contas e não podem sumir; (b) apagar ou
anonimizar o PII direto (`nome` → identificador genérico, `cpf_hash`/`cpf_enc`/`email`/
`telefone` → nulos), preservando `pessoa_id` como chave técnica para os agregados históricos
seguirem consistentes. É anonimização (LGPD art. 12), não eliminação de registro — depois dela a
LGPD deixa de se aplicar porque o dado não identifica mais ninguém.

## 7. Direitos do titular

Pedido de morador (acesso, correção, eliminação — LGPD art. 18):

- **Acesso** — `editor` exporta `pessoas`, `vinculos`, `cobrancas` da própria unidade do
  titular. CPF em claro só se o pedido vier do próprio titular autenticado, nunca por terceiro.
- **Correção** — dado cadastral simples corrigido direto pela `editor`; correção de CPF exige
  nova verificação, não só sobrescrever.
- **Eliminação** — aplicável a dado cadastral (e-mail, telefone) ao deixar o condomínio.
  **Não aplicável, e a recusar com justificativa:** lançamento, ata, deliberação ou anexo com
  valor contábil/legal — têm base legal própria (obrigação legal de prestação de contas),
  independente da vontade do titular, e são hipótese expressa de exceção ao direito de
  eliminação (LGPD art. 16). Resposta correta é explicar a base legal e, quando aplicável,
  aplicar a anonimização da seção 6 em vez da eliminação total.

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

Item que falhar é veto, não sugestão — `juridico-lgpd` tem poder de veto explícito
(`docs/02-AGENTES.md`, item 3).
