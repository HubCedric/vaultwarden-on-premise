# Runbook d'exploitation

## 1. Contrôle quotidien

```bash
cd /opt/vaultwarden-on-premise/scripts
./healthcheck.sh
sudo /usr/local/lib/vaultwarden-monitor/vaultwarden-replication-monitor.sh --check
```

Résultat attendu :

- conteneurs `mariadb` et `vaultwarden` actifs ;
- endpoint `/alive` en HTTP 200 ;
- requête SQL locale réussie ;
- threads IO et SQL de réplication à `Yes` ;
- retard inférieur au seuil.

## 2. Contrôle du VPS

```bash
cd /opt/vaultwarden-proxy
docker compose ps
docker compose logs --since 30m caddy
curl --fail https://vault.example.net/alive
```

## 3. Sauvegarde manuelle

```bash
cd /opt/vaultwarden-on-premise/scripts
./backup_vaultwarden.sh
```

Une sauvegarde complète contient :

- `database.sql.gz` ;
- `vaultwarden-data.tar.gz` ;
- `SHA256SUMS` ;
- `manifest.txt`.

Copiez ensuite le répertoire vers une cible hors site chiffrée.

## 4. Mise à jour Vaultwarden

### Préparation

1. lire les notes de version ;
2. vérifier la réplication ;
3. retirer le nœud secondaire de la rotation ou maintenir un seul nœud actif ;
4. lancer une sauvegarde ;
5. mettre à jour un seul nœud à la fois.

### Exécution

```bash
cd /opt/vaultwarden-on-premise/scripts
./update_vaultwarden.sh 1.36.0
```

Le script :

1. valide la version cible ;
2. exécute une sauvegarde ;
3. modifie `VAULTWARDEN_VERSION` dans le `.env` de déploiement ;
4. redéploie ;
5. attend le healthcheck ;
6. inspecte les logs ;
7. restaure la version précédente si le conteneur ne devient pas sain.

> [!CAUTION]
> Le rollback d'image ne remet pas automatiquement le schéma SQL dans son état précédent. En cas de migration partiellement appliquée, la sauvegarde reste le point de retour réel.

## 5. Mise à jour MariaDB

La réplication exige la même version majeure et idéalement la même version mineure sur les deux nœuds.

Procédure :

1. sauvegarder les deux nœuds ;
2. vérifier les notes de compatibilité ;
3. mettre hors rotation B ;
4. mettre à jour B ;
5. valider B et la réplication ;
6. basculer temporairement vers B si nécessaire ;
7. mettre à jour A ;
8. vérifier les schémas et la réplication ;
9. remettre A en priorité.

Ne lancez pas deux migrations Vaultwarden simultanées sur deux nœuds.

## 6. Rotation des secrets

### Mot de passe applicatif MariaDB

La rotation doit être coordonnée entre :

- l'utilisateur MariaDB ;
- `MARIADB_PASSWORD` ;
- `DATABASE_URL` ;
- `scripts/.env`.

Effectuez la rotation nœud par nœud et validez une connexion avant de fermer la session SQL d'administration.

### Token admin

Remplacez le hash dans `deploy/node/.env`, redéployez et testez `/admin`. N'exposez pas cette interface publiquement sans restriction supplémentaire.

### WireGuard

Pour changer une clé :

1. générer une nouvelle paire ;
2. mettre à jour les peers correspondants ;
3. redémarrer le peer modifié ;
4. vérifier les handshakes ;
5. supprimer l'ancienne clé.

## 7. Basculement vers B

### Basculement planifié

1. arrêter les écritures sur A ou mettre A hors rotation ;
2. attendre un retard nul ;
3. vérifier `SHOW SLAVE STATUS\G` sur B ;
4. placer B en premier dans `deploy/vps/.env` ou le Caddyfile ;
5. recharger Caddy ;
6. tester une création puis une lecture d'élément ;
7. contrôler que la transaction est visible sur A.

### Basculement d'urgence

Si A est indisponible, Caddy peut sélectionner B. Consignez l'heure exacte. Ne redémarrez pas A dans la rotation avant l'analyse des transactions effectuées sur B.

## 8. Retour vers A

1. maintenir A hors rotation ;
2. restaurer la connectivité ;
3. vérifier les deux GTID et les erreurs SQL ;
4. laisser la réplication rattraper ;
5. comparer les comptes d'enregistrements et les données critiques ;
6. tester une écriture de B vers A ;
7. remettre A en premier seulement après validation.

En présence d'une divergence, appliquer le [plan de reprise](disaster-recovery.md), pas un simple `START SLAVE`.

## 9. Journaux utiles

```bash
# Nœud
docker compose -f deploy/node/compose.yaml --env-file deploy/node/.env logs --since 1h vaultwarden
docker compose -f deploy/node/compose.yaml --env-file deploy/node/.env logs --since 1h mariadb

# VPS
docker compose -f deploy/vps/compose.yaml --env-file deploy/vps/.env logs --since 1h caddy

# Timers
journalctl -u vaultwarden-backup.service
journalctl -u vaultwarden-replication-monitor.service
```

## 10. Fréquences recommandées

| Contrôle | Fréquence |
| --- | --- |
| Healthcheck applicatif | toutes les 5 à 15 minutes |
| Réplication | toutes les 5 minutes |
| Sauvegarde complète | quotidienne |
| Copie hors site | quotidienne |
| Test de restauration | trimestriel |
| Revue des mises à jour | mensuelle |
| Revue du pare-feu et des accès | trimestrielle |


## 11. Supervision automatisée

Le paquet de supervision détaillé dans [monitoring.md](monitoring.md) contrôle les deux sens de réplication toutes les cinq minutes, surveille l’état Docker et peut arrêter uniquement le nœud de secours.

```bash
systemctl list-timers --all | grep vaultwarden
```

En cas d’alerte, suivre le [runbook incident de réplication](runbooks/replication-incident.md).
