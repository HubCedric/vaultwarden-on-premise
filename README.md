# Vaultwarden On-Premise

![Vaultwarden](https://img.shields.io/badge/Vaultwarden-On--Premise-blue)
![Docker](https://img.shields.io/badge/Docker-Containerized-blue)
![MariaDB](https://img.shields.io/badge/MariaDB-Database-orange)
![WireGuard](https://img.shields.io/badge/WireGuard-VPN-green)

## Présentation du projet

Ce dépôt documente la mise en place d'une infrastructure **Vaultwarden auto-hébergée** permettant de disposer d'un gestionnaire de mots de passe personnel avec une maîtrise complète de l'infrastructure.

L'objectif initial était de migrer depuis l'offre **Bitwarden SaaS** vers une solution hébergée localement afin de limiter la dépendance à une infrastructure tierce tout en conservant une expérience utilisateur similaire grâce à la compatibilité avec les clients Bitwarden officiels.

La solution retenue est **Vaultwarden**, une implémentation alternative compatible avec l'écosystème Bitwarden et particulièrement adaptée aux environnements disposant de ressources limitées.

## Objectifs

Les objectifs principaux du projet sont :

- Héberger soi-même son gestionnaire de mots de passe.
- Garder la maîtrise complète des données.
- Disposer d'une solution accessible depuis l'extérieur.
- Garantir une disponibilité suffisante pour un usage quotidien.
- Mettre en place une architecture résiliente capable de supporter une panne serveur.

## Architecture globale

L'infrastructure finale repose sur plusieurs composants :

| Composant | Rôle |
| --- | --- |
| Vaultwarden | Application de gestion des mots de passe |
| Docker | Conteneurisation du service |
| MariaDB | Stockage des données applicatives |
| WireGuard | Tunnel VPN sécurisé entre les différents sites |
| Caddy | Reverse proxy et gestion automatique des certificats TLS |
| VPS | Point d'entrée public et répartition du trafic |

L'architecture utilise deux instances Vaultwarden situées sur deux emplacements physiques différents afin d'améliorer la résilience :

```text
                    Internet
                       |
                       |
                  VPS + Caddy
                       |
                 Tunnel WireGuard
                       |
        +--------------+--------------+
        |                             |
  Vaultwarden A                 Vaultwarden B
        |                             |
        +--------- MariaDB -----------+
              Réplication
              master-master
```

Le VPS agit comme point d'entrée unique. Les serveurs Vaultwarden ne sont pas exposés directement sur Internet et communiquent uniquement via le tunnel VPN.

## Environnement utilisé

L'infrastructure a été conçue pour fonctionner sur du matériel léger :

- Raspberry Pi ;
- machine virtuelle Freebox OS ;
- serveur Linux classique ;
- VPS disposant d'une connectivité IPv4/IPv6.

## Documentation

La documentation détaillée est disponible dans le dossier [`docs`](./docs).

- [Architecture](./docs/architecture.md)
- [Installation](./docs/installation.md)
- [Haute disponibilité](./docs/haute-disponibilite.md)
- [Maintenance](./docs/maintenance.md)
- [Sécurité](./docs/securite.md)
- [Debug](./docs/debug.md)
- [Restauration](./docs/restauration.md)

## Scripts

Les scripts d'administration sont disponibles dans le dossier [`scripts`](./scripts).

Ils permettent notamment :

- la mise à jour sécurisée de Vaultwarden ;
- la surveillance de la réplication MariaDB ;
- la réconciliation des données après divergence.

## Avertissement

Cette documentation correspond à une infrastructure personnelle mise en place à titre expérimental.

Même si l'architecture apporte une meilleure disponibilité et une meilleure maîtrise des données, l'auto-hébergement implique également une responsabilité importante :

- maintenir les systèmes à jour ;
- surveiller les services ;
- effectuer des sauvegardes régulières ;
- tester les procédures de restauration.

Un gestionnaire de mots de passe étant un élément critique, il est recommandé de bien comprendre chaque composant avant de déployer une architecture similaire en production.
