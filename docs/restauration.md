# Restauration

## Objectif

Ce document décrit les procédures de restauration et de reprise après incident pour l'infrastructure Vaultwarden.

L'objectif n'est pas seulement de relancer un service arrêté, mais de retrouver un état cohérent de l'application, de la base de données et de la réplication lorsque l'un des composants devient indisponible, corrompu ou désynchronisé.

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

## Scripts du dépôt utiles pour la reprise

La reprise après incident ne repose pas uniquement sur des commandes manuelles. Le dépôt fournit plusieurs scripts qui participent directement à la détection, au diagnostic et à la correction de certains problèmes de réplication.

Ces scripts s'appuient sur le même fichier `.env` que [`scripts/update_vaultwarden.sh`](../scripts/update_vaultwarden.sh). Ce fichier centralise les paramètres nécessaires à l'exploitation, à la supervision et aux opérations de reprise.

Les principaux scripts concernés sont :

- [`scripts/check_replication.sh`](../scripts/check_replication.sh) ;
- [`scripts/reconcile_split_brain.sh`](../scripts/reconcile_split_brain.sh) ;
- [`scripts/update_vaultwarden.sh`](../scripts/update_vaultwarden.sh) pour le fichier `.env` partagé et l'installation initiale de l'outillage.

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

### Dump MariaDB complet

```bash
mysqldump -u root -p --all-databases > all-databases-backup.sql
```

### Dump de la base Vaultwarden

```bash
mysqldump -u root -p vaultwarden > vaultwarden-backup.sql
```

### Sauvegarde des données Vaultwarden

```bash
tar -czf vaultwarden-data-backup.tar.gz /opt/vaultwarden
```

### Sauvegarde de configuration

Conserver également une copie de :

- `/etc/wireguard/wg0.conf` ;
- la configuration MariaDB ;
- la configuration Docker ou Docker Compose ;
- la configuration Caddy sur le VPS ;
- le fichier `.env` utilisé par les scripts du dépôt.

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

## Utilisation de `check_replication.sh`

Le script `check_replication.sh` sert à surveiller l'état de la réplication MariaDB sur chaque nœud.

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

### Installation

```bash
cd /opt/vaultwarden
cp chemin/vers/scripts/check_replication.sh .
chmod +x check_replication.sh
```

Si le fichier `.env` existe déjà, l'éditer directement :

```bash
nano .env
```

Sinon :

```bash
cp chemin/vers/scripts/.env.example .env
nano .env
```

Les variables à compléter dépendent de l'installation, mais incluent notamment :

- `NODENAME`
- `MONITORUSER`
- `MONITORPASSWORD`
- `PEERHOST`
- `PEERPORT`
- `REPLUSER`
- `REPLPASSWORD`

### Cron

```bash
crontab -e
```

```cron
0 6 * * * /opt/vaultwarden/check_replication.sh >> /var/log/check_replication-cron.log 2>&1
```

### Remarques

- le fichier `.env` contient des identifiants et ne doit jamais être commité ;
- l'envoi d'emails nécessite un MTA local fonctionnel ;
- si `ENABLEMAIL=0`, les alertes ne sont journalisées que dans le fichier prévu à cet effet.

---

## Récupération après une réplication cassée durablement

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

Même si un seul nœud servait la majorité du trafic, l'autre peut contenir des écritures plus anciennes jamais répliquées avant la coupure.

---

## Étape 1 : diagnostiquer la connectivité avant de blâmer MariaDB

Avant de supposer que la réplication est cassée au sens MariaDB, vérifier que les deux serveurs peuvent réellement se joindre.

```bash
ping 10.0.0.1
ping 10.0.0.2
nc -zv -w5 10.0.0.1 3306
nc -zv -w5 10.0.0.2 3306
mysql -h 10.0.0.2 -P 3306 -u repli -p -e "SELECT 1;"
```

Une règle de pare-feu absente sur le port 3306 suffit à casser durablement la réplication.

Avant d'aller plus loin, il faut donc confirmer :

- que le tunnel WireGuard fonctionne ;
- que MariaDB écoute bien ;
- que le port 3306 est autorisé dans les deux sens ;
- que le compte concerné peut réellement se connecter à distance.

---

## Étape 2 : quantifier et réconcilier la divergence avant de toucher à la réplication

Lorsque la réplication est restée cassée longtemps, il ne faut pas relancer la synchronisation immédiatement.

Il faut d'abord comparer les deux bases et identifier précisément les écarts. C'est le rôle de `reconcile_split_brain.sh`.

---

## Utilisation de `reconcile_split_brain.sh`

Le script `reconcile_split_brain.sh` est destiné aux cas où la réplication est restée cassée suffisamment longtemps pour que les deux bases aient divergé.

Son rôle est de comparer les deux bases avant toute tentative de reprise de la réplication. Il permet notamment de :

- importer un état frais de chaque côté dans des bases temporaires locales ;
- comparer les tables critiques ;
- déterminer le sens de synchronisation ligne par ligne selon les données ;
- générer des fichiers SQL de correction ;
- appliquer ces corrections uniquement après validation.

Ce script est un outil ponctuel de réconciliation. Il n'a pas vocation à être lancé en cron.

### Principe de fonctionnement

Le script :

1. se connecte en lecture seule aux deux serveurs ;
2. importe un dump frais de chacun dans des bases temporaires locales ;
3. compare les tables `users`, `folders`, `devices`, `ciphers` et `folders_ciphers` ;
4. génère deux fichiers SQL, un pour chaque sens d'application ;
5. permet une application contrôlée après relecture.

La logique de comparaison n'est pas strictement unidirectionnelle. Selon les lignes, une correction peut devoir partir du serveur principal vers le secondaire, ou inversement.

### Prérequis SQL

Créer un compte dédié de lecture seule sur les deux serveurs :

```sql
CREATE USER 'reconcilero'@'localhost' IDENTIFIED BY 'password';
GRANT SELECT ON vaultwarden.* TO 'reconcilero'@'localhost';

CREATE USER 'reconcilero'@'127.0.0.1' IDENTIFIED BY 'password';
GRANT SELECT ON vaultwarden.* TO 'reconcilero'@'127.0.0.1';

CREATE USER 'reconcilero'@'IP_VPN_DU_PAIR' IDENTIFIED BY 'password';
GRANT SELECT ON vaultwarden.* TO 'reconcilero'@'IP_VPN_DU_PAIR';

FLUSH PRIVILEGES;
```

### Installation

```bash
cd /opt/vaultwarden
cp chemin/vers/scripts/reconcile_split_brain.sh .
chmod +x reconcile_split_brain.sh
```

Si le fichier `.env` existe déjà, l'éditer directement :

```bash
nano .env
```

Sinon :

```bash
cp chemin/vers/scripts/.env.example .env
nano .env
```

Compléter notamment les variables suivantes :

- `MASTERHOST`
- `SLAVEHOST`
- identifiants `reconcilero`
- variables d'écriture pour l'application éventuelle des correctifs

### Génération des correctifs sans application

```bash
./reconcile_split_brain.sh /tmp/reconcile-report
```

Cette commande génère les fichiers SQL de correction sans les exécuter.

Il faut relire soigneusement les fichiers produits avant toute application, en particulier si le sens de synchronisation proposé est inattendu sur certaines lignes.

### Application réelle des correctifs

```bash
./reconcile_split_brain.sh /tmp/reconcile-report --apply
```

Cette étape ne doit être réalisée qu'après validation du contenu généré.

---

## Étape 3 : corriger les éventuels problèmes de schéma

Un schéma différent entre les deux serveurs bloque la réplication dès qu'un événement touche la table concernée.

Avant de relancer la réplication, vérifier et aligner :

- les types de colonnes ;
- les contraintes ;
- les index ;
- les tables internes de migration.

Si cette étape est négligée, la réplication risque de se casser immédiatement après la remise en route.

---

## Étape 4 : repartir sur une réplication propre

Une fois les données réconciliées et les schémas alignés, repartir d'une réplication propre plutôt que d'essayer de réparer l'ancien lien.

Sur chaque serveur :

```sql
STOP SLAVE;
RESET SLAVE ALL;
RESET MASTER;
```

Puis reconfigurer la réplication vers l'autre nœud.

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

### Vérification

```sql
SHOW SLAVE STATUS\G
```

Vérifier au minimum :

- `Slave_IO_Running: Yes`
- `Slave_SQL_Running: Yes`
- `Last_Errno: 0`

---

## Étape 5 : conflits bénins possibles après le redémarrage

Même après réconciliation des données applicatives, certaines tables internes de Vaultwarden ou des migrations déjà appliquées peuvent encore provoquer des erreurs de réplication du type :

- `Duplicate entry`
- `Duplicate column name`

Ce n'est pas forcément une divergence de données réelles. Dans ce cas précis, un saut contrôlé d'événement peut parfois être acceptable.

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

## Place des scripts dans la procédure de reprise

En pratique, la reprise suit cette logique :

1. vérifier la connectivité entre les nœuds ;
2. utiliser `check_replication.sh` pour diagnostiquer une panne simple de réplication ;
3. si une divergence durable est suspectée, ne pas forcer la reprise ;
4. utiliser `reconcile_split_brain.sh` pour quantifier et corriger la divergence ;
5. aligner les schémas si nécessaire ;
6. reconfigurer ensuite la réplication proprement sur les deux serveurs.

Cette approche évite de relancer une réplication sur des bases incohérentes, ce qui aggraverait l'incident au lieu de le corriger.

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
| Données divergentes | Réconciliation manuelle ou semi-automatisée avec les scripts du dépôt |
| Schéma incohérent | Alignement structurel avant reprise |
| Accès global au service | Validation via VPS et reverse proxy |

La reprise après incident doit toujours privilégier la cohérence des données avant la remise en service complète. En cas de réplication cassée durablement, la priorité n'est pas de reconnecter les deux nœuds le plus vite possible, mais de reconstruire un état fiable et maîtrisé.
