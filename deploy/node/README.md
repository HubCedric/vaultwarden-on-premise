# Déploiement d'un nœud

1. Copier `.env.example` vers `.env`.
2. Copier le fichier MariaDB A ou B vers `config/mariadb/50-server.cnf`.
3. Créer `data/mariadb` et `data/vaultwarden`.
4. Vérifier que `WIREGUARD_IP` existe sur l'hôte.
5. Exécuter `docker compose --env-file .env config`.
6. Démarrer avec `docker compose --env-file .env up -d`.

Le port 8080 est destiné au VPS via WireGuard. Le port 3306 est destiné au pair MariaDB via WireGuard.
