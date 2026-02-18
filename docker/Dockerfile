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
# ===================================================================
ARG ALPINE_VERSION=3.22
ARG PYTHON_VERSION=3.11
ARG PASSBOLT_CLI_VERSION=0.4.1
ARG SUPERCRONIC_VERSION=v0.2.29
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
ARG ALPINE_VERSION PYTHON_VERSION PASSBOLT_CLI_VERSION SUPERCRONIC_VERSION \
      DEVOPS_UID DEVOPS_GID DEVOPS_GROUP DEVOPS_USER


ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

SHELL ["/bin/ash", "-euxo", "pipefail", "-c"]
# Installation des dépendances de build
RUN apk add --no-cache \
    shadow=4.17.3-r0 \
    python3=3.12.12-r0 \
    py3-pip=25.1.1-r0 \
    py3-cryptography=44.0.3-r0 \
    py3-cffi=1.17.1-r1 \
    bash=5.2.37-r0 \
    su-exec=0.2-r3 \
    tini=0.19.0-r3 \
    tzdata=2025c-r0 \
    ca-certificates=20250911-r0 \
    && rm -rf /var/cache/apk/*

RUN apk add --no-cache \
    # gcc \
    python3-dev=3.12.12-r0 \
    libffi-dev=3.4.8-r0 \
    openssl-dev=3.5.5-r0 \
    curl=8.14.1-r2 \
    wget=1.25.0-r1 \
    tar=1.35-r3 \
    git=2.49.1-r0 \
    openssh-client-default=10.0_p1-r10 \
    rsync=3.4.1-r1 \
    jq=1.8.1-r0 \
    gettext=0.24.1-r0 \
    gnupg=2.4.9-r0 \
    gnupg-dirmngr=2.4.9-r0

# Détecter Python version dynamiquement
RUN PY_VER=$(python3 -c "import sys; print(f'{sys.version_info[0]}.{sys.version_info[1]}')") && \
    echo "Python ${PY_VER} détecté" && \
    export PY_VER

# Création utilisateur/groupe (sécurisée)
RUN set -e && \
    echo "Vérification du groupe ${DEVOPS_GROUP} (GID: ${DEVOPS_GID})" && \
    if ! getent group "${DEVOPS_GID}" >/dev/null; then \
        addgroup -g "${DEVOPS_GID}" "${DEVOPS_GROUP}"; \
    fi && \
    DEVOPS_GROUP_REAL=$(getent group "${DEVOPS_GID}" | cut -d: -f1) && \
    if ! getent passwd "${DEVOPS_UID}" >/dev/null; then \
        adduser -u "${DEVOPS_UID}" \
                -G "${DEVOPS_GROUP_REAL}" \
                -D -s /bin/bash \
                -h "/home/${DEVOPS_USER}" \
                "${DEVOPS_USER}"; \
    fi && \
    mkdir -p "/home/${DEVOPS_USER}/.ansible" && \
    chown -R "${DEVOPS_UID}:${DEVOPS_GID}" "/home/${DEVOPS_USER}" && \
    chmod 755 "/home/${DEVOPS_USER}"

# Installation Supercronic (version épinglée)
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
    wget -q "https://github.com/passbolt/go-passbolt-cli/releases/download/v${PASSBOLT_CLI_VERSION}/go-passbolt-cli_${PASSBOLT_CLI_VERSION}_${PASSBOLT_ARCH}.tar.gz" -O /tmp/passbolt.tar.gz && \
    tar -xzf /tmp/passbolt.tar.gz -C /tmp && \
    mv /tmp/passbolt /usr/local/bin/passbolt && \
    chmod +x /usr/local/bin/passbolt && \
    rm -rf /tmp/passbolt* && \
    passbolt --version

# Installation des dépendances Python
COPY docker/python_requirements.txt /tmp/requirements.txt

RUN pip install --break-system-packages --no-cache-dir -r /tmp/requirements.txt && \
    PY_VER=$(python3 -c "import sys; print(f'{sys.version_info[0]}.{sys.version_info[1]}')") && \
    find "/usr/lib/python${PY_VER}" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true && \
    find "/usr/lib/python${PY_VER}" -name "*.pyc" -delete && \
    rm /tmp/requirements.txt

# ────────────────────────────────────────────────
# ÉTAPE 2 : IMAGE FINALE (Runtime minimal)
# ────────────────────────────────────────────────
FROM alpine:${ALPINE_VERSION}

ARG VERSION ALPINE_VERSION DEVOPS_UID DEVOPS_GID DEVOPS_GROUP DEVOPS_USER BUILD_DATE VCS_REF

# Métadonnées OCI + Security Labels
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
      slsa.ver="1.0.0" \
      slsa.workflow.ref="refs/heads/main"

SHELL ["/bin/ash", "-euxo", "pipefail", "-c"]
# Installation des packages runtime UNIQUEMENT
RUN apk add --no-cache \
    python3=3.12.12-r0 \
    py3-pip=25.1.1-r0 \
    py3-cryptography=44.0.3-r0 \
    py3-cffi=1.17.1-r1 \
    bash=5.2.37-r0 \
    su-exec=0.2-r3 \
    curl=8.14.1-r2 \
    git=2.49.1-r0 \
    openssh-client-default=10.0_p1-r10 \
    rsync=3.4.1-r1 \
    tzdata=2025c-r0 \
    jq=1.8.1-r0 \
    gettext=0.24.1-r0 \
    tini=0.19.0-r3 \
    procps-ng=4.0.4-r3 \
    gnupg=2.4.9-r0 \
    gnupg-dirmngr=2.4.9-r0 \
    ansible=11.6.0-r0 \
    ca-certificates=20250911-r0 \
    && rm -rf /var/cache/apk/* && \
    echo "Vérification du groupe ${DEVOPS_GROUP} (GID: ${DEVOPS_GID})" && \
    if ! getent group "${DEVOPS_GID}" >/dev/null; then \
        addgroup -g "${DEVOPS_GID}" "${DEVOPS_GROUP}"; \
    fi && \
    DEVOPS_GROUP_REAL=$(getent group "${DEVOPS_GID}" | cut -d: -f1) && \
    if ! getent passwd "${DEVOPS_UID}" >/dev/null; then \
        adduser -u "${DEVOPS_UID}" \
                -G "${DEVOPS_GROUP_REAL}" \
                -D -s /bin/bash \
                -h "/home/${DEVOPS_USER}" \
                "${DEVOPS_USER}"; \
    fi && \
    mkdir -p "/home/${DEVOPS_USER}/.ansible" && \
    chown -R "${DEVOPS_UID}:${DEVOPS_GID}" "/home/${DEVOPS_USER}" && \
    chmod 755 "/home/${DEVOPS_USER}"
#    DEVOPS_USER_REAL=$(getent passwd "${DEVOPS_UID}" | cut -d: -f1) && \
# Copie depuis le builder
COPY --from=builder /usr/lib/python* /usr/lib/python*
COPY --from=builder /usr/local/bin/ansible* /usr/local/bin/

RUN ln -s /usr/local/bin/ansible* /usr/bin/ansible* 2>/dev/null || true

COPY --from=builder /usr/local/bin/supercronic /usr/local/bin/
COPY --from=builder /usr/local/bin/passbolt /usr/local/bin/

# Créer les répertoires Ansible
RUN mkdir -p /etc/ansible \
            "/home/${DEVOPS_USER}/ansible/{playbooks,inventories,roles,group_vars,host_vars,library,filter_plugins}" \
            "/home/${DEVOPS_USER}/.ansible/tmp" \
            "/home/${DEVOPS_USER}/.ansible/collections" \
            "/home/${DEVOPS_USER}/.ansible/roles" \
            "/home/${DEVOPS_USER}/.cache" && \
    chown -R "${DEVOPS_UID}:${DEVOPS_GID}" "/home/${DEVOPS_USER}" \
            "/home/${DEVOPS_USER}/.ansible" \
            "/home/${DEVOPS_USER}/.cache" && \
    chmod -R 755 "/home/${DEVOPS_USER}/.ansible"

COPY --chown=${DEVOPS_UID}:${DEVOPS_GID} docker/config/ansible.cfg /etc/ansible/ansible.cfg
COPY --chown=${DEVOPS_UID}:${DEVOPS_GID} docker/ansible_requirements.yml "/home/${DEVOPS_USER}/requirements.yml"

RUN echo "[local]" > /etc/ansible/hosts && \
    echo "localhost ansible_connection=local" >> /etc/ansible/hosts && \
    chmod 644 /etc/ansible/hosts

# Configuration Cron
COPY --chown=${DEVOPS_UID}:${DEVOPS_GID} docker/config/crontab.example "/home/${DEVOPS_USER}/crontab"
RUN chmod 600 "/home/${DEVOPS_USER}/crontab"

# Scripts
COPY docker/scripts/entrypoint.sh /entrypoint.sh
COPY docker/scripts/healthcheck.sh /usr/local/bin/healthcheck.sh
COPY docker/scripts/passbolt-init.sh /usr/local/bin/passbolt-init.sh
RUN chmod 755 /usr/local/bin/passbolt-init.sh \
      /usr/local/bin/healthcheck.sh \
      /entrypoint.sh && \
    # Configuration Passbolt
    mkdir -p /etc/passbolt \
      "/home/${DEVOPS_USER}/.config/passbolt" \
      "/home/${DEVOPS_USER}/.gnupg" && \
    chown -R "${DEVOPS_UID}:${DEVOPS_GID}" /etc/passbolt \ 
      "/home/${DEVOPS_USER}/.config" "/home/${DEVOPS_USER}/.gnupg" && \
    chmod 700 "/home/${DEVOPS_USER}/.gnupg" && \
    # Configuration ssh
    mkdir -p "/home/${DEVOPS_USER}/.ssh" && \
    chown -R "${DEVOPS_UID}:${DEVOPS_GID}" "/home/${DEVOPS_USER}/.ssh" && \
    chmod 700 "/home/${DEVOPS_USER}/.ssh" && \
    # Sécurité finale
    mkdir -p /tmp && chmod 1777 /tmp && \
    rm -f /etc/shadow- /etc/passwd- /etc/group-

# Healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD su-exec "${DEVOPS_USER}":/usr/local/bin/healthcheck.sh || exit 1

# Passer à l'utilisateur non-root
USER "${DEVOPS_UID}:${DEVOPS_GID}"

ENV DEVOPS_USER="${DEVOPS_USER}" \
    DEVOPS_UID="${DEVOPS_UID}" \
    DEVOPS_GID="${DEVOPS_GID}" \
    HOME="/home/${DEVOPS_USER}" \
    ANSIBLE_FORCE_COLOR=true \
    ANSIBLE_NOCOWS=1

# Installation des collections et rôles Ansible (décommenté et corrigé)
USER root
COPY docker/ansible_requirements.yml /tmp/ansible_requirements.yml

RUN set -eux && \
    su-exec "${DEVOPS_USER}" ansible-galaxy install -r /tmp/ansible_requirements.yml && \
    rm -f /tmp/ansible_requirements.yml && \
    find "/home/${DEVOPS_USER}/.ansible" -type f -name "*.pyc" -delete 2>/dev/null || : && \
    # Optionnel : supprime aussi les dossiers __pycache__ (très fréquent avec ansible)
    find "/home/${DEVOPS_USER}/.ansible" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || :
USER "${DEVOPS_UID}:${DEVOPS_GID}"

WORKDIR "/home/${DEVOPS_USER}"

VOLUME ["/home/${DEVOPS_USER}/ansible", "/home/${DEVOPS_USER}/.ansible"]

ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]

CMD ["sleep", "infinity"]
