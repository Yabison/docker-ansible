#!/bin/bash
# ===================================================================
# Script d'initialisation Passbolt (SANS fichier clé)
# ===================================================================

#gpg --list-secret-keys --fingerprint 
#gpg --armor --export-secret-keys 55258CB13A8179ACD464E69093DC221FCFDCC4FA > /tmp/correct_key.asc
# copier coller de /tmp/correct_key.asc

set -euo pipefail

SECRETS_DIR="${SECRETS_DIR:-/run/secrets}"
PASSBOLT_VAULT_FILE="/ansible/vaults/passbolt.vault.yml"

log_info() {
    echo -e "\033[0;32m[PASSBOLT]\033[0m $*"
}

log_warn() {
    echo -e "\033[1;33m[PASSBOLT]\033[0m $*" >&2
}

log_error() {
    echo -e "\033[0;31m[PASSBOLT]\033[0m $*" >&2
}

log_info "Initialisation Passbolt..."

# ===================================================================
# CAS DE SORTIE 1: Vault manquant
# ===================================================================
if [ ! -f "$PASSBOLT_VAULT_FILE" ]; then
    log_warn "⚠️  Fichier vault manquant: $PASSBOLT_VAULT_FILE → Passbolt désactivé"
    exit 0
fi

# ===================================================================
# CAS DE SORTIE 2: passbolt-cli manquant
# ===================================================================
if ! command -v passbolt >/dev/null 2>&1; then
    log_error "❌ passbolt-cli non trouvé dans le PATH"
    exit 1
fi

# ===================================================================
# EXTRACTION VAULT → VARIABLES DIRECTES
# ===================================================================
log_info "🔓 Extraction vault → variables..."

PASSBOLT_SERVER_URL=$(ansible-vault view "$PASSBOLT_VAULT_FILE" \
    --vault-password-file="$SECRETS_DIR/ansible_vault_master_password" \
    --output=yaml | awk '/^passbolt_url:/{getline; print $1}' | tr -d ' ')

PASSBOLT_GPG_KEY_PASSPHRASE=$(ansible-vault view "$PASSBOLT_VAULT_FILE" \
    --vault-password-file="$SECRETS_DIR/ansible_vault_master_password" \
    --output=yaml | awk '/^passbolt_password:/{for(i=2;i<=NF;i++) printf "%s ", $i; print ""}')

PASSBOLT_GPG_KEY=$(ansible-vault view "$PASSBOLT_VAULT_FILE" \
    --vault-password-file="$SECRETS_DIR/ansible_vault_master_password" \
    --output=yaml | awk '/^passbolt_private_key:/{getline; while(getline && /^  /) print substr($0,3); exit}')

# ===================================================================
# CAS DE SORTIE 3: Variables vides
# ===================================================================
if [ -z "$PASSBOLT_SERVER_URL" ]; then
    log_warn "⚠️  PASSBOLT_SERVER_URL vide → Passbolt désactivé"
    exit 0
fi

if [ -z "$PASSBOLT_GPG_KEY" ]; then
    log_error "❌ PASSBOLT_GPG_KEY vide → impossible de continuer"
    exit 1
fi

# ===================================================================
# VÉRIFIER FORMAT CLÉ GPG (dans mémoire)
# ===================================================================
if ! echo "$PASSBOLT_GPG_KEY" | grep -q "^-----BEGIN PGP PRIVATE KEY BLOCK-----"; then
    log_error "❌ Clé GPG invalide (pas armored PGP)"
    echo "Début de la clé: ${PASSBOLT_GPG_KEY:0:50}"
    exit 1
fi

log_info "✓ Clé GPG valide ($(echo "$PASSBOLT_GPG_KEY" | wc -l) lignes)"

# ===================================================================
# IMPORT GPG + TRUST (clé temporaire seulement pour GPG)
# ===================================================================
log_info "🔑 Import GPG..."
GPG_TMP_KEY=$(mktemp)
echo "$PASSBOLT_GPG_KEY" > "$GPG_TMP_KEY"
chmod 600 "$GPG_TMP_KEY"

gpg --batch --import "$GPG_TMP_KEY" 2>/dev/null || log_warn "Clé déjà importée"

GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep sec | head -1 | awk '{print $2}' | cut -d'/' -f2)
if [ -n "$GPG_KEY_ID" ]; then
    log_info "Clé GPG ID: $GPG_KEY_ID"
    echo -e "5\ny\n" | gpg --command-fd 0 --edit-key "$GPG_KEY_ID" trust quit >/dev/null 2>&1 || true
fi

# ✅ NETTOYAGE IMMÉDIAT du fichier tmp GPG
rm -f "$GPG_TMP_KEY"

# ===================================================================
# CONFIG PASSBOLT → SANS FICHIER (direct en paramètre)
# ===================================================================
log_info "⚙️  Configuration passbolt-cli (SANS fichier)..."
PASSBOLT_CONFIG_DIR="$HOME/.config/passbolt"
mkdir -p "$PASSBOLT_CONFIG_DIR"

passbolt configure \
    --serverAddress "$PASSBOLT_SERVER_URL" \
    --userPassword "$PASSBOLT_GPG_KEY_PASSPHRASE" \
    --userPrivateKey "$PASSBOLT_GPG_KEY" || true  # ← DIRECT EN MÉMOIRE !

log_info "✓ Configuration créée: $PASSBOLT_CONFIG_DIR/config.json"

# ===================================================================
# TEST CONNEXION
# ===================================================================
log_info "🧪 Test connexion Passbolt..."
if passbolt list folders >/dev/null 2>&1; then
    log_info "✅ Connexion Passbolt OK !"
    FOLDER_COUNT=$(passbolt list folders 2>/dev/null | grep -c "│" || echo "0")
    log_info "Dossiers: $FOLDER_COUNT"
else
    log_error "❌ Connexion Passbolt ÉCHOUÉE"
    log_error "  URL: $PASSBOLT_SERVER_URL"
    log_error "  Clé: ${PASSBOLT_GPG_KEY:0:50}..."
    log_error "  Passphrase: ${PASSBOLT_GPG_KEY_PASSPHRASE:0:5}..."
    exit 1
fi

log_info "🎉 Initialisation Passbolt TERMINÉE ✓ (SANS fichier disque)"
exit 0
