# Restauration

## Objectif

Ce document décrit les procédures de restauration et de reprise après incident pour l'infrastructure Vaultwarden.

L'objectif n'est pas seulement de restaurer un service arrêté, mais de retrouver un état cohérent de l'application, de la base de données et de la réplication lorsque l'un des composants devient indisponible ou corrompu.

Dans cette architecture, la restauration peut concerner plusieurs niveaux :

- le conteneur Vaultwarden ;
- la base MariaDB locale ;
- la réplication entre les deux bases ;
- la cohérence globale des données après un incident prolongé.

---

## Principes généraux

La réplication MariaDB améliore la disponibilité, mais elle ne remplace pas une sauvegarde.

Deux bases synchronisées ne garantissent pas à elles seules la capacité de revenir en arrière. Une suppression, une corruption ou une erreur logique peut être propagée sur les deux nœuds.

Une procédure de restauration doit donc toujours répondre à deux questions :

- quel est l'état réel de chaque nœud ;
- quelles données doivent être considérées comme valides avant toute remise en service.

Avant toute opération de reprise, il est recommandé de :

- figer la situation ;
- éviter toute nouvelle écriture inutile ;
- identifier clairement le nœud impacté ;
- vérifier l'état de la réplication ;
- conserver une copie des données avant modification.

---

## Types d'incidents

Les incidents les plus probables dans cette architecture sont les suivants :

- conteneur Vaultwarden arrêté ou corrompu ;
- base MariaDB locale indisponible ;
- perte partielle ou totale de la réplication ;
- divergence de données entre les deux nœuds ;
- schéma MariaDB incohérent entre les serveurs ;
- incident réseau empêchant les échanges WireGuard ou MariaDB.

Chaque cas ne nécessite pas la même procédure. Il est donc important de diagnostiquer précisément le problème avant d'appliquer une restauration.

---

## Vérifications préalables

Avant de restaurer quoi que ce soit, effectuer les contrôles suivants.

### État du conteneur Vaultwarden

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

Dans MariaDB :

```sql
SHOW SLAVE STATUS\G
```

Surveiller notamment :

- `Slave_IO_Running`
- `Slave_SQL_Running`
- `Last_Errno`
- `Last_SQL_Error`

### Vérification réseau

Tester la connectivité WireGuard et MariaDB entre les deux nœuds :

```bash
ping 10.0.0.1
ping 10.0.0.2
nc -zv -w5 10.0.0.1 3306
nc -zv -w5 10.0.0.2 3306
```

Tester également une connexion MariaDB directe avec le compte concerné :

```bash
mysql -h 10.0.0.2 -P 3306 -u repli -p -e "SELECT 1;"
```

Cette étape permet de distinguer :

- un problème applicatif ;
- un problème MariaDB ;
- un problème de réplication ;
- un problème de pare-feu ou de réseau.

---

## Restauration simple de Vaultwarden

Si le problème concerne uniquement le conteneur Vaultwarden, sans corruption de la base, la restauration est relativement simple.

### Redémarrage du conteneur

```bash
sudo docker restart vaultwarden
```

### Vérification

```bash
sudo docker ps
sudo docker logs vaultwarden
```

### Recréation du conteneur

Si nécessaire, supprimer puis recréer le conteneur à partir de la configuration prévue :

```bash
sudo docker stop vaultwarden
sudo docker rm vaultwarden
```

Puis relancer le conteneur avec les paramètres habituels ou via Docker Compose.

Cette opération ne doit être réalisée qu'après avoir vérifié que :

- les volumes de données sont toujours présents ;
- la base MariaDB locale est accessible ;
- la variable `DATABASE_URL` est correcte.

---

## Restauration de MariaDB locale

Si MariaDB ne démarre plus ou si la base locale est inutilisable, plusieurs approches sont possibles selon la gravité de l'incident.

### Cas 1 : service arrêté mais données intactes

Tenter un redémarrage :

```bash
sudo systemctl restart mariadb
sudo systemctl status mariadb
```

Si MariaDB redémarre correctement, vérifier immédiatement l'état de la réplication et l'accès depuis Vaultwarden.

### Cas 2 : base locale irrécupérable mais autre nœud sain

Si l'autre serveur dispose d'une base cohérente et à jour, il peut servir de source de reconstruction.

Dans ce cas :

1. arrêter Vaultwarden sur le nœud à reconstruire ;
2. arrêter MariaDB sur ce même nœud ;
3. sauvegarder le répertoire de données MariaDB existant ;
4. repartir d'une base propre ;
5. reconfigurer la réplication à partir du nœud sain.

Cette méthode est adaptée lorsque la perte est localisée à un seul serveur et que l'autre reste fiable.

---

## Sauvegarde avant intervention

Avant toute opération destructive, réaliser une sauvegarde de l'état courant.

### Dump MariaDB

```bash
mysqldump -u root -p --all-databases > all-databases-backup.sql
```

Ou uniquement la base Vaultwarden :

```bash
mysqldump -u root -p vaultwarden > vaultwarden-backup.sql
```

### Sauvegarde des données Vaultwarden

Si des fichiers persistent côté application :

```bash
tar -czf vaultwarden-data-backup.tar.gz /opt/vaultwarden
```

### Sauvegarde de configuration

Conserver également une copie de :

- `/etc/wireguard/wg0.conf`
- la configuration MariaDB
- la configuration Docker ou Docker Compose
- la configuration Caddy sur le VPS

Ces sauvegardes permettent de revenir en arrière si la restauration aggrave la situation.

---

## Restauration après réplication cassée

Une réplication cassée ne signifie pas toujours qu'il faut restaurer les données. Dans de nombreux cas, il faut d'abord comprendre si la rupture est uniquement technique ou si elle a déjà provoqué une divergence réelle.

### Cas 1 : réplication arrêtée sans divergence constatée

Si les deux serveurs sont restés cohérents et que la coupure a été courte, il est possible qu'un redémarrage de la réplication suffise.

Sur le serveur concerné :

```sql
STOP SLAVE;
START SLAVE;
```

Puis vérifier :

```sql
SHOW SLAVE STATUS\G
```

### Cas 2 : configuration de réplication perdue

Si `SHOW SLAVE STATUS` ne retourne plus rien mais que le nœud a déjà été répliqué auparavant, une reconfiguration contrôlée peut suffire.

```sql
CHANGE MASTER TO
  MASTER_HOST='IP_DU_PAIR',
  MASTER_USER='repli',
  MASTER_PASSWORD='mot_de_passe_repli',
  MASTER_PORT=3306,
  MASTER_USE_GTID=slave_pos;
START SLAVE;
```

Puis vérifier à nouveau :

```sql
SHOW SLAVE STATUS\G
```

### Cas 3 : erreur SQL ou conflit de données

Si `Last_Errno` ou `Last_SQL_Error` indiquent un conflit, il ne faut pas relancer aveuglément la réplication.

Dans ce cas, il faut :

- identifier la table concernée ;
- vérifier si le schéma est identique sur les deux nœuds ;
- déterminer s'il s'agit d'un vrai conflit de données ou d'un artefact de migration ;
- éviter toute correction automatique destructrice.

---

## Récupération après réplication cassée durablement

Cette section couvre le cas le plus critique : la réplication est restée cassée longtemps et les deux nœuds ont continué à vivre séparément.

Dans cette situation, il ne s'agit plus d'un simple retard de réplication. Les deux bases peuvent contenir des écritures différentes.

### Symptômes

Ce type d'incident peut se manifester par :

- des données présentes sur un nœud mais absentes sur l'autre ;
- des valeurs différentes pour un même enregistrement ;
- des erreurs SQL lors de la reprise ;
- une reprise impossible malgré une connectivité réseau correcte.

### Règle importante

Ne jamais supposer qu'un seul des deux serveurs contient forcément la vérité complète.

Même si un seul nœud servait la majorité du trafic, l'autre peut contenir des écritures qui n'ont jamais été répliquées avant la rupture.

---

## Procédure de reprise après divergence durable

### 1. Diagnostiquer la connectivité

Avant de blâmer MariaDB, vérifier que les deux serveurs peuvent réellement communiquer.

```bash
ping 10.0.0.1
ping 10.0.0.2
nc -zv -w5 10.0.0.1 3306
nc -zv -w5 10.0.0.2 3306
mysql -h 10.0.0.2 -P 3306 -u repli -p -e "SELECT 1;"
```

Une règle de pare-feu absente sur le port 3306 suffit à casser durablement la réplication.

### 2. Figer la situation

Avant toute tentative de correction :

- éviter toute nouvelle écriture si possible ;
- conserver une sauvegarde des deux bases ;
- ne pas relancer la réplication immédiatement ;
- ne pas choisir arbitrairement un nœud comme source unique sans vérification.

### 3. Quantifier la divergence

Comparer les deux bases avant toute action.

L'objectif est d'identifier :

- les enregistrements présents d'un seul côté ;
- les objets modifiés différemment ;
- les écarts sur les tables critiques comme `users`, `ciphers`, `folders` et `devices`.

Une approche propre consiste à travailler à partir de dumps ou de copies temporaires afin de ne jamais comparer directement dans la base de production.

### 4. Réconcilier les données

Une fois les écarts identifiés, produire les corrections nécessaires pour remettre les deux bases dans un état cohérent.

Cette étape doit être faite avec prudence, table par table si nécessaire.

L'idée générale est la suivante :

- si une ligne n'existe que sur un nœud, la réinjecter sur l'autre ;
- si une même ligne diffère, déterminer quelle version doit être conservée ;
- ne jamais supposer qu'un seul sens de synchronisation suffit pour toutes les tables.

### 5. Vérifier le schéma

Avant de relancer la réplication, s'assurer que les schémas sont identiques sur les deux serveurs.

Un type de colonne différent, une contrainte absente ou une table incohérente suffit à casser de nouveau la réplication dès le premier événement concerné.

### 6. Réinitialiser la réplication proprement

Une fois les données réconciliées et les schémas alignés, repartir d'une réplication propre.

Sur chaque serveur :

```sql
STOP SLAVE;
RESET SLAVE ALL;
RESET MASTER;
```

Puis reconfigurer le lien vers l'autre nœud.

Sur le serveur A :

```sql
CHANGE MASTER TO
  MASTER_HOST='10.0.0.2',
  MASTER_USER='repli',
  MASTER_PASSWORD='mot_de_passe_repli',
  MASTER_PORT=3306,
  MASTER_USE_GTID=slave_pos;
START SLAVE;
```

Sur le serveur B :

```sql
CHANGE MASTER TO
  MASTER_HOST='10.0.0.1',
  MASTER_USER='repli',
  MASTER_PASSWORD='mot_de_passe_repli',
  MASTER_PORT=3306,
  MASTER_USE_GTID=slave_pos;
START SLAVE;
```

### 7. Vérification finale

Sur les deux serveurs :

```sql
SHOW SLAVE STATUS\G
```

Vérifier au minimum :

- `Slave_IO_Running: Yes`
- `Slave_SQL_Running: Yes`
- `Last_Errno: 0`

---

## Scripts du dépôt utiles pour la reprise

La reprise après incident ne repose pas uniquement sur des commandes manuelles. Le dépôt fournit plusieurs scripts qui participent directement à la détection, au diagnostic et à la correction de certains problèmes de réplication.

Les scripts mentionnés ici s'appuient sur le même fichier `.env` que `updatevaultwarden.sh`. Ce fichier centralise les paramètres nécessaires à l'exploitation, à la supervision et aux opérations de reprise.

### checkreplication.sh

Le script [`scripts/check_replication.sh`](scripts/check_replication.sh) sert à surveiller l'état de la réplication MariaDB sur chaque nœud.

Il tourne en tâche planifiée sur les deux serveurs et permet notamment de :

- détecter une réplication saine ou dégradée ;
- tenter un redémarrage automatique de la réplication lorsque cela est sans risque ;
- reconfigurer la réplication si sa configuration a été perdue mais que la position GTID permet une reprise propre ;
- refuser toute correction automatique lorsqu'un conflit de données est détecté ;
- journaliser l'état constaté et envoyer une alerte si nécessaire.

Ce script est adapté aux incidents de réplication simples ou techniques, par exemple :

- thread arrêté sans divergence de données ;
- perte de configuration de réplication ;
- besoin d'alerter rapidement sur un incident silencieux.

En revanche, il ne doit pas être considéré comme un outil de réconciliation de données. En cas de divergence réelle entre les deux nœuds, une intervention dédiée reste nécessaire.

### Installation de checkreplication.sh

```bash
cd /opt/vaultwarden
cp chemin/vers/scripts/checkreplication.sh .
chmod +x checkreplication.sh

# si le fichier .env existe déjà, l'éditer directement
nano .env

# sinon
cp chemin/vers/scripts/env.example .env
nano .env


---

## Cas particulier : conflits bénins après reprise

Après une réconciliation de données, certains conflits résiduels peuvent concerner des tables internes de migration ou des métadonnées déjà appliquées des deux côtés.

Dans ce cas précis, un saut contrôlé d'événement peut parfois être acceptable.

Exemple :

```sql
STOP SLAVE;
SET GLOBAL sql_slave_skip_counter = 1;
START SLAVE;
```

Cette méthode ne doit jamais être utilisée à l'aveugle sur des tables métier telles que :

- `users`
- `ciphers`
- `folders`
- `devices`

Elle n'est acceptable que pour des conflits explicitement identifiés comme bénins.

---

## Tests post-restauration

Une restauration n'est pas terminée tant qu'elle n'a pas été validée.

Après toute reprise, il faut :

- vérifier que Vaultwarden répond correctement ;
- vérifier la connexion à la base ;
- contrôler l'état de la réplication sur les deux nœuds ;
- tester l'accès via le VPS ;
- confirmer la cohérence fonctionnelle depuis un client Bitwarden.

### Exemples utiles

```bash
sudo docker ps
sudo docker logs vaultwarden
curl -vk https://10.0.0.1:443/alive
curl -vk https://10.0.0.2:443/alive
```

Dans MariaDB :

```sql
SHOW SLAVE STATUS\G
```

---

## Recommandations d'exploitation

Pour limiter les risques et simplifier les restaurations futures, il est recommandé de :

- conserver des sauvegardes régulières indépendantes de la réplication ;
- tester périodiquement les procédures de restauration ;
- documenter les incidents rencontrés ;
- surveiller activement l'état de la réplication ;
- valider les mises à jour avant généralisation sur les deux nœuds.

Une architecture redondée sans procédure de restauration testée reste fragile.

---

## Synthèse

La restauration dans cette architecture peut concerner plusieurs couches :

| Élément | Type de restauration |
| --- | --- |
| Conteneur Vaultwarden | Redémarrage ou recréation du service |
| MariaDB locale | Redémarrage, reconstruction ou réimport |
| Réplication MariaDB | Reprise simple, reconfiguration ou réinitialisation |
| Données divergentes | Réconciliation manuelle avant relance |
| Schéma incohérent | Alignement structurel avant reprise |
| Accès global au service | Validation via VPS et reverse proxy |

La reprise après incident doit toujours privilégier la cohérence des données avant la remise en service complète. En cas de réplication cassée durablement, la priorité n'est pas de reconnecter les deux nœuds le plus vite possible, mais de reconstruire un état fiable et maîtrisé.
