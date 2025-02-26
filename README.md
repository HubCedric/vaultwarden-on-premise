# bitwarden-on-premise
Bitwarden on Premise - Raspberry Pi

je me suis lancé dans la mise en place d'un gestionnaire de mot de passe on premise, sur un serveur chez moi à la maison.

état des lieux : actuellement sous bitwarden en mode saas, l'idée est de migrer mes mots de passe sur un serveur en local afin qu'ils ne se trouvent pas sur des serveurs dont je n'ai pas la main.

## Mise en place
idée du projet : installation de la solution Vaultwarden (obligatoire pour les architectures ARM tels que Raspberry Pi ou Freebox OS), et utilisation de la solution IPv6 pour accéder au serveur depuis l'extérieur, sans avoir besoin d'ouvrir des ports sur le routeur ce qui pose souvent des problèmes de sécurité. 

### Installation sur Raspberry Pi

matériel nécessaire pour installation sur raspberry pi : 
* raspberry pi 
* alimentation
* câble ethernet
* carte SD ou SSD + Shield SSD pour Raspberry Pi
* un opérateur proposant IPv6 (en l'occurence, Free)

#### Installation de l'OS

Tout d'abord, il faudra installer l'OS Raspberry Pi sur votre carte SD ou le SSD. Personnellement je suis parti sur le SSD pour une solution plus pérenne (après une mésaventure avec une carte SD bas de gamme qui m'a laché !). 

Pour installer l'OS, vous aurez besoin du logiciel Raspberry Pi Imager, dispo sous Mac, Windows et Linux. On choisit le modèle de Raspberry, l'OS (préferer Raspberry Pi OS Lite (64-bit)), puis le périphérique de stockage (qu'il faut bien sur brancher préalablement au PC). Ensuite on édite les options d'installation pour setup un nom d'utilisateur et un mot de passe, et très important : on active le service SSH !

Concernant le WiFi, c'est à votre aise. Personnellement je préfère partir sur une connexion filaire pour plus de stabilité, mais le WiFi peut fonctionner correctement si le Raspberry est proche de votre routeur (ce qui n'est pas mon cas).

Ensuite on lance l'installation. L'installation sur mon SSD avec le shield m'a pris littéralement 20 secondes avec la vérification. C'est magique la technologie ! 

Par la suite, on peut brancher notre shield au Raspberry (ou tout simplement insérer la carte SD si on a opté pour cette solution), puis brancher le Raspberry au secteur et en y reliant un cordon Ethernet.

Ensuite, pour connaitre l'adresse IP que le Raspberry a pris, je me rend sur l'interface web de mon routeur et je regarde si je vois apparaitre le raspberry dans les appareils connectés, et d'ici on peut voir l'adresse IP du raspberry !

### Installation sur Freebox OS

matériel nécessaire pour installation sur Freebox : 
* SSD NVME compatible avec Freebox (en l'occurence je suis parti sur un Crucial P3 de 2To)
* une Freebox Delta ou Freebox Ultra (l'abonnement Ultra Essentiel fonctionne aussi)
* un opérateur proposant IPv6 (en l'occurence, Free)

#### Installation de l'OS

Avant de vouloir configurer une VM, il faut tout d'abord installer un disque dur dans votre Freebox. Rien de bien compliqué, sur la Freebox Ultra, le slot SSD se trouve en dessous. Je vous conseille d'éteindre votre box avant d'y insérer le SSD, puis la rallumer après. Il me semble qu'il faut simplement formater le disque avant de pouvoir l'utiliser, prenez donc soin de bien sauvegarder toutes les données présents dessus si c'est un SSD réutilisé.

Pour installer une VM sur Freebox OS, c'est pas bien compliqué. Il faut vous rendre sur l'interface web de votre Freebox dans l'onglet "VMs". Cliquer sur "Ajouter une VM", vous lui donnez un petit nom, et on alloue 1 CPU seulement (suffisant et ça nous laisse de la marge pour créer une autre VM si besoin), et 512Mo de RAM. Oui, nous sommes bien en 2025 et pas en 2005, mais c'est largement suffisant ! De ce que je vois actuellement sur mon serveur, il utilise uniquement 26Mo de RAM. En tout cas, j'ai jamais eu de soucis de stabilité !

On coche ensuite la case "Choisir un système d'exploitation pré-installé parmi une liste", ensuite on choisit le système d'exploitation qu'on souhaite. Perso, je suis friand d'Ubuntu, mais n'importe quel OS fonctionnera tant qu'on est sur une base Unix.

Renseigner un nom d'utilisateur et un mot de passe. Pas besoin de cocher la case pour accéder aux disques de la Freebox, ça ne sera pas utile.

Pour ce qui est de la taille du disque, 15Go suffisent. Avec 2 utilisateurs et ~600 mots de passes enregistrés en tout, je ne remplit même pas 30% du stockage. Le répertoire de la BDD ne pèse que 6.3M dans mon cas, donc avec 15Go de stockage on est large !

Une fois fait, on peut finaliser la configuration et notre VM est prête, on peut donc la démarrer. Ici, pour récupérer l'adresse IP, rien de plus simple, elle est directement indiquée sur la page d'accueil de la VM ;)

#### Préparation de l'OS

On va faire la première configuration du serveur. On va commencer par s'y connecter en SSH :

```
ssh username@ipaddress
```

pour ensuite lancer les mises à jour :

```
julabuche@server:~$ sudo apt update
julabuche@server:~$ sudo apt-get upgrade -y
```

et un petit redémarrage pour la forme ;)

```
julabuche@server:~$ sudo reboot

Broadcast message from root@server on pts/1 (Tue 2025-02-25 19:36:22 CET):

The system will reboot now!
```

Voilà, notre serveur est prêt à accueillir Bitwarden !

**à partir d'ici, l'installation est la même qu'on soit sur Freebox OS ou sur Raspberry**

#### Installation de Docker

Pour faire fonctionner Vaultwarden, la solution Docker sera indispensable. Pour l'installer : 

```
julabuche@server:~ $ sudo apt install docker docker-compose -y
```

Ensuite on vérifie que ça fonctionne correctement :
```
julabuche@server:~ $ sudo docker ps
CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES
```

#### Installation du conteneur Docker Vaultwarden

Par la suite, on va télécharger le conteneur docker correspondant à Vaultwarden :

```
julabuche@server:~ $ sudo docker pull vaultwarden/server:latest
latest: Pulling from vaultwarden/server
4d2547c08499: Pull complete
d3c91324ded5: Pull complete
2941ad44fa1c: Pull complete
83805dacd5c4: Pull complete
4e841dd38e77: Pull complete
Digest: *******
Status: Downloaded newer image for vaultwarden/server:latest
docker.io/vaultwarden/server:latest
```

Maintenant, on va lancer le conteneur via le protocole HTTP classique, histoire de voir si ça fonctionne. Dans l'absolu, vaut mieux éviter de le faire tourner en HTTP mais on verra comment faire un peu plus tard pour utiliser HTTPS, ici c'est juste pour voir si ça fonctionne !

```
julabuche@server:~ $ sudo docker run -d --name vaultwarden -v /vw-data/:/data -p 80:80 vaultwarden/server:latest
*********************
julabuche@server:~ $ sudo docker ps
CONTAINER ID   IMAGE                       COMMAND       CREATED         STATUS                            PORTS                               NAMES
4a9b675e9099   vaultwarden/server:latest   "/start.sh"   5 seconds ago   Up 4 seconds (health: starting)   0.0.0.0:80->80/tcp, :::80->80/tcp   vaultwarden
```

Donc là on voit bien qu'il fonctionne, il faudra maintenant se rendre sur l'interface web via l'adresse IP locale du serveur : http://192.168.X.X/ pour s'assurer qu'on a bien l'interface web de Vaultwarden. Pas de panique si le chargement dure à l'infini, de ce que j'ai vu c'est parce qu'il n'y a pas encore HTTPS d'actif. Mais si vous avez le logo Vaultwarden, vous pouvez passer à la suite.

#### Mettre en place le certificat HTTPS

Pour ceci, il vous faut impérativement un nom de domaine. Pas de panique, on peut en avoir gratuitement ! En l'occurence en utilisant IPv6, il faut un hébergeur le supportant, et gratuit. En fait, c'est plutot un fonctionnement de DNS qu'on voit ici.
J'utilisais jusqu'à présent DynV6, mais il existe également MOOO qui supporte IPv6. 

C'est pas très compliqué à configurer, on choisit un nom de domaine (l'extension sera imposée par contre... gratuité oblige), et on y renseigne tout simplement l'IPv6 du serveur (trouvable avec la commande ```ip a```) dans le champ IPv6 !
Une fois fait, vous devriez pouvoir accéder au serveur via votre nouveau nom de domaine.

Perso, j'ai abandonné cette idée car les DNS sont souvent down (et donc impossible d'accéder au serveur). Je pense prochainement acheter un domaine personnalisé, ça fonctionnera mieux je pense.

Une fois votre nom de domaine actif, il faudra génerer un certificat Let's Encrypt pour ce nom de domaine. Pour cela, on utilisera un paquet Linux nommé ```certbot``` :

```
julabuche@server:~ $ sudo docker stop vaultwarden
julabuche@server:~ $ sudo docker rm vaultwarden
julabuche@server:~ $ sudo apt install certbot -y
julabuche@server:~ $ sudo certbot certonly
Saving debug log to /var/log/letsencrypt/letsencrypt.log

How would you like to authenticate with the ACME CA?
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
1: Spin up a temporary webserver (standalone)
2: Place files in webroot directory (webroot)
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Select the appropriate number [1-2] then [enter] (press 'c' to cancel): 1
Enter email address (used for urgent renewal and security notices)
 (Enter 'c' to cancel): *********

- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Please read the Terms of Service at
https://letsencrypt.org/documents/LE-SA-v1.5-February-24-2025.pdf. You must
agree in order to register with the ACME server. Do you agree?
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
(Y)es/(N)o: Y

- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Would you be willing, once your first certificate is successfully issued, to
share your email address with the Electronic Frontier Foundation, a founding
partner of the Let's Encrypt project and the non-profit organization that
develops Certbot? We'd like to send you email about our work encrypting the web,
EFF news, campaigns, and ways to support digital freedom.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
(Y)es/(N)o: N
Account registered.
Please enter the domain name(s) you would like on your certificate (comma and/or
space separated) (Enter 'c' to cancel): ***********
Requesting a certificate for ***********

Successfully received certificate.
Certificate is saved at: /etc/letsencrypt/live/***********/fullchain.pem
Key is saved at:         /etc/letsencrypt/live/***********/privkey.pem
This certificate expires on 2025-05-27.
These files will be updated when the certificate renews.
Certbot has set up a scheduled task to automatically renew this certificate in the background.

- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
If you like Certbot, please consider supporting our work by:
 * Donating to ISRG / Let's Encrypt:   https://letsencrypt.org/donate
 * Donating to EFF:                    https://eff.org/donate-le
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
```

Voilà, on est bon. On peut voir qu'il a généré 2 fichiers, un ```fullchain.pem``` et un ```privkey.pem```. On va les déplacer à un autre endroit :
```
julabuche@server:~ $ sudo mkdir /ssl && cd /ssl && sudo mkdir keys
julabuche@server:/ssl $ sudo -s
root@server:/ssl# sudo cp /etc/letsencrypt/live/***********/fullchain.pem /ssl/keys/certs.pem
root@server:/ssl# sudo cp /etc/letsencrypt/live/***********/privkey.pem /ssl/keys/key.pem
root@server:/ssl# exit
```

Pour ensuite pouvoir les utiliser pour relancer le conteneur afin qu'il utilise HTTPS :
```
julabuche@server:/ssl $ sudo docker run -d --name vaultwarden -e ROCKET_TLS='{certs="/ssl/certs.pem",key="/ssl/key.pem"}' -v /ssl/keys/:/ssl/ -v /vw-data/:/data/ -p 443:80 vaultwarden/server:latest
***************
julabuche@server:/ssl $ sudo docker ps
CONTAINER ID   IMAGE                       COMMAND       CREATED         STATUS                            PORTS                                 NAMES
f2a8d0514b73   vaultwarden/server:latest   "/start.sh"   4 seconds ago   Up 3 seconds (health: starting)   0.0.0.0:443->80/tcp, :::443->80/tcp   vaultwarden
```

Voilà, là on est bon ! vous pouvez essayer d'accéder à votre serveur via le nom de domaine que vous avez setup, en https cette fois ci ;)

/!\ DISCLAIMER : 
* Lors de l'installation du certificat SSL Letsencrypt, il arrive parfois que tous les certificats soient pris et qu'il faille attendre pour le générer. la date et l'heure où vous pouvez réessayer sont inscrits dans les logs quand ça vous met l'erreur.
* Certains réseaux d'entreprises ayant des exigences de sécurité un peu élevées peuvent bloquer l'accès au serveur à cause du certificat Letsencrypt. du coup je vous invite à utiliser un autre certificat si vous le pouvez, mais letsencrypt fonctionne très bien sur des réseaux domestiques. si vous avez que cet usage là, pour le coup letsencrypt fera tout votre usage.

pour la sauvegarde de la BDD, il faut encore que je me penche sur le sujet. le mieux serait soit d'avoir un sauvegarde de la BDD sur un support externe, un serveur à part, ou encore avoir un 2e serveur bitwarden délocalisé afin d'avoir une redondance. 
_En cours de réflexion_

#### mise en place du cron

Pour plusieurs raisons, vous pouvez être amené à redémarrer le serveur, sauf que le conteneur ne redémarre pas automatiquement : il faut donc dire au serveur de démarrer le conteneur avec tous les paramètres à chaque redémarrage. Attention : il faut absolument le faire en root !!

```
julabuche@server:~ $ sudo -s
root@server:/home/cedriccuny# crontab -e
no crontab for root - using an empty one

Select an editor.  To change later, run 'select-editor'.
  1. /bin/nano        <---- easiest
  2. /usr/bin/vim.tiny
  3. /bin/ed

Choose 1-3 [1]: 1
crontab: installing new crontab
```

```
# Edit this file to introduce tasks to be run by cron.
#
# Each task to run has to be defined through a single line
# indicating with different fields when the task will be run
# and what command to run for the task
#
# To define the time you can provide concrete values for
# minute (m), hour (h), day of month (dom), month (mon),
# and day of week (dow) or use '*' in these fields (for 'any').
#
# Notice that tasks will be started based on the cron's system
# daemon's notion of time and timezones.
#
# Output of the crontab jobs (including errors) is sent through
# email to the user the crontab file belongs to (unless redirected).
#
# For example, you can run a backup of all your user accounts
# at 5 a.m every week with:
# 0 5 * * 1 tar -zcf /var/backups/home.tgz /home/
#
# For more information see the manual pages of crontab(5) and cron(8)
#
# m h  dom mon dow   command

@reboot docker run -d --name vaultwarden -e ROCKET_TLS='{certs="/ssl/certs.pem",key="/ssl/key.pem"}' -v /ssl/keys/:/ssl/ -v /vw-data/:/data/ -p 443:80 vaultwarden/server:latest
```

On rentre ici le paramètre ```@reboot``` qui permet de lancer la commande qui suit à chaque redémarrage. La commande qui suit est la même que tout à l'heure pour le lancer manuellement, siplement sans le sudo (car on est en root ;)
Vous pouvez ensuite enregistrer le fichier et redémarrer votre serveur pour tester si le conteneur se lance correctement !

## renouvellement du certificat

voir : https://chatgpt.com/share/1a3f13d0-f890-4f5f-be06-d54b5febbcbd _A rerédiger lorsque ça sera de nouveau le moment du renouvellement_

## upgrade nouvelle version vaultwarden

il arrive que des nouvelles versions de vaultwarden soient publiées (heureusement), voici la procédure pour les installer.

commencer par stopper le conteneur vaultwarden déjà en cours d'exécution :

```
sudo docker stop vaultwarden
sudo docker rm vaultwarden
```

_remplacer `vaultwarden` par le nom du conteneur docker en question qui est visible en tapant la commande `sudo docker ps`_

installer ensuite la dernière version du conteneur docker :

```
sudo docker pull vaultwarden/server:latest
```

une fois fini, vous pouvez relancer le conteneur docker avec la commande suivante : 

```
sudo docker run -d --name vaultwarden -e ROCKET_TLS='{certs="/ssl/certs.pem",key="/ssl/key.pem"}' -v /ssl/keys/:/ssl/ -v /vw-data/:/data/ -p 443:80 vaultwarden/server:latest
```

et voilà, vaultwarden est à jour !

## upgrade openssh

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


