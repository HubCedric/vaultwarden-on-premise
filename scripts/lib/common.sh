#!/usr/bin/env bash

# Shared helpers. The calling script is expected to enable strict mode.

SCRIPT_NAME="${SCRIPT_NAME:-$(basename "$0")}"

load_env_file() {
  local env_file="$1"
  if [[ ! -f "$env_file" ]]; then
    printf 'ERROR: environment file not found: %s\n' "$env_file" >&2
    return 1
  fi

  # shellcheck disable=SC1090
  set -a
  source "$env_file"
  set +a
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || {
    printf 'ERROR: required command not found: %s\n' "$cmd" >&2
    return 1
  }
}

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    printf 'ERROR: required variable is empty: %s\n' "$name" >&2
    return 1
  fi
}

now_iso() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

log_line() {
  local level="$1"
  shift
  local message="$*"
  local line
  line="$(now_iso) [$level] [$SCRIPT_NAME] $message"
  printf '%s\n' "$line"
  if [[ -n "${LOG_FILE:-}" ]]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    printf '%s\n' "$line" >>"$LOG_FILE"
  fi
}

info() { log_line INFO "$@"; }
warn() { log_line WARN "$@"; }
error() { log_line ERROR "$@"; }

die() {
  error "$@"
  exit 1
}

acquire_lock() {
  local lock_file="$1"
  require_cmd flock
  mkdir -p "$(dirname "$lock_file")"
  exec 9>"$lock_file"
  flock -n 9 || die "another execution is already running: $lock_file"
}

compose() {
  # shellcheck disable=SC2154
  docker compose --env-file "$DEPLOY_ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

select_mysql_client() {
  if command -v mariadb >/dev/null 2>&1; then
    printf '%s' mariadb
  elif command -v mysql >/dev/null 2>&1; then
    printf '%s' mysql
  else
    return 1
  fi
}

select_mysqldump_client() {
  if command -v mariadb-dump >/dev/null 2>&1; then
    printf '%s' mariadb-dump
  elif command -v mysqldump >/dev/null 2>&1; then
    printf '%s' mysqldump
  else
    return 1
  fi
}
