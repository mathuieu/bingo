param(
	# Tag de l'image publiée dans ACR. Exemple : -Tag v1.1
	[string]$Tag = "latest",

	# Lance aussi un conteneur local et vérifie la page d'accueil.
	[switch]$Tester,

	# Crée ou met à jour une Azure Container Instance après le push.
	[switch]$DeployAci,

	# Crée ou met à jour une Azure Web App depuis le dépôt GitHub.
	[switch]$DeployWebApp,

	# Paramètres nécessaires à la création de l'ACI.
	[string]$ResourceGroup,
	[string]$Location = "westeurope",
	[string]$AciName = "bingo-aci",
	[string]$DnsNameLabel,
	[string]$WebAppResourceGroup = "RG_demo_sudoku",
	[string]$WebAppPlan = "B1-plan-multi",
	[string]$WebAppName = "bingo-webapp",
	[string]$GitHubRepository = "https://github.com/mathuieu/bingo",
	[string]$GitHubBranch = "main"
)

$ErrorActionPreference = "Stop"

# -----------------------------------------------------------------------------
# Configuration du registre et de l'image
# -----------------------------------------------------------------------------
$Registry = "acrdemorepo.azurecr.io"
$Repository = "bingo"
$Image = "$Registry/$Repository`:$Tag"

Write-Host "Image cible : $Image" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# Vérifications locales
# -----------------------------------------------------------------------------
# Le script doit être exécuté depuis le dossier qui contient le Dockerfile.
if (-not (Test-Path "Dockerfile")) {
	throw "Dockerfile introuvable. Lance install.ps1 depuis le dossier du projet."
}

# Vérifie que Docker répond. Docker Desktop doit être démarré sous Windows.
docker info | Out-Null
if ($LASTEXITCODE -ne 0) {
	throw "Le moteur Docker ne répond pas. Démarre Docker Desktop puis relance le script."
}

# Vérifie que l'Azure CLI est installée.
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
	throw "Azure CLI introuvable. Installe Azure CLI avant de continuer."
}

# -----------------------------------------------------------------------------
# Authentification Azure et connexion à ACR
# -----------------------------------------------------------------------------
# Si la session Azure a expiré, cette commande ouvre le parcours de connexion.
az account show --output none
if ($LASTEXITCODE -ne 0) {
	az login --scope https://management.core.windows.net//.default
}

# Se connecte à l'Azure Container Registry.
az acr login --name acrdemorepo

# -----------------------------------------------------------------------------
# Construction et publication de l'image
# -----------------------------------------------------------------------------
# Construit l'image depuis le Dockerfile présent dans le dossier courant.
docker build -t "bingo:local" .

# Ajoute le nom complet du registre à l'image locale.
docker tag "bingo:local" $Image

# Publie l'image dans ACR.
docker push $Image

Write-Host "Image publiée : $Image" -ForegroundColor Green

# -----------------------------------------------------------------------------
# Déploiement optionnel dans Azure App Service (Web App)
# -----------------------------------------------------------------------------
if ($DeployWebApp) {
	if ([string]::IsNullOrWhiteSpace($env:APP_PASSWORD)) {
		throw "La variable d'environnement APP_PASSWORD est obligatoire avec -DeployWebApp."
	}
	if ([string]::IsNullOrWhiteSpace($env:SECRET_KEY)) {
		throw "La variable d'environnement SECRET_KEY est obligatoire avec -DeployWebApp."
	}

	# Vérifie que le groupe de ressources et le plan Linux existent.
	az group show --name $WebAppResourceGroup --output none
	if ($LASTEXITCODE -ne 0) {
		throw "Le groupe de ressources '$WebAppResourceGroup' est introuvable."
	}

	az appservice plan show `
		--resource-group $WebAppResourceGroup `
		--name $WebAppPlan `
		--output none
	if ($LASTEXITCODE -ne 0) {
		throw "Le plan App Service '$WebAppPlan' est introuvable."
	}

	# Crée la Web App si elle n'existe pas encore. La liste évite qu'une
	# erreur native de 'az webapp show' arrête PowerShell pour un nom absent.
	$WebAppCount = az webapp list `
		--resource-group $WebAppResourceGroup `
		--query "[?name=='$WebAppName'] | length(@)" `
		--output tsv
	if ($WebAppCount -eq "0") {
		az webapp create `
			--resource-group $WebAppResourceGroup `
			--plan $WebAppPlan `
			--name $WebAppName `
			--runtime "PYTHON:3.14" `
			--output none
	}

	# Active le build Python côté App Service et utilise Gunicorn comme serveur.
	az webapp config appsettings set `
		--resource-group $WebAppResourceGroup `
		--name $WebAppName `
		--settings SCM_DO_BUILD_DURING_DEPLOYMENT=1 PORT=8000 APP_PASSWORD=$env:APP_PASSWORD SECRET_KEY=$env:SECRET_KEY `
		--output none
	az webapp config set `
		--resource-group $WebAppResourceGroup `
		--name $WebAppName `
		--startup-file "gunicorn --bind=0.0.0.0:`$PORT app:app" `
		--output none

	# Configure GitHub comme source du code. L'intégration manuelle ne stocke
	# aucun jeton GitHub dans ce script ; synchroniser ensuite avec 'az webapp
	# deployment source sync' après chaque push, ou remplacer par une GitHub Action.
	az webapp deployment source config `
		--resource-group $WebAppResourceGroup `
		--name $WebAppName `
		--repo-url $GitHubRepository `
		--branch $GitHubBranch `
		--manual-integration `
		--output none

	$WebAppHost = az webapp show `
		--resource-group $WebAppResourceGroup `
		--name $WebAppName `
		--query defaultHostName `
		--output tsv
	Write-Host "Web App créée : https://$WebAppHost" -ForegroundColor Green
	Write-Host "Synchroniser le dépôt : az webapp deployment source sync --resource-group $WebAppResourceGroup --name $WebAppName" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
# Déploiement optionnel dans Azure Container Instances (ACI)
# -----------------------------------------------------------------------------
if ($DeployAci) {
	if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
		throw "-ResourceGroup est obligatoire avec -DeployAci."
	}
	if ([string]::IsNullOrWhiteSpace($DnsNameLabel)) {
		throw "-DnsNameLabel est obligatoire avec -DeployAci."
	}

	# Vérifie que le groupe de ressources existe.
	az group show --name $ResourceGroup --output none
	if ($LASTEXITCODE -ne 0) {
		throw "Le groupe de ressources '$ResourceGroup' est introuvable."
	}

	# ACI doit pouvoir s'authentifier auprès de l'ACR privé.
	# Cette commande utilise les identifiants administrateur de l'ACR.
	$AcrUsername = az acr credential show `
		--name acrdemorepo `
		--query username `
		--output tsv
	$AcrPassword = az acr credential show `
		--name acrdemorepo `
		--query "passwords[0].value" `
		--output tsv

	if ([string]::IsNullOrWhiteSpace($AcrUsername) -or [string]::IsNullOrWhiteSpace($AcrPassword)) {
		throw "Impossible de récupérer les identifiants administrateur de l'ACR."
	}

	# Supprime l'ancienne instance si elle existe, puis la recrée avec la nouvelle image.
	# Le nom DNS doit être unique dans la région Azure choisie.
	az container delete `
		--resource-group $ResourceGroup `
		--name $AciName `
		--yes `
		--output none 2>$null

	az container create `
		--resource-group $ResourceGroup `
		--name $AciName `
		--image $Image `
		--registry-login-server $Registry `
		--registry-username $AcrUsername `
		--registry-password $AcrPassword `
		--dns-name-label $DnsNameLabel `
		--ports 80 `
		--protocol TCP `
		--os-type Linux `
		--cpu 1 `
		--memory 1.5 `
		--restart-policy Always `
		--location $Location `
		--environment-variables PORT=80 DB_PATH=/app/grilles.db `
		--output none

	$AciFqdn = az container show `
		--resource-group $ResourceGroup `
		--name $AciName `
		--query "ipAddress.fqdn" `
		--output tsv
	$AciIp = az container show `
		--resource-group $ResourceGroup `
		--name $AciName `
		--query "ipAddress.ip" `
		--output tsv
	$AciDnsUrl = "http://$AciFqdn"
	$AciIpUrl = "http://$AciIp"
	Write-Host "ACI créée (DNS) : $AciDnsUrl" -ForegroundColor Green
	Write-Host "ACI créée (IP)  : $AciIpUrl" -ForegroundColor Green
	Write-Host "Attention : grilles.db est éphémère sans partage Azure Files." -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
# Test local optionnel
# -----------------------------------------------------------------------------
if ($Tester) {
	$ContainerName = "bingo-test"
	$VolumeName = "bingo-test-data"
	$Port = 5001

	# Supprime un ancien test s'il existe, sans arrêter le script s'il est absent.
	docker rm -f $ContainerName 2>$null
	docker volume rm $VolumeName 2>$null
	docker volume create $VolumeName | Out-Null

	# Le volume conserve grilles.db lorsque le conteneur est recréé.
	docker run -d `
		--name $ContainerName `
		-p "${Port}:80" `
		-e "PORT=80" `
		-e "DB_PATH=/data/grilles.db" `
		-v "${VolumeName}:/data" `
		"bingo:local" | Out-Null

	# Vérifie que Flask répond sur le port publié.
	$Code = curl.exe -s -o NUL -w "%{http_code}" "http://127.0.0.1:$Port/"
	if ($Code -ne "200") {
		throw "Le conteneur ne répond pas correctement (HTTP $Code)."
	}

	Write-Host "Test local réussi : http://127.0.0.1:$Port" -ForegroundColor Green
	Write-Host "Pour arrêter le test : docker rm -f $ContainerName" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
# Exemples de commandes pour les prochaines versions
# -----------------------------------------------------------------------------
# Publier la version courante avec le tag latest :
#   .\install.ps1
#
# Publier une version identifiée :
#   .\install.ps1 -Tag v1.1
#
# Construire, publier et lancer le test local :
#   .\install.ps1 -Tester
#
# Publier puis déployer depuis GitHub dans Azure Web App :
#   $env:APP_PASSWORD = "mot-de-passe-prive"
#   $env:SECRET_KEY = "cle-secrete-longue-et-aleatoire"
#   .\install.ps1 `
#       -DeployWebApp `
#       -WebAppResourceGroup "RG_demo_sudoku" `
#       -WebAppPlan "B1-plan-multi" `
#       -WebAppName "bingo-webapp" `
#       -GitHubRepository "https://github.com/mathuieu/bingo" `
#       -GitHubBranch "main"
#
# Synchroniser les prochains commits GitHub :
#   az webapp deployment source sync `
#       --resource-group "RG_demo_sudoku" `
#       --name "bingo-webapp"
#
# Créer ou mettre à jour une Azure Container Instance :
#   .\install.ps1 `
#       -Tag latest `
#       -DeployAci `
#       -ResourceGroup "rg-bingo" `
#       -Location "westeurope" `
#       -AciName "bingo-aci" `
#       -DnsNameLabel "bingo-demo-mathi"
#
# Vérifier l'ACI créée :
#   az container show `
#       --resource-group "rg-bingo" `
#       --name "bingo-aci" `
#       --query "ipAddress.fqdn" `
#       --output tsv
#
# Lancer directement une image publiée avec une base persistante :
#   docker run -d `
#       --name bingo `
#       -p 80:80 `
#       -e PORT=80 `
#       -e DB_PATH=/data/grilles.db `
#       -v bingo-data:/data `
#       acrdemorepo.azurecr.io/bingo:latest
#
# Arrêter et supprimer ce conteneur :
#   docker rm -f bingo