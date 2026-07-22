# Sécurité

## 1. Modèle de menace

Les risques principaux sont :

- compromission du VPS ;
- accès non autorisé à SSH ;
- exposition de MariaDB ;
- fuite des fichiers `.env` ou WireGuard ;
- image Docker compromise ou non maîtrisée ;
- sauvegardes non chiffrées ;
- erreur d'exploitation répliquée sur les deux nœuds ;
- interface `/admin` accessible publiquement.

## 2. Réseau

### VPS

Autoriser publiquement uniquement :

- TCP 80 pour ACME/redirection ;
- TCP 443 pour HTTPS ;
- UDP WireGuard ;
- SSH depuis des adresses ou un VPN d'administration si possible.

### Nœuds

- Vaultwarden `8080` : source VPS WireGuard uniquement ;
- MariaDB `3306` : pair WireGuard uniquement ;
- WireGuard UDP : pairs attendus ;
- SSH : réseau d'administration uniquement.

Exemple UFW à adapter sur un nœud :

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 10.0.0.10 to any port 8080 proto tcp
sudo ufw allow from 10.0.0.2 to any port 3306 proto tcp
sudo ufw allow 51820/udp
sudo ufw enable
```

## 3. TLS

Caddy gère TLS public. Le trafic interne est en HTTP dans WireGuard ; il reste chiffré par le tunnel. Cette approche est préférable à un certificat non vérifié avec `tls_insecure_skip_verify`.

Activez HSTS seulement lorsque le domaine HTTPS fonctionne durablement.

## 4. Vaultwarden

- `DOMAIN` doit correspondre exactement à l'URL publique ;
- `SIGNUPS_ALLOWED=false` après initialisation ;
- token admin Argon2 robuste ;
- `/admin` filtré par IP ou VPN si possible ;
- versions explicites ;
- logs sans niveau excessivement verbeux ;
- 2FA activée sur tous les comptes ;
- politique de mot de passe maître forte et unique.

## 5. Docker

- utiliser les images officielles Vaultwarden et MariaDB ;
- pinner au minimum une version, idéalement un digest après validation ;
- ne pas monter le socket Docker dans les conteneurs ;
- ne pas exécuter de conteneur privilégié ;
- limiter les ports publiés ;
- appliquer les mises à jour du moteur Docker et du système.

## 6. MariaDB

- mots de passe uniques ;
- comptes limités par hôte ;
- pas de root distant ;
- port lié à WireGuard ;
- privilèges de supervision séparés ;
- aucun script automatique ne doit ignorer une erreur SQL métier ;
- backups chiffrés et testés.

## 7. SSH

Changer le port réduit le bruit mais ne remplace pas les contrôles réels :

- clés SSH uniquement ;
- `PasswordAuthentication no` après validation ;
- `PermitRootLogin no` ;
- filtrage réseau ;
- fail2ban facultatif ;
- maintien du paquet OpenSSH via les dépôts de sécurité de la distribution.

Évitez de compiler manuellement OpenSSH sauf nécessité documentée : cela complique les mises à jour et le suivi des paquets.

Avant redémarrage :

```bash
sudo sshd -t
```

Gardez une session ouverte pendant le test d'une nouvelle connexion.

## 8. Secrets

```bash
chmod 600 deploy/node/.env deploy/vps/.env scripts/.env
sudo chmod 600 /etc/wireguard/wg0.conf
```

Ne copiez jamais un `.env` dans une issue GitHub, un log public ou une capture d'écran.

## 9. Sauvegardes

- chiffrement côté client avant envoi hors site ;
- clé de déchiffrement séparée ;
- accès en lecture seule pour la cible quand possible ;
- politique d'immuabilité ou de snapshots ;
- test de restauration périodique.

## 10. Réponse à une fuite de secret

1. retirer le secret du dépôt et de l'historique si nécessaire ;
2. considérer le secret comme compromis même si le commit a été supprimé ;
3. tourner le mot de passe ou la clé ;
4. redéployer ;
5. analyser les journaux ;
6. documenter l'incident.
