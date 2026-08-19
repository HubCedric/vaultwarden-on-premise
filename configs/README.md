# Configurations

[← README](../README.md) · [Architecture](../docs/01-architecture-et-conception.md) · [Mise en œuvre](../docs/02-mise-en-oeuvre-et-reconstruction.md)

Ce dossier regroupe les configurations publiables associées à l'infrastructure. Elles
conservent les noms internes et l'adressage WireGuard, mais jamais les secrets, le
domaine réel ou les IP publiques.

| Dossier | Contenu |
|---|---|
| `caddy/` | bloc Vaultwarden du Caddyfile, domaine anonymisé |
| `docker/` | compose Vaultwarden avec secrets externalisés |
| `mariadb/` | paramètres propres au master et au slave |
| `wireguard/` | topologie complète reconstruite, clés/endpoints publics remplacés |
| `systemd/` | services et timers utilisés par le monitoring |
| `monitoring/` | exemples d’environnement master/slave sans secrets |

Le `config.json` de Vaultwarden est **actif en production**, mais sa copie complète
n'est pas incluse ici car elle contient des champs sensibles et son contenu nettoyé
complet n'a pas été fourni dans les sources du dépôt. Le comportement des réglages
applicatifs est documenté dans la page d'architecture.

Avant déploiement, comparer les fichiers publiés avec la machine cible et injecter les
secrets depuis un emplacement local non versionné.
