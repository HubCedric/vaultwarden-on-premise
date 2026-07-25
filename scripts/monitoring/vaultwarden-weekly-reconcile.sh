#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
load_env
require_vars NODE_NAME RECONCILE_SCRIPT RECONCILE_OUTPUT_DIR STATE_DIR LOG_FILE \
  MAINTENANCE_FILE MAIL_FROM MAIL_TO
safe_mkdirs

[[ -e "$MAINTENANCE_FILE" ]] && { log_line INFO "Mode maintenance actif; réconciliation ignorée"; exit 0; }
[[ -x "$RECONCILE_SCRIPT" ]] || {
  send_mail "[ALERTE][$NODE_NAME] Réconciliation hebdomadaire impossible" \
"Le script n'est pas exécutable ou absent : $RECONCILE_SCRIPT"
  exit 2
}

run_dir="$RECONCILE_OUTPUT_DIR/$(date +%F-%H%M%S)"
mkdir -p "$run_dir"
output_file="$run_dir/execution.log"

set +e
"$RECONCILE_SCRIPT" "$run_dir" >"$output_file" 2>&1
rc=$?
set -e

report_file=""
for candidate in "$run_dir/report.txt" "$run_dir"/*/report.txt; do
  [[ -f "$candidate" ]] && { report_file="$candidate"; break; }
done

if (( rc != 0 )); then
  send_mail "[ALERTE][$NODE_NAME] Échec réconciliation hebdomadaire" \
"Le script reconcile_split_brain.sh a retourné le code $rc.

Sortie :
$(tail -n 200 "$output_file")"
  log_line ERROR "Réconciliation hebdomadaire en échec"
  exit 2
fi

if [[ -z "$report_file" ]]; then
  send_mail "[ALERTE][$NODE_NAME] Rapport de réconciliation absent" \
"Le script a réussi mais aucun report.txt n'a été trouvé dans $run_dir.

Sortie :
$(tail -n 200 "$output_file")"
  exit 2
fi

# Le rapport produit par reconcile_split_brain.sh contient des lignes du type :
# [users] vers master: 0 ligne(s) — vers slave: 0 ligne(s)
# On ne considère que ces compteurs, afin d'ignorer les dates ou identifiants.
if awk '
  /vers master:/ && /vers slave:/ {
    line=$0
    sub(/^.*vers master:[[:space:]]*/, "", line)
    master=line; sub(/[[:space:]].*$/, "", master)
    line=$0
    sub(/^.*vers slave:[[:space:]]*/, "", line)
    slave=line; sub(/[[:space:]].*$/, "", slave)
    if ((master + 0) != 0 || (slave + 0) != 0) found=1
  }
  END { exit(found ? 0 : 1) }
' "$report_file"; then
  send_mail "[ALERTE][$NODE_NAME] Différences lors de la réconciliation" \
"Le contrôle hebdomadaire sans --apply a trouvé des valeurs non nulles.

Rapport :
$(cat "$report_file")"
  log_line ERROR "Réconciliation: différences détectées"
  exit 2
fi

log_line INFO "Réconciliation hebdomadaire sans différence"
