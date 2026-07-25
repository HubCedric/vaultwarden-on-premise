## Unreleased

### Added

- Monitoring MariaDB/Vaultwarden toutes les cinq minutes sur les deux nœuds.
- Alertes SMTP avec rappel quotidien et notification de rétablissement.
- Arrêt de sécurité optionnel du conteneur Vaultwarden sur le nœud de secours.
- Contrôles quotidien des compteurs et hebdomadaire de réconciliation.
- Installateur, unités systemd, configuration msmtp, logrotate et runbooks complets.

# Changelog

## Unreleased

### Added

- déploiements Docker Compose pour les nœuds et le VPS ;
- documentation d'architecture et d'exploitation ;
- sauvegarde DB + `/data` ;
- mise à jour versionnée avec rollback ;
- contrôle de réplication avec options prudentes ;
- exemples MariaDB, WireGuard, Caddy et systemd ;
- validation GitHub Actions ;
- contrôle pré-déploiement des placeholders et prérequis ;
- checklist de publication GitHub.

### Changed

- routage de référence passé de `least_conn` actif/actif à `first` actif/passif ;
- commande `docker-compose` remplacée par `docker compose` ;
- ancienne documentation monolithique archivée.
