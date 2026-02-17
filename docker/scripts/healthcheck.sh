#!/bin/sh
# ===================================================================
# Healthcheck pour conteneur Ansible + Supercronic
# ===================================================================

set -e

# Vérifier qu'Ansible est disponible
if ! command -v ansible >/dev/null 2>&1; then
    echo "ERROR: Ansible command not found"
    exit 1
fi

# Vérifier qu'Ansible fonctionne
if ! ansible --version >/dev/null 2>&1; then
    echo "ERROR: Ansible version check failed"
    exit 1
fi

# Vérifier que Supercronic tourne (si crontab existe)
if [ -f "$HOME/crontab" ]; then
    if ! pgrep -f "supercronic" >/dev/null 2>&1; then
        echo "ERROR: Supercronic process not running (but crontab exists)"
        exit 1
    fi
fi

# Vérifier que Python est disponible
if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: Python3 not found"
    exit 1
fi

# Tout est OK
echo "OK: All checks passed"
exit 0
