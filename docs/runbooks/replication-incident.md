# Runbook — incident de réplication

## Objectif

Éviter toute nouvelle écriture concurrente, identifier la nature de l'erreur et remettre la réplication en service sans masquer une divergence.

## 1. Sécuriser le trafic

Vérifier si le monitor a arrêté le slave :

```bash
sudo docker inspect -f '{{.State.Status}}' vaultwarden
```

S'il tourne encore alors que la réplication est incertaine, retirer le nœud du load balancer ou l'arrêter manuellement.

## 2. Activer le mode maintenance

Sur les deux nœuds :

```bash
sudo touch /etc/vaultwarden-monitor/maintenance
```

## 3. Collecter les états

Sur les deux nœuds :

```sql
SHOW SLAVE STATUS\G
SELECT @@server_id, @@global.gtid_slave_pos, @@global.gtid_binlog_pos;
```

Conserver au minimum :

- `Slave_IO_Running` ;
- `Slave_SQL_Running` ;
- `Last_IO_Errno` et `Last_IO_Error` ;
- `Last_SQL_Errno` et `Last_SQL_Error` ;
- `Master_Host` et `Master_Server_Id` ;
- `Using_Gtid` et `Gtid_IO_Pos`.

## 4. Ne pas masquer l'erreur

Ne pas utiliser automatiquement :

```sql
SET GLOBAL sql_slave_skip_counter=1;
```

Ne pas exécuter de `CHANGE MASTER` avant d'avoir compris la position GTID et vérifié si les binlogs nécessaires existent encore.

## 5. Vérifier la divergence

Lancer sans `--apply` :

```bash
sudo /opt/vaultwarden-on-premise/scripts/reconcile_split_brain.sh \
  "/root/reconcile-$(date +%F-%H%M)"
```

Relire `report.txt` et les deux fichiers SQL générés.

## 6. Choisir la stratégie

- erreur réseau temporaire sans divergence : rétablir le réseau puis relancer la réplication manuellement ;
- erreur SQL : analyser le schéma et les données avant toute action ;
- GTID absent des binlogs, erreur 1236 ou divergence importante : reconstruire le nœud secondaire depuis une source de vérité ;
- écritures sur les deux côtés : appliquer la procédure de réconciliation ou restaurer depuis un dump validé.

## 7. Validation avant remise en service

Sur les deux nœuds :

- IO et SQL à `Yes` ;
- retard à zéro ;
- aucune erreur ;
- source et `server_id` corrects ;
- réconciliation sans différence ;
- test d'écriture dans chaque sens pendant une fenêtre contrôlée.

## 8. Remise en service

```bash
sudo docker start vaultwarden
sudo rm -f /etc/vaultwarden-monitor/maintenance
sudo /usr/local/lib/vaultwarden-monitor/vaultwarden-replication-monitor.sh --check
```

Ne remettre le slave dans le load balancer qu'après validation complète.
