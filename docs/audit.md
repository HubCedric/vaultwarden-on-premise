# Audit du dépôt d'origine

## Résumé

Le dépôt fourni contenait déjà un travail documentaire conséquent : séparation en plusieurs fichiers Markdown, scripts de mise à jour, contrôle de réplication et réconciliation après split-brain. La reconstruction conserve ce retour d'expérience mais sépare désormais trois couches :

1. **déploiement reproductible** : Compose, Caddy, MariaDB et WireGuard ;
2. **documentation d'exploitation** : procédures courantes et reprise ;
3. **outillage sensible** : scripts normaux et scripts expérimentaux clairement identifiés.

## Points positifs conservés

- documentation issue d'incidents réels ;
- refus de corriger automatiquement un conflit SQL ;
- sauvegarde avant mise à jour ;
- contrôle des migrations et possibilité de rollback ;
- procédure de réconciliation des données après divergence ;
- séparation physique des deux nœuds.

## Problèmes corrigés

### Dépôt surtout documentaire

Le dépôt précédent décrivait des commandes, mais ne fournissait pas de `compose.yaml`, de Caddyfile déployable, de configurations WireGuard/MariaDB ni de CI. Ces éléments sont maintenant présents.

### Commande Compose historique

Les scripts utilisaient `docker-compose`. La version courante utilise `docker compose` et la spécification Compose moderne.

### Variable locale absente

Le script de contrôle de réplication utilisait `LOCAL_DB_HOST` et `LOCAL_DB_PORT`, mais ces variables n'étaient pas définies dans le fichier `.env.example`. Elles sont maintenant explicites.

### Confusion entre indisponibilité et absence de réplication

Une requête distante en erreur pouvait être interprétée comme un `SHOW SLAVE STATUS` vide. Le nouveau script distingue le code retour de connexion du contenu SQL.

### Routage actif/actif dangereux

Le Caddyfile historique utilisait `least_conn` sur les deux instances. Avec une réplication MariaDB asynchrone, cela répartit les écritures sur les deux bases et augmente fortement le risque de divergence. La référence utilise désormais `lb_policy first` avec contrôle de santé : un nœud actif, un nœud de secours.

### TLS interne avec vérification désactivée

Le dépôt précédent proposait HTTPS vers des adresses WireGuard avec `tls_insecure_skip_verify`. Le nouveau design utilise HTTP dans le tunnel WireGuard : le chiffrement est assuré par WireGuard, sans faux sentiment de validation TLS.

### Redémarrage par cron

Le lancement du conteneur au démarrage via `@reboot docker rm && docker run` a été remplacé par `restart: unless-stopped` dans Compose. Les tâches périodiques utilisent des timers systemd fournis en exemple.

### Sauvegarde incomplète

Un dump MariaDB ne couvre pas les pièces jointes, les fichiers Send, les clés RSA et certains fichiers de configuration présents dans `/data`. Le script de sauvegarde couvre maintenant la base et le répertoire persistant.

## Décisions importantes

- Une seule version Vaultwarden explicite dans `.env`.
- MariaDB et Vaultwarden sont conteneurisés sur chaque nœud.
- Les ports sont liés à l'adresse WireGuard, pas à toutes les interfaces.
- Caddy est le seul point d'entrée public.
- La réplication automatique n'est pas assimilée à une sauvegarde.
- Les outils de réconciliation restent dans `scripts/experimental/`.

## Limites non supprimées

La réplication dual-primary demeure asynchrone. Elle ne fournit ni quorum, ni protection native contre deux nœuds acceptant simultanément des écritures après partition réseau. L'exploitation doit donc appliquer une discipline de fencing : un seul nœud est autorisé à servir le trafic tant que la cohérence n'est pas confirmée.
