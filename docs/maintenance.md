# Maintenance

## Objectif

Ce document décrit les opérations de maintenance courantes de l'infrastructure Vaultwarden.

Il couvre en particulier :

- la maintenance du certificat TLS ;
- la mise à jour de Vaultwarden ;
- l'utilisation du script `update_vaultwarden.sh` ;
- la maintenance système de base ;
- les ajustements autour de SSH et d'OpenSSH.

L'objectif est de conserver une procédure claire, reproductible et adaptée à une exploitation régulière.

---

## Principes généraux

Une maintenance réussie doit préserver à la fois :

- la disponibilité du service ;
- l'intégrité des données ;
- la cohérence entre les différents nœuds ;
- la capacité à revenir en arrière en cas de problème.

Avant toute opération de maintenance, il est recommandé de :

- vérifier l'état du service ;
- effectuer une sauvegarde adaptée ;
- documenter la version actuelle ;
- éviter de modifier plusieurs composants critiques en même temps sans plan de retour arrière.

---

## Vérifications préalables

Avant toute intervention, effectuer au minimum les contrôles suivants.

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

```sql
SHOW SLAVE STATUS\G
```

Vérifier notamment :

- `Slave_IO_Running`
- `Slave_SQL_Running`
- `Last_Errno`
- `Last_SQL_Error`

### Vérification de l'accès applicatif

```bash
curl -vk https://127.0.0.1/alive
```

Adapter l'URL selon l'architecture réellement utilisée.

---

## Sauvegardes avant maintenance

Avant toute mise à jour importante, effectuer une sauvegarde.

### Sauvegarde de la base Vaultwarden

```bash
mysqldump -u root -p vaultwarden > vaultwarden-backup.sql
```

### Sauvegarde du dossier d'exploitation

```bash
tar -czf vaultwarden-maintenance-backup.tar.gz /opt/vaultwarden
```

### Sauvegarde utile complémentaire

Conserver également une copie de :

- la configuration Docker ou Docker Compose ;
- la configuration MariaDB ;
- la configuration WireGuard si utilisée ;
- la configuration du reverse proxy ou du VPS ;
- le fichier `.env` utilisé par les scripts du dépôt.

Le fichier `.env` contient des identifiants sensibles. Il ne doit jamais être versionné dans le dépôt.

---

## Renouvellement du certificat

Dans la documentation initiale, le certificat était obtenu avec `certbot`, puis copié dans un emplacement utilisé par le conteneur Vaultwarden.

Le renouvellement du certificat fait donc partie des opérations de maintenance régulières.

### Vérifier la date d'expiration

```bash
sudo certbot certificates
```

### Renouveler le certificat

```bash
sudo certbot renew
```

Selon l'installation, il peut être utile de forcer un test de renouvellement :

```bash
sudo certbot renew --dry-run
```

### Mettre à jour les fichiers utilisés par Vaultwarden

Si le conteneur s'appuie sur des copies locales des certificats, recopier les fichiers renouvelés :

```bash
sudo cp /etc/letsencrypt/live/fullchain.pem /ssl/keys/certs.pem
sudo cp /etc/letsencrypt/live/privkey.pem /ssl/keys/key.pem
```

Adapter bien sûr les chemins à l'organisation réelle du serveur.

### Redémarrer le conteneur si nécessaire

```bash
sudo docker restart vaultwarden
```

### Vérification

```bash
sudo docker logs vaultwarden
curl -vk https://127.0.0.1/alive
```

### Points d'attention

Lors du retour d'expérience initial, deux remarques importantes ressortent :

- il peut arriver que Let's Encrypt impose un délai avant une nouvelle émission en cas de tentatives répétées ;
- certains réseaux d'entreprise peuvent être plus stricts avec certains certificats ou chaînes de confiance, même si Let's Encrypt reste généralement parfaitement adapté à un usage domestique.

---

## Mises à jour de Vaultwarden

La mise à jour de Vaultwarden doit être réalisée avec prudence, en particulier dans une architecture avec base MariaDB répliquée.

Une montée de version peut impliquer :

- une nouvelle image Docker ;
- des changements applicatifs ;
- des migrations de schéma ;
- des écarts temporaires entre nœuds si la procédure est mal séquencée.

### Vérifier l'image en cours

```bash
sudo docker ps
sudo docker images | grep vaultwarden
```

### Mettre à jour manuellement l'image

```bash
sudo docker pull vaultwarden/server:latest
```

Si l'on utilise explicitement `latest`, il faut garder en tête qu'on perd en traçabilité par rapport à un tag figé de version.

### Redéployer le conteneur

Exemple générique :

```bash
sudo docker stop vaultwarden
sudo docker rm vaultwarden
sudo docker run -d --name vaultwarden \
  -e ROCKET_TLS='{certs="/ssl/certs.pem",key="/ssl/key.pem"}' \
  -v /ssl:/ssl \
  -v vw-data:/data \
  -p 443:80 \
  vaultwarden/server:latest
```

Adapter la commande à l'architecture réelle du serveur.

### Vérifications post-mise à jour

```bash
sudo docker ps
sudo docker logs vaultwarden
curl -vk https://127.0.0.1/alive
```

Puis côté base :

```sql
SHOW SLAVE STATUS\G
```

---

## Script `update_vaultwarden.sh`

Le dépôt initial prévoit un script `update_vaultwarden.sh` destiné à industrialiser la maintenance applicative. Le README le présente comme un script de mise à jour semi-automatique avec sauvegarde, vérification et rollback.

Ce script constitue le point central de la maintenance applicative quand on veut éviter une procédure manuelle trop fragile.

### Rôle du script

Le script a pour objectif de :

- préparer l'environnement de mise à jour ;
- réutiliser les variables du fichier `.env` ;
- effectuer une sauvegarde avant modification ;
- mettre à jour Vaultwarden ;
- vérifier le bon fonctionnement après redémarrage ;
- permettre un retour arrière en cas d'échec.

### Intérêt

Par rapport à une mise à jour manuelle, cette approche permet de mieux cadrer :

- la sauvegarde préalable ;
- la répétabilité de la procédure ;
- la réduction des oublis ;
- la capacité de rollback.

### Fichier `.env` partagé

Le README précise que `update_vaultwarden.sh` partage le même fichier `.env` que d'autres scripts du dépôt, notamment :

- `check_replication.sh`
- `reconcile_split_brain.sh`

Ce point est important pour l'exploitation, car le fichier `.env` devient le centre de configuration de plusieurs opérations de maintenance et de reprise.

### Installation typique

```bash
cd /opt/vaultwarden
cp chemin/vers/scripts/update_vaultwarden.sh .
chmod +x update_vaultwarden.sh
```

Si le fichier `.env` existe déjà :

```bash
nano .env
```

Sinon :

```bash
cp chemin/vers/scripts/.env.example .env
nano .env
```

### Exécution

```bash
./update_vaultwarden.sh
```

Le comportement exact dépend des variables définies dans `.env` et de la logique du script réellement présente dans le dépôt.

### Recommandations

Avant d'utiliser ce script en production :

- le lire une première fois ;
- vérifier les chemins utilisés ;
- confirmer les volumes Docker et sauvegardes visés ;
- confirmer le comportement de rollback ;
- l'essayer si possible sur un environnement de test ou sur un créneau maîtrisé.

---

## Maintenance dans une architecture redondée

Lorsque deux nœuds Vaultwarden et deux bases MariaDB sont en jeu, la maintenance doit être encore plus rigoureuse.

### Règles générales

- ne pas mettre à jour un seul nœud sans savoir ce que cela implique sur l'autre ;
- vérifier la réplication avant et après intervention ;
- éviter les versions hétérogènes trop longtemps ;
- surveiller les migrations de schéma ;
- documenter précisément l'ordre des opérations.

### Vérification avant maintenance

```sql
SHOW SLAVE STATUS\G
```

Les deux threads de réplication doivent être sains avant de commencer.

### Vérification après maintenance

```sql
SHOW SLAVE STATUS\G
```

Puis vérifier les logs applicatifs :

```bash
sudo docker logs vaultwarden
```

Une mise à jour applicative qui semble correcte côté conteneur peut malgré tout avoir cassé la réplication ou introduit une divergence de schéma.

---

## Maintenance système

La maintenance ne concerne pas uniquement Vaultwarden. Le socle système doit lui aussi rester à jour.

### Mise à jour des paquets système

```bash
sudo apt update
sudo apt upgrade -y
```

Selon le contexte :

```bash
sudo apt full-upgrade -y
```

### Redémarrage du serveur

```bash
sudo reboot
```

Après redémarrage, vérifier immédiatement :

```bash
sudo docker ps
sudo systemctl status mariadb
sudo systemctl status wg-quick@wg0
```

Adapter la vérification WireGuard selon l'architecture réellement utilisée.

---

## Upgrade OpenSSH

Le README initial mentionne explicitement l'upgrade d'OpenSSH comme partie intégrante de la maintenance.

La logique est simple : SSH est un point d'administration critique. Il doit être maintenu à jour pour des raisons de sécurité et de compatibilité.

### Mise à jour via le système

```bash
sudo apt update
sudo apt install --only-upgrade openssh-server -y
```

### Vérifier la version

```bash
ssh -V
sudo sshd -T | head
```

### Vérifier l'état du service

```bash
sudo systemctl status ssh
```

Sur certaines distributions, le service peut aussi s'appeler `sshd`.

### Précaution importante

Ne jamais faire de modification SSH importante sans garder une session ouverte de secours.

En cas d'erreur de configuration, cela évite de se couper complètement l'accès au serveur.

---

## Changer le port par défaut de SSH

Le README initial mentionne également le changement du port par défaut de SSH comme une opération de maintenance et de durcissement classique.

Cela ne remplace pas une vraie politique de sécurité, mais cela permet de réduire une partie du bruit automatisé sur le port standard.

### Modifier la configuration SSH

Éditer le fichier de configuration :

```bash
sudo nano /etc/ssh/sshd_config
```

Rechercher ou ajouter :

```conf
Port 2222
```

Adapter la valeur au port réellement souhaité.

### Vérifier la configuration

```bash
sudo sshd -t
```

### Ouvrir le port dans le pare-feu

Exemple avec UFW :

```bash
sudo ufw allow 2222/tcp
```

### Redémarrer SSH

```bash
sudo systemctl restart ssh
```

### Tester avant de fermer la session courante

Depuis un autre terminal :

```bash
ssh -p 2222 utilisateur@serveur
```

### Quand le test est validé

Si tout fonctionne, on peut ensuite fermer ou restreindre l'ancien port si nécessaire.

---

## Vérifications post-maintenance

Après toute intervention, contrôler systématiquement les points suivants.

### Application

```bash
sudo docker ps
sudo docker logs vaultwarden
curl -vk https://127.0.0.1/alive
```

### Base

```bash
sudo systemctl status mariadb
```

Puis :

```sql
SHOW SLAVE STATUS\G
```

### Réseau et services annexes

```bash
sudo systemctl status wg-quick@wg0
sudo systemctl status ssh
```

### Certificat

```bash
sudo certbot certificates
```

L'idée est de confirmer non seulement que le service redémarre, mais aussi que toute la chaîne de dépendances reste cohérente.

---

## Fréquence conseillée

### À faire régulièrement

- vérifier l'état général du conteneur ;
- surveiller MariaDB ;
- contrôler la réplication ;
- vérifier la validité du certificat ;
- appliquer les mises à jour système maîtrisées.

### À faire lors des évolutions applicatives

- sauvegarder la base ;
- mettre à jour Vaultwarden ;
- vérifier les logs ;
- contrôler les éventuelles migrations ;
- confirmer la cohérence entre nœuds.

### À faire ponctuellement

- mettre à jour OpenSSH ;
- revoir la configuration SSH ;
- vérifier les scripts d'exploitation du dépôt ;
- tester la procédure de rollback.

---

## Bonnes pratiques

Pour rendre la maintenance plus fiable, il est recommandé de :

- utiliser des sauvegardes avant chaque changement important ;
- éviter les mises à jour non documentées ;
- privilégier les scripts du dépôt lorsqu'ils encadrent correctement la procédure ;
- relire les logs après chaque intervention ;
- tester l'accès applicatif et l'état de la réplication après chaque mise à jour.

La maintenance d'un gestionnaire de mots de passe ne doit jamais se limiter à "le conteneur a redémarré". Il faut valider l'ensemble du service.

---

## Synthèse

| Opération | Objectif | Vérification principale |
| --- | --- | --- |
| Renouvellement du certificat | Maintenir l'accès TLS valide | `certbot certificates`, test HTTPS |
| Mise à jour de Vaultwarden | Mettre à jour l'application | logs Docker, accès `/alive` |
| Exécution de `update_vaultwarden.sh` | Industrialiser update, backup et rollback | contrôle du script, logs, état final |
| Mise à jour système | Maintenir le socle OS | état des services après reboot |
| Upgrade OpenSSH | Maintenir l'accès d'administration | `ssh -V`, `systemctl status ssh` |
| Changement de port SSH | Réduire l'exposition du port standard | test de connexion sur le nouveau port |
| Vérification de la réplication | Garantir la cohérence entre nœuds | `SHOW SLAVE STATUS\G` |

Une maintenance correcte repose sur trois principes : préparer, vérifier, et pouvoir revenir en arrière. Dans cette architecture, la cohérence de la base et de la réplication est aussi importante que l'état du conteneur applicatif.
