# Mise en œuvre et reconstruction

[← Architecture](01-architecture-et-conception.md) · [README](../README.md) · [Exploitation →](03-exploitation-et-maintenance.md)

Ce guide regroupe la partie **Sys / Build**. Il sert à installer l'infrastructure sur
des machines vierges, à reconstruire un backend après perte matérielle ou à préparer
une migration. Les commandes sont volontairement proches du copier-coller, mais les
secrets restent hors Git et les valeurs publiques sont remplacées par des
placeholders.

Le fil conducteur est toujours le même : préparer l'OS, établir WireGuard, installer
MariaDB, installer Docker/Vaultwarden, poser les certificats backend, déployer le
monitoring, puis configurer Caddy sur le VPS et effectuer une validation bout en bout.

```mermaid
flowchart LR
    A["OS propre"] --> B["WireGuard"]
    B --> C["MariaDB"]
    C --> D["Réplication"]
    D --> E["Docker"]
    E --> F["Vaultwarden"]
    F --> G["Monitoring"]
    G --> H["Caddy / ingress"]
    H --> I["Validation complète"]
```

> [!IMPORTANT]
> Une reconstruction d'un nœud n'est pas une occasion de lancer immédiatement une
> réplication ou d'appliquer un script de réconciliation. Tant que la copie de données
> de référence n'a pas été identifiée et vérifiée, rester en lecture seule et ne pas
> exposer le nouveau backend à Caddy.
## Prérequis

### Objectif

Réunir les informations et accès nécessaires avant de construire ou reconstruire un nœud.

### Prérequis

- trois machines Linux avec heure synchronisée et accès administrateur ;
- domaine pointant vers `equilihost`, ici représenté par `vaultwarden.example.com` ;
- connectivité publique suffisante pour les endpoints WireGuard ;
- espace chiffré privé pour les clés, tokens, mots de passe et certificats ;
- décision explicite sur le nœud source de vérité avant toute restauration.

### Commandes

Sur chaque machine, collecter sans modifier :

```bash
hostnamectl
cat /etc/os-release
uname -m
timedatectl
df -hT
free -h
```

Préparer une fiche privée contenant les endpoints publics, ports SSH, clés WireGuard, identifiants MariaDB et secret d’administration. Cette fiche ne doit pas être ajoutée au dépôt.

### Vérifications

- les hostnames sont `bitwarden-master`, `bitwarden-slave` et `equilihost` ;
- les trois horloges sont synchronisées ;
- les architectures processeur sont compatibles avec les images Vaultwarden ;
- aucun secret n’est présent dans le répertoire Git.

### Rollback

Aucune modification n’est réalisée à cette étape. Supprimer seulement les notes temporaires non protégées si elles contiennent des secrets.

### Validation finale

- [ ] Inventaire matériel et OS validé
- [ ] Accès administrateur testé
- [ ] DNS et endpoints privés consignés hors Git
- [ ] Source de restauration désignée


## Préparation système

### Objectif

Préparer un Linux à jour, correctement horodaté et doté des outils de diagnostic utilisés par les runbooks.

### Prérequis

Fenêtre de maintenance, console de secours pour les machines distantes et sauvegarde des fichiers système déjà personnalisés.

### Commandes

```bash
sudo apt update
sudo apt upgrade
sudo apt install curl ca-certificates gnupg jq rsync wireguard \
  mariadb-client openssl netcat-openbsd
sudo systemctl enable --now systemd-timesyncd
timedatectl status
```

Définir le hostname correspondant au rôle :

```bash
sudo hostnamectl set-hostname bitwarden-master
```

Adapter sur les deux autres nœuds. Ne pas automatiser un redémarrage hebdomadaire : un reboot planifié n’apporte pas à lui seul de fiabilité et peut masquer une dépendance de démarrage.

### Vérifications

```bash
systemctl --failed --no-pager
systemctl is-active systemd-timesyncd
apt list --upgradable
```

### Rollback

Restaurer les fichiers de configuration sauvegardés si un paquet a remplacé une personnalisation. En cas de perte réseau, utiliser la console locale/VNC du fournisseur avant tout autre changement.

### Validation finale

- [ ] Aucun service critique en échec
- [ ] Heure et fuseau cohérents
- [ ] Paquets de diagnostic présents
- [ ] Redémarrage requis planifié, pas improvisé


## Installation de WireGuard

### Objectif

Créer le réseau privé `10.0.0.0/24` reliant les trois nœuds sans publier les backends.

### Prérequis

WireGuard installé, UDP/51820 autorisé, endpoints publics connus dans la documentation privée et clés générées sur chaque hôte.

### Commandes

Copier le gabarit du nœud depuis [`configs/wireguard/`](../configs/README.md), puis remplacer uniquement les placeholders hors Git.

```bash
sudo install -m 700 -d /etc/wireguard
sudo install -m 600 configs/wireguard/bitwarden-master/wg0.conf.example \
  /etc/wireguard/wg0.conf
sudo editor /etc/wireguard/wg0.conf
sudo systemctl enable --now wg-quick@wg0
```

Sur `equilihost`, activer le forwarding uniquement si le routage master↔slave passe par ce nœud :

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

Rendre la valeur persistante dans un fichier `/etc/sysctl.d/` après validation.

### Vérifications

```bash
sudo wg show
ip -brief address show wg0
ping -c 3 10.0.0.10
nc -vz -w 3 10.0.0.2 3306
```

Contrôler un handshake récent et les `AllowedIPs` exacts. Un service `wg-quick@wg0` en échec avec « wg0 already exists » peut signifier que l’interface a été créée manuellement ; supprimer l’ambiguïté avant le prochain reboot.

### Rollback

```bash
sudo systemctl disable --now wg-quick@wg0
sudo wg-quick down wg0
```

Conserver une session de console ouverte tant que l’accès distant n’est pas confirmé.

### Validation finale

- [ ] Chaque nœud porte la bonne IP WireGuard
- [ ] Handshakes récents
- [ ] Master et slave joignent `equilihost`
- [ ] TCP/443 et TCP/3306 passent uniquement par le chemin prévu
- [ ] Démarrage automatique testé après reboot


## Installation de MariaDB

### Objectif

Installer MariaDB 10.11 directement sur chaque backend et appliquer les paramètres propres à son identité de réplication.

### Prérequis

WireGuard opérationnel, disque sain, ports filtrés et absence de base `vaultwarden` existante à préserver.

### Commandes

```bash
sudo apt update
sudo apt install mariadb-server mariadb-client
sudo systemctl enable --now mariadb
sudo mariadb-secure-installation
```

Installer le fichier du bon nœud :

```bash
sudo install -m 644 configs/mariadb/bitwarden-master/50-server.cnf \
  /etc/mysql/mariadb.conf.d/50-server.cnf
sudo systemctl restart mariadb
```

Sur le slave, utiliser le fichier `bitwarden-slave`. Créer les utilisateurs à partir du gabarit SQL en remplaçant les secrets dans une copie hors Git.

### Vérifications

```bash
sudo mariadb -e "SELECT VERSION(), @@server_id, @@binlog_format;"
sudo ss -lntp | grep 3306
sudo mariadb -e "SHOW VARIABLES LIKE 'auto_increment_%';"
```

Le `server_id` et l’offset doivent être différents entre les deux nœuds.

### Rollback

Restaurer l’ancien `50-server.cnf`, puis redémarrer MariaDB. Ne jamais supprimer une base existante sans dump, somme de contrôle et validation humaine.

### Validation finale

- [ ] MariaDB active au boot
- [ ] `server_id` unique
- [ ] binlog `ROW` actif
- [ ] port 3306 filtré
- [ ] secrets absents du dépôt


## Configuration de la réplication

### Objectif

Initialiser une réplication bidirectionnelle GTID à partir d’une base de référence unique, sans fusion implicite de deux bases divergentes.

### Prérequis

- fenêtre d’indisponibilité et mode maintenance actif ;
- conteneurs Vaultwarden arrêtés ;
- dump cohérent de la base choisie comme référence ;
- utilisateurs de réplication créés et mot de passe conservé hors Git ;
- aucune divergence non analysée.

### Commandes

Sur la source :

```bash
sudo mariadb-dump --single-transaction --routines --events --triggers \
  vaultwarden | gzip > /tmp/vaultwarden-reference.sql.gz
sha256sum /tmp/vaultwarden-reference.sql.gz
```

Copier le dump par un canal chiffré. Sur le nœud à reconstruire, après validation explicite de la cible :

```sql
STOP SLAVE;
CHANGE MASTER TO
  MASTER_HOST='10.0.0.1',
  MASTER_PORT=3306,
  MASTER_USER='repli',
  MASTER_PASSWORD='<SECRET_HORS_GIT>',
  MASTER_USE_GTID=slave_pos;
START SLAVE;
```

Configurer l’autre sens avec `MASTER_HOST='10.0.0.2'`. Les commandes exactes de réimport dépendent de l’état de la base ; voir le [runbook de divergence](05-incidents-et-pra.md) avant toute suppression.

### Vérifications

Sur les deux nœuds :

```sql
SHOW SLAVE STATUS\G
```

Attendre `Slave_IO_Running: Yes`, `Slave_SQL_Running: Yes`, erreurs à zéro et retard nul. Créer ensuite une donnée de test non sensible et vérifier sa présence dans les deux sens.

### Rollback

```sql
STOP SLAVE;
```

Maintenir les conteneurs arrêtés. Restaurer le dump initial si l’import ou la réplication échoue ; ne jamais utiliser `sql_slave_skip_counter` pour masquer un conflit de données sans analyse.

### Validation finale

- [ ] Source de vérité archivée et hashée
- [ ] Deux sens à `Yes/Yes`
- [ ] Aucun `Last_SQL_Error` ni `Last_IO_Error`
- [ ] Test d’écriture bidirectionnel concluant
- [ ] Monitoring réactivé seulement après validation


## Installation de Docker

### Objectif

Installer le moteur Docker et le plugin Compose sur les deux backends.

### Prérequis

Système à jour, architecture ARM64 supportée et politique de paquets choisie. La source exacte des paquets observée sur les backends n’a pas été fournie ; suivre la méthode officielle validée pour l’OS utilisé.

### Commandes

Exemple proche des nœuds en production, qui utilisent encore la commande `docker-compose` appelée par le script de mise à jour :

```bash
sudo apt update
sudo apt install docker.io docker-compose
sudo systemctl enable --now docker
sudo docker version
sudo docker-compose version
```

Ne pas ajouter automatiquement le compte d’exploitation au groupe `docker` : ce groupe confère des privilèges équivalents à root.

### Vérifications

```bash
systemctl is-active docker containerd
sudo docker run --rm hello-world
sudo docker info
```

### Rollback

Arrêter Docker sans supprimer `/var/lib/docker`. Désinstaller les paquets seulement après avoir identifié les volumes et sauvegardé les données nécessaires.

### Validation finale

- [ ] Docker actif au démarrage
- [ ] `docker-compose` disponible pour le script de mise à jour
- [ ] Aucun conteneur de test persistant
- [ ] Accès au socket Docker limité


## Installation de Vaultwarden

### Objectif

Déployer la même version de Vaultwarden sur les deux backends, chacun relié à sa MariaDB locale.

### Prérequis

Docker, MariaDB et les certificats backend disponibles ; clés RSA identiques sur les deux nœuds ; secrets préparés dans un `.env` non versionné.

### Commandes

```bash
sudo install -d -m 750 /opt/vaultwarden /vw-data /ssl/keys
sudo install -m 640 configs/docker/docker-compose.yml \
  /opt/vaultwarden/docker-compose.yml
sudo install -m 600 configs/docker/.env.example /opt/vaultwarden/.env
sudo editor /opt/vaultwarden/.env
cd /opt/vaultwarden
sudo docker-compose config
sudo docker-compose up -d
```

La production actuelle utilisait `vaultwarden/server:1.37.1`, `443:80`, `ROCKET_TLS`, `/vw-data:/data` et `/ssl/keys:/ssl`. Le compose public conserve cette structure mais sort les secrets dans `.env`.

### Vérifications

```bash
sudo docker ps --filter name=vaultwarden
sudo docker inspect vaultwarden \
  --format 'Image={{.Config.Image}} Status={{.State.Status}} Health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}'
curl -k -I --connect-timeout 3 https://10.0.0.1:443/
```

Vérifier que `DOMAIN=https://vaultwarden.example.com` sur les deux nœuds, faute de quoi les jetons peuvent avoir un issuer incohérent.

### Rollback

```bash
cd /opt/vaultwarden
sudo docker-compose down
```

Ne pas supprimer `/vw-data` ni la base. Restaurer l’ancienne image explicitement dans le compose si la nouvelle version échoue.

### Validation finale

- [ ] Même image sur les deux nœuds
- [ ] Conteneurs sains
- [ ] Domaine public identique
- [ ] MariaDB locale utilisée
- [ ] Secrets absents du compose et de Git


## Certificats des backends

### Objectif

Chiffrer le trafic Caddy→Vaultwarden à l’intérieur de WireGuard avec les certificats actuellement attendus par `ROCKET_TLS`.

### Prérequis

OpenSSL installé, répertoire `/ssl/keys` protégé et décision documentée sur l’autorité de confiance. La production actuelle emploie des certificats auto-signés et Caddy désactive leur vérification.

### Commandes

Exemple de génération hors Git :

```bash
sudo openssl req -x509 -newkey rsa:4096 -sha256 -nodes \
  -days 825 \
  -keyout /ssl/keys/key.pem \
  -out /ssl/keys/certs.pem \
  -subj "/CN=10.0.0.1"
sudo chown root:root /ssl/keys/key.pem /ssl/keys/certs.pem
sudo chmod 600 /ssl/keys/key.pem
sudo chmod 644 /ssl/keys/certs.pem
```

Adapter le CN/SAN au nœud. Cette commande est un gabarit, pas une copie d’un certificat réel.

### Vérifications

```bash
sudo openssl x509 -in /ssl/keys/certs.pem -noout \
  -subject -issuer -dates -fingerprint -sha256
sudo stat -c '%a %U:%G %n' /ssl/keys/key.pem /ssl/keys/certs.pem
curl -k -I https://10.0.0.1:443/
```

### Rollback

Restaurer l’ancienne paire depuis le stockage privé et redémarrer le conteneur. Ne jamais committer les clés.

### Validation finale

- [ ] Clé privée en `600`
- [ ] Certificat non expiré
- [ ] Montage `/ssl` visible dans le conteneur
- [ ] Caddy atteint les deux backends


## Installation du monitoring

### Objectif

Installer les contrôles de réplication, de compteurs et de réconciliation sans activer un système incomplet.

### Prérequis

⚠️ Le corpus contient les trois scripts de production et leurs unités, mais pas `common.sh`. L’installation doit rester bloquée tant que ce fichier n’a pas été récupéré depuis une source privée, nettoyé et revu. Les comptes MariaDB de lecture doivent également exister.

### Commandes

Après ajout de la dépendance manquante :

```bash
sudo install -d -m 700 /usr/local/lib/vaultwarden-monitor
sudo install -m 700 scripts/monitoring/*.sh \
  /usr/local/lib/vaultwarden-monitor/
sudo install -m 700 /chemin/prive/common.sh \
  /usr/local/lib/vaultwarden-monitor/common.sh
sudo install -d -m 700 /etc/vaultwarden-monitor
sudo install -m 600 configs/monitoring/.env.example \
  /etc/vaultwarden-monitor/.env
sudo editor /etc/vaultwarden-monitor/.env
```

Installer les unités du bon nœud, recharger systemd, puis tester chaque service manuellement avant d’activer ses timers.

```bash
sudo systemctl daemon-reload
sudo systemctl start vaultwarden-replication-monitor.service
sudo journalctl -u vaultwarden-replication-monitor.service -n 100 --no-pager
```

### Vérifications

- les scripts passent `bash -n` ;
- les mots de passe ne figurent pas dans les arguments de processus ni les logs ;
- le master a `ALLOW_SAFETY_STOP=0` et le slave `1` ;
- le timer de réconciliation est actif uniquement sur le slave.

### Rollback

```bash
sudo systemctl disable --now \
  vaultwarden-replication-monitor.timer \
  vaultwarden-daily-consistency.timer \
  vaultwarden-weekly-reconcile.timer
```

Placer le fichier de maintenance pour empêcher les actions pendant l’analyse.

### Validation finale

- [ ] `common.sh` récupéré et relu
- [ ] Envoi d’un mail de test réussi
- [ ] Contrôle cinq minutes sain
- [ ] Contrôle quotidien sain
- [ ] Réconciliation sans `--apply` saine


## Installation de Caddy

### Objectif

Installer sur `equilihost` le point d’entrée HTTPS et le failover vers les deux backends.

### Prérequis

DNS public prêt, ports 80/443 ouverts vers le VPS, WireGuard opérationnel et backends joignables en HTTPS.

### Commandes

Installer Caddy depuis une source maintenue pour Debian, puis :

```bash
sudo install -m 644 configs/caddy/Caddyfile /etc/caddy/Caddyfile
sudo caddy fmt --overwrite /etc/caddy/Caddyfile
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl enable --now caddy
sudo systemctl reload caddy
```

La version 2.6.2 relevée en août 2026 est un état historique, pas une cible. Valider la version stable choisie en environnement de test avant migration.

### Vérifications

```bash
caddy version
systemctl status caddy --no-pager
curl -I https://vaultwarden.example.com/
sudo journalctl -u caddy -n 100 --no-pager
```

Arrêter temporairement un backend dans une fenêtre de test et confirmer la bascule vers l’autre sans tester une écriture sensible.

### Rollback

Restaurer l’ancien Caddyfile, le valider, puis recharger Caddy. Pour une mise à niveau de paquet, conserver le paquet précédent disponible avant l’intervention.

### Validation finale

- [ ] Certificat public valide
- [ ] Master préféré
- [ ] Bascule vers le slave
- [ ] 503 uniquement lorsque les deux upstreams sont indisponibles
- [ ] Aucun token d’accès présent dans les logs examinés


## Validation du build

### Objectif

Valider l’ensemble de la chaîne avant d’ouvrir le service aux utilisateurs.

### Prérequis

Toutes les étapes précédentes terminées, fenêtre de test et compte Vaultwarden non sensible.

### Commandes

```bash
# Sur les trois nœuds
systemctl --failed --no-pager
sudo wg show

# Sur les backends
sudo systemctl is-active mariadb docker
sudo docker inspect vaultwarden \
  --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}'
sudo mariadb -e "SHOW SLAVE STATUS\G" | grep -E \
  'Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master|Last_.*Error'

# Sur equilihost
sudo caddy validate --config /etc/caddy/Caddyfile
curl -I https://vaultwarden.example.com/
```

Tester successivement : master seul, slave seul, retour du master, création d’une donnée de test, réplication dans les deux sens et notification.

### Vérifications

Le test doit démontrer le chemin complet, pas seulement des services `active`. Vérifier une connexion client, une lecture, une écriture de test et la cohérence après bascule.

### Rollback

Fermer l’accès public ou remettre Caddy sur le dernier backend validé. Arrêter le nœud douteux et conserver les deux bases inchangées pour analyse.

### Validation finale

- [ ] WireGuard OK
- [ ] MariaDB `Yes/Yes` sur les deux nœuds
- [ ] Conteneurs sains
- [ ] Caddy et certificat OK
- [ ] Failover démontré
- [ ] Écriture de test répliquée dans les deux sens
- [ ] Monitoring et e-mail testés
- [ ] Aucun secret ou endpoint public dans Git

## Ordre de remise en production d'un backend reconstruit

Lors d'une reconstruction, l'ordre de mise en service est aussi important que
l'installation elle-même :

1. garder le nouveau backend hors du pool Caddy ;
2. vérifier le système de fichiers, l'heure, le réseau et WireGuard ;
3. restaurer ou initialiser MariaDB depuis une source de référence identifiée ;
4. vérifier les identifiants de réplication (`server_id`, offsets, source attendue) ;
5. lancer la réplication et attendre un état stable ;
6. restaurer `/vw-data` et vérifier en particulier les fichiers hors SQL ;
7. lancer Vaultwarden localement et tester le endpoint ;
8. vérifier le monitoring ;
9. seulement ensuite rendre le backend éligible derrière Caddy.

### Validation finale standard

```bash
sudo wg show
sudo systemctl is-active mariadb docker
sudo mariadb -e "SHOW SLAVE STATUS\\G" | grep -E \
  'Master_Host|Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master|Last_.*Error'
sudo docker inspect vaultwarden \
  --format 'Status={{.State.Status}} Health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}'
```

La validation publique doit ensuite être faite depuis `equilihost`, puis depuis un
client Bitwarden réel.

## Navigation

[← Architecture](01-architecture-et-conception.md) · [Exploitation et maintenance →](03-exploitation-et-maintenance.md)
