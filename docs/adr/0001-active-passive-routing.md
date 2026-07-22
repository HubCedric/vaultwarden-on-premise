# ADR-0001 — Routage actif/passif

- **Statut** : accepté
- **Date** : 2026-07-21

## Contexte

Deux instances Vaultwarden utilisent deux bases MariaDB reliées par une réplication GTID asynchrone. Un équilibrage actif/actif envoie des écritures aux deux bases. Une coupure de réplication peut alors produire deux historiques valides mais incompatibles.

## Décision

Le reverse proxy Caddy utilise la stratégie `first` :

1. nœud A en priorité ;
2. nœud B uniquement lorsque A est déclaré indisponible ;
3. contrôles de santé actifs sur `/alive` ;
4. maintien hors rotation d'un nœud revenu après incident jusqu'à validation de la réplication.

## Conséquences

### Positives

- la majorité des écritures se fait sur un seul nœud ;
- moins de conflits applicatifs et de migrations simultanées ;
- procédure de basculement compréhensible ;
- comportement Caddy lisible.

### Négatives

- le basculement ne garantit pas un RPO nul ;
- un retour automatique du nœud prioritaire peut être dangereux s'il a divergé ;
- une intervention humaine reste nécessaire après un incident significatif ;
- la réplication dual-primary reste complexe.

## Alternatives rejetées

- `least_conn` ou `round_robin` : écritures concurrentes sur les deux nœuds ;
- base MariaDB unique : point de panne unique ;
- Galera : architecture plus cohérente pour le multi-primary, mais beaucoup plus lourde pour ce projet personnel et non validée ici ;
- réplication primaire/réplique stricte : plus sûre, mais nécessite une procédure de promotion et de reconfiguration lors du basculement.
