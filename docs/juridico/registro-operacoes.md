# Registro das operações de tratamento de dados pessoais (LGPD art. 37)

Condição **A4** do Portão A (`pareceres/2026-09-07-producao-dado-real-supabase-vercel.md` §4.3).
Documento vivo: toda operação nova (destino novo, categoria nova, mudança de retenção, troca de
conta) entra aqui **antes** de existir — e a revisão entra na tabela do §9, não num commit sem
rastro.

**Este registro chegou atrasado, e isso está dito aqui em vez de escondido.** O parecer o dava como
pré-condição da subida do acervo. O acervo subiu em **2026-09-07, 22:40 UTC**; este documento é de
**2026-09-11**. Nesse intervalo, dado pessoal real existiu em produção sem registro de operações e
sem proteção no domínio de produção (§8). Nada foi publicado e nenhuma segunda pessoa foi
cadastrada — medido, §3 —, então o atraso não produziu exposição conhecida. Produziu quatro dias
de tratamento sem o documento que o art. 37 exige.

**Sobre o repositório ser público.** Esta versão não contém nome de pessoa natural. A identificação
nominal do controlador de fato e de quem responde a titulares vive **fora** do repositório (§1) — o
art. 37 exige que o registro exista e esteja disponível à ANPD, não que seja publicado.

---

## 1. Controlador

| | |
|---|---|
| **Controlador pretendido** | O **condomínio** (pessoa jurídica, CNPJ próprio) — quem decide, por assembleia e sindicatura, que documentos existem, quem é morador, o que se publica e por quanto tempo (art. 5º, VI; parecer §6.1) |
| **Controlador de fato, hoje** | **A dona do projeto, pessoalmente** — conselheira e condômina. Não há registro escrito de que o condomínio adotou o Breeze (parecer §6.2). Enquanto não houver, ela trata o dado por iniciativa e meios próprios, amparada no legítimo interesse **dela**, que cobre o acesso aos documentos que já detém e **não cobre** cadastrar vizinhos |
| **O que transforma um no outro** | Deliberação em ata (melhor) ou autorização escrita da sindicatura — e-mail serve (suficiente). É o item **B1** e bloqueia o Portão B |
| **Identificação nominal e contato** | Fora deste repositório público. `[A PREENCHER — dona: onde fica a versão com identificação]` |

## 2. Operadores

Cada operador trata **em nome do controlador e sob instrução dele** (art. 5º, VII; art. 39). A
hospedagem não tem base legal própria — é meio do mesmo tratamento (parecer §4.1).

| Operador | Serviço | Onde | Estado medido | DPA |
|---|---|---|---|---|
| **Supabase Inc.** | Postgres, Auth, Storage | Organização **Breeze**, projeto `breeze`, **`sa-east-1` (São Paulo)**, criado em 2026-09-07 21:06 UTC, dentro da conta Supabase usada pelo estúdio da dona | As 37 migrações do repositório aplicadas — inclusive a `_test_only` (§8); acervo carregado (§3) | `supabase.com/legal/customer-resources/data-processing-addendum` — **aceite, versão e data `[A CONFIRMAR — A3]`** |
| **Vercel Inc.** | Hospedagem da aplicação, funções, CDN | Projeto `breeze` no time pessoal da dona (plano Hobby); funções respondendo de `gru1` (São Paulo), observado no cabeçalho `x-vercel-id` — **não é configuração verificada, é observação** | Aplicação no ar; **Vercel Authentication em todas as implantações desde 2026-09-11** (§8) | `vercel.com/legal/dpa` — **aceite, versão e data `[A CONFIRMAR — A3]`** |

O identificador do projeto Supabase (`project-ref`) não é reproduzido aqui: não é segredo — vai
embutido em qualquer cliente —, mas é endereço, e este repositório é público. Está no painel.

**Subprocessadores:** snapshot datado das listas públicas de cada um — **`[PENDENTE — A3]`**.
Arquivar em `docs/juridico/operadores/` com a data da captura.

**Operadores que não existem, e por decisão:** OCR roda local (ADR-0024) — nenhum fornecedor de
OCR recebe página do acervo. LLM está desligado (ADR-0027) — nenhuma API de modelo recebe texto.
E-mail transacional ainda não foi escolhido (`runbook-deploy.md` §5). **Cada um desses, no dia em
que existir, é um operador novo e entra neste registro antes do primeiro byte.**

### 2.1 Instrução de região — direção expressa do controlador (condição A2)

> O controlador instrui que todo o armazenamento e processamento de dado pessoal do Breeze pela
> Supabase ocorra na região **`sa-east-1` (São Paulo, Brasil)**. Qualquer tratamento fora dessa
> região que não seja o acesso administrativo e de suporte inerente ao serviço não está
> autorizado.

Registrada aqui porque o DPA da Supabase (cl. 6.1) autoriza tratamento "anywhere that Supabase or
its Sub-processors maintain facilities" **salvo direção de região do cliente** — sem a direção
escrita, a escolha no painel não é oponível (parecer, condição A2).

## 3. Categorias de dado pessoal

Inventário da skill `lgpd-condominio` §1, acrescido do que o parecer mandou acrescentar (texto de
documento e chunks), e com o que **existe hoje em produção**, medido em 2026-09-11 por contagem —
sem abrir conteúdo.

| Categoria | Onde vive | Existe em produção hoje? |
|---|---|---|
| Nome | `pessoas.nome`, atas, deliberações, `audit.log` | Sim: 1 pessoa real (a editora) + 1 registro sintético de seed (e-mail `.local`, sem conta, papel encerrado). E nomes dentro do texto de atas e comunicados |
| E-mail | `pessoas.email`, `auth.users` | Sim: 1 conta |
| CPF | `pessoas.cpf_hash` (HMAC), `cpf_enc` (reversível) | **Não** em `pessoas` (nenhum `cpf_hash` gravado). **No texto do acervo: redigido** — 0 CPF formatado em páginas e chunks; 3 documentos com marca de redação |
| Telefone | `pessoas.telefone` | Não |
| Unidade | `vinculos` | Não (nenhum vínculo) |
| Situação de pagamento | `cobrancas` | Não (F2) |
| **Texto de documento do acervo** | `documentos`, `documento_paginas`, `chunks`, bucket `documentos` | **Sim: 43 documentos, 313 páginas, 201 chunks, 43 arquivos no Storage.** PII fora de campo estruturado — nome em ata, qualificação de síndico, lista de brigada, contato de vendedor (parecer §3.2). **0 publicados; 0 arquivos no bucket `publicos`** |
| Anexos financeiros e cotações | `lancamento_anexos`, `documentos` | Cotações sim (dentro dos 43, visibilidade `conselho`); anexos financeiros não (F2) |
| Trilha de auditoria | `audit.log`, `audit.acesso` | Sim, por construção |

**Dado sensível (art. 11): nenhum**, verificado — não presumido — no parecer §3.3.

## 4. Finalidades e base legal

Transcrito do parecer §4.1. **Nunca consentimento** (skill §2; mudança exige ADR).

| Finalidade | Base legal | Fundamento |
|---|---|---|
| Guardar e organizar o acervo documental | **Obrigação legal** (art. 7º, II) | CC art. 1.348, VIII; Lei 4.591/64, art. 22, §1º, "g" |
| Dar acesso a condôminos para fiscalizar a gestão | **Legítimo interesse** (art. 7º, IX + art. 10) | CC art. 1.335, III |
| Identificar quem é morador (CPF como alias, e-mail para magic link) | **Legítimo interesse** (art. 7º, IX) | D2, ADR-0003 |
| Trilha de auditoria | **Legítimo interesse** (art. 7º, IX) | SPEC §7 |

**Ressalva que decorre do §1:** a obrigação legal do art. 7º, II é **do condomínio**. Enquanto o
controlador de fato for a dona, ela não pode invocá-la como sua — e o que a ampara é só o próprio
legítimo interesse, suficiente para o Portão A e insuficiente para o B.

## 5. Titulares

- **Condôminos** proprietários e **inquilinos** — hoje só a editora tem cadastro.
- **Terceiros citados em documento, sem conta e sem relação com o Breeze:** síndico terceirizado
  e ex-síndico; representantes e vendedores de fornecedor (cotações); funcionários da
  administradora (carta de apresentação); brigadistas e instrutor (atestado de brigada);
  responsáveis técnicos (Habite-se, reformas).

Os terceiros são a razão de o canal do titular precisar funcionar **sem conta** (item B3;
`off-boarding-ex-morador.md` §1).

## 6. Transferência internacional

- **Corpo do dado em São Paulo:** Postgres e Storage em `sa-east-1` (§2).
- **Transferência residual que permanece** (parecer §2.2): plano de controle, suporte e telemetria
  de duas empresas norte-americanas; CDN global da Vercel (inofensiva **enquanto** nada com PII for
  cacheável — ADR-0004 regra 2); subprocessadores.
- **Mecanismo (art. 33):** nenhum dos dois DPAs incorpora as cláusulas-padrão da ANPD (Resolução
  CD/ANPD nº 19/2024, adequação encerrada em 23/08/2025); ambos trazem as SCC europeias.
- **Risco residual assumido.** A lacuna não é fechável por um condomínio de ~50 unidades. Dona do
  risco: **a dona do projeto**. **Reavaliar em 2027-09** ou quando qualquer dos dois publicar
  termos brasileiros. Rastreado como **J1** em `docs/ops/divida-tecnica.md`.

## 7. Retenção

Transcrito do topo do parecer.

| Objeto | Retenção | Fundamento |
|---|---|---|
| Atas, convenção, regimento, laudos (PDF + texto + chunks) | **Permanente** | Decisão de produto; Lei 4.591/64 art. 22 §1º "g" |
| Balancetes, cotações, comunicados financeiros | **5 anos** | Idem |
| `pessoas` | Enquanto houver vínculo ou papel vigente; PII cadastral anonimizada em `vinculos.fim + 5 anos` | `off-boarding-ex-morador.md` §4 |
| `audit.acesso` | **6 meses** | SPEC §7 |
| `audit.log` | **Permanente, não expurgável** | ADR-0013 |
| Dumps de backup cifrados | 12 semanais + 12 mensais | `backup.md` §4 — **backup ainda não existe** (B4) |
| Logs do provedor | **Não definido** | J4, dono `devops` |

**Descarte não tem rotina ainda.** A retenção de 5 anos e a de 6 meses são regra escrita, não
mecanismo rodando. Nada está perto de vencer — o documento mais antigo é de dez/2025 —, mas a
rotina precisa existir antes de o primeiro prazo chegar, não depois.

## 8. Medidas de segurança

Separado entre **o que foi verificado** e **o que o desenho promete**, porque a diferença entre
as duas colunas é justamente o que este registro existe para não esconder.

| Medida | Estado em 2026-09-11 |
|---|---|
| RLS negando por padrão, fronteira única de autorização (ADR-0012) | **Verificado:** 320/320 asserts pgTAP no CI (run `34619369719`) — contra o stack local. **Não** exercitada contra o projeto hospedado (D2) |
| Buckets privados, signed URL de TTL curto (ADR-0004) | **Verificado no schema:** `documentos` e `anexos-financeiros` privados; `publicos` é público **e está vazio** |
| CPF em HMAC + AES-256-GCM, chaves fora do banco (ADR-0014) | Desenho implementado; nenhum CPF gravado em produção ainda. `cpf_enc` pendente (B6) |
| Redação de CPF/RG no texto extraído antes do chunk | **Verificado em produção:** 0 CPF formatado em `documento_paginas` e `chunks` |
| Trilha encadeada em `audit.log` (ADR-0013) | Desenho implementado e testado no CI |
| MFA (`aal2`) obrigatório para `editor`/`conselho` | **Verificado** contra o GoTrue local (D1); não contra o hospedado |
| MFA nas contas administrativas da dona (Supabase, Vercel, GitHub) | **`[A CONFIRMAR — A7]`** |
| Proteção do domínio de produção | **Vercel Authentication em todas as implantações, ligada em 2026-09-11** — antes disso, só as URLs de implantação eram protegidas e o domínio de produção respondia a qualquer um (D19) |
| Backup cifrado em conta separada | **Não existe** (B4) |
| Extensão de teste fora de produção | **Violada:** `pgtap` 1.3.3 instalada no projeto hospedado — a migração `_test_only` subiu por push manual, sem o filtro do CI. Remoção pendente, dono `eng-supabase` (D19) |

## 9. Revisões

| Data | Quem | O que mudou |
|---|---|---|
| 2026-09-11 | orquestrador, a partir do parecer de 2026-09-07 | Criação. Estado de produção medido por contagem, sem leitura de conteúdo. Registrado o atraso em relação à subida do acervo |
