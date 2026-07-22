#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2154
set -Eeuo pipefail
umask 077

SCRIPT_NAME="update_vaultwarden"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
load_env_file "$ENV_FILE"
LOG_FILE="${UPDATE_LOG_FILE:-/var/log/vaultwarden-update.log}"

TARGET_VERSION="${1:-}"
if [[ -z "$TARGET_VERSION" || "$TARGET_VERSION" == -* ]]; then
  printf 'Usage: %s <vaultwarden-version>\n' "$0" >&2
  exit 1
fi
if [[ ! "$TARGET_VERSION" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  die "invalid Vaultwarden version/tag: $TARGET_VERSION"
fi

for var in DEPLOY_ENV_FILE COMPOSE_FILE HEALTHCHECK_TIMEOUT VAULTWARDEN_SERVICE; do
  require_var "$var"
done
require_cmd docker
require_cmd awk
require_cmd mktemp

[[ -f "$DEPLOY_ENV_FILE" ]] || die "deployment env file not found: $DEPLOY_ENV_FILE"
[[ -f "$COMPOSE_FILE" ]] || die "compose file not found: $COMPOSE_FILE"
acquire_lock "/run/lock/vaultwarden-update.lock"

get_env_value() {
  local key="$1"
  awk -F= -v key="$key" '$1==key {sub(/^[^=]*=/, ""); print; exit}' "$DEPLOY_ENV_FILE"
}

set_env_value() {
  local key="$1"
  local value="$2"
  local tmp
  tmp="$(mktemp "${DEPLOY_ENV_FILE}.XXXXXX")"
  awk -v key="$key" -v value="$value" '
    BEGIN { found=0 }
    $0 ~ "^" key "=" { print key "=" value; found=1; next }
    { print }
    END { if (!found) print key "=" value }
  ' "$DEPLOY_ENV_FILE" >"$tmp"
  chmod --reference="$DEPLOY_ENV_FILE" "$tmp" 2>/dev/null || chmod 600 "$tmp"
  mv "$tmp" "$DEPLOY_ENV_FILE"
}

CURRENT_VERSION="$(get_env_value VAULTWARDEN_VERSION)"
[[ -n "$CURRENT_VERSION" ]] || die "VAULTWARDEN_VERSION is missing from $DEPLOY_ENV_FILE"

if [[ "$CURRENT_VERSION" == "$TARGET_VERSION" ]]; then
  info "Vaultwarden $TARGET_VERSION is already configured"
  exit 0
fi

info "preparing update from $CURRENT_VERSION to $TARGET_VERSION"
"$SCRIPT_DIR/backup_vaultwarden.sh"

ENV_BACKUP="${DEPLOY_ENV_FILE}.before-${TARGET_VERSION}.$(date '+%Y%m%d-%H%M%S')"
cp "$DEPLOY_ENV_FILE" "$ENV_BACKUP"
rollback() {
  warn "rolling back deployment variable to $CURRENT_VERSION"
  cp "$ENV_BACKUP" "$DEPLOY_ENV_FILE"
  if compose config --quiet && compose up -d --no-deps "$VAULTWARDEN_SERVICE"; then
    warn "previous image was redeployed; database migrations are not automatically reverted"
  else
    error "automatic image rollback failed; manual intervention required"
  fi
}

set_env_value VAULTWARDEN_VERSION "$TARGET_VERSION"
if ! compose config --quiet; then
  rollback
  die "Compose validation failed with the target version"
fi

info "pulling Vaultwarden image $TARGET_VERSION"
if ! compose pull "$VAULTWARDEN_SERVICE"; then
  rollback
  die "image pull failed"
fi

STARTED_AT="$(date --iso-8601=seconds)"
info "redeploying Vaultwarden"
if ! compose up -d --no-deps "$VAULTWARDEN_SERVICE"; then
  rollback
  die "Compose redeployment failed"
fi

CONTAINER_ID="$(compose ps -q "$VAULTWARDEN_SERVICE")"
[[ -n "$CONTAINER_ID" ]] || {
  rollback
  die "cannot resolve the Vaultwarden container id"
}

ELAPSED=0
STATUS="starting"
while (( ELAPSED < HEALTHCHECK_TIMEOUT )); do
  STATUS="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$CONTAINER_ID" 2>/dev/null || true)"
  case "$STATUS" in
    healthy) break ;;
    unhealthy|exited|dead) break ;;
  esac
  sleep 3
  ELAPSED=$((ELAPSED + 3))
done

RECENT_LOGS="$(docker logs --since "$STARTED_AT" "$CONTAINER_ID" 2>&1 || true)"
printf '%s\n' "$RECENT_LOGS" >>"$LOG_FILE"

if grep -Eiq 'panic|Error running migrations|QueryError|DatabaseError' <<<"$RECENT_LOGS"; then
  error "migration or database error detected in container logs"
  rollback
  exit 1
fi

if [[ "$STATUS" != "healthy" ]]; then
  error "Vaultwarden did not become healthy within ${HEALTHCHECK_TIMEOUT}s (status=$STATUS)"
  rollback
  exit 1
fi

rm -f "$ENV_BACKUP"
info "Vaultwarden update completed successfully: $CURRENT_VERSION -> $TARGET_VERSION"
