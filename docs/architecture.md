# Architecture de l'infrastructure

## Vue d'ensemble

L'infrastructure Vaultwarden repose sur une architecture distribuée conçue pour améliorer la disponibilité du service tout en conservant une maîtrise complète des données.

L'objectif est de limiter les points uniques de défaillance. Une panne matérielle, une coupure réseau ou l'indisponibilité d'un serveur ne doivent pas rendre le gestionnaire de mots de passe totalement inaccessible.

L'architecture retenue s'appuie sur les éléments suivants :

- deux instances Vaultwarden indépendantes ;
- deux bases de données MariaDB synchronisées ;
- un tunnel VPN WireGuard entre les différents composants ;
- un VPS public servant de point d'entrée ;
- un reverse proxy Caddy assurant l'exposition du service en HTTPS.

---

## Schéma global

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

Cette architecture repose sur un point d'entrée public unique, tandis que les composants applicatifs et les bases de données restent sur un réseau privé.

Les serveurs Vaultwarden ne sont donc pas directement exposés à Internet. Le trafic utilisateur transite par le VPS, puis rejoint les nœuds applicatifs via WireGuard.

---

## Composants

### Vaultwarden

Vaultwarden est une implémentation alternative du serveur Bitwarden, compatible avec les clients officiels Bitwarden.

Dans cette architecture, deux instances distinctes sont déployées :

- une instance principale ;
- une instance secondaire.

Les deux nœuds sont configurés de manière similaire afin de permettre une continuité de service en cas d'indisponibilité de l'un d'eux.

Vaultwarden ne stocke pas directement ses données métier dans des fichiers applicatifs locaux. Les informations persistantes sont externalisées dans MariaDB.

### MariaDB

Chaque serveur Vaultwarden dispose de sa propre instance MariaDB locale.

Ce choix évite de dépendre d'une base centralisée unique et permet à chaque nœud de fonctionner avec une copie complète des données applicatives.

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

La réplication MariaDB synchronise automatiquement les modifications d'une base vers l'autre.

Cette architecture permet :

- de disposer de deux copies complètes des données ;
- de réduire le risque de point unique de panne au niveau de la base ;
- de maintenir temporairement le service en cas d'indisponibilité d'un des nœuds.

En contrepartie, une réplication master-master impose une surveillance régulière. En cas de rupture prolongée entre les deux serveurs, un risque de divergence de données peut apparaître.

---

## Réseau privé

### WireGuard

Les échanges internes entre les différents composants s'appuient sur un tunnel VPN WireGuard.

Ce réseau privé remplit plusieurs fonctions :

- chiffrer les communications inter-serveurs ;
- isoler les flux internes du réseau public ;
- fournir un plan d'adressage privé dédié à l'infrastructure.

Exemple de plan d'adressage :

```text
Serveur Vaultwarden A : 10.0.0.1
Serveur Vaultwarden B : 10.0.0.2
VPS : 10.0.0.10
```

Les communications suivantes transitent exclusivement par ce réseau privé :

- les échanges entre Caddy et les instances Vaultwarden ;
- la réplication entre MariaDB A et MariaDB B ;
- les scripts d'administration, de supervision et de contrôle.

Cette approche limite l'exposition réseau des nœuds internes et simplifie la maîtrise des flux autorisés.

---

## Point d'entrée public

### VPS et reverse proxy

Le VPS constitue l'unique composant accessible depuis Internet.

Son rôle est de centraliser l'entrée du trafic utilisateur, de terminer les connexions HTTPS et de transmettre les requêtes vers les serveurs Vaultwarden disponibles.

Le reverse proxy utilisé est **Caddy**.

Ses avantages dans cette architecture sont les suivants :

- configuration simple et lisible ;
- gestion automatique des certificats TLS ;
- possibilité d'orienter le trafic vers le nœud applicatif disponible ;
- séparation claire entre exposition publique et services internes.

```text
Utilisateur
    |
    |
  HTTPS
    |
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

Le VPS ne porte pas la donnée métier. Il agit uniquement comme passerelle d'accès et point de contrôle réseau.

---

## Stockage des données

Les données sensibles sont stockées exclusivement sur les serveurs privés hébergeant Vaultwarden et MariaDB.

La base MariaDB contient notamment :

- les comptes utilisateurs ;
- les coffres ;
- les éléments enregistrés ;
- les paramètres associés aux utilisateurs.

Le VPS public n'a pas vocation à stocker des données applicatives utilisateur. Son rôle se limite au reverse proxy, à la terminaison TLS et à l'acheminement du trafic.

Conformément au fonctionnement de Vaultwarden et des clients Bitwarden, les données sensibles restent chiffrées côté applicatif selon le modèle prévu par la solution.

---

## Disponibilité

La disponibilité du service repose sur plusieurs mécanismes complémentaires.

### Redondance applicative

Deux instances Vaultwarden sont déployées sur des nœuds distincts.

Si l'une devient indisponible, l'autre peut continuer à assurer le service, sous réserve que les dépendances associées restent opérationnelles.

### Redondance des données

Chaque nœud dispose de sa propre base MariaDB.

La réplication master-master maintient les deux copies synchronisées et évite de concentrer l'ensemble des données sur une seule base centrale.

### Séparation physique

Les serveurs Vaultwarden sont hébergés sur des emplacements distincts.

Cette séparation réduit l'impact d'un incident localisé, par exemple :

- une panne électrique ;
- une panne matérielle ;
- une perte de connectivité locale ;
- un incident physique sur un site donné.

---

## Limites et points d'attention

Cette architecture améliore nettement la résilience du service, mais elle ne supprime pas l'ensemble des risques d'exploitation.

Les principaux points de vigilance sont les suivants :

- une divergence MariaDB peut apparaître en cas de désynchronisation prolongée ;
- une erreur d'administration peut être répliquée sur les deux nœuds ;
- la réplication ne remplace pas une stratégie de sauvegarde ;
- les opérations de mise à jour doivent être réalisées avec méthode.

La haute disponibilité ne dispense donc ni de la supervision, ni des sauvegardes, ni des procédures de restauration testées.

---

## Évolutions possibles

Plusieurs axes d'amélioration peuvent être envisagés à moyen terme :

- mise en place d'une sauvegarde externalisée régulière ;
- automatisation des tests de restauration ;
- centralisation de la supervision ;
- amélioration du monitoring réseau et applicatif ;
- ajout d'un nœud supplémentaire selon les besoins d'évolution.

Ces évolutions ne sont pas indispensables au fonctionnement actuel, mais elles peuvent renforcer la robustesse globale de l'infrastructure.

---

## Synthèse

L'architecture repose sur les composants suivants :

| Élément | Rôle |
| --- | --- |
| Vaultwarden | Serveur de gestion des mots de passe |
| MariaDB | Stockage local des données sur chaque nœud |
| Réplication MariaDB master-master | Synchronisation des deux bases |
| WireGuard | Réseau privé chiffré entre les composants |
| VPS | Point d'entrée public |
| Caddy | Reverse proxy HTTPS et gestion TLS |

Cette organisation permet de disposer d'un gestionnaire de mots de passe auto-hébergé, accessible depuis l'extérieur, tout en conservant une séparation nette entre exposition publique, traitement applicatif et stockage des données.
