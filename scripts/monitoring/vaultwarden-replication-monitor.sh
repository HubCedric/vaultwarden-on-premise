#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
load_env

require_vars NODE_NAME NODE_ROLE LOCAL_DB_HOST LOCAL_DB_PORT LOCAL_SERVER_ID \
  PEER_NAME PEER_HOST PEER_PORT PEER_SERVER_ID MONITOR_USER MONITOR_PASSWORD \
  EXPECTED_MASTER_HOST EXPECTED_MASTER_PORT EXPECTED_GTID_MODE \
  LAG_WARNING_SECONDS LAG_CRITICAL_SECONDS FAILURES_BEFORE_STOP \
  VAULTWARDEN_CONTAINER CONTAINER_STARTING_MAX_SECONDS RESTART_DELTA_CRITICAL \
  ALLOW_SAFETY_STOP MAIL_FROM MAIL_TO STATE_DIR LOG_FILE MAINTENANCE_FILE

safe_mkdirs
exec 9>"$STATE_DIR/monitor.lock"
flock -n 9 || exit 0

MODE="${1:---check}"
case "$MODE" in
  --check|--verbose|--send-test-mail|--force-alert) ;;
  *) echo "Usage: $0 [--check|--verbose|--send-test-mail|--force-alert]" >&2; exit 2 ;;
esac

if [[ "$MODE" == "--send-test-mail" ]]; then
  send_mail "[TEST][$NODE_NAME] Supervision Vaultwarden" \
"Test SMTP réussi depuis $NODE_NAME.
Date : $(now_iso)
Pair configuré : $PEER_NAME ($PEER_HOST:$PEER_PORT)"
  log_line INFO "Mail de test envoyé"
  exit 0
fi

if [[ -e "$MAINTENANCE_FILE" ]]; then
  log_line INFO "Mode maintenance actif; contrôle ignoré"
  exit 0
fi

declare -a PROBLEMS=()
declare -a CRITICALS=()
declare -a DETAILS=()
declare -a RECOMMENDATIONS=()

add_problem() {
  PROBLEMS+=("$1")
  DETAILS+=("$2")
}
add_critical() {
  CRITICALS+=("$1")
  PROBLEMS+=("$1")
  DETAILS+=("$2")
}

status_summary() {
  local label="$1" status="$2"
  local master_host master_port master_id io sql lag io_errno io_error sql_errno sql_error using_gtid gtid_io relay_file relay_pos
  master_host="$(field "$status" Master_Host)"
  master_port="$(field "$status" Master_Port)"
  master_id="$(field "$status" Master_Server_Id)"
  io="$(field "$status" Slave_IO_Running)"
  sql="$(field "$status" Slave_SQL_Running)"
  lag="$(field "$status" Seconds_Behind_Master)"
  io_errno="$(field "$status" Last_IO_Errno)"
  io_error="$(field "$status" Last_IO_Error)"
  sql_errno="$(field "$status" Last_SQL_Errno)"
  sql_error="$(field "$status" Last_SQL_Error)"
  using_gtid="$(field "$status" Using_Gtid)"
  gtid_io="$(field "$status" Gtid_IO_Pos)"
  relay_file="$(field "$status" Relay_Master_Log_File)"
  relay_pos="$(field "$status" Exec_Master_Log_Pos)"

  cat <<EOF
[$label]
Master_Host: ${master_host:-vide}
Master_Port: ${master_port:-vide}
Master_Server_Id: ${master_id:-vide}
Slave_IO_Running: ${io:-vide}
Slave_SQL_Running: ${sql:-vide}
Seconds_Behind_Master: ${lag:-NULL}
Last_IO_Errno: ${io_errno:-vide}
Last_IO_Error: ${io_error:-vide}
Last_SQL_Errno: ${sql_errno:-vide}
Last_SQL_Error: ${sql_error:-vide}
Using_Gtid: ${using_gtid:-vide}
Gtid_IO_Pos: ${gtid_io:-vide}
Relay_Master_Log_File: ${relay_file:-vide}
Exec_Master_Log_Pos: ${relay_pos:-vide}
EOF
}

check_replication_status() {
  local detected_on="$1" expected_host="$2" expected_port="$3" expected_server_id="$4" status="$5"
  local io sql lag io_errno sql_errno master_host master_port master_id using_gtid gtid_io
  io="$(field "$status" Slave_IO_Running)"
  sql="$(field "$status" Slave_SQL_Running)"
  lag="$(field "$status" Seconds_Behind_Master)"
  io_errno="$(field "$status" Last_IO_Errno)"
  sql_errno="$(field "$status" Last_SQL_Errno)"
  master_host="$(field "$status" Master_Host)"
  master_port="$(field "$status" Master_Port)"
  master_id="$(field "$status" Master_Server_Id)"
  using_gtid="$(field "$status" Using_Gtid)"
  gtid_io="$(field "$status" Gtid_IO_Pos)"

  [[ "$io" == "Yes" ]] || add_critical "$detected_on: thread IO arrêté" "Slave_IO_Running=${io:-vide}"
  [[ "$sql" == "Yes" ]] || add_critical "$detected_on: thread SQL arrêté" "Slave_SQL_Running=${sql:-vide}"

  if [[ "${io_errno:-0}" =~ ^[0-9]+$ ]] && (( io_errno != 0 )); then
    add_critical "$detected_on: erreur IO $io_errno" "$(field "$status" Last_IO_Error)"
    RECOMMENDATIONS+=("Ne pas effectuer de saut automatique d'événement. Examiner l'erreur IO et les GTID.")
  fi
  if [[ "${sql_errno:-0}" =~ ^[0-9]+$ ]] && (( sql_errno != 0 )); then
    add_critical "$detected_on: erreur SQL $sql_errno" "$(field "$status" Last_SQL_Error)"
    RECOMMENDATIONS+=("Ne pas utiliser sql_slave_skip_counter sans analyse de cohérence.")
  fi

  [[ "$master_host" == "$expected_host" ]] || add_critical "$detected_on: source incorrecte" "Master_Host=$master_host; attendu=$expected_host"
  [[ "$master_port" == "$expected_port" ]] || add_critical "$detected_on: port source incorrect" "Master_Port=$master_port; attendu=$expected_port"
  [[ "$master_id" == "$expected_server_id" ]] || add_critical "$detected_on: server_id source incorrect" "Master_Server_Id=$master_id; attendu=$expected_server_id"
  [[ "$using_gtid" == "$EXPECTED_GTID_MODE" ]] || add_critical "$detected_on: mode GTID inattendu" "Using_Gtid=$using_gtid; attendu=$EXPECTED_GTID_MODE"
  [[ -n "$gtid_io" ]] || add_critical "$detected_on: Gtid_IO_Pos vide" "La position GTID reçue est vide."

  if [[ "$lag" == "NULL" || -z "$lag" ]]; then
    add_critical "$detected_on: retard indéterminable" "Seconds_Behind_Master=${lag:-vide}"
  elif [[ "$lag" =~ ^[0-9]+$ ]]; then
    if (( lag > LAG_CRITICAL_SECONDS )); then
      add_critical "$detected_on: retard critique ${lag}s" "Seuil critique=${LAG_CRITICAL_SECONDS}s"
    elif (( lag > LAG_WARNING_SECONDS )); then
      add_problem "$detected_on: retard élevé ${lag}s" "Seuil d'alerte=${LAG_WARNING_SECONDS}s"
    fi
  else
    add_problem "$detected_on: valeur de retard invalide" "Seconds_Behind_Master=$lag"
  fi
}

LOCAL_STATUS=""
PEER_STATUS=""

if ! LOCAL_STATUS="$(mysql_cmd "$LOCAL_DB_HOST" "$LOCAL_DB_PORT" --execute='SHOW SLAVE STATUS\G' 2>&1)"; then
  add_critical "$NODE_NAME: MariaDB inaccessible" "$LOCAL_STATUS"
elif [[ -z "$LOCAL_STATUS" ]]; then
  add_critical "$NODE_NAME: réplication absente" "SHOW SLAVE STATUS ne retourne aucune ligne."
else
  check_replication_status "$NODE_NAME" "$EXPECTED_MASTER_HOST" "$EXPECTED_MASTER_PORT" "$PEER_SERVER_ID" "$LOCAL_STATUS"
fi

if ! PEER_STATUS="$(mysql_cmd "$PEER_HOST" "$PEER_PORT" --execute='SHOW SLAVE STATUS\G' 2>&1)"; then
  add_critical "$PEER_NAME: MariaDB inaccessible depuis $NODE_NAME" "$PEER_STATUS"
elif [[ -z "$PEER_STATUS" ]]; then
  add_critical "$PEER_NAME: réplication absente" "SHOW SLAVE STATUS ne retourne aucune ligne."
else
  check_replication_status "$PEER_NAME" "$LOCAL_DB_HOST" "$LOCAL_DB_PORT" "$LOCAL_SERVER_ID" "$PEER_STATUS"
fi

# Santé du conteneur local, sans lecture des logs applicatifs.
container_details=""
if docker inspect "$VAULTWARDEN_CONTAINER" >/dev/null 2>&1; then
  c_status="$(docker inspect -f '{{.State.Status}}' "$VAULTWARDEN_CONTAINER")"
  c_health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$VAULTWARDEN_CONTAINER")"
  c_started="$(docker inspect -f '{{.State.StartedAt}}' "$VAULTWARDEN_CONTAINER")"
  c_restarts="$(docker inspect -f '{{.RestartCount}}' "$VAULTWARDEN_CONTAINER")"
  prev_restarts_file="$STATE_DIR/restart_count"
  prev_restarts="$(cat "$prev_restarts_file" 2>/dev/null || echo "$c_restarts")"
  printf '%s\n' "$c_restarts" >"$prev_restarts_file"
  restart_delta=$(( c_restarts - prev_restarts ))
  (( restart_delta < 0 )) && restart_delta=0

  container_details="Status=$c_status Health=$c_health StartedAt=$c_started RestartCount=$c_restarts DeltaRestart=$restart_delta"

  if [[ "$c_status" == "exited" || "$c_status" == "dead" ]]; then
    add_critical "$NODE_NAME: Vaultwarden arrêté" "$container_details"
  fi

  if [[ "$c_status" == "restarting" ]]; then
    add_critical "$NODE_NAME: Vaultwarden redémarre en boucle" "$container_details"
  fi
  if [[ "$c_health" == "unhealthy" ]]; then
    add_critical "$NODE_NAME: Vaultwarden unhealthy" "$container_details"
  fi
  if (( restart_delta >= RESTART_DELTA_CRITICAL )); then
    add_critical "$NODE_NAME: redémarrages Docker répétés" "$container_details"
  fi
  if [[ "$c_health" == "starting" ]]; then
    started_epoch="$(date -d "$c_started" +%s 2>/dev/null || echo 0)"
    now_epoch="$(date +%s)"
    if (( started_epoch > 0 && now_epoch - started_epoch > CONTAINER_STARTING_MAX_SECONDS )); then
      add_critical "$NODE_NAME: Vaultwarden reste en démarrage" "$container_details"
    fi
  fi
else
  add_critical "$NODE_NAME: conteneur Vaultwarden introuvable" "Nom attendu: $VAULTWARDEN_CONTAINER"
fi

incident_file="$STATE_DIR/incident.active"
last_reminder_file="$STATE_DIR/last_reminder_date"
failure_count_file="$STATE_DIR/critical_failure_count"
stopped_marker="$STATE_DIR/vaultwarden_stopped_by_monitor"

if (( ${#CRITICALS[@]} > 0 )); then
  failures="$(cat "$failure_count_file" 2>/dev/null || echo 0)"
  failures=$((failures + 1))
  printf '%s\n' "$failures" >"$failure_count_file"
else
  printf '0\n' >"$failure_count_file"
  failures=0
fi

safety_action="Aucune"
if [[ "$NODE_ROLE" == "slave" && "$ALLOW_SAFETY_STOP" == "1" && ${#CRITICALS[@]} -gt 0 ]]; then
  immediate=0
  for p in "${CRITICALS[@]}"; do
    [[ "$p" == *"erreur IO"* || "$p" == *"erreur SQL"* ]] && immediate=1
  done
  if (( immediate == 1 || failures >= FAILURES_BEFORE_STOP )); then
    if docker inspect -f '{{.State.Running}}' "$VAULTWARDEN_CONTAINER" 2>/dev/null | grep -qx true; then
      if docker stop "$VAULTWARDEN_CONTAINER" >/dev/null; then
        touch "$stopped_marker"
        safety_action="Conteneur $VAULTWARDEN_CONTAINER arrêté automatiquement sur $NODE_NAME"
        log_line ERROR "$safety_action"
      else
        safety_action="ÉCHEC de l'arrêt automatique du conteneur"
      fi
    else
      safety_action="Conteneur déjà arrêté"
    fi
  else
    safety_action="Arrêt différé: échec critique $failures/$FAILURES_BEFORE_STOP"
  fi
fi

build_body() {
  local title="$1"
  {
    printf '%s\n\n' "$title"
    printf 'Date : %s\n' "$(now_iso)"
    printf 'Contrôle exécuté par : %s\n' "$NODE_NAME"
    printf 'Pair contrôlé : %s (%s:%s)\n' "$PEER_NAME" "$PEER_HOST" "$PEER_PORT"
    printf 'Action de sécurité : %s\n\n' "$safety_action"

    printf 'Problèmes détectés :\n'
    local i
    for ((i=0; i<${#PROBLEMS[@]}; i++)); do
      printf -- '- %s\n  Détail: %s\n' "${PROBLEMS[$i]}" "${DETAILS[$i]:-}"
    done

    printf '\nÉtat de réplication local :\n'
    if [[ -n "$LOCAL_STATUS" ]]; then status_summary "$NODE_NAME" "$LOCAL_STATUS"; else printf 'Indisponible\n'; fi
    printf '\nÉtat de réplication du pair :\n'
    if [[ -n "$PEER_STATUS" ]]; then status_summary "$PEER_NAME" "$PEER_STATUS"; else printf 'Indisponible\n'; fi
    printf '\nÉtat du conteneur local :\n%s\n' "${container_details:-Indisponible}"

    if (( ${#RECOMMENDATIONS[@]} > 0 )); then
      printf '\nActions conseillées :\n'
      printf -- '- %s\n' "${RECOMMENDATIONS[@]}"
    fi
  }
}

current_date="$(TZ="$TIMEZONE" date +%F)"
current_hour="$(TZ="$TIMEZONE" date +%H)"
current_hour=$((10#$current_hour))

if (( ${#PROBLEMS[@]} > 0 )) || [[ "$MODE" == "--force-alert" ]]; then
  if [[ ! -e "$incident_file" ]]; then
    printf '%s\n' "$(date +%s)" >"$incident_file"
    # Le mail initial compte comme notification du jour afin d'éviter un
    # rappel cinq minutes plus tard lorsque l'incident commence après 09:00.
    printf '%s\n' "$current_date" >"$last_reminder_file"
    body="$(build_body "Un incident de réplication ou de santé Vaultwarden a été détecté.")"
    send_mail "[ALERTE][$NODE_NAME] Vaultwarden / réplication" "$body"
    log_line ERROR "Incident détecté; mail initial envoyé"
  else
    last_reminder="$(cat "$last_reminder_file" 2>/dev/null || true)"
    if (( current_hour >= REMINDER_HOUR )) && [[ "$last_reminder" != "$current_date" ]]; then
      body="$(build_body "Rappel : l'incident Vaultwarden est toujours en cours.")"
      send_mail "[RAPPEL][$NODE_NAME] Incident Vaultwarden toujours actif" "$body"
      printf '%s\n' "$current_date" >"$last_reminder_file"
      log_line WARN "Rappel quotidien envoyé"
    else
      log_line WARN "Incident toujours actif; aucun nouveau mail"
    fi
  fi
  exit 2
fi

if [[ -e "$incident_file" ]]; then
  started_epoch="$(cat "$incident_file" 2>/dev/null || date +%s)"
  duration=$(( $(date +%s) - started_epoch ))
  send_mail "[RÉTABLI][$NODE_NAME] Vaultwarden / réplication" \
"L'incident est rétabli.

Date : $(now_iso)
Contrôle exécuté par : $NODE_NAME
Durée approximative : ${duration} secondes
État local : réplication saine
État du pair : réplication saine
État du conteneur local : ${container_details:-indisponible}

Le conteneur arrêté automatiquement sur le slave n'est jamais redémarré par ce script."
  rm -f "$incident_file" "$last_reminder_file"
  log_line INFO "Incident rétabli; mail envoyé"
else
  log_line INFO "Réplication et conteneur sains"
fi
