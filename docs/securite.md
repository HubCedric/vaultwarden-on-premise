# Sécurité

## Objectif

Ce document décrit les principaux choix et mesures de sécurité mis en place autour de l'infrastructure Vaultwarden.

Il couvre en particulier :

- l'exposition réseau du service ;
- la sécurisation des flux ;
- la protection des accès d'administration ;
- la gestion des secrets ;
- la sécurisation des échanges entre nœuds ;
- les points de vigilance liés à MariaDB, Docker et SSH.

L'objectif n'est pas de transformer cette infrastructure en environnement militaire, mais de réduire les risques réels tout en gardant une exploitation raisonnable et maintenable.

---

## Principes généraux

Un gestionnaire de mots de passe impose un niveau d'exigence supérieur à beaucoup d'autres services auto-hébergés.

Même si les données Vaultwarden sont chiffrées côté application, cela ne dispense pas de sécuriser correctement :

- l'accès réseau ;
- le transport ;
- les comptes système ;
- la base de données ;
- les scripts d'exploitation ;
- la maintenance.

Les principes à respecter sont les suivants :

- exposer le moins possible ;
- chiffrer les flux utiles ;
- segmenter les accès ;
- limiter les privilèges ;
- éviter les automatismes dangereux ;
- conserver une exploitation lisible et vérifiable.

---

## Réduire l'exposition réseau

L'un des choix structurants du projet consiste à éviter autant que possible l'ouverture de ports inutiles vers Internet.

Le README initial souligne explicitement l'intérêt d'une architecture basée sur IPv6 et sur des échanges ciblés, afin d'éviter les expositions réseau superflues souvent sources de problèmes de sécurité.

### Objectif

Réduire la surface d'attaque en n'exposant que ce qui est strictement nécessaire.

### À limiter au maximum

- l'ouverture large de ports publics ;
- l'exposition directe de MariaDB ;
- l'accès SSH non maîtrisé ;
- les services d'administration accessibles depuis n'importe où ;
- les secrets stockés en clair dans des emplacements non contrôlés.

### Règle pratique

Un port ouvert doit toujours répondre à une nécessité d'exploitation clairement identifiée.

---

## Chiffrement des accès HTTPS

Le service Vaultwarden ne doit pas être exploité durablement en HTTP. Le README initial présente bien une phase de test temporaire en HTTP, mais la mise en service réelle repose ensuite sur HTTPS avec certificat.

### Pourquoi

Le chiffrement TLS protège :

- les identifiants échangés ;
- les sessions ;
- les métadonnées applicatives sensibles ;
- la confidentialité des échanges entre client et serveur.

### Mise en place avec Let's Encrypt

Le README initial décrit l'utilisation de `certbot` pour obtenir un certificat Let's Encrypt.

Exemple :

```bash
sudo apt install certbot -y
sudo certbot certonly
```

Une fois les certificats obtenus, ils sont copiés dans un emplacement utilisé par le conteneur.

Exemple :

```bash
sudo cp /etc/letsencrypt/live/fullchain.pem /ssl/keys/certs.pem
sudo cp /etc/letsencrypt/live/privkey.pem /ssl/keys/key.pem
```

Puis Vaultwarden est redémarré avec la configuration TLS adaptée.

### Points d'attention

Le retour d'expérience initial mentionne deux limites utiles à garder en tête :

- Let's Encrypt peut imposer des délais en cas de génération répétée ;
- certains environnements d'entreprise très restrictifs peuvent être plus sensibles à certaines chaînes de certificats, même si Let's Encrypt reste généralement très adapté à un usage domestique.

---

## Sécurisation des échanges entre nœuds

Dans l'architecture redondée décrite dans le README initial, les serveurs ne doivent pas échanger leurs données en clair sur le réseau. Le choix retenu est l'utilisation d'un tunnel WireGuard entre les machines.

### Rôle de WireGuard

WireGuard sert à :

- isoler les flux inter-serveurs ;
- éviter l'exposition directe des échanges MariaDB ;
- simplifier la topologie réseau entre les nœuds ;
- garder une interconnexion chiffrée entre les différentes machines.

### Services concernés

Le tunnel protège notamment :

- les échanges MariaDB sur le port 3306 ;
- les flux liés à la supervision de réplication ;
- les opérations de reprise ou de réconciliation ;
- la communication entre les nœuds applicatifs et le VPS selon l'architecture choisie.

### Vérification

```bash
ip a
ping 10.0.0.1
ping 10.0.0.2
ping 10.0.0.10
```

L'idée est de vérifier que l'interface `wg0` est bien active et que les pairs se joignent correctement.

---

## MariaDB : ne pas exposer plus que nécessaire

MariaDB est l'un des composants les plus sensibles de l'architecture. Même si la réplication impose des communications réseau entre les nœuds, cela ne justifie pas une exposition large.

### Bonnes pratiques issues de l'architecture initiale

- ouvrir le port 3306 uniquement entre les serveurs qui en ont besoin ;
- limiter les connexions au réseau VPN WireGuard ;
- éviter toute exposition publique inutile ;
- contrôler précisément les comptes autorisés à se connecter à distance.

### Vérification réseau

```bash
nc -zv -w5 10.0.0.1 3306
nc -zv -w5 10.0.0.2 3306
mysql -h 10.0.0.2 -P 3306 -u repli -p -e "SELECT 1;"
```

### Retour d'expérience important

Le README documente un incident où la réplication était cassée non pas à cause de MariaDB elle-même, mais à cause d'une règle `ufw` absente sur le port 3306 depuis l'IP VPN du pair dans un sens.

Cela montre deux choses :

- un pare-feu trop ouvert est dangereux ;
- un pare-feu trop restrictif ou incohérent peut casser l'exploitation silencieusement.

La bonne approche consiste donc à ouvrir strictement ce qui est nécessaire, dans le bon sens, pour les bonnes IP.

---

## Principe du moindre privilège sur MariaDB

Les comptes techniques utilisés par la supervision et la reprise ne doivent pas avoir plus de droits que nécessaire.

Le README initial insiste sur cette idée en distinguant les comptes locaux capables d'agir sur la réplication, et les comptes distants limités à la lecture de statut.

### Exemple : compte de supervision

Le compte `monitor` est créé plusieurs fois selon l'hôte, avec des privilèges différents.

Exemple :

```sql
CREATE USER 'monitor'@'localhost' IDENTIFIED BY 'password';
GRANT REPLICATION CLIENT, SUPER ON *.* TO 'monitor'@'localhost';

CREATE USER 'monitor'@'127.0.0.1' IDENTIFIED BY 'password';
GRANT REPLICATION CLIENT, SUPER ON *.* TO 'monitor'@'127.0.0.1';

CREATE USER 'monitor'@'IP_VPN_DU_PAIR' IDENTIFIED BY 'password';
GRANT REPLICATION CLIENT ON *.* TO 'monitor'@'IP_VPN_DU_PAIR';

FLUSH PRIVILEGES;
```

### Intérêt de cette approche

Elle permet de garantir que :

- les actions sensibles comme `STOP SLAVE`, `START SLAVE` ou `CHANGE MASTER TO` restent limitées au local ;
- le pair distant ne peut que lire le statut ;
- une compromission du compte distant n'offre pas les mêmes capacités qu'un accès local.

### Point d'attention `localhost` / `127.0.0.1`

Le README signale également qu'il faut traiter séparément `localhost` et `127.0.0.1`, car selon le mode de connexion du client `mysql`, MariaDB peut appliquer l'une ou l'autre entrée.

---

## Gestion des secrets

L'infrastructure s'appuie sur plusieurs secrets sensibles :

- mots de passe MariaDB ;
- identifiants de réplication ;
- identifiants de supervision ;
- identifiants de réconciliation ;
- éventuels paramètres de mail ;
- secrets applicatifs ;
- clés WireGuard ;
- certificat privé TLS.

### Fichier `.env`

Les scripts du dépôt s'appuient sur un fichier `.env` partagé, notamment :

- `update_vaultwarden.sh`
- `check_replication.sh`
- `reconcile_split_brain.sh`

Le README précise explicitement que ce fichier contient des identifiants et ne doit jamais être commité.

### Règles minimales

- ne jamais versionner `.env` ;
- restreindre ses permissions ;
- éviter les copies inutiles ;
- documenter son emplacement exact ;
- le sauvegarder de manière sécurisée.

### Permissions recommandées

```bash
chmod 600 .env
chown root:root .env
```

Adapter selon l'utilisateur réellement utilisé pour l'exploitation.

---

## Sécuriser les scripts d'exploitation

Les scripts du dépôt simplifient l'exploitation, mais ils deviennent aussi des points sensibles.

Ils peuvent contenir ou consommer :

- des mots de passe ;
- des hôtes internes ;
- des accès d'administration ;
- des logiques de reprise.

### Bonnes pratiques

- ne jamais laisser un script modifiable par n'importe quel utilisateur ;
- vérifier les permissions ;
- lire le script avant de l'exécuter en production ;
- distinguer les scripts de supervision des scripts capables d'écrire ou de corriger ;
- éviter d'automatiser des corrections destructrices.

### Permissions typiques

```bash
chmod 700 update_vaultwarden.sh
chmod 700 check_replication.sh
chmod 700 reconcile_split_brain.sh
```

À adapter selon l'organisation réelle du serveur et l'utilisateur d'exploitation.

---

## SSH : protéger l'accès d'administration

SSH est la porte d'entrée d'administration principale. Il doit donc être traité comme un composant critique.

Le README initial mentionne explicitement :

- l'upgrade d'OpenSSH ;
- le changement du port par défaut de SSH.

### Mettre à jour OpenSSH

```bash
sudo apt update
sudo apt install --only-upgrade openssh-server -y
```

### Vérifier le service

```bash
sudo systemctl status ssh
ssh -V
```

### Changer le port par défaut

Modifier la configuration :

```bash
sudo nano /etc/ssh/sshd_config
```

Ajouter ou modifier :

```conf
Port 2222
```

Tester la configuration :

```bash
sudo sshd -t
```

Ouvrir le port côté pare-feu :

```bash
sudo ufw allow 2222/tcp
```

Redémarrer SSH :

```bash
sudo systemctl restart ssh
```

Tester depuis un autre terminal :

```bash
ssh -p 2222 utilisateur@serveur
```

### Limite de cette mesure

Changer le port SSH ne constitue pas une protection forte à lui seul. Cela réduit surtout le bruit automatique sur le port standard.

Il faut considérer cette mesure comme un durcissement complémentaire, pas comme une sécurité suffisante à elle seule.

---

## Pare-feu : filtrer sans casser l'exploitation

Le pare-feu doit protéger les services, mais il doit aussi rester cohérent avec l'architecture réelle.

Le retour d'expérience initial montre qu'une absence de règle sur le port 3306 pour une IP VPN donnée peut casser la réplication silencieusement.

### Méthode

Chaque règle doit répondre à une question simple :

- quel service est exposé ;
- à qui ;
- pourquoi ;
- dans quel sens ;
- sur quel réseau.

### Exemples typiques

Autoriser SSH sur le port choisi :

```bash
sudo ufw allow 2222/tcp
```

Autoriser WireGuard :

```bash
sudo ufw allow 51820/udp
```

Autoriser MariaDB uniquement depuis le pair VPN :

```bash
sudo ufw allow from 10.0.0.2 to any port 3306 proto tcp
```

Adapter évidemment les IP aux machines réelles.

### Vérification

```bash
sudo ufw status verbose
```

Le but n'est pas d'avoir "beaucoup" de règles, mais des règles lisibles et justifiées.

---

## Docker et conteneur Vaultwarden

Docker simplifie le déploiement, mais ne doit pas faire oublier les bases de sécurité.

### Bonnes pratiques minimales

- limiter les volumes montés au strict nécessaire ;
- éviter d'exposer des ports inutiles ;
- vérifier les logs après chaque changement ;
- conserver une trace de l'image réellement utilisée ;
- éviter les manipulations manuelles improvisées sur le conteneur en production.

### Vérification

```bash
sudo docker ps
sudo docker logs vaultwarden
sudo docker inspect vaultwarden
```

### Point d'attention

Un conteneur qui tourne ne veut pas dire que l'ensemble du service est sain.

Il faut aussi vérifier :

- l'accès HTTPS ;
- MariaDB ;
- la réplication ;
- les certificats ;
- les dépendances réseau.

---

## Réplication : sécurité et prudence opérationnelle

Le README initial insiste sur un point important : automatiser la supervision est utile, mais il ne faut pas automatiser aveuglément la correction de conflits de données.

### Pourquoi

Dans une base de mots de passe, une correction automatique mal conçue peut :

- masquer une divergence ;
- écraser des données valides ;
- faire croire à un retour à la normale alors que l'incohérence persiste.

### Bonne approche

- automatiser la détection ;
- automatiser uniquement les reprises sans ambiguïté ;
- alerter immédiatement en cas de conflit ;
- conserver les corrections complexes pour une intervention manuelle.

Cette logique est exactement celle décrite pour `check_replication.sh` dans le README initial.

---

## Disponibilité et sécurité

Le README montre bien qu'une architecture plus disponible peut aussi améliorer la sécurité opérationnelle globale, à condition d'être correctement maîtrisée.

Deux serveurs situés dans des lieux différents permettent de réduire certains risques :

- panne locale longue ;
- incident matériel ;
- indisponibilité d'un seul accès Internet ;
- risque physique localisé.

Mais cette redondance n'améliore la sécurité que si les échanges inter-sites sont bien protégés et si la réplication reste surveillée.

Une redondance mal supervisée peut au contraire augmenter le risque d'incohérence.

---

## Contrôles réguliers

### Vérifier les services critiques

```bash
sudo docker ps
sudo systemctl status mariadb
sudo systemctl status ssh
sudo systemctl status wg-quick@wg0
```

### Vérifier le certificat

```bash
sudo certbot certificates
```

### Vérifier la réplication

```sql
SHOW SLAVE STATUS\G
```

### Vérifier le pare-feu

```bash
sudo ufw status verbose
```

### Vérifier l'accès HTTPS

```bash
curl -vk https://127.0.0.1/alive
```

Ces contrôles simples permettent de détecter rapidement une dérive de sécurité ou d'exploitation.

---

## Bonnes pratiques récapitulatives

- exposer le moins possible ;
- chiffrer tous les flux sensibles ;
- utiliser WireGuard pour les échanges inter-nœuds ;
- ne pas exposer MariaDB inutilement ;
- limiter les privilèges des comptes MariaDB ;
- protéger le fichier `.env` ;
- ne jamais committer les secrets ;
- maintenir OpenSSH à jour ;
- durcir SSH sans se couper l'accès ;
- filtrer le réseau avec des règles explicites ;
- surveiller activement la réplication ;
- éviter les corrections automatiques dangereuses.

---

## Synthèse

| Élément | Risque principal | Mesure de sécurité |
| --- | --- | --- |
| Vaultwarden exposé en clair | Interception des flux | HTTPS avec certificat valide |
| Échanges inter-nœuds | Fuite ou interception réseau | Tunnel WireGuard |
| MariaDB | Exposition directe ou accès excessifs | Filtrage IP, comptes dédiés, moindre privilège |
| Scripts d'exploitation | Fuite de secrets ou usage abusif | permissions strictes, lecture préalable, `.env` protégé |
| SSH | Accès d'administration ciblé | mise à jour OpenSSH, port dédié, pare-feu |
| Réplication | Divergence silencieuse ou correction dangereuse | supervision, alertes, interventions prudentes |

La sécurité de cette infrastructure repose moins sur un produit miracle que sur un ensemble de choix cohérents : peu d'exposition, des flux chiffrés, des privilèges limités, des secrets protégés et une exploitation disciplinée.
