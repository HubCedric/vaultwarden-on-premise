# Supervision de la réplication et de Vaultwarden

Cette supervision est conçue pour deux nœuds MariaDB en réplication GTID bidirectionnelle :

- `bitwarden-master` : `10.0.0.1`, `server_id=1` ;
- `bitwarden-slave` : `10.0.0.2`, `server_id=2`.

Chaque nœud surveille sa réplication locale et interroge également le pair via WireGuard. Les alertes précisent le nœud qui a exécuté le contrôle et le nœud sur lequel l'anomalie a été observée.

> [!CAUTION]
> La supervision ne répare jamais la réplication. Elle peut uniquement arrêter le conteneur Vaultwarden du nœud de secours afin de limiter le risque de split-brain.

## Fonctionnalités

Le contrôle principal s'exécute toutes les cinq minutes et vérifie :

- accessibilité MariaDB locale et distante ;
- présence de `SHOW SLAVE STATUS` ;
- threads IO et SQL ;
- erreurs IO et SQL ;
- retard de réplication ;
- source, port et `server_id` attendus ;
- mode GTID et position `Gtid_IO_Pos` ;
- état Docker `running`, `exited`, `dead` ou `restarting` ;
- santé Docker `healthy`, `unhealthy` ou `starting` ;
- état `starting` depuis plus de deux minutes ;
- augmentation anormale de `RestartCount`.

Le paquet ajoute aussi :

- une comparaison quotidienne des compteurs de tables ;
- une réconciliation hebdomadaire en lecture seule ;
- un mail initial, un rappel quotidien et un mail de rétablissement ;
- un mode maintenance ;
- une rotation des journaux sur 90 jours.

## Politique d'arrêt du slave

`bitwarden-master` ne doit jamais avoir `ALLOW_SAFETY_STOP=1`.

Sur `bitwarden-slave`, le conteneur est arrêté :

- immédiatement sur une erreur IO ou SQL explicite ;
- après deux contrôles critiques consécutifs pour les autres anomalies ;
- après deux contrôles avec un retard supérieur au seuil critique.

Le script ne redémarre jamais le conteneur. La remise en service reste manuelle.

## Installation

### 1. Installer les dépendances

Sur les deux nœuds :

```bash
sudo apt update
sudo apt install -y mariadb-client msmtp msmtp-mta ca-certificates
```

### 2. Déployer les fichiers

Depuis la racine du dépôt :

```bash
sudo ./scripts/install_monitoring.sh
```

Le script ne remplace pas une configuration existante dans `/etc/vaultwarden-monitor/monitor.env` ou `/etc/msmtprc`.

### 3. Créer le compte MariaDB

Copier le modèle :

```bash
cp config/monitoring/create_monitor_user.sql.example /tmp/create_monitor_user.sql
nano /tmp/create_monitor_user.sql
sudo mariadb < /tmp/create_monitor_user.sql
rm -f /tmp/create_monitor_user.sql
```

Sur le master, limiter le compte réseau au pair `10.0.0.2`. Sur le slave, le limiter à `10.0.0.1`. Le wildcard `10.0.0.%` fonctionne, mais il est moins restrictif.

Vérification :

```bash
sudo mariadb -e "SELECT User, Host FROM mysql.user WHERE User='vaultwarden_monitor';"
```

### 4. Configurer SMTP

Éditer :

```bash
sudo nano /etc/msmtprc
sudo chmod 600 /etc/msmtprc
```

Exemple Infomaniak :

```ini
account        vaultwarden-monitor
host           mail.infomaniak.com
port           587
from           no-reply@example.net
user           no-reply@example.net
password       A_CONFIGURER
auth           login
tls            on
tls_starttls   on
```

Ne jamais publier `/etc/msmtprc` ni son mot de passe.

### 5. Configurer le master

Éditer `/etc/vaultwarden-monitor/monitor.env` :

```ini
NODE_NAME="bitwarden-master"
NODE_ROLE="master"
LOCAL_DB_HOST="10.0.0.1"
LOCAL_DB_PORT="3306"
LOCAL_SERVER_ID="1"

PEER_NAME="bitwarden-slave"
PEER_HOST="10.0.0.2"
PEER_PORT="3306"
PEER_SERVER_ID="2"

EXPECTED_MASTER_HOST="10.0.0.2"
EXPECTED_MASTER_PORT="3306"
ALLOW_SAFETY_STOP="0"
```

### 6. Configurer le slave

```ini
NODE_NAME="bitwarden-slave"
NODE_ROLE="slave"
LOCAL_DB_HOST="10.0.0.2"
LOCAL_DB_PORT="3306"
LOCAL_SERVER_ID="2"

PEER_NAME="bitwarden-master"
PEER_HOST="10.0.0.1"
PEER_PORT="3306"
PEER_SERVER_ID="1"

EXPECTED_MASTER_HOST="10.0.0.1"
EXPECTED_MASTER_PORT="3306"
ALLOW_SAFETY_STOP="1"
```

Sur les deux nœuds :

```bash
sudo chmod 600 /etc/vaultwarden-monitor/monitor.env
```

## Tests avant activation

### Vérifier la syntaxe

```bash
sudo bash -n /usr/local/lib/vaultwarden-monitor/*.sh
```

### Tester le SMTP

```bash
sudo /usr/local/lib/vaultwarden-monitor/vaultwarden-replication-monitor.sh --send-test-mail
```

### Lancer un contrôle complet

```bash
sudo /usr/local/lib/vaultwarden-monitor/vaultwarden-replication-monitor.sh --verbose
```

### Tester les compteurs

```bash
sudo /usr/local/lib/vaultwarden-monitor/vaultwarden-daily-consistency.sh
```

### Tester une fausse source sur le slave

Pendant une fenêtre de maintenance, remplacer temporairement :

```ini
EXPECTED_MASTER_HOST="10.0.0.99"
```

Au premier contrôle, un mail est envoyé et l'arrêt est différé à `1/2`. Au second contrôle, le conteneur slave est arrêté. Restaurer ensuite `10.0.0.1`.

### Tester un conteneur arrêté

```bash
sudo docker stop vaultwarden
```

Le prochain contrôle doit signaler `Vaultwarden arrêté`. Après le test :

```bash
sudo docker start vaultwarden
sudo /usr/local/lib/vaultwarden-monitor/vaultwarden-replication-monitor.sh --check
```

## Activation permanente

Sur les deux serveurs :

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now vaultwarden-replication-monitor.timer
sudo systemctl enable --now vaultwarden-daily-consistency.timer
sudo systemctl enable --now vaultwarden-weekly-reconcile.timer
```

Vérification :

```bash
systemctl list-timers --all | grep vaultwarden
```

Les timers restent activés après redémarrage.

## Cycle des alertes

- détection initiale : un mail ;
- incident persistant : aucun mail toutes les cinq minutes ;
- rappel : une fois par jour après l'heure configurée ;
- rétablissement : un mail lorsque les contrôles redeviennent sains.

Le mail initial est enregistré comme notification du jour. Un incident créé après 09:00 ne produit donc pas un second mail cinq minutes plus tard.

## Mode maintenance

Activer :

```bash
sudo touch /etc/vaultwarden-monitor/maintenance
```

Désactiver :

```bash
sudo rm -f /etc/vaultwarden-monitor/maintenance
```

Le mode maintenance est local à chaque nœud. Il faut l'activer sur les deux si l'intervention concerne les deux serveurs.

## Journaux

```bash
sudo tail -n 100 /var/log/vaultwarden-replication-monitor.log
sudo journalctl -u vaultwarden-replication-monitor.service -n 100 --no-pager
sudo journalctl -u vaultwarden-replication-monitor.service -f
```

Le code de sortie `2` représente un incident détecté. L'unité systemd le considère comme une sortie attendue grâce à `SuccessExitStatus=2` ; l'alerte reste visible dans les journaux et par mail.

## Mise à jour du monitoring

Après un `git pull` :

```bash
sudo ./scripts/install_monitoring.sh
sudo bash -n /usr/local/lib/vaultwarden-monitor/*.sh
sudo systemctl daemon-reload
```

Le fichier `monitor.env` et `/etc/msmtprc` existants sont conservés.

## Limites importantes

La supervision ne garantit pas que les données sont identiques. Elle vérifie l'état de la réplication déclaré par MariaDB, compare quotidiennement des compteurs et exécute une réconciliation hebdomadaire. Deux tables peuvent avoir le même nombre de lignes avec des contenus différents.

Elle ne surveille pas le load balancer, WireGuard, l'espace disque, le CPU, la mémoire, les certificats, la réception effective des mails ni les erreurs applicatives visibles uniquement dans les logs Vaultwarden.
