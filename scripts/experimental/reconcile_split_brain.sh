#!/usr/bin/env bash
#
# Outil ponctuel (PAS un script de cron) pour réconcilier 2 bases Vaultwarden
# ayant divergé pendant une panne de réplication (split-brain). Se connecte
# EN DIRECT aux 2 serveurs (via .env, compte lecture seule
# 'reconcile_ro' — jamais le compte applicatif 'vaultwarden' ni 'monitor'
# qui n'a pas accès au schéma), importe un dump frais de chacun dans des
# bases temporaires locales (jamais dans une base nommée "vaultwarden"),
# compare ligne par ligne (la plus récente par colonne de date gagne), et
# génère 2 fichiers SQL à relire puis à exécuter soi-même sur le vrai
# serveur concerné :
#   - apply_to_master.sql : ce qu'il faut appliquer sur le serveur master
#   - apply_to_slave.sql  : ce qu'il faut appliquer sur le serveur slave
#
# Par défaut, ce script ne fait que lire les deux serveurs et générer des
# fichiers SQL. Avec --apply, il écrit réellement sur les bases après une
# confirmation explicite : cette option est expérimentale et destructive.
#
# Utilise INSERT ... ON DUPLICATE KEY UPDATE (jamais DELETE ni REPLACE) pour
# ne jamais déclencher de suppression en cascade sur les tables liées.
#
# À exécuter depuis l'un des 2 serveurs (celui qui a un accès local en
# écriture pour héberger les bases temporaires) ; l'autre est interrogé via
# le réseau VPN.
#
# Usage : ./reconcile_split_brain.sh <dossier_sortie> [--apply]
#
# --apply : après génération et confirmation explicite (taper "oui"),
#   applique réellement les 2 fichiers — celui du serveur LOCAL (celui d'où
#   tourne le script) via les droits admin déjà présents, celui du serveur
#   DISTANT via une connexion réseau avec le compte applicatif 'vaultwarden'
#   (déjà ALL PRIVILEGES sur vaultwarden.*, déjà joignable via le réseau
#   VPN — aucun nouveau grant nécessaire). Sans ce flag, le script ne fait
#   que générer les fichiers à relire, comme avant.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Fichier .env introuvable ($ENV_FILE). Copiez .env.example vers .env et renseignez les valeurs." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

MYSQL_BIN="${MYSQL_BIN:-mysql}"
MYSQLDUMP_BIN="${MYSQLDUMP_BIN:-mysqldump}"

OUT_DIR=""
APPLY=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    -*)
      echo "Option inconnue: $arg" >&2
      exit 1
      ;;
    *) OUT_DIR="$arg" ;;
  esac
done

if [[ -z "$OUT_DIR" ]]; then
  echo "Usage: $0 <dossier_sortie> [--apply]" >&2
  exit 1
fi

# Détermine quel côté est "local" (celui d'où tourne le script) : c'est
# celui dont le *_HOST vaut 127.0.0.1/localhost. Nécessaire uniquement pour
# --apply, pour savoir lequel des 2 fichiers appliquer en local (droits
# admin) et lequel appliquer à distance (compte 'vaultwarden' réseau).
if [[ "$APPLY" -eq 1 ]]; then
  LOCAL_ROLE=""
  if [[ "$MASTER_HOST" == "127.0.0.1" || "$MASTER_HOST" == "localhost" ]]; then
    LOCAL_ROLE="master"
  elif [[ "$SLAVE_HOST" == "127.0.0.1" || "$SLAVE_HOST" == "localhost" ]]; then
    LOCAL_ROLE="slave"
  fi
  if [[ -z "$LOCAL_ROLE" ]]; then
    echo "Impossible de determiner le cote local avec --apply : ni MASTER_HOST ni SLAVE_HOST ne vaut 127.0.0.1/localhost dans .env." >&2
    exit 1
  fi
  if [[ "$LOCAL_ROLE" == "master" ]]; then
    REMOTE_HOST="$SLAVE_HOST"; REMOTE_PORT="$SLAVE_PORT"
    REMOTE_WRITE_USER="${SLAVE_WRITE_USER:-}"; REMOTE_WRITE_PASSWORD="${SLAVE_WRITE_PASSWORD:-}"
  else
    REMOTE_HOST="$MASTER_HOST"; REMOTE_PORT="$MASTER_PORT"
    REMOTE_WRITE_USER="${MASTER_WRITE_USER:-}"; REMOTE_WRITE_PASSWORD="${MASTER_WRITE_PASSWORD:-}"
  fi
  if [[ -z "$REMOTE_WRITE_USER" || -z "$REMOTE_WRITE_PASSWORD" ]]; then
    echo "--apply demande mais *_WRITE_USER/*_WRITE_PASSWORD manquant dans .env pour le cote distant." >&2
    exit 1
  fi
fi

mkdir -p "$OUT_DIR"
APPLY_MASTER="$OUT_DIR/apply_to_master.sql"
APPLY_SLAVE="$OUT_DIR/apply_to_slave.sql"
REPORT="$OUT_DIR/report.txt"
: > "$APPLY_MASTER"
: > "$APPLY_SLAVE"
: > "$REPORT"

TMP_MASTER_DB="reconcile_master_tmp_$$"
TMP_SLAVE_DB="reconcile_slave_tmp_$$"

# Connexion locale utilisée pour héberger/comparer les bases temporaires
# (droits admin nécessaires : CREATE/DROP DATABASE). Distincte des comptes
# 'reconcile_ro' utilisés pour lire les 2 serveurs vaultwarden.
LOCAL_MYSQL_OPTS=(-u "${LOCAL_ADMIN_USER:-root}")
[[ -n "${LOCAL_ADMIN_SOCKET:-}" ]] && LOCAL_MYSQL_OPTS+=(--socket="$LOCAL_ADMIN_SOCKET")
LOCAL_MYSQLDUMP_OPTS=("${LOCAL_MYSQL_OPTS[@]}")

m() { "$MYSQL_BIN" "${LOCAL_MYSQL_OPTS[@]}" "$@"; }

cleanup() {
  m -e "DROP DATABASE IF EXISTS \`$TMP_MASTER_DB\`; DROP DATABASE IF EXISTS \`$TMP_SLAVE_DB\`;" 2>/dev/null
}
trap cleanup EXIT

echo "Import en direct depuis les 2 serveurs dans des bases temporaires ($TMP_MASTER_DB, $TMP_SLAVE_DB)..."
m -e "CREATE DATABASE \`$TMP_MASTER_DB\`; CREATE DATABASE \`$TMP_SLAVE_DB\`;" || exit 1

MYSQL_PWD="$MASTER_PASSWORD" "$MYSQLDUMP_BIN" -h "$MASTER_HOST" -P "$MASTER_PORT" -u "$MASTER_USER" \
    --single-transaction --no-tablespaces vaultwarden \
  | m "$TMP_MASTER_DB" || { echo "Échec import direct depuis master ($MASTER_HOST)" >&2; exit 1; }

MYSQL_PWD="$SLAVE_PASSWORD" "$MYSQLDUMP_BIN" -h "$SLAVE_HOST" -P "$SLAVE_PORT" -u "$SLAVE_USER" \
    --single-transaction --no-tablespaces vaultwarden \
  | m "$TMP_SLAVE_DB" || { echo "Échec import direct depuis slave ($SLAVE_HOST)" >&2; exit 1; }

# Transforme un bloc d'INSERT générés par mysqldump (--complete-insert) en
# INSERT ... ON DUPLICATE KEY UPDATE, en réutilisant la liste de colonnes
# déjà présente dans l'instruction (jamais de DELETE : on ne veut aucune
# cascade FK involontaire sur les tables liées).
to_upsert() {
  # Uniquement index()/substr()/split() (POSIX) : pas d'extension gawk
  # (match() à 3 arguments), pour rester portable (BSD awk sur macOS,
  # mawk sur Debian où gawk n'est pas garanti présent). LC_ALL=C : les
  # colonnes chiffrées (ciphers.data, akey, etc.) contiennent des blobs
  # binaires bruts, pas de l'UTF-8 valide — sans forcer un traitement
  # octet par octet, awk plante ("multibyte conversion failure") dès qu'il
  # rencontre un de ces octets en locale UTF-8.
  # mysqldump peut scinder un INSERT multi-lignes sur plusieurs lignes
  # physiques (une virgule de continuation en fin de ligne, pas de ";").
  # On accumule jusqu'a la ligne qui termine reellement par ";" avant de
  # transformer - traiter juste la 1ere ligne comme l'instruction complete
  # tronquerait le VALUES et casserait la syntaxe (deja vu en production).
  LC_ALL=C awk '
    function flush(line, p1, p2, cols, n, upd, i, c) {
      line = buf
      sub(/;[[:space:]]*$/, "", line)
      p1 = index(line, "(")
      p2 = index(line, ")")
      cols = substr(line, p1 + 1, p2 - p1 - 1)
      n = split(cols, colarr, ",")
      upd = ""
      for (i = 1; i <= n; i++) {
        c = colarr[i]
        gsub(/^ +| +$/, "", c)
        upd = upd (i > 1 ? ", " : "") c "=VALUES(" c ")"
      }
      print line " ON DUPLICATE KEY UPDATE " upd ";"
      buf = ""
      buffering = 0
    }
    /^INSERT INTO/ {
      buf = $0
      if ($0 ~ /;[[:space:]]*$/) { flush() } else { buffering = 1 }
      next
    }
    buffering {
      buf = buf "\n" $0
      if ($0 ~ /;[[:space:]]*$/) { flush() }
      next
    }
    # Toute autre ligne (preambule mysqldump, SET, commentaires) est
    # volontairement ignoree : le fichier de sortie ne doit contenir que
    # les upserts, jamais une instruction supplementaire non relue.
  '
}

# Construit l'expression SQL qui transforme une ligne en tuple SQL quote
# ("('v1','v2')"), colonne par colonne via QUOTE() (echappement cote
# serveur), pour une cle simple ou composite indifferemment.
row_quote_expr() {
  local alias="$1"; shift
  local parts=("'('") col first=1
  for col in "$@"; do
    if [[ $first -eq 1 ]]; then first=0; else parts+=("','"); fi
    parts+=("QUOTE(${alias}.${col})")
  done
  parts+=("')'")
  local IFS=,
  echo "CONCAT(${parts[*]})"
}

# Dumpe, depuis $src_db, les lignes dont la cle (simple ou composite,
# cols_csv) correspond a l'un des tuples de pk_list_file (un tuple SQL
# quote par ligne, produit par row_quote_expr), transformees en upsert.
dump_upserts() {
  local src_db="$1" table="$2" cols_csv="$3" pk_list_file="$4" dest_file="$5"
  [[ -s "$pk_list_file" ]] || return 0
  local tuples where_clause
  tuples="$(paste -sd, "$pk_list_file")"
  where_clause="(${cols_csv}) IN (${tuples})"
  "$MYSQLDUMP_BIN" "${LOCAL_MYSQLDUMP_OPTS[@]}" --no-create-info --complete-insert --skip-add-locks \
    --skip-comments --compact --where="$where_clause" "$src_db" "$table" \
    | to_upsert >> "$dest_file"
}

# Table avec cle simple OU composite (cols_csv: "uuid" ou "uuid,user_uuid")
# + colonne de date : genere les 2 sens a partir d'une requete de
# comparaison par sens, en joignant sur TOUTES les colonnes de la cle (une
# jointure sur une seule colonne d'une cle composite - ex: devices.uuid,
# partage par plusieurs comptes - produirait un produit cartesien et des
# comparaisons entre lignes qui ne sont pas la meme entree logique).
reconcile_table() {
  local table="$1" pk_csv="$2" ts="$3"
  local -a cols
  IFS=',' read -ra cols <<< "$pk_csv"
  local probe_col="${cols[0]}"
  local join_cond="" col
  for col in "${cols[@]}"; do
    [[ -n "$join_cond" ]] && join_cond+=" AND "
    join_cond+="m.${col} = s.${col}"
  done

  local to_master to_slave n_to_master n_to_slave
  to_master="$(mktemp)"; to_slave="$(mktemp)"

  m -N -e "
    SELECT $(row_quote_expr s "${cols[@]}")
    FROM \`$TMP_SLAVE_DB\`.${table} s
    LEFT JOIN \`$TMP_MASTER_DB\`.${table} m ON ${join_cond}
    WHERE m.${probe_col} IS NULL OR s.${ts} > m.${ts};
  " > "$to_master"

  m -N -e "
    SELECT $(row_quote_expr m "${cols[@]}")
    FROM \`$TMP_MASTER_DB\`.${table} m
    LEFT JOIN \`$TMP_SLAVE_DB\`.${table} s ON ${join_cond}
    WHERE s.${probe_col} IS NULL OR m.${ts} > s.${ts};
  " > "$to_slave"

  n_to_master=$(wc -l < "$to_master" | tr -d ' ')
  n_to_slave=$(wc -l < "$to_slave" | tr -d ' ')

  echo "[$table] vers master: $n_to_master ligne(s) — vers slave: $n_to_slave ligne(s)" | tee -a "$REPORT"

  dump_upserts "$TMP_SLAVE_DB" "$table" "$pk_csv" "$to_master" "$APPLY_MASTER"
  dump_upserts "$TMP_MASTER_DB" "$table" "$pk_csv" "$to_slave" "$APPLY_SLAVE"

  rm -f "$to_master" "$to_slave"
}

# folders_ciphers : clé composite, pas de colonne de date -> simple
# différence d'ensemble, INSERT IGNORE (rien à mettre à jour, juste la
# présence de la paire compte).
reconcile_folders_ciphers() {
  local to_master to_slave n_to_master n_to_slave
  to_master="$(mktemp)"; to_slave="$(mktemp)"

  m -N -e "
    SELECT CONCAT('(', QUOTE(s.cipher_uuid), ',', QUOTE(s.folder_uuid), ')')
    FROM \`$TMP_SLAVE_DB\`.folders_ciphers s
    LEFT JOIN \`$TMP_MASTER_DB\`.folders_ciphers m
      ON m.cipher_uuid = s.cipher_uuid AND m.folder_uuid = s.folder_uuid
    WHERE m.cipher_uuid IS NULL;
  " > "$to_master"

  m -N -e "
    SELECT CONCAT('(', QUOTE(m.cipher_uuid), ',', QUOTE(m.folder_uuid), ')')
    FROM \`$TMP_MASTER_DB\`.folders_ciphers m
    LEFT JOIN \`$TMP_SLAVE_DB\`.folders_ciphers s
      ON s.cipher_uuid = m.cipher_uuid AND s.folder_uuid = m.folder_uuid
    WHERE s.cipher_uuid IS NULL;
  " > "$to_slave"

  n_to_master=$(wc -l < "$to_master" | tr -d ' ')
  n_to_slave=$(wc -l < "$to_slave" | tr -d ' ')
  echo "[folders_ciphers] vers master: $n_to_master paire(s) — vers slave: $n_to_slave paire(s)" | tee -a "$REPORT"

  if [[ -s "$to_master" ]]; then
    {
      echo -n "INSERT IGNORE INTO folders_ciphers (cipher_uuid, folder_uuid) VALUES "
      paste -sd, "$to_master"
      echo ";"
    } >> "$APPLY_MASTER"
  fi
  if [[ -s "$to_slave" ]]; then
    {
      echo -n "INSERT IGNORE INTO folders_ciphers (cipher_uuid, folder_uuid) VALUES "
      paste -sd, "$to_slave"
      echo ";"
    } >> "$APPLY_SLAVE"
  fi

  rm -f "$to_master" "$to_slave"
}

echo "=== Réconciliation split-brain — $(date) ===" | tee -a "$REPORT"

# Ordre de dépendance : users avant folders/devices/ciphers, ciphers/folders
# avant folders_ciphers.
reconcile_table "users" "uuid" "updated_at"
reconcile_table "folders" "uuid" "updated_at"
# devices : cle primaire composite (uuid, user_uuid) - un meme appareil
# (navigateur partage) peut etre associe a plusieurs comptes.
reconcile_table "devices" "uuid,user_uuid" "updated_at"
reconcile_table "ciphers" "uuid" "updated_at"
reconcile_folders_ciphers

echo | tee -a "$REPORT"
echo "Fichiers générés dans $OUT_DIR :" | tee -a "$REPORT"
echo "  - $APPLY_MASTER (à relire puis exécuter SUR bitwarden-master : sudo mysql vaultwarden < apply_to_master.sql)" | tee -a "$REPORT"
echo "  - $APPLY_SLAVE  (à relire puis exécuter SUR bitwarden-slave  : sudo mysql vaultwarden < apply_to_slave.sql)" | tee -a "$REPORT"
echo | tee -a "$REPORT"
echo "Jusqu'ici, ce script n'a écrit sur AUCUNE base réelle — seulement dans les bases temporaires $TMP_MASTER_DB/$TMP_SLAVE_DB, supprimées en fin d'exécution." | tee -a "$REPORT"

if [[ "$APPLY" -eq 1 ]]; then
  if [[ "$LOCAL_ROLE" == "master" ]]; then
    LOCAL_FILE="$APPLY_MASTER"; REMOTE_FILE="$APPLY_SLAVE"
  else
    LOCAL_FILE="$APPLY_SLAVE"; REMOTE_FILE="$APPLY_MASTER"
  fi

  echo | tee -a "$REPORT"
  echo "=== --apply : application reelle demandee ===" | tee -a "$REPORT"
  echo "Local  ($LOCAL_ROLE, via droits admin)          : $LOCAL_FILE" | tee -a "$REPORT"
  echo "Distant ($REMOTE_HOST, compte $REMOTE_WRITE_USER) : $REMOTE_FILE" | tee -a "$REPORT"
  echo
  read -r -p "Confirmer l'application reelle sur les 2 bases de production ? Tapez exactement 'oui' : " CONFIRM
  if [[ "$CONFIRM" != "oui" ]]; then
    echo "Annule par l'utilisateur. Aucune ecriture effectuee." | tee -a "$REPORT"
    exit 0
  fi

  if [[ -s "$LOCAL_FILE" ]]; then
    if m vaultwarden < "$LOCAL_FILE"; then
      echo "Application locale reussie ($LOCAL_FILE)." | tee -a "$REPORT"
    else
      echo "ECHEC de l'application locale ($LOCAL_FILE). Base distante non touchee. Voir ci-dessus." | tee -a "$REPORT"
      exit 1
    fi
  else
    echo "Rien a appliquer localement (fichier vide)." | tee -a "$REPORT"
  fi

  if [[ -s "$REMOTE_FILE" ]]; then
    if MYSQL_PWD="$REMOTE_WRITE_PASSWORD" "$MYSQL_BIN" -h "$REMOTE_HOST" -P "$REMOTE_PORT" -u "$REMOTE_WRITE_USER" vaultwarden < "$REMOTE_FILE"; then
      echo "Application distante reussie ($REMOTE_FILE sur $REMOTE_HOST)." | tee -a "$REPORT"
    else
      echo "ECHEC de l'application distante ($REMOTE_FILE sur $REMOTE_HOST). La base locale a deja ete modifiee : verifier manuellement avant de relancer." | tee -a "$REPORT"
      exit 1
    fi
  else
    echo "Rien a appliquer a distance (fichier vide)." | tee -a "$REPORT"
  fi

  echo | tee -a "$REPORT"
  echo "Application terminee sur les 2 serveurs." | tee -a "$REPORT"
fi
