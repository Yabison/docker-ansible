# Makefile - Gestion Docker Ansible / Semaphore (Yabison style)
# Inspiré du Makefile fourni + adaptations UID/GID dynamiques

# Variables principales
IMAGE_NAME      ?= yabison/ansible-semaphore
VERSION         ?= dev-$(shell date +%Y%m%d-%H%M)
BUILD_DATE      := $(shell date -u +'%Y-%m-%dT%H:%M:%SZ')
VCS_REF         := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
VCS_URL         := $(shell git config --get remote.origin.url 2>/dev/null || echo "unknown")

# UID/GID de l'utilisateur courant (pour volumes bindés)
DEVOPS_UID      := 1000 #$(shell id -u)
DEVOPS_GID      := 1000 #$(shell id -g)

# Chemins des répertoires
DATA_HOSTED         := ./data-hosted
SECRETS_DIR         := $(DATA_HOSTED)/.secrets
VAULTS_DIR          := $(SECRETS_DIR)/ansible-vaults
CLEAR_PASS_DIR      := $(SECRETS_DIR)/docker-cleartext
PASSBOLT_VAULT_FILENAME := passbolt.vault.yml
PASSBOLT_VAULT_FILE := $(VAULTS_DIR)/$(PASSBOLT_VAULT_FILENAME)
COMPOSE_FILE        ?= docker-compose.yml
PASSWORD_FILE       ?= $(CLEAR_PASS_DIR)/ansible_vault_password
DOCKERFILE      ?= docker/Dockerfile
#ALPINE_VERSION  ?= $(shell grep -m1 'ARG ALPINE_VERSION=' $(DOCKERFILE) | cut -d= -f2)
PIN_SCRIPT      ?= docker/scripts/pin-apk-versions.py
# Service docker-compose principal
SERVICE        ?= ansible


# Couleurs
RED    := \033[0;31m
GREEN  := \033[0;32m
YELLOW := \033[1;33m
CYAN   := \033[0;36m
NC     := \033[0m

# Capturé AVANT le -include .env, donc = "Makefile" uniquement
MAKEFILE_SELF := $(lastword $(MAKEFILE_LIST))

# recupere les variables du .env
-include .env
export

.PHONY: help build build-base up up-build rebuild down logs shell clean push scan test audit security-report get-password save-password remove-password init-dirs create-passbolt-vault pin-versions test-pin hadolint

help: ## Afficher cette aide
	@echo "$(CYAN)Commandes disponibles :$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_SELF) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-18s$(NC) %s\n", $$1, $$2}'

# ────────────────────────────────────────────────
# Initialisation des répertoires
# ────────────────────────────────────────────────
init-dirs: ## Créer tous les répertoires nécessaires (ansible, secrets, crontab)
	@echo "$(GREEN)Création des répertoires data-hosted...$(NC)"
	@mkdir -p $(DATA_HOSTED)/ansible
	@mkdir -p $(DATA_HOSTED)/.ansible
	@mkdir -p ./docker/config
	@mkdir -p $(VAULTS_DIR)
	@mkdir -p $(CLEAR_PASS_DIR)
	@mkdir -p $(DATA_HOSTED)/.secrets
	@echo "$(GREEN)✅ Répertoires créés :$(NC)"
	@echo "  - $(DATA_HOSTED)/ansible/"
	@echo "  - $(DATA_HOSTED)/.ansible/"
	@echo "  - ./docker/config/"
	@echo "  - $(VAULTS_DIR)/"
	@echo "  - $(CLEAR_PASS_DIR)/"

# ────────────────────────────────────────────────
# Password management (vault)
# ────────────────────────────────────────────────# Fonction pour obtenir le mot de passe (depuis fichier ou saisie)
ansible-vault-password-get: ## get ansible vault password
	@if [ -f $(PASSWORD_FILE) ]; then \
		cat $(PASSWORD_FILE); \
	else \
		echo "🔐 Fichier $(PASSWORD_FILE) non trouvé"; \
		echo -n "Entrez le mot de passe Ansible Vault initial: " >&2; \
		read -s VAULT_PASS && echo "$$VAULT_PASS"; \
	fi
ansible-vault-password-save: ## save ansible vault password
	@echo "⚠️  ATTENTION : Sauvegarder le mot de passe en clair est risqué !"
	@echo -n "Êtes-vous sûr ? (yes/no): " && read CONFIRM && \
	if [ "$$CONFIRM" = "yes" ]; then \
		echo -n "Entrez le mot de passe Ansible Vault: "; \
		read -s VAULT_PASS && \
		echo "$$VAULT_PASS" > $(PASSWORD_FILE) && \
		chmod 600 $(PASSWORD_FILE) && \
		echo "" && \
		echo "✅ Mot de passe sauvegardé dans $(PASSWORD_FILE) (chmod 600)"; \
	else \
		echo "❌ Opération annulée"; \
	fi

# Supprimer le fichier de mot de passe
ansible-vault-password-remove: ## remove ansible vault password
	@if [ -f $(PASSWORD_FILE) ]; then \
		rm -f $(PASSWORD_FILE) && \
		echo "✅ Fichier $(PASSWORD_FILE) supprimé"; \
	else \
		echo "ℹ️  Aucun fichier $(PASSWORD_FILE) à supprimer"; \
	fi

# ────────────────────────────────────────────────
# Passbolt Vault Management
# ────────────────────────────────────────────────
create-passbolt-vault-docker: init-dirs get-private-key
	@echo "$(CYAN)[1/3] Saisie Passbolt...$(NC)"
	@printf "Passbolt URL [https://passbolt.yabison.com](https://passbolt.yabison.com): " && \
	read -r PASSBOLT_URL ; \
	if [ -z "$$PASSBOLT_URL" ]; then \
	  PASSBOLT_URL="https://passbolt.yabison.com" ; \
	fi ; \
	export PASSBOLT_URL && \
	printf "Passbolt Password: " && \
	read -s PASSBOLT_PASSWORD && echo && \
	export PASSBOLT_PASSWORD && \
	echo "$(CYAN)[2/3] Création YAML...$(NC)" && \
	printf "passbolt_url: \"%s\"\n" "$$PASSBOLT_URL" > $(PASSBOLT_VAULT_FILE) && \
	printf "passbolt_private_key: |\n" >> $(PASSBOLT_VAULT_FILE) && \
	sed 's/^/  /' /tmp/passbolt_key.tmp >> $(PASSBOLT_VAULT_FILE) && \
	printf "\npassbolt_password: \"%s\"\n" "$$PASSBOLT_PASSWORD" >> $(PASSBOLT_VAULT_FILE) && \
	chmod 600 $(PASSBOLT_VAULT_FILE)
	@echo "$(CYAN)[3/3] Cryptage via docker ...$(NC)" 
	$(MAKE) vault-encrypt-docker
	@rm -f /tmp/passbolt_key.tmp
	@echo "$(GREEN)✅ TERMINÉ$(NC)"

get-private-key:
	@echo "$(YELLOW)🔑 Clé privée PGP (fichier ./passbolt_private.txt) :$(NC)" 
	@read KEY_FILE ; \
	if [ -z "$$KEY_FILE" ]; then \
	  KEY_FILE="./passbolt_private.txt" ; \
	fi ; \
	if [ -f "$$KEY_FILE" ]; then \
		cp "$$KEY_FILE" /tmp/passbolt_key.tmp ; \
		echo "$(GREEN)✅ Fichier copié$(NC)" ; \
	else \
		echo "$(RED)❌ Fichier NON trouvé: $$KEY_FILE$(NC)" ; \
		ls -la . | grep -i passbolt || true ; \
		exit 1 ; \
	fi

# ────────────────────────────────────────────────
# Cryptage via Docker Compose
# ────────────────────────────────────────────────
vault-encrypt-docker: init-dirs ## Crypter un fichier via Docker Compose (ANSIBLE_VAULT_PASSWORD auto)
	@echo "$(CYAN)Cryptage via Docker Compose...$(NC)"
	@if [ ! -f "$(PASSWORD_FILE)" ]; then \
		echo "$(RED)❌ Fichier $(PASSWORD_FILE) requis$(NC)"; \
		echo "→ make password-save"; \
		exit 1; \
	fi
	@ANSIBLE_VAULT_PASSWORD=$$(cat $(PASSWORD_FILE)) \
	DEVOPS_UID=$(DEVOPS_UID) DEVOPS_GID=$(DEVOPS_GID) \
	docker compose -f $(COMPOSE_FILE) run --rm  -v $(VAULTS_DIR):/vaults  $(SERVICE) \
	ansible-vault encrypt /vaults/$(PASSBOLT_VAULT_FILENAME) 

vault-decrypt-docker: ## Décrypter via Docker Compose
	@echo "$(CYAN)Décryptage via Docker Compose...$(NC)"
	@if [ ! -f "$(PASSWORD_FILE)" ]; then \
		echo "$(RED)❌ Fichier $(PASSWORD_FILE) requis$(NC)"; \
		exit 1; \
	fi
	@ANSIBLE_VAULT_PASSWORD=$$(cat $(PASSWORD_FILE)) \
	DEVOPS_UID=$(DEVOPS_UID) DEVOPS_GID=$(DEVOPS_GID) \
	docker compose -f $(COMPOSE_FILE) run --rm -v $(VAULTS_DIR):/vaults  $(SERVICE) \
	ansible-vault decrypt /vaults/$(PASSBOLT_VAULT_FILENAME)

vault-view-docker: ## Voir contenu vault via Docker (sans décrypter)
	@echo "$(CYAN)Affichage vault via Docker Compose...$(NC)"
	@ANSIBLE_VAULT_PASSWORD=$$(cat $(PASSWORD_FILE)) \
	DEVOPS_UID=$(DEVOPS_UID) DEVOPS_GID=$(DEVOPS_GID) \
	docker compose -f $(COMPOSE_FILE) run --rm -v $(VAULTS_DIR):/vaults $(SERVICE) \
	ansible-vault view /vaults/$(PASSBOLT_VAULT_FILENAME)

# ────────────────────────────────────────────────
# Build
# ────────────────────────────────────────────────
build: ## Construire l'image principale
	@echo "$(GREEN)Build $(IMAGE_NAME):$(VERSION)  [UID=$(DEVOPS_UID) GID=$(DEVOPS_GID)]$(NC)"
	DEVOPS_UID=$(DEVOPS_UID) DEVOPS_GID=$(DEVOPS_GID) \
	docker compose -f $(COMPOSE_FILE) build 

build-nocache: ## Construire l'image principale no cache
	@echo "$(GREEN)Build $(IMAGE_NAME):$(VERSION)  [UID=$(DEVOPS_UID) GID=$(DEVOPS_GID)]$(NC)"
	DEVOPS_UID=$(DEVOPS_UID) DEVOPS_GID=$(DEVOPS_GID) \
	docker compose -f $(COMPOSE_FILE) build --no-cache

# ────────────────────────────────────────────────
# Lancement
# ────────────────────────────────────────────────
up: init-dirs ## Lancer docker compose (détaché)
	@echo "$(GREEN)Lancement docker compose...$(NC)"
	@echo "🔐 Démarrage du container sécurisé..."
	@ANSIBLE_VAULT_PASSWORD=$$($(MAKE) -s ansible-vault-password-get ) \
	DEVOPS_UID=$(DEVOPS_UID) DEVOPS_GID=$(DEVOPS_GID) \
	docker compose -f $(COMPOSE_FILE) up -d

up-build: ## Build + lancer
	$(MAKE) build
	$(MAKE) up

up-foreground: init-dirs # Lancer en foreground (logs directs)
	@echo "🔐 Démarrage du container sécurisé..."
	@ANSIBLE_VAULT_PASSWORD=$$($(MAKE) -s ansible-vault-password-get) \
	DEVOPS_UID=$(DEVOPS_UID) DEVOPS_GID=$(DEVOPS_GID) \
	docker compose -f $(COMPOSE_FILE) up --build

rebuild: down build up ## Tout arrêter → rebuild → relancer

restart: down  up ## Tout arrêter → relancer
down: ## Arrêter et supprimer les conteneurs
	docker compose -f $(COMPOSE_FILE) down

stop: ## Juste arrêter (sans rm)
	docker compose -f $(COMPOSE_FILE) stop

logs: ## Suivre les logs
	docker compose -f $(COMPOSE_FILE) logs -f $(SERVICE)

ps: ## État des conteneurs
	docker compose -f $(COMPOSE_FILE) ps

# ────────────────────────────────────────────────
# Shell & Exec
# ────────────────────────────────────────────────
exec: ## Exec interactif dans le conteneur
	DEVOPS_UID=$(DEVOPS_UID) DEVOPS_GID=$(DEVOPS_GID) \
	docker compose -f $(COMPOSE_FILE) exec -it $(SERVICE) bash

shell: ## Shell interactif dans le conteneur
	DEVOPS_UID=$(DEVOPS_UID) DEVOPS_GID=$(DEVOPS_GID) \
	docker compose -f $(COMPOSE_FILE) run --rm $(SERVICE) bash

exec-%: ## Exécuter une commande (ex: make exec-ansible --version)
	DEVOPS_UID=$(DEVOPS_UID) DEVOPS_GID=$(DEVOPS_GID) \
	docker compose -f $(COMPOSE_FILE) run --rm $(SERVICE) $(*:exec-%=%)

# ────────────────────────────────────────────────
# Sécurité & Audit
# ────────────────────────────────────────────────
scan: ## Scanner vulnérabilités (trivy + docker scout si dispo)
	@echo "$(YELLOW)Scan sécurité $(IMAGE_NAME):$(VERSION)$(NC)"
	@command -v trivy >/dev/null 2>&1 && trivy image --severity HIGH,CRITICAL $(IMAGE_NAME):$(VERSION) || echo "$(RED)Trivy absent$(NC)"
	@docker scout cves $(IMAGE_NAME):$(VERSION) 2>/dev/null || echo "$(YELLOW)Docker Scout non disponible$(NC)"

test: ## Tests rapides via docker compose (run --rm)
	@echo "$(CYAN)Tests de base via docker compose:$(NC)"
	
	#@echo "1. Utilisateur non-root"
	#@docker compose -f $(COMPOSE_FILE) run --rm $(SERVICE) whoami | grep -q devops && \
  #		echo "$(GREEN)✓ devops$(NC)" || echo "$(RED)✗ utilisateur incorrect$(NC)"
	
	@echo "2. Ansible présent"
	@docker compose -f $(COMPOSE_FILE) run --rm $(SERVICE) ansible --version >/dev/null 2>&1 && \
		echo "$(GREEN)✓$(NC)" || echo "$(RED)✗ Ansible absent ou non exécutable$(NC)"
	
	@echo "3. Python présent"
	@docker compose -f $(COMPOSE_FILE) run --rm $(SERVICE) python3 --version >/dev/null 2>&1 && \
		echo "$(GREEN)✓$(NC)" || echo "$(RED)✗ Python absent$(NC)"
	
	@echo "$(CYAN)Tous les tests terminés$(NC)"

audit: scan test ## Audit rapide (scan + tests)

security-report: ## Générer un petit rapport texte
	@echo "Rapport sécurité - $(BUILD_DATE)" > security-report.txt
	@echo "Image: $(IMAGE_NAME):$(VERSION)" >> security-report.txt
	@echo "VCS: $(VCS_REF)" >> security-report.txt
	@echo "\n=== Trivy ===" >> security-report.txt
	@trivy image --severity HIGH,CRITICAL $(IMAGE_NAME):$(VERSION) >> security-report.txt 2>&1 || echo "Trivy absent" >> security-report.txt
	@echo "\n=== whoami ===" >> security-report.txt
	@docker run --rm $(IMAGE_NAME):$(VERSION) whoami >> security-report.txt
	@echo "$(GREEN)Rapport créé : security-report.txt$(NC)"
# ────────────────────────────────────────────────
# APK Pinning (hadolint DL3018)
# ────────────────────────────────────────────────
pin-versions: ## Épingle les versions APK dans le Dockerfile (résolution live via pkgs.alpinelinux.org)
	@echo "$(CYAN)📌 Détection Alpine version : $(ALPINE_VERSION)$(NC)"
	@if [ ! -f "$(PIN_SCRIPT)" ]; then \
		echo "$(RED)❌ Script introuvable : $(PIN_SCRIPT)$(NC)"; \
		echo "   → Téléchargez-le depuis le projet ou lancez : make renovate-install"; \
		exit 1; \
	fi
	@python3 $(PIN_SCRIPT) --alpine-version $(ALPINE_VERSION) $(DOCKERFILE)
	@echo "$(GREEN)✅ Terminé. Lancez 'make hadolint' pour vérifier.$(NC)"

pin-versions-update: ## [MAJ] Met à jour les versions APK déjà épinglées
	@echo "$(CYAN)🔄 Mise à jour APK — Alpine $(ALPINE_VERSION)$(NC)"
	@python3 $(PIN_SCRIPT) --alpine-version $(ALPINE_VERSION) --update $(DOCKERFILE)
	@echo "$(GREEN)✅ Terminé. Lancez 'make hadolint' pour vérifier.$(NC)"

pin-versions-dry: ## Simulation d'épinglage APK (sans modification)
	@echo "$(CYAN)🔎 Dry-run PIN — aucun fichier modifié$(NC)"
	@python3 $(PIN_SCRIPT) --alpine-version $(ALPINE_VERSION) --dry-run $(DOCKERFILE)

pin-versions-update-dry: ## Simulation de mise à jour APK (sans modification)
	@echo "$(CYAN)🔎 Dry-run UPDATE — aucun fichier modifié$(NC)"
	@python3 $(PIN_SCRIPT) --alpine-version $(ALPINE_VERSION) --update --dry-run $(DOCKERFILE)

hadolint: ## Lint du Dockerfile
	docker run --rm -i hadolint/hadolint:latest-alpine < $(DOCKERFILE)

# ────────────────────────────────────────────────
# Nettoyage & Push
# ────────────────────────────────────────────────
clean: ## Nettoyage conteneurs / images locales
	docker compose -f $(COMPOSE_FILE) down -v --remove-orphans
	docker rmi $(IMAGE_NAME):$(VERSION) 2>/dev/null || true
	docker rmi $(IMAGE_NAME):latest 2>/dev/null || true
	docker system prune -f

push: ## Pousser vers registry (confirmation)
	@echo "$(YELLOW)Vous allez pousser $(IMAGE_NAME):$(VERSION) et :latest$(NC)"
	@read -p "Confirmer ? [y/N] " -n 1 -r; echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		docker push $(IMAGE_NAME):$(VERSION); \
		docker push $(IMAGE_NAME):latest; \
		echo "$(GREEN)Push terminé$(NC)"; \
	else \
		echo "$(YELLOW)Annulé$(NC)"; \
	fi

# Règle par défaut
.DEFAULT_GOAL := help