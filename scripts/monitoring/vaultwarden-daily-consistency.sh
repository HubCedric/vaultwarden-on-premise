#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
load_env
require_vars NODE_NAME LOCAL_DB_HOST LOCAL_DB_PORT PEER_NAME PEER_HOST PEER_PORT \
  MONITOR_USER MONITOR_PASSWORD VAULTWARDEN_DB COUNT_TABLES STATE_DIR LOG_FILE \
  MAINTENANCE_FILE MAIL_FROM MAIL_TO
safe_mkdirs

[[ -e "$MAINTENANCE_FILE" ]] && { log_line INFO "Mode maintenance actif; contrôle quotidien ignoré"; exit 0; }

problems=()
report="Contrôle quotidien des compteurs
Date : $(now_iso)
Exécuté par : $NODE_NAME

"

for table in $COUNT_TABLES; do
  local_count="$(mysql_cmd "$LOCAL_DB_HOST" "$LOCAL_DB_PORT" --skip-column-names \
    --execute="SELECT COUNT(*) FROM \`${VAULTWARDEN_DB}\`.\`${table}\`;" 2>&1)" || {
      problems+=("$NODE_NAME/$table inaccessible: $local_count"); continue; }
  peer_count="$(mysql_cmd "$PEER_HOST" "$PEER_PORT" --skip-column-names \
    --execute="SELECT COUNT(*) FROM \`${VAULTWARDEN_DB}\`.\`${table}\`;" 2>&1)" || {
      problems+=("$PEER_NAME/$table inaccessible: $peer_count"); continue; }

  report+=$(printf '%-24s local=%-10s pair=%-10s\n' "$table" "$local_count" "$peer_count")
  [[ "$local_count" == "$peer_count" ]] || problems+=("$table: $NODE_NAME=$local_count, $PEER_NAME=$peer_count")
done

if (( ${#problems[@]} > 0 )); then
  report+="
Différences ou erreurs :
"
  for p in "${problems[@]}"; do report+="- $p"$'\n'; done
  send_mail "[ALERTE][$NODE_NAME] Cohérence quotidienne Vaultwarden" "$report"
  log_line ERROR "Contrôle quotidien en anomalie"
  exit 2
fi

log_line INFO "Contrôle quotidien des compteurs réussi"

