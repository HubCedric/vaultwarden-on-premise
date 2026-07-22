# Contribuer

## Avant une proposition

- ne jamais ajouter de secret ou de donnée réelle ;
- conserver les exemples génériques ;
- expliquer le risque opérationnel d'une commande destructive ;
- fournir un mode lecture seule ou dry-run lorsque possible ;
- mettre à jour la documentation liée.

## Contrôles locaux

```bash
make validate
make shellcheck
make compose-config
```

Les scripts Bash doivent passer `bash -n` et ShellCheck. Les fichiers Compose doivent rester valides après interpolation avec les `.env.example`.
