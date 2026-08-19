# Scripts

[← README](../README.md) · [Supervision](../docs/04-supervision-replication-et-coherence.md) · [Incidents / PRA](../docs/05-incidents-et-pra.md)

Les scripts sont conservés séparément de la documentation afin de pouvoir les relire,
les comparer à la production et les versionner comme de vrais composants techniques.

| Fichier | Rôle | Remarque |
|---|---|---|
| `monitoring/vaultwarden-replication-monitor.sh` | réplication + pair + conteneur + alertes | dépend de `common.sh` non publié |
| `monitoring/vaultwarden-daily-consistency.sh` | comparaison quotidienne de compteurs | lecture seule |
| `monitoring/vaultwarden-weekly-reconcile.sh` | wrapper de confirmation de divergence | actif sur le slave malgré le nom historique `weekly` |
| `monitoring/vaultwarden-weekly-reconcile.master-disabled.sh` | ancienne version master | référence historique, désactivée |
| `reconciliation/reconcile_split_brain.sh` | comparaison détaillée et génération SQL | lecture seule par défaut ; `--apply` écrit réellement |
| `update/update_vaultwarden.sh` | mise à jour Vaultwarden avec sauvegarde/rollback | relire avant utilisation |

`common.sh` est requis par plusieurs scripts mais n'est pas inclus dans les éléments
sources actuellement publiables. Tant qu'il manque, le dossier monitoring doit être
considéré comme une **copie de référence**, pas comme un paquet autonome installable.

Avant utilisation :

```bash
find scripts -type f -name '*.sh' -exec bash -n {} \;
```

Si `shellcheck` est disponible :

```bash
find scripts -type f -name '*.sh' -exec shellcheck {} \;
```

Le fonctionnement détaillé, les seuils, les états persistants et la logique de
safety-stop sont documentés dans
[Supervision, réplication et cohérence](../docs/04-supervision-replication-et-coherence.md).
