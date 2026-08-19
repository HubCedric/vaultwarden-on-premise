# Sécurité du dépôt

Ce dépôt public ne doit jamais contenir de mot de passe, token d’administration, clé WireGuard, clé TLS privée, URL de base avec identifiants, secret SMTP, adresse IP publique réelle ou nom de domaine réel.

Ne pas ouvrir d’Issue publique pour une vulnérabilité qui révèle un secret ou une information d’infrastructure. Utiliser un canal privé avec le mainteneur du dépôt. En cas de fuite, révoquer d’abord le secret concerné, retirer la valeur de la configuration active, puis nettoyer l’historique Git si nécessaire.

Avant chaque publication :

- rechercher les domaines, adresses, e-mails, tokens et clés connus ;
- contrôler les fichiers ignorés par Git ;
- vérifier les sorties de logs et captures ;
- confirmer que les exemples utilisent uniquement `vaultwarden.example.com`, les IP WireGuard autorisées et des placeholders explicites.

Les limites et travaux de durcissement sont centralisés dans [les axes d’amélioration](docs/07-axes-d-amelioration.md).

