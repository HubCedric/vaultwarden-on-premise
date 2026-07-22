#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2154
set -Eeuo pipefail

SCRIPT_NAME="healthcheck"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
load_env_file "$ENV_FILE"
LOG_FILE="${HEALTHCHECK_LOG_FILE:-/var/log/vaultwarden-healthcheck.log}"

for var in DEPLOY_ENV_FILE COMPOSE_FILE DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD; do
  require_var "$var"
done

require_cmd docker
require_cmd curl
MYSQL_BIN="$(select_mysql_client)" || die "mariadb or mysql client is required"

FAILED=0

if compose ps --status running --services | grep -qx "${VAULTWARDEN_SERVICE:-vaultwarden}"; then
  info "Vaultwarden service is running"
else
  error "Vaultwarden service is not running"
  FAILED=1
fi

WIREGUARD_IP="$(awk -F= '$1=="WIREGUARD_IP" {print $2}' "$DEPLOY_ENV_FILE" | tail -n1)"
if [[ -n "$WIREGUARD_IP" ]] && curl --fail --silent --show-error --max-time 5 "http://${WIREGUARD_IP}:8080/alive" >/dev/null; then
  info "Vaultwarden /alive endpoint is healthy"
else
  error "Vaultwarden /alive endpoint failed"
  FAILED=1
fi

if MYSQL_PWD="$DB_PASSWORD" "$MYSQL_BIN" --connect-timeout=5 -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -N -e 'SELECT 1;' "$DB_NAME" | grep -qx 1; then
  info "MariaDB query succeeded"
else
  error "MariaDB query failed"
  FAILED=1
fi

if [[ "${CHECK_REPLICATION_IN_HEALTHCHECK:-0}" == "1" ]]; then
  if "$SCRIPT_DIR/check_replication.sh"; then
    info "Replication check succeeded"
  else
    error "Replication check failed"
    FAILED=1
  fi
fi

exit "$FAILED"
