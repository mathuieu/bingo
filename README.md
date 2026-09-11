# Bingo entre amis

Une application web de bingo en Python et Flask.

Les mots sont chargés depuis `mots.txt`. Chaque joueur peut créer une grille avec un numéro choisi, puis la retrouver plus tard. Les cases sont interactives et deviennent vertes lorsqu'elles sont cochées. Une animation de cotillon se déclenche lorsque la grille est complète.

## Fonctionnalités

- Grilles aléatoires de 3 x 3.
- Numéro de grille choisi par le joueur.
- Stockage des grilles dans SQLite.
- Recherche d'une grille par son numéro.
- Cases cliquables avec animation de victoire.
- Page d'administration sur `/admin`.
- Ajout et suppression de mots.
- Réinitialisation des grilles.
- Image Docker publiée dans Azure Container Registry.
- Déploiement possible dans Azure Container Instances.

## Démarrage local

Installer les dépendances :

```powershell
python -m pip install -r requirements.txt
```

Définir le mot de passe privé avant de lancer l'application :

```powershell
$env:APP_PASSWORD = "mon-mot-de-passe"
$env:SECRET_KEY = "une-cle-secrete-longue-et-aleatoire"
```

Ces valeurs restent dans l'environnement local et ne doivent pas être ajoutées à GitHub. Chaque clone du projet peut choisir son propre mot de passe.

Lancer l'application :

```powershell
python app.py
```

Ouvrir ensuite :

- Application : http://127.0.0.1:5000
- Administration : http://127.0.0.1:5000/admin

Le serveur local utilise le port 5000 par défaut. Le port peut être changé avec la variable `PORT`.

L'application demande le mot de passe sur `/connexion` avant d'autoriser l'accès au bingo et à l'administration. La session est supprimée avec **Se déconnecter**.

## Liste des mots

Ajouter un mot ou une expression dans `mots.txt`, un élément par ligne :

```text
Apéro
Général 5 étoiles
Départ en suisse
```

Les espaces à l'intérieur d'une expression sont conservés.

## Stockage

Les grilles sont stockées dans `grilles.db` avec SQLite.

Pour utiliser un autre emplacement :

```powershell
$env:DB_PATH = "C:\chemin\vers\grilles.db"
python app.py
```

Dans Docker, il est recommandé de monter un volume sur `/data` :

```powershell
docker volume create bingo-data
```

## Docker

Construire l'image :

```powershell
docker build -t bingo:local .
```

Lancer l'application sur le port 80 :

```powershell
docker run -d `
    --name bingo `
    -p 5000:80 `
    -e PORT=80 `
    -e DB_PATH=/data/grilles.db `
    -v bingo-data:/data `
    bingo:local
```

L'application est alors disponible sur http://localhost:5000.

Arrêter le conteneur :

```powershell
docker rm -f bingo
```

## Publication dans ACR

Le script `install.ps1` automatise la construction et la publication dans :

```text
acrdemorepo.azurecr.io/bingo
```

Publier l'image `latest` :

```powershell
.\install.ps1
```

Publier une version identifiée :

```powershell
.\install.ps1 -Tag v1.1
```

Tester aussi l'image localement :

```powershell
.\install.ps1 -Tester
```

## Déploiement Azure Container Instances

Le script peut publier l'image puis recréer l'ACI :

```powershell
.\install.ps1 `
    -Tag latest `
    -DeployAci `
    -ResourceGroup "RG_bingo" `
    -Location "westeurope" `
    -AciName "bingo-aci" `
    -DnsNameLabel "bingo"
```

L'application est exposée en HTTP sur le port 80 :

```text
http://bingo.westeurope.azurecontainer.io
```

Vérifier l'état de l'ACI :

```powershell
az container show `
    --resource-group "RG_bingo" `
    --name "bingo-aci" `
    --query "{state:instanceView.state, fqdn:ipAddress.fqdn, ip:ipAddress.ip}" `
    --output json
```

> L'ACI utilise actuellement un stockage local éphémère pour SQLite. Pour conserver les grilles après la suppression ou le remplacement de l'ACI, il faudra monter un partage Azure Files ou utiliser une base de données managée.

## Structure du projet

```text
app.py                 Application Flask et routes web
mots.py                Lecture et gestion de la liste des mots
grilles.py             Génération et stockage SQLite des grilles
mots.txt               Liste des mots disponibles
templates/index.html   Interface principale du bingo
templates/admin.html   Interface d'administration
Dockerfile             Construction de l'image Docker
install.ps1            Publication ACR et déploiement ACI
requirements.txt       Dépendances Python
```

## Licence

Projet personnel pour jouer au bingo entre amis.
