# Vaultwarden On-Premise

[![Quality checks](https://github.com/HubCedric/bitwarden-on-premise/actions/workflows/quality.yml/badge.svg)](https://github.com/HubCedric/bitwarden-on-premise/actions/workflows/quality.yml)
![Vaultwarden](https://img.shields.io/badge/Vaultwarden-self--hosted-175DDC)
![Docker Compose](https://img.shields.io/badge/Docker-Compose-2496ED)
![MariaDB](https://img.shields.io/badge/MariaDB-replication-C0765A)
![WireGuard](https://img.shields.io/badge/WireGuard-private_network-88171A)
![Caddy](https://img.shields.io/badge/Caddy-reverse_proxy-1F88C0)

Infrastructure reproductible et documentation d'exploitation pour héberger Vaultwarden sur un ou deux sites, avec MariaDB, WireGuard, Caddy, sauvegardes et procédures de reprise.

> [!WARNING]
> Ce dépôt décrit une infrastructure personnelle. La variante haute disponibilité utilise une réplication MariaDB asynchrone à deux nœuds : elle améliore la continuité de service, mais ne remplace ni un cluster à quorum ni des sauvegardes testées.

## Ce que contient le dépôt

- un déploiement Docker Compose pour chaque nœud Vaultwarden ;
- un reverse proxy Caddy sur VPS ;
- des exemples WireGuard et MariaDB ;
- des scripts de sauvegarde, mise à jour et contrôle de réplication ;
- une documentation d'installation, d'architecture, d'exploitation et de reprise après incident ;
- des contrôles GitHub Actions pour les scripts, le YAML et les liens internes.

## Architecture de référence

```mermaid
flowchart TB
    U[Clients Bitwarden] -->|HTTPS| C[Caddy sur VPS]
    C -->|WireGuard / HTTP privé| A[Vaultwarden A - actif]
    C -. basculement .->|WireGuard / HTTP privé| B[Vaultwarden B - secours]
    A --> DBA[(MariaDB A)]
    B --> DBB[(MariaDB B)]
    DBA <-->|Réplication GTID asynchrone| DBB
```

Le routage applicatif est **actif/passif**. Caddy utilise le premier nœud sain dans l'ordre déclaré. Cela réduit les écritures concurrentes par rapport à un équilibrage actif/actif. Lors d'un basculement, le retour du nœud A doit rester contrôlé jusqu'à validation de la réplication.

## Démarrage rapide

### 1. Préparer un nœud

```bash
git clone https://github.com/HubCedric/bitwarden-on-premise.git
cd bitwarden-on-premise/deploy/node
cp .env.example .env
cp config/mariadb/50-server-node-a.cnf.example config/mariadb/50-server.cnf
nano .env
mkdir -p data/mariadb data/vaultwarden
chmod 700 data
```

### 2. Valider et démarrer

```bash
../../scripts/preflight.sh
docker compose --env-file .env config
docker compose --env-file .env up -d
```

### 3. Vérifier

```bash
docker compose ps
curl --fail http://10.0.0.1:8080/alive
```

Pour un second nœud, utilisez l'exemple MariaDB `node-b`, changez les adresses, les secrets et le nom du projet Compose.

## Documentation

Le dossier [`docs/`](docs/) regroupe la documentation détaillée du projet. Les documents sont classés ci-dessous par usage afin de faciliter la navigation.

### Point d'entrée

| Document | Contenu |
| --- | --- |
| [Index de la documentation](docs/index.md) | Vue d'ensemble et point d'entrée principal de la documentation. |
| [Audit du dépôt d'origine](docs/audit.md) | Analyse de l'ancien dépôt, constats et décisions de restructuration. |
| [Checklist de publication](docs/publication-checklist.md) | Vérifications à effectuer avant ou après une publication sur GitHub. |

### Architecture et conception

| Document | Contenu |
| --- | --- |
| [Architecture applicative](docs/architecture.md) | Composants, flux réseau, rôles des serveurs et fonctionnement général. |
| [Décision d'architecture : routage actif/passif](docs/adr/0001-active-passive-routing.md) | Raisons du choix d'un routage actif/passif plutôt qu'actif/actif. |
| [Haute disponibilité](docs/high-availability.md) | Architecture de redondance, réplication et principes de basculement. |
| [Haute disponibilité — documentation historique](docs/haute-disponibilite.md) | Ancienne documentation en français conservée pour référence. |

### Installation et configuration

| Document | Contenu |
| --- | --- |
| [Installation](docs/installation.md) | Mise en place complète de l'infrastructure depuis un environnement vierge. |
| [Configuration](docs/configuration.md) | Variables, fichiers d'environnement et paramètres des différents composants. |
| [Migration SQLite vers MariaDB](docs/migration-sqlite-mariadb.md) | Procédure et précautions pour migrer la base de données Vaultwarden. |

### Exploitation et maintenance

| Document | Contenu |
| --- | --- |
| [Runbook d'exploitation](docs/operations.md) | Opérations courantes, contrôles, commandes utiles et procédures quotidiennes. |
| [Maintenance](docs/maintenance.md) | Procédures historiques de maintenance et de mise à jour. |
| [Sauvegarde et restauration](docs/backup-restore.md) | Stratégie de sauvegarde, vérifications et procédure de restauration. |
| [Restauration — documentation historique](docs/restauration.md) | Ancienne procédure de restauration conservée pour référence. |

### Incidents et reprise

| Document | Contenu |
| --- | --- |
| [Plan de reprise après sinistre](docs/disaster-recovery.md) | Procédures de reprise après perte d'un nœud, divergence ou incident majeur. |
| [Dépannage](docs/troubleshooting.md) | Diagnostic des pannes fréquentes et pistes de résolution. |
| [Debug — retours d'expérience](docs/debug.md) | Incidents techniques rencontrés et corrections appliquées. |

### Sécurité

| Document | Contenu |
| --- | --- |
| [Sécurité](docs/security.md) | Durcissement, gestion des secrets, exposition réseau et bonnes pratiques. |
| [Sécurité — documentation historique](docs/securite.md) | Ancienne documentation de sécurité conservée pour référence. |

### Historique

| Document | Contenu |
| --- | --- |
| [README historique](docs/history/legacy-readme.md) | Version archivée de l'ancien README monolithique. |

## Scripts principaux

```text
scripts/
├── backup_vaultwarden.sh       Sauvegarde cohérente DB + données persistantes
├── check_replication.sh        Contrôle et redémarrage prudent de la réplication
├── healthcheck.sh              Contrôle applicatif, base et réplication
├── preflight.sh                Vérification des placeholders et prérequis
├── update_vaultwarden.sh       Mise à jour versionnée avec backup et rollback
├── validate_repo.sh            Validation locale du dépôt
└── experimental/               Outils sensibles issus du retour d'expérience
```

Copiez [`scripts/.env.example`](scripts/.env.example) vers `scripts/.env`, adaptez les valeurs et protégez le fichier :

```bash
chmod 600 scripts/.env
```

## Principes d'exploitation

1. Ne jamais utiliser `latest` en production : déployer une version explicite.
2. Sauvegarder la base **et** le répertoire `/data` de Vaultwarden.
3. Tester périodiquement une restauration sur une machine isolée.
4. Ne jamais ignorer automatiquement une erreur SQL de réplication.
5. Après un basculement, empêcher le retour automatique d'un nœud divergent.
6. Restreindre MariaDB et Vaultwarden au réseau WireGuard.
7. Conserver une copie de sauvegarde hors site et chiffrée.

## État du projet

Le déploiement simple est la base recommandée. La partie haute disponibilité est volontairement marquée comme avancée et doit être adaptée à votre version de MariaDB, votre réseau et votre tolérance au risque.

## Licence et responsabilité

Vaultwarden est un projet tiers non affilié à Bitwarden, Inc. Ce dépôt n'embarque pas Vaultwarden ; il fournit uniquement des fichiers de déploiement et de la documentation. Choisissez une licence GitHub adaptée avant publication publique du dépôt.
