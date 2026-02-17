#!/bin/bash
# ===================================================================
# Entrypoint pour Ansible + Supercronic - Version refactorisée
# ===================================================================
set -e
set -o pipefail

# ===================================================================
# CONSTANTES & VARIABLES GLOBALES
# ===================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'
readonly SECRETS_DIR="/secrets"
readonly REQUIREMENTS_FILE="$HOME/requirements.yml"
readonly CRONTAB_FILE="$HOME/crontab"
readonly MOTD_ERROR_FILE="/tmp/.motderror"

# ===================================================================
# FONCTIONS DE LOGGING
# ===================================================================
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
}

# ===================================================================
# FONCTIONS D'INITIALISATION
# ===================================================================
print_header() {
    log_info "========================================="
    log_info "Démarrage du conteneur Ansible"
    log_info "Hostname: $(hostname)"
    log_info "User: $(whoami) (UID: $(id -u), GID: $(id -g))"
    log_info "Date: $(date)"
    log_info "Timezone: ${TZ:-UTC}"
    log_info "========================================="
}

check_security() {
    if [ "$(id -u)" -eq 0 ]; then
        log_error "Container should NOT run as root!"
        exit 1
    fi
    log_info "✓ Running as non-root user (secure)"
}

init_secrets_tmpfs() {
    if ! mountpoint -q "$SECRETS_DIR" 2>/dev/null; then
        mkdir -p "$SECRETS_DIR"
        mount -t tmpfs -o size=10M,mode=0700 tmpfs "$SECRETS_DIR"
        log_info "✓ Tmpfs monté pour $SECRETS_DIR (RAM uniquement)"
    fi
}

load_vault_password() {
    log_info "🔓 Initialisation Vault password..."
    if [ -f /run/secrets/ansible_vault_password ]; then
        ANSIBLE_VAULT_PASSWORD=$(cat /run/secrets/ansible_vault_password)
        if [ -n "$ANSIBLE_VAULT_PASSWORD" ]; then
            log_info "✅ Vault password chargé en RAM (${ANSIBLE_VAULT_PASSWORD:0:3}...)"
            export ANSIBLE_VAULT_PASSWORD
        else
            log_warn "⚠️  Vault password vide"
        fi
    else
        log_warn "⚠️  Aucun mot de passe vault (/run/secrets/ansible_vault_password)"
    fi
}

# ===================================================================
# FONCTIONS ANSIBLE
# ===================================================================
run_passbolt_init() {
    log_info "🔓 Initialisation Passbolt via Ansible..."
    if ansible-playbook ansible/default-scripts/passbolt-init.yml \
        -e "secrets_dir=$SECRETS_DIR" 2>/dev/null; then
        log_info "✓ Passbolt initialisé"
    else
        log_warn "⚠️  Passbolt init ignoré/skippé"
    fi
}

cleanup_old_requirements() {
    log_info "🧹 Nettoyage anciens requirements..."
    local dirs=("requirements_ansible" "requirements_git")
    for dir in "${dirs[@]}"; do
        if [ -d "$HOME/$dir" ]; then
            log_info "Removing old $dir directory"
            rm -rf "$HOME/$dir"
        fi
    done
}

install_galaxy_requirements() {
    if [ -f "$REQUIREMENTS_FILE" ]; then
        log_info "Installing Ansible Galaxy requirements from: $REQUIREMENTS_FILE"
        if ansible-galaxy install --ignore-errors -r "$REQUIREMENTS_FILE"; then
            log_info "✓ Galaxy requirements installed successfully"
        else
            log_warn "⚠️  Some Galaxy requirements failed (non-fatal)"
        fi
    else
        log_info "No requirements.yml found, skipping Galaxy install"
    fi
}

# ===================================================================
# FONCTIONS SSH & GIT
# ===================================================================
init_gitlab_ssh_key() {
    if [ -f "/ansible/vaults/gitlab_deploy_key_private.vault" ]; then
        log_info "🔓 Déchiffrement GitLab deploy key..."
        ansible-vault decrypt /ansible/vaults/gitlab_deploy_key_private.vault \
            --output ~/.ssh/id_rsa
        chmod 600 ~/.ssh/id_rsa
        log_info "✓ GitLab SSH key configuré"
    fi
}

check_ssh_permissions() {
    if [ -d "$HOME/.ssh" ]; then
        log_info "🔍 Vérification SSH configuration..."
        
        local ssh_dir_perms=$(stat -c %a "$HOME/.ssh" 2>/dev/null || stat -f %Lp "$HOME/.ssh" 2>/dev/null)
        [ "$ssh_dir_perms" != "700" ] && log_warn "SSH dir perms: $ssh_dir_perms (should be 700)"
        
        for key in "$HOME/.ssh/id_"*; do
            [ -f "$key" ] && [[ ! "$key" =~ \.pub$ ]] && [[ ! "$key" =~ \.vault$ ]] || continue
            local key_perms=$(stat -c %a "$key" 2>/dev/null || stat -f %Lp "$key" 2>/dev/null)
            [ "$key_perms" != "600" ] && log_warn "SSH key $key perms: $key_perms (should be 600)"
        done
        
        log_info "✓ SSH configuration checked"
    fi
}

# ===================================================================
# FONCTIONS SUPERVISION
# ===================================================================
start_supercronic() {
    if [ -f "$CRONTAB_FILE" ]; then
        log_info "Starting Supercronic with crontab: $CRONTAB_FILE"
        if supercronic -test "$CRONTAB_FILE" 2>/dev/null; then
            log_info "✓ Crontab syntax valid"
            supercronic "$CRONTAB_FILE" &
            echo $! > /tmp/supercronic.pid
            log_info "✓ Supercronic started (PID: $!)"
        else
            log_error "❌ Crontab syntax invalid: $CRONTAB_FILE"
        fi
    else
        log_warn "No crontab at $CRONTAB_FILE - Supercronic skipped"
    fi
}

# ===================================================================
# FONCTIONS UTILITAIRES
# ===================================================================
print_versions() {
    log_info "========================================="
    log_info "Installed versions:"
    log_info "========================================="
    
    command -v ansible >/dev/null && log_info "Ansible: $(ansible --version | head -1)"
    command -v python3 >/dev/null && log_info "Python: $(python3 --version)"
    command -v passbolt >/dev/null && log_info "Passbolt: $(passbolt --version 2>/dev/null || echo 'N/A')"
    command -v git >/dev/null && log_info "Git: $(git --version)"
    log_info "========================================="
}

show_motd() {
    if [ -f "$MOTD_ERROR_FILE" ]; then
        cat "$MOTD_ERROR_FILE"
    elif [ -f "$HOME/.motd" ]; then
        cat "$HOME/.motd"
    fi
}

cleanup() {
    log_info "========================================="
    log_info "Shutting down gracefully..."
    
    if [ -f /tmp/supercronic.pid ]; then
        local pid=$(cat /tmp/supercronic.pid)
        if ps -p "$pid" >/dev/null 2>&1; then
            log_info "Stopping Supercronic (PID: $pid)..."
            kill -TERM "$pid" 2>/dev/null || true
            for i in {1..5}; do
                ! ps -p "$pid" >/dev/null 2>&1 && break
                sleep 1
            done
        fi
        rm -f /tmp/supercronic.pid
    fi
    
    find "$HOME/.ansible/tmp" -type f -mtime +1 -delete 2>/dev/null || true
    log_info "✓ Cleanup complete"
}

# ===================================================================
# MAIN INITIALIZATION
# ===================================================================
main_init() {
    print_header
    check_security
    init_secrets_tmpfs
    load_vault_password
    run_passbolt_init
    cleanup_old_requirements
    install_galaxy_requirements
    init_gitlab_ssh_key
    check_ssh_permissions
    print_versions
    start_supercronic
    show_motd
}

# ===================================================================
# COMMAND HANDLER (pour ansible-vault, etc.)
# ===================================================================
handle_ansible_vault() {
    log_info "🔐 Mode Ansible Vault détecté: $*"
    print_header
    check_security
    init_secrets_tmpfs
    exec "$@"
}

# ===================================================================
# ENTRYPOINT LOGIC
# ===================================================================
trap cleanup EXIT SIGTERM SIGINT

if [ "${1}" = "ansible-vault" ]; then
    handle_ansible_vault "$@"
elif [ $# -eq 0 ]; then
    main_init
    exec bash
else
    main_init
    log_info "Starting main process: $*"
    exec "$@"
fi
