# ===================================================================
# DOCKERFILE ANSIBLE - Alpine Hardened MULTI-STAGE (IMPROVED)
# ===================================================================
# 
# Améliorations de sécurité:
#   ✅ Multi-stage optimisé
#   ✅ Utilisateur non-root strict
#   ✅ Permissions minimales
#   ✅ Healthcheck amélioré
#   ✅ Nettoyage agressif
#   ✅ Versions épinglées
#   ✅ Security labels
#
# Auteur: Yabison (improved)
# Version: 2.1.0
# ===================================================================# ARG globales (portables)

ARG ALPINE_VERSION=3.22
ARG PYTHON_VERSION=3.12
ARG DEVOPS_UID=1000
ARG DEVOPS_GID=1000
ARG DEVOPS_GROUP=devops
ARG DEVOPS_USER=devops
# ────────────────────────────────────────────────
# ÉTAPE 1 : BUILDER
# ────────────────────────────────────────────────
FROM alpine:${ALPINE_VERSION} AS builder

ARG VERSION=2.1.0
ARG BUILD_DATE
ARG VCS_REF
ARG ALPINE_VERSION PYTHON_VERSION DEVOPS_UID DEVOPS_GID DEVOPS_GROUP DEVOPS_USER

ARG PASSBOLT_CLI_VERSION="0.4.1"
ARG SUPERCRONIC_VERSION="v0.2.29"
# ENV pour pip/ansible
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    ANSIBLE_HOST_KEY_CHECKING=False


# ===================================================================
# Installation des dépendances de build
# ===================================================================
# Layer 1: Base système + Python (stable)
RUN apk add --no-cache \
    # User management
    shadow \
    # Python minimal
    python3 \
    py3-pip \
    py3-cryptography \
    py3-cffi \
    # Runtime tools essentiels
    bash \
    su-exec \
    tini \
    tzdata \
    ca-certificates \
    && rm -rf /var/cache/apk/*
 # Layer 2: Build tools (changent souvent)
RUN apk add --no-cache \
    gcc \
    python3-dev \
    libffi-dev \
    openssl-dev \
    curl \
    wget \
    tar \
    git \
    openssh-client \  
    rsync \
    jq \
    gettext \
    gnupg \
    gnupg-dirmngr
   
# Détecter Python version dynamiquement
RUN PY_VER=$(python3 -c "import sys; print(f'{sys.version_info[0]}.{sys.version_info[1]}')") && \
    echo "Python ${PY_VER} détecté" && \
    export PY_VER

# User sécurisé (early)
# ===================================================================
# Création utilisateur/groupe (sécurisée)
# ===================================================================
# RUN set -euo pipefail && \
#     echo "==============================================================" && \
#     echo "DEBUG: Vérification du groupe '${DEVOPS_GROUP}' (GID: ${DEVOPS_GID})" && \
#     echo "==============================================================" && \
#     getent group "${DEVOPS_GID}" && echo "→ Groupe existe déjà" || echo "→ Groupe n'existe pas encore" && \
#     echo "" && \
#     id || echo "→ Pas d'utilisateur courant détectable" && \
#     echo "=============================================================="

RUN set -e && \
    # Créer le groupe s'il n'existe pas
    echo "Vérification du groupe ${DEVOPS_GROUP} (GID: ${DEVOPS_GID})" && \
    if ! getent group "${DEVOPS_GID}" >/dev/null; then \
        addgroup -g "${DEVOPS_GID}" "${DEVOPS_GROUP}"; \
    fi && \
    DEVOPS_GROUP_REAL=$(getent group "${DEVOPS_GID}" | cut -d: -f1) && \
    # Créer l'utilisateur s'il n'existe pas
    if ! getent passwd "${DEVOPS_UID}" >/dev/null; then \
        adduser -u "${DEVOPS_UID}" \
                -G "${DEVOPS_GROUP_REAL}" \
                -D -s /bin/bash \
                -h /home/${DEVOPS_USER} \
                "${DEVOPS_USER}"; \
    fi && \
    DEVOPS_USER_REAL=$(getent passwd "${DEVOPS_UID}" | cut -d: -f1) && \
    # Créer le home directory avec bonnes permissions
    mkdir -p /home/${DEVOPS_USER}/.ansible && \
    chown -R "${DEVOPS_UID}:${DEVOPS_GID}" /home/${DEVOPS_USER} && \
    chmod 755 /home/${DEVOPS_USER}

# ===================================================================
# Installation Supercronic (version épinglée)
# ===================================================================
RUN set -ex && \
    ARCH=$(uname -m) && \
    case ${ARCH} in \
        x86_64) SUPERCRONIC_ARCH="amd64" ;; \
        aarch64) SUPERCRONIC_ARCH="arm64" ;; \
        armv7l) SUPERCRONIC_ARCH="arm" ;; \
        *) echo "Architecture non supportée: ${ARCH}" && exit 1 ;; \
    esac && \
    SUPERCRONIC_URL="https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-${SUPERCRONIC_ARCH}" && \
    wget -qO /usr/local/bin/supercronic "${SUPERCRONIC_URL}" && \
    chmod +x /usr/local/bin/supercronic && \
    case ${ARCH} in \
        x86_64) PASSBOLT_ARCH="linux_amd64" ;; \
        aarch64) PASSBOLT_ARCH="linux_arm64" ;; \
        *) echo "Architecture non supportée: ${ARCH}" && exit 1 ;; \
    esac && \
    wget -q https://github.com/passbolt/go-passbolt-cli/releases/download/v${PASSBOLT_CLI_VERSION}/go-passbolt-cli_${PASSBOLT_CLI_VERSION}_${PASSBOLT_ARCH}.tar.gz -O /tmp/passbolt.tar.gz && \
    tar -xzf /tmp/passbolt.tar.gz -C /tmp && \
    mv /tmp/passbolt /usr/local/bin/passbolt && \
    chmod +x /usr/local/bin/passbolt && \
    rm -rf /tmp/passbolt* && \
    passbolt --version
# ===================================================================
# Installation des dépendances Python
# ===================================================================
COPY docker/python_requirements.txt /tmp/requirements.txt

RUN pip install --break-system-packages --no-cache-dir -r /tmp/requirements.txt && \
    PY_VER=$(python3 -c "import sys; print(f'{sys.version_info[0]}.{sys.version_info[1]}')") && \
    find /usr/lib/python${PY_VER} -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true && \
    find /usr/lib/python${PY_VER} -name "*.pyc" -delete && \
    rm /tmp/requirements.txt


# ===================================================================
# Installation des collections et rôles Ansible
# # ===================================================================
# COPY docker/ansible_requirements.yml /tmp/ansible_requirements.yml

# USER "${DEVOPS_UID}:${DEVOPS_GID}"

# RUN  su-exec ${DEVOPS_USER} ansible-galaxy  install -r /tmp/ansible_requirements.yml && \
#     rm /tmp/ansible_requirements.yml && \
#     # Nettoyer les caches Ansible
#     find home/${DEVOPS_USER}/.ansible -type f -name "*.pyc" -delete 2>/dev/null || true

# ────────────────────────────────────────────────
# ÉTAPE 2 : IMAGE FINALE (Runtime minimal)
# ────────────────────────────────────────────────
FROM alpine:3.19

ARG VERSION ALPINE_VERSION DEVOPS_UID DEVOPS_GID DEVOPS_GROUP DEVOPS_USER BUILD_DATE VCS_REF


# ===================================================================
# Métadonnées OCI + Security Labels
# ===================================================================
LABEL org.opencontainers.image.title="Ansible + Supercronic (Alpine Hardened)" \
      org.opencontainers.image.description="Ansible avec cron non-root - Alpine multi-stage hardened" \
      org.opencontainers.image.vendor="Yabison" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.authors="Herve Tamet <herve.tamet@yabison.com>" \
      org.opencontainers.image.url="https://yabison.com" \
      org.opencontainers.image.documentation="https://github.com/Yabison/ansible-docker" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.base.name="alpine:3.19" \
      security.non-root="true" \
      security.tini="true" \
      security.multi-stage="true" \     
      # SLSA
      slsa.ver="1.0.0" \
      slsa.github.com/workflow/ref="refs/heads/main"



# ===================================================================
# Installation des packages runtime UNIQUEMENT
# ===================================================================
RUN apk add --no-cache \
    # Python runtime (pas de dev)
    python3 \
    py3-pip \
    py3-cryptography \
    py3-cffi \
    # Outils essentiels
    bash \
    su-exec \
    curl \
    git \
    openssh-client \
    rsync \
    # Système
    tzdata \
    jq \
    gettext \
    su-exec \
    tini \
    # Pour healthcheck
    procps \
    # GPG pour le chiffrement
    gnupg \
    gnupg-dirmngr \
    ansible \
    # Pour passbolt-cli (Go binary - pas de dépendances PHP nécessaires)
    ca-certificates \
    && rm -rf /var/cache/apk/*

# COPY docker/python_requirements.txt /tmp/requirements.txt
# RUN pip install --break-system-packages --no-cache-dir -r /tmp/requirements.txt && \
#     PY_VER=$(python3 -c "import sys; print(f'{sys.version_info[0]}.{sys.version_info[1]}')") && \
#     find /usr/lib/python${PY_VER} -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true && \
#     find /usr/lib/python${PY_VER} -name "*.pyc" -delete && \
#     rm /tmp/requirements.txt


RUN set -e && \
    # Créer le groupe s'il n'existe pas
    echo "Vérification du groupe ${DEVOPS_GROUP} (GID: ${DEVOPS_GID})" && \
    if ! getent group "${DEVOPS_GID}" >/dev/null; then \
        addgroup -g "${DEVOPS_GID}" "${DEVOPS_GROUP}"; \
    fi && \
    DEVOPS_GROUP_REAL=$(getent group "${DEVOPS_GID}" | cut -d: -f1) && \
    # Créer l'utilisateur s'il n'existe pas
    if ! getent passwd "${DEVOPS_UID}" >/dev/null; then \
        adduser -u "${DEVOPS_UID}" \
                -G "${DEVOPS_GROUP_REAL}" \
                -D -s /bin/bash \
                -h /home/${DEVOPS_USER} \
                "${DEVOPS_USER}"; \
    fi && \
    DEVOPS_USER_REAL=$(getent passwd "${DEVOPS_UID}" | cut -d: -f1) && \
    # Créer le home directory avec bonnes permissions
    mkdir -p /home/${DEVOPS_USER}/.ansible && \
    chown -R "${DEVOPS_UID}:${DEVOPS_GID}" /home/${DEVOPS_USER} && \
    chmod 755 /home/${DEVOPS_USER}
# ===================================================================
# Copie depuis le builder
# ===================================================================

# Copier utilisateur/groupe
# COPY --from=builder /etc/passwd /etc/group /etc/shadow /etc/

# Copier home directory
#COPY --from=builder --chown=${DEVOPS_UID}:${DEVOPS_GID} /home/${DEVOPS_USER} /home/${DEVOPS_USER}

# Copier Python packages
COPY --from=builder /usr/lib/python* /usr/lib/python*
# Copier binaires Ansible
#COPY --from=builder /usr/bin/ansible* /usr/bin/
COPY --from=builder /usr/local/bin/ansible* /usr/local/bin/

# Créer des symlinks dans /usr/bin pour compatibilité
RUN ln -s /usr/local/bin/ansible* /usr/bin/ansible* 2>/dev/null || true

# Copier supercronic & passbolt
COPY --from=builder /usr/local/bin/supercronic /usr/local/bin/
COPY --from=builder /usr/local/bin/passbolt /usr/local/bin/



# Copier collections et rôles Ansible
# COPY --from=builder /root/.ansible /root/.ansible

# ===================================================================
# Configuration Ansible
# ===================================================================

# Créer les répertoires Ansible
RUN mkdir -p /etc/ansible \
            /home/${DEVOPS_USER}/ansible/{playbooks,inventories,roles,group_vars,host_vars,library,filter_plugins} \
            /home/${DEVOPS_USER}/.ansible/tmp  \
            /home/${DEVOPS_USER}/.ansible/collections  \
            /home/${DEVOPS_USER}/.ansible/roles \
             /home/${DEVOPS_USER}/.cache && \
    chown -R ${DEVOPS_UID}:${DEVOPS_GID} /home/${DEVOPS_USER} \
      /home/${DEVOPS_USER}/.ansible \
      /home/${DEVOPS_USER}/.cache && \
    chmod -R 755 /home/${DEVOPS_USER}/.ansible/ 

# Copier la configuration Ansible
COPY --chown=${DEVOPS_UID}:${DEVOPS_GID} docker/config/ansible.cfg /etc/ansible/ansible.cfg
COPY --chown=${DEVOPS_UID}:${DEVOPS_GID} docker/ansible_requirements.yml /home/${DEVOPS_USER}/requirements.yml


# Créer un inventaire par défaut
RUN echo "[local]" > /etc/ansible/hosts && \
    echo "localhost ansible_connection=local" >> /etc/ansible/hosts && \
    chmod 644 /etc/ansible/hosts

# ===================================================================
# Configuration Cron
# ===================================================================

# Copier le crontab (avec permissions strictes)
COPY --chown=${DEVOPS_UID}:${DEVOPS_GID} docker/config/crontab.example /home/${DEVOPS_USER}/crontab
RUN chmod 600 /home/${DEVOPS_USER}/crontab

# ===================================================================
# Scripts
# ===================================================================

# Copier l'entrypoint
COPY docker/scripts/entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh && \
    # Vérifier la syntaxe bash
    bash -n /entrypoint.sh

# Script healthcheck
COPY docker/scripts/healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod 755 /usr/local/bin/healthcheck.sh


# ===================================================================
# Installation du lookup plugin Ansible pour Passbolt
# ===================================================================

#RUN mkdir -p /home/${DEVOPS_USER}/.ansible/plugins/lookup && \
#    chown -R ${DEVOPS_UID}:${DEVOPS_GID} /home/${DEVOPS_USER}/.ansible

#COPY docker/plugins/passbolt.py /home/${DEVOPS_USER}/.ansible/plugins/lookup/passbolt.py
#RUN chown ${DEVOPS_UID}:${DEVOPS_GID} /home/${DEVOPS_USER}/.ansible/plugins/lookup/passbolt.py

# ===================================================================
# Scripts Passbolt
# ===================================================================

COPY docker/scripts/passbolt-init.sh /usr/local/bin/passbolt-init.sh
RUN chmod 755 /usr/local/bin/passbolt-init.sh

# ===================================================================
# Configuration Passbolt
# ===================================================================

# Créer les répertoires de configuration
RUN mkdir -p /etc/passbolt \
             /home/${DEVOPS_USER}/.config/passbolt \
             /home/${DEVOPS_USER}/.gnupg && \
    chown -R ${DEVOPS_UID}:${DEVOPS_GID} /etc/passbolt /home/${DEVOPS_USER}/.config /home/${DEVOPS_USER}/.gnupg && \
    chmod 700 /home/${DEVOPS_USER}/.gnupg

# ===================================================================
# Configuration ssh
# ===================================================================

# Créer les répertoires de configuration
RUN mkdir -p /home/${DEVOPS_USER}/.ssh && \
    chown -R ${DEVOPS_UID}:${DEVOPS_GID} /home/${DEVOPS_USER}/.ssh && \
    chmod 700 /home/${DEVOPS_USER}/.ssh

# ===================================================================
# Sécurité finale
# ===================================================================

# Créer le répertoire tmp avec sticky bit
RUN mkdir -p /tmp && chmod 1777 /tmp

# S'assurer que l'utilisateur ne peut pas élever ses privilèges
# RUN chmod 755 /usr/bin/su-exec && \
#     # Nettoyer les fichiers sensibles
#     rm -f /etc/shadow- /etc/passwd- /etc/group-

    # Nettoyer les fichiers sensibles
RUN rm -f /etc/shadow- /etc/passwd- /etc/group-

# ===================================================================
# Healthcheck
# ===================================================================
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD su-exec ${DEVOPS_USER}:/usr/local/bin/healthcheck.sh || exit 1

# ===================================================================
# Configuration finale
# ===================================================================



# Passer à l'utilisateur non-root
USER ${DEVOPS_UID}:${DEVOPS_GID}
# Variables d'environnement utilisateur
ENV DEVOPS_USER=${DEVOPS_USER} \
    DEVOPS_UID=${DEVOPS_UID} \
    DEVOPS_GID=${DEVOPS_GID} \
    HOME=/home/${DEVOPS_USER} \
    #\
    #ANSIBLE_LOCAL_TEMP=/home/devops/.ansible/tmp \
    #ANSIBLE_REMOTE_TEMP=/tmp/.ansible/tmp
    #ANSIBLE_HOST_KEY_CHECKING=False \
    ANSIBLE_FORCE_COLOR=true \
    ANSIBLE_NOCOWS=1
    
# ===================================================================
# Installation des collections et rôles Ansible
# # ===================================================================
COPY docker/ansible_requirements.yml /tmp/ansible_requirements.yml

RUN  su-exec ${DEVOPS_USER} ansible-galaxy  install -r /tmp/ansible_requirements.yml && \
    rm /tmp/ansible_requirements.yml && \
    # Nettoyer les caches Ansible
    find home/${DEVOPS_USER}/.ansible -type f -name "*.pyc" -delete 2>/dev/null || true
# Répertoire de travail
WORKDIR /home/${DEVOPS_USER}

# Volumes recommandés (documentation)
VOLUME ["/home/${DEVOPS_USER}/ansible", "/home/${DEVOPS_USER}/.ansible"]

# Point d'entrée avec tini (gestionnaire de signaux)
ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]

# Commande par défaut
# CMD ["bash"]

CMD ["sleep", "infinity"]