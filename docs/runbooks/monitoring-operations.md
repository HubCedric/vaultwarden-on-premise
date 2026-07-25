# Runbook — exploitation du monitoring

## État des timers

```bash
systemctl list-timers --all | grep vaultwarden
```

## Contrôle immédiat

```bash
sudo /usr/local/lib/vaultwarden-monitor/vaultwarden-replication-monitor.sh --check
```

## Mail de test

```bash
sudo /usr/local/lib/vaultwarden-monitor/vaultwarden-replication-monitor.sh --send-test-mail
```

## Vérifier un incident actif

```bash
sudo ls -la /var/lib/vaultwarden-monitor
sudo cat /var/lib/vaultwarden-monitor/critical_failure_count
sudo cat /var/lib/vaultwarden-monitor/last_reminder_date
```

## Conteneur arrêté par le monitor

Le fichier suivant indique qu'un arrêt de sécurité a eu lieu :

```bash
sudo test -e /var/lib/vaultwarden-monitor/vaultwarden_stopped_by_monitor && echo oui
```

Après correction :

```bash
sudo docker start vaultwarden
sudo /usr/local/lib/vaultwarden-monitor/vaultwarden-replication-monitor.sh --check
```

## Désactiver les timers

```bash
sudo systemctl disable --now vaultwarden-replication-monitor.timer
sudo systemctl disable --now vaultwarden-daily-consistency.timer
sudo systemctl disable --now vaultwarden-weekly-reconcile.timer
```

## Réactiver

```bash
sudo systemctl enable --now vaultwarden-replication-monitor.timer
sudo systemctl enable --now vaultwarden-daily-consistency.timer
sudo systemctl enable --now vaultwarden-weekly-reconcile.timer
```
