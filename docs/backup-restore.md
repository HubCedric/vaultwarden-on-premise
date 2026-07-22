# Sauvegarde et restauration

## 1. Périmètre

Une sauvegarde exploitable doit couvrir :

- la base MariaDB ;
- le répertoire persistant Vaultwarden `/data` ;
- les configurations non versionnées ;
- les clés WireGuard ;
- idéalement les données Caddy du VPS.

Le dépôt Git ne contient volontairement aucun secret ni donnée de production.

## 2. Sauvegarde automatisée

```bash
cd /opt/vaultwarden-on-premise/scripts
./backup_vaultwarden.sh
```

Le dump utilise une transaction cohérente et l'archive de données est créée dans le même répertoire horodaté.

### Vérifier le résultat

```bash
find /var/backups/vaultwarden -maxdepth 2 -type f -ls
sha256sum -c /var/backups/vaultwarden/<timestamp>/SHA256SUMS
zgzip_test() { gzip -t "$1"; }
gzip -t /var/backups/vaultwarden/<timestamp>/database.sql.gz
tar -tzf /var/backups/vaultwarden/<timestamp>/vaultwarden-data.tar.gz | head
```

## 3. Rétention

La rétention locale est gérée par `BACKUP_RETENTION_DAYS`. Une stratégie raisonnable :

- 7 à 14 sauvegardes quotidiennes locales ;
- 4 sauvegardes hebdomadaires hors site ;
- plusieurs sauvegardes mensuelles chiffrées.

La destination hors site doit être indépendante des deux nœuds.

## 4. Chiffrement hors site

Utilisez un outil prévu pour le chiffrement et la déduplication, par exemple restic ou borg, avec une clé conservée ailleurs. Ne déposez pas les archives en clair dans un stockage cloud.

## 5. Test de restauration isolé

Ne testez jamais directement sur la production.

1. créer une VM ou un réseau Docker isolé ;
2. copier une sauvegarde ;
3. démarrer une MariaDB vide de même version ;
4. importer le dump ;
5. restaurer `/data` ;
6. démarrer la même version Vaultwarden ;
7. connecter un client de test ;
8. vérifier plusieurs coffres, pièces jointes et organisations.

## 6. Restauration complète d'un nœud

### Arrêter le service

```bash
cd /opt/vaultwarden-on-premise/deploy/node
docker compose --env-file .env down
```

### Préserver l'état cassé

```bash
sudo mv data data.before-restore.$(date +%Y%m%d-%H%M%S)
mkdir -p data/mariadb data/vaultwarden
```

### Restaurer MariaDB

Démarrer uniquement MariaDB :

```bash
docker compose --env-file .env up -d mariadb
```

Attendre le healthcheck, puis importer :

```bash
gunzip -c /path/to/backup/database.sql.gz \
  | docker compose --env-file .env exec -T mariadb \
      mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" vaultwarden
```

Pour éviter d'exposer le mot de passe dans l'historique, préférez une session root ou un fichier temporaire protégé.

### Restaurer `/data`

```bash
tar -xzf /path/to/backup/vaultwarden-data.tar.gz -C data/vaultwarden
```

Vérifiez les propriétaires selon l'image utilisée :

```bash
find data/vaultwarden -maxdepth 2 -ls | head
```

### Redémarrer Vaultwarden

```bash
docker compose --env-file .env up -d
docker compose --env-file .env logs -f vaultwarden
```

## 7. Après restauration dans une architecture répliquée

Ne reconnectez pas immédiatement le nœud restauré à son pair. Une restauration remet une base dans le passé ; la réplication peut rejouer des événements de manière inattendue.

Procédure :

1. isoler MariaDB du pair ;
2. valider l'application localement ;
3. choisir explicitement la source de vérité ;
4. reconstruire le second nœud à partir de cette source ;
5. réinitialiser la réplication ;
6. tester avant remise en rotation.

## 8. Restauration d'une seule donnée

Vaultwarden ne fournit pas ici de procédure SQL supportée pour restaurer un élément individuel. Pour un coffre, privilégiez les fonctions d'export/import côté client. Toute manipulation SQL ciblée doit être testée sur une copie isolée.

## 9. Critères d'une sauvegarde valide

- fichiers non vides ;
- sommes SHA-256 correctes ;
- dump lisible par MariaDB ;
- archive `/data` lisible ;
- version Vaultwarden consignée ;
- date et nœud source consignés ;
- restauration réellement testée.
