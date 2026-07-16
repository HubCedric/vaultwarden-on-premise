#!/usr/bin/env bash
#
# Surveillance quotidienne (cron) de la réplication MariaDB master<->master
# entre srv1 et srv2, avec correction automatique limitée aux cas sûrs :
#
# - thread de réplication arrêté sans erreur de données -> redémarrage
#   automatique (STOP SLAVE / START SLAVE), plusieurs tentatives.
# - configuration de réplication perdue (SHOW SLAVE STATUS vide) mais
#   gtid_slave_pos non vide (ce nœud a déjà répliqué avant) -> reconfiguration
#   automatique (CHANGE MASTER TO ... MASTER_USE_GTID=slave_pos) qui repart
#   exactement de la dernière position connue.
#
# Jamais de correction automatique si :
# - gtid_slave_pos est vide (aucune position de reprise sûre connue) ;
# - un conflit de données est détecté (Last_SQL_Errno != 0) — le corriger
#   automatiquement (ex: sql_slave_skip_counter) risquerait de faire diverger
#   silencieusement les 2 bases d'une base de mots de passe.
#
# Ce script est identique sur srv1 et srv2 : seul .env change (NODE_NAME et
# le sens LOCAL/PEER sont inversés d'un nœud à l'autre).
#
# Usage : ./check_replication.sh   (pas d'argument, prévu pour tourner en cron)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Fichier .env introuvable ($ENV_FILE). Copiez .env.example vers .env et renseignez les valeurs." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

LOCK_FILE="/tmp/check_replication_${NODE_NAME}.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "Une exécution de check_replication.sh est déjà en cours pour ${NODE_NAME}, on quitte." >&2
  exit 0
fi

log() {
  local message="$1"
  local timestamp
  timestamp="$(date +"%Y-%m-%d %H:%M:%S")"
  echo "$timestamp - $message" | tee -a "$REPLICATION_LOG_FILE"
}

fail() {
  log "ERREUR: $1"
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Commande requise manquante: $1"
}

require_cmd mysql
require_cmd flock
[[ "${ENABLE_MAIL:-0}" -eq 1 ]] && require_cmd mail

mysql_local() {
  MYSQL_PWD="$MONITOR_PASSWORD" mysql -h "$LOCAL_DB_HOST" -P "$LOCAL_DB_PORT" -u "$MONITOR_USER" "$@"
}

mysql_peer() {
  MYSQL_PWD="$MONITOR_PASSWORD" mysql -h "$PEER_HOST" -P "$PEER_PORT" -u "$MONITOR_USER" "$@"
}

# Extrait la valeur d'un champ depuis la sortie verticale (\G) de SHOW SLAVE STATUS.
get_field() {
  local dump="$1" field="$2"
  echo "$dump" | grep -m1 -E "^[[:space:]]*${field}:" | sed -E "s/^[[:space:]]*${field}:[[:space:]]?//"
}

get_slave_status_local() {
  mysql_local -e "SHOW SLAVE STATUS\G" 2>>"$REPLICATION_LOG_FILE"
}

get_slave_status_peer() {
  mysql_peer -e "SHOW SLAVE STATUS\G" 2>>"$REPLICATION_LOG_FILE"
}

get_gtid_slave_pos_local() {
  mysql_local -N -e "SELECT @@global.gtid_slave_pos;" 2>>"$REPLICATION_LOG_FILE"
}

send_mail() {
  local subject="$1" body="$2"
  if ! printf '%s\n' "$body" | mail -s "$subject" "$MAIL_TO" 2>>"$REPLICATION_LOG_FILE"; then
    log "ATTENTION: échec de l'envoi de l'email d'alerte (MTA local absent/mal configuré ?)."
  fi
}

# Redémarrage sûr : uniquement si le thread est arrêté sans erreur de données.
attempt_restart() {
  local i status_dump io sql
  for ((i = 1; i <= RESTART_RETRY_COUNT; i++)); do
    log "Tentative de redémarrage du thread de réplication ($i/$RESTART_RETRY_COUNT)..."
    mysql_local -e "STOP SLAVE; START SLAVE;" 2>>"$REPLICATION_LOG_FILE"
    sleep "$RESTART_RETRY_DELAY"
    status_dump="$(get_slave_status_local)"
    io="$(get_field "$status_dump" "Slave_IO_Running")"
    sql="$(get_field "$status_dump" "Slave_SQL_Running")"
    if [[ "$io" == "Yes" && "$sql" == "Yes" ]]; then
      log "Redémarrage réussi après $i tentative(s)."
      return 0
    fi
  done
  return 1
}

# Reconfiguration uniquement si gtid_slave_pos prouve une activité antérieure :
# MASTER_USE_GTID=slave_pos repart alors exactement de cette position, jamais
# de "maintenant" qui risquerait de sauter des données. Le mot de passe de
# réplication n'est jamais loggé.
attempt_reconfigure() {
  log "Reconfiguration de la réplication (CHANGE MASTER TO ... MASTER_USE_GTID=slave_pos) depuis gtid_slave_pos existant."
  mysql_local -e "CHANGE MASTER TO MASTER_HOST='${PEER_HOST}', MASTER_PORT=${PEER_PORT}, MASTER_USER='${REPL_USER}', MASTER_PASSWORD='${REPL_PASSWORD}', MASTER_USE_GTID=slave_pos; START SLAVE;" 2>>"$REPLICATION_LOG_FILE"
  sleep "$RESTART_RETRY_DELAY"
  local status_dump io sql
  status_dump="$(get_slave_status_local)"
  io="$(get_field "$status_dump" "Slave_IO_Running")"
  sql="$(get_field "$status_dump" "Slave_SQL_Running")"
  [[ "$io" == "Yes" && "$sql" == "Yes" ]]
}

log "=== Vérification de la réplication ($NODE_NAME) ==="

EMAIL_SUBJECT=""
EMAIL_BODY=""
NEEDS_MAIL=0

LOCAL_STATUS="$(get_slave_status_local)"
LOCAL_STATUS_RC=$?

if [[ "$LOCAL_STATUS_RC" -ne 0 ]]; then
  fail "Impossible d'interroger la base locale (connexion MySQL échouée, code $LOCAL_STATUS_RC). Vérifiez MONITOR_USER/MONITOR_PASSWORD/LOCAL_DB_HOST/LOCAL_DB_PORT dans .env et le détail de l'erreur ci-dessus dans $REPLICATION_LOG_FILE. Il est impossible de conclure quoi que ce soit sur l'état de la réplication tant que cette connexion ne fonctionne pas — ce n'est pas la même chose qu'une réplication non configurée."
fi

if [[ -z "$LOCAL_STATUS" ]]; then
  log "SHOW SLAVE STATUS ne retourne aucune ligne : réplication non configurée sur ce nœud."
  GTID_POS="$(get_gtid_slave_pos_local)"

  if [[ -n "$GTID_POS" ]]; then
    log "gtid_slave_pos non vide ($GTID_POS) : ce nœud a déjà répliqué avant, reconfiguration automatique."
    if attempt_reconfigure; then
      log "Reconfiguration automatique réussie."
      NEEDS_MAIL=1
      EMAIL_SUBJECT="[$NODE_NAME] Réplication reconfigurée automatiquement"
      EMAIL_BODY="$(printf "La réplication avait perdu sa configuration (SHOW SLAVE STATUS vide) mais gtid_slave_pos (%s) prouvait une activité antérieure.\n\nReconfiguration automatique effectuée depuis cette position exacte, réplication à nouveau active." "$GTID_POS")"
    else
      log "Échec de la reconfiguration automatique."
      NEEDS_MAIL=1
      EMAIL_SUBJECT="[$NODE_NAME] ÉCHEC reconfiguration automatique de la réplication"
      EMAIL_BODY="$(printf "SHOW SLAVE STATUS était vide, gtid_slave_pos (%s) indiquait une reprise possible, mais la reconfiguration automatique (CHANGE MASTER TO + START SLAVE) a échoué.\n\nIntervention manuelle requise. Voir %s." "$GTID_POS" "$REPLICATION_LOG_FILE")"
    fi
  else
    log "gtid_slave_pos vide : réplication jamais initialisée (ou remise à zéro totale). Aucune action automatique."
    NEEDS_MAIL=1
    EMAIL_SUBJECT="[$NODE_NAME] Réplication non initialisée"
    EMAIL_BODY="SHOW SLAVE STATUS est vide et gtid_slave_pos est vide : il n'y a aucune position de reprise sûre, donc aucune action automatique. Mise en place manuelle nécessaire (voir README, section Mise en place du cluster)."
  fi
else
  IO_RUNNING="$(get_field "$LOCAL_STATUS" "Slave_IO_Running")"
  SQL_RUNNING="$(get_field "$LOCAL_STATUS" "Slave_SQL_Running")"
  SECONDS_BEHIND="$(get_field "$LOCAL_STATUS" "Seconds_Behind_Master")"
  SQL_ERRNO="$(get_field "$LOCAL_STATUS" "Last_SQL_Errno")"
  SQL_ERROR="$(get_field "$LOCAL_STATUS" "Last_SQL_Error")"
  IO_ERRNO="$(get_field "$LOCAL_STATUS" "Last_IO_Errno")"
  IO_ERROR="$(get_field "$LOCAL_STATUS" "Last_IO_Error")"

  if [[ "$IO_RUNNING" == "Yes" && "$SQL_RUNNING" == "Yes" ]]; then
    if [[ "$SECONDS_BEHIND" =~ ^[0-9]+$ ]] && ((SECONDS_BEHIND > SECONDS_BEHIND_THRESHOLD)); then
      log "Réplication active mais retard de ${SECONDS_BEHIND}s (seuil: ${SECONDS_BEHIND_THRESHOLD}s)."
      NEEDS_MAIL=1
      EMAIL_SUBJECT="[$NODE_NAME] Retard de réplication (${SECONDS_BEHIND}s)"
      EMAIL_BODY="$(printf "Les threads de réplication tournent normalement mais accusent un retard de %ss (seuil configuré: %ss).\n\nCe n'est pas une panne : pas d'action automatique. À surveiller si le retard persiste ou augmente." "$SECONDS_BEHIND" "$SECONDS_BEHIND_THRESHOLD")"
    else
      log "Réplication saine (IO: $IO_RUNNING, SQL: $SQL_RUNNING, retard: ${SECONDS_BEHIND:-0}s)."
    fi
  else
    log "Thread de réplication arrêté (IO: $IO_RUNNING, SQL: $SQL_RUNNING)."

    if [[ -n "$SQL_ERRNO" && "$SQL_ERRNO" != "0" ]]; then
      log "Erreur SQL détectée (errno $SQL_ERRNO) : $SQL_ERROR"
      NEEDS_MAIL=1
      EMAIL_SUBJECT="[$NODE_NAME] Conflit de données sur la réplication (errno $SQL_ERRNO)"
      EMAIL_BODY="$(printf "Le thread SQL s'est arrêté sur une erreur de données (probable conflit d'écriture) :\n\nerrno: %s\n%s\n\nAucune correction automatique n'est tentée dans ce cas (risque de divergence silencieuse entre les 2 bases). Intervention manuelle requise : examiner l'incohérence avant de relancer la réplication." "$SQL_ERRNO" "$SQL_ERROR")"
    else
      log "Pas d'erreur de données (IO errno: ${IO_ERRNO:-aucun}), tentative de redémarrage sûr."
      if attempt_restart; then
        NEEDS_MAIL=1
        EMAIL_SUBJECT="[$NODE_NAME] Réplication interrompue puis rétablie automatiquement"
        EMAIL_BODY="$(printf "Le thread de réplication était arrêté (IO: %s, SQL: %s, dernière erreur IO: %s).\n\nRedémarrage automatique (STOP SLAVE / START SLAVE) réussi, réplication à nouveau active." "$IO_RUNNING" "$SQL_RUNNING" "${IO_ERROR:-aucune}")"
      else
        NEEDS_MAIL=1
        EMAIL_SUBJECT="[$NODE_NAME] ÉCHEC du redémarrage automatique de la réplication"
        EMAIL_BODY="$(printf "Le thread de réplication était arrêté et n'a pas pu être rétabli après %s tentative(s).\n\nIO: %s (errno: %s - %s)\nSQL: %s\n\nIntervention manuelle requise. Voir %s." "$RESTART_RETRY_COUNT" "$IO_RUNNING" "${IO_ERRNO:-aucun}" "${IO_ERROR:-aucune}" "$SQL_RUNNING" "$REPLICATION_LOG_FILE")"
      fi
    fi
  fi
fi

# Le pair est toujours interrogé (en lecture seule), sur chaque exécution,
# pas seulement en cas d'alerte : le but est bien de vérifier les 2 bases
# (locale + pair) à chaque passage, pas uniquement le nœud sur lequel le
# cron tourne.
PEER_STATUS="$(get_slave_status_peer)"
if [[ -z "$PEER_STATUS" ]]; then
  PEER_SUMMARY="Statut du pair ($PEER_HOST) : injoignable, ou réplication non configurée sur ce nœud."
else
  PEER_IO="$(get_field "$PEER_STATUS" "Slave_IO_Running")"
  PEER_SQL="$(get_field "$PEER_STATUS" "Slave_SQL_Running")"
  PEER_LAG="$(get_field "$PEER_STATUS" "Seconds_Behind_Master")"
  PEER_SUMMARY="$(printf "Statut du pair (%s) : IO=%s, SQL=%s, retard=%ss." "$PEER_HOST" "$PEER_IO" "$PEER_SQL" "${PEER_LAG:-inconnu}")"
fi
log "$PEER_SUMMARY"

if [[ "$NEEDS_MAIL" -eq 1 ]]; then
  log "Résumé de l'alerte [$EMAIL_SUBJECT] : $EMAIL_BODY"

  if [[ "${ENABLE_MAIL:-0}" -eq 1 ]]; then
    send_mail "$EMAIL_SUBJECT" "$(printf '%s\n\n%s' "$EMAIL_BODY" "$PEER_SUMMARY")"
  else
    log "Envoi d'email désactivé (ENABLE_MAIL=0) : alerte journalisée uniquement, voir ci-dessus."
  fi
fi

log "=== Fin de la vérification ($NODE_NAME) ==="
exit 0
