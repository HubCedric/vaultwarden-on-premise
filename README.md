# bitwarden-on-premise
Bitwarden on Premise - Raspberry Pi

je me suis lancé dans la mise en place d'un gestionnaire de mot de passe on premise, sur un serveur chez moi à la maison.

état des lieux : actuellement sous bitwarden en mode saas, l'idée est de migrer mes mots de passe sur un serveur en local afin qu'ils ne se trouvent pas sur des serveurs dont je n'ai pas la main.

idée du projet : utiliser IPv6 pour accéder au serveur depuis l'extérieur, sans avoir besoin d'ouvrir des ports sur le routeur ce qui pose souvent des problèmes de sécurité. 

matériel nécessaire : 
* raspberry pi (actuellement migré sur une VM sur ma Freebox, mais les étapes d'installation sont les mêmes)
* alimentation
* cable ethernet (inutile si vous faites tourner sur une VM sur la Freebox)
* carte SD
* un opérateur proposant IPv6 (en l'occurence, Free)

j'ai suivi un tuto assez bien fait pour installer bitwarden sur un raspberry, car nativement, l'architecture du processeur du raspberry (arm) n'est pas compatible avec bitwarden (de même avec la freebox, cette dernière créée des VMs sur une architecture arm, qui globalement fonctionne bien mais qui rend impossible l'installation de bitwarden officiel). l'idée est donc de faire tourner un conteneur docker qui s'appelle vaultwarden et qui fonctionne tout autant que bitwarden officiel. le voici : https://raspberrytips.fr/installer-bitwarden-sur-raspberry-pi/

en gros, voici les étapes d'installation : 
* installer docker
* installer le conteneur docker et le lancer
* utiliser un DNS pour translater l'IPv6 en une URL
* mettre en place un certificat SSL (obligatoire pour créer un compte sur votre interface web, mais au delà de ça, indispensable pour stocker des mots de passe...)

je vais pas redétailler toutes les étapes, le tuto en ligne est assez bien fait pour le coup. pour le DNS, j'ai utilisé https://dynv6.com/, qui après quelques recherches est à ma connaissance le seul qui supporte IPv6.
ça marche plutôt bien, et c'est gratuit.

j'ai quand même eu quelques soucis lors de l'installation, mais rien de méchant. lors de l'installation du certificat SSL Letsencrypt, il arrive parfois que tous les certificats soient pris et qu'il faille attendre pour le générer. la date et l'heure où vous pouvez réessayer sont inscrits dans les logs quand ça vous met l'erreur.

de plus, certains réseaux d'entreprises ayant des exigences de sécurité un peu élevées peuvent bloquer l'accès au serveur à cause du certificat Letsencrypt. du coup je vous invite à utiliser un autre certificat si vous le pouvez, mais letsencrypt fonctionne très bien sur des réseaux domestiques. si vous avez que cet usage là, pour le coup letsencrypt fera tout votre usage.

pour la sauvegarde de la BDD, il faut encore que je me penche sur le sujet. le mieux serait soit d'avoir un sauvegarde de la BDD sur un support externe, un serveur à part, ou encore avoir un 2e serveur bitwarden délocalisé afin d'avoir une redondance. 
_En cours de réflexion_

# renouvellement du certificat

voir : https://chatgpt.com/share/1a3f13d0-f890-4f5f-be06-d54b5febbcbd _A rerédiger lorsque ça sera de nouveau le moment du renouvellement_

# upgrade nouvelle version vaultwarden

il arrive que des nouvelles versions de vaultwarden soient publiées (heureusement), voici la procédure pour les installer.

commencer par stopper le conteneur vaultwarden déjà en cours d'exécution :

```
sudo docker stop vaultwarden
```

_remplacer `vaultwarden` par le nom du conteneur docker en question qui est visible en tapant la commande `sudo docker ps`_

installer ensuite la dernière version du conteneur docker :

```
sudo docker pull vaultwarden/server:latest
```

une fois fini, vous pouvez relancer le conteneur docker avec la commande suivante : 

```
sudo docker run -d -e ROCKET_TLS='{certs="/ssl/certs.pem",key="/ssl/key.pem"}' -v /ssl/keys/:/ssl/ -v /vw-data/:/data/ -p 443:80 vaultwarden/server:latest
```

et voilà, vaultwarden est à jour !

# upgrade openssh

une vulnérabilité d'openssh est sortie début juillet 2024, voici la procédure pour le mettre à jour (un apt-get install openssh-server ne suffit pas car les repo de base ne sont pas encore à jour visiblement)

la vulnérabilté en question : https://www.cert.ssi.gouv.fr/alerte/CERTFR-2024-ALE-009/

tout d'abord on fait une vérification de la version d'openssh : 
```
ssh -V
```
```
julabuche@server:~ $ ssh -V
OpenSSH_9.2p1 Debian-2+deb12u2, OpenSSL 3.0.11 19 Sep 2023
```

ensuite on fait une sauvegarde de la config actuelle d'openssh : 
```
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
```

ensuite, màj et install des paquets nécessaires pour la suite :
```
sudo apt-get update
sudo apt-get install -y build-essential zlib1g-dev libssl-dev libpam0g-dev wget
```

on download le zip de openssh de la bonne version, on le unpack et on rentre dans le dossier
```
wget https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-9.8p1.tar.gz
tar -xzf openssh-9.8p1.tar.gz
cd openssh-9.8p1
```

ces 2 commandes sont plutôt longues à l'exécution, c'est un script pour installer openssh dans la bonne version je supposes...

```
./configure
make
```

on installe ensuite openssh et on redémarre le service : 
```
sudo make install
sudo systemctl restart sshd
```

on vérifie ensuite la version d'openssh avec la commande
```
ssh -V
```
```
julabuche@server:~/openssh-9.8p1 $ ssh -V
OpenSSH_9.8p1, OpenSSL 3.0.13 30 Jan 2024
```

voilà, openssh est à jour et la vulnérabilité est patchée !


