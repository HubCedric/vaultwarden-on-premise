# Configuration

## 1. Fichiers

| Fichier | Usage | Secret |
| --- | --- | --- |
| `deploy/node/.env` | variables Compose d'un nœud | oui |
| `deploy/node/config/mariadb/50-server.cnf` | identité et réplication MariaDB | non |
| `deploy/vps/.env` | domaine et upstreams Caddy | partiellement |
| `scripts/.env` | identifiants et chemins d'exploitation | oui |
| `/etc/wireguard/wg0.conf` | clés privées WireGuard | oui |

Tous les fichiers secrets doivent appartenir à root ou à l'administrateur et être en mode `600`.

## 2. Variables du nœud

### Identité

- `COMPOSE_PROJECT_NAME` : unique par machine, par exemple `vaultwarden-a`.
- `WIREGUARD_IP` : adresse locale du nœud sans CIDR, par exemple `10.0.0.1`.
- `TZ` : fuseau horaire, par exemple `Europe/Paris`.

### Images

- `VAULTWARDEN_VERSION` : version explicite, jamais `latest`.
- `MARIADB_VERSION` : même version exacte sur les deux nœuds.

### Vaultwarden

- `DOMAIN` : URL publique complète, par exemple `https://vault.example.net`.
- `DATABASE_URL` : URI MySQL interne vers le service `mariadb`.
- `ADMIN_TOKEN` : hash Argon2, entre quotes simples dans `.env` si la valeur contient `$`.

Les hashes Argon2 contiennent des caractères `$`. Conservez la valeur entière entre apostrophes dans `.env`. Selon la version de Compose, il peut être nécessaire de doubler les `$`. Vérifiez la valeur résolue avec `docker compose --env-file .env config` avant le premier démarrage, sans publier cette sortie car elle révèle le secret.

- `SIGNUPS_ALLOWED` : `false` après création des comptes.
- `INVITATIONS_ALLOWED` : à adapter à l'usage.
- `LOG_LEVEL` : `warn` ou `info` en exploitation.

Un mot de passe inséré dans `DATABASE_URL` doit être URL-encodé. Évitez les caractères réservés ou encodez-les correctement.

### MariaDB

- `MARIADB_DATABASE` : `vaultwarden`.
- `MARIADB_USER` : compte applicatif.
- `MARIADB_PASSWORD` : mot de passe applicatif.
- `MARIADB_ROOT_PASSWORD` : mot de passe root local au conteneur.

Les deux mots de passe doivent être différents.

## 3. Configuration MariaDB

Les fichiers `50-server-node-a.cnf.example` et `50-server-node-b.cnf.example` diffèrent par :

- `server_id` ;
- `auto_increment_offset` ;
- éventuellement le nom du binlog.

Copiez exactement un exemple vers `50-server.cnf` sur chaque nœud.

## 4. Caddy

Variables du VPS :

- `DOMAIN` : nom public ;
- `NODE_A_UPSTREAM` : `10.0.0.1:8080` ;
- `NODE_B_UPSTREAM` : `10.0.0.2:8080` ;
- `ACME_EMAIL` : adresse de contact ACME.

L'ordre des upstreams est significatif. Le premier est prioritaire.

## 5. Scripts

Les scripts utilisent un fichier séparé, car ils contiennent des identifiants d'exploitation et des chemins hôte.

Variables importantes :

- `DEPLOY_DIR` : dossier `deploy/node` ;
- `DEPLOY_ENV_FILE` : fichier `.env` du déploiement ;
- `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` ;
- `VAULTWARDEN_DATA_DIR` ;
- `BACKUP_DIR` ;
- `LOCAL_DB_HOST`, `PEER_HOST` pour la réplication ;
- `MONITOR_USER`, `MONITOR_PASSWORD` ;
- `REPLICATION_AUTO_RESTART` ;
- `REPLICATION_AUTO_RECONFIGURE` désactivé par défaut.

## 6. Secrets

Générez des valeurs aléatoires :

```bash
openssl rand -base64 48
```

Pour le token admin Vaultwarden, utilisez la commande de hash proposée par Vaultwarden dans sa documentation. Ne commitez jamais la valeur brute ni le hash dans Git.

## 7. Validation

```bash
make validate
```

Puis, sur chaque machine :

```bash
docker compose --env-file deploy/node/.env -f deploy/node/compose.yaml config
```
