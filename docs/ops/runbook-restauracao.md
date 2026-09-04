# Runbook de restauração — Breeze

Procedimento real de restore, para ser seguido ao pé da letra em um desastre (perda do projeto
Supabase, conta comprometida, corrupção de dados) e **testado de verdade a cada trimestre**. Um
runbook nunca testado é ficção — não é critério de "pronto" até a primeira execução real estar
registrada na seção 4.

Pré-requisito: backup existente e íntegro, produzido por `scripts/backup.sh` (ver
`docs/ops/backup.md`). Sem backup, não há o que restaurar.

---

## 1. Quando acionar

- Projeto Supabase de produção inacessível, apagado ou com dados corrompidos além do que um
  estorno (SPEC §5.4) resolve.
- Suspeita de adulteração que quebra a hash-chain de `audit.log` (SPEC §7) — restaurar para uma
  versão anterior íntegra pode ser necessário para investigar, em paralelo com a escalação
  imediata do incidente.
- Teste trimestral programado (não é incidente — é exercício).

Restore falho durante o teste trimestral é **crítico**: escalar imediatamente à dona do projeto,
não apenas registrar no runbook e seguir em frente (ver `.claude/agents/devops.md`).

## 2. Pré-requisitos para executar

- Acesso ao bucket de backup (conta separada, credencial em `rclone.conf` — ver
  `docs/ops/backup.md` §3).
- `BACKUP_ENCRYPTION_KEY` para decifrar o dump.
- `supabase` CLI instalado, ou um projeto Postgres novo (local via `supabase start`, ou um
  projeto Supabase novo para o teste trimestral — **nunca sobrescrever produção durante um
  teste**, restaurar em ambiente isolado).
- `psql` / `pg_restore` compatível com a major version do Postgres do projeto (17, ver
  `supabase/config.toml`).

## 3. Procedimento passo a passo

### 3.1 Localizar e baixar o backup mais recente íntegro

```bash
# Lista os dumps disponíveis no bucket de backup, do mais recente para o mais antigo
rclone lsl breeze-backup:<bucket>/db/ | sort -k2 | tail -20

# Baixa o dump cifrado e o .sha256 correspondente
rclone copy breeze-backup:<bucket>/db/<ano>/breeze-db-<timestamp>.dump.gpg ./restore-tmp/
rclone copy breeze-backup:<bucket>/db/<ano>/breeze-db-<timestamp>.dump.sha256 ./restore-tmp/
```

### 3.2 Decifrar e verificar integridade

```bash
cd restore-tmp
gpg --batch --yes --decrypt --passphrase "$BACKUP_ENCRYPTION_KEY" \
  --output breeze-db-<timestamp>.dump \
  breeze-db-<timestamp>.dump.gpg

# Confere o hash contra o registrado no momento do backup — se não bater, o dump está
# corrompido ou adulterado; não prosseguir, buscar o dump da semana anterior e investigar.
sha256sum -c breeze-db-<timestamp>.dump.sha256   # ou: shasum -a 256 -c ...
```

### 3.3 Provisionar o destino da restauração

- **Teste trimestral:** `supabase start` local, ou um projeto Supabase novo dedicado a teste
  (nunca o de produção).
- **Desastre real:** novo projeto Supabase de produção, provisionado pela dona do projeto
  (provisionamento remoto pago não é decisão deste agente — ver `docs/ops/backup.md` §3).

Anotar a connection string do destino como `RESTORE_DB_URL`.

### 3.4 Restaurar o schema e os dados

```bash
# Formato custom (-Fc) permite restore com paralelismo e sem recriar o banco do zero
pg_restore \
  --no-owner \
  --no-privileges \
  --clean --if-exists \
  --jobs=4 \
  --dbname="$RESTORE_DB_URL" \
  breeze-db-<timestamp>.dump
```

`--clean --if-exists` remove objetos existentes antes de recriar — necessário para restaurar
por cima de um banco já inicializado pelo `supabase start` (que já tem os schemas `auth`,
`storage` etc. do Supabase). Em um projeto Supabase novo e vazio, o efeito é apenas idempotência.

### 3.5 Restaurar o Storage

```bash
# Direção invertida do backup: da conta de backup de volta para o Storage do destino.
rclone sync breeze-backup:<bucket>/storage-mirror <destino-storage-remote>: \
  --checksum --transfers 8
```

`<destino-storage-remote>` é um remoto `rclone` apontando para o endpoint S3 do Storage do
projeto de destino (mesmo mecanismo de configuração do remoto `breeze-prod-storage`, ver
`docs/ops/backup.md` §3).

### 3.6 Validação pós-restore (checklist obrigatório)

Não considerar o restore concluído sem confirmar, no destino restaurado:

- [ ] `select count(*) from documentos;` e `select count(*) from lancamentos;` batem (ordem de
      grandeza) com o esperado do backup mais recente.
- [ ] RLS está ativa nas tabelas críticas (`select relrowsecurity from pg_class where relname in
      ('documentos','chunks','documento_paginas','lancamentos');` — todas `true`).
- [ ] `audit.log` está presente e a hash-chain não está quebrada nas últimas N linhas (checagem
      manual do encadeamento `hash_registro = sha256(hash_anterior || linha canônica)` — SPEC §7).
- [ ] Um documento aleatório do Storage abre e corresponde ao registro em `documentos` (mesmo
      `sha256`).
- [ ] Login de teste (magic link) funciona no ambiente restaurado, se o teste incluir a camada
      de aplicação e não só o banco.
- [ ] Tempo total do procedimento (do início do download até a validação) registrado na seção 4
      — é o RTO real, não estimado.

### 3.7 Limpeza

Apagar o dump decifrado local (`breeze-db-<timestamp>.dump`) e o diretório `restore-tmp/` assim
que a validação terminar — não deixar dado pessoal decifrado em disco além do necessário.

```bash
cd .. && rm -rf restore-tmp
```

---

## 4. Registro de testes reais

Preencher a cada execução — teste trimestral **ou** incidente real. Sem entrada aqui, o restore
não é considerado validado, independentemente de o procedimento "parecer" correto.

| Data | Tipo (teste trimestral / incidente real) | Backup usado (timestamp) | Destino | Resultado | RTO observado | Executado por | Observações |
|---|---|---|---|---|---|---|---|
| _(nenhum teste executado ainda)_ | — | — | — | — | — | — | Pendente — primeiro teste trimestral a agendar antes do fim de F0/início de F1. Até esta linha ganhar uma entrada real, o backup **não** atende ao critério de pronto (ver `.claude/agents/devops.md`). |

Regra de cadência: uma entrada nova a cada trimestre corrido, no máximo. Se um trimestre passar
sem teste, isso é uma lacuna a escalar, não a esconder.

Se um teste **falhar**: registrar o resultado como "Falhou" com a causa, e escalar
imediatamente à dona do projeto — não é suficiente documentar e seguir para o próximo item do
backlog.
