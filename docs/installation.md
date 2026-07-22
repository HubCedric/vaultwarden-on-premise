# Installation

## 1. Préparation

Cette procédure couvre un nœud Linux Debian/Ubuntu récent. Elle s'applique à une VM Freebox, un Raspberry Pi 64 bits ou un serveur classique.

### Ressources minimales indicatives

- 1 à 2 vCPU ;
- 1 Go de RAM recommandé ;
- 20 Go de stockage minimum ;
- stockage SSD recommandé ;
- adresse IP stable sur le LAN ;
- IPv4 ou IPv6 permettant d'établir WireGuard.

### Paquets hôte

```bash
sudo apt update
sudo apt install -y ca-certificates curl git wireguard mariadb-client gzip tar jq
```

Installez Docker Engine et le plugin Compose depuis la documentation officielle Docker de votre distribution. Vérifiez ensuite :

```bash
docker version
docker compose version
```

## 2. Cloner le dépôt

```bash
sudo mkdir -p /opt/vaultwarden-on-premise
sudo chown "$USER":"$USER" /opt/vaultwarden-on-premise
git clone https://github.com/HubCedric/bitwarden-on-premise.git /opt/vaultwarden-on-premise
cd /opt/vaultwarden-on-premise
```

## 3. Configurer WireGuard

Copiez l'exemple adapté :

```bash
sudo cp config/wireguard/node-a.conf.example /etc/wireguard/wg0.conf
sudo chmod 600 /etc/wireguard/wg0.conf
sudo nano /etc/wireguard/wg0.conf
sudo systemctl enable --now wg-quick@wg0
```

Contrôles :

```bash
sudo wg show
ip address show wg0
ping -c 3 10.0.0.10
```

## 4. Préparer le déploiement du nœud

```bash
cd /opt/vaultwarden-on-premise/deploy/node
cp .env.example .env
cp config/mariadb/50-server-node-a.cnf.example config/mariadb/50-server.cnf
chmod 600 .env
nano .env
```

À modifier au minimum :

- `COMPOSE_PROJECT_NAME` ;
- `WIREGUARD_IP` ;
- `VAULTWARDEN_VERSION` ;
- `DOMAIN` ;
- les mots de passe MariaDB ;
- `DATABASE_URL` ;
- `ADMIN_TOKEN` ;
- `SIGNUPS_ALLOWED`.

Créez les répertoires persistants :

```bash
mkdir -p data/mariadb data/vaultwarden
chmod 700 data
```

## 5. Valider la configuration

```bash
../../scripts/preflight.sh
docker compose --env-file .env config --quiet
docker compose --env-file .env pull
```

La commande `config` ne doit afficher aucune erreur ni valeur vide inattendue.

## 6. Démarrer le nœud

```bash
docker compose --env-file .env up -d
docker compose --env-file .env ps
```

Suivre le premier démarrage :

```bash
docker compose --env-file .env logs -f mariadb vaultwarden
```

Contrôle applicatif privé :

```bash
curl --fail "http://${WIREGUARD_IP:-10.0.0.1}:8080/alive"
```

## 7. Initialiser le compte

Lors du premier démarrage uniquement :

1. autorisez temporairement les inscriptions avec `SIGNUPS_ALLOWED=true` ;
2. créez votre compte ;
3. remettez `SIGNUPS_ALLOWED=false` ;
4. redéployez avec `docker compose up -d` ;
5. vérifiez que l'inscription publique est fermée.

L'interface d'administration `/admin` doit être protégée par un `ADMIN_TOKEN` Argon2 robuste et idéalement restreinte par le reverse proxy ou le pare-feu.

## 8. Installer le VPS Caddy

Sur le VPS :

```bash
sudo mkdir -p /opt/vaultwarden-proxy
sudo cp -a deploy/vps/. /opt/vaultwarden-proxy/
cd /opt/vaultwarden-proxy
cp .env.example .env
nano .env
```

Démarrer :

```bash
docker compose --env-file .env config --quiet
docker compose --env-file .env up -d
docker compose --env-file .env logs -f caddy
```

Le DNS public doit pointer vers le VPS. Les nœuds privés n'ont pas besoin d'enregistrement public.

## 9. Préparer les scripts

```bash
cd /opt/vaultwarden-on-premise/scripts
cp .env.example .env
chmod 600 .env
nano .env
```

Testez d'abord :

```bash
./healthcheck.sh
./backup_vaultwarden.sh
./check_replication.sh
```

La réplication n'est pas active tant que la procédure de [haute disponibilité](high-availability.md) n'est pas terminée.

## 10. Installer les timers systemd

Adaptez les chemins dans les unités si le dépôt n'est pas sous `/opt/vaultwarden-on-premise` :

```bash
sudo cp systemd/*.service systemd/*.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now vaultwarden-backup.timer
sudo systemctl enable --now vaultwarden-replication-check.timer
systemctl list-timers 'vaultwarden-*'
```

## 11. Validation finale

- le coffre Web s'ouvre en HTTPS ;
- un client mobile ou navigateur se synchronise ;
- les inscriptions sont fermées ;
- Caddy atteint uniquement l'adresse WireGuard ;
- MariaDB n'est pas exposée sur Internet ;
- une sauvegarde complète est créée ;
- la restauration est planifiée pour être testée.
