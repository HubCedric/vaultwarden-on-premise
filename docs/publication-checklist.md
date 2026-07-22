# Checklist de publication GitHub

## Identité du dépôt

- [x] remplacer `OWNER/REPOSITORY` par `HubCedric/bitwarden-on-premise` dans le badge, les commandes de clonage et les exemples ;
- [x] conserver le nom **Vaultwarden On-Premise** et la description courte du README ;
- [ ] ajouter sur GitHub les topics `vaultwarden`, `self-hosted`, `docker-compose`, `mariadb`, `wireguard`, `caddy`, `backup` et `high-availability` ;
- [ ] choisir et ajouter une licence adaptée (MIT recommandée pour autoriser la réutilisation avec attribution et sans garantie).

## Secrets et données personnelles

- vérifier qu'aucun `.env`, dump SQL, certificat, clé WireGuard ou clé SSH n'est suivi par Git ;
- rechercher les valeurs `CHANGE_ME`, domaines réels, adresses IP publiques, emails personnels et noms d'utilisateurs ;
- conserver uniquement des adresses privées d'exemple et des domaines `example.net` ;
- relire l'ancien README archivé avant publication, car il contient l'historique brut du projet.

Commandes utiles :

```bash
git grep -nE 'CHANGE_ME|BEGIN (RSA|OPENSSH|PRIVATE) KEY'
git status --ignored
git ls-files | grep -E '(^|/)(\.env|data|backups|logs)(/|$)'
```

Les placeholders `CHANGE_ME` doivent rester dans les fichiers `.example`, mais jamais dans une configuration réellement déployée.

## Validation

```bash
make validate
make shellcheck
make compose-config
```

Avant de présenter le dépôt comme déployable, faire au moins un test sur une VM vierge :

1. installation d'un nœud unique ;
2. création d'un compte et synchronisation d'un client ;
3. sauvegarde puis restauration isolée ;
4. mise à jour vers une version test ;
5. seulement ensuite, mise en place du second nœud et du basculement.

## Paramètres GitHub recommandés

- activer les alertes Dependabot et l'analyse des secrets ;
- protéger la branche principale et exiger le workflow `Quality checks` ;
- désactiver les issues publiques pour les signalements contenant des secrets et utiliser les avis de sécurité privés ;
- documenter chaque changement d'architecture dans `docs/adr/`.
