#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

load_env() {
  local env_file="${ENV_FILE:-/etc/vaultwarden-monitor/monitor.env}"
  [[ -r "$env_file" ]] || { echo "Fichier de configuration introuvable: $env_file" >&2; exit 2; }
  # shellcheck disable=SC1090
  source "$env_file"
}

require_vars() {
  local v
  for v in "$@"; do
    [[ -n "${!v:-}" ]] || { echo "Variable obligatoire absente: $v" >&2; exit 2; }
  done
}

now_iso() { TZ="${TIMEZONE:-Europe/Paris}" date '+%Y-%m-%d %H:%M:%S %Z'; }

log_line() {
  local level="$1"; shift
  local line
  line="$(now_iso) [$level] $*"
  printf '%s\n' "$line"
  [[ -n "${LOG_FILE:-}" ]] && printf '%s\n' "$line" >>"$LOG_FILE"
}

send_mail() {
  local subject="$1"
  local body="$2"
  [[ "${MAIL_ENABLED:-1}" == "1" ]] || return 0
  command -v msmtp >/dev/null 2>&1 || { log_line ERROR "msmtp est absent"; return 1; }

  {
    printf 'From: %s <%s>\n' "${MAIL_FROM_NAME:-Vaultwarden Monitor}" "$MAIL_FROM"
    printf 'To: %s\n' "$MAIL_TO"
    printf 'Subject: %s\n' "$subject"
    printf 'Content-Type: text/plain; charset=UTF-8\n'
    printf 'Content-Transfer-Encoding: 8bit\n'
    printf '\n%s\n' "$body"
  } | msmtp --account="${MSMTP_ACCOUNT:-default}" "$MAIL_TO"
}

mysql_cmd() {
  local host="$1" port="$2"; shift 2
  MYSQL_PWD="$MONITOR_PASSWORD" mariadb \
    --connect-timeout=5 \
    --host="$host" --port="$port" --user="$MONITOR_USER" \
    --batch --raw "$@"
}

field() {
  local dump="$1" key="$2"
  awk -F': ' -v k="$key" '$1 ~ "^[[:space:]]*" k "$" {print $2; exit}' <<<"$dump"
}

safe_mkdirs() {
  install -d -m 700 "$STATE_DIR"
  touch "$LOG_FILE"
  chmod 600 "$LOG_FILE"
}
