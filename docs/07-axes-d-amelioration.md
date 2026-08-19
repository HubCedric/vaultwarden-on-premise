# Axes d'amélioration

[← Historique / REX](06-historique-decisions-et-rex.md) · [README](../README.md)

Cette page est **le seul endroit volontairement centré sur les défauts et la dette
technique**. Le reste du dépôt documente l'infrastructure et son exploitation. Ici,
les constats sont transformés en checklist maintenable, à traiter au fil du temps.

Les niveaux de priorité ne signifient pas qu'un point est forcément exploitable ou
qu'un incident est en cours : ils indiquent l'ordre logique dans lequel il est utile
de travailler.

## 🔴 Priorité 0 — protection des données et continuité

- [ ] **Mettre en place une vraie stratégie de sauvegarde versionnée.**
  - dump MariaDB régulier ;
  - sauvegarde de `/vw-data`, notamment `sends/` et `attachments/` ;
  - sauvegarde des configs nécessaires à la reconstruction ;
  - copie stockée hors des deux backends ;
  - rétention définie ;
  - restauration réellement testée.
  - Voir : [Incidents et PRA](05-incidents-et-pra.md).

- [ ] **Traiter la non-réplication des fichiers Vaultwarden.**
  - un Send a déjà démontré que les métadonnées SQL peuvent exister sur les deux
    nœuds alors que le fichier n'existe que sur celui qui a reçu l'upload ;
  - éviter un rsync bidirectionnel naïf qui pourrait propager suppressions ou conflits ;
  - choisir entre stockage partagé/objet, réplication conçue avec sémantique de
    suppression, ou limitation explicitement assumée + détection.

- [ ] **Protéger électriquement `bitwarden-slave`.**
  - installer un UPS 230 V pour le Raspberry Pi + SSD ;
  - préférer un modèle avec USB HID compatible NUT ;
  - configurer les alertes secteur/batterie et l'arrêt propre sur batterie faible ;
  - étudier l'activation du watchdog matériel ;
  - prévoir un moyen de power-cycle distant ;
  - tester microcoupure puis coupure longue.

- [ ] **Supprimer les secrets des fichiers world-readable.**
  - ne plus stocker `DATABASE_URL` et `ADMIN_TOKEN` en clair dans un compose `0644` ;
  - utiliser un fichier local non versionné avec permissions strictes ;
  - conserver dans Git uniquement `.env.example` et les noms de variables.

- [ ] **Empêcher la journalisation des tokens Vaultwarden dans Caddy.**
  - les erreurs de reverse proxy peuvent inclure l'URI complète de
    `/notifications/hub?access_token=...` ;
  - mettre en place une stratégie de redaction compatible avec la version cible de Caddy ;
  - ne jamais collecter/coller des logs HTTP bruts sans filtrage.

## 🔴 Priorité 1 — disponibilité et cohérence

- [ ] **Mettre Caddy sur une version et une source de paquets maintenues.**
  - vérifier la version stable au moment de l'intervention ;
  - migrer depuis la source actuelle si nécessaire ;
  - valider le Caddyfile avant reload ;
  - remplacer les directives dépréciées (`health_path`, `path`) lors de la migration.

- [ ] **Définir un health check plus représentatif de l'état réellement servi.**
  - Caddy ne vérifie actuellement que l'HTTP `/` ;
  - documenter l'interaction entre health check Caddy et safety-stop du slave ;
  - éviter qu'un backend HTTP « vivant » mais incohérent soit préféré sans signalement.

- [ ] **Ajouter une vérification de cohérence des fichiers.**
  - vérifier que chaque Send/attachment référencé en DB existe réellement ;
  - signaler les écarts sans supprimer automatiquement de fichiers.

- [ ] **Tester périodiquement le failover.**
  - master indisponible → slave ;
  - slave indisponible → master ;
  - reboot contrôlé VPS → WireGuard + Caddy + upstreams ;
  - restauration de la réplication après retour d'un pair.

## 🟠 Priorité 2 — durcissement

- [ ] **Ajouter un firewall hôte sur `bitwarden-slave`.**
  - le périmètre Orange filtre actuellement les accès observés, mais le système lui-même
    accepte les entrées ;
  - reproduire une politique restrictive comparable au master sans casser WireGuard,
    SSH et MariaDB inter-site.

- [ ] **Durcir l'hôte VPS en complément du firewall Infomaniak.**
  - conserver l'accès nécessaire aux autres sites hébergés ;
  - ajouter un filtrage hôte uniquement après inventaire complet des flux.

- [ ] **Réduire les privilèges et la portée des comptes MariaDB.**
  - remplacer les grants `%` lorsqu'ils ne sont pas nécessaires ;
  - vérifier si `monitor@127.0.0.1` a réellement besoin de `SUPER` ;
  - séparer et faire tourner les secrets actuellement réutilisés entre certains comptes.

- [ ] **Normaliser les permissions.**
  - `docker-compose.yml` non secret ou permissions plus strictes si secret ;
  - `rsa_key.pem` sans bits d'exécution et avec droits minimaux ;
  - `wg0.conf` à `0600` ;
  - cohérence des propriétaires entre master et slave.

- [ ] **Durcir le service systemd Caddy avec un drop-in testé.**
  - conserver l'utilisateur non-root et `ProtectSystem=full` ;
  - étudier `NoNewPrivileges`, bounding capabilities et protections kernel/cgroup ;
  - ne pas copier aveuglément un profil générique, car le VPS sert aussi d'autres sites.

## 🟡 Priorité 3 — fiabilité du monitoring et maintenabilité

- [ ] **Corriger la gestion d'état des mails d'incident.**
  - l'état d'incident est écrit avant la confirmation d'envoi SMTP ;
  - un échec mail peut donc empêcher la relance du premier message.

- [ ] **Corriger la récupération du code retour dans le wrapper reconcile.**
  - `if ! result="$(...)"; then rc=$?` masque le code d'origine ;
  - le bug touche surtout le diagnostic, pas la logique de safety-stop.

- [ ] **Ajouter `TIMEZONE` et `REMINDER_HOUR` aux variables obligatoires du monitor.**

- [ ] **Renommer `weekly-reconcile` ou documenter définitivement le nom historique.**
  - le timer du slave est quotidien malgré le nom `weekly`.

- [ ] **Décider du devenir de `vaultwarden_stopped_by_monitor`.**
  - le marqueur est écrit mais n'est pas utilisé pour piloter une reprise automatique.

- [ ] **Ajouter un vrai healthcheck Docker** si les branches `healthy/unhealthy` du
  monitor doivent avoir un sens opérationnel.

- [ ] **Nettoyer les reliquats après sauvegarde.**
  - anciens `db.sqlite3*` ;
  - scripts `.backup` ;
  - ancien reconcile du master ;
  - `Caddyfile.save` ;
  - règles/anciens ports SSH devenus inutiles ;
  - fichiers de dumps ponctuels à conserver ou archiver selon une politique claire.

- [ ] **Vérifier l'utilité de `vaultwarden_test`** et supprimer la base seulement si
  aucune procédure ou script ne l'utilise.

- [ ] **Décider si le VPS a besoin de swap.** Ce n'est pas un incident aujourd'hui,
  mais la décision mérite d'être explicite pour une petite VM.

## ✅ Corrections déjà réalisées

- [x] Autorisation UDP/51820 sur UFW du master après identification du blocage WireGuard.
- [x] Autorisation UDP/51820 ajoutée au firewall fournisseur du VPS.
- [x] Vérification du retour des handshakes WireGuard et disparition des blocages UFW associés.
- [x] Confirmation que les 503 du 5 août correspondaient réellement à l'absence simultanée des deux backends.
- [x] Validation du fonctionnement des rappels et notifications du monitoring pendant un incident prolongé.

## Méthode de traitement

Pour chaque case :

1. préparer la correction dans une branche ou un dépôt privé ;
2. sauvegarder la configuration actuelle ;
3. appliquer sur le nœud concerné ;
4. exécuter les validations de [l'exploitation](03-exploitation-et-maintenance.md) ;
5. tester le scénario de panne concerné si possible ;
6. mettre à jour la documentation et la configuration versionnée ;
7. cocher la tâche seulement lorsque la production et le dépôt correspondent.

## Navigation

[← Historique, décisions et REX](06-historique-decisions-et-rex.md) · [Retour au README](../README.md)
