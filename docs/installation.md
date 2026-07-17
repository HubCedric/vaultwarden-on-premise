# Installation

## Objectif

Ce document décrit l'installation initiale de Vaultwarden sur un serveur personnel.

Il couvre :

- la préparation de la machine ;
- l'installation du système ;
- l'installation de Docker ;
- le premier démarrage de Vaultwarden ;
- la mise en place de HTTPS ;
- le redémarrage automatique du conteneur ;
- la migration de la base SQLite vers MariaDB.

L'objectif est d'obtenir une première instance fonctionnelle, propre et exploitable, avant d'aller plus loin sur la haute disponibilité ou la reprise après incident.

---

## Vue d'ensemble

L'installation initiale a été pensée pour fonctionner sur des plateformes légères de type ARM, notamment un Raspberry Pi ou une VM hébergée sur Freebox OS.

Le projet part du principe qu'une solution comme Vaultwarden est bien adaptée à ce type de matériel, là où l'implémentation Bitwarden officielle est plus contraignante sur des plateformes comme Raspberry Pi ou Freebox.

Deux scénarios d'installation sont donc envisagés :

- installation sur Raspberry Pi ;
- installation dans une VM sous Freebox OS.

Dans les deux cas, la logique générale reste la même :

1. installer le système ;
2. préparer l'accès SSH ;
3. mettre à jour la machine ;
4. installer Docker ;
5. lancer Vaultwarden ;
6. sécuriser l'accès en HTTPS ;
7. préparer la suite de l'exploitation.

---

## Prérequis généraux

Avant de commencer, il faut disposer :

- d'un serveur ou d'une VM sous Linux ;
- d'un accès SSH ;
- d'une connectivité réseau stable ;
- d'un nom de domaine si HTTPS public est prévu ;
- d'un accès administrateur sur la machine ;
- d'une architecture compatible avec Docker.

Le README initial mentionne également l'intérêt d'un accès IPv6 pour publier le service sans devoir ouvrir inutilement des ports sur le routeur, ce qui simplifie souvent l'exposition réseau et limite certains problèmes de sécurité.

---

## Installation sur Raspberry Pi

### Matériel utilisé

Le scénario Raspberry Pi présenté dans la documentation initiale repose sur les éléments suivants :

- un Raspberry Pi ;
- une alimentation ;
- un câble Ethernet ;
- une carte SD ou, de préférence, un SSD ;
- éventuellement un shield SSD pour Raspberry Pi ;
- un accès réseau, idéalement filaire.

Le retour d'expérience initial recommande plutôt le SSD qu'une carte SD, pour des raisons de fiabilité dans le temps.

### Installation du système

L'installation de l'OS se fait avec Raspberry Pi Imager.

Choix recommandés :

- modèle de Raspberry correspondant ;
- `Raspberry Pi OS Lite 64-bit` ;
- support de stockage adapté ;
- définition d'un utilisateur et d'un mot de passe ;
- activation de SSH dès la phase de préparation.

Le Wi-Fi reste possible, mais la documentation d'origine privilégie clairement une connexion filaire pour plus de stabilité.

### Démarrage initial

Une fois l'image écrite :

- brancher le support de stockage ;
- relier le Raspberry au réseau ;
- l'alimenter ;
- récupérer son adresse IP depuis l'interface du routeur ou de la box.

---

## Installation sur Freebox OS

### Matériel et contexte

La documentation initiale décrit aussi une installation dans une VM hébergée sur Freebox OS, avec par exemple un SSD NVMe dans une Freebox Delta ou Ultra.

Ce scénario permet de faire tourner Vaultwarden sur une VM légère, avec peu de ressources, tout en gardant une installation simple à domicile.

### Création de la VM

Depuis l'interface Freebox OS, il faut :

- ajouter une VM ;
- lui donner un nom ;
- allouer 1 vCPU ;
- allouer 512 Mo de RAM ;
- choisir une distribution Linux ;
- définir un utilisateur et un mot de passe ;
- allouer un disque virtuel d'environ 15 Go.

Le README précise que cette configuration reste largement suffisante pour un usage personnel avec peu d'utilisateurs et une volumétrie faible.

### Démarrage

Une fois la VM créée :

- la démarrer ;
- relever son adresse IP depuis l'interface Freebox OS ;
- poursuivre ensuite l'installation comme pour une machine Linux classique.

---

## Préparation du système

Une fois connecté en SSH sur le serveur, la première étape consiste à mettre le système à jour.

Connexion :

```bash
ssh utilisateur@adresse_ip
```

Mise à jour :

```bash
sudo apt update
sudo apt-get upgrade -y
```

Redémarrage :

```bash
sudo reboot
```

Cette étape permet de repartir sur une base propre avant d'installer Docker et les autres composants.

---

## Installation de Docker

Vaultwarden repose ici sur un conteneur Docker. La documentation initiale installe donc Docker ainsi que `docker-compose` via les paquets système.

Installation :

```bash
sudo apt install docker docker-compose -y
```

Vérification :

```bash
sudo docker ps
```

Si la commande répond correctement, la base d'exécution des conteneurs est prête.

---

## Premier déploiement de Vaultwarden

### Récupération de l'image

Télécharger l'image Docker :

```bash
sudo docker pull vaultwarden/server:latest
```

### Premier lancement en HTTP

Le README initial propose un premier démarrage en HTTP, uniquement pour valider rapidement que le service démarre correctement avant d'ajouter TLS.

Exemple :

```bash
sudo docker run -d \
  --name vaultwarden \
  -v vw-data:/data \
  -p 80:80 \
  vaultwarden/server:latest
```

Vérification :

```bash
sudo docker ps
```

À ce stade, l'objectif est simplement de vérifier que l'interface se lance bien localement et que le conteneur reste en état `Up`.

### Remarque

Ce démarrage HTTP est un test temporaire. Il ne constitue pas une configuration de production durable, surtout pour un service aussi sensible qu'un gestionnaire de mots de passe.

---

## Mise en place de HTTPS

### Principe

Une fois le service validé, il faut mettre en place HTTPS avec un certificat. Le README initial s'appuie sur Let's Encrypt via `certbot`.

### Arrêter le conteneur temporaire

Avant de générer le certificat, l'ancienne instance HTTP est supprimée.

```bash
sudo docker stop vaultwarden
sudo docker rm vaultwarden
```

### Installer Certbot

```bash
sudo apt install certbot -y
```

### Générer le certificat

```bash
sudo certbot certonly
```

Le processus demande ensuite :

- une méthode de validation ;
- une adresse email ;
- l'acceptation des conditions ;
- le ou les noms de domaine à certifier.

Une fois l'opération terminée, le certificat et la clé privée sont générés dans `/etc/letsencrypt/live/`.

### Préparer les fichiers TLS pour Vaultwarden

Créer l'arborescence :

```bash
sudo mkdir -p /ssl/keys
```

Copier les certificats :

```bash
sudo cp /etc/letsencrypt/live/fullchain.pem /ssl/keys/certs.pem
sudo cp /etc/letsencrypt/live/privkey.pem /ssl/keys/key.pem
```

### Relancer Vaultwarden avec TLS

Exemple de lancement :

```bash
sudo docker run -d \
  --name vaultwarden \
  -e ROCKET_TLS='{certs="/ssl/certs.pem",key="/ssl/key.pem"}' \
  -v /ssl/keys:/ssl \
  -v vw-data:/data \
  -p 443:80 \
  vaultwarden/server:latest
```

Vérification :

```bash
sudo docker ps
```

À partir de là, l'accès doit se faire via le nom de domaine configuré en HTTPS.

### Limites signalées dans le README

La documentation initiale mentionne deux points pratiques à garder en tête :

- il peut arriver qu'il faille attendre avant de regénérer un certificat Let's Encrypt en cas de quota temporaire ;
- certains environnements professionnels très filtrés peuvent poser davantage de problèmes avec certains certificats publics que les réseaux domestiques classiques.

---

## Redémarrage automatique simple avec cron

### Pourquoi

Dans la version initiale non redondée, un redémarrage de la machine ne relance pas automatiquement le conteneur avec tous ses paramètres si aucun mécanisme n'a été prévu.

Le README propose donc une solution simple via la crontab root.

### Éditer la crontab root

```bash
sudo -s
crontab -e
```

### Entrée de cron

Exemple :

```cron
@reboot docker rm -f vaultwarden ; docker run -d --name vaultwarden -e ROCKET_TLS='{certs="/ssl/certs.pem",key="/ssl/key.pem"}' -v /ssl/keys:/ssl -v vw-data:/data -p 443:80 vaultwarden/server:latest
```

Cette logique reprend l'idée décrite dans le README : supprimer au besoin l'ancien conteneur nommé `vaultwarden`, puis le recréer proprement au redémarrage avec les bons paramètres.

### Important

Cette solution est adaptée à une instance simple. Le README précise qu'à partir du moment où une architecture redondée est mise en place, cette logique n'est plus forcément pertinente et certaines configurations initiales doivent être revues.

---

## Migration de SQLite vers MariaDB

### Pourquoi migrer

Par défaut, Vaultwarden utilise SQLite.

Le README explique cependant qu'une base MariaDB devient préférable dès qu'on veut :

- répliquer les données ;
- préparer une redondance ;
- sortir d'une logique mono-fichier ;
- mieux intégrer la base dans une architecture de haute disponibilité.

### Installer les dépendances

```bash
sudo apt install mariadb-server python3 -y
sudo python3 -m pip install sqlite3-to-mysql --break-system-packages
```

### Lancer la migration

Depuis le répertoire contenant `db.sqlite3` :

```bash
sqlite3mysql -f db.sqlite3 -d vaultwarden -u vaultwarden -p -X -i IGNORE
```

Le README initial indique que cette commande peut être lancée sur un seul serveur dans le cas où la réplication MariaDB prendra ensuite le relais pour propager les données.

### Point d'attention

Cette migration ne suffit pas à elle seule pour obtenir une architecture redondée. Elle prépare simplement le passage vers MariaDB, qui sera ensuite utilisée dans la configuration de cluster et de réplication décrite dans les autres documents.

---

## Vérifications minimales après installation

Une fois l'installation terminée, il faut vérifier plusieurs points.

### Vérifier le conteneur

```bash
sudo docker ps
sudo docker logs vaultwarden
```

### Vérifier l'accès HTTPS

```bash
curl -vk https://nom-de-domaine/
```

### Vérifier le certificat

```bash
sudo certbot certificates
```

### Vérifier le service MariaDB si la migration a été faite

```bash
sudo systemctl status mariadb
```

L'objectif est de s'assurer que le service applicatif, le chiffrement TLS et le moteur de base sont tous opérationnels.

---

## Résultat attendu

À l'issue de cette procédure, on doit disposer :

- d'un serveur Linux accessible en SSH ;
- d'un conteneur Vaultwarden fonctionnel ;
- d'un accès HTTPS valide ;
- d'un stockage persistant pour les données ;
- éventuellement d'une base MariaDB prête à être utilisée à la place de SQLite.

Cette installation constitue la base de travail avant d'aborder :

- la haute disponibilité ;
- la réplication MariaDB ;
- la supervision ;
- la reprise après incident.

---

## Synthèse

| Élément | Objectif |
| --- | --- |
| Installation du système | disposer d'une base Linux propre et accessible |
| Mise à jour initiale | partir sur un système à jour |
| Docker | exécuter Vaultwarden dans un conteneur |
| Premier lancement HTTP | valider rapidement le bon fonctionnement |
| HTTPS avec Certbot | sécuriser l'accès au service |
| Cron de redémarrage | relancer simplement le conteneur au boot |
| Migration SQLite vers MariaDB | préparer l'évolution vers une architecture répliquée |

L'installation initiale reste volontairement simple. Elle permet d'obtenir rapidement une instance Vaultwarden fonctionnelle, avant d'introduire les mécanismes plus avancés de redondance, de supervision et de reprise.
