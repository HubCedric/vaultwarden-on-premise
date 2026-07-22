> [!CAUTION]
> Archive historique conservée pour le retour d'expérience. Cette page contient des commandes, versions et choix d'architecture obsolètes. Ne l'utilisez pas comme procédure d'installation ; suivez le [README principal](../../README.md) et la documentation courante.

# bitwarden-on-premise
Bitwarden on Premise - Raspberry Pi

je me suis lancé dans la mise en place d'un gestionnaire de mot de passe on premise, sur un serveur chez moi à la maison.

état des lieux : actuellement sous bitwarden en mode saas, l'idée est de migrer mes mots de passe sur un serveur en local afin qu'ils ne se trouvent pas sur des serveurs dont je n'ai pas la main.

# Sommaire

* [Mise en place](#mise-en-place)
  * [Installation sur Raspberry Pi](#installation-sur-raspberry-pi)
    * [Installation de l'OS](#installation-de-los)  
  * [Installation sur Freebox OS](#installation-sur-freebox-os)  
    * [Installation de l'OS](#installation-de-los-1)  
    * [Préparation de l'OS](#préparation-de-los)  
    * [Installation de Docker](#installation-de-docker)  
    * [Mettre en place le certificat HTTPS](#mettre-en-place-le-certificat-https)  
    * [Mise en place du cron](#mise-en-place-du-cron)
* [En cas d'indisponibilité du serveur](#en-cas-dindisponibilité-du-serveur)  
  * [Mise en place du tunnel VPN](#mise-en-place-du-tunnel-vpn)
  * [Transfert de la base de données SQLITE3 vers MySQL](#transfert-de-la-base-de-donnees-sqlite3-vers-mysql)
  * [Mise en place du cluster entre les 2 bases de données](#mise-en-place-du-cluster-entre-les-2-bases-de-donnees)
  * [Surveillance et correction automatique de la réplication](#surveillance-et-correction-automatique-de-la-réplication)
  * [Récupération après une réplication cassée durablement (split-brain)](#récupération-après-une-réplication-cassée-durablement-split-brain)
  * [Configuration du VPS](#configuration-du-vps)
* [Debug](#debug)  
  * [Root cause : colonnes uuid/id converties en TEXT au lieu de VARCHAR(36)](#root-cause--colonnes-uuidid-converties-en-text-au-lieu-de-varchar36)  
* [Si besoin de downgrade de version](#si-besoin-de-downgrade-de-version)  
* [Sécurité](#sécurité)  
  * [Renouvellement du certificat](#renouvellement-du-certificat)  
  * [Mises à jour de Vaultwarden](#mises-à-jour-de-vaultwarden)  
    * [Script de mise à jour semi-automatique (avec backup, vérification et rollback)](#script-de-mise-à-jour-semi-automatique-avec-backup-vérification-et-rollback)  
  * [Upgrade OpenSSH](#upgrade-openssh)  
  * [Changer le port par défaut de SSH](#changer-le-port-par-défaut-de-ssh)  


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

**à partir d'ici, l'installation est la même qu'on soit sur Freebox OS ou sur Raspberry**

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

#### Mise en place du cron

Pour plusieurs raisons, vous pouvez être amené à redémarrer le serveur, sauf que le conteneur ne redémarre pas automatiquement : il faut donc dire au serveur de démarrer le conteneur avec tous les paramètres à chaque redémarrage. Attention : il faut absolument le faire en root !!

```
julabuche@server:~ $ sudo -s
root@server:/home/julabuche# crontab -e
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

@reboot docker rm vaultwarden && docker run -d --name vaultwarden -e ROCKET_TLS='{certs="/ssl/certs.pem",key="/ssl/key.pem"}' -v /ssl/keys/:/ssl/ -v /vw-data/:/data/ -p 443:80 vaultwarden/server:latest
```

On rentre ici le paramètre ```@reboot``` qui permet de lancer la commande qui suit à chaque redémarrage. La commande qui suit est la même que tout à l'heure pour le lancer manuellement, siplement sans le sudo (car on est en root ;), et on ajoute juste avant la suppression de l'ancien conteneur nommé vaultwarden sinon il redémarrera pas ^^
Vous pouvez ensuite enregistrer le fichier et redémarrer votre serveur pour tester si le conteneur se lance correctement !

## En cas d'indisponibilité du serveur

Jusqu'à présent, je faisais tourner mon serveur sur ma Freebox, cependant dans mon quartier j'ai eu une période avec pas mal de coupures internet qui durent longtemps. Vous en conviendrez que pour l'utilisation d'un gestionnaire de mot de passe, ça pose problème si une coupure de 2 semaines venait à arriver. (spoiler : c'est déjà arrivé !). On peut aussi garder l'éventualité que le serveur plante (c'est aussi déjà arrivé, souvenez vous de ma carte SD...). Du coup, qu'est-ce qu'on fait ?

Plusieurs solutions peuvent palier à ce problème. J'ai eu 2 idées :
* Mettre en place une sauvegarde de la BDD. Ca peut être bien en cas de plantage du serveur afin d'avoir une sauvegarde, mais si y'a des coupures internet ça garde le serveur indispo. Et puis, faire une sauvegarde implique d'avoir un 2e support de stockage, ce qui peut être contraignant dans certaines configurations/infrastructures.
* Mettre en place un 2e serveur pour avoir une redondance. C'est la solution qui offre la meilleure qualité de service, mais c'est aussi la plus compliquée à mettre en place :D

Au final, je suis parti sur la 2e solution. J'ai l'avantage de pouvoir avoir 2 serveurs à 2 endroits différents (un chez moi, et l'autre chez mes parents), ça a l'avantage de protéger aussi des risques physiques (incendie par exemple). Donc l'idée, c'est d'avoir 2 serveurs identiques qui communiquent entre eux via un tunnel VPN pour sécuriser l'échange des données. Un cluster au niveau de la base de données servira à l'échange des données entre les 2 serveurs.

Prérequis :
* 3 serveurs
  * 1 VPS qui nous servira pour du load balancing : explications plus bas.
  * 2 serveurs faisant tourner le conteneur Vaultwarden. Le fonctionnement de Vaultwarden doit être une copie conforme des 2 côtés ! 
* Les 3 serveurs doivent communiquer entre eux en réseau (via IPv4 ou IPv6, le plus simple étant IPv6 car pas besoin d'ouverture de ports)

/!\ A partir de maintenant, étant donné qu'on met en place une redondance, il y a certaines configurations effectuées en amont qui ne seront plus utiles. Vous pouvez donc supprimer la ligne du cron permettant de redémarrer le conteneur, et vous n'avez pas besoin de certificat Let's Encrypt pour les serveurs finaux (ni même pour le VPS d'ailleurs, explications plus bas).

### Mise en place du tunnel VPN

On va commencer par mettre en place un tunnel VPN, pour cela on va utiliser WireGuard. Rien à voir avec les solutions du type NordVPN, NordVPN ayant pour objectif principal de faire du chiffre. Ici, c'est totalement gratuit !

On commence par installer WireGuard **sur les 3 serveurs** et on se rend ensuite dans le dossier correspondant avec l'utilisateur root :
```
julabuche@server:~ $ sudo apt install wireguard
julabuche@server:~ $ cd /etc/wireguard/
julabuche@server:/etc/wireguard/ $ sudo -s
root@server:/etc/wireguard/ $
```

Sur un des 2 serveurs, on va lancer ces 2 commandes qui vont servir à génerer les clés des serveurs/client, qu'on va ensuite intégrer à la configuration de WireGuard :

```
wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
wg genkey | tee /etc/wireguard/client_private.key | wg pubkey > /etc/wireguard/client_public.key
```

Dans le répertoire ```/etc/wireguard``` vous trouverez 4 fichiers :

```
root@server:/etc/wireguard# ll
total 36
drwx------   2 root root  4096 Mar 12 08:34 ./
drwxr-xr-x 118 root root 12288 Mar 11 10:14 ../
-rw-r--r--   1 root root    45 Mar  5 17:19 client_private.key
-rw-r--r--   1 root root    45 Mar  5 17:19 client_public.key
-rw-r--r--   1 root root    45 Mar  5 17:16 server_private.key
-rw-r--r--   1 root root    45 Mar  5 17:16 server_public.key
```

Ces fichiers vont servir pour éditer la configuration de WireGuard.

sur le VPS, on va lancer cette commande pour générer les clés :

```
wg genkey | tee privatekey | wg pubkey > publickey
```

Ensuite, sur le serveur principal (le "serveur VPN"), on édite le fichier suivant :

```
sudo nano /etc/wireguard/wg0.conf
```

```
[Interface]
Address = 10.0.0.1/32
ListenPort = 51820
PrivateKey = PRIVATE_SERVER

[Peer]
PublicKey = PUBLIC_CLIENT
AllowedIPs = 10.0.0.2/32
Endpoint = [IPV6_CLIENT_VPN]:51820

[Peer]
PublicKey = PUBLIC_VPS
AllowedIPs = 10.0.0.10/32
Endpoint = [IPV6_VPS]:51820
```

Ensuite, sur le serveur secondaire (le "client VPN"), on édite le fichier suivant :

```
sudo nano /etc/wireguard/wg0.conf
```

```
[Interface]
PrivateKey = PRIVATE_CLIENT
Address = 10.0.0.2/32
ListenPort = 51820
DNS = 8.8.8.8

[Peer]
PublicKey = PUBLIC_SERVER 
Endpoint = [IPV6_SERVEUR_VPN]:51820
AllowedIPs = 10.0.0.1/32
PersistentKeepalive = 25

[Peer]
PublicKey = PUBLIC_VPS 
Endpoint = [IPV6_VPS]:51820
AllowedIPs = 10.0.0.10/32
PersistentKeepalive = 25
```

Ensuite, sur le VPS, on édite le fichier suivant :

```
sudo nano /etc/wireguard/wg0.conf
```

```
[Interface]
PrivateKey = PRIVATE_VPS
Address = 10.0.0.10/32
ListenPort = 51820

[Peer]
PublicKey = PUBLIC_SERVER
Endpoint = [IPV6_SERVEUR_VPN]:51820
AllowedIPs = 10.0.0.1/32
PersistentKeepalive = 25

[Peer]
PublicKey = PUBLIC_CLIENT
Endpoint = [IPV6_CLIENT_VPN]:51820
AllowedIPs = 10.0.0.2/32
PersistentKeepalive = 25
```

Une fois les fichiers de configuration édités, il faut lancer le service :

_Seulement sur le "serveur VPN" :_

```
sudo wg addconf wg0 <(wg showconf wg0)
```

_Sur les 3 machines :_

```
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
sudo systemctl status wg-quick@wg0
```

Personnellement, j'ai dû installer le paquet ```resolvconf``` sur une des machines sinon ça ne marchait pas.

On peut tester le bon fonctionnement en tapant la commande ```ip a``` et voir si une carte réseau nommée ```wg0``` est bien présente. On peut aussi essayer de ping les adresses IP ```10.0.0.1```, ```10.0.0.2``` et ```10.0.0.10``` pour voir si ça fonctionne !

## Transfert de la base de données SQLITE3 vers MySQL

Par défaut, Vaultwarden utilise une base de données SQLITE3 pour stocker vos mots de passe (de manière chiffrée évidemment), sauf qu'à l'usage c'est pas très utilisable. L'idée, c'est de "transformer" la base SQLITE3 vers une base MySQL, afin de pouvoir répliquer les données de façon automatique et instantanément vers le 2e serveur de backup.

Les 2 serveurs se verront utiliser une base MySQL à terme, et non pas une base SQLITE3.

Avant tout, il faudra installer les paquets suivants
```
sudo apt install mariadb-server python3
sudo python3 -m pip install sqlite3-to-mysql --break-system-packages
```

Ensuite, on peut lancer le transfert SQLITE3 vers MySQL
```
julabuche@server:/vw-data/ $ sqlite3mysql -f db.sqlite3 -d vaultwarden -u vaultwarden -p -X -i IGNORE
```

Vous pouvez lancer cette commande seulement sur un serveur, la réplication fera que les données seront automatiquement synchronisées.

## Mise en place du cluster entre les 2 bases de données

---

### Prérequis

- Deux serveurs MariaDB (`db1` et `db2`) avec la **même version** installée
- Un accès root sur les deux serveurs
- Le port **3306** ouvert entre les deux serveurs
- Les deux serveurs doivent avoir des **adresses IP fixes**
- Pare-feu configuré pour autoriser les connexions entre les serveurs MariaDB

---

### Configuration de MariaDB

Modifier le fichier de configuration MariaDB (`/etc/mysql/mariadb.conf.d/50-server.cnf` ou `/etc/my.cnf`) sur **les deux serveurs** :

#### Sur `srv1` :

```
[mysqld]
server-id = 1
log_bin = mysql-bin
binlog_format = ROW
bind-address = 0.0.0.0 <= IP SRV1 VPN
auto_increment_increment = 2
auto_increment_offset = 1
skip-name-resolve
```

#### Sur `srv2` :
```
[mysqld]
server-id = 2
log_bin = mysql-bin
binlog_format = ROW
bind-address = 0.0.0.0 <= IP SRV2 VPN
auto_increment_increment = 2
auto_increment_offset = 2
skip-name-resolve
```

#### Sur `srv1` & `srv2`
```
sudo systemctl restart mariadb
```

```
CREATE USER 'repli'@'%' IDENTIFIED BY 'password';
GRANT REPLICATION SLAVE ON *.* TO 'repli'@'%';
FLUSH PRIVILEGES;
```

### Configuration de la réplication

#### Sur `srv1` :

```
CHANGE MASTER TO
  MASTER_HOST='srv2',
  MASTER_USER='repli',
  MASTER_PASSWORD='password',
  MASTER_PORT=3306,
  MASTER_USE_GTID=slave_pos;

START SLAVE;
```

#### Sur `srv2` :
```
CHANGE MASTER TO
  MASTER_HOST='srv1',
  MASTER_USER='repli',
  MASTER_PASSWORD='password',
  MASTER_PORT=3306,
  MASTER_USE_GTID=slave_pos;

START SLAVE;
```

#### Vérification sur `srv1` & `srv2` :
```
SHOW SLAVE STATUS\G
```

## Surveillance et correction automatique de la réplication

Une fois le cluster en place, la réplication master↔master peut se casser silencieusement (coupure réseau, redémarrage de MariaDB, conflit sur une ligne). Comme c'est une base de mots de passe, on veut le savoir vite — sans qu'un script ne "corrige" tout seul un conflit de données au risque de faire diverger discrètement les 2 bases sans que personne ne s'en rende compte.

[`scripts/check_replication.sh`](scripts/check_replication.sh) tourne en cron chaque jour sur `srv1` **et** `srv2` (chacun surveille son propre thread de réplication, et lit — en lecture seule — le statut de l'autre pour donner une vue complète en cas d'alerte) :

- **Réplication saine** (threads actifs, retard sous le seuil) → rien ne se passe, une simple ligne de log.
- **Thread arrêté sans erreur de données** (coupure réseau, arrêt manuel) → tentative de redémarrage automatique (`STOP SLAVE; START SLAVE;`, plusieurs essais), puis email indiquant que c'est corrigé — ou que ça a échoué et qu'une intervention est nécessaire.
- **`SHOW SLAVE STATUS` ne retourne plus rien** (configuration perdue, ex. après un `RESET SLAVE ALL`) **mais `gtid_slave_pos` prouve que ce nœud avait déjà répliqué avant** → reconfiguration automatique (`CHANGE MASTER TO ... MASTER_USE_GTID=slave_pos; START SLAVE;`) en repartant exactement de la dernière position connue : aucun risque de trou ni de doublon de données.
- **`gtid_slave_pos` vide** (réplication jamais initialisée, ou remise à zéro totale) → le script ne touche à rien et alerte par email pour une mise en place manuelle (voir section précédente) : c'est le seul cas où la position de reprise sûre n'est pas connue.
- **Conflit de données** (`Last_SQL_Errno != 0`, ex. clé dupliquée) → **jamais de correction automatique**, alerte immédiate par email avec le détail de l'erreur SQL, pour investigation manuelle.

### Prérequis SQL

Sur `srv1` & `srv2` :

```sql
CREATE USER 'monitor'@'localhost' IDENTIFIED BY 'password';
GRANT REPLICATION CLIENT, SUPER ON *.* TO 'monitor'@'localhost';

CREATE USER 'monitor'@'127.0.0.1' IDENTIFIED BY 'password';
GRANT REPLICATION CLIENT, SUPER ON *.* TO 'monitor'@'127.0.0.1';

CREATE USER 'monitor'@'<IP VPN DU PAIR>' IDENTIFIED BY 'password';
GRANT REPLICATION CLIENT ON *.* TO 'monitor'@'<IP VPN DU PAIR>';

FLUSH PRIVILEGES;
```

Même nom d'utilisateur (`monitor`), mais plusieurs lignes avec des hôtes différents : MariaDB applique les privilèges de l'entrée la plus spécifique correspondant à l'hôte de connexion. Ainsi le `SUPER` (nécessaire pour `STOP SLAVE`/`START SLAVE`/`CHANGE MASTER TO`) n'est jamais accessible depuis le réseau, seulement en local (`localhost` **et** `127.0.0.1` : selon la configuration du client `mysql`, une connexion à `localhost` peut malgré tout passer par du TCP et être vue par le serveur comme `127.0.0.1` — les deux entrées évitent toute ambiguïté) — le pair ne peut que *lire* le statut, jamais agir dessus. (Sur MariaDB ≥ 10.5, `REPLICATION SLAVE ADMIN` peut remplacer `SUPER` pour se limiter au strict nécessaire.)

### Installation

`check_replication.sh` partage le même fichier `.env` que `update_vaultwarden.sh` (voir [Script de mise à jour semi-automatique](#script-de-mise-à-jour-semi-automatique-avec-backup-vérification-et-rollback) pour l'installation initiale du dossier) — s'il existe déjà, ne renseigner que les variables `NODE_NAME`, `MONITOR_USER`/`MONITOR_PASSWORD`, `PEER_HOST`/`PEER_PORT`, `REPL_USER`/`REPL_PASSWORD` en plus :

```
cd /opt/vaultwarden
cp /chemin/vers/scripts/check_replication.sh .
chmod +x check_replication.sh
# .env déjà présent ? éditer directement : nano .env
# sinon : cp /chemin/vers/scripts/.env.example ./.env puis nano .env
```

### Cron (sur `srv1` ET `srv2`)

```
crontab -e
```
```
# m h  dom mon dow   command
0 6 * * * /opt/vaultwarden/check_replication.sh >> /var/log/check_replication_cron.log 2>&1
```

/!\ Le fichier `.env` contient des identifiants et n'est jamais commité (voir `.gitignore`).

/!\ Pour le moment, `ENABLE_MAIL=0` par défaut : les alertes ne sont écrites que dans `REPLICATION_LOG_FILE`, aucun email n'est envoyé. Passer `ENABLE_MAIL=1` (et renseigner `MAIL_TO`) activera l'envoi par email, mais nécessite un MTA local fonctionnel (`postfix`, `ssmtp`, `msmtp`...) pour que la commande `mail` envoie effectivement les alertes.

## Récupération après une réplication cassée durablement (split-brain)

Retour d'expérience d'un incident réel : la réplication master↔master s'est cassée silencieusement (voir [Debug](#debug) pour la cause réseau) et est restée cassée pendant un moment sans que ça soit détecté — avant la mise en place de `check_replication.sh` ci-dessus, il n'y avait aucun moyen de le savoir. Pendant cette période, les deux serveurs ont continué à fonctionner indépendamment (Vaultwarden tournait sur `bitwarden-slave`, servant tout le trafic, tandis que `bitwarden-master` avait son propre historique), ce qui a créé une divergence réelle de données entre les 2 bases — pas juste un retard à rattraper.

Cette section documente la procédure complète suivie pour s'en sortir, dans l'ordre.

### 1. Diagnostiquer la connectivité avant de blâmer la réplication elle-même

Avant de supposer que la réplication est "cassée" au sens MariaDB, vérifier que les 2 serveurs peuvent seulement se joindre :
- `ping` entre les 2 IP VPN (confirme le tunnel WireGuard, pas grand-chose de plus)
- `nc -zv -w5 <IP pair> 3306` (le port MySQL répond-il vraiment ?)
- `mysql -h <IP pair> -P 3306 -u <compte> -p -e "SELECT 1;"` avec le compte concerné

Dans notre cas, le vrai blocage était un firewall (`ufw`) qui n'autorisait aucune connexion entrante sur le port 3306 depuis l'IP VPN du pair — aucune règle du tout pour ce sens, alors que la réplication (et donc `repli`) en a besoin dans les 2 sens. Voir aussi le piège `127.0.0.1` vs `localhost` documenté plus haut pour les comptes de supervision.

### 2. Quantifier et réconcilier la divergence de données AVANT de toucher à la réplication

Ne jamais supposer qu'un des 2 côtés est "la vérité" sans vérifier — même si un seul des 2 servait le trafic au moment de la panne, l'autre peut avoir des écritures plus anciennes jamais répliquées avant la coupure. [`scripts/reconcile_split_brain.sh`](scripts/reconcile_split_brain.sh) sert exactement à ça :

1. Se connecte en lecture seule aux 2 serveurs (compte dédié `reconcile_ro`, voir prérequis SQL ci-dessous), importe un dump frais de chacun dans des bases temporaires locales (jamais dans une base nommée `vaultwarden`).
2. Compare `users`, `folders`, `devices` (clé composite `uuid`+`user_uuid` — un même appareil/navigateur peut être associé à plusieurs comptes) et `ciphers` ligne par ligne : la version la plus récente (`updated_at`) gagne, dans le sens qui convient (ça peut être master→slave pour une ligne et slave→master pour une autre — ne jamais supposer qu'un sens unique s'applique à tout).
3. Compare aussi `folders_ciphers` (association dossier/mot de passe, clé composite sans colonne de date : simple différence d'ensemble).
4. Génère 2 fichiers SQL (`apply_to_master.sql`, `apply_to_slave.sql`) à relire avant toute exécution.

**Prérequis SQL** (sur `srv1` & `srv2`, comme pour `monitor`) :
```sql
CREATE USER 'reconcile_ro'@'localhost' IDENTIFIED BY 'password';
GRANT SELECT ON vaultwarden.* TO 'reconcile_ro'@'localhost';

CREATE USER 'reconcile_ro'@'127.0.0.1' IDENTIFIED BY 'password';
GRANT SELECT ON vaultwarden.* TO 'reconcile_ro'@'127.0.0.1';

CREATE USER 'reconcile_ro'@'<IP VPN DU PAIR>' IDENTIFIED BY 'password';
GRANT SELECT ON vaultwarden.* TO 'reconcile_ro'@'<IP VPN DU PAIR>';

FLUSH PRIVILEGES;
```

**Installation et usage :** même fichier `.env` partagé que les 2 autres scripts (voir plus loin l'installation de `update_vaultwarden.sh`) — compléter avec `MASTER_HOST`/`SLAVE_HOST` (`127.0.0.1` pour le serveur LOCAL, celui d'où on lance, IP VPN pour l'autre) et les identifiants `reconcile_ro`/`vaultwarden` correspondants :
```
cp /chemin/vers/scripts/reconcile_split_brain.sh .
chmod +x reconcile_split_brain.sh
# .env déjà présent ? éditer directement : nano .env
# sinon : cp /chemin/vers/scripts/.env.example ./.env puis nano .env

./reconcile_split_brain.sh /tmp/reconcile_report        # génère les fichiers, rien n'est écrit
# relire /tmp/reconcile_report/apply_to_*.sql, en particulier tout cas où
# le sens de synchronisation d'une ligne surprend (voir known_errors.md)

./reconcile_split_brain.sh /tmp/reconcile_report --apply   # applique réellement, après confirmation "oui"
```

`--apply` écrit le fichier du serveur **local** via les droits admin déjà présents, et celui du serveur **distant** via le compte applicatif `vaultwarden` existant (déjà `ALL PRIVILEGES` sur `vaultwarden.*`, déjà joignable sur le réseau — aucun nouveau grant nécessaire) : renseigner `MASTER_WRITE_USER`/`MASTER_WRITE_PASSWORD` et `SLAVE_WRITE_USER`/`SLAVE_WRITE_PASSWORD` dans `.env` avec les vrais identifiants Vaultwarden de chaque serveur.

Outil **ponctuel** : pas de cron, à utiliser une fois par incident puis oublier.

### 3. Corriger les éventuels problèmes de schéma avant de relancer la réplication

Un schéma différent entre les 2 serveurs (ex: une colonne `CHAR` d'un côté, `VARCHAR` de l'autre — cf. `sso_users` dans [Debug](#debug)) bloque la réplication dès qu'un événement touche cette table. Vérifier et aligner **avant** l'étape suivante, sinon la réplication se recassera immédiatement.

### 4. Repartir sur une réplication propre

Une fois les données réconciliées (étape 2) et les schémas alignés (étape 3), repartir de zéro plutôt que d'essayer de réparer l'ancien lien — sur les **2 serveurs** :

```sql
STOP SLAVE;
RESET SLAVE ALL;
RESET MASTER;
```

/!\ `RESET MASTER` vide le binlog et la position GTID **générée** par ce serveur, mais **pas** `gtid_slave_pos` (la position qu'il a mémorisée comme "j'ai déjà rejoué jusqu'ici depuis l'autre serveur") — sans `RESET SLAVE ALL` en plus, la réplication repart sur une très vieille position et rejoue tout l'historique déjà appliqué des 2 côtés (voir `known_errors.md` pour les symptômes exacts rencontrés).

Puis, sur chaque serveur, pointer vers l'autre (adapter les IP) :
```sql
CHANGE MASTER TO
  MASTER_HOST='<IP VPN de l''autre serveur>',
  MASTER_USER='repli',
  MASTER_PASSWORD='<mot de passe repli>',
  MASTER_PORT=3306,
  MASTER_USE_GTID=slave_pos;
START SLAVE;
```

Vérifier avec `SHOW SLAVE STATUS\G` sur les 2 : `Slave_IO_Running: Yes`, `Slave_SQL_Running: Yes`, `Last_Errno: 0`.

### 5. Conflits bénins possibles après le redémarrage

Même avec les données applicatives réconciliées, des tables internes à Vaultwarden/Diesel (ex: `__diesel_schema_migrations`, ou une `ALTER TABLE` de migration déjà appliquée des 2 côtés) peuvent encore déclencher une erreur de réplication (`Duplicate entry`, `Duplicate column name`) — ce n'est pas une divergence de données réelles, juste deux historiques de migrations identiques qui se recroisent. C'est le **seul** type de cas où sauter l'événement est acceptable (jamais sur `users`/`ciphers`/`folders`/`devices`) :
```sql
STOP SLAVE;
SET GLOBAL sql_slave_skip_counter = 1;
START SLAVE;
```
Revérifier `SHOW SLAVE STATUS\G` ; répéter si un nouveau conflit du même type apparaît.

### 6. Après coup

- Relancer `check_replication.sh` sur les 2 serveurs pour confirmer qu'il ne signale plus rien.
- Faire un test de bout en bout (une écriture d'un côté, vérifier qu'elle apparaît de l'autre) avant de redonner confiance totale.
- Relancer Vaultwarden sur le serveur resté éteint et le remettre dans la rotation Caddy.

## Configuration du VPS

Après avoir testé que la réplication fonctionne dans les 2 sens, on va pouvoir configurer le VPS.

Comme dit plus haut, j'ai finalement acheté un nom de domaine. DynV6 et compagnie c'est bien beau, mais c'est pas trop top pour une utilisation "intensive", les DNS sont souvent dans les choux. C'était bien pour débuter mais à terme vaut mieux un truc qui marche 24/24 7/7.

Le VPS va faire office de load balancer. C'est lui qui va choisir sur quel serveur final il va se connecter, et comme réplication est faite via le cluster, ce sera totalement transpartent pour l'utilisateur final. C'est à lui qu'on va se connecter en priorité en gros, et il va utiliser les adresse IP VPN afin que les serveurs finaux ne soient pas du tout visible depuis l'exterieur. Le but c'est qu'on y accède jamais en direct, mais uniquement via le load balancer !

Pour ce faire, on va utiliser la solution Caddy. Cette derniere à l'avantage d'être simple à configurer, et a l'avantage de gérer nativement les certificats SSL, donc cela ne demandera jamais de repasser par dessus pour mettre à jour les certificats.

```
sudo apt install caddy
```

Ensuite on édite le fichier de conf : 

```
sudo nano /etc/caddy/Caddyfile
```

```
bitwarden.mondomaine.fr {                                     # Ici il faut renseigner l'URL de votre domaine. Perso j'ai mis "bitwarden.mondomaine.fr"
        reverse_proxy {                                       # Cela sert à ajouter les 2 serveurs finaux et que le VPS puisse choisir entre tout ceux qu'il y a dans la liste
                to https://10.0.0.1                           # Ici c'est là ou vous allez mettre les 2 IP VPN de vos serveurs finaux
                to https://10.0.0.2
                lb_policy least_conn                          # Quelques paramètres supplémentaires
                lb_try_duration 5s
                lb_try_interval 250ms

                # Ignorer les certificats auto-signés         # Ici c'est pour ignorer le fait qu'on a pas de certificat HTTPS pour les 2 IP VPN (pas de panique, la connexion se fera tout de même en HTTPS)
                transport http {
                        tls_insecure_skip_verify
                }
        }
}
```

Ensuite on relance le service :

```
sudo caddy reload --config /etc/caddy/Caddyfile 
```

Parallèlement à ça, il faudra vous rendre sur le manager de votre nom de domaine et allouer l'adresse IPv4 et IPv6 du VPS au domaine que vous avez enregistré dans votre configuration Caddy (en l'occurence ici "bitwarden.mondomaine.fr").
On attend quelques dizaines de secondes que les DNS se mettent à jour, et normalement ça fonctionne !

## Debug

J'ai rencontré un bug sur les versions supérieurs à 2025.7.0 de Vaultwarden. Etant donné que j'utilise une BDD MySQL, il peut arriver des bugs et incompatibiltés, et on est typiquement dans le cas.

J'avais cette erreur : 

```
[2026-03-25 22:16:56.111][panic][ERROR] thread 'main' panicked at 'Error running migrations: QueryError(DieselMigrationName { name: "2024-03-06-170000_add_sso_users", version: MigrationVersion("20240306170000") }, DatabaseError(Unknown, "Can't create table vaultwarden_test.sso_users (errno: 150 \"Foreign key constraint is incorrectly formed\")"))': src/db/mod.rs:505
```

Pour la faire courte, une table `sso_users` devait être créée suite à cette mise à jour, et une incompatibilité sur la forme de la table `users` empêchait la création de la table `sso_users`

Pour le debug : 

Backup de la BDD

```
mysqldump -u <user> -p vaultwarden > backup_vaultwarden_prod.sql
```

Suppression des conteneurs Docker existants :

```
sudo docker stop vaultwarden
sudo docker rm vaultwarden
```

Modification dans la BDD :

```
DROP TABLE IF EXISTS sso_users
ALTER TABLE users MODIFY COLUMN uuid VARCHAR(36) NOT NULL;
```

Dans le dossier `/opt/vaultwarden/` où se trouve le `docker-compose.yml` :

```
sudo docker pull vaultwarden/server:latest
sudo docker-compose up -d
```

### Root cause : colonnes uuid/id converties en TEXT au lieu de VARCHAR(36)

En creusant plus loin (rencontré à nouveau en passant de 1.35.8 à 1.36.0, cette fois sur la table `archives` et la colonne `ciphers.uuid`), la vraie cause commune à ces deux bugs est la même : l'outil `sqlite3-to-mysql` utilisé pour la conversion initiale (voir [Transfert de la base de données SQLITE3 vers MySQL](#transfert-de-la-base-de-donnees-sqlite3-vers-mysql)) a converti quasiment toutes les colonnes `uuid` / `*_uuid` / `id` en `TEXT` au lieu de `VARCHAR(36)`/`CHAR(36)` comme le prévoit le schéma officiel de Vaultwarden. Une colonne `TEXT` ne peut porter qu'un index de préfixe (ex: `PRIMARY KEY (uuid(255))`), jamais un index sur sa valeur complète — or une clé étrangère exige un index complet sur la colonne référencée. Résultat : **chaque nouvelle version qui ajoute une clé étrangère vers une colonne uuid encore mal typée** provoque la même erreur (`errno: 150`), sur une table différente à chaque fois.

Cette correction est intégrée directement dans [`scripts/update_vaultwarden.sh`](scripts/update_vaultwarden.sh) (flag `--fix-uuid-columns`, voir la section [Script de mise à jour semi-automatique](#script-de-mise-à-jour-semi-automatique-avec-backup-vérification-et-rollback)) plutôt que dans un script séparé, afin qu'une mise à jour future puisse la déclencher automatiquement dès qu'elle détecte des colonnes uuid/id encore en `TEXT`, sans avoir à redécouvrir le problème table par table à chaque fois.

## Si besoin de downgrade de version

Modifier le docker-compose.yml avec le bon numéro de version du conteneur :

```
text
services:
  vaultwarden:
    image: vaultwarden/server:1.35.0
    # … autres options
```
Puller la nouvelle (en fait ancienne) image.

Dans le dossier où est le docker-compose.yml :
```
sudo docker-compose pull
```

Redémarrer le service

```
docker-compose down
docker-compose up -d
```


# Sécurité

Voici un chapitre concernant la sécurité du serveur mis en place. Etant donné qu'on est sur un serveur hébergeant des mots de passe, ce n'est pas un aspect à prendre à la légère. Ici, on va voir comment :
* Renouveler le certificat HTTPS en cas d'installation sans cluster
* Mettre à jour le conteneur docker Vaultwarden
* Mettre à jour OpenSSH
* Changer le port par défaut de SSH

## Renouvellement du certificat

voir : https://chatgpt.com/share/1a3f13d0-f890-4f5f-be06-d54b5febbcbd _A rerédiger lorsque ça sera de nouveau le moment du renouvellement_

## Mises à jour de Vaultwarden

Il arrive que des nouvelles versions de vaultwarden soient publiées (heureusement), voici la procédure pour les installer.

Commencer par stopper le conteneur vaultwarden déjà en cours d'exécution :

```
sudo docker stop vaultwarden
sudo docker rm vaultwarden
```

_Remplacer `vaultwarden` par le nom du conteneur docker en question qui est visible en tapant la commande `sudo docker ps`_

Installer ensuite la dernière version du conteneur docker :

```
sudo docker pull vaultwarden/server:latest
```

Une fois fini, vous pouvez relancer le conteneur docker avec la commande suivante : 

```
sudo docker run -d --name vaultwarden -e ROCKET_TLS='{certs="/ssl/certs.pem",key="/ssl/key.pem"}' -v /ssl/keys/:/ssl/ -v /vw-data/:/data/ -p 443:80 vaultwarden/server:latest
```

Et voilà, vaultwarden est à jour !

Bien entendu, il est possible d'en faire un script pour ne rien avoir à faire... Vous savez nous les informaticiens, on est des gros flemmards !

```
#!/bin/bash

# Fichier de log
LOG_FILE="/var/log/update_vaultwarden.log"

# Fonction pour écrire dans le log et afficher dans le terminal avec timestamp
log() {
    local message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$timestamp - $message" | tee -a $LOG_FILE
}

log "Début de la mise à jour de Vaultwarden."

# Arrêter et supprimer le conteneur existant
log "Arrêt du conteneur Docker vaultwarden..."
sudo docker stop vaultwarden >> $LOG_FILE 2>&1 | tee -a $LOG_FILE
log "Suppression du conteneur Docker vaultwarden..."
sudo docker rm vaultwarden >> $LOG_FILE 2>&1 | tee -a $LOG_FILE

# Télécharger la dernière version de Vaultwarden
log "Téléchargement de la dernière version de Vaultwarden..."
sudo docker pull vaultwarden/server:latest >> $LOG_FILE 2>&1 | tee -a $LOG_FILE

# Relancer le conteneur avec les paramètres nécessaires
log "Relance du conteneur Vaultwarden..."
sudo docker run -d --name vaultwarden \
    -e ROCKET_TLS='{certs="/ssl/certs.pem",key="/ssl/key.pem"}' \
    -v /ssl/keys/:/ssl/ \
    -v /vw-data/:/data/ \
    -p 443:80 vaultwarden/server:latest >> $LOG_FILE 2>&1 | tee -a $LOG_FILE

log "Opération terminée."
```

Plus qu'à lancer le script, et la mise a jour part ! Bien sur, on peut le mettre dans un cron pour le lancer régulièrement :-)

### Script de mise à jour semi-automatique (avec backup, vérification et rollback)

Suite au bug de migration rencontré en passant de 1.35.8 à 1.36.0 (voir [Debug](#debug)), le script précédent a été complété par [`scripts/update_vaultwarden.sh`](scripts/update_vaultwarden.sh), pensé pour un déploiement `docker-compose`. Contrairement au script ci-dessus, il ne se contente pas de puller `latest` et relancer : il **vérifie avant d'agir** et sait **revenir en arrière** si la mise à jour échoue.

Ce que fait le script, dans l'ordre :

1. **Backup** de la base (`mysqldump` compressé et horodaté) avant toute action, avec purge automatique des backups trop anciens.
2. **Vérification préventive du charset/collation** de la base (`utf8mb4` / `utf8mb4_unicode_ci`). Si un problème est détecté :
   - sans le flag `--fix-collation` : le script **s'arrête immédiatement sans rien modifier** et renvoie vers la procédure de correction du [wiki officiel MariaDB backend](https://github.com/dani-garcia/vaultwarden/wiki/Using-the-MariaDB-%28MySQL%29-Backend#foreign-key-errors-collation-and-charset) ;
   - avec le flag `--fix-collation` : le script affiche les commandes SQL qu'il va exécuter, **demande une confirmation explicite** (`[y/N]`), puis applique lui-même l'`ALTER DATABASE` et les `ALTER TABLE ... CONVERT TO CHARACTER SET` sur toutes les tables, et revérifie que la correction a bien pris avant de poursuivre.
3. **Vérification préventive des colonnes uuid/id encore en TEXT** (résidu de la conversion SQLite → MySQL, cf. [Debug](#debug) — c'est ce qui a bloqué `users.uuid` puis `ciphers.uuid`, une table différente à chaque montée de version). Si un problème est détecté :
   - sans le flag `--fix-uuid-columns` : le script **s'arrête immédiatement sans rien modifier** et liste les colonnes concernées ;
   - avec le flag `--fix-uuid-columns` : le script repère toutes les colonnes `uuid`/`id`/`*_uuid` encore en `TEXT`, ne convertit une colonne que si **100% de ses valeurs non nulles font exactement 36 caractères** (sinon elle est ignorée et signalée, jamais tronquée), reconstruit les index (clé primaire, unique, secondaire) qui portaient un préfixe sur ces colonnes, affiche le plan complet et demande confirmation avant toute exécution.
   - Dans les deux cas, le script ne crée et ne supprime jamais de table lui-même — la création de tables (ex: `archives`, `sso_users`) reste toujours du ressort des migrations internes de Vaultwarden.
4. **Pull** de la version demandée (passée en argument, jamais `latest`, pour rester reproductible) et mise à jour du tag dans `docker-compose.yml` (avec vérification que la substitution a bien pris effet avant de continuer).
5. **Relance** du conteneur (`docker-compose up -d`) — c'est Vaultwarden qui exécute ses propres migrations au démarrage, le script ne crée ni ne modifie aucune table.
6. **Contrôle post-update** : attente du healthcheck du conteneur (affiche les logs du conteneur **en direct dans le même terminal** pendant l'attente, pas besoin d'ouvrir une deuxième session) et scan des logs à la recherche des erreurs de migration connues (`panic`, `Error running migrations`, `QueryError`).
7. **Rollback automatique** si l'étape 5 échoue à démarrer ou si l'étape 6 détecte un problème : le tag précédent est restauré dans `docker-compose.yml` et l'ancienne version est relancée.

**Installation :**

```
cd /opt/vaultwarden
cp /chemin/vers/scripts/update_vaultwarden.sh .
cp /chemin/vers/scripts/.env.example ./.env
nano .env   # renseigner COMPOSE_DIR, identifiants DB, chemins de backup, etc.
chmod +x update_vaultwarden.sh
```

Ce même fichier `.env` est partagé par `check_replication.sh` et `reconcile_split_brain.sh` (voir plus loin) : chaque script ne lit que les variables qui le concernent, un seul fichier à maintenir par serveur.

**Utilisation :**

```
./update_vaultwarden.sh 1.36.0
```

Ou, si le charset/collation et/ou les colonnes uuid/id doivent être corrigés automatiquement (avec confirmation avant toute modification) :

```
./update_vaultwarden.sh 1.36.0 --fix-collation --fix-uuid-columns
```

En cas de doute sur l'état de la base, il ne coûte rien de toujours passer les deux flags : chaque vérification ne déclenche sa correction (et sa confirmation) que si un problème est réellement détecté, sinon le script log simplement "OK" et continue.

/!\ Le fichier `.env` contient les identifiants de la base et n'est jamais commité (voir `.gitignore`).

/!\ Limite du rollback : si une migration a déjà modifié une partie du schéma avant d'échouer plus loin, revenir à l'ancienne image Docker ne annule pas forcément ces changements de schéma. Le backup effectué à l'étape 1 reste donc la garantie ultime pour restaurer un état cohérent si besoin.

## Upgrade OpenSSH

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

Voilà, openssh est à jour et la vulnérabilité est patchée !

## Changer le port par défaut de SSH

Il peut arriver que certaines personnes tente de brute force votre serveur (étant donné que c'est un serveur visible sur internet), donc pour remédier à ça on peut remplacer le port par défaut qu'utilise SSH.

Ouvrir le fichier de configuration SSH avec un éditeur de texte (par exemple nano):

```
sudo nano /etc/ssh/sshd_config
```

Remplacer la ligne ```# Port 22``` par la ligne suivante (en enlevant le # et en changeant le port) :
```
Port 37845
```

Personnellement je n'utilise pas de pare feu, mais si vous en utilisez il faut laisser passer ce port :

Avec UFW :

```
sudo ufw allow 37845/tcp
sudo ufw deny 22/tcp # à faire après avoir testé que tout fonctionne correctement
sudo ufw status
```

Avec IPTABLES : 

```
sudo iptables -A INPUT -p tcp --dport 37845 -j ACCEPT
sudo apt-get install iptables-persistent
sudo netfilter-persistent save
```

On redémarre SSH :

```
sudo systemctl restart ssh
```

Personnellement, j'ai aussi dû supprimer le service ```ssh.socket``` qui posait problème et qui m'empêchait de changer le port de connexion :

```
sudo systemctl disable ssh.socket
sudo systemctl stop ssh.socket
sudo systemctl restart ssh
```

Tester la connexion SSH sur le nouveau port
```
ssh -p 37845 julabuche@server
```

Une fois SSH redémarré, on peut vérifier que le serveur SSH écoute bien sur le nouveau port :

```
sudo ss -tulnp | grep ssh
tcp   LISTEN   0        128                *:37845             *:*    users:(("sshd",pid=1234,fd=3))
```

Si on veut bien faire, on peut désactiver également le passage du port 22 via les firewall :

Avec UFW : 

```
sudo ufw deny 22/tcp
```

Et pour vérifier : 
```
sudo ufw status
```

Avec IPTABLES :

```
sudo iptables -A INPUT -p tcp --dport 22 -j DROP
```

Et pour vérifier
```
sudo iptables -L -n -v
```
Vous devriez voir apparaitre ceci :
```
    0     0 ACCEPT     6    --  *      *       0.0.0.0/0            0.0.0.0/0            tcp dpt:37845
   10   584 DROP       6    --  *      *       0.0.0.0/0            0.0.0.0/0            tcp dpt:22
```
