# Plan de reprise après sinistre

## 1. Priorités

1. empêcher de nouvelles écritures contradictoires ;
2. préserver les deux états existants ;
3. remettre un service fiable, pas seulement un service qui répond ;
4. reconstruire la redondance après validation.

## 2. Classification

| Incident | Exemple | Réponse |
| --- | --- | --- |
| Applicatif | conteneur arrêté | redémarrage contrôlé |
| Base locale | MariaDB indisponible | restauration ou reconstruction depuis le pair |
| Réseau | WireGuard coupé | réparer avant de toucher aux données |
| Réplication | thread IO arrêté | redémarrage prudent après diagnostic |
| Divergence | écritures sur A et B | gel, sauvegarde, réconciliation |
| Perte de site | disque/serveur détruit | restauration depuis backup et pair sain |
| Compromission | secrets ou hôte compromis | isolation, rotation, reconstruction |

## 3. Gel de l'incident

- retirer un nœud de Caddy ;
- arrêter Vaultwarden sur le nœud non choisi ;
- bloquer temporairement 3306 si nécessaire ;
- noter les heures, versions et symptômes ;
- faire des dumps séparés nommés `node-a` et `node-b` ;
- archiver `/data` des deux côtés.

## 4. Choisir la source de vérité

Ne choisissez pas uniquement en fonction du nom `master` ou `slave`. Examinez :

- quel nœud a servi le trafic ;
- la date des dernières écritures ;
- les utilisateurs concernés ;
- les éléments manquants ;
- les pièces jointes ;
- les erreurs de réplication ;
- les GTID.

## 5. Réconciliation

L'outil expérimental peut produire des fichiers SQL à relire :

```bash
scripts/experimental/reconcile_split_brain.sh /tmp/reconcile-report
```

Ne lancez `--apply` qu'après :

- lecture du code ;
- sauvegarde des deux bases ;
- lecture complète des fichiers SQL ;
- test sur copies isolées ;
- validation du sens de chaque correction.

Les tables d'association sans date et les suppressions sont particulièrement difficiles à réconcilier automatiquement.

## 6. Reconstruction recommandée

Après choix d'une base saine :

1. maintenir le nœud source seul en service ;
2. sauvegarder source DB + `/data` ;
3. supprimer ou isoler la base du nœud à reconstruire ;
4. restaurer un clone complet ;
5. aligner la version Vaultwarden ;
6. réinitialiser les métadonnées de réplication ;
7. configurer GTID vers la source ;
8. tester dans les deux sens ;
9. remettre le nœud reconstruit en secours ;
10. documenter les causes et actions préventives.

## 7. Perte totale des deux nœuds

1. reconstruire WireGuard et le VPS ;
2. déployer un nœud unique ;
3. restaurer la dernière sauvegarde validée ;
4. tester les clients ;
5. remettre le service public ;
6. reconstruire le second nœud plus tard ;
7. réinitialiser la réplication depuis le nœud restauré.

La priorité est un nœud fiable, pas la restauration immédiate de la complexité HA.

## 8. Compromission

Une restauration sur un hôte compromis n'est pas suffisante. Reconstruisez depuis une image système propre, changez :

- clés SSH ;
- clés WireGuard ;
- mots de passe MariaDB ;
- token admin ;
- identifiants du registrar/DNS si exposés ;
- secrets de sauvegarde.

Analysez les journaux et considérez les sauvegardes réalisées après la compromission comme potentiellement suspectes.

## 9. Validation de sortie de crise

- accès HTTPS fonctionnel ;
- création et synchronisation d'un élément test ;
- pièces jointes accessibles ;
- 2FA fonctionnelle ;
- backup post-reprise créé ;
- réplication saine ou volontairement désactivée ;
- un seul nœud actif ;
- compte rendu d'incident rédigé.
