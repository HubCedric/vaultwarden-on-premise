# Debug

## Objectif

Ce document regroupe les éléments de diagnostic et de correction pour les incidents techniques rencontrés sur cette infrastructure Vaultwarden.

Il couvre en particulier :

- les problèmes de réplication MariaDB ;
- les incohérences de schéma entre les deux nœuds ;
- les erreurs provoquées par certaines migrations ou conversions de colonnes ;
- les cas où un downgrade de version peut être nécessaire.

L'objectif est de conserver une documentation orientée exploitation, avec des vérifications concrètes et des actions reproductibles.

---

## Principes de diagnostic

Avant de corriger un incident, il faut d'abord identifier précisément sa nature.

Un problème visible côté application peut en réalité venir :

- du conteneur Vaultwarden ;
- de MariaDB ;
- de la réplication ;
- d'un schéma incohérent ;
- d'une migration partiellement appliquée ;
- d'un problème réseau ou pare-feu.

Avant toute modification, il est recommandé de :

- lire les logs applicatifs ;
- vérifier l'état de MariaDB ;
- contrôler la réplication ;
- comparer les schémas si une table précise est mentionnée dans les erreurs ;
- éviter les corrections destructrices tant que la cause n'est pas clairement identifiée.

---

## Commandes de base

### État du conteneur

```bash
sudo docker ps
sudo docker logs vaultwarden
```

### État de MariaDB

```bash
sudo systemctl status mariadb
sudo journalctl -u mariadb --no-pager -n 100
```

### État de la réplication

```sql
SHOW SLAVE STATUS\G
```

Points à vérifier en priorité :

- `Slave_IO_Running`
- `Slave_SQL_Running`
- `Last_Errno`
- `Last_SQL_Error`

### Connectivité réseau

```bash
ping 10.0.0.1
ping 10.0.0.2
nc -zv -w5 10.0.0.1 3306
nc -zv -w5 10.0.0.2 3306
mysql -h 10.0.0.2 -P 3306 -u repli -p -e "SELECT 1;"
```

Ces contrôles permettent de distinguer rapidement :

- une panne réseau ;
- un blocage firewall ;
- une panne MariaDB ;
- une simple rupture de réplication.

---

## Incident réel : réplication cassée silencieusement

Un incident rencontré en production a montré qu'une réplication master-master peut se casser sans symptôme immédiat côté application [file:1].

Dans le cas observé, les deux serveurs ont continué à fonctionner alors que la réplication était rompue, ce qui a provoqué une divergence réelle des données entre les deux bases, et pas seulement un retard de synchronisation [file:1].

La cause initiale n'était pas MariaDB elle-même, mais un problème de connectivité réseau : un pare-feu `ufw` n'autorisait pas les connexions entrantes sur le port 3306 depuis l'IP VPN du pair dans un sens, alors que la réplication avait besoin d'un accès bidirectionnel [file:1].

### Vérifications recommandées

Avant d'accuser MariaDB, vérifier systématiquement :

```bash
ping 10.0.0.1
ping 10.0.0.2
nc -zv -w5 10.0.0.1 3306
nc -zv -w5 10.0.0.2 3306
mysql -h 10.0.0.2 -P 3306 -u repli -p -e "SELECT 1;"
```

### Point d'attention sur les comptes MariaDB

Il faut également faire attention au comportement de `localhost` et `127.0.0.1` dans MariaDB.

Selon la façon dont le client `mysql` se connecte, une connexion locale peut être vue par MariaDB comme :

- `localhost` ;
- ou `127.0.0.1`.

Pour éviter toute ambiguïté, les comptes techniques utilisés par les scripts doivent être créés explicitement pour les deux cas lorsque nécessaire [file:1].

---

## Root cause : colonnes `uuid` / `id` converties en `TEXT` au lieu de `VARCHAR(36)`

Un problème rencontré lors des manipulations autour de la base a conduit à une incohérence de schéma : certaines colonnes `uuid` ou `id` ont été converties en `TEXT` alors qu'elles devaient rester en `VARCHAR(36)` [file:1].

Cette différence de type peut sembler bénigne, mais elle est en réalité bloquante pour la réplication dès qu'un événement SQL touche la table concernée [file:1].

### Pourquoi c'est un problème

Dans une base Vaultwarden, plusieurs tables métier reposent sur des identifiants UUID.

Lorsque ces colonnes ne sont plus du même type sur les deux serveurs, on introduit une dérive de schéma qui peut provoquer :

- des erreurs SQL pendant la réplication ;
- des différences de comportement selon les index ou contraintes ;
- des conflits lors des migrations ;
- une impossibilité de reprendre correctement la réplication tant que les schémas ne sont pas réalignés.

### Symptômes possibles

Les symptômes peuvent inclure :

- réplication qui casse à la première modification sur une table donnée ;
- erreur SQL dans `SHOW SLAVE STATUS\G` ;
- schéma différent entre les deux nœuds ;
- comportement incohérent lors de mises à jour ou migrations.

---

## Vérifier le type réel des colonnes

Pour inspecter la structure d'une table :

```sql
SHOW CREATE TABLE users\G
SHOW CREATE TABLE devices\G
SHOW CREATE TABLE ciphers\G
SHOW CREATE TABLE folders\G
SHOW CREATE TABLE folders_ciphers\G
```

Pour une vue plus ciblée :

```sql
SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_KEY
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'vaultwarden'
  AND TABLE_NAME = 'users';
```

Même principe pour les autres tables :

```sql
SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_KEY
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'vaultwarden'
  AND TABLE_NAME = 'devices';
```

L'objectif est de comparer les deux serveurs et de confirmer que les colonnes sensibles ont bien le même type partout.

---

## Corriger un schéma incohérent

Si une colonne `uuid` ou `id` a été transformée en `TEXT` au lieu de `VARCHAR(36)`, il faut réaligner le schéma avant toute tentative de reprise durable de la réplication [file:1].

### Précautions

Avant toute modification :

- faire un dump de la base ;
- arrêter les écritures si possible ;
- comparer les deux schémas ;
- identifier quel schéma doit devenir la référence.

### Sauvegarde préalable

```bash
mysqldump -u root -p vaultwarden > vaultwarden-before-schema-fix.sql
```

### Exemple de correction

Le type exact à appliquer dépend de la table et de la structure attendue, mais l'idée générale est de remettre la colonne dans son type nominal.

Exemple générique :

```sql
ALTER TABLE users MODIFY COLUMN uuid VARCHAR(36) NOT NULL;
```

Ou :

```sql
ALTER TABLE ciphers MODIFY COLUMN uuid VARCHAR(36) NOT NULL;
```

Le même principe s'applique aux colonnes `id` si elles ont subi la même dérive.

### Important

Ne pas appliquer une correction au hasard sur un seul nœud puis relancer immédiatement la réplication.

Il faut d'abord :

1. vérifier la structure cible correcte ;
2. aligner les deux serveurs ;
3. confirmer l'absence d'autres dérives ;
4. seulement ensuite reprendre ou reconstruire la réplication.

---

## Vérifier les différences de schéma entre les deux serveurs

Lorsqu'une réplication casse de manière répétée sur une table précise, il faut comparer explicitement le schéma des deux côtés [file:1].

### Méthode

Sur chaque serveur :

```sql
SHOW CREATE TABLE users\G
SHOW CREATE TABLE devices\G
SHOW CREATE TABLE ciphers\G
SHOW CREATE TABLE folders\G
SHOW CREATE TABLE folders_ciphers\G
```

Comparer ensuite :

- le type exact des colonnes ;
- les index ;
- les clés primaires ;
- les contraintes ;
- les colonnes ajoutées par migration ;
- l'ordre global du schéma si nécessaire.

### Règle

Une réplication ne doit jamais être relancée durablement tant qu'un doute existe sur l'identité structurelle des deux bases.

---

## Erreurs liées aux migrations déjà appliquées

Même après réconciliation des données, certaines erreurs peuvent encore survenir lors de la reprise de la réplication, notamment si les deux nœuds ont déjà appliqué des migrations identiques dans des historiques différents [file:1].

Les symptômes typiques sont :

- `Duplicate entry`
- `Duplicate column name`

Ces erreurs peuvent concerner :

- des tables internes liées aux migrations ;
- des changements de schéma déjà appliqués des deux côtés ;
- des événements SQL rejoués alors qu'ils n'ont plus d'effet utile.

### Cas bénins possibles

Dans certains cas précis, il peut être acceptable de sauter un événement de réplication, mais uniquement si l'analyse montre qu'il ne touche pas à des données métier réelles [file:1].

Exemple :

```sql
STOP SLAVE;
SET GLOBAL sql_slave_skip_counter = 1;
START SLAVE;
```

### Limites

Cette méthode ne doit jamais être utilisée à l'aveugle sur des tables comme :

- `users`
- `ciphers`
- `folders`
- `devices`

Elle n'est acceptable que lorsque le conflit est clairement identifié comme bénin, par exemple sur une migration déjà appliquée ou une table interne de suivi [file:1].

---

## Cas de figure : `SHOW SLAVE STATUS` ne retourne rien

Si `SHOW SLAVE STATUS\G` ne retourne aucune ligne, cela signifie généralement que la configuration de réplication n'existe plus sur le nœud concerné [file:1].

Cela peut arriver par exemple après un `RESET SLAVE ALL`.

### Interprétation

Deux cas sont possibles :

- le nœud avait déjà été répliqué auparavant et possède encore une position de reprise exploitable ;
- le nœud n'a plus aucune information exploitable de reprise.

Dans le premier cas, une reconfiguration contrôlée via GTID peut suffire [file:1].

### Exemple

```sql
CHANGE MASTER TO
  MASTER_HOST='IP_DU_PAIR',
  MASTER_USER='repli',
  MASTER_PASSWORD='mot_de_passe_repli',
  MASTER_PORT=3306,
  MASTER_USE_GTID=slave_pos;
START SLAVE;
```

### Cas où il ne faut pas automatiser

Si la position GTID exploitable n'est pas connue, il ne faut pas tenter une reprise automatique. Il faut repartir sur une procédure de reconstruction propre [file:1].

---

## Repartir sur une réplication propre après incident

Lorsque les données ont été réconciliées et que les schémas sont alignés, il est souvent préférable de repartir de zéro plutôt que d'essayer de réparer un lien de réplication devenu incohérent [file:1].

### Réinitialisation

Sur les deux serveurs :

```sql
STOP SLAVE;
RESET SLAVE ALL;
RESET MASTER;
```

### Reconfiguration

Sur chaque serveur, pointer vers l'autre :

```sql
CHANGE MASTER TO
  MASTER_HOST='IP_VPN_DU_PAIR',
  MASTER_USER='repli',
  MASTER_PASSWORD='mot_de_passe_repli',
  MASTER_PORT=3306,
  MASTER_USE_GTID=slave_pos;
START SLAVE;
```

### Vérification

```sql
SHOW SLAVE STATUS\G
```

Contrôler au minimum :

- `Slave_IO_Running: Yes`
- `Slave_SQL_Running: Yes`
- `Last_Errno: 0`

### Point d'attention

Le retour d'expérience initial montre qu'après certaines manipulations, repartir proprement est plus fiable qu'une tentative de réparation partielle, notamment lorsque l'historique GTID et l'ancien lien de réplication ne sont plus totalement maîtrisés [file:1].

---

## Si besoin de downgrade de version

Dans certains cas, un problème peut provenir d'une mise à jour récente de Vaultwarden, d'un changement de schéma ou d'une incompatibilité apparue après migration. Le README initial mentionne explicitement qu'un downgrade peut faire partie des pistes de debug [file:1].

Le downgrade ne doit cependant pas être considéré comme une première réponse. Il faut d'abord vérifier :

- si l'incident est réellement apparu après une montée de version ;
- si la base a subi des migrations irréversibles ;
- si les deux nœuds tournent bien avec la même version ;
- si le problème ne vient pas en réalité d'un schéma divergent ou d'une réplication déjà cassée.

### Vérifier la version en cours

```bash
sudo docker ps
sudo docker images | grep vaultwarden
```

### Consulter les logs

```bash
sudo docker logs vaultwarden
```

### Revenir à une image antérieure

Exemple générique :

```bash
sudo docker stop vaultwarden
sudo docker rm vaultwarden
sudo docker pull vaultwarden/server:<ancienne_version>
```

Puis relancer le conteneur avec la même configuration qu'auparavant, en remplaçant simplement le tag de l'image.

### Précautions importantes

Avant tout downgrade :

- sauvegarder la base ;
- sauvegarder les volumes ;
- vérifier la compatibilité de schéma ;
- éviter de downgrader un seul nœud dans une architecture redondée.

Si un downgrade est nécessaire, il doit être pensé pour l'ensemble du dispositif, pas uniquement pour un serveur isolé.

---

## Aide au diagnostic rapide

### Symptôme : Vaultwarden répond mal ou ne démarre plus

Vérifier :

```bash
sudo docker ps
sudo docker logs vaultwarden
sudo systemctl status mariadb
```

### Symptôme : réplication cassée sans explication claire

Vérifier :

```bash
ping 10.0.0.1
ping 10.0.0.2
nc -zv -w5 10.0.0.1 3306
nc -zv -w5 10.0.0.2 3306
mysql -h 10.0.0.2 -P 3306 -u repli -p -e "SELECT 1;"
```

Puis :

```sql
SHOW SLAVE STATUS\G
```

### Symptôme : erreur SQL persistante sur une table

Vérifier :

```sql
SHOW CREATE TABLE users\G
SHOW CREATE TABLE devices\G
SHOW CREATE TABLE ciphers\G
SHOW CREATE TABLE folders\G
SHOW CREATE TABLE folders_ciphers\G
```

Comparer les deux nœuds et rechercher une différence de type, de contrainte ou de migration.

### Symptôme : erreur liée à une migration déjà appliquée

Envisager uniquement après validation :

```sql
STOP SLAVE;
SET GLOBAL sql_slave_skip_counter = 1;
START SLAVE;
SHOW SLAVE STATUS\G
```

---

## Recommandations

Pour réduire les incidents difficiles à diagnostiquer, il est recommandé de :

- surveiller activement la réplication ;
- conserver les deux serveurs strictement alignés en version ;
- éviter les modifications manuelles de schéma hors procédure ;
- documenter chaque incident réel rencontré ;
- effectuer une sauvegarde avant toute action structurelle sur MariaDB.

Une architecture redondée devient difficile à opérer si les schémas dérivent silencieusement ou si les erreurs de réplication sont ignorées trop longtemps.

---

## Synthèse

Les incidents les plus importants rencontrés sur cette infrastructure tournent autour de trois axes :

| Problème | Cause possible | Action prioritaire |
| --- | --- | --- |
| Réplication cassée | Réseau, firewall, configuration perdue, conflit SQL | Vérifier connectivité puis `SHOW SLAVE STATUS\G` |
| Erreur sur une table spécifique | Schéma divergent entre les nœuds | Comparer `SHOW CREATE TABLE` des deux côtés |
| Incident après mise à jour | Migration, incompatibilité, changement de version | Lire les logs, vérifier le schéma, envisager un downgrade si nécessaire |

Le point clé à retenir est qu'un problème de réplication n'est pas toujours un problème de données. Il peut venir d'un simple blocage réseau, mais tant qu'il n'est pas diagnostiqué rapidement, il finit par produire une vraie divergence applicative [file:1].
