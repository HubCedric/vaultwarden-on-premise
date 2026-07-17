# Haute disponibilité

## Objectif

L'objectif de cette architecture est de maintenir l'accès à Vaultwarden même en cas d'indisponibilité d'un des serveurs.

Dans un contexte d'auto-hébergement, une panne matérielle, une coupure Internet prolongée ou un incident système peut rendre le coffre inaccessible. Pour un gestionnaire de mots de passe, cette situation est particulièrement problématique.

La solution retenue repose sur :

- deux serveurs Vaultwarden ;
- deux bases MariaDB synchronisées ;
- un tunnel WireGuard entre les différents nœuds ;
- un VPS public servant de point d'entrée ;
- un reverse proxy chargé de basculer vers le nœud disponible.

---

## Principe de fonctionnement

L'utilisateur se connecte toujours au même domaine public.

La requête arrive sur le VPS, qui joue le rôle de reverse proxy. Le trafic est ensuite transmis via WireGuard vers l'un des deux serveurs Vaultwarden.

Chaque serveur Vaultwarden dispose de sa propre base MariaDB locale. Les deux bases sont synchronisées au moyen d'une réplication MariaDB master-master.

```text
                    Internet
                       |
                       |
                  VPS + Caddy
                       |
                 Tunnel WireGuard
                       |
        +--------------+--------------+
        |                             |
  Vaultwarden A                 Vaultwarden B
        |                             |
    MariaDB A  <==============>  MariaDB B
             Réplication
             master-master
```

Cette architecture permet :

- de ne pas exposer directement les serveurs privés ;
- de conserver une copie locale des données sur chaque nœud ;
- d'assurer un basculement applicatif si un serveur devient indisponible ;
- d'améliorer la résilience globale du service.

---

## Prérequis

Avant de mettre en place la haute disponibilité, les éléments suivants doivent être disponibles :

- un VPS public joignable depuis Internet ;
- deux serveurs privés capables d'héberger Vaultwarden ;
- une connectivité réseau entre les trois machines ;
- WireGuard, MariaDB et Docker installables sur les serveurs ;
- une installation Vaultwarden fonctionnelle au moins sur un premier nœud ;
- des adresses IP fixes ou stables pour les trois machines ;
- un pare-feu maîtrisé sur chaque hôte.

Il est fortement recommandé que les deux serveurs Vaultwarden soient configurés de manière aussi proche que possible afin de simplifier l'exploitation.

---

## Hypothèses d'adressage

Les exemples de cette documentation reposent sur le plan d'adressage suivant :

```text
Serveur Vaultwarden A : 10.0.0.1
Serveur Vaultwarden B : 10.0.0.2
VPS : 10.0.0.10
Port MariaDB : 3306
Port WireGuard : 51820
```

Les adresses publiques réelles, les noms d'interface et les clés devront être adaptés à l'environnement cible.

---

## Mise en place du tunnel WireGuard

Les trois machines doivent communiquer sur un réseau privé dédié.

### Installation

Sur les trois serveurs :

```bash
sudo apt update
sudo apt install wireguard -y
```

Sur certaines distributions, l'installation de `resolvconf` peut également être nécessaire :

```bash
sudo apt install resolvconf -y
```

### Génération des clés

Sur chaque machine, générer une paire de clés :

```bash
wg genkey | tee privatekey | wg pubkey > publickey
```

Conserver soigneusement :

- la clé privée locale ;
- la clé publique locale ;
- les clés publiques des pairs.

### Configuration du serveur Vaultwarden A

Créer le fichier `/etc/wireguard/wg0.conf` :

```ini
[Interface]
Address = 10.0.0.1/32
ListenPort = 51820
PrivateKey = CLE_PRIVEE_A

[Peer]
PublicKey = CLE_PUBLIQUE_B
AllowedIPs = 10.0.0.2/32
Endpoint = IP_PUBLIQUE_OU_IPV6_B:51820
PersistentKeepalive = 25

[Peer]
PublicKey = CLE_PUBLIQUE_VPS
AllowedIPs = 10.0.0.10/32
Endpoint = IP_PUBLIQUE_OU_IPV6_VPS:51820
PersistentKeepalive = 25
```

### Configuration du serveur Vaultwarden B

Créer le fichier `/etc/wireguard/wg0.conf` :

```ini
[Interface]
Address = 10.0.0.2/32
ListenPort = 51820
PrivateKey = CLE_PRIVEE_B

[Peer]
PublicKey = CLE_PUBLIQUE_A
AllowedIPs = 10.0.0.1/32
Endpoint = IP_PUBLIQUE_OU_IPV6_A:51820
PersistentKeepalive = 25

[Peer]
PublicKey = CLE_PUBLIQUE_VPS
AllowedIPs = 10.0.0.10/32
Endpoint = IP_PUBLIQUE_OU_IPV6_VPS:51820
PersistentKeepalive = 25
```

### Configuration du VPS

Créer le fichier `/etc/wireguard/wg0.conf` :

```ini
[Interface]
Address = 10.0.0.10/32
ListenPort = 51820
PrivateKey = CLE_PRIVEE_VPS

[Peer]
PublicKey = CLE_PUBLIQUE_A
AllowedIPs = 10.0.0.1/32
Endpoint = IP_PUBLIQUE_OU_IPV6_A:51820
PersistentKeepalive = 25

[Peer]
PublicKey = CLE_PUBLIQUE_B
AllowedIPs = 10.0.0.2/32
Endpoint = IP_PUBLIQUE_OU_IPV6_B:51820
PersistentKeepalive = 25
```

### Démarrage

Sur les trois machines :

```bash
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
sudo systemctl status wg-quick@wg0
```

### Vérification

Vérifier que l'interface `wg0` est présente :

```bash
ip a
```

Tester ensuite la connectivité :

```bash
ping 10.0.0.1
ping 10.0.0.2
ping 10.0.0.10
```

Une fois cette étape validée, l'ensemble des échanges internes peut transiter par le réseau privé WireGuard.

---

## Migration SQLite vers MariaDB

Par défaut, Vaultwarden utilise SQLite. Cette base convient à une instance simple, mais elle n'est pas adaptée à une réplication inter-serveurs.

L'objectif est donc de migrer les données vers MariaDB afin de permettre une synchronisation entre les deux nœuds.

### Installation des paquets nécessaires

Sur le serveur source :

```bash
sudo apt update
sudo apt install mariadb-server python3 python3-pip -y
sudo python3 -m pip install sqlite3-to-mysql --break-system-packages
```

### Import depuis SQLite

Depuis le répertoire contenant `db.sqlite3` :

```bash
sqlite3mysql -f db.sqlite3 -d vaultwarden -u vaultwarden -p -X -i IGNORE
```

Cette opération n'a besoin d'être réalisée qu'une seule fois sur le premier serveur. La réplication MariaDB se chargera ensuite de transmettre les données vers le second nœud.

---

## Mise en place de MariaDB sur les deux serveurs

Les deux serveurs doivent exécuter MariaDB avec une configuration compatible avec la réplication master-master.

### Installation

Sur les deux serveurs :

```bash
sudo apt update
sudo apt install mariadb-server -y
```

### Configuration du serveur A

Éditer le fichier MariaDB, généralement `/etc/mysql/mariadb.conf.d/50-server.cnf` :

```ini
[mysqld]
server-id = 1
log_bin = mysql-bin
binlog_format = ROW
bind-address = 0.0.0.0
auto_increment_increment = 2
auto_increment_offset = 1
skip-name-resolve
```

### Configuration du serveur B

```ini
[mysqld]
server-id = 2
log_bin = mysql-bin
binlog_format = ROW
bind-address = 0.0.0.0
auto_increment_increment = 2
auto_increment_offset = 2
skip-name-resolve
```

Redémarrer MariaDB sur les deux serveurs :

```bash
sudo systemctl restart mariadb
```

### Création de l'utilisateur de réplication

Sur les deux serveurs :

```sql
CREATE USER 'repli'@'%' IDENTIFIED BY 'mot_de_passe_repli';
GRANT REPLICATION SLAVE ON *.* TO 'repli'@'%';
FLUSH PRIVILEGES;
```

### Ouverture du pare-feu

Autoriser le port 3306 entre les deux nœuds sur le réseau WireGuard uniquement.

Exemple avec UFW sur le serveur A :

```bash
sudo ufw allow from 10.0.0.2 to any port 3306 proto tcp
```

Exemple sur le serveur B :

```bash
sudo ufw allow from 10.0.0.1 to any port 3306 proto tcp
```

### Configuration de la réplication sur le serveur A

```sql
CHANGE MASTER TO
  MASTER_HOST='10.0.0.2',
  MASTER_USER='repli',
  MASTER_PASSWORD='mot_de_passe_repli',
  MASTER_PORT=3306,
  MASTER_USE_GTID=slave_pos;
START SLAVE;
```

### Configuration de la réplication sur le serveur B

```sql
CHANGE MASTER TO
  MASTER_HOST='10.0.0.1',
  MASTER_USER='repli',
  MASTER_PASSWORD='mot_de_passe_repli',
  MASTER_PORT=3306,
  MASTER_USE_GTID=slave_pos;
START SLAVE;
```

### Vérification

Sur les deux serveurs :

```sql
SHOW SLAVE STATUS\G
```

Les champs suivants doivent être surveillés :

- `Slave_IO_Running: Yes`
- `Slave_SQL_Running: Yes`
- `Last_Errno: 0`

---

## Configuration de Vaultwarden avec MariaDB

Une fois MariaDB opérationnelle, Vaultwarden doit être configuré pour utiliser cette base au lieu de SQLite.

Exemple de variable d'environnement :

```env
DATABASE_URL=mysql://vaultwarden:mot_de_passe_fort@127.0.0.1:3306/vaultwarden
```

Si l'application tourne via Docker Compose, cette variable doit être injectée dans le service Vaultwarden.

Exemple simplifié :

```yaml
services:
  vaultwarden:
    image: vaultwarden/server:1.36.0
    container_name: vaultwarden
    restart: always
    ports:
      - "443:80"
    environment:
      DATABASE_URL: "mysql://vaultwarden:mot_de_passe_fort@127.0.0.1:3306/vaultwarden"
      ADMIN_TOKEN: "xxxxxxxxxx"
      ROCKET_TLS: '{certs="/ssl/certs.pem",key="/ssl/key.pem"}'
      DOMAIN: "https://bitwarden.domaine.fr"
    volumes:
      - /vw-data:/data
      - /ssl/keys/:/ssl/
```

Cette configuration doit être reproduite sur les deux nœuds.

---

## Mise en place du reverse proxy sur le VPS

Le VPS constitue le point d'entrée unique de l'infrastructure.

L'idée est de faire pointer le domaine public vers le VPS, puis de laisser Caddy transmettre les requêtes vers les serveurs Vaultwarden via WireGuard.

### Exemple de Caddyfile

```caddy
bitwarden.domaine.fr {
    header {
        X-Content-Type-Options "nosniff"
        Referrer-Policy "no-referrer"
        X-Frame-Options "SAMEORIGIN"
        X-Xss-Protection "1; mode=block"
        X-Robots-Tag "noindex, noarchive, nofollow"
        -X-Powered-By
    }

    reverse_proxy https://10.0.0.1:443 https://10.0.0.2:443 {
        lb_policy first
        lb_try_duration 5s
        lb_try_interval 250ms

        transport http {
            tls_insecure_skip_verify
        }

        health_path /
        health_interval 5s
        health_timeout 2s

        header_up X-Real-IP {remote_host}
    }
}
```

Cette configuration doit être adaptée à la manière dont Vaultwarden est exposé sur les nœuds internes.

Le point important est le suivant : le contrôle d'état doit vérifier un endpoint applicatif pertinent, et pas seulement la joignabilité réseau du serveur.

---

## Vérification du basculement

Une fois l'ensemble de la chaîne en place, il est nécessaire de tester le fonctionnement réel de la haute disponibilité.

### Vérifications minimales

- accéder au domaine public et confirmer que Vaultwarden répond ;
- arrêter Vaultwarden sur un des deux nœuds ;
- vérifier que le trafic est bien redirigé vers l'autre nœud ;
- relancer le nœud arrêté ;
- vérifier qu'il réintègre correctement l'infrastructure ;
- contrôler l'état de la réplication MariaDB après le test.

### Exemples utiles

Sur un nœud Vaultwarden :

```bash
sudo docker ps
sudo docker logs vaultwarden
sudo docker restart vaultwarden
```

Sur le VPS :

```bash
curl -vk https://10.0.0.1:443/alive
curl -vk https://10.0.0.2:443/alive
```

L'objectif est de vérifier que le nœud est réellement fonctionnel côté application et pas seulement accessible côté réseau.

---

## Surveillance de la réplication

Une réplication master-master peut se casser silencieusement.

Dans ce type d'infrastructure, il est indispensable de surveiller régulièrement :

- l'état des threads de réplication ;
- la présence éventuelle d'erreurs SQL ;
- la latence de réplication ;
- la connectivité réseau entre les nœuds ;
- l'état du port 3306 sur chaque serveur.

### Vérifications manuelles utiles

Sur chaque nœud :

```sql
SHOW SLAVE STATUS\G
```

Depuis un serveur vers son pair :

```bash
ping 10.0.0.2
nc -zv -w5 10.0.0.2 3306
mysql -h 10.0.0.2 -P 3306 -u repli -p -e "SELECT 1;"
```

Ces tests permettent de distinguer un problème MariaDB d'un problème réseau ou pare-feu.

---

## Correction automatique encadrée

Une surveillance automatisée peut être mise en place pour détecter certains cas simples :

- thread arrêté sans conflit de données ;
- perte de configuration de réplication ;
- reprise réseau après coupure temporaire.

En revanche, un conflit SQL réel ou une divergence de données ne doit pas être corrigé automatiquement sans validation.

Les actions automatisables peuvent inclure :

```sql
STOP SLAVE;
START SLAVE;
```

ou une reconfiguration contrôlée :

```sql
CHANGE MASTER TO
  MASTER_HOST='IP_DU_PAIR',
  MASTER_USER='repli',
  MASTER_PASSWORD='mot_de_passe_repli',
  MASTER_PORT=3306,
  MASTER_USE_GTID=slave_pos;
START SLAVE;
```

Toute automatisation doit être accompagnée de logs exploitables et, idéalement, d'une alerte.

---

## Récupération après réplication cassée durablement

Lorsqu'une réplication est restée cassée longtemps, il ne faut pas supposer qu'un des deux serveurs contient forcément la vérité complète.

Les deux nœuds peuvent avoir continué à accepter des écritures différentes. On se retrouve alors dans une situation de divergence réelle, parfois assimilable à un split-brain applicatif.

### 1. Vérifier la connectivité

Avant d'accuser MariaDB, vérifier que les deux serveurs peuvent réellement communiquer :

```bash
ping 10.0.0.1
ping 10.0.0.2
nc -zv -w5 10.0.0.1 3306
nc -zv -w5 10.0.0.2 3306
```

Un pare-feu mal configuré sur le port 3306 suffit à casser durablement la réplication.

### 2. Quantifier la divergence

Avant toute relance de réplication, il faut comparer les données présentes de part et d'autre.

L'objectif est d'identifier :

- les éléments présents sur un seul nœud ;
- les enregistrements modifiés différemment ;
- les éventuels conflits sur les objets critiques.

Cette étape doit être faite avec prudence. Tant que les deux jeux de données n'ont pas été réconciliés, relancer la réplication peut empirer la situation.

### 3. Corriger les écarts de schéma

Si les deux bases n'ont pas exactement le même schéma, la réplication se cassera de nouveau immédiatement.

Il faut donc vérifier les colonnes, types et contraintes avant de repartir.

### 4. Réinitialiser proprement la réplication

Une fois les données réconciliées et les schémas alignés, repartir sur une réplication propre.

Sur chaque serveur :

```sql
STOP SLAVE;
RESET SLAVE ALL;
RESET MASTER;
```

Puis reconfigurer la réplication vers le pair :

```sql
CHANGE MASTER TO
  MASTER_HOST='IP_DU_PAIR',
  MASTER_USER='repli',
  MASTER_PASSWORD='mot_de_passe_repli',
  MASTER_PORT=3306,
  MASTER_USE_GTID=slave_pos;
START SLAVE;
```

### 5. Vérifier l'état final

Sur les deux serveurs :

```sql
SHOW SLAVE STATUS\G
```

Les deux threads doivent être actifs et aucune erreur SQL ne doit subsister.

---

## Points d'attention

Cette architecture améliore fortement la disponibilité, mais elle ne remplace pas les bonnes pratiques d'exploitation.

Les points suivants restent indispensables :

- sauvegardes régulières ;
- tests de restauration ;
- supervision ;
- validation des mises à jour ;
- contrôle de la réplication ;
- documentation des procédures d'incident.

La réplication n'est pas une sauvegarde. Une erreur logique ou une suppression peut être répliquée sur les deux nœuds.

---

## Synthèse

La haute disponibilité de cette infrastructure repose sur l'association de plusieurs mécanismes :

| Élément | Rôle |
| --- | --- |
| Deux instances Vaultwarden | Continuité applicative |
| Deux bases MariaDB locales | Copie locale complète sur chaque nœud |
| Réplication MariaDB master-master | Synchronisation inter-serveurs |
| WireGuard | Réseau privé chiffré |
| VPS | Point d'entrée public unique |
| Caddy | Reverse proxy et basculement |

Cette organisation permet de maintenir un service Vaultwarden auto-hébergé plus résilient qu'une installation simple sur un seul serveur, à condition de surveiller activement la réplication et de maîtriser les procédures de reprise.
