#!/usr/bin/env bash
#
# Mise à jour semi-automatique de Vaultwarden (docker-compose) avec :
# - backup de la base avant toute action
# - vérification préventive du charset/collation (voir issue vaultwarden #7182)
# - contrôle du healthcheck / des logs après mise à jour
# - rollback automatique vers l'ancienne version en cas d'échec
#
# Usage: ./update_vaultwarden.sh <version> [--fix-collation] [--fix-uuid-columns]
#   ex : ./update_vaultwarden.sh 1.36.0
#   ex : ./update_vaultwarden.sh 1.36.0 --fix-collation --fix-uuid-columns
#
# --fix-collation : si le charset/collation de la base est incorrect, propose
#   (avec confirmation explicite) de le corriger automatiquement avant de
#   poursuivre la mise à jour. Sans ce flag, le script s'arrête et laisse la
#   correction manuelle.
#
# --fix-uuid-columns : si des colonnes uuid/id/*_uuid sont encore en TEXT
#   (résidu de la conversion SQLite -> MySQL, cf. .claude/known_errors.md),
#   propose (avec confirmation explicite) de les convertir en VARCHAR(36)
#   avant de poursuivre — c'est ce type de colonne qui bloque, une par une à
#   chaque montée de version, la création de nouvelles clés étrangères
#   (déjà vu sur users.uuid puis ciphers.uuid). Sans ce flag, le script
#   s'arrête et liste les colonnes concernées sans y toucher.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Fichier .env introuvable ($ENV_FILE). Copiez .env.example vers .env et renseignez les valeurs." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

NEW_VERSION=""
FIX_COLLATION=0
FIX_UUID_COLUMNS=0
for arg in "$@"; do
  case "$arg" in
    --fix-collation) FIX_COLLATION=1 ;;
    --fix-uuid-columns) FIX_UUID_COLUMNS=1 ;;
    -*)
      echo "Option inconnue: $arg" >&2
      exit 1
      ;;
    *) NEW_VERSION="$arg" ;;
  esac
done

if [[ -z "$NEW_VERSION" ]]; then
  echo "Usage: $0 <version> [--fix-collation] [--fix-uuid-columns]   (ex: $0 1.36.0 --fix-collation --fix-uuid-columns)" >&2
  exit 1
fi

COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"

log() {
  local message="$1"
  local timestamp
  timestamp="$(date +"%Y-%m-%d %H:%M:%S")"
  echo "$timestamp - $message" | tee -a "$LOG_FILE"
}

fail() {
  log "ERREUR: $1"
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Commande requise manquante: $1"
}

require_cmd docker
require_cmd docker-compose
require_cmd mysql
require_cmd mysqldump

# Corrige le charset/collation de la base et de toutes ses tables vers
# utf8mb4 / utf8mb4_unicode_ci (cf. issue vaultwarden #7182). Demande une
# confirmation explicite avant toute modification, backup déjà disponible.
#
# MySQL (contrairement à MariaDB) refuse de modifier la collation d'une
# colonne référencée par une clé étrangère, même avec foreign_key_checks=0
# (ERROR 1833). Les clés étrangères sont donc supprimées avant la conversion
# des tables, puis recréées à l'identique (mêmes colonnes, ON DELETE/UPDATE)
# une fois la conversion terminée. Toute la génération de SQL (y compris les
# noms entre backticks) est faite côté serveur via CONCAT, jamais par
# manipulation de chaînes côté bash.
fix_collation() {
  local fk_drop_statements fk_add_statements alter_statements fk_count

  fk_drop_statements="$(MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -u "$DB_USER" -N -e \
    "SELECT CONCAT('ALTER TABLE \`', TABLE_NAME, '\` DROP FOREIGN KEY \`', CONSTRAINT_NAME, '\`;') FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_SCHEMA='${DB_NAME}' AND CONSTRAINT_TYPE='FOREIGN KEY';" 2>/dev/null)"

  fk_add_statements="$(MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -u "$DB_USER" -N -e \
    "SELECT CONCAT('ALTER TABLE \`', kcu.TABLE_NAME, '\` ADD CONSTRAINT \`', kcu.CONSTRAINT_NAME, '\` FOREIGN KEY (\`', GROUP_CONCAT(kcu.COLUMN_NAME ORDER BY kcu.ORDINAL_POSITION SEPARATOR '\`,\`'), '\`) REFERENCES \`', kcu.REFERENCED_TABLE_NAME, '\` (\`', GROUP_CONCAT(kcu.REFERENCED_COLUMN_NAME ORDER BY kcu.ORDINAL_POSITION SEPARATOR '\`,\`'), '\`) ON DELETE ', rc.DELETE_RULE, ' ON UPDATE ', rc.UPDATE_RULE, ';') FROM information_schema.KEY_COLUMN_USAGE kcu JOIN information_schema.REFERENTIAL_CONSTRAINTS rc ON rc.CONSTRAINT_SCHEMA=kcu.CONSTRAINT_SCHEMA AND rc.CONSTRAINT_NAME=kcu.CONSTRAINT_NAME AND rc.TABLE_NAME=kcu.TABLE_NAME WHERE kcu.CONSTRAINT_SCHEMA='${DB_NAME}' AND kcu.REFERENCED_TABLE_NAME IS NOT NULL GROUP BY kcu.TABLE_NAME, kcu.CONSTRAINT_NAME, kcu.REFERENCED_TABLE_NAME, rc.DELETE_RULE, rc.UPDATE_RULE;" 2>/dev/null)"

  alter_statements="$(MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -u "$DB_USER" -N -e \
    "SELECT CONCAT('ALTER TABLE \`', TABLE_NAME, '\` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;') FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='${DB_NAME}' AND TABLE_TYPE='BASE TABLE';" 2>/dev/null)"

  if [[ -z "$alter_statements" ]]; then
    fail "Impossible de générer la liste des tables à convertir. Mise à jour annulée."
  fi

  fk_count=0
  [[ -n "$fk_drop_statements" ]] && fk_count="$(echo "$fk_drop_statements" | wc -l)"

  echo
  echo "Les commandes suivantes vont être exécutées sur la base '${DB_NAME}' :"
  echo "  ALTER DATABASE \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  echo "  + suppression temporaire de ${fk_count} clé(s) étrangère(s) (nécessaire sous MySQL pour convertir les colonnes référencées)"
  echo "  + un ALTER TABLE ... CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; pour chaque table"
  echo "  + recréation à l'identique des ${fk_count} clé(s) étrangère(s) supprimée(s)"
  echo "Backup disponible en cas de souci : $BACKUP_FILE"
  read -r -p "Confirmer l'application de cette correction ? [y/N] " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    fail "Correction annulée par l'utilisateur. Mise à jour annulée."
  fi

  log "Correction de la collation en cours..."
  if ! MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -u "$DB_USER" -e \
    "ALTER DATABASE \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>>"$LOG_FILE"; then
    fail "Échec de l'ALTER DATABASE. Mise à jour annulée (backup disponible: $BACKUP_FILE)."
  fi

  log "Suppression temporaire de ${fk_count} clé(s) étrangère(s), conversion des tables, puis recréation des clés étrangères..."
  if ! MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -u "$DB_USER" "$DB_NAME" 2>>"$LOG_FILE" <<SQL
SET foreign_key_checks=0;
${fk_drop_statements}
${alter_statements}
${fk_add_statements}
SET foreign_key_checks=1;
SQL
  then
    fail "Échec de l'application de la correction. Base potentiellement dans un état intermédiaire (ex: clé étrangère non recréée) : restaurez le backup si besoin ($BACKUP_FILE). Mise à jour annulée."
  fi

  BAD_TABLES="$(MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -u "$DB_USER" -N -e \
    "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA='${DB_NAME}' AND TABLE_TYPE='BASE TABLE' AND TABLE_COLLATION != 'utf8mb4_unicode_ci';" 2>/dev/null)"
  MISSING_FK_COUNT=0
  if [[ -n "$fk_drop_statements" ]]; then
    MISSING_FK_COUNT="$(MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -u "$DB_USER" -N -e \
      "SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_SCHEMA='${DB_NAME}' AND CONSTRAINT_TYPE='FOREIGN KEY';" 2>/dev/null)"
  fi

  if [[ -n "$BAD_TABLES" ]]; then
    fail "La correction n'a pas suffi, tables toujours en collation incorrecte : $(echo "$BAD_TABLES" | tr '\n' ' ' | sed 's/ *$//'). Intervention manuelle nécessaire. Mise à jour annulée."
  fi
  if [[ -n "$fk_drop_statements" && "${MISSING_FK_COUNT:-0}" -lt "$fk_count" ]]; then
    fail "Certaines clés étrangères n'ont pas été recréées (${MISSING_FK_COUNT:-0}/${fk_count}). Intervention manuelle nécessaire, backup disponible: $BACKUP_FILE. Mise à jour annulée."
  fi

  log "Collation corrigée avec succès (utf8mb4_unicode_ci), ${fk_count} clé(s) étrangère(s) recréée(s)."
}

# Convertit en VARCHAR(36) toutes les colonnes uuid/id/*_uuid encore en TEXT
# (cf. .claude/known_errors.md). Reconstruit les index (clé primaire,
# unique, secondaire) qui portaient un préfixe sur ces colonnes. Une colonne
# n'est convertie que si 100% de ses valeurs non nulles font exactement 36
# caractères ; sinon elle est ignorée et signalée, jamais tronquée. Testé
# contre PK simple préfixée, PK composite, index secondaire et index
# unique préfixés (voir known_errors.md pour le détail du test).
fix_uuid_columns() {
  local candidates safe_list skipped_list tbl col nullable bad tables

  candidates="$(MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -u "$DB_USER" -N -e \
    "SELECT CONCAT(TABLE_NAME,'|',COLUMN_NAME,'|',IS_NULLABLE) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='${DB_NAME}' AND DATA_TYPE='text' AND (COLUMN_NAME='uuid' OR COLUMN_NAME='id' OR RIGHT(COLUMN_NAME,5)='_uuid') ORDER BY TABLE_NAME, COLUMN_NAME;" 2>/dev/null)"

  if [[ -z "$candidates" ]]; then
    log "Aucune colonne uuid/id candidate trouvée."
    return 0
  fi

  safe_list=""
  skipped_list=""

  while IFS='|' read -r tbl col nullable; do
    [[ -z "$tbl" ]] && continue
    bad="$(MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -u "$DB_USER" -N -e \
      "SELECT COUNT(*) FROM \`${tbl}\` WHERE \`${col}\` IS NOT NULL AND LENGTH(\`${col}\`) <> 36;" 2>/dev/null)"
    if [[ "${bad:-0}" -eq 0 ]]; then
      safe_list+="${tbl}|${col}|${nullable}"$'\n'
    else
      skipped_list+="${tbl}.${col} (${bad} valeur(s) non conforme(s))"$'\n'
    fi
  done <<< "$candidates"

  if [[ -n "$skipped_list" ]]; then
    log "Colonnes ignorées (longueur != 36, non touchées, à examiner manuellement) :"
    echo "$skipped_list" | tee -a "$LOG_FILE"
  fi

  if [[ -z "$safe_list" ]]; then
    log "Aucune colonne uuid/id ne peut être convertie en sécurité."
    return 0
  fi

  tables="$(echo "$safe_list" | cut -d'|' -f1 | sort -u)"

  local -a table_names alter_statements summary_lines

  for tbl in $tables; do
    local cols_for_table col_in_list affected_indexes drop_clauses add_clauses modify_clauses
    local idx idx_info non_unique idx_cols idx_cols_bt t c n full_stmt

    cols_for_table="$(echo "$safe_list" | awk -F'|' -v t="$tbl" '$1==t {print $2}')"
    col_in_list="$(echo "$cols_for_table" | sed "s/.*/'&'/" | paste -sd, -)"

    affected_indexes="$(MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -u "$DB_USER" -N -e \
      "SELECT DISTINCT INDEX_NAME FROM information_schema.STATISTICS WHERE TABLE_SCHEMA='${DB_NAME}' AND TABLE_NAME='${tbl}' AND COLUMN_NAME IN (${col_in_list});" 2>/dev/null)"

    drop_clauses=""
    add_clauses=""

    if [[ -n "$affected_indexes" ]]; then
      while read -r idx; do
        [[ -z "$idx" ]] && continue
        idx_info="$(MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -u "$DB_USER" -N -e \
          "SELECT CONCAT(NON_UNIQUE,'|',GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX SEPARATOR ',')) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA='${DB_NAME}' AND TABLE_NAME='${tbl}' AND INDEX_NAME='${idx}' GROUP BY NON_UNIQUE;" 2>/dev/null)"
        non_unique="${idx_info%%|*}"
        idx_cols="${idx_info#*|}"
        idx_cols_bt="\`$(echo "$idx_cols" | sed 's/,/`,`/g')\`"

        if [[ "$idx" == "PRIMARY" ]]; then
          drop_clauses+="DROP PRIMARY KEY, "
          add_clauses+="ADD PRIMARY KEY (${idx_cols_bt}), "
        else
          drop_clauses+="DROP INDEX \`${idx}\`, "
          if [[ "$non_unique" == "0" ]]; then
            add_clauses+="ADD UNIQUE INDEX \`${idx}\` (${idx_cols_bt}), "
          else
            add_clauses+="ADD INDEX \`${idx}\` (${idx_cols_bt}), "
          fi
        fi
      done <<< "$affected_indexes"
    fi

    modify_clauses=""
    while IFS='|' read -r t c n; do
      [[ "$t" == "$tbl" ]] || continue
      if [[ "$n" == "YES" ]]; then
        modify_clauses+="MODIFY COLUMN \`${c}\` VARCHAR(36) COLLATE utf8mb4_unicode_ci, "
      else
        modify_clauses+="MODIFY COLUMN \`${c}\` VARCHAR(36) COLLATE utf8mb4_unicode_ci NOT NULL, "
      fi
    done <<< "$safe_list"

    full_stmt="ALTER TABLE \`${tbl}\` ${drop_clauses}${modify_clauses}${add_clauses}"
    full_stmt="${full_stmt%, };"

    table_names+=("$tbl")
    alter_statements+=("$full_stmt")
    summary_lines+=("${tbl}: $(echo "$cols_for_table" | tr '\n' ' ' | sed 's/ *$//')")
  done

  echo
  echo "Plan de correction (${#table_names[@]} table(s)) :"
  for line in "${summary_lines[@]}"; do
    echo "  - $line"
  done
  echo
  echo "Instructions SQL exactes qui seront exécutées (relisez-les avant de confirmer) :"
  for stmt in "${alter_statements[@]}"; do
    echo "  $stmt"
  done
  echo "Backup disponible en cas de souci : $BACKUP_FILE"
  read -r -p "Confirmer l'application de ce plan ? [y/N] " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    fail "Correction annulée par l'utilisateur. Mise à jour annulée."
  fi

  for i in "${!table_names[@]}"; do
    tbl="${table_names[$i]}"
    log "Conversion de la table ${tbl}..."
    if ! MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -u "$DB_USER" "$DB_NAME" -e "${alter_statements[$i]}" 2>>"$LOG_FILE"; then
      fail "Échec sur la table ${tbl}. Tables déjà converties avant celle-ci (voir log) : laissez-les en l'état ou restaurez le backup si besoin ($BACKUP_FILE). Mise à jour annulée."
    fi
    log "Table ${tbl} convertie avec succès."
  done

  log "Colonnes uuid/id corrigées avec succès (${#table_names[@]} table(s))."
}

[[ -f "$COMPOSE_FILE" ]] || fail "docker-compose.yml introuvable: $COMPOSE_FILE"

log "=== Début de la mise à jour Vaultwarden vers $NEW_VERSION ==="

# --- Version actuellement déployée (pour rollback) ---
CURRENT_IMAGE="$(grep -E '^\s*image:\s*vaultwarden/server:' "$COMPOSE_FILE" | head -n1 | sed -E 's/.*image:\s*//')"
[[ -n "$CURRENT_IMAGE" ]] || fail "Impossible de déterminer l'image actuelle dans $COMPOSE_FILE"
CURRENT_VERSION="${CURRENT_IMAGE##*:}"
log "Version actuellement déployée : $CURRENT_VERSION"

if [[ "$CURRENT_VERSION" == "$NEW_VERSION" ]]; then
  log "La version cible ($NEW_VERSION) est déjà celle déployée. Rien à faire."
  exit 0
fi

# --- Backup de la base ---
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/vaultwarden_${CURRENT_VERSION}_$(date +%Y%m%d_%H%M%S).sql.gz"
log "Backup de la base vers $BACKUP_FILE"
if ! MYSQL_PWD="$DB_PASSWORD" mysqldump -h "$DB_HOST" -u "$DB_USER" "$DB_NAME" | gzip > "$BACKUP_FILE"; then
  fail "Le backup de la base a échoué, mise à jour annulée."
fi
if [[ ! -s "$BACKUP_FILE" ]]; then
  fail "Le fichier de backup est vide, mise à jour annulée."
fi
log "Backup OK ($(du -h "$BACKUP_FILE" | cut -f1))"

find "$BACKUP_DIR" -name 'vaultwarden_*.sql.gz' -mtime "+${BACKUP_RETENTION_DAYS}" -print -delete 2>/dev/null | while read -r f; do
  log "Backup expiré supprimé: $f"
done

# --- Vérification préventive de la collation ---
# cf. https://github.com/dani-garcia/vaultwarden/wiki/Using-the-MariaDB-%28MySQL%29-Backend#foreign-key-errors-collation-and-charset
#
# On vérifie TABLE_COLLATION (la collation réellement appliquée à chaque
# table) et non DEFAULT_COLLATION_NAME de information_schema.SCHEMATA : cette
# dernière n'est qu'un défaut pour les futures tables et peut valoir
# utf8mb4_unicode_ci suite à un ALTER DATABASE alors que les tables
# existantes sont, elles, toujours en utf8mb4_general_ci.
log "Vérification de la collation des tables..."
BAD_TABLES="$(MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -u "$DB_USER" -N -e \
  "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA='${DB_NAME}' AND TABLE_TYPE='BASE TABLE' AND TABLE_COLLATION != 'utf8mb4_unicode_ci';" 2>/dev/null)"

if [[ -n "$BAD_TABLES" ]]; then
  log "Tables avec une collation incorrecte détectées : $(echo "$BAD_TABLES" | tr '\n' ' ' | sed 's/ *$//') (attendu: utf8mb4_unicode_ci)."

  if [[ "$FIX_COLLATION" -ne 1 ]]; then
    fail "Corrigez-la manuellement avant de mettre à jour (voir le wiki MariaDB backend), ou relancez avec --fix-collation. Mise à jour annulée."
  fi

  fix_collation
else
  log "Collation des tables OK (utf8mb4_unicode_ci)."
fi

# --- Vérification préventive des colonnes uuid/id encore en TEXT ---
# cf. .claude/known_errors.md — MySQL ne peut pas former de clé étrangère
# vers une colonne TEXT (index par préfixe uniquement, pas sur la valeur
# complète). Chaque nouvelle version qui ajoute une FK vers une colonne
# uuid/id encore en TEXT échoue avec errno 150, sur une table différente à
# chaque fois (déjà vu sur users.uuid, puis ciphers.uuid).
log "Vérification des colonnes uuid/id..."
UUID_CANDIDATES="$(MYSQL_PWD="$DB_PASSWORD" mysql -h "$DB_HOST" -u "$DB_USER" -N -e \
  "SELECT TABLE_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='${DB_NAME}' AND DATA_TYPE='text' AND (COLUMN_NAME='uuid' OR COLUMN_NAME='id' OR RIGHT(COLUMN_NAME,5)='_uuid') LIMIT 1;" 2>/dev/null)"

if [[ -n "$UUID_CANDIDATES" ]]; then
  log "Des colonnes uuid/id encore en TEXT ont été détectées."

  if [[ "$FIX_UUID_COLUMNS" -ne 1 ]]; then
    fail "Corrigez-les manuellement, ou relancez avec --fix-uuid-columns pour une correction automatique (avec confirmation). Mise à jour annulée."
  fi

  fix_uuid_columns
else
  log "Colonnes uuid/id OK (VARCHAR(36))."
fi

# --- Pull de la nouvelle image ---
log "Pull de vaultwarden/server:$NEW_VERSION"
if ! docker pull "vaultwarden/server:$NEW_VERSION" >> "$LOG_FILE" 2>&1; then
  fail "Le pull de l'image $NEW_VERSION a échoué."
fi

# --- Mise à jour du docker-compose.yml ---
cp "$COMPOSE_FILE" "$COMPOSE_FILE.bak"
sed -i -E "s#(image:[[:space:]]*vaultwarden/server:)[^[:space:]]+#\1${NEW_VERSION}#" "$COMPOSE_FILE"
if ! grep -qE "image:[[:space:]]*vaultwarden/server:${NEW_VERSION}([[:space:]]|\$)" "$COMPOSE_FILE"; then
  cp "$COMPOSE_FILE.bak" "$COMPOSE_FILE"
  fail "La mise à jour du tag dans docker-compose.yml n'a pas pris effet (sed n'a rien remplacé). Fichier original restauré. Mise à jour annulée."
fi
log "docker-compose.yml mis à jour ($CURRENT_VERSION -> $NEW_VERSION), backup: $COMPOSE_FILE.bak"

rollback() {
  log "ROLLBACK: retour à la version $CURRENT_VERSION"
  cp "$COMPOSE_FILE.bak" "$COMPOSE_FILE"
  (cd "$COMPOSE_DIR" && docker-compose up -d) >> "$LOG_FILE" 2>&1
  log "ROLLBACK terminé. Le service tourne à nouveau en $CURRENT_VERSION."
  log "/!\\ Si une migration a partiellement modifié le schéma avant d'échouer, vérifiez l'état de la base manuellement (backup disponible: $BACKUP_FILE)."
}

# --- Application de la mise à jour ---
log "Relance du conteneur avec la version $NEW_VERSION"
if ! (cd "$COMPOSE_DIR" && docker-compose up -d) >> "$LOG_FILE" 2>&1; then
  log "docker-compose up -d a échoué."
  rollback
  exit 1
fi

# --- Contrôle post-update ---
log "Attente du healthcheck (max ${HEALTHCHECK_TIMEOUT}s) — logs du conteneur en direct ci-dessous :"
docker logs -f "$CONTAINER_NAME" 2>&1 &
LOG_TAIL_PID=$!

ELAPSED=0
STATUS="unknown"
while (( ELAPSED < HEALTHCHECK_TIMEOUT )); do
  STATUS="$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "unknown")"
  [[ "$STATUS" == "healthy" || "$STATUS" == "unhealthy" ]] && break
  sleep 3
  ELAPSED=$((ELAPSED + 3))
done

kill "$LOG_TAIL_PID" 2>/dev/null
wait "$LOG_TAIL_PID" 2>/dev/null

RECENT_LOGS="$(docker logs "$CONTAINER_NAME" --since "${HEALTHCHECK_TIMEOUT}s" 2>&1 || true)"
if echo "$RECENT_LOGS" | grep -Eiq "panic|Error running migrations|QueryError"; then
  log "Erreur détectée dans les logs du conteneur après mise à jour :"
  echo "$RECENT_LOGS" | grep -Ei "panic|Error running migrations|QueryError" | tee -a "$LOG_FILE"
  rollback
  exit 1
fi

if [[ "$STATUS" != "healthy" ]]; then
  log "Le conteneur n'est pas 'healthy' après ${HEALTHCHECK_TIMEOUT}s (status: $STATUS)."
  rollback
  exit 1
fi

rm -f "$COMPOSE_FILE.bak"
log "=== Mise à jour vers $NEW_VERSION terminée avec succès ==="
exit 0

