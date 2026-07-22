#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY_DIR="${DEPLOY_DIR:-$ROOT_DIR/deploy/node}"
ENV_FILE="${1:-$DEPLOY_DIR/.env}"
COMPOSE_FILE="${COMPOSE_FILE:-$DEPLOY_DIR/compose.yaml}"
MARIADB_CONFIG="${MARIADB_CONFIG:-$DEPLOY_DIR/config/mariadb/50-server.cnf}"

ERRORS=0
WARNINGS=0

ok() { printf 'OK    %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*" >&2; WARNINGS=$((WARNINGS + 1)); }
fail() { printf 'ERROR %s\n' "$*" >&2; ERRORS=$((ERRORS + 1)); }

[[ -f "$ENV_FILE" ]] || { fail "missing deployment environment file: $ENV_FILE"; exit 1; }
[[ -f "$COMPOSE_FILE" ]] || { fail "missing Compose file: $COMPOSE_FILE"; exit 1; }
[[ -f "$MARIADB_CONFIG" ]] || fail "missing MariaDB configuration: $MARIADB_CONFIG"

# The file is local administrator input and must follow shell-compatible .env syntax.
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

required=(
  COMPOSE_PROJECT_NAME TZ WIREGUARD_IP VAULTWARDEN_VERSION MARIADB_VERSION
  DOMAIN MARIADB_DATABASE MARIADB_USER MARIADB_PASSWORD MARIADB_ROOT_PASSWORD
  DATABASE_URL ADMIN_TOKEN SIGNUPS_ALLOWED
)

for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    fail "required variable is empty: $name"
  fi
done

if grep -Eq '(^|[^A-Z_])(CHANGE_ME|OWNER/REPOSITORY)' "$ENV_FILE"; then
  fail "the environment file still contains a CHANGE_ME or repository placeholder"
else
  ok "no deployment placeholder found in .env"
fi

if [[ "${DOMAIN:-}" == https://* ]]; then
  ok "DOMAIN uses HTTPS"
else
  fail "DOMAIN must be a complete HTTPS URL"
fi

if [[ "${VAULTWARDEN_VERSION:-}" == "latest" || "${MARIADB_VERSION:-}" == "latest" ]]; then
  fail "production image tags must be explicit, not latest"
else
  ok "container image tags are explicit"
fi

if [[ "${ADMIN_TOKEN:-}" == *argon2id* ]]; then
  ok "ADMIN_TOKEN looks like an Argon2 PHC value"
else
  fail "ADMIN_TOKEN does not look like an Argon2 hash"
fi

if [[ "${DATABASE_URL:-}" == mysql://*"@mariadb:"*"/${MARIADB_DATABASE:-}" ]]; then
  ok "DATABASE_URL targets the internal MariaDB service"
else
  warn "DATABASE_URL does not match the expected internal service/name pattern"
fi

for directory in "$DEPLOY_DIR/data/mariadb" "$DEPLOY_DIR/data/vaultwarden"; do
  if [[ -d "$directory" ]]; then
    ok "persistent directory exists: ${directory#$ROOT_DIR/}"
  else
    fail "missing persistent directory: $directory"
  fi
done

if command -v ip >/dev/null 2>&1; then
  if ip -o address show | grep -Fq " ${WIREGUARD_IP:-__missing__}/"; then
    ok "WIREGUARD_IP exists on this host"
  else
    warn "WIREGUARD_IP is not currently assigned on this host"
  fi
else
  warn "ip command unavailable; WireGuard address was not checked"
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  if docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config --quiet; then
    ok "Docker Compose configuration is valid"
  else
    fail "Docker Compose configuration is invalid"
  fi
else
  warn "Docker Compose unavailable; semantic Compose validation was skipped"
fi

if (( ERRORS > 0 )); then
  printf '\nPreflight failed: %d error(s), %d warning(s).\n' "$ERRORS" "$WARNINGS" >&2
  exit 1
fi

printf '\nPreflight succeeded with %d warning(s).\n' "$WARNINGS"
