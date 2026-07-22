# Scripts expérimentaux

Ces scripts proviennent du retour d'expérience du dépôt d'origine et manipulent des scénarios très spécifiques.

- `reconcile_split_brain.sh` compare deux bases divergentes et peut, avec `--apply`, écrire sur la production après confirmation.
- `update_vaultwarden_legacy.sh` contient des corrections automatiques de collation et de colonnes UUID issues d'une ancienne migration SQLite vers MySQL/MariaDB.

Avant utilisation :

1. sauvegarder séparément les deux bases et `/data` ;
2. lire le script complet ;
3. tester sur des copies isolées ;
4. générer les changements sans application ;
5. relire chaque instruction SQL ;
6. documenter le résultat.
