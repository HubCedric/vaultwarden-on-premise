#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2154
set -Eeuo pipefail
umask 077

SCRIPT_NAME="backup_vaultwarden"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
load_env_file "$ENV_FILE"
LOG_FILE="${BACKUP_LOG_FILE:-/var/log/vaultwarden-backup.log}"

for var in BACKUP_DIR BACKUP_RETENTION_DAYS DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD VAULTWARDEN_DATA_DIR; do
  require_var "$var"
done

require_cmd gzip
require_cmd tar
require_cmd sha256sum
require_cmd find

DUMP_BIN="$(select_mysqldump_client)" || die "mariadb-dump or mysqldump is required"
acquire_lock "/run/lock/vaultwarden-backup.lock"

[[ -d "$VAULTWARDEN_DATA_DIR" ]] || die "Vaultwarden data directory not found: $VAULTWARDEN_DATA_DIR"

STAMP="$(date '+%Y%m%d-%H%M%S')"
PARTIAL_DIR="$BACKUP_DIR/.${STAMP}.partial"
FINAL_DIR="$BACKUP_DIR/$STAMP"
mkdir -p "$PARTIAL_DIR"

cleanup() {
  local rc=$?
  if (( rc != 0 )); then
    rm -rf "$PARTIAL_DIR"
  fi
  exit "$rc"
}
trap cleanup EXIT

info "starting backup into $FINAL_DIR"

MYSQL_PWD="$DB_PASSWORD" "$DUMP_BIN" \
  --host="$DB_HOST" \
  --port="$DB_PORT" \
  --user="$DB_USER" \
  --single-transaction \
  --quick \
  --routines \
  --events \
  --triggers \
  --hex-blob \
  --databases "$DB_NAME" \
  | gzip -9 >"$PARTIAL_DIR/database.sql.gz"

gzip -t "$PARTIAL_DIR/database.sql.gz"
[[ -s "$PARTIAL_DIR/database.sql.gz" ]] || die "database dump is empty"

# Archive the content, not the parent directory, to simplify restoration.
tar -C "$VAULTWARDEN_DATA_DIR" -czf "$PARTIAL_DIR/vaultwarden-data.tar.gz" .
tar -tzf "$PARTIAL_DIR/vaultwarden-data.tar.gz" >/dev/null

{
  printf 'created_at=%s\n' "$(now_iso)"
  printf 'node=%s\n' "${NODE_NAME:-unknown}"
  printf 'database_host=%s\n' "$DB_HOST"
  printf 'database_name=%s\n' "$DB_NAME"
  printf 'data_directory=%s\n' "$VAULTWARDEN_DATA_DIR"
  if [[ -f "${DEPLOY_ENV_FILE:-}" ]]; then
    awk -F= '$1=="VAULTWARDEN_VERSION" {print "vaultwarden_version=" $2}' "$DEPLOY_ENV_FILE" | tail -n1
    awk -F= '$1=="MARIADB_VERSION" {print "mariadb_version=" $2}' "$DEPLOY_ENV_FILE" | tail -n1
  fi
} >"$PARTIAL_DIR/manifest.txt"

(
  cd "$PARTIAL_DIR"
  sha256sum database.sql.gz vaultwarden-data.tar.gz manifest.txt >SHA256SUMS
)

mv "$PARTIAL_DIR" "$FINAL_DIR"
trap - EXIT

info "backup completed: $FINAL_DIR"

find "$BACKUP_DIR" \
  -mindepth 1 -maxdepth 1 -type d \
  -name '20????????-??????' \
  -mtime "+$BACKUP_RETENTION_DAYS" \
  -print -exec rm -rf {} + \
  | while IFS= read -r expired; do
      info "expired backup removed: $expired"
    done
