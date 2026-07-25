#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ${EUID} -ne 0 ]]; then
  echo "Exécutez ce script avec sudo." >&2
  exit 1
fi

install -d -m 700 /etc/vaultwarden-monitor /var/lib/vaultwarden-monitor
install -d -m 755 /usr/local/lib/vaultwarden-monitor

install -m 700 "$ROOT_DIR/scripts/monitoring/common.sh" /usr/local/lib/vaultwarden-monitor/common.sh
install -m 700 "$ROOT_DIR/scripts/monitoring/vaultwarden-replication-monitor.sh" /usr/local/lib/vaultwarden-monitor/
install -m 700 "$ROOT_DIR/scripts/monitoring/vaultwarden-daily-consistency.sh" /usr/local/lib/vaultwarden-monitor/
install -m 700 "$ROOT_DIR/scripts/monitoring/vaultwarden-weekly-reconcile.sh" /usr/local/lib/vaultwarden-monitor/

if [[ ! -e /etc/vaultwarden-monitor/monitor.env ]]; then
  install -m 600 "$ROOT_DIR/config/monitoring/monitor.env.example" /etc/vaultwarden-monitor/monitor.env
  echo "Créé : /etc/vaultwarden-monitor/monitor.env (à configurer)"
else
  echo "Conservé : /etc/vaultwarden-monitor/monitor.env"
fi

if [[ ! -e /etc/msmtprc ]]; then
  install -m 600 "$ROOT_DIR/config/monitoring/msmtprc.example" /etc/msmtprc
  echo "Créé : /etc/msmtprc (à configurer)"
else
  echo "Conservé : /etc/msmtprc"
fi

install -m 644 "$ROOT_DIR/config/monitoring/logrotate-vaultwarden-monitor" /etc/logrotate.d/vaultwarden-monitor
install -m 644 "$ROOT_DIR/systemd/vaultwarden-replication-monitor.service" /etc/systemd/system/
install -m 644 "$ROOT_DIR/systemd/vaultwarden-replication-monitor.timer" /etc/systemd/system/
install -m 644 "$ROOT_DIR/systemd/vaultwarden-daily-consistency.service" /etc/systemd/system/
install -m 644 "$ROOT_DIR/systemd/vaultwarden-daily-consistency.timer" /etc/systemd/system/
install -m 644 "$ROOT_DIR/systemd/vaultwarden-weekly-reconcile.service" /etc/systemd/system/
install -m 644 "$ROOT_DIR/systemd/vaultwarden-weekly-reconcile.timer" /etc/systemd/system/

systemctl daemon-reload
cat <<'MSG'

Installation des fichiers terminée.

Étapes suivantes :
1. Configurer /etc/vaultwarden-monitor/monitor.env.
2. Configurer /etc/msmtprc.
3. Créer le compte MariaDB avec config/monitoring/create_monitor_user.sql.example.
4. Tester le mail et les contrôles.
5. Activer les timers seulement après validation.

Consultez docs/monitoring.md.
MSG
