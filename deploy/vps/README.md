# Reverse proxy VPS

Le VPS doit rejoindre le même réseau WireGuard que les deux nœuds.

```bash
cp .env.example .env
nano .env
docker compose --env-file .env config
docker compose --env-file .env up -d
```

Le premier upstream est prioritaire. Après un incident ayant pu créer une divergence, maintenez le nœud concerné hors rotation jusqu'à validation de la réplication.
