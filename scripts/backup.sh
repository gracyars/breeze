#!/usr/bin/env bash
#
# scripts/backup.sh — backup semanal próprio do Breeze.
#
# Regra dura (SPEC §7, docs/ops/backup.md): o snapshot automático do Supabase NÃO conta como
# backup. Este script faz (1) `pg_dump` completo do Postgres e (2) espelho do Storage, cifra os
# dois e envia para uma conta de um provedor DIFERENTE do de produção. Roda semanalmente via
# `.github/workflows/backup.yml` e pode ser rodado manualmente para o teste trimestral de
# restore (docs/ops/runbook-restauracao.md).
#
# Requer (ver .env.example): SUPABASE_DB_URL, BACKUP_STORAGE_PROVIDER, BACKUP_STORAGE_BUCKET,
# BACKUP_STORAGE_ACCESS_KEY_ID, BACKUP_STORAGE_SECRET_ACCESS_KEY, BACKUP_STORAGE_REGION,
# BACKUP_ENCRYPTION_KEY. Requer os binários: pg_dump, rclone, gpg, sha256sum (ou shasum).
#
# Uso:
#   scripts/backup.sh                # dump + storage + upload (rotina semanal)
#   scripts/backup.sh --dump-only     # só gera os arquivos locais, não sobe (útil p/ teste local)

set -euo pipefail

: "${SUPABASE_DB_URL:?defina SUPABASE_DB_URL (ver .env.example)}"
: "${BACKUP_STORAGE_BUCKET:?defina BACKUP_STORAGE_BUCKET (conta separada, provedor diferente)}"
: "${BACKUP_ENCRYPTION_KEY:?defina BACKUP_ENCRYPTION_KEY para cifrar o dump antes do upload}"

DUMP_ONLY=false
if [[ "${1:-}" == "--dump-only" ]]; then
  DUMP_ONLY=true
fi

STAMP="$(date -u +%Y-%m-%dT%H%M%SZ)"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/breeze-backup.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

echo "== Breeze backup — $STAMP =="
echo "Diretório de trabalho: $WORKDIR"

# ---------------------------------------------------------------------------
# 1. pg_dump do Postgres (schema + dados), formato custom (-Fc) — permite restore seletivo e
#    é mais compacto que texto puro. Inclui o schema `audit` (READ do log é parte do backup,
#    mesmo sendo append-only e fora do PostgREST).
# ---------------------------------------------------------------------------
DUMP_FILE="$WORKDIR/breeze-db-${STAMP}.dump"
echo "-- pg_dump para $DUMP_FILE"
pg_dump "$SUPABASE_DB_URL" \
  --format=custom \
  --no-owner \
  --no-privileges \
  --file="$DUMP_FILE"

DUMP_SHA256="$(sha256sum "$DUMP_FILE" 2>/dev/null || shasum -a 256 "$DUMP_FILE")"
echo "$DUMP_SHA256" > "$DUMP_FILE.sha256"
echo "-- sha256: $DUMP_SHA256"

# ---------------------------------------------------------------------------
# 2. Cifra o dump em repouso antes de sair da máquina (dado pessoal — CPF, nome, unidade,
#    financeiro). AES-256, simétrico, chave fora do repositório (BACKUP_ENCRYPTION_KEY).
# ---------------------------------------------------------------------------
ENCRYPTED_DUMP="$DUMP_FILE.gpg"
echo "-- cifrando dump"
gpg --batch --yes --symmetric --cipher-algo AES256 \
  --passphrase "$BACKUP_ENCRYPTION_KEY" \
  --output "$ENCRYPTED_DUMP" \
  "$DUMP_FILE"
rm -f "$DUMP_FILE"

if $DUMP_ONLY; then
  echo "-- --dump-only: arquivos ficam em $WORKDIR (trap não vai apagar até você copiar)"
  trap - EXIT
  echo "$WORKDIR"
  exit 0
fi

# ---------------------------------------------------------------------------
# 3. Upload do dump cifrado para a conta de backup — provedor diferente do de produção,
#    configurado como remoto `rclone` chamado `breeze-backup` (ver docs/ops/backup.md para o
#    passo de configuração one-time do `rclone config`, feito manualmente pela dona do projeto,
#    nunca com credencial em texto no CI).
# ---------------------------------------------------------------------------
RCLONE_REMOTE="${BACKUP_RCLONE_REMOTE:-breeze-backup}"
DEST_DB="${RCLONE_REMOTE}:${BACKUP_STORAGE_BUCKET}/db/$(date -u +%Y)/$(basename "$ENCRYPTED_DUMP")"
echo "-- enviando dump cifrado para $DEST_DB"
rclone copyto "$ENCRYPTED_DUMP" "$DEST_DB" --checksum
rclone copyto "$DUMP_FILE.sha256" "${DEST_DB}.sha256" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 4. Espelho do Supabase Storage (buckets de documentos e anexos financeiros) direto para a
#    conta de backup, sem passar por disco local — `rclone sync` entre dois remotos S3
#    compatíveis (Supabase Storage expõe endpoint S3; ver docs/ops/backup.md). `sync` é
#    unidirecional: origem → backup, nunca o inverso.
# ---------------------------------------------------------------------------
SUPABASE_STORAGE_REMOTE="${BACKUP_SUPABASE_STORAGE_REMOTE:-breeze-prod-storage}"
DEST_STORAGE="${RCLONE_REMOTE}:${BACKUP_STORAGE_BUCKET}/storage-mirror"
echo "-- espelhando Storage: ${SUPABASE_STORAGE_REMOTE}: -> $DEST_STORAGE"
rclone sync "${SUPABASE_STORAGE_REMOTE}:" "$DEST_STORAGE" \
  --checksum \
  --transfers 8 \
  --log-level INFO

echo "== Backup concluído: $STAMP =="
echo "DB: $DEST_DB"
echo "Storage: $DEST_STORAGE"
echo ""
echo "Lembrete: registrar esta execução (ou falha) se for o teste trimestral, em"
echo "docs/ops/runbook-restauracao.md — backup nunca testado não é backup."
