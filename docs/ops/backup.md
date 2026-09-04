# Backup, retenção e teto de custo de LLM

Fonte: `docs/01-SPEC.md` §1.2 (ambientes e custo) e §7 (backup e retenção). Este documento é
operacional — o "porquê" arquitetural está no SPEC; aqui está o "como", executável.

Dono deste documento: `devops`. Mudança de provedor de backup ou de LLM é decisão conjunta com
`arquiteto` e a dona do projeto (ver `.claude/agents/devops.md`, seção "Quando escalar").

---

## 1. Regra dura: backup do provedor não é backup

O snapshot automático do Supabase (point-in-time recovery / snapshot diário do provedor) **não
conta como backup do Breeze**. Ele protege contra falha de infraestrutura do próprio Supabase,
não contra: conta comprometida, erro humano que apaga o projeto, encerramento da conta,
disputa de cobrança, ou falha do provedor em si. Backup real exige uma cópia dos dados **fora**
do provedor de produção, em conta separada.

Por isso o Breeze mantém:

1. **`pg_dump` semanal** do Postgres completo (schema + dados, formato `-Fc`), incluindo o
   schema `audit` (o log é append-only e fora do PostgREST, mas ainda é dado que precisa
   sobreviver a um desastre).
2. **Espelho do Supabase Storage** (buckets de documentos e de anexos financeiros) via `rclone
   sync`, unidirecional, para a mesma conta de backup.
3. Ambos em **conta separada, de provedor diferente do de produção** — hoje Supabase (produção);
   backup em outro provedor S3-compatível (ex.: Backblaze B2 ou Cloudflare R2 — decisão de
   provedor é conjunta `arquiteto`/dona do projeto, ver §5).
4. Ambos **cifrados em repouso** (AES-256, `gpg` simétrico) antes de saírem da máquina que roda
   o backup — o dump contém CPF, nome, unidade e dado financeiro.
5. **Restore testado de verdade a cada trimestre**, com data e resultado registrados em
   `docs/ops/runbook-restauracao.md`. Um runbook nunca testado é ficção, não é critério de
   pronto — não conta como backup funcional até o primeiro teste passar.

## 2. Mecanismo

Implementado em `scripts/backup.sh`, executado semanalmente por
`.github/workflows/backup.yml` (`workflow_dispatch` também disponível para rodar sob demanda,
inclusive para o teste trimestral de restore).

Passo a passo do script:

1. `pg_dump "$SUPABASE_DB_URL" --format=custom --no-owner --no-privileges` → arquivo `.dump`.
2. `sha256sum` do dump, guardado ao lado — é o que permite verificar integridade no restore.
3. `gpg --symmetric --cipher-algo AES256` cifra o dump com `BACKUP_ENCRYPTION_KEY`.
4. `rclone copyto` envia o dump cifrado para `breeze-backup:<bucket>/db/<ano>/`.
5. `rclone sync` espelha o Storage de produção (`breeze-prod-storage:`) para
   `breeze-backup:<bucket>/storage-mirror`, sem passar por disco local.

Todas as variáveis usadas estão documentadas em `.env.example`. Em CI, os secrets equivalentes
vivem em GitHub Actions Secrets (nunca em texto no repositório).

## 3. Configuração pendente (ação humana, uma vez)

Isto **não foi provisionado** por este agente — provisionar remoto e gastar dinheiro exige
aprovação da dona do projeto:

1. Criar a conta de backup em um provedor S3-compatível diferente do Supabase (sugestão:
   Backblaze B2 — tem free tier e API compatível; decisão final é conjunta com `arquiteto`).
2. Rodar `rclone config` localmente (uma vez) para criar dois remotos:
   - `breeze-prod-storage` → aponta para o endpoint S3 do Supabase Storage de produção
     (`https://<project-ref>.supabase.co/storage/v1/s3`, credencial de acesso ao Storage).
   - `breeze-backup` → aponta para a conta separada criada no passo 1.
3. Copiar o `~/.config/rclone/rclone.conf` gerado, converter para base64
   (`base64 -i ~/.config/rclone/rclone.conf`) e salvar como secret `BACKUP_RCLONE_CONFIG` no
   repositório GitHub (Settings → Secrets and variables → Actions).
4. Gerar `BACKUP_ENCRYPTION_KEY` (`openssl rand -base64 32`) e salvar como secret. Guardar uma
   cópia fora do GitHub também (ex.: gerenciador de senha da dona do projeto) — se o secret do
   GitHub for perdido junto com o repositório, os backups cifrados ficam irrecuperáveis.
5. Preencher `SUPABASE_DB_URL` e `BACKUP_STORAGE_BUCKET` como secrets.
6. Rodar `.github/workflows/backup.yml` manualmente uma vez (`workflow_dispatch`) para validar
   antes de confiar no cron semanal.

Até esses passos serem feitos, `backup.yml` roda no schedule mas **falha** por falta de secrets
— falha visível e alertável é melhor que sucesso silencioso enganoso.

## 4. Retenção

Da SPEC §7:

- **Piso legal de 5 anos** para documentação condominial em geral — Lei 4.591/64, art. 22, §1º,
  alínea "g" (único piso explícito que sobreviveu à derrogação pelo Código Civil).
- Atas, convenção e laudos: **permanentes**, por decisão de produto (não obrigação legal
  comprovada).
- Log de acesso (quem consultou inadimplência nominal etc.): **6 meses**.
- Folha, ponto e registro de empregados: `[NÃO CONFIRMADO — verificar]` — não implementar
  rotina de expurgo automático para essas categorias até confirmação jurídica
  (`condominio-legal`/`juridico-lgpd`).
- Atenção: Lei 8.212/91 art. 32 §11 não fixa mais 10 anos desde a Lei 11.941/2009 — hoje é "até
  a prescrição". Não usar "10 anos" como piso de retenção sem revalidar a fonte.
- Rotina de anonimização de ex-morador preserva agregados financeiros e apaga PII — implementação
  é escopo de `eng-supabase`/backend, não deste documento.

Retenção do **backup em si** (quantas gerações semanais manter): reter os últimos 12 dumps
semanais + 1 por mês nos últimos 12 meses (política de avô-pai-filho simplificada), para conter
custo de storage sem perder capacidade de restaurar um estado de meses atrás. Ajustável quando o
volume real de dados ficar claro — não otimizar antes de doer.

## 5. Teto de custo — recorrente e LLM

### 5.1 Recorrente (infraestrutura)

Orçamento de referência (SPEC §1.2): **~R$300/mês** — Vercel Pro ~110, Supabase Pro ~140,
worker ~15, LLM 20–60, backup e domínio ~10. Custo único de OCR + embeddings do backfill do
acervo: R$50–300 (fora do recorrente).

Mudança de provedor (Vercel ou Supabase) tem impacto direto nesse orçamento e na arquitetura —
é decisão conjunta `arquiteto` + dona do projeto, este agente não decide sozinho (ver
`.claude/agents/devops.md`).

### 5.2 Teto de custo de LLM

Mecanismo previsto:

- `LLM_MONTHLY_BUDGET_CENTS` (`.env.example`) define o teto mensal em centavos de BRL. Valor de
  referência inicial: **R$60/mês** (topo da faixa 20–60 do SPEC), revisável.
- `LLM_BUDGET_ALERT_THRESHOLD_PCT` define o limiar de alerta (padrão 80%) — ao ultrapassar esse
  percentual do teto no mês corrente, dispara alerta em `LLM_BUDGET_ALERT_WEBHOOK_URL`.
- A contabilização do gasto (somar custo por chamada de classificação, OCR e síntese) é
  implementação de aplicação — escopo de `eng-supabase`/backend, não deste agente. Este agente
  garante que o **teto e o alerta existem como configuração de ambiente e como ponto de
  escalonamento no pipeline**, não que a lógica de soma está no worker.
- Ao se aproximar do teto (>= limiar), o sistema **alerta o orquestrador/dona do projeto**. Este
  agente (`devops`) e o sistema **não decidem cortar funcionalidade sozinhos** — essa decisão é
  do orquestrador ou da dona do projeto (ver "Quando escalar" em `.claude/agents/devops.md`).
- Recomendação de mitigação já prevista no SPEC (risco 7, §8): cache de consultas frequentes,
  teto mensal, modelo pequeno na etapa de classificação (`LLM_MODEL_CLASSIFICACAO` separado de
  `LLM_MODEL_SINTESE` em `.env.example`, exatamente para permitir usar um modelo mais barato na
  classificação em lote).

Pendente de ação humana: escolher e configurar o canal real de alerta (Slack, e-mail, etc.) em
`LLM_BUDGET_ALERT_WEBHOOK_URL`, e implementar a contabilização de custo por chamada (escopo de
quem escreve o pipeline de ingestão/busca, F1).
