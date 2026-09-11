# Parecer — Subida a produção com o acervo real (Supabase hospedado + Vercel)

**Data:** 2026-09-07
**Agente:** `juridico-lgpd`
**Pedido:** autorizar a criação de um projeto Supabase hospedado + app na Vercel recebendo os 43
PDFs reais do acervo (313 páginas, 201 trechos indexados). Primeira vez que dado pessoal do
condomínio sai da máquina da dona do projeto.
**Fontes lidas:** `docs/01-SPEC.md` §2, §2.1, §7; `docs/04-DECISOES.md` D2/D3;
`docs/inventario-acervo.md`; `docs/juridico/off-boarding-ex-morador.md`; pareceres de 2026-09-04 e
2026-09-06; ADR-0004, 0006, 0009, 0014, 0018, 0019, 0024, 0030; `docs/ops/backup.md`,
`docs/ops/runbook-deploy.md`, `docs/ops/divida-tecnica.md`; skills `lgpd-condominio`,
`condominio-legal`. Inspeção própria dos 43 PDFs (varredura de padrões de PII, sem reproduzir
conteúdo — ver §3).

---

## Veredito global

> **APROVADO COM CONDIÇÃO, em três portões sequenciais.**
>
> **Não é um "não".** Nada no acervo, nem na arquitetura, impede a subida. O que existe é uma
> ordem obrigatória: **o dado documental pode subir antes do backup; a primeira pessoa cadastrada
> e a primeira publicação, não.**
>
> - **Portão A — subir o acervo (dado documental, visibilidade só-gestão):** 7 condições, todas
>   baratas, nenhuma depende de terceiro. **Libera hoje.**
> - **Portão B — cadastrar qualquer pessoa que não seja a editora:** 6 condições, entre elas o
>   backup exercitado e o registro de quem é o controlador. **Vetado até estarem satisfeitas.**
> - **Portão C — publicar qualquer documento (sair de `em_revisao`):** 5 condições por documento.
>   **Vetado até o Portão B fechar e o checklist rodar documento a documento.**
>
> **Resposta direta à pergunta de sequência do orquestrador:** *não* é "pode subir, mas só depois
> do backup". É **"pode subir o acervo antes do backup; não pode ter usuário nem publicação antes
> dele"**. O motivo está em §1.4 e não é formalidade: hoje o acervo tem cópia autoritativa fora do
> Breeze (a máquina da dona e o portal da administradora), então perdê-lo é aborrecimento, não
> incidente. No instante em que existir um `pessoas` com CPF real, produção passa a ser a **única**
> cópia de um dado pessoal — e aí ausência de backup vira descumprimento do art. 46.

**Base legal do tratamento (não muda por causa da hospedagem):** obrigação legal (LGPD art. 7º, II
— CC art. 1.348, VIII, dever de prestar contas, verificado em fonte primária) e legítimo interesse
(art. 7º, IX, com o teste do art. 10 — fiscalização da gestão pelos condôminos). **Nunca
consentimento** (D2; skill §2). Detalhamento e o papel de Supabase/Vercel em §4.

**Retenção fixada para o que este parecer autoriza** (SPEC §7):

| Objeto que passa a existir em produção | Retenção | Fundamento |
|---|---|---|
| Os 43 PDFs no bucket `documentos` + texto extraído + chunks | Atas, convenção, regimento e laudos: **permanente** (decisão de produto). Balancetes, cotações e comunicados financeiros: **5 anos** | Lei 4.591/64, art. 22, §1º, "g" |
| `pessoas` (quando existirem) | Ativa enquanto houver vínculo ou papel vigente; PII cadastral anonimizada em `vinculos.fim + 5 anos` | `off-boarding-ex-morador.md` §4 |
| `audit.acesso` | **6 meses** | SPEC §7 |
| `audit.log` | **Permanente, não expurgável** | ADR-0013 |
| Dumps de backup cifrados | 12 semanais + 12 mensais | `backup.md` §4 |
| Logs do provedor (Supabase/Vercel) | **Não definido — item aberto**, ver §5.4 | — |

---

## 1. Pode subir? Condições, por portão

### 1.1 Portão A — condições bloqueantes para o acervo subir

Todas verificáveis em uma sessão, nenhuma depende de resposta de terceiro.

| # | Condição | Por quê é bloqueante |
|---|---|---|
| **A1** | Projeto Supabase criado em **`sa-east-1` (São Paulo)** | Região de projeto Supabase é **imutável depois da criação** — trocar é criar projeto novo e restaurar. Errar aqui custa a migração inteira. Peso jurídico em §2. |
| **A2** | **Direção expressa de região registrada por escrito** (`docs/juridico/registro-operacoes.md`), não só a escolha no painel | O DPA da Supabase (cl. 6.1) diz que ela pode tratar "anywhere that Supabase or its Sub-processors maintain facilities", *salvo* se o cliente direcionar região específica. Sem a direção registrada, o padrão contratual é global e a escolha de `sa-east-1` não é oponível. |
| **A3** | **DPAs aceitos e arquivados** — Supabase (`/legal/customer-resources/data-processing-addendum`) e Vercel (`/legal/dpa`), com data e versão, mais snapshot da lista de subprocessadores de cada um | É o instrumento que torna os dois **operadores** (art. 39) em vez de destinatários indefinidos. Sem ele não há instrução documentada, e o controlador responde sozinho por tudo (art. 42). |
| **A4** | **Registro de operações de tratamento** (art. 37) existindo antes do primeiro byte real | O art. 37 é expresso: o registro é exigido **especialmente quando o tratamento se baseia no legítimo interesse** — que é uma das nossas duas bases. Conteúdo mínimo em §4.3. É um `.md` de uma hora de trabalho; não há justificativa para deixá-lo para depois. |
| **A5** | **Env vars escopadas só a Production na Vercel**; Preview e Development sem credencial de produção; `git.deploymentEnabled` restrito a `main` (já está em `vercel.json`) | ADR-0009 regra 4. Preview de PR com credencial de produção é acesso a dado real por URL não listada — e URL de preview da Vercel é adivinhável o bastante. |
| **A6** | **Deployment Protection ligada antes do primeiro deploy** (`runbook-deploy.md` §4) | Enquanto não houver aviso de privacidade e canal do titular (Portão B), a URL pública não deve responder a estranho. É a compensação temporária que torna o Portão A defensável sem o Portão B. |
| **A7** | **MFA ligado nas contas Supabase, Vercel e GitHub da dona** | Com editora única (D4) e conta pessoal (§6), o comprometimento de uma dessas contas é o comprometimento do acervo inteiro e da chave. Art. 46 pede medida "apta a proteger" — MFA em conta administrativa é o piso, não o extra. |

**Já satisfeito, verificado nesta sessão:** `Documentos do Condomínio/` está no `.gitignore`
(linha 57) e nenhum dos 43 arquivos está rastreado pelo git — o repositório pode ganhar remoto sem
levar o acervo junto. Este era o vetor de vazamento mais provável de todos e ele já está fechado.

### 1.2 Portão B — vetado até: cadastrar pessoa que não seja a editora

Enquanto só a editora tiver conta, o que existe em produção é a **cópia de documentos que ela já
detém legitimamente como condômina e conselheira**, num servidor que ela controla, sem ninguém
mais lendo. Isso é sustentável em legítimo interesse próprio. **No instante em que ela cadastra a
segunda pessoa, muda a natureza do tratamento**: passa a coletar CPF, e-mail e vínculo de
terceiros, e a operar um serviço para uma coletividade. Condições:

| # | Condição | Dono |
|---|---|---|
| **B1** | **Quem é o controlador está registrado por escrito** — deliberação de assembleia, autorização escrita da sindicatura, ou registro equivalente (§6) | dona do projeto |
| **B2** | **Aviso de privacidade publicado e alcançável sem login** (art. 9º), linkado do rodapé e da tela `/entrar` — conteúdo em §5.1 | quem fizer UI |
| **B3** | **Canal do titular funcionando** (art. 18, §1º + art. 41), alcançável por quem **não** tem conta | dona do projeto |
| **B4** | **Backup em conta separada rodado com sucesso pelo menos uma vez** (`backup.md` §3, `runbook-deploy.md` passo 1) | `devops` |
| **B5** | **`CPF_HASH_PEPPER` e `CPF_ENC_KEY` com cópia fora da conta do provedor** (ADR-0014: perder a chave de cifra congela o pepper para sempre) | dona do projeto |
| **B6** | **`cpf_enc` implementado em código** — hoje não existe (dívida C1-2); cadastrar pessoa real hoje grava bytes de enfeite na coluna que deveria ser a cifra | quem implementar o cadastro |

**Não é condição, e digo para não ser confundido:** runbook de restauração *exercitado em
produção*. O primeiro restore de verdade é exigência do SPEC §7 e do `backup.md` §1.5 e continua
valendo — mas ele acontece depois de existir o que restaurar. Exigir restore antes de haver dado é
circular. O que exijo em B4 é o **backup ter rodado uma vez com sucesso**; o restore trimestral
segue como compromisso com prazo, e o primeiro cai em até 90 dias do Portão B.

### 1.3 Portão C — vetado até: publicar qualquer documento

Por documento, o checklist de `docs/juridico/checklist-publicacao.md` (criado junto com este
parecer). As cinco condições estruturais:

| # | Condição |
|---|---|
| **C1** | **Etapa de redação de CPF/RG no texto extraído**, antes do chunk. Não é hipótese: a ata da AGI de 04.12.2025 traz **CPF e RG completos, em claro** (§3.2). Indexar sem redigir transforma "qual o CPF do síndico" em consulta de busca — mudança de natureza, não de grau (skill §8, itens 11 e 12). |
| **C2** | **Convenção registrada não vai ao bucket `publicos` sem inspeção da qualificação das partes.** Convenção registrada em cartório costuma trazer nome, CPF, RG e endereço do representante da incorporadora e dos proprietários originais. `publicos` é leitura **sem login, pela internet inteira** (ADR-0004). Publicar antes de olhar é veto automático (skill §8, item 8). |
| **C3** | **Visibilidade decidida pela página mais restritiva** (ADR-0019: `documentos.visibilidade` é o piso), com atenção à ata de 04.02.2026 que embute o regimento — a cópia pública é o arquivo autônomo (#43), nunca a ata continente. |
| **C4** | **`chunks` e `documento_paginas` espelhando a RLS do documento pai** — verificado pela suíte, mas reconfirmado no ambiente hospedado (dívida D2, §5.4). |
| **C5** | **Parecer específico do `juridico-lgpd` para qualquer documento que não seja convenção ou regimento indo a `publico`** — decisão que este agente **não toma sozinho** (§7). |

### 1.4 Por que o backup **não** bloqueia o Portão A

Sendo explícito, porque é a única parte deste parecer que afrouxa uma regra existente e ela
merece ser contestável:

O `runbook-deploy.md` §0 hoje trava os 43 documentos no backup. Discordo, e a razão é factual: os
43 PDFs **não nascem em produção**. Existem na máquina da dona, e existem no portal da
administradora — vários deles têm "SITE" no próprio nome de arquivo, isto é, são a versão que a
administradora já distribui. Perder o bucket de produção amanhã custaria refazer o upload e a
curadoria: **horas de trabalho, zero dado perdido**. Backup protege contra perda; sem perda
possível, ele não é o controle que trava esta etapa.

O que muda tudo é `pessoas`. CPF, e-mail e vínculo de morador **nascem em produção e só existem
lá**. Perdê-los é perder dado pessoal sob a guarda do controlador — art. 46 c/c art. 6º, VII, e um
incidente comunicável. Por isso o backup é bloqueante no Portão B e não no A.

Efeito prático, que é o que interessa: **a dona não precisa esperar a conta de backup para ver o
acervo real dentro do produto.** Ela pode criar o projeto, aplicar as migrações, subir os 43 PDFs,
rodar a ingestão e curar os documentos — sozinha, atrás da Deployment Protection, sem ninguém mais
entrando. É o caminho mais curto para o produto no ar, e ele está liberado hoje.

---

## 2. Região e transferência internacional

**Veredito: `sa-east-1` é BLOQUEANTE — mas não pela razão que costuma ser dada.**

### 2.1 Bloqueante por irreversibilidade, antes de ser bloqueante por direito

Região de projeto Supabase não se troca depois. Uma escolha errada só se corrige com projeto novo
+ restore + rotação de chaves + novo `project-ref` em toda a configuração. Uma decisão de um
clique cujo erro custa uma migração inteira é bloqueante independentemente do peso jurídico.

### 2.2 O que `sa-east-1` resolve, e o que não resolve

`sa-east-1` **elimina a transferência internacional do corpo do dado** — os PDFs, o Postgres, o
Storage ficam em São Paulo. Isso não é pouco: é a maior parte do volume e a totalidade do
conteúdo.

**Não elimina a transferência internacional.** Permanecem, e é honesto listá-las:

- **Plano de controle e suporte.** Supabase Inc. e Vercel Inc. são empresas norte-americanas; o
  acesso administrativo, o suporte e a telemetria operacional partem de fora do Brasil. Acesso
  remoto a partir do exterior é, na leitura corrente, transferência internacional (art. 5º, XV).
- **CDN da Vercel.** A rede de borda é global por construção. Isso é **inofensivo para o conteúdo
  sensível**, porque o desenho já manda que nada com PII seja cacheável (ADR-0004 regra 2, SPEC
  §7 — rota que assina URL é `no-store`). Mas é uma condição a manter, não um fato garantido: se
  alguém cachear uma resposta com dado pessoal, a proteção some sem aviso.
- **Subprocessadores** de ambos, listados nas páginas públicas de cada um.

### 2.3 O mecanismo de transferência — e a lacuna que eu não consigo fechar

A LGPD trata transferência internacional em capítulo próprio (arts. 33 a 36). A Resolução CD/ANPD
nº 19, de 23/08/2024, aprovou as **cláusulas-padrão contratuais** brasileiras, e o período de
adequação **encerrou em 23/08/2025** — ou seja, hoje elas são exigíveis, não opcionais.

Verifiquei o texto dos dois DPAs nesta sessão:

- **Supabase** — "Applicable Data Protection Laws" enumera GDPR, leis suíças e leis estaduais dos
  EUA. **Não menciona LGPD, Brasil ou ANPD. Não há anexo brasileiro.** Incorpora as SCC
  **europeias**, não as da ANPD.
- **Vercel** — define "Applicable Data Protection Laws" com "without limitation" e enumera GDPR,
  UK DPA 2018, CCPA, PIPEDA e Australian Privacy Act. O Schedule 4 traz termos específicos para
  essas mesmas cinco jurisdições. **Brasil e LGPD ausentes de ambos.**

**Conclusão sem maquiagem: a lacuna de cláusulas-padrão da ANPD existe e não é fechável pela dona
do projeto.** Nenhum condomínio de ~50 unidades negocia adendo contratual com a Vercel Inc. Fingir
que "está tudo certo" seria o tipo de parecer que não protege ninguém.

**Postura que recomendo, e é a que sustento por escrito:**

1. `sa-east-1` **obrigatório** — reduz a transferência ao mínimo residual (controle e suporte) e
   é a única parte que depende só de nós.
2. **Direção expressa de região registrada** (condição A2) — é o que dá efeito contratual à
   escolha diante da cl. 6.1 da Supabase.
3. **Registrar a lacuna como risco residual assumido**, com dono nomeado e data de reavaliação, no
   registro de operações. Risco documentado e assumido é postura de conformidade; risco não
   percebido é negligência. A diferença importa se um dia houver questionamento.
4. **Reavaliar em 12 meses** ou quando qualquer dos dois publicar termos brasileiros.
5. Se a exposição incomodar a dona mais do que o custo: a alternativa real é Postgres gerenciado
   por provedor brasileiro. **Não recomendo** — trocaria uma lacuna documental por perder Auth,
   Storage e RLS integrados, que são a espinha do produto, para um ganho jurídico marginal num
   tratamento de baixo risco. Registro a alternativa para que a escolha seja consciente.

**Resposta curta à pergunta:** a escolha de região é **bloqueante** (por irreversibilidade e por
ser o único fator sob nosso controle), mas **não é suficiente** — ela reduz a transferência, não a
elimina, e o mecanismo formal do art. 33 permanece imperfeito por limitação de mercado.

---

## 3. O que há de dado pessoal no acervo, nomeadamente

Varredura própria dos 43 PDFs por padrões (CPF, CNPJ, menção a CPF/RG, inadimplência, unidade,
saúde, biometria, assinatura). Nada de conteúdo pessoal reproduzido aqui.

### 3.1 O achado que mais importa — e é uma boa notícia

**Os três balancetes não contêm relação nominal de inadimplentes.** As 17 ocorrências de
"inadimplência/atraso/devedor" nos balancetes de dez/25, jan/26 e fev/26 são **todas agregadas** —
linhas do tipo "CONDOMINOS EM ATRASO" com valor total por fundo, no Resumo de Emissões e na
Posição Financeira. Nenhuma lista de unidade ou de nome.

Consequência: **os três balancetes podem ir a `autenticado` sem violar o SPEC §7.** Era a maior
ameaça de veto do lote e ela não se materializou.

Ressalva de inferência, que fica registrada e não bloqueia: em condomínio pequeno, um total em
atraso dividido pelo valor da cota dá o **número aproximado de unidades** inadimplentes. Isso não
identifica ninguém e é informação que a assembleia já discute abertamente. Aceitável. **Não
aceitável** seria o produto ordenar ou listar unidades de forma que permita inferir *quais* — é
exatamente o que o SPEC §7 proíbe e o que o checklist de publicação verifica.

### 3.2 Dado pessoal identificado, por documento

| Doc | O que há | Classificação | Visibilidade máxima |
|---|---|---|---|
| **#2 AGI 04.12.2025** | **CPF e RG completos, em claro, de pessoa natural** (qualificação do síndico), + CNPJ | Dado pessoal, **alto poder de reidentificação** | `autenticado` **com redação de CPF/RG no texto indexado** (C1). Nunca `publico`. |
| **#3 AGE 04.02.2026 (36 pp)** | CNPJ, menções a CPF/RG, deliberações, regimento embutido, dados de registro cartorário | Dado pessoal comum + documento misto | `autenticado`; piso do arquivo pela página mais restritiva (C3) |
| **#5 AGE 30.04.2026** | CNPJ, referências a unidade, deliberação sobre reconhecimento facial | Dado pessoal comum | `autenticado` |
| **#8 Convenção registrada** | Escaneada; qualificação das partes **não inspecionada** (só OCR local feito) | A verificar antes de publicar | **`publico` bloqueado até C2** |
| **#10 Carta de renúncia — síndico** | Nome de pessoa natural em contexto de saída de mandato | Dado pessoal comum, com carga reputacional | `autenticado`. Nunca `publico`. |
| **#22 Atestado de brigada** | **Lista nominal de treinados** (moradores e/ou funcionários) + nome e registro MTE do instrutor | Dado pessoal comum, inclui **terceiro não-condômino** (funcionário/instrutor) | `autenticado` — é informação de emergência de interesse dos moradores. Nunca `publico`. |
| **#23 Carta de apresentação da gestão** | Nomes de pessoas da administradora | Terceiro não-condômino (skill §8, item 11) | `autenticado` (é comunicado já distribuído a todos) |
| **#35–37 Cotações de segurança** | CNPJ, menções a CPF/RG, contato direto de vendedor, especificação técnica concorrencial | Dado pessoal de terceiro + sigilo comercial de concorrente | **`conselho`** — confirma o parecer de 2026-09-04 |
| **#39–41 Balancetes** | Inadimplência **agregada**, contas, fornecedores | Financeiro, sem PII nominal | `autenticado` |
| **#18, #19 Composição da cota** | Rateio; **sem** tabela por unidade na extração | Financeiro agregado | `autenticado` |
| **#33 Habite-se, #34 Manual, #38 Reformas** | Menções a CPF/RG em formulários e qualificação de responsáveis técnicos | Dado pessoal comum, baixo risco | `autenticado` |
| Demais comunicados | Sem PII detectada | — | `autenticado` |

### 3.3 Dado pessoal **sensível** (art. 11)

**Nenhum, e isso foi verificado, não presumido.**

- **"COMUNICADO FACIAL" (#25) não é biométrico.** Confirmado em `docs/ocr/medicao-vision-convencao.md`:
  é aviso de que o cadastro facial passou a ser feito por app de terceiro, com links de loja.
  **Levanto o sinalizador que eu mesmo havia posto no inventário.**
- As 8 ocorrências de "reconhecimento facial" nas cotações e na AGE de 30.04 são **especificação
  de equipamento e deliberação de compra** — terminais, quantidade, preço. Não há rosto, template
  nem cadastro no acervo.
- As 4 ocorrências de "doença/médico" na AGE de 04.02 são **texto normativo do regimento**
  (recebimento de encomenda em emergência, exigência de atestado para uso da academia). Regra
  abstrata não é dado de saúde de ninguém.

### 3.4 Algum dos 43 não deveria subir de jeito nenhum?

**Não.** Nenhum é barrado de existir no armazenamento privado da gestão. A restrição que este
parecer impõe é de **publicação**, não de guarda — e guardar é justamente o que a Lei 4.591/64,
art. 22, §1º, "g" manda fazer.

Duas ressalvas operacionais, que não são vetos:

- **#16** é duplicata byte-idêntica de #15. Já está em `erro` pelo `unique(sha256)`. Correto —
  deduplicar é minimização (art. 6º, III), não só higiene.
- **#8 (Convenção)** sobe, mas fica em `em_revisao` até C2. Subir ≠ publicar.

### 3.5 Achado fora do escopo do Breeze, que escalo mesmo assim

O acervo evidencia que o condomínio **contratou tratamento de dado biométrico de moradores** —
terminais de reconhecimento facial para 10.000 faces nas áreas comuns (cotação #36, deliberado na
AGE de 30.04) e cadastro facial por app de terceiro (#25). **Biometria é dado pessoal sensível
(art. 11, II, "b")**, com regime muito mais pesado: base legal restrita, aviso específico,
avaliação de impacto recomendada, e o fornecedor do app como operador com contrato próprio.

**Isso não é tratamento do Breeze e não afeta este veredito.** Registro por dois motivos: (a) é
exposição real do controlador que a dona provavelmente não mapeou; (b) **se algum dia se propuser
integrar o Breeze ao controle de acesso, isso é assunto novo, com parecer novo, e a resposta
padrão é não** — indexar o comunicado sobre biometria é uma coisa, tocar no template biométrico é
outra completamente diferente.

---

## 4. Base legal e registro de operações

### 4.1 A hospedagem em terceiro não tem base legal própria — e essa é a resposta

Erro comum: procurar "a base legal para usar a nuvem". Não existe. Hospedar não é finalidade nova;
é **meio** de executar o mesmo tratamento. Supabase e Vercel tratam **em nome do controlador**,
sob as instruções dele — são **operadores** (art. 5º, VII). A base legal continua sendo a do
tratamento original:

| Finalidade | Base legal | Fundamento |
|---|---|---|
| Guardar e organizar o acervo documental | **Obrigação legal** (art. 7º, II) | CC art. 1.348, VIII (prestar contas) + Lei 4.591/64, art. 22, §1º, "g" (guarda) |
| Dar acesso a condôminos para fiscalizar a gestão | **Legítimo interesse** (art. 7º, IX + art. 10) | Direito da condição de condômino; CC art. 1.335, III |
| Identificar quem é morador (CPF como alias, e-mail para magic link) | **Legítimo interesse** (art. 7º, IX) | Necessário para dar a cada um só o que é dele (D2, ADR-0003) |
| Trilha de auditoria (`audit.log`, `audit.acesso`) | **Legítimo interesse** (art. 7º, IX) | Não-adulteração e prova de acesso são o que dá autoridade ao produto (SPEC §7) |

**Nunca consentimento**, e a razão é substantiva, não estilística: morar na unidade já sujeita ao
rateio e à prestação de contas por lei e convenção; consentimento pressupõe recusa sem prejuízo,
que aqui não existe, e traria revogabilidade (art. 8º, §5º) que inviabilizaria a contabilidade
(skill §2). Mudança dessa base exige ADR explícito.

### 4.2 O que a figura do operador exige, concretamente

O ADR-0006 já usava "operador" para o fornecedor de OCR pago; o ADR-0024 tirou esse fornecedor do
caminho ao rodar OCR local. **A figura não sumiu — subiu de nível.** O que era um fornecedor
opcional de uma etapa agora é a hospedagem inteira. Exigências (arts. 39, 46, 47, 48):

1. **Contrato com cláusulas de proteção** — os DPAs (condição A3).
2. **Instruções documentadas** do controlador — região (A2), buckets privados (ADR-0004), sem
   cache de PII, retenção.
3. **Autorização e visibilidade dos subprocessadores** — snapshot da lista, com data.
4. **Dever de comunicar incidente ao controlador** — presente em ambos os DPAs; o que falta é o
   nosso lado: quem, no Breeze, recebe esse aviso e o que faz com ele (§5.4).
5. **Segurança** (art. 46) — cifra em repouso, MFA, backup em conta separada.

**Precedente que fica registrado:** com OCR local (ADR-0024) o projeto evitou um operador. Com a
hospedagem, não evita — mas continua valendo a regra: **cada novo destino de dado é um operador
novo, e passa por este agente antes de existir.** Vale para provedor de e-mail transacional
(`runbook-deploy.md` §5), para qualquer API de LLM, para qualquer ferramenta de analytics.

### 4.3 Registro de operações — conteúdo mínimo (art. 37)

Arquivo a criar: `docs/juridico/registro-operacoes.md`. **Fora do meu escopo de arquivo** — deixo
a especificação para quem o orquestrador designar:

1. **Controlador** — identificação, conforme resolvido no §6.
2. **Operadores** — Supabase Inc. e Vercel Inc.: serviço prestado, região direcionada, DPA aceito
   (URL, versão, data), lista de subprocessadores (snapshot datado).
3. **Categorias de dado** — copiar o inventário da skill `lgpd-condominio` §1, acrescentando o
   texto de documento e os chunks (PII fora de campo estruturado — "Armadilha nº1").
4. **Finalidades e base legal** — a tabela do §4.1.
5. **Titulares** — condôminos, inquilinos, terceiros citados em documento (síndico terceirizado,
   representantes de fornecedor, brigadistas, funcionários da administradora).
6. **Transferência internacional** — mecanismo, o que `sa-east-1` cobre, e a **lacuna de
   cláusulas-padrão da ANPD registrada como risco residual assumido**, com dono e data de
   reavaliação (§2.3).
7. **Retenção** — a tabela do topo deste parecer.
8. **Medidas de segurança** — RLS negando por padrão, buckets privados + signed URL de TTL curto,
   CPF em HMAC + AES-256-GCM com chaves fora do banco, trilha encadeada, backup cifrado em conta
   separada, MFA obrigatório para `editor`/`conselho`.
9. **Data e responsável por cada revisão.**

---

## 5. O que o produto precisa ter antes de existir dado real em produção

Separado por natureza, como pedido. **Tela**, **documento** e **configuração**.

### 5.1 Tela

| O quê | Onde | Quando | Conteúdo mínimo |
|---|---|---|---|
| **Aviso de privacidade** | `/privacidade`, público, sem login | **Portão B** | Controlador e como contatá-lo; finalidades e base legal de cada uma; categorias de dado; que **Supabase e Vercel são operadores**, nominalmente, com região; transferência internacional e o que se faz a respeito; retenção por categoria; direitos do art. 18 e como exercer; data da versão |
| **Link no rodapé** | Layout global | Portão B | Alcançável de qualquer tela, inclusive deslogado |
| **Link na tela de login** | `/entrar` | Portão B | A tela de login já trata CPF antes de qualquer sessão. O aviso tem de estar **antes** do primeiro tratamento, não depois |
| **Canal do titular** | `/privacidade` + rodapé | Portão B | Endereço que **não exige conta** — ex-morador e terceiro citado em ata também são titulares e não têm login (`off-boarding` §1) |
| **Aviso de retenção onde ela é visível ao usuário** | Tela de documento e de encerramento de vínculo | F1, **não bloqueante** | "Este documento é guardado por X" — a política existir num `.md` que ninguém lê não satisfaz o art. 9º |

**Nenhuma dessas telas existe hoje** — a busca por "privacidade/titular/encarregado/LGPD" em
`app/`, `components/` e `lib/` retorna uma única ocorrência, num comentário de
`app/entrar/acoes.ts`. É a maior lacuna de produto deste parecer, e é trabalho de horas, não de
semanas.

### 5.2 Documento

| O quê | Caminho | Quando |
|---|---|---|
| **Registro de operações** (art. 37) | `docs/juridico/registro-operacoes.md` | **Portão A** |
| **Checklist de publicação** | `docs/juridico/checklist-publicacao.md` | Criado com este parecer |
| **DPAs arquivados + subprocessadores** | `docs/juridico/operadores/` | **Portão A** |
| **Procedimento de resposta ao titular** | `docs/runbook.md`, seção nova | **Portão B** — quem responde, em quanto tempo (art. 19: imediata em forma simplificada; até 15 dias para declaração completa), como se registra |
| **Procedimento de incidente** (art. 48) | `docs/runbook.md`, seção nova | **Portão B** — como se detecta, quem decide comunicar ANPD e titulares, prazo. A Resolução CD/ANPD nº 15/2024 fixou prazo curto em dias úteis para a comunicação à ANPD *(prazo exato `[NÃO CONFIRMADO nesta sessão]` — confirmar no texto da resolução antes de escrever o número no runbook)* |
| **Registro do controlador** | onde couber (§6) | **Portão B** |

### 5.3 Configuração

| O quê | Portão |
|---|---|
| Supabase `sa-east-1` | A (A1) |
| Direção de região registrada por escrito | A (A2) |
| Env vars só em Production; Preview/Development sem credencial de produção | A (A5) |
| Deployment Protection ligada | A (A6) |
| MFA nas contas Supabase, Vercel e GitHub | A (A7) |
| `CPF_HASH_PEPPER` novo, nunca o de `.env.local` (já tratado como exposto — `runbook-deploy.md` §2) | A |
| Cópia das chaves fora da conta do provedor | B (B5) |
| Backup em conta separada, uma execução real bem-sucedida | B (B4) |
| Signup público desabilitado no Auth (só a `editor` cadastra) | A — já previsto no `runbook-deploy.md` passo 2.5 |
| Nenhuma resposta com PII cacheável na borda da Vercel | A — invariante a manter, ADR-0004 regra 2 |

### 5.4 Aberto, com dono, sem bloquear

- **Retenção de log do provedor.** Supabase e Vercel guardam logs de requisição por período
  próprio, que pode conter caminhos com identificadores. Ninguém definiu o que fazer. Dono:
  `devops`. Baixo risco (o desenho do ADR-0004 já proíbe nome informativo em objeto de Storage).
- **Reverificação da RLS no ambiente hospedado** (dívida D2). A suíte de 176 asserts rodou só
  contra o stack local. **Não bloqueia o Portão A** — no Portão A, só a editora tem conta, e o
  papel dela é o mais permissivo do sistema; não há a quem vazar. **Bloqueia o Portão B**, junto
  de B4: no minuto em que existir uma segunda conta, a RLS passa a ser a única coisa entre um
  morador e o dado de outro.
- **Quem recebe o aviso de incidente do operador** e o que faz com ele. Dono: `devops` + dona.

---

## 6. A conta que hospeda — quem é o controlador

**Vale registrar, sim, e é a pendência de maior consequência deste parecer** — maior que a região,
maior que a lacuna de cláusulas-padrão.

### 6.1 Quem é o controlador

**O condomínio.** O art. 5º, VI define controlador por um critério de fato — *a quem competem as
decisões referentes ao tratamento* — não pela titularidade da conta nem por quem paga a fatura. As
decisões que definem este tratamento (quais documentos existem, quem é morador, o que se publica,
por quanto tempo se guarda) são da coletividade, exercidas por assembleia e sindicatura. O
condomínio edilício é ente despersonalizado, mas tem CNPJ, contrata, é parte em juízo e responde
por seus atos; nada disso o impede de ser controlador.

**Não incide a exclusão do art. 4º, I** ("pessoa natural, para fins exclusivamente particulares e
não econômicos"). A finalidade aqui é a administração de uma coletividade e o dado é de terceiros.
Que a dona não cobre nada por isso é irrelevante — "não econômico" não basta; a exclusão exige
também "exclusivamente particular", e não é.

### 6.2 O problema real: a decisão do condomínio ainda não existe por escrito

Enquanto não houver registro de que o condomínio adotou o Breeze, a leitura de fato inverte-se — e
a inversão é desfavorável à dona:

| Cenário | Quem é o controlador | Consequência |
|---|---|---|
| **Condomínio adotou o Breeze**, registrado em ata, deliberação ou autorização escrita da sindicatura | **Condomínio** | A dona atua **por ele**. A obrigação legal do art. 7º, II (dever de prestar contas) é do condomínio e ampara o tratamento inteiro. Responsabilidade do art. 42 é do condomínio |
| **Não há registro** (situação de hoje) | **A dona, pessoalmente** | Ela trata dado de terceiros por iniciativa e meios próprios. Não pode invocar como sua a obrigação legal do síndico. Sobra o legítimo interesse **dela**, como condômina e conselheira — que **cobre o acesso dela aos documentos que já detém** e **não cobre** cadastrar vizinhos, coletar CPF e operar um serviço para a coletividade. Responsabilidade do art. 42 recai sobre ela, pessoa natural |

**É exatamente esta linha que separa o Portão A do Portão B**, e é por isso que a fronteira do
veto está onde está. O Portão A cabe confortavelmente no legítimo interesse próprio dela. O Portão
B não cabe em nada, enquanto o condomínio não disser que quer.

### 6.3 O que fazer — caminho mais curto

Não exijo assembleia. Exijo **rastro escrito**, na forma mais barata que o condomínio conseguir:

1. **Melhor:** item em pauta de assembleia, deliberado e registrado em ata. É o que resolve de vez
   e vira também a autorização para publicar o acervo (§7).
2. **Suficiente para o Portão B:** autorização escrita da sindicatura — e-mail serve — dizendo que
   o condomínio adota o Breeze como ferramenta de acesso ao acervo e que a dona opera em nome
   dele, com o encargo de responder a titulares.
3. **Mínimo aceitável, e só como ponte com prazo:** declaração unilateral escrita da dona,
   registrada em `docs/juridico/`, afirmando que **o dado é do condomínio e não dela**, que a
   conta é custódia temporária, e com data-limite para obter (1) ou (2). Ponte, não solução — se
   vencer sem substituição, o Portão B se fecha de novo.

### 6.4 Implicações de a conta ser pessoal, mesmo com o controlador definido

Persistem, e cada uma tem mitigação barata:

| Implicação | Mitigação | Portão |
|---|---|---|
| **Bus factor = 1.** Morte, incapacidade ou perda de acesso da dona = o condomínio perde o acervo e o histórico | Backup em conta separada (B4) + chaves em cofre externo (B5), com procedimento de recuperação documentado | B |
| **Descasamento contratual.** A contraparte de Supabase/Vercel é uma pessoa natural; o controlador é o condomínio. Se ela sair do conselho, o condomínio não tem título sobre a conta | Registrar em §6.3 que a titularidade é custódia; migrar para conta em nome do condomínio quando ele tiver meios | Depois, com prazo |
| **Exposição pessoal.** Sem registro do controlador, um pedido de titular ou uma reclamação à ANPD encontram a pessoa natural | §6.3 | B |
| **Transferência futura da conta** ao condomínio ou a outra síndica é operação de tratamento nova | Entrada própria no registro de operações quando ocorrer | Quando ocorrer |
| **Nomear a organização/projeto Supabase com o nome do condomínio, não com nome pessoal** | Um clique, no ato da criação — e é evidência de que a custódia é declarada | A |

---

## 7. O que este agente **não** decide

Repito para que não se confunda liberação de produção com liberação de publicação:

**A abertura do acervo além de convenção e regimento é decisão da dona do projeto, não minha.** É
a decisão pendente nº 1 do briefing e o SPEC §7 é explícito: se a escolha for publicar acervo
aberto, **é obrigatória etapa de redação/anonimização antes da publicação**. Este parecer não a
antecipa nem a prejulga. O que ele faz é dizer o que essa etapa teria de conter (§3.2, C1 e C2) e
garantir que ela seja uma decisão consciente, não o efeito colateral de uma configuração.

E, para constar: **não negocio veto**. Se algum agente vier propor "só desta vez" expor
inadimplência nominal a morador, CPF em claro fora da `editor`, ou publicar ata sem redação, a
resposta é a mesma e o pedido sobe ao orquestrador em vez de virar exceção.

---

## Checklist acionável

**Portão A — libera hoje**

- [x] `devops`/dona: Supabase em `sa-east-1` (A1) — **verificado 2026-09-11**: organização Breeze, projeto `breeze`, `sa-east-1`
- [x] dona: direção de região por escrito no registro de operações (A2) — `registro-operacoes.md` §2.1, 2026-09-11
- [ ] dona: aceitar e arquivar DPAs + snapshot de subprocessadores (A3)
- [x] orquestrador: designar quem escreve `docs/juridico/registro-operacoes.md` — spec no §4.3 (A4) — **escrito em 2026-09-11, quatro dias depois de o acervo subir**
- [ ] `devops`: env vars só em Production; Preview/Development sem credencial de produção (A5)
- [x] `devops`: Deployment Protection antes do primeiro deploy (A6) — **ligada em todas as implantações em 2026-09-11; o domínio de produção ficou aberto de 2026-09-07 até então** (D19)
- [ ] dona: MFA em Supabase, Vercel e GitHub (A7)
- [ ] dona: nomear a organização Supabase com o nome do condomínio (§6.4)
- [x] `juridico-lgpd`: verificar que o acervo não está rastreado pelo git — **confirmado**
- [x] `juridico-lgpd`: levantar o sinalizador de biometria do "COMUNICADO FACIAL" — **não é
      biométrico** (§3.3)
- [ ] `devops`: alterar `runbook-deploy.md` §0 — a trava do backup passa a valer para o Portão B,
      não para a ingestão dos 43 (§1.4)

**Portão B — vetado até**

- [ ] dona: registrar quem é o controlador (§6.3) (B1)
- [ ] UI: `/privacidade` público + links no rodapé e em `/entrar` (B2)
- [ ] dona: canal do titular alcançável sem conta (B3)
- [ ] `devops`: backup em conta separada, uma execução real bem-sucedida (B4)
- [ ] dona: chaves em cofre fora da conta do provedor (B5)
- [ ] backend: `cpf_enc` implementado (dívida C1-2) (B6)
- [ ] `auditor-rls`: reverificar a suíte contra o projeto hospedado (dívida D2)
- [ ] `devops`: procedimento de titular e de incidente no runbook — confirmar o prazo da
      Resolução CD/ANPD nº 15/2024 antes de escrever o número

**Portão C — vetado até**

- [x] ingestão: etapa de redação de CPF/RG antes do chunk (C1) — `lib/ingestao/redacao.ts`; **verificado em produção**: 0 CPF formatado em páginas e chunks
- [ ] `editor`: inspecionar a qualificação das partes na Convenção antes de `publicos` (C2)
- [ ] `editor`: rodar `checklist-publicacao.md` documento a documento (C3–C5)

**Sem prazo, escalado**

- [ ] dona: ciência de que o condomínio trata biometria por fora do Breeze (§3.5)
- [ ] dona: decisão pendente nº 1 — abrir ou não o acervo além de convenção e regimento (§7)

---

## Pendências de verificação deste parecer

| Afirmação | Situação |
|---|---|
| Fim do período de adequação às cláusulas-padrão da ANPD em 23/08/2025 | **Verificado** em fontes secundárias qualificadas (escritórios de advocacia) mais o comunicado da própria ANPD. Não abri o texto da Resolução CD/ANPD nº 19/2024 no Diário Oficial |
| DPA da Supabase não menciona LGPD/Brasil/ANPD; cl. 6.1 permite tratamento "anywhere" salvo direção de região | **Verificado** no texto publicado em `supabase.com/legal/customer-resources/data-processing-addendum` |
| DPA da Vercel enumera GDPR, UK, CCPA, PIPEDA e Austrália; Brasil ausente do rol e do Schedule 4 | **Verificado** no texto publicado em `vercel.com/legal/dpa` |
| Prazo de comunicação de incidente da Resolução CD/ANPD nº 15/2024 | **`[NÃO CONFIRMADO]`** — não citar número sem abrir o texto |
| Condomínio edilício como controlador na prática regulatória da ANPD | Raciocínio a partir do art. 5º, VI. **Não localizei guia específico da ANPD sobre condomínios nesta sessão** — a conclusão se sustenta pelo texto legal, mas não afirmo que há orientação oficial |
| CC art. 1.348, VIII e art. 1.335, III | **Verificados em fonte primária** (Planalto), em sessão anterior |
| Lei 4.591/64, art. 22, §1º, "g" | **Verificado**, sessão anterior |
