#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

load_env

require_vars \
  NODE_NAME \
  NODE_ROLE \
  RECONCILE_SCRIPT \
  RECONCILE_OUTPUT_DIR \
  STATE_DIR \
  LOG_FILE \
  MAINTENANCE_FILE \
  MAIL_FROM \
  MAIL_TO \
  VAULTWARDEN_CONTAINER \
  ALLOW_SAFETY_STOP

safe_mkdirs

CONFIRMATION_DELAY_SECONDS="${RECONCILE_CONFIRMATION_DELAY_SECONDS:-300}"

if [[ -e "$MAINTENANCE_FILE" ]]; then
  log_line INFO "Mode maintenance actif; réconciliation ignorée"
  exit 0
fi

if [[ ! -x "$RECONCILE_SCRIPT" ]]; then
  send_mail \
    "[ALERTE][$NODE_NAME] Réconciliation quotidienne impossible" \
    "Le script est absent ou non exécutable :

$RECONCILE_SCRIPT

Date : $(now_iso)
Nœud : $NODE_NAME

Aucun arrêt automatique de Vaultwarden n'a été effectué,
car une erreur du script ne prouve pas une divergence des bases."

  log_line ERROR "Script de réconciliation absent ou non exécutable"
  exit 2
fi

report_has_differences() {
  local report_file="$1"

  grep -Eq \
    'vers (master|slave):[[:space:]]*[1-9][0-9]*[[:space:]]+(ligne|paire)\(s\)' \
    "$report_file"
}

find_report_file() {
  local run_dir="$1"

  find "$run_dir" \
    -type f \
    -name report.txt \
    -print \
    -quit
}

run_reconciliation() {
  local run_dir="$1"
  local output_file="$run_dir/execution.log"

  mkdir -p "$run_dir"

  set +e
  "$RECONCILE_SCRIPT" "$run_dir" >"$output_file" 2>&1
  local rc=$?
  set -e

  if (( rc != 0 )); then
    printf 'ERROR_RC=%s\n' "$rc"
    return 1
  fi

  local report_file
  report_file="$(find_report_file "$run_dir")"

  if [[ -z "$report_file" || ! -f "$report_file" ]]; then
    printf 'ERROR_REPORT_ABSENT\n'
    return 2
  fi

  printf '%s\n' "$report_file"
}

base_timestamp="$(date +%F-%H%M%S)"
first_run_dir="$RECONCILE_OUTPUT_DIR/${base_timestamp}-first"

first_result=""
if ! first_result="$(run_reconciliation "$first_run_dir")"; then
  rc=$?

  send_mail \
    "[ALERTE][$NODE_NAME] Échec de la première réconciliation" \
    "La première vérification quotidienne n'a pas pu être exécutée correctement.

Date : $(now_iso)
Nœud : $NODE_NAME
Résultat interne : $first_result
Dossier : $first_run_dir

Sortie :
$(tail -n 200 "$first_run_dir/execution.log" 2>/dev/null || true)

Aucun arrêt automatique de Vaultwarden n'a été effectué,
car cette erreur ne confirme pas une divergence des bases."

  log_line ERROR "Première réconciliation impossible, code interne=$rc"
  exit 2
fi

first_report="$first_result"

if ! report_has_differences "$first_report"; then
  log_line INFO "Réconciliation quotidienne sans différence"
  exit 0
fi

log_line WARN \
  "Différence détectée au premier contrôle; confirmation dans ${CONFIRMATION_DELAY_SECONDS}s"

sleep "$CONFIRMATION_DELAY_SECONDS"

second_timestamp="$(date +%F-%H%M%S)"
second_run_dir="$RECONCILE_OUTPUT_DIR/${second_timestamp}-confirmation"

second_result=""
if ! second_result="$(run_reconciliation "$second_run_dir")"; then
  rc=$?

  send_mail \
    "[ALERTE][$NODE_NAME] Confirmation de réconciliation impossible" \
    "Une différence avait été détectée lors du premier contrôle,
mais le contrôle de confirmation a échoué.

Date : $(now_iso)
Nœud : $NODE_NAME
Résultat interne : $second_result
Premier rapport : $first_report
Dossier de confirmation : $second_run_dir

Premier rapport :
$(cat "$first_report")

Sortie du second contrôle :
$(tail -n 200 "$second_run_dir/execution.log" 2>/dev/null || true)

Vaultwarden n'a pas été arrêté automatiquement,
car la divergence n'a pas pu être confirmée."

  log_line ERROR "Contrôle de confirmation impossible, code interne=$rc"
  exit 2
fi

second_report="$second_result"

if ! report_has_differences "$second_report"; then
  log_line INFO \
    "Différence transitoire disparue lors du contrôle de confirmation; aucun arrêt"
  exit 0
fi

safety_action="Aucun arrêt automatique effectué"

if [[ "$NODE_ROLE" == "slave" && "$ALLOW_SAFETY_STOP" == "1" ]]; then
  if docker inspect "$VAULTWARDEN_CONTAINER" >/dev/null 2>&1; then
    container_running="$(
      docker inspect \
        -f '{{.State.Running}}' \
        "$VAULTWARDEN_CONTAINER" 2>/dev/null || echo false
    )"

    if [[ "$container_running" == "true" ]]; then
      if docker stop "$VAULTWARDEN_CONTAINER" >/dev/null; then
        safety_action="Le conteneur $VAULTWARDEN_CONTAINER a été arrêté automatiquement sur $NODE_NAME"
        log_line ERROR "$safety_action"
      else
        safety_action="ÉCHEC de l'arrêt automatique du conteneur $VAULTWARDEN_CONTAINER"
        log_line ERROR "$safety_action"
      fi
    else
      safety_action="Le conteneur $VAULTWARDEN_CONTAINER était déjà arrêté sur $NODE_NAME"
      log_line WARN "$safety_action"
    fi
  else
    safety_action="Le conteneur $VAULTWARDEN_CONTAINER est introuvable sur $NODE_NAME"
    log_line ERROR "$safety_action"
  fi
else
  safety_action="Arrêt interdit : NODE_ROLE=$NODE_ROLE, ALLOW_SAFETY_STOP=$ALLOW_SAFETY_STOP"
  log_line ERROR "$safety_action"
fi

send_mail \
  "[CRITIQUE][$NODE_NAME] Divergence Vaultwarden confirmée" \
  "Une divergence entre les deux bases a été détectée deux fois
à ${CONFIRMATION_DELAY_SECONDS} secondes d'intervalle.

Date : $(now_iso)
Nœud ayant exécuté le contrôle : $NODE_NAME
Action de sécurité : $safety_action

================ PREMIER RAPPORT ================

$(cat "$first_report")

================ RAPPORT DE CONFIRMATION ================

$(cat "$second_report")

=========================================================

Vaultwarden ne sera jamais redémarré automatiquement.

Avant toute remise en service :
1. activer le mode maintenance ;
2. vérifier SHOW SLAVE STATUS sur les deux nœuds ;
3. analyser les fichiers SQL produits ;
4. choisir explicitement la base de référence ;
5. réconcilier ou reconstruire le nœud divergent ;
6. contrôler à nouveau les deux bases ;
7. seulement ensuite redémarrer Vaultwarden sur le slave."

log_line ERROR \
  "Divergence confirmée sur deux contrôles; action=$safety_action"

exit 2
