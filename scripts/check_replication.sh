#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2154
set -Eeuo pipefail
umask 077

SCRIPT_NAME="check_replication"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
load_env_file "$ENV_FILE"
LOG_FILE="${REPLICATION_LOG_FILE:-/var/log/vaultwarden-replication.log}"

for var in NODE_NAME LOCAL_DB_HOST LOCAL_DB_PORT PEER_HOST PEER_PORT MONITOR_USER MONITOR_PASSWORD SECONDS_BEHIND_THRESHOLD RESTART_RETRY_COUNT RESTART_RETRY_DELAY; do
  require_var "$var"
done

MYSQL_BIN="$(select_mysql_client)" || die "mariadb or mysql client is required"
acquire_lock "/run/lock/vaultwarden-replication-${NODE_NAME}.lock"

mysql_query() {
  local host="$1"
  local port="$2"
  shift 2
  MYSQL_PWD="$MONITOR_PASSWORD" "$MYSQL_BIN" \
    --connect-timeout=5 \
    --host="$host" \
    --port="$port" \
    --user="$MONITOR_USER" \
    --batch --raw "$@"
}

local_query() { mysql_query "$LOCAL_DB_HOST" "$LOCAL_DB_PORT" "$@"; }
peer_query() { mysql_query "$PEER_HOST" "$PEER_PORT" "$@"; }

field() {
  local dump="$1"
  local name="$2"
  awk -F': ' -v key="$name" '$1 ~ "^[[:space:]]*" key "$" {print $2; exit}' <<<"$dump"
}

notify() {
  local subject="$1"
  local body="$2"
  warn "$subject - $body"
  if [[ "${ENABLE_MAIL:-0}" == "1" ]]; then
    if command -v mail >/dev/null 2>&1; then
      printf '%s\n' "$body" | mail -s "$subject" "$MAIL_TO" || warn "mail delivery failed"
    else
      warn "ENABLE_MAIL=1 but mail command is unavailable"
    fi
  fi
}

get_local_status() { local_query --execute='SHOW SLAVE STATUS\G'; }
get_peer_status() { peer_query --execute='SHOW SLAVE STATUS\G'; }

restart_replication() {
  local attempt status io sql
  for ((attempt = 1; attempt <= RESTART_RETRY_COUNT; attempt++)); do
    info "replication restart attempt $attempt/$RESTART_RETRY_COUNT"
    local_query --execute='STOP SLAVE; START SLAVE;' >/dev/null
    sleep "$RESTART_RETRY_DELAY"
    status="$(get_local_status)"
    io="$(field "$status" Slave_IO_Running)"
    sql="$(field "$status" Slave_SQL_Running)"
    if [[ "$io" == "Yes" && "$sql" == "Yes" ]]; then
      info "replication threads restarted successfully"
      return 0
    fi
  done
  return 1
}

reconfigure_replication() {
  require_var REPL_USER
  require_var REPL_PASSWORD

  local gtid
  gtid="$(local_query --skip-column-names --execute='SELECT @@global.gtid_slave_pos;')"
  [[ -n "$gtid" ]] || return 2

  info "reconfiguring replication from the existing gtid_slave_pos"
  # Values come from the protected local .env. Do not log this statement.
  local_query --execute="CHANGE MASTER TO MASTER_HOST='${PEER_HOST}', MASTER_PORT=${PEER_PORT}, MASTER_USER='${REPL_USER}', MASTER_PASSWORD='${REPL_PASSWORD}', MASTER_USE_GTID=slave_pos; START SLAVE;" >/dev/null
  sleep "$RESTART_RETRY_DELAY"

  local status io sql
  status="$(get_local_status)"
  io="$(field "$status" Slave_IO_Running)"
  sql="$(field "$status" Slave_SQL_Running)"
  [[ "$io" == "Yes" && "$sql" == "Yes" ]]
}

info "checking local replication on $NODE_NAME ($LOCAL_DB_HOST:$LOCAL_DB_PORT)"

if ! LOCAL_STATUS="$(get_local_status 2>>"$LOG_FILE")"; then
  notify "[$NODE_NAME] MariaDB local connection failed" "Cannot query the local database. Replication status is unknown."
  exit 2
fi

EXIT_CODE=0

if [[ -z "$LOCAL_STATUS" ]]; then
  if [[ "${REPLICATION_AUTO_RECONFIGURE:-0}" == "1" ]]; then
    if reconfigure_replication; then
      notify "[$NODE_NAME] replication reconfigured" "The replication connection was missing and was recreated from the existing gtid_slave_pos."
    else
      rc=$?
      if [[ "$rc" -eq 2 ]]; then
        notify "[$NODE_NAME] replication is not configured" "SHOW SLAVE STATUS and gtid_slave_pos are empty. Manual initialization is required."
      else
        notify "[$NODE_NAME] replication reconfiguration failed" "Manual intervention is required."
      fi
      EXIT_CODE=2
    fi
  else
    notify "[$NODE_NAME] replication is not configured" "SHOW SLAVE STATUS is empty. Automatic reconfiguration is disabled."
    EXIT_CODE=2
  fi
else
  IO_RUNNING="$(field "$LOCAL_STATUS" Slave_IO_Running)"
  SQL_RUNNING="$(field "$LOCAL_STATUS" Slave_SQL_Running)"
  SQL_ERRNO="$(field "$LOCAL_STATUS" Last_SQL_Errno)"
  SQL_ERROR="$(field "$LOCAL_STATUS" Last_SQL_Error)"
  IO_ERRNO="$(field "$LOCAL_STATUS" Last_IO_Errno)"
  IO_ERROR="$(field "$LOCAL_STATUS" Last_IO_Error)"
  LAG="$(field "$LOCAL_STATUS" Seconds_Behind_Master)"

  if [[ "$SQL_ERRNO" =~ ^[0-9]+$ ]] && (( SQL_ERRNO != 0 )); then
    notify "[$NODE_NAME] replication SQL error $SQL_ERRNO" "$SQL_ERROR. No automatic skip was attempted."
    EXIT_CODE=2
  elif [[ "$IO_RUNNING" == "Yes" && "$SQL_RUNNING" == "Yes" ]]; then
    if [[ "$LAG" =~ ^[0-9]+$ ]] && (( LAG > SECONDS_BEHIND_THRESHOLD )); then
      notify "[$NODE_NAME] replication lag ${LAG}s" "Threads are running but lag exceeds ${SECONDS_BEHIND_THRESHOLD}s."
      EXIT_CODE=1
    else
      info "local replication healthy: IO=$IO_RUNNING SQL=$SQL_RUNNING lag=${LAG:-unknown}s"
    fi
  else
    warn "replication thread stopped: IO=$IO_RUNNING SQL=$SQL_RUNNING IO_ERRNO=${IO_ERRNO:-0}"
    if [[ "${REPLICATION_AUTO_RESTART:-0}" == "1" ]]; then
      if restart_replication; then
        notify "[$NODE_NAME] replication restarted" "Stopped threads were restarted without skipping SQL events. Previous IO error: ${IO_ERROR:-none}."
      else
        notify "[$NODE_NAME] replication restart failed" "Manual intervention is required."
        EXIT_CODE=2
      fi
    else
      notify "[$NODE_NAME] replication threads stopped" "Automatic restart is disabled. IO=${IO_RUNNING}, SQL=${SQL_RUNNING}, error=${IO_ERROR:-none}."
      EXIT_CODE=2
    fi
  fi
fi

info "checking peer replication status ($PEER_HOST:$PEER_PORT)"
if ! PEER_STATUS="$(get_peer_status 2>>"$LOG_FILE")"; then
  notify "[$NODE_NAME] peer database unreachable" "Cannot query $PEER_HOST:$PEER_PORT with the monitor account."
  (( EXIT_CODE < 2 )) && EXIT_CODE=2
elif [[ -z "$PEER_STATUS" ]]; then
  notify "[$NODE_NAME] peer replication is not configured" "The peer is reachable but SHOW SLAVE STATUS is empty."
  (( EXIT_CODE < 2 )) && EXIT_CODE=2
else
  PEER_IO="$(field "$PEER_STATUS" Slave_IO_Running)"
  PEER_SQL="$(field "$PEER_STATUS" Slave_SQL_Running)"
  PEER_LAG="$(field "$PEER_STATUS" Seconds_Behind_Master)"
  info "peer status: IO=$PEER_IO SQL=$PEER_SQL lag=${PEER_LAG:-unknown}s"
  if [[ "$PEER_IO" != "Yes" || "$PEER_SQL" != "Yes" ]]; then
    notify "[$NODE_NAME] peer replication unhealthy" "Peer status: IO=$PEER_IO SQL=$PEER_SQL."
    (( EXIT_CODE < 2 )) && EXIT_CODE=2
  fi
fi

exit "$EXIT_CODE"
