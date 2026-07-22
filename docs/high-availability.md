# Haute disponibilité

## 1. Positionnement

Cette architecture améliore la disponibilité d'un service personnel, mais reste une solution avancée et expérimentale. Deux nœuds MariaDB en réplication asynchrone ne fournissent pas de consensus.

La stratégie retenue est :

- réplication dual-primary pour permettre les écritures après basculement ;
- routage actif/passif pour éviter les écritures simultanées en fonctionnement normal ;
- intervention humaine après un incident réseau ou un basculement prolongé.

## 2. Prérequis

- mêmes versions MariaDB ;
- horloges synchronisées ;
- adresses WireGuard fixes ;
- ports 3306 autorisés uniquement entre A et B ;
- base et schéma identiques ;
- sauvegarde complète avant initialisation ;
- un compte de réplication dédié ;
- un compte de supervision en lecture du statut.

## 3. Configuration des nœuds

Sur A :

```bash
cp deploy/node/config/mariadb/50-server-node-a.cnf.example \
   deploy/node/config/mariadb/50-server.cnf
```

Sur B :

```bash
cp deploy/node/config/mariadb/50-server-node-b.cnf.example \
   deploy/node/config/mariadb/50-server.cnf
```

Redémarrez MariaDB après modification.

## 4. Comptes SQL

Adaptez puis exécutez [`config/mariadb/bootstrap.sql.example`](../config/mariadb/bootstrap.sql.example) sur chaque nœud.

Le compte de réplication doit être limité aux adresses WireGuard du pair. Le compte de supervision local peut recevoir le privilège nécessaire au redémarrage des threads, mais le compte distant ne doit lire que le statut.

## 5. Initialisation depuis une source de vérité

Choisissez A comme source initiale.

### Sauvegarder A

```bash
scripts/backup_vaultwarden.sh
```

### Aligner B

Arrêtez Vaultwarden B, restaurez la base de A sur B et copiez le répertoire `/data` nécessaire. Les deux bases doivent être identiques avant de créer la boucle de réplication.

### Configurer B depuis A

Sur B :

```sql
STOP SLAVE;
RESET SLAVE ALL;
CHANGE MASTER TO
  MASTER_HOST='10.0.0.1',
  MASTER_PORT=3306,
  MASTER_USER='repl',
  MASTER_PASSWORD='CHANGE_ME',
  MASTER_USE_GTID=slave_pos;
START SLAVE;
```

### Configurer A depuis B

Sur A :

```sql
STOP SLAVE;
RESET SLAVE ALL;
CHANGE MASTER TO
  MASTER_HOST='10.0.0.2',
  MASTER_PORT=3306,
  MASTER_USER='repl',
  MASTER_PASSWORD='CHANGE_ME',
  MASTER_USE_GTID=slave_pos;
START SLAVE;
```

## 6. Vérification

Sur les deux nœuds :

```sql
SHOW SLAVE STATUS\G
SELECT @@global.gtid_binlog_pos, @@global.gtid_slave_pos;
```

Attendus :

- `Slave_IO_Running: Yes` ;
- `Slave_SQL_Running: Yes` ;
- `Last_SQL_Errno: 0` ;
- `Seconds_Behind_Master` faible ou nul.

Testez une écriture contrôlée sur A et vérifiez sa présence sur B. Ne testez pas en produisant simultanément des écritures des deux côtés.

## 7. Caddy actif/passif

Le Caddyfile fourni déclare A avant B :

```caddyfile
reverse_proxy {$NODE_A_UPSTREAM} {$NODE_B_UPSTREAM} {
    lb_policy first
    health_uri /alive
}
```

Le healthcheck applicatif ne garantit pas la santé de la réplication. Un nœud peut répondre `/alive` tout en ayant une base divergente. Après un incident, utilisez le pare-feu, l'arrêt du conteneur ou la configuration Caddy pour empêcher sa remise en rotation automatique.

## 8. Surveillance

Installez le script sur les deux nœuds avec des variables inversées :

```bash
scripts/check_replication.sh
```

Valeurs recommandées :

```dotenv
REPLICATION_AUTO_RESTART=1
REPLICATION_AUTO_RECONFIGURE=0
SECONDS_BEHIND_THRESHOLD=60
```

La reconfiguration automatique est désactivée par défaut car un `SHOW SLAVE STATUS` vide après incident peut nécessiter une analyse plus large.

## 9. Split-brain

Signes :

- thread SQL arrêté sur doublon ou clé étrangère ;
- écritures récentes différentes sur A et B ;
- GTID incompatibles ;
- deux nœuds ont servi le trafic pendant une partition.

Actions immédiates :

1. arrêter les écritures sur un nœud ;
2. sauvegarder les deux bases séparément ;
3. ne pas utiliser `sql_slave_skip_counter` sur des tables métier ;
4. comparer les données ;
5. choisir ou reconstruire une source de vérité ;
6. réinitialiser la réplication seulement après réconciliation.

L'outil historique de comparaison se trouve dans `scripts/experimental/reconcile_split_brain.sh`. Lisez son code et exécutez-le d'abord sans `--apply`.

## 10. Limite du volume `/data`

La réplication MariaDB ne synchronise pas les pièces jointes et autres fichiers du volume Vaultwarden. Pour une vraie reprise sur B, mettez en place une réplication de fichiers soigneusement contrôlée ou restaurez le volume depuis une sauvegarde récente. Une synchronisation bidirectionnelle naïve peut elle aussi créer des conflits.
