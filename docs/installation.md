# Installation de l'infrastructure

Ce document décrit la mise en place initiale de l'infrastructure Vaultwarden.

L'objectif est d'obtenir une instance Vaultwarden fonctionnelle accessible en HTTPS depuis l'extérieur.

La partie haute disponibilité (deuxième serveur, réplication MariaDB, VPS et WireGuard) est détaillée dans le document dédié :

➡️ [Haute disponibilité](./haute-disponibilite.md)

---

# Prérequis

## Matériel

L'installation peut fonctionner sur différents supports :

- Raspberry Pi ;
- machine virtuelle ;
- serveur Linux classique ;
- VPS.

Exemple de configuration minimale :

| Ressource | Valeur recommandée |
| --- | --- |
| CPU | 1 cœur |
| RAM | 512 Mo minimum |
| Stockage | 10 Go minimum |
| OS | Distribution Linux 64 bits |

Vaultwarden étant une application légère, une configuration très modeste suffit pour un usage personnel.

---

# Installation du système

## Raspberry Pi

Pour une installation sur Raspberry Pi, il est recommandé d'utiliser :

- un SSD plutôt qu'une carte SD ;
- une connexion Ethernet plutôt que Wi-Fi.

L'utilisation d'un SSD permet d'améliorer la fiabilité du système, les cartes SD étant plus sensibles aux écritures répétées.

L'installation de l'OS peut être réalisée avec **Raspberry Pi Imager**.

Configuration recommandée :

- Raspberry Pi OS Lite 64 bits ;
- activation du service SSH ;
- création d'un utilisateur administrateur ;
- configuration réseau.

---

## Machine virtuelle Freebox OS

Une alternative consiste à héberger Vaultwarden dans une machine virtuelle.

Exemple de configuration utilisée :

| Ressource | Valeur |
| --- | --- |
| CPU | 1 cœur |
| RAM | 512 Mo |
| Stockage | 15 Go |

Cette configuration est largement suffisante pour un usage personnel.

Une distribution Linux légère peut être utilisée, par exemple Ubuntu Server.

---

# Préparation du serveur Linux

Après l'installation du système :

Connexion SSH :

```bash
ssh utilisateur@adresse_ip
```

Mise à jour du système :

```bash
sudo apt update
sudo apt upgrade -y
```

Redémarrage :

```bash
sudo reboot
```

---

# Installation de Docker

Vaultwarden est exécuté dans un conteneur Docker.

Installation :

```bash
sudo apt install docker docker-compose -y
```

Vérification :

```bash
sudo docker ps
```

Si aucune erreur n'apparaît, Docker est fonctionnel.

---

# Déploiement de Vaultwarden

Création du dossier de données :

```bash
sudo mkdir /vw-data
```

Téléchargement de l'image Docker :

```bash
sudo docker pull vaultwarden/server:latest
```

Premier lancement de test :

```bash
sudo docker run -d \
--name vaultwarden \
-v /vw-data/:/data \
-p 80:80 \
vaultwarden/server:latest
```

L'interface web est alors accessible via :

```
http://adresse_ip_du_serveur
```

Cette étape permet uniquement de vérifier que Vaultwarden fonctionne correctement.

L'utilisation en HTTP n'est pas recommandée pour une utilisation réelle.

---

# Configuration HTTPS

L'accès final doit impérativement utiliser HTTPS.

Pour cela, il est nécessaire de disposer :

- d'un nom de domaine ;
- d'un certificat TLS.

Plusieurs solutions sont possibles :

- certificat Let's Encrypt ;
- certificat interne ;
- reverse proxy gérant automatiquement les certificats.

Dans l'architecture finale, la gestion HTTPS est réalisée par **Caddy sur le VPS**.

---

# Déploiement avec HTTPS local

Pour une installation simple sans VPS, Vaultwarden peut gérer directement son certificat TLS.

Exemple :

```bash
sudo docker run -d \
--name vaultwarden \
-e ROCKET_TLS='{certs="/ssl/certs.pem",key="/ssl/key.pem"}' \
-v /ssl/keys/:/ssl/ \
-v /vw-data/:/data/ \
-p 443:80 \
vaultwarden/server:latest
```

Le service devient alors accessible via :

```
https://nom-de-domaine
```

---

# Configuration du démarrage automatique

Afin que Vaultwarden redémarre automatiquement après un redémarrage serveur, il est recommandé d'utiliser la politique Docker :

```bash
docker update --restart unless-stopped vaultwarden
```

Cette méthode est préférable à un lancement manuel via cron car Docker gère directement le cycle de vie du conteneur.

---

# Passage à une architecture haute disponibilité

Une fois l'instance Vaultwarden fonctionnelle, l'architecture peut être étendue avec :

- un deuxième serveur Vaultwarden ;
- une seconde base MariaDB ;
- une réplication MariaDB master-master ;
- un tunnel WireGuard ;
- un VPS avec Caddy.

Cette architecture est détaillée dans :

➡️ [Haute disponibilité](./haute-disponibilite.md)

---

# Vérifications finales

Avant de considérer l'installation terminée, vérifier :

- accès HTTPS fonctionnel ;
- connexion avec un client Bitwarden officiel ;
- création d'un élément dans le coffre ;
- synchronisation correcte ;
- sauvegarde des données.

Le serveur Vaultwarden est maintenant opérationnel.
