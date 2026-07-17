# Haute disponibilité

L'objectif de cette partie est de mettre en place une architecture permettant de limiter les interruptions de service.

L'infrastructure repose sur plusieurs éléments :

- Deux serveurs Vaultwarden indépendants ;
- Une base MariaDB propre à chaque serveur ;
- Une réplication MariaDB entre les deux bases ;
- Un tunnel VPN WireGuard permettant la communication sécurisée entre les différents composants ;
- Un VPS servant de point d'entrée public avec un reverse proxy Caddy.

Cette architecture permet de continuer à accéder au service en cas d'indisponibilité temporaire d'un des deux serveurs Vaultwarden.

---

# Mise en place du tunnel VPN WireGuard

Afin de ne pas exposer directement les serveurs Vaultwarden sur Internet, un réseau privé est créé entre les différentes machines grâce à WireGuard.

Le tunnel VPN est composé de trois équipements :

| Machine | Adresse VPN | Rôle |
| --- | --- | --- |
| Serveur Vaultwarden principal | 10.0.0.1 | Serveur principal |
| Serveur Vaultwarden secondaire | 10.0.0.2 | Serveur secondaire |
| VPS Caddy | 10.0.0.10 | Point d'entrée public |

---

## Installation de WireGuard

WireGuard doit être installé sur les trois machines.

Connexion en SSH puis installation :

```bash
sudo apt update
sudo apt install wireguard
```

On se place ensuite dans le dossier de configuration :

```bash
cd /etc/wireguard/
```

Passage en utilisateur root :

```bash
sudo -s
```

---

# Génération des clés WireGuard

Chaque machine possède une paire de clés :

- une clé privée ;
- une clé publique.

Les clés privées doivent rester secrètes et ne doivent jamais être partagées.

## Serveur Vaultwarden principal

Génération des clés :

```bash
wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey
```

Les fichiers obtenus sont :

```text
/etc/wireguard/privatekey
/etc/wireguard/publickey
```

Afficher les clés :

```bash
cat /etc/wireguard/privatekey
cat /etc/wireguard/publickey
```

---

## Serveur Vaultwarden secondaire

Même opération :

```bash
wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey
```

---

## VPS

Même opération :

```bash
wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey
```

---

# Configuration WireGuard

La configuration de WireGuard se trouve dans :

```bash
/etc/wireguard/wg0.conf
```

Création ou modification du fichier :

```bash
nano /etc/wireguard/wg0.conf
```

---

# Configuration du serveur Vaultwarden principal

Fichier :

```bash
/etc/wireguard/wg0.conf
```

Configuration :

```ini
[Interface]
Address = 10.0.0.1/32
ListenPort = 51820
PrivateKey = CLE_PRIVEE_SERVEUR_PRINCIPAL


[Peer]
# Serveur secondaire
PublicKey = CLE_PUBLIQUE_SERVEUR_SECONDAIRE
AllowedIPs = 10.0.0.2/32
Endpoint = [IPV6_SERVEUR_SECONDAIRE]:51820


[Peer]
# VPS
PublicKey = CLE_PUBLIQUE_VPS
AllowedIPs = 10.0.0.10/32
Endpoint = [IPV6_VPS]:51820
```

---

# Configuration du serveur Vaultwarden secondaire

Fichier :

```bash
/etc/wireguard/wg0.conf
```

Configuration :

```ini
[Interface]
Address = 10.0.0.2/32
ListenPort = 51820
PrivateKey = CLE_PRIVEE_SERVEUR_SECONDAIRE


[Peer]
# Serveur principal
PublicKey = CLE_PUBLIQUE_SERVEUR_PRINCIPAL
Endpoint = [IPV6_SERVEUR_PRINCIPAL]:51820
AllowedIPs = 10.0.0.1/32
PersistentKeepalive = 25


[Peer]
# VPS
PublicKey = CLE_PUBLIQUE_VPS
Endpoint = [IPV6_VPS]:51820
AllowedIPs = 10.0.0.10/32
PersistentKeepalive = 25
```

---

# Configuration du VPS

Fichier :

```bash
/etc/wireguard/wg0.conf
```

Configuration :

```ini
[Interface]
Address = 10.0.0.10/32
ListenPort = 51820
PrivateKey = CLE_PRIVEE_VPS


[Peer]
# Serveur principal
PublicKey = CLE_PUBLIQUE_SERVEUR_PRINCIPAL
Endpoint = [IPV6_SERVEUR_PRINCIPAL]:51820
AllowedIPs = 10.0.0.1/32
PersistentKeepalive = 25


[Peer]
# Serveur secondaire
PublicKey = CLE_PUBLIQUE_SERVEUR_SECONDAIRE
Endpoint = [IPV6_SERVEUR_SECONDAIRE]:51820
AllowedIPs = 10.0.0.2/32
PersistentKeepalive = 25
```

---

# Démarrage du service WireGuard

Activation automatique au démarrage :

```bash
sudo systemctl enable wg-quick@wg0
```

Démarrage du tunnel :

```bash
sudo systemctl start wg-quick@wg0
```

Vérification :

```bash
sudo systemctl status wg-quick@wg0
```

---

# Vérification du tunnel VPN

Vérifier la présence de l'interface réseau :

```bash
ip a
```

Une interface similaire doit apparaître :

```text
wg0: <POINTOPOINT,NOARP,UP,LOWER_UP>
    inet 10.0.0.x/32
```

Tester la communication entre les machines :

Depuis le serveur principal :

```bash
ping 10.0.0.2
ping 10.0.0.10
```

Depuis le serveur secondaire :

```bash
ping 10.0.0.1
ping 10.0.0.10
```

Depuis le VPS :

```bash
ping 10.0.0.1
ping 10.0.0.2
```

---

# Problème rencontré

Sur certaines installations, WireGuard peut nécessiter le paquet supplémentaire :

```bash
sudo apt install resolvconf
```

Sans ce paquet, certains paramètres réseau peuvent ne pas être appliqués correctement.

---

# Vérification de l'état WireGuard

La commande suivante permet de voir l'état du tunnel :

```bash
sudo wg show
```

Exemple :

```text
interface: wg0
  public key: XXXXX
  listening port: 51820

peer:
  endpoint: XXXXX
  latest handshake: 30 seconds ago
  transfer: XXXXX received, XXXXX sent
```

La présence d'un **latest handshake récent** confirme que la communication fonctionne.

---

# Réplication MariaDB

Chaque serveur Vaultwarden possède sa propre base MariaDB.

La haute disponibilité n'est donc pas basée sur une base unique partagée, mais sur une réplication entre les deux instances MariaDB.

Architecture :

```text
Vaultwarden A
      |
      |
 MariaDB A
      |
      |
 Réplication MariaDB
      |
      |
 MariaDB B
      |
      |
Vaultwarden B
```

Les deux bases doivent rester synchronisées afin de permettre une reprise sur l'autre serveur en cas de panne.

La configuration détaillée de MariaDB est disponible dans :

[Installation](./installation.md)

---

# Limites de cette architecture

Même si cette architecture améliore la disponibilité, elle ne remplace pas une vraie solution de sauvegarde.

Les points importants :

- Une suppression accidentelle est également répliquée ;
- Une corruption de données peut être propagée ;
- Les sauvegardes externes restent indispensables ;
- Les tests de restauration doivent être effectués régulièrement.

La haute disponibilité protège principalement contre une panne matérielle ou une indisponibilité d'un serveur.
