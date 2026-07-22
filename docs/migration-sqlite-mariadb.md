# Migration SQLite vers MariaDB

## 1. Risques

La migration change le moteur de base et peut modifier les types, index, collations et contraintes. Le retour d'expérience d'origine a montré qu'un outil de conversion générique pouvait transformer des colonnes UUID en `TEXT`, puis casser de futures migrations Vaultwarden utilisant des clés étrangères.

La méthode la plus sûre est une migration supportée et vérifiée sur une copie de test. Ne réalisez pas la conversion directement sur l'unique instance de production.

## 2. Préparation

1. mettre Vaultwarden à une version connue et explicite ;
2. exporter le coffre depuis un client comme filet de sécurité supplémentaire ;
3. arrêter les écritures ;
4. sauvegarder le fichier SQLite et tout `/data` ;
5. créer une VM de test ;
6. installer la même version Vaultwarden avec MariaDB vide.

## 3. Vérifications avant import

```bash
sqlite3 db.sqlite3 'PRAGMA integrity_check;'
sqlite3 db.sqlite3 '.tables'
```

Le résultat de `integrity_check` doit être `ok`.

## 4. Conversion

Le dépôt ne lance pas automatiquement `sqlite3-to-mysql`, car la conversion dépend des versions et du schéma. Si cet outil est utilisé, inspectez impérativement le schéma généré avant démarrage de Vaultwarden.

Exemples de contrôles :

```sql
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, COLUMN_TYPE
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA='vaultwarden'
  AND (COLUMN_NAME='uuid' OR COLUMN_NAME='id' OR COLUMN_NAME LIKE '%\_uuid');
```

Recherchez les colonnes UUID en `TEXT` :

```sql
SELECT TABLE_NAME, COLUMN_NAME
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA='vaultwarden'
  AND DATA_TYPE IN ('text', 'tinytext', 'mediumtext', 'longtext')
  AND (COLUMN_NAME='uuid' OR COLUMN_NAME='id' OR COLUMN_NAME LIKE '%\_uuid');
```

## 5. Collation

La base et les tables doivent utiliser une configuration cohérente, par exemple `utf8mb4` et `utf8mb4_unicode_ci` selon les recommandations de la version Vaultwarden utilisée.

```sql
SELECT TABLE_NAME, TABLE_COLLATION
FROM information_schema.TABLES
WHERE TABLE_SCHEMA='vaultwarden';
```

## 6. Test applicatif

Démarrez Vaultwarden sur la base convertie et vérifiez :

- absence d'erreur de migration ;
- connexion de plusieurs utilisateurs ;
- synchronisation ;
- création, modification et suppression d'un élément de test ;
- organisations et collections ;
- pièces jointes ;
- interface d'administration.

## 7. Mise en production

1. annoncer une fenêtre d'arrêt ;
2. refaire une sauvegarde finale SQLite ;
3. refaire la conversion avec les mêmes commandes validées ;
4. contrôler types, index et collations ;
5. démarrer la version testée ;
6. conserver le fichier SQLite intact pendant toute la période de validation ;
7. ne mettre en place la réplication qu'après validation complète du nœud unique.

## 8. Outil historique

Le script `scripts/experimental/update_vaultwarden_legacy.sh` contient des fonctions de correction des collations et colonnes UUID issues d'un incident réel. Il n'est pas intégré au chemin normal : relisez le SQL généré, sauvegardez la base et testez sur une copie avant toute utilisation.
