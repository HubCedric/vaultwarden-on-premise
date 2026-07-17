# Architecture de l'infrastructure

## Vue d'ensemble

L'infrastructure Vaultwarden repose sur une architecture distribuée permettant d'améliorer la disponibilité du service tout en conservant un contrôle complet sur les données.

L'objectif est d'éviter qu'une panne unique (serveur indisponible, coupure Internet, problème matériel...) rende le gestionnaire de mots de passe inaccessible.

L'architecture finale repose sur :

- deux instances Vaultwarden indépendantes ;
- deux bases MariaDB synchronisées ;
- un tunnel VPN WireGuard entre les différents composants ;
- un VPS public servant de point d'entrée ;
- un reverse proxy Caddy assurant l'accès utilisateur.

---

# Schéma global

```text
                             Internet

                                |
                                |
                         Domaine public
                                |
                                |
                           VPS + Caddy
                      Reverse proxy HTTPS
                                |
                                |
                         Tunnel WireGuard
                                |
              +-----------------+-----------------+
              |                                   |
              |                                   |
       Serveur Vaultwarden A              Serveur Vaultwarden B
              |                                   |
              |                                   |
       Vaultwarden A                      Vaultwarden B
              |                                   |
              |                                   |
          MariaDB A  <=================>  MariaDB B

                  Réplication MariaDB
                    master-master
```

---

# Composants

## Vaultwarden

Vaultwarden est une implémentation alternative du serveur Bitwarden.

Il permet d'utiliser les applications officielles Bitwarden tout en hébergeant soi-même le serveur.

Dans cette architecture, deux instances Vaultwarden sont utilisées :

- une instance principale ;
- une instance secondaire.

Les deux instances sont configurées de manière identique afin de pouvoir prendre le relais en cas d'indisponibilité.

---

## MariaDB

Chaque serveur Vaultwarden possède sa propre base de données MariaDB.

Contrairement à une architecture avec une base de données centralisée, chaque nœud fonctionne avec une copie locale complète des données.

Architecture :

```text
Vaultwarden A
      |
      |
  MariaDB A

      ||
      ||
 Réplication
 master-master

      ||
      ||

  MariaDB B
      |
      |
Vaultwarden B
```

La réplication MariaDB permet de synchroniser automatiquement les modifications effectuées sur l'une des bases vers l'autre.

Cette approche permet :

- d'avoir deux copies complètes des données ;
- de continuer à fonctionner temporairement en cas d'indisponibilité d'un serveur ;
- d'éviter un point unique de panne au niveau de la base de données.

Cependant, une réplication master-master nécessite une surveillance attentive afin d'éviter les divergences de données en cas de rupture prolongée de communication.

---

# Réseau

## WireGuard

Les communications internes entre les différents composants utilisent un tunnel VPN WireGuard.

Le VPN permet :

- de chiffrer les échanges entre les serveurs ;
- de ne pas exposer directement les serveurs Vaultwarden sur Internet ;
- d'utiliser des adresses IP privées dédiées à l'infrastructure.

Exemple de plan d'adressage :

```text
Serveur Vaultwarden A :
10.0.0.1

Serveur Vaultwarden B :
10.0.0.2

VPS :
10.0.0.10
```

Les échanges entre :

- Caddy et Vaultwarden ;
- MariaDB A et MariaDB B ;
- les différents scripts de supervision ;

passent par ce réseau privé.

---

# VPS et reverse proxy

Le VPS constitue le seul point accessible depuis Internet.

Son rôle est :

- recevoir les connexions HTTPS des utilisateurs ;
- gérer les certificats TLS ;
- transmettre les requêtes vers les serveurs Vaultwarden disponibles.

Le reverse proxy utilisé est **Caddy**.

Avantages :

- configuration simple ;
- gestion automatique des certificats Let's Encrypt ;
- possibilité de basculer automatiquement vers un autre serveur Vaultwarden.

Architecture :

```text
Utilisateur

    |
    |
 HTTPS

    |

Caddy (VPS)

    |
    |
 HTTPS via WireGuard

    |
    +------------+
    |            |
Vaultwarden A  Vaultwarden B
```

---

# Stockage des données

Les données sensibles sont stockées uniquement sur les serveurs privés.

La base MariaDB contient notamment :

- les utilisateurs ;
- les coffres ;
- les éléments enregistrés ;
- les paramètres utilisateurs.

Les données restent chiffrées conformément au fonctionnement de Vaultwarden/Bitwarden.

Le VPS ne stocke aucune donnée utilisateur. Son rôle est uniquement de servir de passerelle réseau.

---

# Haute disponibilité

La disponibilité repose sur plusieurs mécanismes complémentaires :

## Redondance applicative

Deux instances Vaultwarden sont disponibles.

Si un serveur devient indisponible, le second peut continuer à fournir le service.

## Redondance des données

Chaque serveur possède sa propre base MariaDB.

La réplication master-master maintient les deux copies synchronisées.

## Séparation physique

Les deux serveurs Vaultwarden sont hébergés sur des emplacements différents.

Cela permet de limiter l'impact d'un incident physique :

- panne électrique ;
- panne matérielle ;
- problème réseau local ;
- sinistre.

---

# Limites de l'architecture

Cette architecture améliore fortement la disponibilité, mais elle n'élimine pas tous les risques.

Points d'attention :

- une mauvaise gestion de la réplication MariaDB peut provoquer une divergence des données ;
- une erreur de configuration peut être répliquée sur les deux bases ;
- les sauvegardes restent indispensables ;
- les mises à jour doivent être réalisées avec précaution.

La réplication n'est donc pas considérée comme un remplacement complet des sauvegardes.

---

# Évolution possible

Plusieurs améliorations pourraient être envisagées :

- ajout d'une sauvegarde externalisée régulière ;
- automatisation complète des tests de restauration ;
- supervision centralisée ;
- ajout d'un troisième nœud de lecture ;
- amélioration du monitoring réseau et applicatif.

---

# Résumé

L'architecture finale repose donc sur :

| Élément | Rôle |
| --- | --- |
| Vaultwarden | Serveur de gestion des mots de passe |
| MariaDB | Stockage local des données sur chaque nœud |
| Réplication MariaDB master-master | Synchronisation des deux bases |
| WireGuard | Réseau privé chiffré entre les composants |
| VPS | Point d'entrée public |
| Caddy | Reverse proxy HTTPS et gestion TLS |

Cette architecture permet d'obtenir un gestionnaire de mots de passe auto-hébergé, résilient et accessible depuis l'extérieur tout en conservant la maîtrise complète de l'infrastructure.
