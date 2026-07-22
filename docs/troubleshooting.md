# Dépannage

## 1. Diagnostic rapide

```bash
scripts/healthcheck.sh
docker compose -f deploy/node/compose.yaml --env-file deploy/node/.env ps
docker compose -f deploy/node/compose.yaml --env-file deploy/node/.env logs --tail 200 vaultwarden mariadb
sudo wg show
```

## 2. Vaultwarden ne démarre pas

### Vérifier la base

```bash
MYSQL_PWD='...' mariadb -h 10.0.0.1 -P 3306 -u vaultwarden -e 'SELECT 1;'
```

### Vérifier `DATABASE_URL`

Le mot de passe doit être URL-encodé. Une valeur contenant `@`, `:`, `/`, `#` ou `%` peut casser l'URI.

### Vérifier les permissions `/data`

```bash
ls -la deploy/node/data/vaultwarden
docker compose -f deploy/node/compose.yaml --env-file deploy/node/.env logs vaultwarden
```

## 3. Le coffre Web charge sans fin

- vérifier HTTPS public ;
- vérifier `DOMAIN` ;
- vérifier les erreurs de navigateur ;
- vérifier Caddy ;
- tester `/alive` depuis le VPS vers chaque nœud.

```bash
curl -v http://10.0.0.1:8080/alive
curl -v http://10.0.0.2:8080/alive
```

## 4. Caddy renvoie 502/503

```bash
sudo wg show
nc -zv 10.0.0.1 8080
nc -zv 10.0.0.2 8080
docker compose -f deploy/vps/compose.yaml --env-file deploy/vps/.env logs --tail 200 caddy
```

Vérifiez l'ordre et la syntaxe des upstreams. Caddy ne peut basculer que vers un nœud joignable et déclaré sain.

## 5. MariaDB ne démarre pas

```bash
docker compose -f deploy/node/compose.yaml --env-file deploy/node/.env logs --tail 300 mariadb
df -h
df -i
ls -la deploy/node/data/mariadb
```

Causes fréquentes :

- configuration `.cnf` invalide ;
- identifiant `server_id` dupliqué ;
- disque plein ;
- permissions du volume ;
- changement de version majeur sans procédure d'upgrade.

## 6. Réplication arrêtée

```sql
SHOW SLAVE STATUS\G
```

### IO arrêté, SQL sain

Vérifiez :

- WireGuard ;
- pare-feu ;
- port 3306 ;
- compte `repl` ;
- mot de passe ;
- binlogs disponibles.

### SQL arrêté avec erreur

Ne sautez pas automatiquement l'événement. Sauvegardez les deux bases et analysez `Last_SQL_Errno` et `Last_SQL_Error`.

### `SHOW SLAVE STATUS` vide

Cela signifie que la connexion de réplication n'est pas configurée sur ce nœud. Cela ne doit pas être confondu avec une erreur de connexion au serveur MariaDB lui-même.

## 7. Erreur de clé étrangère lors d'une migration

Inspectez :

- types exacts des colonnes référencées ;
- longueur et collation ;
- index complets ;
- schéma identique sur les deux nœuds.

```sql
SHOW CREATE TABLE users\G
SHOW CREATE TABLE ciphers\G
```

Le retour d'expérience historique a identifié des colonnes UUID converties en `TEXT`. Consultez [Migration SQLite vers MariaDB](migration-sqlite-mariadb.md).

## 8. Mise à jour en échec

Le script remet l'ancienne version dans le fichier `.env` et redéploie. Consultez :

```bash
tail -n 300 /var/log/vaultwarden-update.log
docker compose -f deploy/node/compose.yaml --env-file deploy/node/.env logs --tail 300 vaultwarden
```

Si le schéma a été modifié, restaurez sur une copie et comparez avant toute action sur la production.

## 9. Le nœud B manque des pièces jointes

La réplication MariaDB ne couvre pas `/data`. Vérifiez la stratégie de copie de fichiers et la date du dernier backup. Ne lancez pas une synchronisation bidirectionnelle sans connaître le sens de vérité.

## 10. Collecte d'informations

Avant intervention risquée, collectez :

```bash
date -Is
docker version
docker compose version
docker compose -f deploy/node/compose.yaml --env-file deploy/node/.env ps
sudo wg show
scripts/healthcheck.sh
```

Masquez tous les secrets avant partage.
