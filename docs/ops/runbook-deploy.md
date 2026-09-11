# Runbook de deploy — primeira subida a produção (Supabase hospedado + Vercel)

Fonte: `docs/01-SPEC.md` §1.2, `docs/ops/backup.md`, `docs/ops/runbook-restauracao.md`,
`docs/adr/0009-politica-de-ambientes.md`, `docs/ops/divida-tecnica.md` (D1, D2, D3).

Este documento é a sequência operacional da **primeira** subida — não um runbook genérico de
release. Depois que produção existir, releases seguintes são só `git push` para `main` (CI faz
`supabase db push`; Vercel faz o deploy do app) — ver `README.md`, seção CI/CD.

Dono: `devops`. Nenhum passo aqui provisiona nada sozinho — cada ação que gasta dinheiro ou cria
uma conta é explicitamente marcada como "ação da dona do projeto".

---

## 0. Pré-condição que trava tudo

**Não subir os 43 documentos reais (dado pessoal — nome, unidade, CPF, financeiro) antes de:**

1. O backup em conta separada existir e ter passado por pelo menos uma execução real
   (`workflow_dispatch` de `.github/workflows/backup.yml`, validada manualmente).
2. `juridico-lgpd` liberar a ingestão do dado real (avaliação em paralelo, fora do escopo deste
   agente).

Sem (1), o Breeze pode ir ao ar (app funcionando, autenticação funcionando) mas **sem dado real
carregado** — subir o produto vazio ou com seed sintético não é bloqueado por isto; subir os 43
documentos é.

---

## 1. Ordem de execução

### Passo 1 — Conta de backup (ação da dona do projeto + `devops` prepara o resto)

Ver `docs/ops/backup.md` §3, passo a passo completo. Resumo da divisão de trabalho:

- **Só a dona do projeto:** criar a conta no provedor de backup (Backblaze B2 recomendado —
  free tier, API S3-compatível; decisão final de provedor é conjunta com `arquiteto`), gerar as
  credenciais de acesso.
- **`devops` prepara sem credencial (já feito):** `scripts/backup.sh`,
  `.github/workflows/backup.yml`, este runbook, `docs/ops/runbook-restauracao.md`. Nada aqui
  precisa ser reescrito quando a credencial existir — só os secrets do GitHub precisam ser
  preenchidos (passo abaixo).
- Depois que a conta existir: rodar `rclone config` localmente (uma vez), gerar
  `BACKUP_RCLONE_CONFIG` (base64) e os demais secrets listados em `docs/ops/backup.md` §3, e
  disparar `backup.yml` manualmente para validar antes do cron semanal.

### Passo 2 — Projeto Supabase hospedado (ação da dona do projeto)

1. Dona cria a organização nova no Supabase.
2. Dona (ou `devops`, dentro da organização já criada pela dona) cria o projeto — plano Pro, região
   `sa-east-1` (São Paulo) se disponível, para latência com usuários no Brasil.
3. Anotar: `Project URL`, `anon key`, `service_role key`, connection string do Postgres,
   `project-ref`.
4. Aplicar as 37 migrações no projeto novo: `supabase link --project-ref <ref>` seguido de
   `supabase db push` (o mesmo mecanismo do job `db-push` do CI, rodado uma vez manualmente para
   o projeto nascer com o schema — depois disso, releases seguem pelo CI). **Confirmar que
   `20260904122300_pgtap_test_only.sql` não vai — o filtro do job `db-push` já cuida disso quando
   o push for feito pelo CI; se for feito manualmente neste passo 0, filtrar à mão.**

   > **Executado em 2026-09-07 — e o filtro à mão não aconteceu.** O push manual levou
   > `pgtap` a produção. Corrigido em 2026-09-11: `drop extension pgtap` (sem `CASCADE`) +
   > `supabase migration repair --status reverted 20260904122300 --linked`, provado por
   > `db push --dry-run` com o diretório filtrado ("Remote database is up to date").
   >
   > **Regra que vale daqui em diante: nunca `supabase db push` contra o remoto a partir da raiz
   > do repositório.** A CLI enxerga `20260904122300_pgtap_test_only.sql` como pendente e
   > **reinstala `pgtap` em produção** — sem erro, sem aviso. O único caminho de migração para
   > produção é o job `db-push` do CI. "Filtrar à mão" é instrução que depende de alguém lembrar,
   > e já falhou uma vez.
5. Configurar Auth: habilitar TOTP (`[auth.mfa.totp]` — equivalente hospedado da flag que D1
   precisou ligar no `config.toml` local), habilitar magic link, desabilitar signup público (só
   `editor` cadastra pessoa — ver SPEC §2.1).

### Passo 3 — Variáveis de ambiente na Vercel

Ver seção 2 abaixo para a lista completa com origem de cada uma.

### Passo 4 — Vincular o projeto Vercel e primeiro deploy

1. `vercel link` (projeto ainda não vinculado — dona já autenticada como `gracyars-6864`).
2. Confirmar `vercel.json` (`framework: nextjs`, `buildCommand: pnpm build`) — nenhuma mudança
   necessária para o deploy em si.
3. **Ativar Deployment Protection (senha ou Vercel Authentication/SSO) antes do primeiro
   deploy** — ver seção 4 abaixo para o porquê e a ressalva sobre o magic link.
4. Deploy. Confirmar build verde.

### Passo 5 — Reverificação pós-deploy (D1/D2)

Ver seção 3 abaixo — lista do que rodar contra o projeto hospedado antes de confiar nele.

### Passo 6 — E-mail transacional (pode vir depois do passo 4, mas antes de qualquer usuário real
entrar)

Ver seção 5. Bloqueante para uso real por moradores; não bloqueante para o deploy técnico em si.

### Passo 7 — Ingestão dos 43 documentos reais

Só depois de: passo 1 validado (backup real rodou e teve sucesso) **e** liberação do
`juridico-lgpd`. Ver seção 0.

---

## 2. Variáveis de ambiente — Vercel (produção)

| Variável | Origem | Vazio quebra o quê |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Projeto Supabase hospedado (passo 2) | **Quebra tudo.** É `NEXT_PUBLIC_*` — inlinada no bundle no momento do `build`. Vazia, o cliente do navegador (`lib/supabase/navegador.ts`) e o de servidor (`lib/supabase/servidor.ts`) apontam para `undefined`. **Precisa existir antes do build, não só antes do runtime** — consequência direta: o projeto Supabase tem que nascer antes do primeiro `vercel deploy`. |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Projeto Supabase hospedado | Mesma classe do item acima — quebra login e toda leitura autenticada. |
| `SUPABASE_SERVICE_ROLE_KEY` | Projeto Supabase hospedado (Project Settings → API) | Quebra lookup de login (`clienteDeServico()` lança erro explícito se ausente — `lib/supabase/servico.ts`) e qualquer estágio de worker que rode no mesmo processo. **Nunca** exposta ao client — só server-side na Vercel. |
| `SUPABASE_DB_URL` | Projeto Supabase hospedado (connection string direta) | Quebra `pg_dump` (`scripts/backup.sh`) — não é lida pelo app Next.js em si, é usada pelo workflow de backup (GitHub Actions secret, não Vercel env, mas listada aqui por completude). |
| `CPF_HASH_PEPPER` | **Gerar novo — `openssl rand -hex 32`.** Nunca reaproveitar o de `.env.local` de desenvolvimento (esse arquivo já passou por esta sessão do Claude Code; tratar como potencialmente exposto e, à parte deste deploy, **rotacionar também o valor de dev** por higiene). | Quebra hash de login por CPF (`hashDeCpf()` lança erro explícito se ausente — `lib/identidade/cpf.ts`). Sem ele, ninguém entra por CPF (e-mail direto ainda funcionaria, mas o produto perde o alias, ADR-0003). **Gerar, guardar em gerenciador de senha da dona do projeto fora do repositório, colar só no painel Vercel.** |
| `LLM_API_KEY`, `LLM_PROVIDER`, `LLM_MODEL_CLASSIFICACAO`, `LLM_MODEL_SINTESE` | Decisão D18 — deixar vazio de propósito em F1. | **Não quebra o build nem o app.** `lib/busca/buscar.ts` lê `Boolean(process.env.LLM_API_KEY)` para decidir se a metade semântica da busca está ligada — vazio = desligada, e a UI já avisa disso (D18, trava explícita). Busca léxica (`tsvector`) funciona sem isso. |
| `OCR_API_KEY`, `OCR_PROVIDER` | Decisão D17 — OCR passou a ser local (Vision do macOS), não API paga. | **Não quebra nada em produção.** O OCR roda no backfill, offline, antes da ingestão — não é uma dependência de runtime do app hospedado na Vercel. |
| `LLM_MONTHLY_BUDGET_CENTS` | Já tem default em `.env.example` (`6000`) | Não quebra — é config de teto, não de conexão. Manter o default ou ajustar por decisão da dona do projeto. |
| `LLM_BUDGET_ALERT_THRESHOLD_PCT` | Default `80` | Idem. |
| `LLM_BUDGET_ALERT_WEBHOOK_URL` | **Pendente — ação da dona do projeto**, escolher canal (Slack/e-mail/etc.) | Não quebra o app. Sem ele, o teto existe mas o alerta não tem para onde disparar — risco operacional (estourar o teto sem ninguém saber), não risco de build. Ver seção 6. |
| `BACKUP_STORAGE_*`, `BACKUP_ENCRYPTION_KEY`, `BACKUP_RCLONE_*` | Provedor de backup (passo 1) | Não são lidas pelo app Next.js — vivem como **GitHub Actions Secrets**, não como env var da Vercel. Listadas em `.env.example` para documentar o contrato, não para configurar na Vercel. |
| `VERCEL_URL`, `VERCEL_ENV` | Injetadas automaticamente pela própria Vercel | Não configurar manualmente. |

**Resumo do bloqueio de build:** `NEXT_PUBLIC_SUPABASE_URL` e `NEXT_PUBLIC_SUPABASE_ANON_KEY` são
as únicas que travam o build/runtime se vazias — e ambas exigem o projeto Supabase hospedado já
existir. `CPF_HASH_PEPPER` e `SUPABASE_SERVICE_ROLE_KEY` não travam o build (lidas em runtime,
dentro de função), mas travam login/dados na primeira requisição real. Todas as outras têm
comportamento gracioso de "desligado" documentado no código (D17/D18).

---

## 3. Reverificação pós-deploy — o que muda de local para hospedado

| Item | O que rodar | Contra o quê | Resultado bloqueante? |
|---|---|---|---|
| **D1** (GoTrue só emite `aal2` após verificação real) | `pnpm probe:aal2` (`scripts/probe/aal2-gotrue.ts` — já é agnóstico de URL, aceita qualquer projeto Supabase) | Projeto hospedado, com `SUPABASE_URL`/chaves apontando para produção (ou um usuário de teste dedicado, nunca a `editor` real) | **Sim.** 10/10 verificações precisam passar. Se o GoTrue hospedado emitir `aal2` antes da verificação de TOTP, toda a autorização de `editor`/`conselho` está mais fraca do que a suíte pgTAP local mede — não subir dado real até isto passar. |
| **D2** (comportamento geral em hospedado) | 1) Suíte pgTAP completa: `supabase test db --local` **não serve** — precisa rodar contra o remoto. Usar `supabase db push` no projeto (já feito no passo 2) e então exercitar manualmente os cenários críticos de RLS que a suíte cobre localmente (ao menos: bloqueio de `TRUNCATE` para `service_role` — já confirmado como propriedade do Postgres, vale nos dois ambientes; timing de `aal2`, coberto por D1 acima). 2) Login end-to-end real: CPF/e-mail → magic link → sessão → TOTP → `aal2`. | Projeto hospedado | **Login end-to-end: sim, bloqueante** — é o caminho de entrada de todo mundo. **Extensões geridas / `pg_net`:** médio, não bloqueia a subida do app, mas registrar o resultado em `docs/ops/divida-tecnica.md` (D2) com data, marcando fechado se passar. |
| **D3** (CI real no runner GitHub hospedado) | O próprio `ci-gate` do `.github/workflows/ci.yml`, na primeira execução real contra um remoto GitHub | Repositório com remoto (ainda não existe — ver "o que falta" no relatório) | **Sim, para confiar no gate como proteção de merge.** Não bloqueia o primeiro deploy manual, mas bloqueia "deploy futuro sem revisão manual" até confirmado. |
| **Deployment Protection x magic link** | Teste manual: pedir magic link de um usuário de teste, abrir o link recebido por e-mail, confirmar que ele chega em `app/auth/confirmar` sem cair na tela de senha/SSO da Vercel | Deploy protegido, ambiente real | **Sim.** Ver seção 4 — se a proteção bloquear o link, ninguém entra. |
| **SMTP / entregabilidade** | Enviar magic link de teste para uma caixa real (não `mailpit` local) e confirmar entrega, sem cair em spam | Domínio de e-mail configurado (seção 5) | **Sim, para uso real** — não bloqueia o deploy técnico, bloqueia qualquer usuário real conseguir entrar. |

O que **não** dá para reverificar sem o projeto hospedado existir (portanto não verificado até
agora, nesta rodada): tudo na tabela acima. `pnpm probe:aal2` está pronto e não precisa de
nenhuma mudança de código — é só apontar as env vars para o projeto novo.

---

## 4. Deployment Protection

**Recomendação: ativar proteção (senha ou Vercel Authentication) no primeiro deploy, sim.**

Motivo: hoje nada está publicado. Uma URL de produção da Vercel é alcançável por qualquer um que
a descubra (buscadores indexam, links vazam, `*.vercel.app` é adivinhável por padrão de nome) —
mesmo com autenticação própria do produto, ela expõe: a tela de login (que já é
cuidadosamente indistinguível, ADR-0003 — não é o risco principal), mas também qualquer rota que
dependa só de RLS e não de proteção de borda, e a superfície de ataque disponível para
tentativa de força bruta/enumeração antes mesmo do primeiro usuário real existir. Convenção e
regimento serem públicos por decisão de produto é diferente de "o app inteiro fica acessível
antes de estar pronto para receber tráfego real".

**O que isso quebra, e a mitigação:** a proteção da Vercel intercepta **toda** requisição não
autenticada por ela — inclusive `GET /auth/confirmar` (a rota que o magic link do e-mail abre,
`app/auth/confirmar/route.ts`). Um link de magic link do Supabase não carrega o token de bypass
da Vercel; a pessoa cairia na tela de senha da Vercel antes de chegar à troca do código por
sessão.

Mitigação: usar o mecanismo de **Protection Bypass for Automation** da Vercel (um token que pode
ser anexado a domínios/subrotas específicas, ou a opção de excluir uma rota da proteção) — ou,
mais simples para o primeiro momento: proteger com senha só até o dia de abrir para os
moradores de verdade, e desativar a proteção exatamente quando o e-mail (seção 5) e o D1/D2
(seção 3) estiverem confirmados. Não recomendo tentar reconciliar proteção de borda com magic
link via engenharia adicional agora — é complexidade nova num caminho de autenticação que já é
crítico; mais simples manter a proteção da Vercel desligada assim que o produto estiver pronto
para os primeiros usuários reais, e usar a autenticação do próprio produto (que já é o
mecanismo real) como a defesa em profundidade única a partir daí.

**Sequência recomendada:** proteger → validar D1/D2/e-mail com contas de teste (a proteção da
Vercel não impede quem tem a senha de testar, incluindo `devops`) → desproteger só quando pronto
para os primeiros moradores reais entrarem pelo magic link de verdade.

---

## 5. E-mail transacional

ADR-0003 já registra: SMTP padrão do Supabase hospedado tem limite baixo e reputação
compartilhada — **não serve para produção**, porque o magic link é o único caminho de entrada
(sem senha).

Precisa: domínio próprio (ou subdomínio, ex. `mail.breeze-condominio.com.br`) com SPF, DKIM e
DMARC configurados no provedor de e-mail transacional, e o Supabase apontado para esse SMTP
customizado (Auth → Settings → SMTP Settings).

Opções de provedor (custo aproximado, plano de entrada, volume irrelevante aqui — é um
condomínio, poucas dezenas de e-mails/mês):

- **Resend** — free tier cobre volume deste porte (até 3.000 e-mails/mês no free); domínio
  verificado é grátis. Provavelmente **R$0/mês** para este volume.
- **Amazon SES** — mais barato ainda por e-mail (~US$0,10/1000), mas exige configuração mais
  manual (verificação de domínio no Route53 ou DNS externo) e sandbox inicial.
- **Postmark** — melhor entregabilidade histórica para transacional, plano pago desde ~US$15/mês.

Recomendação: Resend, pelo custo (~R$0 no volume deste produto) e simplicidade de setup.

**Bloqueante para a primeira subida técnica?** Não — o app pode subir e ser testado com contas de
teste usando o SMTP padrão do Supabase (limite baixo, mas suficiente para os testes da seção 3).
**Bloqueante para abrir para moradores reais?** Sim — sem isso, magic links reais têm risco real
de não chegar ou cair em spam, e "login não funciona" para o único mecanismo de entrada do
produto é crítico.

Ação: dona do projeto registra o domínio (se ainda não tiver um) e cria a conta no provedor de
e-mail escolhido; `devops` configura SPF/DKIM/DMARC e aponta o SMTP no Supabase assim que a
credencial existir.

---

## 6. Custo mensal — configuração recomendada

| Item | Custo/mês (BRL, aprox.) | Observação |
|---|---|---|
| Vercel Pro | ~R$110 | Necessário para Deployment Protection com granularidade e para domínio custom sem limite do free tier. |
| Supabase Pro | ~R$140 | Necessário para PITR do provedor (que não substitui o backup próprio, mas é camada extra) e para não pausar por inatividade. |
| Backup (Backblaze B2) | ~R$0–5 | Volume de 43 documentos + dumps semanais fica dentro do free tier (10GB) por muito tempo; custo real só aparece com o acervo bem maior. |
| E-mail (Resend) | ~R$0 | Free tier cobre o volume esperado. |
| Domínio (se novo) | ~R$3–5/mês (~R$40–60/ano) | Só se a dona ainder não tiver um domínio `.com.br`. |
| Worker (processamento de ingestão) | ~R$15 (SPEC §1.2) ou **R$0** | D17 já zerou o custo de OCR pago; se o worker rodar na própria máquina da mantenedora (hoje é o caso — ver dívida A5), custo adicional de hospedagem do worker é zero por enquanto. |
| LLM | R$0 hoje (D18 — desligado) | Teto configurado (`LLM_MONTHLY_BUDGET_CENTS=6000`, R$60) para quando for ligado. |
| **Total estimado** | **~R$255–270/mês** | Abaixo do teto de referência do SPEC §1.2 (~R$300/mês) — com folga, porque D17 e D18 removeram dois dos itens mais caros da estimativa original (LLM 20–60 e worker 15 parcialmente). |

Custo único (fora do recorrente): zero por ora — D17 zerou o custo de OCR pago; embeddings
seguem desligados (D18). O único custo único remanescente é o tempo de configuração manual
(contas, DNS, secrets), não dinheiro.
